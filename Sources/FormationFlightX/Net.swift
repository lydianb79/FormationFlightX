import Foundation
import Network
import QuartzCore
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
}

enum NetMessage { case state(NetState), hello(NetHello) }

private struct Writer {
    var d = Data()
    mutating func u8(_ v: UInt8) { d.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    mutating func f(_ v: Float) { u32(v.bitPattern) }
    mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
    mutating func v3(_ v: V3) { f(v.x); f(v.y); f(v.z) }
    mutating func str(_ s: String) { let b = Array(s.utf8.prefix(40)); u8(UInt8(b.count)); d.append(contentsOf: b) }
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
    static let magic: UInt8 = 0xF7, version: UInt8 = 1

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
        w.str(h.name); w.str(h.group)
        return w.d
    }

    /// Nil for anything that is not a well-formed message of this version: the network is not trusted.
    static func decode(_ data: Data) -> NetMessage? {
        guard data.count >= 7, data.count < 512 else { return nil }
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
            h.name = r.str(); h.group = r.str()
            guard r.ok, [h.windSpeed, h.windFrom, h.turbulence, h.gustiness, h.thermals, h.cloud, h.haze].allSatisfy({ $0.isFinite }) else { return nil }
            h.windSpeed = clampf(h.windSpeed, 0, 20); h.windFrom = clampf(h.windFrom, 0, 360); h.turbulence = clampf(h.turbulence, 0, 1)
            h.gustiness = clampf(h.gustiness, 0, 1); h.thermals = clampf(h.thermals, 0, 2); h.cloud = clampf(h.cloud, 0, 1); h.haze = clampf(h.haze, 0, 1)
            return .hello(h)
        default: return nil
        }
    }
}

/// Finds the other pilots and carries the messages. All Network.framework work happens on one private queue;
/// received messages wait in an inbox that the game empties once per frame.
final class FormationNet {
    static let serviceType = "_formflightx._udp"
    let id: UInt32
    private let queue = DispatchQueue(label: "formationflightx.net")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var outgoing: [String: NWConnection] = [:]      // by the other side's service name
    private var incoming: [ObjectIdentifier: NWConnection] = [:]
    private let lock = NSLock()
    private var inbox: [(Data, Double)] = []
    private var statusText = "Off"
    private(set) var running = false

    init(id: UInt32 = UInt32.random(in: 1000...UInt32.max)) { self.id = id }

    /// A short line for the menu: off, searching, or what went wrong.
    var status: String { lock.lock(); defer { lock.unlock() }; return statusText }
    private func setStatus(_ s: String) { lock.lock(); statusText = s; lock.unlock() }

    private func parameters() -> NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = true
        p.allowLocalEndpointReuse = true
        return p
    }

    func start() {
        guard !running else { return }
        running = true
        setStatus("Looking for other pilots…")
        queue.async { [self] in
            do {
                let l = try NWListener(using: parameters())
                l.service = NWListener.Service(name: "\(id)", type: FormationNet.serviceType)
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.stateUpdateHandler = { [weak self] st in
                    if case .failed(let e) = st { self?.setStatus("Network unavailable (\(e.localizedDescription))") }
                    if case .waiting(let e) = st { self?.setStatus("Waiting for the network (\(e.localizedDescription))") }
                }
                l.start(queue: queue)
                listener = l
            } catch {
                setStatus("Network unavailable (\(error.localizedDescription))")
                return
            }
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
        queue.async { [self] in
            listener?.cancel(); listener = nil
            browser?.cancel(); browser = nil
            outgoing.values.forEach { $0.cancel() }; outgoing = [:]
            incoming.values.forEach { $0.cancel() }; incoming = [:]
        }
        lock.lock(); inbox = []; lock.unlock()
    }

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

    private func accept(_ c: NWConnection) {
        // a restarted or roaming peer shows up as a new flow; old ones are dropped when they fail or pile up
        if incoming.count > 16 { incoming.values.forEach { $0.cancel() }; incoming = [:] }
        let key = ObjectIdentifier(c)
        incoming[key] = c
        c.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: self?.incoming[key] = nil
            default: break
            }
        }
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, _, _, error in
            guard let s = self, let c = c else { return }
            if let d = data, !d.isEmpty {
                let now = CACurrentMediaTime()
                s.lock.lock()
                if s.inbox.count < 600 { s.inbox.append((d, now)) }
                s.lock.unlock()
            }
            if error == nil { s.receive(c) } else { c.cancel() }
        }
    }

    /// Send to every pilot found. Datagrams that cannot be delivered are simply lost; the next one replaces them.
    func broadcast(_ d: Data) {
        guard running else { return }
        queue.async { [self] in
            for c in outgoing.values where c.state == .ready { c.send(content: d, completion: .idempotent) }
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
            }
        }
    }
}
