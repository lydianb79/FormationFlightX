import simd
import Foundation
import QuartzCore

// The formation side of the game: who is flying, who leads, where each slot is, and what goes over the network.

extension Game {
    static let aiNames = ["Computer 1", "Computer 2"]

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
        input.resetThrottle(aircraft.spec.kind, launch: true)
        lastYReset()
        snapCamera()
        if !quiet { say("Joining on \(name(of: leadID)) as number \(n + 1)", 3) }
        return true
    }

    /// The lead chooses where the formation flies; everyone else follows.
    func chooseSite(_ i: Int) {
        if !isLead, let w = wingmen.first(where: { $0.id == leadID }), w.ai == nil {
            say("The flying site is chosen by the lead (\(w.name))", 3); return
        }
        selectSite(i)
    }

    // MARK: Roster

    func computeOrder() {
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
                    guard remotePilots.count < 2 else { continue }         // three fly together, no more
                    let n = Wingman(id: h.id, name: h.name, specIndex: 0)
                    wingmen.append(n); w = n
                    say("\(h.name.isEmpty ? "A pilot" : h.name) joined the formation", 4)
                }
                w?.name = h.name.isEmpty ? "Pilot" : h.name; w?.hello = h; w?.leadEpoch = h.leadEpoch; w?.lastHello = t
            case .state(let s):
                wingmen.first { $0.id == s.id && $0.ai == nil }?.receive(s, at: t)
            }
        }
        for w in wingmen where w.ai == nil && now - w.lastHello > 5 { say("\(w.name) left the formation", 4) }
        wingmen.removeAll { $0.ai == nil && now - $0.lastHello > 5 }

        let wantAI = aiPartners && remotePilots.isEmpty
        if !wantAI { wingmen.removeAll { $0.ai != nil } }
        else if !wingmen.contains(where: { $0.ai != nil }) {
            for k in 0..<2 {
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
        // the lead's choices apply to everyone
        if !isLead, let w = wingmen.first(where: { $0.id == leadID }), w.ai == nil, now - w.lastHello < 3 {
            let h = w.hello
            if Int(h.site) != siteIndex, Int(h.site) < SiteSpec.all.count { selectSite(Int(h.site)) }
            if let f = FormationKind(rawValue: Int(h.formation)), f != formation { formation = f; say("Formation: \(f.name)", 3) }
            if Int(h.spacing) != spacing, Int(h.spacing) < Formation.spacingNames.count { spacing = Int(h.spacing); say("Spacing: " + Formation.spacingNames[spacing]) }
            if Int(h.timeOfDay) < Game.timeNames.count { timeOfDay = Int(h.timeOfDay) }
            env.windSpeed = h.windSpeed; env.windFrom = h.windFrom; env.turbulence = h.turbulence; env.gustiness = h.gustiness
            env.thermalStrength = h.thermals; env.cloud = h.cloud; env.haze = h.haze
        }
    }

    /// Put a computer partner where it can start flying: the lead onto the racetrack, a wingman into its slot,
    /// or beside the pilots for a hand launch when the lead is still low.
    func place(_ w: Wingman) {
        let ac = w.aircraft, spec = ac.spec
        let n = order.firstIndex(of: w.id) ?? 1
        w.ai = FormationPilot()
        w.crashTimer = 0
        let home = terrain.pilotPos
        if n == 0 {
            let p = V3(home.x - 110, home.y + FormationPilot.altitude, home.z - 70)
            ac.reset(pos: V3(p.x, max(p.y, terrain.height(p.x, p.z) + 22), p.z), heading: -.pi / 2, speed: FormationPilot.cruise(spec))
        } else if let lead = flying(leadID), !lead.crashed, let s = slot(n), lead.pos.y - terrain.height(lead.pos.x, lead.pos.z) > 10 {
            let (f, _) = Formation.frame(of: lead)
            var p = s - f * 6
            p.y = max(p.y, terrain.height(p.x, p.z) + 6)
            ac.reset(pos: p, heading: atan2(-f.x, -f.z), speed: max(length(lead.vel), spec.stallSpeed * 1.4))
        } else {
            ac.reset(pos: home + V3(2 + 3 * Float(n), 1.9, -3), heading: 0, speed: clampf(spec.stallSpeed * 1.7, 4, 9))
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
            } else if n == 0 {
                w.controls = w.ai!.lead(ac, terrain: terrain, dt: sdt)
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
        if running && !aircraft.crashed {
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
            wingSmokeAcc += sdt * 40
            let puffs = Int(wingSmokeAcc); wingSmokeAcc -= Float(puffs)
            for w in wingmen where w.smoke && w.present(now) && !w.aircraft.crashed && puffs > 0 {
                let ac = w.aircraft
                for k in 0..<min(puffs, 4) {
                    particles.append(Particle(pos: ac.pos + ac.q.act(ac.spec.smokePos) - ac.vel * (Float(k) / 40), vel: env.windVec * 0.8 + ac.vel * 0.08,
                                              age: 0, life: 3.5, size: 0.16, color: V4(0.96, 0.96, 0.97, 0.5)))
                }
            }
        }

        // tell the others
        guard net.running else { return }
        helloAcc += realDt
        if helloAcc >= 0.5 {
            helloAcc = 0
            var h = NetHello()
            h.id = net.id; h.leadEpoch = leadEpoch; h.site = UInt16(siteIndex)
            h.formation = UInt8(formation.rawValue); h.spacing = UInt8(spacing); h.timeOfDay = UInt8(timeOfDay)
            h.windSpeed = env.windSpeed; h.windFrom = env.windFrom; h.turbulence = env.turbulence; h.gustiness = env.gustiness
            h.thermals = env.thermalStrength; h.cloud = env.cloud; h.haze = env.haze
            h.name = pilotName; h.group = group
            net.broadcast(NetCodec.encode(h))
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
            s.mates.append(Mate(id: id, number: k + 1, name: w.name, detail: detail, good: good))
        }
        if net.running { s.net = remotePilots.isEmpty ? net.status : "\(remotePilots.count + 1) pilots connected" }
        else { s.net = multiplayer ? "" : "Network off" }
    }
}
