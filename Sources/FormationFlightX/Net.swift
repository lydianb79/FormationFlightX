import Foundation
import Network
import QuartzCore
import dnssd
import simd

// Serverless multiplayer. Every copy of the app advertises itself on the local network with Bonjour and
// looks for the others; each pilot then sends their aircraft's state straight to every other pilot over UDP.
// There is no host: whoever is there flies together, up to three. With peer-to-peer Wi-Fi enabled, two or
// three Macs find each other even without a shared access point.

/// What a pilot sends many times a second: where the aircraft is and how it is moving.
struct NetState {
    var id: UInt32 = 0
    var time: Double = 0            // sender's clock when the state was true
    var spec: UInt16 = 0            // index into the aircraft library
    var crashed = false, smoke = false
    var pos = V3.zero, vel = V3.zero, omega = V3.zero, servo = V3.zero
    var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var level: Float = 0            // motor speed
}

/// Sent twice a second: who the pilot is and, from the formation lead, what everyone flies in.
struct NetHello {
    var id: UInt32 = 0
    var leadEpoch: UInt32 = 0       // the pilot with the highest number leads; taking the lead raises it
    var site: UInt16 = 0
    var formation: UInt8 = 0, spacing: UInt8 = 0, timeOfDay: UInt8 = 0
    var windSpeed: Float = 0, windFrom: Float = 0, turbulence: Float = 0, gustiness: Float = 0, thermals: Float = 0, cloud: Float = 0, haze: Float = 0
    var name = ""
    var group = ""
    var place: UInt8 = 0            // 0 in the menus, 1 in the lobby, 2 flying
}

/// A line of chat, or the lead calling everyone in the lobby into the air. Sent several times, because
/// datagrams can be lost; `seq` lets the receivers recognise the repeats.
struct NetChat {
    var id: UInt32 = 0
    var seq: UInt32 = 0
    var kind: UInt8 = 0             // 0 text, 1 "everyone take off"
    var text = ""
}

/// One 20 ms frame of speech, Opus-coded.
struct NetVoice {
    var id: UInt32 = 0
    var seq: UInt16 = 0
    var payload = Data()
}

enum NetMessage { case state(NetState), hello(NetHello), chat(NetChat), voice(NetVoice) }

private struct Writer {
    var d = Data()
    mutating func u8(_ v: UInt8) { d.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    mutating func f(_ v: Float) { u32(v.bitPattern) }
    mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
    mutating func v3(_ v: V3) { f(v.x); f(v.y); f(v.z) }
    mutating func str(_ s: String, max: Int = 40) {
        // cut at a character boundary, so a long line never ends in half a letter
        var t = s
        while t.utf8.count > max { t.removeLast() }
        u8(UInt8(t.utf8.count)); d.append(contentsOf: Array(t.utf8))
    }
}

private struct Reader {
    let d: [UInt8]
    var i = 0
    var ok = true
    init(_ data: Data) { d = [UInt8](data) }
    mutating func u8() -> UInt8 { guard i < d.count else { ok = false; return 0 }; defer { i += 1 }; return d[i] }
    mutating func u16() -> UInt16 { UInt16(u8()) | UInt16(u8()) << 8 }
    mutating func u32() -> UInt32 { var v: UInt32 = 0; for k in 0..<4 { v |= UInt32(u8()) << (8 * UInt32(k)) }; return v }
    mutating func f() -> Float { Float(bitPattern: u32()) }
    mutating func f64() -> Double { var v: UInt64 = 0; for k in 0..<8 { v |= UInt64(u8()) << (8 * UInt64(k)) }; return Double(bitPattern: v) }
    mutating func v3() -> V3 { V3(f(), f(), f()) }
    mutating func str() -> String { let n = Int(u8()); guard i + n <= d.count else { ok = false; return "" }; defer { i += n }; return String(decoding: d[i..<i + n], as: UTF8.self) }
}

enum NetCodec {
    static let magic: UInt8 = 0xF7, version: UInt8 = 2
    static let maxSize = 1200, maxChat = 240

    static func encode(_ c: NetChat) -> Data {
        var w = Writer()
        w.u8(magic); w.u8(version); w.u8(3); w.u32(c.id)
        w.u32(c.seq); w.u8(c.kind); w.str(c.text, max: maxChat)
        return w.d
    }

    static func encode(_ v: NetVoice) -> Data {
        var w = Writer()
        w.u8(magic); w.u8(version); w.u8(4); w.u32(v.id)
        w.u16(v.seq); w.d.append(v.payload)
        return w.d
    }

    static func encode(_ s: NetState) -> Data {
        var w = Writer()
        w.u8(magic); w.u8(version); w.u8(1); w.u32(s.id)
        w.f64(s.time); w.u16(s.spec); w.u8((s.crashed ? 1 : 0) | (s.smoke ? 2 : 0))
        w.v3(s.pos); w.v3(s.vel); w.v3(s.omega); w.v3(s.servo)
        w.f(s.q.imag.x); w.f(s.q.imag.y); w.f(s.q.imag.z); w.f(s.q.real); w.f(s.level)
        return w.d
    }

    static func encode(_ h: NetHello) -> Data {
        var w = Writer()
        w.u8(magic); w.u8(version); w.u8(2); w.u32(h.id)
        w.u32(h.leadEpoch); w.u16(h.site); w.u8(h.formation); w.u8(h.spacing); w.u8(h.timeOfDay)
        for v in [h.windSpeed, h.windFrom, h.turbulence, h.gustiness, h.thermals, h.cloud, h.haze] { w.f(v) }
        w.str(h.name); w.str(h.group); w.u8(h.place)
        return w.d
    }

    /// Nil for anything that is not a well-formed message of this version: the network is not trusted.
    static func decode(_ data: Data) -> NetMessage? {
        guard data.count >= 7, data.count <= maxSize else { return nil }
        var r = Reader(data)
        guard r.u8() == magic, r.u8() == version else { return nil }
        let type = r.u8(), id = r.u32()
        switch type {
        case 1:
            var s = NetState(); s.id = id
            s.time = r.f64(); s.spec = r.u16()
            let fl = r.u8(); s.crashed = fl & 1 != 0; s.smoke = fl & 2 != 0
            s.pos = r.v3(); s.vel = r.v3(); s.omega = r.v3(); s.servo = r.v3()
            let qv = r.v3(), qr = r.f()
            s.level = r.f()
            guard r.ok else { return nil }
            let all = [s.pos.x, s.pos.y, s.pos.z, s.vel.x, s.vel.y, s.vel.z, s.omega.x, s.omega.y, s.omega.z, s.servo.x, s.servo.y, s.servo.z, qv.x, qv.y, qv.z, qr, s.level]
            guard s.time.isFinite, all.allSatisfy({ $0.isFinite && abs($0) < 1e5 }) else { return nil }
            let n = sqrt(simd_length_squared(qv) + qr * qr)
            guard n > 0.5, n < 2 else { return nil }
            s.q = simd_quatf(ix: qv.x / n, iy: qv.y / n, iz: qv.z / n, r: qr / n)
            s.servo = simd_clamp(s.servo, V3(repeating: -1), V3(repeating: 1))
            s.level = clampf(s.level, 0, 1.4)
            return .state(s)
        case 2:
            var h = NetHello(); h.id = id
            h.leadEpoch = r.u32(); h.site = r.u16(); h.formation = r.u8(); h.spacing = r.u8(); h.timeOfDay = r.u8()
            h.windSpeed = r.f(); h.windFrom = r.f(); h.turbulence = r.f(); h.gustiness = r.f(); h.thermals = r.f(); h.cloud = r.f(); h.haze = r.f()
            h.name = r.str(); h.group = r.str(); h.place = min(r.u8(), 2)
            guard r.ok, [h.windSpeed, h.windFrom, h.turbulence, h.gustiness, h.thermals, h.cloud, h.haze].allSatisfy({ $0.isFinite }) else { return nil }
            h.windSpeed = clampf(h.windSpeed, 0, 20); h.windFrom = clampf(h.windFrom, 0, 360); h.turbulence = clampf(h.turbulence, 0, 1)
            h.gustiness = clampf(h.gustiness, 0, 1); h.thermals = clampf(h.thermals, 0, 2); h.cloud = clampf(h.cloud, 0, 1); h.haze = clampf(h.haze, 0, 1)
            return .hello(h)
        case 3:
            var c = NetChat(); c.id = id
            c.seq = r.u32(); c.kind = r.u8(); c.text = r.str()
            guard r.ok, c.kind <= 1 else { return nil }
            // no control characters: the text is shown as it comes
            c.text = String(c.text.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init))
            return .chat(c)
        case 4:
            var v = NetVoice(); v.id = id
            v.seq = r.u16()
            guard r.ok, data.count - r.i > 0, data.count - r.i <= 400 else { return nil }
            v.payload = data.subdata(in: data.startIndex + r.i..<data.endIndex)
            return .voice(v)
        default: return nil
        }
    }
}

/// Finds the other pilots and carries the messages. All Network.framework work happens on one private queue;
/// received messages wait in an inbox that the game empties once per frame.
///
/// Two ways of meeting:
/// - On a local network every copy advertises itself with Bonjour and sends straight to every other copy.
/// - Over the internet one pilot hosts and the others connect to the host's address. The host answers each of
///   them down the path their own packets opened through their router, and passes every pilot's messages on to
///   the others, so only the host needs a port that can be reached from outside.
final class FormationNet {
    static let serviceType = "_formflightx._udp"
    static let port: UInt16 = 47800
    let id: UInt32
    /// Off for tests that should use only the direct connection.
    var discovery = true
    private let queue = DispatchQueue(label: "formationflightx.net")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var outgoing: [String: NWConnection] = [:]      // local pilots, by the number they advertise
    private var incoming: [ObjectIdentifier: NWConnection] = [:]
    private var flowID: [ObjectIdentifier: UInt32] = [:]    // who is at the other end of each incoming flow
    private var flowSeen: [ObjectIdentifier: Double] = [:]
    private var hostLink: NWConnection?                     // this pilot's connection to an online host
    private let lock = NSLock()
    private var inbox: [(Data, Double)] = []
    private var statusText = "Off"
    private var hostSeen = 0.0, hostTarget = ""
    private var guests = 0
    private var listenPort: UInt16 = 0
    private(set) var running = false
    private let mapping = PortMapping()

    init(id: UInt32 = UInt32.random(in: 1000...UInt32.max)) { self.id = id }

    /// A short line for the menu: off, searching, or what went wrong.
    var status: String { lock.lock(); defer { lock.unlock() }; return statusText }
    private func setStatus(_ s: String) { lock.lock(); statusText = s; lock.unlock() }

    private func parameters() -> NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = true
        return p
    }

    func start() {
        guard !running else { return }
        running = true
        setStatus("Looking for other pilots…")
        queue.async { [self] in
            // the well-known port, so that a host has one number to give out; another copy on the same Mac takes any port
            var l = try? NWListener(using: parameters(), on: NWEndpoint.Port(rawValue: FormationNet.port)!)
            var fixed = l != nil
            func begin(_ l: NWListener) {
                if discovery { l.service = NWListener.Service(name: "\(id)", type: FormationNet.serviceType) }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.stateUpdateHandler = { [weak self, weak l] st in
                    guard let s = self else { return }
                    switch st {
                    case .ready:
                        s.lock.lock(); s.listenPort = l?.port?.rawValue ?? 0; s.lock.unlock()
                    case .failed(let e):
                        // the port is taken (a second copy on this Mac): listen on any port instead
                        if fixed, let any = try? NWListener(using: s.parameters()) { fixed = false; l?.cancel(); s.listener = any; begin(any) }
                        else { s.setStatus("Network unavailable (\(e.localizedDescription))") }
                    case .waiting(let e): s.setStatus("Waiting for the network (\(e.localizedDescription))")
                    default: break
                    }
                }
                l.start(queue: queue)
            }
            if l == nil { l = try? NWListener(using: parameters()); fixed = false }
            guard let made = l else { setStatus("Network unavailable"); return }
            listener = made
            begin(made)
            guard discovery else { return }
            let b = NWBrowser(for: .bonjour(type: FormationNet.serviceType, domain: nil), using: parameters())
            b.browseResultsChangedHandler = { [weak self] results, _ in self?.found(results) }
            b.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st { self?.setStatus("Cannot search the network (\(e.localizedDescription))") }
                if case .waiting = st { self?.setStatus("Allow local network access for FormationFlightX in System Settings ▸ Privacy & Security") }
                if case .ready = st { self?.setStatus("Looking for other pilots…") }
            }
            b.start(queue: queue)
            browser = b
        }
    }

    func stop() {
        guard running else { return }
        running = false
        setStatus("Off")
        mapping.close()
        queue.async { [self] in
            listener?.cancel(); listener = nil
            browser?.cancel(); browser = nil
            outgoing.values.forEach { $0.cancel() }; outgoing = [:]
            incoming.values.forEach { $0.cancel() }; incoming = [:]; flowID = [:]; flowSeen = [:]
            hostLink?.cancel(); hostLink = nil
        }
        lock.lock(); inbox = []; hostTarget = ""; guests = 0; lock.unlock()
    }

    // MARK: Online

    /// The port this copy listens on (the well-known one unless another copy on this Mac has it).
    var port: UInt16 { lock.lock(); defer { lock.unlock() }; return listenPort }

    /// Ask the router to let pilots on the internet reach this Mac, or stop asking.
    func setHosting(_ on: Bool) {
        if on { let p = port; mapping.open(port: p == 0 ? FormationNet.port : p) } else { mapping.close() }
    }
    var hosting: Bool { mapping.wanted }
    /// What the host tells the others, once the router has answered: "address:port".
    var publicAddress: String? { mapping.address }
    /// Why there is no public address, if the router has refused or does not answer.
    var hostingProblem: String? { mapping.problem }
    /// How many pilots are connected to this copy as their host.
    var guestCount: Int { lock.lock(); defer { lock.unlock() }; return guests }

    /// Connect to a host: "name-or-address" or "name-or-address:port".
    func join(_ address: String) {
        var host = address.trimmingCharacters(in: .whitespaces), port = FormationNet.port
        if host.hasPrefix("["), let end = host.firstIndex(of: "]") {                 // [IPv6]:port
            let rest = host[host.index(after: end)...]
            if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { port = p }
            host = String(host[host.index(after: host.startIndex)..<end])
        } else if host.filter({ $0 == ":" }).count == 1, let i = host.lastIndex(of: ":"), let p = UInt16(host[host.index(after: i)...]) {
            port = p; host = String(host[..<i])
        }
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        lock.lock(); hostTarget = "\(host):\(port)"; hostSeen = 0; lock.unlock()
        queue.async { [self] in
            hostLink?.cancel()
            let c = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters())
            c.stateUpdateHandler = { [weak self, weak c] st in
                guard let s = self, let c = c, s.hostLink === c else { return }
                if case .failed = st { s.hostLink = nil }
            }
            c.start(queue: queue)
            hostLink = c
            receive(c, flow: nil)
        }
    }

    func leave() {
        lock.lock(); hostTarget = ""; lock.unlock()
        queue.async { [self] in hostLink?.cancel(); hostLink = nil }
    }

    /// The host this copy is connected or connecting to, and whether the host is answering.
    var joined: (target: String, answering: Bool)? {
        lock.lock(); defer { lock.unlock() }
        return hostTarget.isEmpty ? nil : (hostTarget, CACurrentMediaTime() - hostSeen < 3)
    }

    // MARK: Local discovery

    private func found(_ results: Set<NWBrowser.Result>) {
        var seen = Set<String>()
        for r in results {
            guard case .service(let name, _, _, _) = r.endpoint, name != "\(id)" else { continue }
            seen.insert(name)
            if outgoing[name] == nil {
                let c = NWConnection(to: r.endpoint, using: parameters())
                c.stateUpdateHandler = { [weak self, weak c] st in
                    guard let s = self, let c = c else { return }
                    switch st {
                    case .failed, .cancelled: if s.outgoing[name] === c { s.outgoing[name] = nil }
                    default: break
                    }
                }
                c.start(queue: queue)
                outgoing[name] = c
            }
        }
        for (name, c) in outgoing where !seen.contains(name) { c.cancel(); outgoing[name] = nil }
    }

    // MARK: Receiving

    private func drop(_ key: ObjectIdentifier) {
        incoming[key]?.cancel()
        incoming[key] = nil; flowID[key] = nil; flowSeen[key] = nil
    }

    private func accept(_ c: NWConnection) {
        let now = CACurrentMediaTime()
        // flows that have gone quiet belong to pilots who left, or to a path that changed
        for (k, t) in flowSeen where now - t > 10 { drop(k) }
        if incoming.count > 24 { c.cancel(); return }
        let key = ObjectIdentifier(c)
        incoming[key] = c; flowSeen[key] = now
        c.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: self?.drop(key)
            default: break
            }
        }
        c.start(queue: queue)
        receive(c, flow: key)
    }

    /// Guests of this host: flows from pilots who are not reachable through local discovery.
    private func guestFlows() -> [(ObjectIdentifier, UInt32)] {
        flowID.filter { outgoing["\($0.value)"] == nil }.map { ($0.key, $0.value) }
    }

    private func receive(_ c: NWConnection, flow: ObjectIdentifier?) {
        c.receiveMessage { [weak self, weak c] data, _, _, error in
            guard let s = self, let c = c else { return }
            if let d = data, d.count >= 7, d.count <= NetCodec.maxSize, d[d.startIndex] == NetCodec.magic {
                let now = CACurrentMediaTime()
                let b = d.startIndex
                let sender = UInt32(d[b + 3]) | UInt32(d[b + 4]) << 8 | UInt32(d[b + 5]) << 16 | UInt32(d[b + 6]) << 24
                if sender != s.id {
                    s.lock.lock()
                    if s.inbox.count < 900 { s.inbox.append((d, now)) }
                    if flow == nil { s.hostSeen = now }
                    s.lock.unlock()
                    if let key = flow {
                        s.flowSeen[key] = now
                        if s.flowID[key] != sender {
                            // the same pilot on a new path replaces the old one
                            for (k, v) in s.flowID where v == sender && k != key { s.drop(k) }
                            s.flowID[key] = sender
                        }
                        // The host passes messages on: between its guests, and between guests and the pilots on
                        // its own local network, who cannot reach each other.
                        let guests = s.guestFlows()
                        let fromGuest = s.outgoing["\(sender)"] == nil
                        for (k, who) in guests where who != sender { s.incoming[k]?.send(content: d, completion: .idempotent) }
                        if fromGuest { for o in s.outgoing.values where o.state == .ready { o.send(content: d, completion: .idempotent) } }
                        s.lock.lock(); s.guests = guests.count; s.lock.unlock()
                    }
                }
            }
            if error == nil { s.receive(c, flow: flow) } else if let key = flow { s.drop(key) } else { c.cancel() }
        }
    }

    // MARK: Sending

    /// Send to every pilot this copy can reach. Datagrams that cannot be delivered are simply lost; the next one replaces them.
    func broadcast(_ d: Data) {
        guard running else { return }
        queue.async { [self] in
            for c in outgoing.values where c.state == .ready { c.send(content: d, completion: .idempotent) }
            for (k, _) in guestFlows() { incoming[k]?.send(content: d, completion: .idempotent) }
            if let h = hostLink, h.state == .ready { h.send(content: d, completion: .idempotent) }
        }
    }

    /// Everything received since the last call, each with the local time it arrived.
    func drain() -> [(NetMessage, Double)] {
        lock.lock(); let raw = inbox; inbox = []; lock.unlock()
        return raw.compactMap { d, t in
            guard let m = NetCodec.decode(d) else { return nil }
            switch m {
            case .state(let s): return s.id == id ? nil : (m, t)
            case .hello(let h): return h.id == id ? nil : (m, t)
            case .chat(let c): return c.id == id ? nil : (m, t)
            case .voice(let v): return v.id == id ? nil : (m, t)
            }
        }
    }
}

/// Asks the router to forward a UDP port to this Mac (NAT-PMP, PCP or UPnP, whichever it speaks) and reports
/// the address the outside world sees. This is what lets a host be reached without setting up the router by hand.
final class PortMapping {
    private var ref: DNSServiceRef?
    private let lock = NSLock()
    private var result: String?, trouble: String?
    private(set) var wanted = false
    private var port: UInt16 = 0
    private static let queue = DispatchQueue(label: "formationflightx.portmap")

    var address: String? { lock.lock(); defer { lock.unlock() }; return result }
    var problem: String? { lock.lock(); defer { lock.unlock() }; return trouble }

    func open(port p: UInt16) {
        guard !wanted || p != port else { return }
        close()
        wanted = true; port = p
        let cb: DNSServiceNATPortMappingReply = { _, _, _, err, ext, _, _, extPort, _, ctx in
            guard let ctx = ctx else { return }
            let me = Unmanaged<PortMapping>.fromOpaque(ctx).takeUnretainedValue()
            let a = UInt32(bigEndian: ext), p = UInt16(bigEndian: extPort)
            let b = (UInt8(a >> 24), UInt8(a >> 16 & 255), UInt8(a >> 8 & 255), UInt8(a & 255))
            me.lock.lock(); defer { me.lock.unlock() }
            if err != kDNSServiceErr_NoError || a == 0 || p == 0 {
                me.result = nil
                me.trouble = err == kDNSServiceErr_DoubleNAT ? "This Mac is behind two routers; the port has to be forwarded on both by hand."
                                                             : "The router did not open the port by itself."
            } else if b.0 == 10 || (b.0 == 172 && b.1 >= 16 && b.1 < 32) || (b.0 == 192 && b.1 == 168) || (b.0 == 100 && b.1 >= 64 && b.1 < 128) {
                // the router itself has no public address: the internet provider shares one between customers
                me.result = nil
                me.trouble = "Your internet provider does not give this connection an address of its own, so it cannot host."
            } else {
                me.result = "\(b.0).\(b.1).\(b.2).\(b.3):\(p)"; me.trouble = nil
            }
        }
        var r: DNSServiceRef?
        let err = DNSServiceNATPortMappingCreate(&r, 0, 0, DNSServiceProtocol(kDNSServiceProtocol_UDP), p.bigEndian, p.bigEndian, 0, cb, Unmanaged.passUnretained(self).toOpaque())
        guard err == kDNSServiceErr_NoError, let made = r else {
            lock.lock(); trouble = "The router could not be asked to open the port."; lock.unlock(); return
        }
        ref = made
        DNSServiceSetDispatchQueue(made, PortMapping.queue)
    }

    func close() {
        wanted = false
        if let r = ref { DNSServiceRefDeallocate(r); ref = nil }
        lock.lock(); result = nil; trouble = nil; lock.unlock()
    }
}
