import simd
import Foundation
import QuartzCore

// What goes on behind the menus: a flight of five of the chosen aircraft flies the site in the chosen formation,
// trailing smoke, and a camera follows it, cutting from one view to the next. Nothing here touches the pilot's
// own aircraft, which waits where it was left.

extension Game {
    /// A menu is open over a 3D site, and nobody else's flying needs to be shown instead.
    var showcaseActive: Bool {
        hud.overlay.pausesSim && site.panorama == nil && fixedView == nil && closeup == nil && !(together && sessionRunning) && !Game.noShowcase
    }

    private func launchShowcase() {
        let home = terrain.pilotPos, spec = AircraftLibrary.all[aircraftIndex]
        showFlight = (0..<5).map { Wingman(id: 0xF000_0000 + UInt32($0), name: "", specIndex: aircraftIndex) }
        let p = V3(home.x - 150, home.y + FormationPilot.altitude(site), home.z - 70)
        let lead = showFlight[0].aircraft
        lead.reset(pos: V3(p.x, max(p.y, terrain.gnd(p.x, p.z) + 22), p.z), heading: -.pi / 2, speed: FormationPilot.cruise(spec))
        for (n, w) in showFlight.enumerated() {
            w.ai = FormationPilot()
            if n > 0 { rejoin(n) }
            for i in w.aircraft.levels.indices { w.aircraft.levels[i] = 0.7 }
            w.aircraft.updateRenderPose(ahead: 0)
        }
        showShot = Int(CACurrentMediaTime()) % 5; showShotTime = 0; showSnap = true
    }

    private var showSpacing: Float { Formation.spacing(spacing, span: showFlight[0].aircraft.spec.span) }

    /// Put number `n` back into its slot behind the lead.
    private func rejoin(_ n: Int) {
        let lead = showFlight[0].aircraft, ac = showFlight[n].aircraft
        let (f, _) = Formation.frame(of: lead)
        var p = Formation.slot(n, lead: lead, kind: formation, spacing: showSpacing)
        p.y = max(p.y, terrain.gnd(p.x, p.z) + 6)
        ac.reset(pos: p, heading: atan2(-f.x, -f.z), speed: max(length(lead.vel), ac.spec.stallSpeed * 1.4))
        showFlight[n].crashTimer = 0
    }

    func updateShowcase(dt: Float) {
        guard showcaseActive else {
            if !showFlight.isEmpty { showFlight = []; particles.removeAll(); snapCamera() }
            return
        }
        let key = siteVersion * 1000 + aircraftIndex
        if showFlight.isEmpty || key != showKey { showKey = key; launchShowcase() }
        let lead = showFlight[0].aircraft
        // the lead flies the racetrack, wide enough for the outermost wingman; the others hold their slots
        let reach = showSpacing * (1...4).map { abs(formation.offset($0).x) }.max()!
        for (n, w) in showFlight.enumerated() {
            let ac = w.aircraft
            if ac.crashed || !terrain.contains(ac.pos) || !ac.pos.y.isFinite || terrain.overWater(ac.pos) || terrain.strikes(ac.pos, reach: 0.3 * ac.spec.span) {
                if n == 0 { launchShowcase(); return }
                w.crashTimer += dt
                if w.crashTimer > 0.5 { rejoin(n) }
                w.controls = Controls()
            } else if n == 0 {
                w.controls = w.ai!.lead(ac, terrain: terrain, reach: reach, dt: dt)
            } else {
                w.controls = w.ai!.follow(ac, lead: lead, slot: Formation.slot(n, lead: lead, kind: formation, spacing: showSpacing), terrain: terrain, dt: dt)
            }
        }
        let h: Float = 0.001
        showAcc += dt
        while showAcc >= h {
            env.advance(dt: h, at: lead.pos, airspeed: lead.airspeed, terrain: terrain)
            for w in showFlight { w.aircraft.step(dt: h, c: w.controls, terrain: terrain, wind: env.wind(at: w.aircraft.pos, terrain: terrain), rollMu: site.rollMu) }
            showAcc -= h
        }
        for w in showFlight { w.aircraft.updateRenderPose(ahead: showAcc) }

        // smoke from all five, and the smoke already in the air drifting and thinning
        showSmoke += dt * 48
        let puffs = Int(showSmoke); showSmoke -= Float(puffs)
        if puffs > 0 { for w in showFlight where !w.aircraft.crashed {
            let ac = w.aircraft
            for k in 0..<min(puffs, 3) {
                particles.append(Particle(pos: ac.pos + ac.q.act(ac.spec.smokePos) - ac.vel * (Float(k) / 48), vel: env.windVec * 0.8 + ac.vel * 0.08,
                                          age: 0, life: 2.2, size: 0.17, color: V4(0.96, 0.96, 0.97, 0.36)))
            }
        } }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].vel *= 1 - min(0.8 * dt, 1)
            particles[i].pos += particles[i].vel * dt
        }
        particles.removeAll { $0.age >= $0.life }
        if particles.count > 900 { particles.removeFirst(particles.count - 900) }
    }

    /// The camera for the showcase. Returns false when it does not apply and the pilot's own camera should.
    func showcaseCamera(_ dt: Float) -> Bool {
        guard showcaseActive, let lead = showFlight.first?.aircraft else { return false }
        var c = V3.zero
        for w in showFlight { c += w.aircraft.renderPos }
        c /= Float(showFlight.count)
        let R = (showFlight.map { distance($0.aircraft.renderPos, c) }.max() ?? 2) + lead.spec.span
        let (f, r) = Formation.frame(of: lead)
        let up = V3(0, 1, 0)

        showShotTime += dt
        let passed = showShot == 2 && (dot(c - showEye, f) > R + 25 || distance(c, showEye) > 320)
        if showShotTime > 10 || (passed && showShotTime > 2.5) { showShot = (showShot + 1) % 5; showShotTime = 0; showSnap = true }
        var want: V3, wantFov: Float = 36 * deg
        switch showShot {
        case 0:     // from behind and above, off to one side
            want = c - f * (R * 1.2 + 2) + up * (R * 1.1 + 1) + r * (R * 1.3)
        case 1:     // flying alongside, a little ahead
            want = c + r * (R * 1.7 + 2) + f * (R * 0.6) + up * (R * 0.2)
        case 2:     // standing on the ground as they come past
            if showSnap {
                let v = max(length(lead.vel), 8)
                var p = c + f * (v * 4) + r * 30
                p.y = terrain.gnd(p.x, p.z) + 1.7
                showEye = p
            }
            want = showEye
            wantFov = clampf(2 * atan(R * 1.5 / max(distance(c, showEye), 1)), 6 * deg, 55 * deg)
        case 3:     // circling them
            showAngle += dt * 0.32
            want = c + V3(cos(showAngle), 0, sin(showAngle)) * (R * 1.9 + 3) + up * (R * 0.4 + 1)
        default:    // ahead and a little below, looking back at them coming on
            want = c + f * (R * 2 + 3) - r * (R * 0.5) - up * (R * 0.2)
        }
        want.y = max(want.y, terrain.gnd(want.x, want.z) + 1.2)
        if showSnap { eye = want; showTarget = c; fov = wantFov }
        else {
            eye += (want - eye) * min(1, dt * (showShot == 2 ? 20 : 3.5))
            showTarget += (c - showTarget) * min(1, dt * 12)
            fov += (wantFov - fov) * min(1, dt * 3)
        }
        showSnap = false
        // the main menu covers the left of the window: aim to the left of the flight so that it sits in the open part
        var t = showTarget
        if hud.overlay == .menu {
            let d = distance(eye, t), side = normalize(cross(t - eye, up))
            t -= side * (d * tan(fov / 2) * 1.5 * 0.32)
        }
        target = t; upVec = up
        return true
    }
}
