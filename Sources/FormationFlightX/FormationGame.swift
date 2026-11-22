import simd
import Foundation
import QuartzCore

// The formation side of the game: who is flying, who leads, where each slot is, and what goes over the network.

extension Game {
    static let aiNames = ["Computer 1", "Computer 2", "Computer 3", "Computer 4"]

    var leadID: UInt32 { order.first ?? net.id }
    var isLead: Bool { leadID == net.id }
    /// My place in the formation: 0 leads, 1 and 2 are the wingmen.
    var myNumber: Int { order.firstIndex(of: net.id) ?? 0 }
    var remotePilots: [Wingman] { wingmen.filter { $0.ai == nil } }

    func name(of id: UInt32) -> String { id == net.id ? pilotName : (wingmen.first { $0.id == id }?.name ?? "?") }

    /// The aircraft of a formation member, if it is flying right now.
    func flying(_ id: UInt32) -> Aircraft? {
        if id == net.id { return simHeld ? nil : aircraft }
        guard let w = wingmen.first(where: { $0.id == id }), w.present(CACurrentMediaTime()) else { return nil }
        return w.aircraft
    }

    /// The spacing between neighbours in metres, set by the lead's wingspan.
    var spacingMetres: Float {
        let span = (leadID == net.id ? aircraft : wingmen.first { $0.id == leadID }?.aircraft)?.spec.span ?? aircraft.spec.span
        return Formation.spacing(spacing, span: span)
    }

    /// Slot of formation number `n` (1 or 2), if the lead is flying.
    func slot(_ n: Int) -> V3? {
        guard n >= 1, let lead = flying(leadID), !lead.crashed else { return nil }
        return Formation.slot(n, lead: lead, kind: formation, spacing: spacingMetres)
    }

    // MARK: Commands

    func nextFormation() {
        guard isLead else { say("The formation is called by the lead (\(name(of: leadID)))"); return }
        formation = FormationKind(rawValue: (formation.rawValue + 1) % FormationKind.allCases.count) ?? .vic
        say("Formation: \(formation.name) — \(formation.blurb)", 4)
    }

    func nextSpacing() {
        guard isLead else { say("The spacing is called by the lead (\(name(of: leadID)))"); return }
        spacing = (spacing + 1) % Formation.spacingNames.count
        say(String(format: "Spacing: %@ (%.1f m)", Formation.spacingNames[spacing], spacingMetres))
    }

    /// Take the lead, or, when already leading, hand it back.
    func takeLead() {
        if isLead && leadEpoch > 0 {
            leadEpoch = 0
            computeOrder()
            say(isLead ? "You keep the lead: nobody else has claimed it" : "\(name(of: leadID)) has the lead", 3)
        } else if isLead {
            say("You already lead the formation")
        } else {
            leadEpoch = (wingmen.map { $0.leadEpoch }.max() ?? 0) + 1
            computeOrder()
            say("You have the lead", 3)
        }
        helloAcc = 1
    }

    /// Start again in the air, a little behind your slot and at the lead's speed. False if there is nobody to join.
    @discardableResult func joinUp(quiet: Bool) -> Bool {
        computeOrder()
        let n = myNumber
        guard n >= 1, let lead = flying(leadID), !lead.crashed, !lead.onGround, let s = slot(n) else {
            if !quiet { say(isLead ? "You are the lead: the others join on you" : "The lead is not flying yet") }
            return false
        }
        let (f, _) = Formation.frame(of: lead)
        resetAircraft()
        var p = s - f * max(8, 2 * spacingMetres)
        p.y = max(p.y, terrain.height(p.x, p.z) + 6)
        aircraft.reset(pos: p, heading: atan2(-f.x, -f.z), speed: max(length(lead.vel), aircraft.spec.stallSpeed * 1.4))
        racePrev = p                // (being moved there is not flying through a gate)
        inHand = false              // (a reset puts a hand-launched aircraft back in the hand; this one is flying)
        input.resetThrottle(aircraft.spec.kind, launch: true)
        lastYReset()
        snapCamera()
        if !quiet { say("Joining on \(name(of: leadID)) as number \(n + 1)", 3) }
        return true
    }

    /// The host chooses where the session flies; everyone else follows.
    func chooseSite(_ i: Int) {
        if together && !isHost { say("The flying site is chosen by the host (\(name(of: hostID)))", 3); return }
        selectSite(i)
    }

    /// How far the outermost wingman sits to the side of the lead.
    var formationReach: Float { spacingMetres * (1...max(order.count - 1, 2)).map { abs(formation.offset($0).x) }.max()! }

    // MARK: Session

    /// Flying with other pilots, as opposed to alone or with the computer.
    var together: Bool { !remotePilots.isEmpty }
    /// The pilot who runs the session: whoever has switched hosting on, or failing that the lowest number.
    var hostID: UInt32 {
        var hosts = remotePilots.filter { $0.hello.hosting }.map { $0.id }
        if net.hosting { hosts.append(net.id) }
        return hosts.min() ?? ([net.id] + remotePilots.map { $0.id }).min()!
    }
    var isHost: Bool { hostID == net.id }

    /// Host: start the session, or start it again. Everyone goes back to the launch point and flies.
    func startSession() {
        guard isHost else { return }
        let again = sessionRunning
        sessionRunning = true; sessionCount &+= 1; sessionSeen = sessionCount
        helloAcc = 1
        cameFromMenu = false; lobbyReturn = false; hud.overlay = .none
        resetAircraft()
        launchPartners()
        if together { note(again ? "\(pilotName) restarted the session" : "\(pilotName) started the session") }
    }

    /// Host: stop the session. Everyone comes back to the lobby, where wings can be changed.
    func stopSession() {
        guard isHost, sessionRunning else { return }
        sessionRunning = false
        helloAcc = 1
        cameFromMenu = false; hud.overlay = .lobby
        if together { note("\(pilotName) stopped the session") }
    }

    /// The computer pilots start again from beside the pilots, with you.
    func launchPartners() {
        computeOrder()
        for w in wingmen where w.ai != nil { place(w, launch: true) }
        // while you still hold your aircraft they hold theirs, and throw when you do
        partnersHeld = inHand && remotePilots.isEmpty
        launchGrace = 6
    }

    /// Your place among the computer pilots: 0 leads, 1 is number 2, and so on.
    func setPlace(_ n: Int) {
        if n == 0 { if leadEpoch == 0 { leadEpoch = 1 } } else { leadEpoch = 0; myPlace = n }
        computeOrder()
    }

    /// Leave the menus and fly, if the session allows it.
    func takeOff() {
        lobbyReturn = false
        if !together {
            cameFromMenu = false; hud.overlay = .none
            // unless you are coming back to a flight already under way, everyone launches together from the pilots' position
            let flying = !aircraft.crashed && !aircraft.onGround && length(aircraft.vel) > 3 && aircraft.pos.y - terrain.gnd(aircraft.pos.x, aircraft.pos.z) > 3 && flownOnce
            if !flying { resetAircraft(); launchPartners(); flownOnce = true }
        }
        else if sessionRunning { cameFromMenu = false; hud.overlay = .none }
        else if isHost { startSession() }
        else { cameFromMenu = false; hud.overlay = .lobby; say("Waiting for \(name(of: hostID)) to start the session", 3) }
    }

    /// Open a browser or panel from the lobby and come back to the lobby afterwards.
    func fromLobby(_ o: Overlay) { cameFromMenu = false; lobbyReturn = true; hud.overlay = o }

    private func followSession() {
        let o = hud.overlay
        if lobbyReturn && (o == .menu || o == .none) { lobbyReturn = false; hud.overlay = .lobby }
        guard together else { sessionRunning = !simHeld; return }       // alone, flying is the session
        if !isHost, let w = wingmen.first(where: { $0.id == hostID }), CACurrentMediaTime() - w.lastHello < 3 {
            let h = w.hello
            let was = sessionRunning
            sessionRunning = h.running; sessionCount = h.session
            if h.running && h.session != sessionSeen {
                // a start or restart: fly, unless busy in a browser
                sessionSeen = h.session
                if o == .none || o == .lobby || o == .menu {
                    cameFromMenu = false; hud.overlay = .none
                    resetAircraft()
                    say("\(w.name) \(was ? "restarted" : "started") the session", 3)
                }
                note("\(w.name) \(was ? "restarted" : "started") the session")
            } else if was && !h.running {
                note("\(w.name) stopped the session")
                say("\(w.name) stopped the session", 3)
            }
        }
        // while the session is stopped nobody flies
        if !sessionRunning && hud.overlay == .none { cameFromMenu = false; hud.overlay = .lobby }
    }

    /// The autopilot for this pilot's own wing flies whatever part the pilot has: as the lead a wide racetrack
    /// the others can follow, as a wingman the slot.
    func flyMyPart(dt: Float) -> Controls {
        let n = myNumber
        if n >= 1, let lead = flying(leadID), !lead.crashed, let s = slot(n) {
            return ownPilot.follow(aircraft, lead: lead, slot: s, terrain: terrain, dt: dt * timeScale)
        }
        return ownPilot.lead(aircraft, terrain: terrain, reach: formationReach, dt: dt * timeScale)
    }

    // MARK: Lobby

    /// A note from the app in the chat.
    func note(_ text: String) {
        chatCount += 1
        chat.append(ChatLine(id: chatCount, name: "", text: text, system: true, time: CACurrentMediaTime()))
        if chat.count > 200 { chat.removeFirst(chat.count - 200) }
    }

    private func transmit(_ c: NetChat) {
        // datagrams can be lost, so each line goes out five times; receivers drop the repeats
        chatOut.append((NetCodec.encode(c), 5, 0))
    }

    func sendChat(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatCount += 1; chatSeq &+= 1
        var line = String(text.prefix(NetCodec.maxChat))
        while line.utf8.count > NetCodec.maxChat { line.removeLast() }
        chat.append(ChatLine(id: chatCount, name: pilotName, text: line, mine: true, time: CACurrentMediaTime()))
        transmit(NetChat(id: net.id, seq: chatSeq, kind: 0, text: line))
    }

    private func received(_ c: NetChat) {
        guard let w = wingmen.first(where: { $0.id == c.id && $0.ai == nil }) else { return }     // only from pilots in this formation
        guard chatSeen.insert(UInt64(c.id) << 32 | UInt64(c.seq)).inserted else { return }
        if chatSeen.count > 4000 { chatSeen.removeAll() }
        guard c.kind == 0 else { return }
        guard !c.text.isEmpty else { return }
        chatCount += 1
        chat.append(ChatLine(id: chatCount, name: w.name, text: c.text, time: CACurrentMediaTime()))
        if chat.count > 200 { chat.removeFirst(chat.count - 200) }
        if hud.overlay != .lobby { unreadChat += 1 }
    }

    /// Where this pilot is, as the others see it: 0 in the menus, 1 in the lobby, 2 flying.
    var place: UInt8 { hud.overlay == .lobby ? 1 : (simHeld ? 0 : 2) }
    static let placeNames = ["In the menus", "In the lobby", "Flying"]

    // MARK: Roster

    func computeOrder() {
        if remotePilots.isEmpty {
            // alone with the computer: its pilots in their order, you in the place you chose (or in front, if you took the lead)
            var o = wingmen.filter { $0.ai != nil }.map { $0.id }.sorted()
            o.insert(net.id, at: o.isEmpty || leadEpoch > 0 ? 0 : min(max(myPlace, 1), o.count))
            order = o
            return
        }
        var all: [(id: UInt32, epoch: UInt32)] = [(net.id, leadEpoch)]
        for w in wingmen { all.append((w.id, w.ai == nil ? w.leadEpoch : 0)) }
        // the highest claim leads; with no claim at all the computer does, or the lowest number on the network
        all.sort { $0.epoch != $1.epoch ? $0.epoch > $1.epoch : $0.id < $1.id }
        let lead = all[0].id
        // pilots take the lower numbers, computer partners (numbers 1 and 2 on the wire) the rest
        order = [lead] + all.dropFirst().map { $0.id }.sorted { ($0 < 1000) != ($1 < 1000) ? $0 >= 1000 : $0 < $1 }
    }

    /// Read the network, keep the list of pilots current, and bring in or send away the computer partners.
    func updateRoster() {
        let now = CACurrentMediaTime()
        let before = leadID
        for (m, t) in net.drain() {
            switch m {
            case .hello(let h):
                guard h.group == group else { continue }
                var w = wingmen.first { $0.id == h.id && $0.ai == nil }
                if w == nil {
                    guard remotePilots.count < Formation.maxPilots - 1 else { continue }         // five fly together, no more
                    let n = Wingman(id: h.id, name: h.name, specIndex: 0)
                    wingmen.append(n); w = n
                    say("\(h.name.isEmpty ? "A pilot" : h.name) joined the formation", 4)
                    note("\(h.name.isEmpty ? "A pilot" : h.name) joined")
                }
                w?.name = h.name.isEmpty ? "Pilot" : h.name; w?.hello = h; w?.leadEpoch = h.leadEpoch; w?.lastHello = t
            case .state(let s):
                wingmen.first { $0.id == s.id && $0.ai == nil }?.receive(s, at: t)
            case .chat(let c): received(c)
            case .clock(let k):
                wingmen.first { $0.id == k.id && $0.ai == nil }?.receive(k, at: t, me: net.id)
            case .voice(let v):
                if wingmen.contains(where: { $0.id == v.id && $0.ai == nil }) { voice.receive(from: v.id, seq: v.seq, payload: v.payload) }
            }
        }
        for w in wingmen where w.ai == nil && now - w.lastHello > 5 { say("\(w.name) left the formation", 4); note("\(w.name) left") }
        if wingmen.contains(where: { $0.ai == nil && now - $0.lastHello > 5 }) {
            wingmen.removeAll { $0.ai == nil && now - $0.lastHello > 5 }
            voice.keep(only: Set(remotePilots.map { $0.id }))
        }
        if hud.overlay == .lobby { unreadChat = 0 }

        // (the computer flies fixed-wing aircraft only: no partners for a helicopter or a multirotor)
        let wantAI = aiPartners && remotePilots.isEmpty && aircraft.spec.kind == .airplane
        if !wantAI { wingmen.removeAll { $0.ai != nil } }
        else if wingmen.filter({ $0.ai != nil }).count != aiCount {
            wingmen.removeAll { $0.ai != nil }
            for k in 0..<aiCount {
                let w = Wingman(id: UInt32(k + 1), name: Game.aiNames[k], specIndex: aircraftIndex)
                w.ai = FormationPilot()
                wingmen.append(w)
            }
            computeOrder()
            for w in wingmen where w.ai != nil { place(w) }
        }
        // the computer flies the same model as you, so everyone has the same speed range
        for w in wingmen where w.ai != nil && w.specIndex != aircraftIndex {
            w.specIndex = aircraftIndex
            w.aircraft = Aircraft(AircraftLibrary.all[aircraftIndex]); w.aircraft.unlimitedBattery = true
            place(w)
        }
        computeOrder()
        if leadID != before && !order.isEmpty && hud.overlay != .splash {
            say(isLead ? "You have the lead" : "\(name(of: leadID)) has the lead", 3)
            // computer wingmen that suddenly have a new lead, or the computer taking over, start from a sensible place
            for w in wingmen where w.ai != nil && (w.id == leadID || before == w.id) { if w.aircraft.crashed || w.aircraft.onGround { place(w) } }
        }
        // the host's choices apply to everyone: where, and in what weather and light
        if !isHost, let w = wingmen.first(where: { $0.id == hostID }), now - w.lastHello < 3 {
            let h = w.hello
            if Int(h.site) != siteIndex, Int(h.site) != loadingSite, Int(h.site) < SiteSpec.all.count { selectSite(Int(h.site)) }
            if Int(h.timeOfDay) < Game.timeNames.count { timeOfDay = Int(h.timeOfDay) }
            env.windSpeed = h.windSpeed; env.windFrom = h.windFrom; env.turbulence = h.turbulence; env.gustiness = h.gustiness
            env.thermalStrength = h.thermals; env.cloud = h.cloud; env.haze = h.haze
        }
        // the lead calls the formation
        if !isLead, let w = wingmen.first(where: { $0.id == leadID }), w.ai == nil, now - w.lastHello < 3 {
            let h = w.hello
            if let f = FormationKind(rawValue: Int(h.formation)), f != formation { formation = f; say("Formation: \(f.name)", 3) }
            if Int(h.spacing) != spacing, Int(h.spacing) < Formation.spacingNames.count { spacing = Int(h.spacing); say("Spacing: " + Formation.spacingNames[spacing]) }
        }
        followSession()
    }

    /// Put a computer partner where it can start flying: the lead onto the racetrack, a wingman into its slot,
    /// or beside the pilots for a hand launch when the lead is still low.
    func place(_ w: Wingman, launch: Bool = false) {
        let ac = w.aircraft, spec = ac.spec
        let n = order.firstIndex(of: w.id) ?? 1
        w.ai = FormationPilot()
        w.crashTimer = 0
        let home = terrain.pilotPos
        if n == 0 && !launch {
            let p = V3(home.x - 110, home.y + FormationPilot.altitude(site), home.z - 70)
            ac.reset(pos: V3(p.x, max(p.y, terrain.height(p.x, p.z) + 22), p.z), heading: -.pi / 2, speed: FormationPilot.cruise(spec))
        } else if !launch, let lead = flying(leadID), !lead.crashed, let s = slot(n), lead.pos.y - terrain.height(lead.pos.x, lead.pos.z) > 10 {
            let (f, _) = Formation.frame(of: lead)
            var p = s - f * 6
            p.y = max(p.y, terrain.height(p.x, p.z) + 6)
            ac.reset(pos: p, heading: atan2(-f.x, -f.z), speed: max(length(lead.vel), spec.stallSpeed * 1.4))
        } else {
            // thrown from beside the pilots; an aircraft that needs a runway is given flying speed a little higher up
            if spec.handLaunch { ac.reset(pos: home + V3(2 + 3 * Float(n), 1.9, -3), heading: 0, speed: Game.throwSpeed(spec)); ac.q = ac.q * simd_quatf(angle: Game.throwAngle, axis: V3(1, 0, 0)); ac.vel = ac.q.act(V3(0, 0, -Game.throwSpeed(spec))) }
            else { ac.reset(pos: home + V3(2 + 5 * Float(n), 5, -3), heading: 0, speed: spec.stallSpeed * 1.6) }
        }
        for i in ac.levels.indices { ac.levels[i] = 0.7 }
        ac.updateRenderPose(ahead: 0)
    }

    // MARK: Every frame

    func updateFormation(dt: Float, realDt: Float) {
        let now = CACurrentMediaTime()
        let running = !paused && !simHeld
        let sdt = dt * timeScale

        // computer partners: decide the controls for the next steps, and pick up the pieces after a crash
        for w in wingmen where w.ai != nil {
            let ac = w.aircraft
            guard running else { ac.updateRenderPose(ahead: 0); continue }
            let n = order.firstIndex(of: w.id) ?? 1
            if ac.crashed {
                w.crashTimer += sdt
                w.controls = Controls()
                if w.crashTimer > 3 { place(w) }
            } else if !terrain.contains(ac.pos) || !ac.pos.y.isFinite || terrain.overWater(ac.pos) {
                place(w)
            } else if terrain.strikes(ac.pos, reach: 0.3 * ac.spec.span) {
                ac.crashed = true; ac.crashImpact = length(ac.vel); ac.vel *= 0.1
            } else if n == 0 {
                // the computer lead flies slower while you are still on your way to your slot
                // (it starts waiting when you are 40 m out and stops when you are within 15 m, so it does not keep changing its mind)
                let off = slotError.map { length($0) } ?? 0
                if isLead { leadWaits = false } else if aircraft.crashed || aircraft.onGround || off > 40 { leadWaits = true } else if off < 15 { leadWaits = false }
                w.controls = w.ai!.lead(ac, terrain: terrain, reach: formationReach, dt: sdt, pace: leadWaits ? 0.85 : 1)
            } else if let lead = flying(leadID), !lead.crashed, let s = slot(n) {
                w.controls = w.ai!.follow(ac, lead: lead, slot: s, terrain: terrain, dt: sdt)
            } else {
                w.controls = w.ai!.lead(ac, terrain: terrain, dt: sdt)       // nobody to follow: fly the racetrack
            }
            ac.updateRenderPose(ahead: ac.crashed || Game.noInterp ? 0 : acc)
        }
        // pilots on the network
        for w in wingmen where w.ai == nil { w.extrapolate(now: now, dt: realDt) }

        // touching another aircraft ends the flight for both
        // (not in the first seconds after a launch: everyone starts side by side and has to sort themselves out)
        if running { launchGrace = max(launchGrace - sdt, 0) }
        if running && !aircraft.crashed && launchGrace <= 0 {
            for w in wingmen where w.present(now) && !w.aircraft.crashed {
                let d = w.aircraft.pos - aircraft.pos
                let reach = aircraft.spec.span + w.aircraft.spec.span
                let h = length(V3(d.x, 0, d.z)) / (0.42 * reach), v = d.y / (0.14 * reach)
                guard h * h + v * v < 1 else { continue }
                aircraft.crashed = true
                aircraft.crashImpact = max(length(aircraft.vel - w.aircraft.vel), 5)
                if w.ai != nil { w.aircraft.crashed = true; w.aircraft.crashImpact = aircraft.crashImpact }
                say("Mid-air collision with \(w.name)", 3)
                break
            }
        }

        // how well the slot is being held
        slotError = nil; slotMarker = nil
        let n = myNumber
        if n >= 1, let lead = flying(leadID), let s = slot(n) {
            let (f, r) = Formation.frame(of: lead)
            let e = s - aircraft.pos
            slotTol = max(0.35 * spacingMetres, 0.6)
            slotError = V3(dot(e, r), e.y, dot(e, f))
            let good = length(e) < slotTol
            slotMarker = (s, f, max(0.5 * aircraft.spec.span, 0.4), good)
            if running && !aircraft.crashed && !aircraft.onGround {
                flownTime += sdt
                if good { stationTime += sdt }
            }
        }

        // smoke from the others
        if running {
            for w in wingmen where w.smoke && w.present(now) && !w.aircraft.crashed { laySmoke(w.id, from: w.aircraft, dt: sdt) }
        }

        // voice: on while the network is; push to talk is the B key in flight and a button in the lobby
        if voice.onFrame == nil {
            let net = self.net
            voice.onFrame = { seq, payload in net.broadcast(NetCodec.encode(NetVoice(id: net.id, seq: seq, payload: payload))) }
        }
        voice.setActive(net.running)
        // the keyboard key only counts in flight (elsewhere it is typing); a controller's button counts everywhere
        voice.talkHeld = lobbyTalk || input.talkOnDevice || (hud.overlay == .none && input.keys.contains(input.talkKey))

        // tell the others
        guard net.running else { chatOut = []; return }
        for i in chatOut.indices where chatOut[i].next <= now {
            net.broadcast(chatOut[i].data)
            chatOut[i].left -= 1; chatOut[i].next = now + 0.12
        }
        chatOut.removeAll { $0.left <= 0 }
        helloAcc += realDt
        if helloAcc >= 0.5 {
            helloAcc = 0
            var h = NetHello()
            h.id = net.id; h.leadEpoch = leadEpoch; h.site = UInt16(siteIndex)
            h.formation = UInt8(formation.rawValue); h.spacing = UInt8(spacing); h.timeOfDay = UInt8(timeOfDay)
            h.windSpeed = env.windSpeed; h.windFrom = env.windFrom; h.turbulence = env.turbulence; h.gustiness = env.gustiness
            h.thermals = env.thermalStrength; h.cloud = env.cloud; h.haze = env.haze
            h.name = pilotName; h.group = group; h.place = place
            h.hosting = net.hosting; h.running = sessionRunning; h.session = sessionCount
            net.broadcast(NetCodec.encode(h))
        }
        clockAcc += realDt
        if clockAcc >= 0.25 {
            clockAcc = 0
            var k = NetClock()
            k.id = net.id
            let sent = CACurrentMediaTime()             // (read here, so this frame's own work is not counted as delay)
            k.time = sent
            k.echoes = remotePilots.compactMap { $0.echo(now: sent) }
            net.broadcast(NetCodec.encode(k))
        }
        sendAcc += realDt
        if running && sendAcc >= 1 / 60 {
            sendAcc = min(sendAcc - 1 / 60, 1 / 60)
            var s = NetState()
            s.id = net.id; s.time = now; s.spec = UInt16(aircraftIndex)
            s.crashed = aircraft.crashed; s.smoke = smokeOn && aircraft.power > 0.08
            s.pos = aircraft.renderPos; s.vel = aircraft.crashed ? .zero : aircraft.vel; s.omega = aircraft.crashed ? .zero : aircraft.omega
            s.q = aircraft.renderQ; s.servo = aircraft.servo; s.level = aircraft.levels[0]
            net.broadcast(NetCodec.encode(s))
        }
    }

    // MARK: Display

    func fillFormationHUD(_ s: inout HUDState) {
        let now = CACurrentMediaTime()
        let n = myNumber
        s.role = order.count < 2 ? "SOLO" : (n == 0 ? "LEAD" : "NUMBER \(n + 1)")
        s.formation = order.count < 2 ? "" : "\(formation.name) · \(Formation.spacingNames[spacing]) \(String(format: "%.1f m", spacingMetres))"
        s.slot = slotError; s.slotTol = slotTol
        s.onStation = slotError.map { length($0) < slotTol } ?? false
        if n >= 1 {
            if let e = slotError {
                s.station = String(format: "%.1f m from slot", length(e)) + (flownTime > 3 ? String(format: " · on station %.0f%%", 100 * stationTime / flownTime) : "")
            } else { s.station = "Waiting for the lead" }
        }
        for (k, id) in order.enumerated() where id != net.id {
            guard let w = wingmen.first(where: { $0.id == id }) else { continue }
            var detail = "", good = false
            if !w.present(now) { detail = "not flying" }
            else if w.aircraft.crashed { detail = "crashed" }
            else {
                detail = String(format: "%.0f m", distance(w.aircraft.pos, aircraft.pos))
                // the lead sees how well each wingman is holding position
                if k >= 1, let sl = slot(k) {
                    let e = distance(sl, w.aircraft.pos)
                    good = e < max(0.35 * spacingMetres, 0.6)
                    detail += String(format: " · %.1f m off slot", e)
                }
            }
            s.mates.append(Mate(id: id, number: k + 1, name: w.name, detail: detail, good: good, talking: voice.speaking(id)))
        }
        // the map
        let (f, r) = Formation.frame(of: aircraft)
        var far: Float = 0
        for w in wingmen where w.present(now) {
            let d = w.aircraft.pos - aircraft.pos, (wf, _) = Formation.frame(of: w.aircraft)
            let p = SIMD2(dot(d, r), dot(d, f))
            far = max(far, simd_length(p))
            s.blips.append(Blip(id: w.id, p: p, heading: atan2(dot(wf, r), dot(wf, f)), dAlt: d.y, name: w.ai == nil ? w.name : "", lead: w.id == leadID,
                                talking: voice.speaking(w.id), crashed: w.aircraft.crashed))
        }
        let home = terrain.pilotPos - aircraft.pos
        s.mapHome = SIMD2(dot(home, r), dot(home, f))
        s.mapNorth = atan2(dot(V3(0, 0, -1), r), dot(V3(0, 0, -1), f))
        // the scale steps out to keep the farthest of the others in the picture, and does not flicker between steps
        let want = [Float(15), 30, 60, 120, 250, 500, 1000, 2000].first { $0 >= far * 1.15 } ?? 2000
        if want > mapRange || far * 1.6 < mapRange { mapRange = want }
        s.mapRange = mapRange
        // under the map: how far the lead is (or, leading, the nearest of the others)
        if !isLead, let l = wingmen.first(where: { $0.id == leadID && $0.present(now) }) {
            s.mapNote = String(format: "Lead %.0f m", distance(l.aircraft.pos, aircraft.pos))
        } else if let d = wingmen.filter({ $0.present(now) }).map({ distance($0.aircraft.pos, aircraft.pos) }).min() {
            s.mapNote = String(format: "Nearest %.0f m", d)
        }
        s.talking = remotePilots.filter { voice.speaking($0.id) }.map { $0.name }
        s.unread = unreadChat
        s.chat = chat.suffix(4).filter { !$0.mine && now - $0.time < 10 }
        s.micLive = voice.sending
        if net.running && voice.mode != .off {
            if voice.micProblem != nil { s.mic = "Microphone unavailable" }
            else if voice.sending { s.mic = "ON AIR" }
            else { s.mic = voice.mode == .open ? "Mic open" : "Hold \(input.talkHint) to talk" }
        }
        if net.running {
            if !remotePilots.isEmpty { s.net = "\(remotePilots.count + 1) pilots connected" }
            else if let j = net.joined { s.net = j.answering ? "Connected to \(j.target); waiting for the others" : "Calling \(j.target)…" }
            // (the address itself stays in the panels: the flight screen is what gets streamed and shared)
            else if net.hosting { s.net = "Hosting; waiting for pilots" }
            else { s.net = net.status }
        }
        else { s.net = multiplayer ? "" : "Network off" }
    }
}
