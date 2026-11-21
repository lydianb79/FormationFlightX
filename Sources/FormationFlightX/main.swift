import AppKit
import GameController
import MetalKit
import SwiftUI

func runSelfTest() {
    let site = SiteSpec.all[0]
    let terrain = Terrain(site: site)
    let env = Environment()
    env.configure(site)
    env.obstacles = terrain.windObstacles
    for spec in AircraftLibrary.all {
        let ac = Aircraft(spec)
        var ap = Autopilot()
        if spec.handLaunch {
            ac.reset(pos: V3(2, 1.9, 0), heading: 0, speed: clampf(spec.stallSpeed * 1.7, 4, 9))
        } else {
            ac.reset(pos: V3(spec.kind == .airplane ? -50 : -6, ac.restHeight + 0.02, 0), heading: -.pi / 2)
        }
        print("== \(spec.name)  mass \(spec.mass) kg")
        var c = Controls()
        var minAgl: Float = 1e9, maxSpeed: Float = 0
        for i in 0..<60_000 {
            if i % 10 == 0 { c = ap.update(ac, terrain: terrain, dt: 0.01) }
            env.advance(dt: 0.001, at: ac.pos, airspeed: ac.airspeed, terrain: terrain)
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: env.wind(at: ac.pos, terrain: terrain), rollMu: site.rollMu)
            let agl = ac.pos.y - terrain.height(ac.pos.x, ac.pos.z)
            if i > 15_000 { minAgl = min(minAgl, agl); maxSpeed = max(maxSpeed, ac.airspeed) }
            if i % 5000 == 0 {
                print(String(format: "t=%4.1f pos=(%7.1f,%6.1f,%7.1f) agl=%5.1f v=%5.1f pitch=%5.1f roll=%6.1f thr=%.2f wp=%d %@",
                             Float(i) / 1000, ac.pos.x, ac.pos.y, ac.pos.z, agl, ac.airspeed, ac.pitch / deg, ac.roll / deg, c.throttle, ap.wp, ac.crashed ? "CRASHED" : ""))
            }
        }
        print(String(format: "   after 15 s: min agl %.1f m, max airspeed %.1f m/s, crashed=%@", minAgl, maxSpeed, ac.crashed ? "YES" : "no"))
    }
}

func runAutorotationTest() {
    let site = SiteSpec.all[0]
    let terrain = Terrain(site: site)
    let ac = Aircraft(AircraftLibrary.all[4])
    ac.reset(pos: V3(0, 90, 0), heading: 0)
    ac.vel = V3(0, 0, -8)
    var c = Controls(); c.hold = true
    print("== Autorotation: \(ac.spec.name), engine off at 90 m, 8 m/s forward")
    for i in 0..<12_000 {
        let agl = ac.pos.y - terrain.height(ac.pos.x, ac.pos.z)
        c.throttle = agl > 6 ? 0.42 : 0.9          // slightly negative collective, then flare
        c.elevator = clampf(3 * (-0.12 - ac.pitch) - 0.3 * ac.omega.x, -1, 1) * (agl > 6 ? 1 : 0) + (agl > 6 ? 0 : clampf(3 * (0.0 - ac.pitch), -1, 1))
        c.aileron = clampf(2 * (0 - ac.roll), -1, 1)
        ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0.05)
        if i % 1000 == 0 || ac.onGround {
            print(String(format: "t=%4.1f agl=%5.1f sink=%5.1f m/s fwd=%4.1f rotor=%3.0f%% %@", Float(i) / 1000, agl, -ac.vel.y, ac.airspeed, ac.levels[0] * 100, ac.crashed ? "CRASHED" : (ac.onGround ? "LANDED" : "")))
            if ac.onGround { break }
        }
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--soundtest"), i + 1 < CommandLine.arguments.count {
    writeSoundTest(to: CommandLine.arguments[i + 1])
    exit(0)
}

// Test and check runs make no sound: they build many games in a row, each of which would otherwise start playing its
// idle engine and ambience through the speakers. Screenshots are silent too. (--perf keeps sound: it measures it.)
do {
    let quiet = CommandLine.arguments.dropFirst().contains { a in
        ["test", "check", "list", "stats", "crop"].contains { a.hasPrefix("--") && a.hasSuffix($0) } || ["--shot", "--flightsound", "--treehit"].contains(a)
    }
    if quiet && !CommandLine.arguments.contains("--perf") { SoundEngine.offline = true }
}

if CommandLine.arguments.contains("--hidtest") {
    // report what the controller code detects, then quit
    let input = InputManager()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    print("joysticks: \(input.hid.joysticks.count)  gamepad-class: \(input.hid.gamepads.count)  name: \(input.hid.name)  used as transmitter: \(input.hid.connected)")
    print("system game controllers: " + GCController.controllers().map { "\($0.vendorName ?? "?") extended=\($0.extendedGamepad != nil)" }.joined(separator: ", "))
    print("axes: " + input.hid.axes.map { String(format: "%+.2f", $0) }.joined(separator: " "))
    let c = input.poll(dt: 0.016, kind: .airplane)
    print(String(format: "channels: aileron %+.2f elevator %+.2f throttle %.2f rudder %+.2f  source: %@", c.aileron, c.elevator, c.throttle, c.rudder, input.source))
    exit(0)
}

/// Scripted manoeuvres that exercise the stall, spin and propeller effects, and print each aircraft's figures.
func runPhysicsTest() {
    let site = SiteSpec.all[0]
    let terrain = Terrain(site: site)
    func fly(_ ac: Aircraft, _ seconds: Float, _ c: (Float) -> Controls, each: (Float) -> Void = { _ in }) {
        for i in 0..<Int(seconds * 1000) {
            ac.step(dt: 0.001, c: c(Float(i) / 1000), terrain: terrain, wind: .zero, rollMu: site.rollMu)
            if i % 20 == 0 { each(Float(i) / 1000) }
        }
    }
    print("name                          mass  W/S g/dm2  T/W  stall km/h  Ipitch  Iroll  CG %MAC")
    for spec in AircraftLibrary.all where spec.kind == .airplane {
        let wingZ = spec.surfaces.filter { $0.isWing }.map { $0.pos.z - 0.25 * $0.chord }.min() ?? 0
        let rootChord = spec.surfaces.first { $0.isWing }?.chord ?? 0.2
        print(String(format: "%-28@ %5.2f  %6.0f   %4.2f   %5.0f     %6.3f %6.3f   %3.0f", spec.name as NSString, spec.mass, spec.mass / spec.wingArea * 10,
                     spec.thrustToWeight, spec.stallSpeed * 3.6, spec.inertia.x, spec.inertia.z, -wingZ / rootChord * 100))
    }
    for name in ["Skylark Trainer", "North American T-6 Texan", "P-51D Mustang", "Piper J-3 Cub", "Extra 300", "Flatty 3D"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        print("== \(name)")
        // 1. stalls the way a pilot meets them: hold height as the speed bleeds off, and when the wing lets go
        //    keep the stick where it is for two seconds. Power off, then with 60% power.
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        for power in [Float(0), 0.6] {
            ac.reset(pos: V3(0, 150, 0), heading: 0, speed: spec.stallSpeed * 1.5)
            var elevI: Float = 0, held: Float? = nil, tBreak: Float = 0
            var breakV: Float = 0, pitch0: Float = 0, y0: Float = 0, minPitch: Float = 9, maxBank: Float = 0, done = false
            fly(ac, 25, { t in
                var c = Controls(); c.throttle = power
                if let h = held { c.elevator = h; return c }
                elevI = clampf(elevI + 0.6 * (-ac.vel.y - (power > 0 ? -0.3 : 0)) * 0.001, -0.3, 1)
                c.elevator = clampf(elevI + 0.12 * -ac.vel.y - 0.15 * ac.omega.x, -1, 1)
                c.aileron = clampf(-1.5 * ac.roll, -0.3, 0.3)
                if ac.wingStall > 0.45 || (t > 3 && elevI >= 0.999) { held = c.elevator; tBreak = t; breakV = ac.airspeed; pitch0 = ac.pitch; y0 = ac.pos.y }
                return c
            }, each: { t in
                guard held != nil, !done else { return }
                if t - tBreak > 2 { done = true; print(String(format: "   stall %@: breaks at %.0f km/h (predicted %.0f) with the nose %.0f° up; in the next 2 s the nose reaches %.0f°, bank up to %.0f°, height lost %.0f m",
                                                   power > 0 ? "with power" : "power off ", breakV * 3.6, spec.stallSpeed * 3.6, pitch0 / deg, minPitch / deg, maxBank / deg, y0 - ac.pos.y)); return }
                minPitch = min(minPitch, ac.pitch); maxBank = max(maxBank, abs(ac.roll))
            })
            if !done { print("   stall \(power > 0 ? "with power" : "power off "): did not stall in 25 s — it has the power to hold height") }
        }
        // 2. spin: stall it, then full rudder and up elevator; then neutralise and count the recovery
        ac.reset(pos: V3(0, 250, 0), heading: 0, speed: spec.stallSpeed * 1.15)
        var yawTurned: Float = 0, startY: Float = 0
        fly(ac, 6, { t in
            var c = Controls(); c.elevator = 1; c.rudder = t > 1 ? 1 : 0; c.aileron = 0; return c
        }, each: { t in if t > 1 { yawTurned += abs(ac.q.act(ac.omega).y) * 0.02 } })
        let spinRate = abs(ac.q.act(ac.omega).y) / deg, sink = -ac.vel.y
        startY = ac.pos.y
        var recovered: Float = -1
        let spinSign: Float = ac.q.act(ac.omega).y < 0 ? -1 : 1
        fly(ac, 6, { _ in var c = Controls(); c.rudder = -0.6; c.elevator = -0.2; return c },
            each: { t in if recovered < 0 && ac.wingStall < 0.1 && ac.q.act(ac.omega).y * spinSign < 0.4 && t > 0.3 { recovered = t } })     // the rotation has stopped (the held rudder may then yaw it the other way)
        print(String(format: "   spin: turned %.1f times in 5 s, %.0f°/s, sinking %.0f m/s; recovery %@, height lost recovering %.0f m",
                     yawTurned / (2 * .pi), spinRate, sink, recovered < 0 ? "not within 6 s" : String(format: "%.1f s", recovered), startY - ac.pos.y))
        // 3. take-off run with the controls untouched: how far does it swing?
        ac.reset(pos: V3(0, ac.restHeight + 0.02, 0), heading: 0)
        fly(ac, 3.0, { _ in var c = Controls(); c.throttle = 1; return c })
        let hd = atan2(-ac.forward.x, -ac.forward.z) / deg
        print(String(format: "   take-off, hands off, 3 s at full throttle: heading swings %.0f° %@, bank %.0f°, speed %.0f km/h",
                     abs(hd), hd > 0 ? "left" : "right", ac.roll / deg, ac.airspeed * 3.6))
        // 4. battery: full throttle on the ground
        let ac2 = Aircraft(spec)
        ac2.reset(pos: V3(0, 100, 0), heading: 0, speed: spec.stallSpeed * 1.5)
        var t50: Float = 0
        fly(ac2, 40, { _ in var c = Controls(); c.throttle = 1; c.elevator = clampf(2 * (0 - ac2.pitch), -0.5, 0.5); c.aileron = clampf(-2 * ac2.roll, -0.5, 0.5); return c })
        t50 = ac2.battery
        print(String(format: "   battery after 40 s at full throttle in flight: %.0f%%  (shaft speed %.0f%% of static)", t50 * 100, ac2.levels[0] * 100))
    }
}

/// Tests of the ground, water, helicopter and weather models.
func runEnvTest() {
    func site(_ key: String) -> (SiteSpec, Terrain, Environment) {
        let s = SiteSpec.all.first { $0.key == key }!
        let t = Terrain(site: s); let e = Environment(); e.configure(s); e.obstacles = t.windObstacles
        return (s, t, e)
    }
    func plane(_ name: String) -> Aircraft { let a = Aircraft(AircraftLibrary.all.first { $0.name == name }!); a.unlimitedBattery = true; return a }
    // 1. water take-off
    do {
        let (_, terrain, env) = site("lake")
        for name in ["Beaver Floatplane", "Super Cub Floatplane", "Twin Otter Floatplane"] {
            let ac = plane(name)
            guard let p = terrain.waterStart(windFrom: env.windFrom) else { print("no water start found"); break }
            ac.reset(pos: p + V3(0, ac.restHeight - 0.05, 0), heading: -env.windFrom * deg)
            var rest: Float = 0, liftOff: Float = -1, run: Float = 0, hump: Float = 0
            for i in 0..<14000 {
                var c = Controls(); let t = Float(i) / 1000
                c.throttle = t > 2 ? 1 : 0
                c.elevator = t > 2 ? clampf(0.25 + 2 * (0.1 - ac.pitch), -0.3, 0.8) : 0
                c.aileron = clampf(-2 * ac.roll, -0.5, 0.5)
                ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
                if i == 1999 { rest = ac.pos.y - (terrain.site.waterLevel ?? 0) }
                if t > 2 && liftOff < 0 { hump = max(hump, ac.pitch); if !ac.onGround && ac.airspeed > 5 { liftOff = t - 2; run = distance(ac.pos, p) } }
            }
            print(String(format: "WATER %@: floats %.2f m above the surface at rest, %@, afterwards %.0f m up at %.0f km/h%@", name, rest,
                         liftOff < 0 ? "did not lift off in 12 s" : String(format: "airborne after %.1f s and %.0f m", liftOff, run),
                         ac.pos.y - (terrain.site.waterLevel ?? 0), ac.airspeed * 3.6, ac.crashed ? "  CRASHED" : ""))
        }
    }
    // 2. landing roll: touch down at 1.3 x stall speed and coast, then the same with brakes, on three surfaces
    for key in ["meadow", "lake", "snow"] {
        let (s, terrain, _) = site(key)
        var out = "ROLL \(s.displayName):"
        for brake in [Float(0), 1] {
            let ac = plane("Skylark Trainer")
            ac.reset(pos: V3(-60, ac.restHeight + 0.02, 0), heading: -.pi / 2, speed: ac.spec.stallSpeed * 1.2)
            var c = Controls(); c.brake = brake; c.elevator = -0.1
            var i = 0
            while i < 40000 && (length(ac.vel) > 0.3 || i < 500) { ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0); i += 1 }
            out += String(format: "  %@ %.0f m", brake > 0 ? "braked" : "coasting", ac.pos.x + 60)
        }
        print(out)
    }
    // 3. crosswind ground loop tendency: taildragger rolling at speed, kicked sideways
    for name in ["Skylark Trainer", "Piper J-3 Cub"] {
        let (_, terrain, _) = site("meadow")
        let ac = plane(name)
        ac.reset(pos: V3(-60, ac.restHeight + 0.02, 0), heading: -.pi / 2, speed: 9)
        ac.omega.y = 0.6
        for _ in 0..<4000 { ac.step(dt: 0.001, c: Controls(), terrain: terrain, wind: .zero, rollMu: 0) }
        let hd = atan2(-ac.forward.x, -ac.forward.z) / deg + 90
        print(String(format: "SWERVE %@: after a 35°/s yaw disturbance at 32 km/h, heading ends %.0f° off%@", name, abs(hd), ac.crashed ? " (tipped over)" : ""))
    }
    // 4. ground effect: fly level at a fixed height and attitude for 3 s; less drag near the ground keeps more speed
    do {
        let (_, terrain, _) = site("meadow")
        var res: [(Float, Float)] = []
        for h in [Float(40), 0.03] {
            let ac = plane("Stick 40")
            let y = h + ac.restHeight
            ac.reset(pos: V3(0, y, 0), heading: -.pi / 2, speed: ac.spec.stallSpeed * 1.5)
            ac.q = ac.q * simd_quatf(angle: 5 * deg, axis: V3(1, 0, 0))
            let q0 = ac.q
            var lift: Float = 0
            for i in 0..<3000 {
                let v0 = ac.vel.y
                ac.step(dt: 0.001, c: Controls(), terrain: terrain, wind: .zero, rollMu: 0)
                if i == 200 { lift = (ac.vel.y - v0) / 0.001 + gravity }
                ac.pos.y = y; ac.vel.y = 0; ac.q = q0; ac.omega = .zero       // hold height and attitude
            }
            res.append((ac.airspeed, lift))
        }
        print(String(format: "GROUND EFFECT low-wing Stick 40, held level at 5° nose-up for 3 s: speed left %.1f km/h at 40 m, %.1f km/h with the wheels just off the runway; lift %.2f g vs %.2f g",
                     res[0].0 * 3.6, res[1].0 * 3.6, res[0].1 / gravity, res[1].1 / gravity))
    }
    // 5. helicopter: vertical descent into vortex ring, then fly forward out of it
    do {
        let (_, terrain, _) = site("meadow")
        let ac = Aircraft(AircraftLibrary.all[4])
        ac.reset(pos: V3(0, 150, 0), heading: 0)
        var maxV: Float = 0, sinkIn: Float = 0, sinkOut: Float = 0
        for i in 0..<16000 {
            let t = Float(i) / 1000
            var c = Controls()
            let eb = simd_float3x3(ac.q).transpose * cross(ac.up, t < 9 ? V3(0, 1, 0) : normalize(V3(0, 1, -0.45)))
            c.elevator = clampf(eb.x * 6 / 5, -1, 1); c.aileron = clampf(-eb.z * 6 / 5, -1, 1)
            c.throttle = t < 3 ? 0.52 : (t < 9 ? 0.66 : 0.8)          // settle into a descent, then pull collective
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
            maxV = max(maxV, ac.vortexRing)
            if i == 8900 { sinkIn = -ac.vel.y }
            if i == 15900 { sinkOut = -ac.vel.y }
        }
        print(String(format: "VORTEX RING %@: depth %.0f%%; sinking %.1f m/s with hover collective held; %.1f m/s after flying forward out of it", ac.spec.name, maxV * 100, sinkIn, sinkOut))
    }
    // 6. weather: wind profile, turbulence strength, wake behind the clubhouse, thermals
    do {
        let (s, terrain, env) = site("meadow")
        env.windSpeed = 5; env.turbulence = 0
        let prof = [Float(0.3), 1, 2, 5, 10, 30, 100].map { String(format: "%.0f m: %.1f", $0, length(env.wind(at: V3(0, $0, -80), terrain: terrain))) }.joined(separator: ", ")
        print("WIND PROFILE (5 m/s at 10 m): " + prof)
        env.turbulence = 0.3
        func rms(_ p: V3) -> Float {
            var s2: Float = 0; var mean = V3.zero; var n: Float = 0
            var samples: [V3] = []
            for _ in 0..<20000 { env.advance(dt: 0.001, at: p, airspeed: 14, terrain: terrain); samples.append(env.wind(at: p, terrain: terrain)) }
            for v in samples { mean += v; n += 1 }; mean /= n
            for v in samples { s2 += length_squared(v - mean) }
            return sqrt(s2 / n)
        }
        let hw = s.runwayWid / 2
        let d = env.windVec / env.windSpeed
        let club = V3(-48, 2, hw + 34)
        print(String(format: "TURBULENCE (setting 30%%, wind 5 m/s): gust strength %.2f m/s in open air at 30 m, %.2f m/s at 3 m, %.2f m/s 15 m downwind of the clubhouse",
                     rms(V3(0, 30, -150)), rms(V3(0, 3, -150)), rms(club + d * 15)))
        env.thermalsOn = true; env.windSpeed = 0; env.turbulence = 0
        env.advance(dt: 0.001, at: .zero, airspeed: 10, terrain: terrain)
        var up: Float = -9, down: Float = 9
        for i in 0..<400 { let p = V3(Float(i % 20) * 40 - 400, 120, Float(i / 20) * 28 - 460); let w = env.wind(at: p, terrain: terrain).y; up = max(up, w); down = min(down, w) }
        print(String(format: "THERMALS at 120 m: strongest lift %.1f m/s, strongest sink %.1f m/s, %d active", up, down, env.thermals.count))
    }
}

/// Rudder check: yaw authority from the propeller blast alone (aircraft held nose-up and motionless at hover
/// power, or full power if it cannot hover) at a quarter, half and full rudder, plus the yaw rate in cruise.
func runRudderTest() {
    let terrain = Terrain(site: SiteSpec.all[0])
    print("name                            T/W   blast yaw accel deg/s2 at rudder        pitch accel   roll accel    blast share of speed on     cruise yaw")
    print("                                       25%      50%     100%                  100% elev     100% ail      inner wing  ailerons  tail   deg/s")
    for spec in AircraftLibrary.all where spec.kind == .airplane {
        let up = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
        let n = min(sqrt(spec.mass * gravity / spec.props[0].staticThrust / Float(spec.props.count)), 1)
        func accel(_ set: (inout Controls) -> Void) -> (V3, Float) {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0); ac.q = up
            for i in ac.levels.indices { ac.levels[i] = n }
            var c = Controls(); c.throttle = 0.82 * n + 0.18 * n * n; set(&c)
            for _ in 0..<400 { ac.vel = .zero; ac.omega = .zero; ac.q = up; ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0) }
            ac.omega = .zero; ac.vel = .zero
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
            let fin = spec.surfaces.firstIndex { $0.flapCh == 2 }
            return (ac.omega / 0.001 / deg, fin.map { ac.stallT[$0] } ?? 0)
        }
        let rest = accel { _ in }.0
        let q = accel { $0.rudder = 0.25 }, h = accel { $0.rudder = 0.5 }, f = accel { $0.rudder = 1 }
        let e = accel { $0.elevator = 1 }, a = accel { $0.aileron = 1 }
        let ail = spec.surfaces.filter { $0.isWing && $0.flapCh == 0 }, ailArea = ail.reduce(Float(0)) { $0 + $1.area }
        let ailWash = ailArea > 0 ? sqrt(ail.reduce(Float(0)) { $0 + $1.area * $1.wash * $1.wash } / ailArea) : 0
        let tailWash = spec.surfaces.first { !$0.isWing && $0.flapCh == 1 }?.wash ?? 0
        print(String(format: "%@ %4.2f  %6.0f   %6.0f   %6.0f          %6.0f        %6.0f          %4.2f       %4.2f    %4.2f    %5.0f", spec.name.padding(toLength: 30, withPad: " ", startingAt: 0),
                     spec.thrustToWeight, abs(q.0.y - rest.y), abs(h.0.y - rest.y), abs(f.0.y - rest.y), abs(e.0.x - rest.x), abs(a.0.z - rest.z),
                     spec.surfaces.first { $0.isWing }?.wash ?? 0, ailWash, tailWash, measureRates(spec).yaw))
    }

    // open loop: hanging on the propeller with no stick input, then a third rudder for 0.3 s. What actually moves?
    for name in ["Flatty 3D", "Foam Extra XL", "Vortex 3D"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        ac.reset(pos: V3(0, 100, 0), heading: 0); ac.q = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
        let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
        ac.levels[0] = n
        var c = Controls(); c.throttle = 0.82 * n + 0.18 * n * n
        for k in 0..<1300 {
            c.rudder = k >= 1000 ? 0.33 : 0
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
            if k == 999 || k == 1299 {
                let nose = ac.q.act(V3(0, 0, -1))
                print(String(format: "HOVER OPEN %@ %@: body rates pitch %5.0f, yaw %5.0f, roll %5.0f deg/s; nose %3.0f deg off vertical; momentum %.5f, inertia %.5f %.5f %.5f",
                             name as NSString, k == 999 ? "after 1 s hands off     " : "after 0.3 s of 33% rudder", ac.omega.x / deg, ac.omega.y / deg, ac.omega.z / deg, acos(clampf(nose.y, -1, 1)) / deg,
                             spec.props[0].momentum, spec.inertia.x, spec.inertia.y, spec.inertia.z))
            }
        }
    }
    // the way it is really flown: level flight, pull to the vertical, settle into a hover on the throttle with a gentle
    // pilot on elevator and aileron, rudder left alone; then half rudder for 0.4 s. How much does the nose answer?
    for name in ["Flatty 3D", "Foam Extra XL", "Vortex 3D"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        for sink in [Float(0), -2.5] {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0, speed: spec.stallSpeed * 1.8)
            let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
            var c = Controls(), yaw0: Float = 0, lean0: Float = 0, info = ""
            for k in 0..<7000 {
                let local = ac.q.inverse.act(V3(0, 1, 0))                    // straight up as the aircraft sees it
                let vertical = local.z < -0.8
                c.throttle = k < 500 ? 0.6 : clampf(0.82 * n + 0.18 * n * n - 0.25 * (ac.vel.y - sink), 0, 1)
                c.elevator = k < 500 ? 0 : clampf(0.9 * atan2(local.y, -local.z) - 0.08 * ac.omega.x, -1, 1)
                c.aileron = vertical ? clampf(0.3 * ac.omega.z, -1, 1) : clampf(-1.5 * ac.roll, -0.5, 0.5)
                c.rudder = k >= 5000 && k < 5400 ? 0.5 : (vertical && k < 5000 ? clampf(0.5 * local.x + 0.08 * ac.omega.y, -1, 1) : 0)
                ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
                if k == 4999 { yaw0 = ac.omega.y; lean0 = asin(clampf(local.x, -1, 1))
                    let fin = spec.surfaces.firstIndex { $0.flapCh == 2 }!
                    info = String(format: "before: nose %2.0f deg off vertical, climbing %4.1f m/s, shaft %3.0f%%, fin stall %.2f", acos(clampf(-local.z, -1, 1)) / deg, ac.vel.y, ac.levels[0] * 100, ac.stallT[fin]) }
                if k == 5399 { print(String(format: "HOVER FLOWN %@ (target climb %4.1f) %@; half rudder for 0.4 s: yaw rate %4.0f -> %4.0f deg/s, sideways lean %3.0f -> %3.0f deg",
                                           name.padding(toLength: 13, withPad: " ", startingAt: 0) as NSString, sink, info, yaw0 / deg, ac.omega.y / deg, lean0 / deg, asin(clampf(local.x, -1, 1)) / deg)) }
            }
        }
    }
    // hands off from a 6 degree lean: how fast does it get away in each axis?
    for name in ["Flatty 3D", "Foam Extra XL", "Vortex 3D"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        print("SURFACES \(name): " + spec.surfaces.filter { !$0.isWing }.map { String(format: "[n %.0f,%.0f z %.2f area %.3f wash %.2f]", $0.normal.x, $0.normal.y, $0.pos.z, $0.area, $0.wash) }.joined(separator: " "))
        for (yawAxis, variant) in [(true, 0), (false, 0), (true, 1), (true, 2), (true, 3), (true, 4)] {
            var spec = spec
            if variant == 1 { spec.props[0].momentum = 0 }
            if variant == 2 { for i in spec.surfaces.indices { spec.surfaces[i].swirl = 0 } }
            if variant == 3 { spec.props[0].axis = V3(0, 0, -1); spec.props[0].pos.x = 0; spec.props[0].pos.y = 0 }
            if variant == 4 { spec.props[0].torqueK = 0 }
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0)
            ac.q = simd_quatf(angle: 0.1, axis: yawAxis ? V3(0, 0, 1) : V3(1, 0, 0)) * simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
            let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
            ac.levels[0] = n
            var t30: Float = -1, t60: Float = -1
            for k in 0..<4000 {
                var c = Controls(); c.throttle = 0.82 * n + 0.18 * n * n; c.aileron = clampf(0.3 * ac.omega.z, -1, 1)
                ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
                let off = acos(clampf(ac.q.act(V3(0, 0, -1)).y, -1, 1))
                if name == "Vortex 3D" && (variant == 0 || variant == 2) && k % 100 == 0 && k < 400 { let fi = spec.surfaces.firstIndex { $0.flapCh == 2 }!; let va = ac.q.inverse.act(ac.vel)
                    print(String(format: "  t=%.2f off %4.1f  rates p %5.0f y %5.0f r %5.0f  body vel x %5.2f y %5.2f z %5.2f  fin stall %.2f", Float(k) / 1000, off / deg, ac.omega.x / deg, ac.omega.y / deg, ac.omega.z / deg, va.x, va.y, va.z, ac.stallT[fi])) }
                if t30 < 0 && off > 30 * deg { t30 = Float(k) / 1000 }
                if t60 < 0 && off > 60 * deg { t60 = Float(k) / 1000 }
            }
            print(String(format: "HOVER DIVERGE %@ lean in %@ %@: 30 deg off after %.1f s, 60 deg after %.1f s", name as NSString, yawAxis ? "yaw  " : "pitch", ["", "(no gyro)", "(no swirl)", "(straight thrust)", "(no torque)"][variant], t30, t60))
        }
    }
    // a human-like pilot: reacts 0.2 s late, in still air and in a light gusty wind. Which axis gets away?
    for name in ["Flatty 3D", "Foam Extra XL", "Vortex 3D"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        for (gain, windV, gyro) in [(Float(0.6), Float(0), Float(1)), (0.3, 0, 1), (0.15, 0, 1), (0.6, 0, 0), (0.3, 0, 0), (0.15, 0, 0), (0.3, 3, 1), (0.3, 3, 0)] {
            var spec = spec; spec.props[0].momentum *= gyro
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0); ac.q = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
            ac.q = simd_quatf(angle: 0.1, axis: V3(0, 0, 1)) * simd_quatf(angle: 0.1, axis: V3(1, 0, 0)) * ac.q       // start a little off
            let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
            ac.levels[0] = n
            var queue: [Controls] = []
            var worstPitch: Float = 0, worstYaw: Float = 0, t: Float = 8, rud: Float = 0, ele: Float = 0
            for k in 0..<8000 {
                var c = Controls()
                let local = ac.q.inverse.act(V3(0, 1, 0))
                c.throttle = clampf(0.82 * n + 0.18 * n * n - 0.3 * ac.vel.y, 0, 1)
                c.elevator = clampf(gain * local.y - 0.1 * gain * ac.omega.x, -1, 1)
                c.rudder = clampf(gain * local.x + 0.1 * gain * ac.omega.y, -1, 1)
                c.aileron = clampf(0.3 * ac.omega.z, -1, 1)
                queue.append(c)
                let use = queue.count > 200 ? queue.removeFirst() : Controls(throttle: c.throttle)
                let gust = windV * (1 + 0.4 * sin(Float(k) * 0.004) + 0.3 * sin(Float(k) * 0.011))
                ac.step(dt: 0.001, c: use, terrain: terrain, wind: V3(gust * 0.7, 0, gust * 0.7), rollMu: 0)
                worstPitch = max(worstPitch, abs(asin(clampf(local.y, -1, 1)))); worstYaw = max(worstYaw, abs(asin(clampf(local.x, -1, 1))))
                rud += abs(use.rudder); ele += abs(use.elevator)
                if local.z > -0.35 { t = Float(k) / 1000; break }
            }
            print(String(format: "HOVER HUMAN %@ gain %.2f wind %.0f gyro %.0f: %@; worst lean in pitch %2.0f deg, in yaw %2.0f deg; average elevator %2.0f%%, rudder %2.0f%%",
                         name.padding(toLength: 13, withPad: " ", startingAt: 0) as NSString, gain, windV, gyro, t < 8 ? String(format: "fell out after %.1f s", t) : "held 8 s", worstPitch / deg, worstYaw / deg, ele / (t * 1000) * 100, rud / (t * 1000) * 100))
        }
    }
    // a flown hover: a simple pilot holds the nose on the vertical with elevator and rudder, in still air and in wind
    // blowing across the fin. How far does the nose wander, and how much of the rudder does it take?
    for name in ["Flatty 3D", "Foam Extra XL", "Foam Bipe 3D", "Katana Foamy", "Vortex 3D", "Extra 300"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        for (windV, fromSide) in [(Float(0), true), (3, true), (5, true), (3, false), (5, false)] {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0); ac.q = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
            let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
            ac.levels[0] = n
            var worst: Float = 0, rudSum: Float = 0, rudMax: Float = 0, fell = false, eleSum: Float = 0, ailSum: Float = 0, rollMax: Float = 0
            for k in 0..<8000 {
                var c = Controls()
                let nose = ac.q.act(V3(0, 0, -1))
                let local = ac.q.inverse.act(V3(0, 1, 0))            // straight up, seen from the aircraft: x right, y canopy side
                c.throttle = clampf(0.82 * n + 0.18 * n * n - 0.3 * ac.vel.y - 0.1 * (ac.pos.y - 100), 0, 1)
                c.elevator = clampf(2.5 * local.y - 0.2 * ac.omega.x, -1, 1)
                c.rudder = clampf(2.5 * local.x + 0.2 * ac.omega.y, -1, 1)
                c.aileron = clampf(0.3 * ac.omega.z, -1, 1)                   // stop the torque roll
                let wv = windV * min(Float(k) / 1000, 1)
                ac.step(dt: 0.001, c: c, terrain: terrain, wind: fromSide ? V3(wv, 0, 0) : V3(0, 0, wv), rollMu: 0)
                let tilt = acos(clampf(nose.y, -1, 1))
                if k > 1500 { worst = max(worst, tilt); rudSum += abs(c.rudder); rudMax = max(rudMax, abs(c.rudder)); eleSum += abs(c.elevator); ailSum += abs(c.aileron); rollMax = max(rollMax, abs(ac.omega.z)) }
                if tilt > 1.2 { fell = true; break }
            }
            print(String(format: "HOVER HOLD %@ wind %.0f m/s %@: %@; nose up to %2.0f deg off vertical; average stick: rudder %3.0f%% (peak %3.0f%%), elevator %3.0f%%, aileron %3.0f%%; roll rate up to %3.0f deg/s",
                         name.padding(toLength: 13, withPad: " ", startingAt: 0) as NSString, windV, fromSide ? "on the fin " : "on the wing", fell ? "FELL OUT" : "held 8 s", worst / deg, rudSum / 6500 * 100, rudMax * 100, eleSum / 6500 * 100, ailSum / 6500 * 100, rollMax / deg))
        }
    }
}

/// Rotorcraft check: hover point, power, acro rates, control with the throttle closed, propwash, and for
/// helicopters the hover in each mode, flips and inverted flight.
func runRotorTest() {
    let terrain = Terrain(site: SiteSpec.all[0])
    func fly(_ ac: Aircraft, _ seconds: Float, _ c: (Float) -> Controls, each: (Float) -> Void = { _ in }) {
        for i in 0..<Int(seconds * 1000) { ac.step(dt: 0.001, c: c(Float(i) / 1000), terrain: terrain, wind: .zero, rollMu: 0); each(Float(i) / 1000) }
    }
    print("MULTIROTORS                 mass g  T/W   hover   climb    roll rate deg/s      full roll with      level-mode  propwash: sink m/s, lift lost,")
    print("                                          stick   m/s2     full stick  30% stick  throttle closed    km/h       wobble deg/s")
    for spec in AircraftLibrary.all where spec.kind == .multirotor {
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        let hov = spec.hoverThrottle
        func start() { ac.reset(pos: V3(0, 150, 0), heading: 0); for i in ac.levels.indices { ac.levels[i] = sqrt(spec.mass * gravity / (Float(spec.multi!.motors.count) * spec.multi!.maxThrust)) } }
        // punch out
        start(); var c = Controls(); c.mode = 1; c.throttle = hov
        fly(ac, 0.5) { _ in c }
        c.throttle = 1; fly(ac, 0.06) { _ in c }; let v0 = ac.vel.y; fly(ac, 0.1) { _ in c }
        let climb = (ac.vel.y - v0) / 0.1
        // roll rates
        func rollRate(_ stick: Float, thr: Float) -> Float {
            start(); var c = Controls(); c.mode = 1; c.throttle = hov
            fly(ac, 0.3) { _ in c }
            c.aileron = stick; c.throttle = thr
            var peak: Float = 0
            fly(ac, 0.6, { _ in c }, each: { _ in peak = max(peak, abs(ac.omega.z)) })
            return peak / deg
        }
        let full = rollRate(1, thr: hov), part = rollRate(0.3, thr: hov), closed = rollRate(1, thr: 0)
        // top speed: self-level, full forward stick, full throttle
        start(); c = Controls(); c.mode = 0; c.throttle = 1; c.elevator = -1
        var top: Float = 0
        fly(ac, 8, { _ in c }, each: { _ in top = max(top, sqrt(ac.vel.x * ac.vel.x + ac.vel.z * ac.vel.z)) })
        // propwash: let it sink straight down at hover throttle after a brief cut
        start(); c = Controls(); c.mode = 0
        var wash: Float = 0, wob: Float = 0
        fly(ac, 4, { t in c.throttle = t < 0.9 ? 0.0 : hov * 0.98; return c }, each: { t in if t > 1.5 { wash = max(wash, ac.vortexRing); wob = max(wob, abs(ac.omega.x) + abs(ac.omega.z)) } })
        print(String(format: "%@ %6.0f  %4.1f   %3.0f%%   %5.1f      %5.0f       %5.0f        %5.0f           %5.0f      %4.1f  %3.0f%%  %3.0f", spec.name.padding(toLength: 26, withPad: " ", startingAt: 0),
                     spec.mass * 1000, spec.thrustToWeight, hov * 100, climb, full, part, closed, top * 3.6, -ac.vel.y, wash * 100, wob / deg))
    }
    // direction check: stick forward (elevator -1) must tip the nose down and move the machine forward, in both modes
    for name in ["Quad X450", "Apex 5 Racer", "Kestrel 550"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        for mode in 0..<2 {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 150, 0), heading: 0); for i in ac.levels.indices { ac.levels[i] = spec.kind == .helicopter ? 1 : 0.5 }
            var c = Controls(); c.mode = mode; c.throttle = spec.kind == .helicopter ? 0.66 : spec.hoverThrottle; c.elevator = -0.3
            fly(ac, 0.6) { _ in c }
            let nose = ac.q.act(V3(0, 0, -1))
            print(String(format: "DIRECTION %@ mode %d, stick forward: nose %@ (%.0f deg), moving %@ at %.1f m/s", name, mode, nose.y < 0 ? "DOWN" : "UP", asin(clampf(nose.y, -1, 1)) / deg,
                         dot(ac.vel, V3(0, 0, -1)) > 0 ? "FORWARD" : "BACKWARD", abs(dot(ac.vel, V3(0, 0, -1)))))
        }
    }
    print("HELICOPTERS                 mass g  rotor m  hover stick: high low rotor climb m/s   flip deg/s  pirouette deg/s   inverted hover       head speed in a")
    print("                                                                      (full pitch)                                (acro, 3 s)          full-pitch climb")
    for spec in AircraftLibrary.all where spec.kind == .helicopter {
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        func hoverStick(_ mode: Int) -> Float {
            ac.reset(pos: V3(0, 150, 0), heading: 0); ac.levels[0] = 1
            var c = Controls(); c.mode = 1; c.rotorSpeed = mode; c.throttle = 0.7
            var integ = c.throttle
            fly(ac, 5) { _ in integ = clampf(integ - 0.4 * ac.vel.y * 0.001, 0, 1); c.throttle = clampf(integ - 0.08 * ac.vel.y, 0, 1); c.elevator = clampf(-2 * ac.pitch - 0.3 * ac.omega.x, -1, 1); c.aileron = clampf(-2 * ac.roll + 0.3 * ac.omega.z, -1, 1); return c }
            return integ
        }
        let h3 = hoverStick(2), hn = hoverStick(0)
        var c = Controls(); c.throttle = 1
        var droop: Float = 9
        ac.reset(pos: V3(0, 150, 0), heading: 0); ac.levels[0] = 1
        fly(ac, 3, { _ in c.elevator = clampf(-2 * ac.pitch - 0.3 * ac.omega.x, -1, 1); c.aileron = clampf(-2 * ac.roll + 0.3 * ac.omega.z, -1, 1); return c }, each: { t in if t > 1 { droop = min(droop, ac.levels[0]) } })
        let climb = ac.vel.y
        ac.reset(pos: V3(0, 150, 0), heading: 0); ac.levels[0] = 1
        c = Controls(); c.mode = 1; c.throttle = h3; c.aileron = 1
        var flip: Float = 0
        fly(ac, 0.8, { _ in c }, each: { _ in flip = max(flip, abs(ac.omega.z)) })
        ac.reset(pos: V3(0, 150, 0), heading: 0); ac.levels[0] = 1
        c = Controls(); c.mode = 1; c.throttle = h3; c.rudder = 1
        var piro: Float = 0
        fly(ac, 0.8, { _ in c }, each: { _ in piro = max(piro, abs(ac.omega.y)) })
        // inverted hover: start upside down on negative pitch and hold it
        ac.reset(pos: V3(0, 150, 0), heading: 0); ac.levels[0] = 1
        ac.q = simd_quatf(angle: .pi, axis: V3(0, 0, 1)) * ac.q
        var integ = 1 - h3, worst: Float = 0
        fly(ac, 3, { _ in
            integ = clampf(integ + 0.4 * ac.vel.y * 0.001, 0, 1)
            c = Controls(); c.mode = 1; c.throttle = clampf(integ + 0.08 * ac.vel.y, 0, 1)
            let up = ac.q.inverse.act(V3(0, -1, 0))             // straight down, as the machine sees it: should be its own up axis
            c.elevator = clampf(2 * up.z - 0.3 * ac.omega.x, -1, 1); c.aileron = clampf(2 * up.x + 0.3 * ac.omega.z, -1, 1); return c
        }, each: { _ in worst = max(worst, acos(clampf(-ac.q.act(V3(0, 1, 0)).y, -1, 1))) })
        print(String(format: "%@ %6.0f   %4.2f              %3.0f%%   %3.0f%%      %5.1f        %5.0f        %5.0f        sinks %4.1f m/s, off %2.0f deg     %3.0f%%", spec.name.padding(toLength: 26, withPad: " ", startingAt: 0),
                     spec.mass * 1000, spec.heli!.rotorR, h3 * 100, hn * 100, climb, flip / deg, piro / deg, -ac.vel.y, worst / deg, droop * 100))
    }
}

/// Handling diagnostics: control rates for every airplane, and the balance of forces in a prop-hang.
func runHandlingTest() {
    let terrain = Terrain(site: SiteSpec.all[0])
    print("name                            roll deg/s  pitch deg/s  yaw deg/s   (full stick at 1.6 x stall speed)")
    var rolls: [(String, Float)] = []
    for spec in AircraftLibrary.all where spec.kind == .airplane {
        let m = measureRates(spec)
        let r = m.roll, p = m.pitch, y = m.yaw
        rolls.append((spec.name, r))
        print(String(format: "%@  %6.0f      %6.0f      %6.0f        low rate %2.0f%% (roll %3.0f deg/s), expo %2.0f%%", spec.name.padding(toLength: 30, withPad: " ", startingAt: 0), r, p, y, spec.lowRate * 100, r * spec.lowRate, spec.expo * 100))
    }
    let sorted = rolls.sorted { $0.1 < $1.1 }
    print(String(format: "ROLL RATE RANGE: slowest %@ %.0f deg/s, fastest %@ %.0f deg/s", sorted.first!.0, sorted.first!.1, sorted.last!.0, sorted.last!.1))

    // prop-hang: nose straight up, motionless, thrust equal to weight. What does the aircraft do untouched, and how much can the controls push back?
    for name in ["Flatty 3D", "Vortex 3D", "Extra 300"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        func accel(_ c0: Controls) -> V3 {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 100, 0), heading: 0)
            ac.q = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0))
            let n = sqrt(spec.mass * gravity / spec.props[0].staticThrust)
            ac.levels[0] = n
            var c = c0; c.throttle = 0.82 * n + 0.18 * n * n            // throttle that holds this shaft speed
            for _ in 0..<60 { ac.vel = .zero; ac.omega = .zero; ac.q = simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0)); ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0) }
            ac.omega = .zero; ac.vel = .zero
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
            return ac.omega / 0.001 / deg
        }
        let rest = accel(Controls())
        var ca = Controls(); ca.aileron = 1; var ce = Controls(); ce.elevator = 1; var cr = Controls(); cr.rudder = 1
        let a = accel(ca) - rest, e = accel(ce) - rest, r = accel(cr) - rest
        print(String(format: "HOVER %@ (hover needs %.0f%% shaft speed): untouched it accelerates roll %.0f, pitch %.0f, yaw %.0f deg/s2; full stick can add roll %.0f, pitch %.0f, yaw %.0f deg/s2",
                     name, sqrt(spec.mass * gravity / spec.props[0].staticThrust) * 100, rest.z, rest.x, rest.y, abs(a.z), abs(e.x), abs(r.y)))
    }
    // continuous roll at speed: hold full aileron for three rolls and see how far the nose wanders off the direction of flight
    for name in ["Flatty 3D", "Vortex 3D", "Extra 300", "Skylark Trainer"] {
        guard let spec = AircraftLibrary.all.first(where: { $0.name == name }) else { continue }
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        ac.reset(pos: V3(0, 300, 0), heading: 0, speed: spec.stallSpeed * 2.6)
        var c = Controls(); c.throttle = 0.8
        for _ in 0..<400 { ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0) }
        let dir0 = normalize(V3(ac.vel.x, 0, ac.vel.z))
        c.aileron = 1
        var turns: Float = 0, cone: Float = 0, t: Float = 0
        while turns < 3 && t < 6 {
            ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
            turns += abs(ac.omega.z) * 0.001 / (2 * .pi); t += 0.001
            cone = max(cone, acos(clampf(dot(ac.forward, normalize(ac.vel)), -1, 1)) / deg)
        }
        let hv = normalize(V3(ac.vel.x, 0, ac.vel.z))
        print(String(format: "ROLLS %@: 3 rolls in %.1f s; nose up to %.0f° off the direction of flight; heading drifts %.0f°; height lost %.0f m",
                     name, t, cone, acos(clampf(dot(hv, dir0), -1, 1)) / deg, 300 - ac.pos.y))
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--pitchdebug"), i + 2 < CommandLine.arguments.count {
    // step response in pitch: aircraft name, elevator amount
    let spec = AircraftLibrary.all.first { $0.name == CommandLine.arguments[i + 1] }!
    let terrain = Terrain(site: SiteSpec.all[0])
    let ac = Aircraft(spec); ac.unlimitedBattery = true
    ac.reset(pos: V3(0, 200, 0), heading: 0, speed: spec.stallSpeed * 1.6)
    var c = Controls(); c.throttle = 0.5
    for k in 0..<1000 {
        if k == 300 { c.elevator = Float(CommandLine.arguments[i + 2]) ?? 0.2 }
        ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
        if k % 50 == 0 {
            let va = simd_float3x3(ac.q).transpose * ac.vel
            print(String(format: "t=%.2f pitch rate %6.0f deg/s  alpha %5.1f  speed %4.1f  wing stall %.2f  pitch %5.1f", Float(k) / 1000, ac.omega.x / deg, atan2(-va.y, -va.z) / deg, ac.airspeed, ac.wingStall, ac.pitch / deg))
        }
    }
    exit(0)
}

/// Balance and elevator check for every airplane.
func runBalanceTest() {
    let terrain = Terrain(site: SiteSpec.all[0])
    print("name                            design  actual margin      trim speed   full up elevator from cruise (1.7 x stall)   ...from fast (2.8 x stall)")
    print("                                margin  glide   60% power  (x stall)    peak rate  peak angle  peak g                peak rate  peak angle  peak g")
    var low: [String] = []
    for spec in AircraftLibrary.all where spec.kind == .airplane {
        let m0 = measuredMargin(spec, throttle: 0), m1 = measuredMargin(spec, throttle: 0.6)
        if min(m0, m1) < 0.04 { low.append(spec.name) }
        // speed at which it flies level hands-off: where the pitching moment is zero with lift equal to weight
        var trim: Float = 0
        for k in stride(from: Float(1.05), through: 4, by: 0.05) {
            let v = spec.stallSpeed * k
            // angle of attack for 1 g at this speed, by bisection
            var lo: Float = -4 * deg, hi: Float = 14 * deg
            for _ in 0..<12 { let mid = (lo + hi) / 2; if pitchBalance(spec, alpha: mid, speed: v, throttle: 0.4).lift < spec.mass * gravity { lo = mid } else { hi = mid } }
            if pitchBalance(spec, alpha: (lo + hi) / 2, speed: v, throttle: 0.4).moment >= 0 { trim = k; break }
        }
        func pull(_ k: Float) -> (Float, Float, Float) {
            let ac = Aircraft(spec); ac.unlimitedBattery = true
            ac.reset(pos: V3(0, 300, 0), heading: 0, speed: spec.stallSpeed * k)
            var c = Controls(); c.throttle = 0.5
            for _ in 0..<300 { ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0) }
            c.elevator = 1
            var rate: Float = 0, ang: Float = 0, g: Float = 0
            for _ in 0..<1200 {
                let v0 = ac.vel
                ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0)
                let va = simd_float3x3(ac.q).transpose * ac.vel
                rate = max(rate, ac.omega.x / deg); ang = max(ang, atan2(-va.y, -va.z) / deg)
                let acc = (ac.vel - v0) / 0.001 + V3(0, gravity, 0)
                g = max(g, dot(acc, ac.up) / gravity)
            }
            return (rate, ang, g)
        }
        let p1 = pull(1.7), p2 = pull(2.8)
        print(String(format: "%@ %5.0f%%  %5.0f%%  %5.0f%%     %@       %6.0f     %6.0f°    %5.1f                %6.0f     %6.0f°    %5.1f",
                     spec.name.padding(toLength: 30, withPad: " ", startingAt: 0), spec.designMargin * 100, m0 * 100, m1 * 100,
                     trim > 0 ? String(format: "%4.2f", trim) : "none", p1.0, p1.1, p1.2, p2.0, p2.1, p2.2))
    }
    print("MARGIN BELOW 4%: " + (low.isEmpty ? "none" : low.joined(separator: ", ")))
}

if CommandLine.arguments.contains("--ruddertest") { runRudderTest(); exit(0) }
if CommandLine.arguments.contains("--rotortest") { runRotorTest(); exit(0) }
if CommandLine.arguments.contains("--ambiencetest") { printAmbienceLevels(); exit(0) }
if CommandLine.arguments.contains("--touchtest") {
    // drop a trainer from knee height on every 3D site: it must report a touchdown, and the site says what it landed on
    let names = ["asphalt", "grass", "snow", "sand", "earth"]
    for site in SiteSpec.all where site.panorama == nil {
        let terrain = Terrain(site: site)
        let ac = Aircraft(AircraftLibrary.all[0])
        ac.reset(pos: V3(0, terrain.height(0, 0) + ac.restHeight + 0.5, 0), heading: 0)
        var hit: Float = 0, wheel = false
        for _ in 0..<1500 { ac.step(dt: 0.001, c: Controls(), terrain: terrain, wind: .zero, rollMu: site.rollMu); if ac.touchImpact > hit { hit = ac.touchImpact; wheel = ac.touchWheel } }
        print(String(format: "TOUCH %@: %.1f m/s on %@, runway %@, beside it %@", site.name.padding(toLength: 22, withPad: " ", startingAt: 0), hit, wheel ? "wheels" : "airframe",
                     names[terrain.groundKind(0, 0)], names[terrain.groundKind(0, site.runwayWid / 2 + 30)]))
    }
    exit(0)
}
if CommandLine.arguments.contains("--panostats") {
    // how sharp each installed panorama really is
    for site in SiteSpec.all {
        guard let url = site.panorama, let img = Panoramas.image(url, maxSize: 8192) else { continue }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        print(String(format: "%@ %d x %d  detail %.2f", url.lastPathComponent.padding(toLength: 32, withPad: " ", startingAt: 0), w, h, Panoramas.detail(px, width: w, height: h)))
    }
    exit(0)
}
if let ci = CommandLine.arguments.firstIndex(of: "--maskcheck"), ci + 1 < CommandLine.arguments.count {
    // every photo site: what counts as an object (red) and what as open sky, with the obstacles outlined
    let dir = URL(fileURLWithPath: CommandLine.arguments[ci + 1])
    let only = ci + 2 < CommandLine.arguments.count ? CommandLine.arguments[ci + 2] : ""
    for site in SiteSpec.all {
        guard let url = site.panorama, only.isEmpty || url.lastPathComponent.contains(only), let mask = PanoMask(url: url), let img = Panoramas.image(url, maxSize: 4096) else { continue }
        let W = 2160, top = 0.20, bottom = 0.58                         // the band of the picture around the horizon
        let H = Int(Double(W) / 2 * (bottom - top))
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
        let fullH = CGFloat(W) / 2
        ctx.draw(img, in: CGRect(x: 0, y: -(1 - CGFloat(bottom)) * fullH, width: CGFloat(W), height: fullH))
        let s = CGFloat(W) / CGFloat(mask.w)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 0.38))
        for y in Int(top * Double(mask.h))..<Int(bottom * Double(mask.h)) { for x in 0..<mask.w where mask.solid[y * mask.w + x] {
            ctx.fill(CGRect(x: CGFloat(x) * s, y: CGFloat(H) - (CGFloat(y) - CGFloat(top) * CGFloat(mask.h) + 1) * s, width: s, height: s))
        } }
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)); ctx.setLineWidth(2)
        for o in site.obstacles {
            let d = CGFloat(o.distance), hw = asin(min(CGFloat(Panoramas.solidRadius(o, at: 0)) / d, 1)) * 180 / .pi
            let hi = atan((CGFloat(o.height) - CGFloat(site.eyeHeight)) / d) * 180 / .pi
            for shift: CGFloat in [-360, 0, 360] {
                let x0 = (CGFloat(o.bearing) + shift - hw + 180) / 360 * CGFloat(W)
                let yTop = CGFloat(H) - ((0.5 - (hi + CGFloat(site.horizon)) / 180) - CGFloat(top)) * fullH
                let yHor = CGFloat(H) - (0.5 - CGFloat(top)) * fullH
                ctx.stroke(CGRect(x: x0, y: yHor, width: 2 * hw / 360 * CGFloat(W), height: yTop - yHor))
            }
        }
        if let out = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_mask.jpg") as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(d, out, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(d)
        }
        let band = (Int(0.25 * Double(mask.h))..<mask.h / 2).reduce(0) { n, y in n + (0..<mask.w).filter { mask.solid[y * mask.w + $0] }.count }
        print(String(format: "%@ %2.0f%% of the 45 degrees above the horizon holds something", url.lastPathComponent.padding(toLength: 30, withPad: " ", startingAt: 0),
                     Float(band) / Float(mask.w * (mask.h / 2 - Int(0.25 * Double(mask.h)))) * 100))
    }
    exit(0)
}
if let ci = CommandLine.arguments.firstIndex(of: "--musictest"), ci + 1 < CommandLine.arguments.count {
    // render 80 seconds of the menu music to a WAV file and report its level and how long it took
    let m = MusicSynth()
    var pcm: [Int16] = [], peak: Float = 0, sumSq: Double = 0, bad = false
    let t0 = Date(), total = 44100 * 80
    var quiet = 0, quietMax = 0
    for i in 0..<total {
        let s = m.next()
        if !s.0.isFinite || !s.1.isFinite { bad = true }
        peak = max(peak, abs(s.0), abs(s.1)); sumSq += Double(s.0 * s.0 + s.1 * s.1)
        if abs(s.0) < 0.002 && abs(s.1) < 0.002 { quiet += 1; quietMax = max(quietMax, quiet) } else { quiet = 0 }
        pcm.append(Int16(max(-1, min(1, s.0)) * 30000)); pcm.append(Int16(max(-1, min(1, s.1)) * 30000))
        if i % (44100 * 10) == 44100 * 10 - 1 { print(String(format: "  to %2d s: peak %.2f", (i + 1) / 44100, peak)) }
    }
    let took = Date().timeIntervalSince(t0)
    writeWav(pcm, sampleRate: 44100, to: CommandLine.arguments[ci + 1])
    print(String(format: "MUSIC 80 s: peak %.2f rms %.3f, longest silence %.2f s, %@; rendered in %.2f s (%.1f%% of real time)", peak, sqrt(sumSq / Double(total * 2)),
                 Float(quietMax) / 44100, bad ? "NON-FINITE SAMPLES" : "ok", took, took / 80 * 100))
    exit(0)
}
if CommandLine.arguments.contains("--obstaclelist") {
    // every photo site: how close the nearest solid thing is to the pilot and to the start, and how tall the tallest is
    for site in SiteSpec.all where site.panorama != nil {
        guard !site.obstacles.isEmpty else { print("\(site.displayName.padding(toLength: 30, withPad: " ", startingAt: 0)) no obstacles"); continue }
        let edge = site.obstacles.map { $0.distance - Panoramas.solidRadius($0, at: 0) }.min() ?? 0
        let start = site.obstacles.map { o -> Float in let c = Panoramas.position(o, north: site.north); return hypot(site.startX - c.x, site.startZ - c.y) - Panoramas.solidRadius(o, at: 0) }.min() ?? 0
        let within60 = site.obstacles.filter { $0.distance - Panoramas.solidRadius($0, at: 0) < 60 }.count
        print(String(format: "%@ %2d obstacles, nearest solid edge %5.1f m from the pilot, %5.1f m from the start; %2d within 60 m; tallest %4.1f m",
                     site.displayName.padding(toLength: 30, withPad: " ", startingAt: 0), site.obstacles.count, edge, start, within60, site.obstacles.map { $0.height }.max() ?? 0))
    }
    exit(0)
}
if let ci = CommandLine.arguments.firstIndex(of: "--panocrop"), ci + 4 < CommandLine.arguments.count {
    // a close look at part of a photo site: --panocrop <out.jpg> <file name part> <bearing from> <bearing to>
    // draws the ground at labelled distances and the obstacles, at high resolution, to judge how far things are
    let a = CommandLine.arguments
    guard let site = SiteSpec.all.first(where: { $0.panorama?.lastPathComponent.contains(a[ci + 2]) == true }), let url = site.panorama,
          let img = Panoramas.image(url, maxSize: 8192), let b0 = Double(a[ci + 3]), let b1 = Double(a[ci + 4]), b1 > b0 else { print("no such site"); exit(1) }
    let W = 1900, ppd = CGFloat(W) / CGFloat(b1 - b0)
    let top = CGFloat(b1 - b0) * 0.2, bottom = -CGFloat(b1 - b0) * 0.12
    let H = Int((top - bottom) * ppd)
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
    let eye = CGFloat(site.eyeHeight), hor = CGFloat(site.horizon), grad = site.groundGradient
    func ground(_ b: CGFloat, _ d: CGFloat) -> CGFloat { let t = Float(b - CGFloat(site.north)) * deg; return CGFloat(grad.x * sin(t) - grad.y * cos(t)) * d }
    func elev(_ b: CGFloat, _ d: CGFloat, _ h: CGFloat = 0) -> CGFloat { atan((ground(b, d) + h - eye) / d) * 180 / .pi }
    func X(_ b: CGFloat) -> CGFloat { (b - CGFloat(b0)) * ppd }
    func Y(_ el: CGFloat) -> CGFloat { CGFloat(H) - (top - el) * ppd }          // CoreGraphics origin is bottom-left
    // the photo: full image spans 360 x 180 degrees; place it so bearing b0 is at x = 0 and elevation `top` at the top
    for shift: CGFloat in [-360, 0, 360] {
        ctx.draw(img, in: CGRect(x: X(-180 + shift), y: Y(-90 - hor), width: 360 * ppd, height: 180 * ppd))
    }
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)); ctx.stroke(CGRect(x: 0, y: Y(0), width: CGFloat(W), height: 0))
    for r in [8, 12, 16, 20, 25, 30, 40, 50, 60, 80, 100, 150, 250] as [CGFloat] {
        ctx.setStrokeColor(CGColor(srgbRed: 0.1, green: 0.95, blue: 1, alpha: 0.85))
        ctx.beginPath()
        for i in 0...200 { let b = CGFloat(b0) + CGFloat(b1 - b0) * CGFloat(i) / 200; let pt = CGPoint(x: X(b), y: Y(elev(b, r))); if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) } }
        ctx.strokePath()
        let label = NSAttributedString(string: "\(Int(r)) m", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.yellow])
        let line = CTLineCreateWithAttributedString(label)
        for fx in [0.02, 0.5] as [CGFloat] { let b = CGFloat(b0) + CGFloat(b1 - b0) * fx; ctx.textPosition = CGPoint(x: X(b), y: Y(elev(b, r)) + 2); CTLineDraw(line, ctx) }
    }
    for o in site.obstacles {
        let d = CGFloat(o.distance), hw = asin(min(CGFloat(o.radius) / d, 1)) * 180 / .pi
        for shift: CGFloat in [-360, 0, 360] {
            let b = CGFloat(o.bearing) + shift
            // near edge on the ground, and the top
            let lo = elev(b, max(d - CGFloat(o.radius), 0.5)), hi = elev(b, d, CGFloat(o.height))
            let r = CGRect(x: X(b - hw), y: Y(lo), width: 2 * hw * ppd, height: (hi - lo) * ppd)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 0.22)); ctx.fill(r)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 1)); ctx.stroke(r)
            let label = NSAttributedString(string: String(format: "%.0f m, r %.0f, h %.0f", o.distance, o.radius, o.height), attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.white])
            ctx.textPosition = CGPoint(x: X(b - hw) + 3, y: Y(hi) - 14); CTLineDraw(CTLineCreateWithAttributedString(label), ctx)
        }
    }
    if let out = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[ci + 1]) as CFURL, "public.jpeg" as CFString, 1, nil) {
        CGImageDestinationAddImage(d, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary); CGImageDestinationFinalize(d)
    }
    print("\(url.lastPathComponent): bearings \(b0)...\(b1), \(Int(ppd)) px per degree, eye \(site.eyeHeight) m")
    exit(0)
}
if let ci = CommandLine.arguments.firstIndex(of: "--panocheck"), ci + 1 < CommandLine.arguments.count {
    // draw each photo site's invisible ground (rings), obstacles and start point onto its photo, to check them by eye
    let dir = URL(fileURLWithPath: CommandLine.arguments[ci + 1])
    let only = ci + 2 < CommandLine.arguments.count ? CommandLine.arguments[ci + 2] : ""
    let W = 1800, ppd = CGFloat(W) / 180, top: CGFloat = 24, bottom: CGFloat = -34
    let H = Int((top - bottom) * ppd)
    for site in SiteSpec.all {
        guard let url = site.panorama, only.isEmpty || url.lastPathComponent.contains(only), let img = Panoramas.image(url, maxSize: 4096) else { continue }
        guard let ctx = CGContext(data: nil, width: W, height: H * 2, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
        let hor = CGFloat(site.horizon), eye = CGFloat(site.eyeHeight)
        let grad = site.groundGradient
        /// Height of the ground at a photo bearing and distance.
        func ground(_ b: CGFloat, _ d: CGFloat) -> CGFloat {
            let a = Float(b - CGFloat(site.north)) * deg
            return CGFloat(grad.x * sin(a) - grad.y * cos(a)) * d
        }
        func elev(_ b: CGFloat, _ d: CGFloat, _ h: CGFloat = 0) -> CGFloat { atan((ground(b, d) + h - eye) / d) * 180 / .pi }
        for half in 0..<2 {
            ctx.saveGState()
            // flip to a top-left origin for this half
            ctx.translateBy(x: 0, y: CGFloat(half == 0 ? H * 2 : H)); ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H))
            func X(_ b: CGFloat) -> CGFloat { (b - CGFloat(half == 0 ? -180 : 0)) * ppd }
            func Y(_ el: CGFloat) -> CGFloat { (top - el) * ppd }
            // the photo: row of elevation el is at (90 - el - hor) degrees from its top
            ctx.saveGState()
            let y0 = -(90 - top - hor) * ppd, x0 = CGFloat(half == 0 ? 0 : -W)
            ctx.translateBy(x: x0, y: y0 + 180 * ppd); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(2 * W), height: 180 * ppd))
            ctx.restoreGState()
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.stroke(CGRect(x: 0, y: Y(0), width: CGFloat(W), height: 0))
            for (k, r) in [5, 10, 20, 40, 80, 160].enumerated() {
                ctx.setStrokeColor(CGColor(srgbRed: 0.1, green: 0.9, blue: 1, alpha: k % 2 == 0 ? 0.9 : 0.6))
                ctx.beginPath()
                for i in 0...180 {
                    let b = CGFloat(half == 0 ? -180 : 0) + CGFloat(i)
                    let pt = CGPoint(x: X(b), y: Y(elev(b, CGFloat(r))))
                    if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
                }
                ctx.strokePath()
            }
            for o in site.obstacles {
                let d = CGFloat(o.distance), hw = asin(min(CGFloat(o.radius) / d, 1)) * 180 / .pi
                let lo = elev(CGFloat(o.bearing), d), hi = elev(CGFloat(o.bearing), d, CGFloat(o.height))
                for shift: CGFloat in [-360, 0, 360] {
                    let r = CGRect(x: X(CGFloat(o.bearing) - hw + shift), y: Y(hi), width: 2 * hw * ppd, height: (hi - lo) * ppd)
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 0.3)); ctx.fill(r)
                    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 1)); ctx.stroke(r)
                }
            }
            // start point (yellow) and the direction straight ahead (green)
            let sx = CGFloat(site.startX), sz = CGFloat(site.startZ), sd = max(hypot(sx, sz), 0.5)
            var sb = atan2(sx, -sz) * 180 / .pi + CGFloat(site.north)
            sb = (sb + 540).truncatingRemainder(dividingBy: 360) - 180
            let fb = (CGFloat(site.north) + 540).truncatingRemainder(dividingBy: 360) - 180
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: X(sb) - 5, y: Y(elev(sb, sd)) - 5, width: 10, height: 10))
            // where the model heads from there (orange)
            let ha = Float(site.startHeading) * deg
            let ex = sx + CGFloat(sin(ha)) * 12, ez = sz - CGFloat(cos(ha)) * 12, ed = max(hypot(ex, ez), 0.5)
            var eb = atan2(ex, -ez) * 180 / .pi + CGFloat(site.north)
            eb = (eb + 540).truncatingRemainder(dividingBy: 360) - 180
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: X(eb) - 3, y: Y(elev(eb, ed)) - 3, width: 6, height: 6))
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 1, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: X(fb) - 2, y: Y(top), width: 4, height: 40))
            ctx.restoreGState()
        }
        guard let out = ctx.makeImage() else { continue }
        let dst = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".jpg")
        if let d = CGImageDestinationCreateWithURL(dst as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(d, out, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(d)
        }
        print(String(format: "%@ north %.0f horizon %.1f eye %.1f start (%.0f, %.0f) hdg %.0f, %d obstacles", url.lastPathComponent, site.north, site.horizon, site.eyeHeight,
                     site.startX, site.startZ, site.startHeading, site.obstacles.count))
    }
    exit(0)
}
if let ci = CommandLine.arguments.firstIndex(of: "--flightsound"), ci + 3 < CommandLine.arguments.count {
    // fly the demo pilot for 25 s, then dive in, and record what the game's own sound engine plays: --flightsound out.wav <site> <aircraft>
    SoundEngine.offline = true
    let sn = CommandLine.arguments[ci + 2], an = CommandLine.arguments[ci + 3]
    let g = Game(site: SiteSpec.all.firstIndex { $0.name.contains(sn) } ?? 0, aircraft: AircraftLibrary.all.firstIndex { $0.name.contains(an) } ?? 0)
    g.autopilotOn = true
    print("FLIGHTSOUND \(g.site.name), \(g.aircraft.spec.name)")
    let per = 735
    let l = UnsafeMutablePointer<Float>.allocate(capacity: per), r = UnsafeMutablePointer<Float>.allocate(capacity: per)
    var pcm: [Int16] = [], prev: Float = 0
    for f in 0..<(60 * 34) {
        if f == 60 * 20 { g.autopilotOn = false }           // throttle closed: glide
        if f == 60 * 25 { g.aircraft.pos.y = g.terrain.height(g.aircraft.pos.x, g.aircraft.pos.z) + 3; g.aircraft.vel = V3(9, -14, 0) }
        g.frame(dt: 1 / 60)
        g.sound.render(left: l, right: r, count: per)
        var jump: Float = 0, rms: Float = 0
        for i in 0..<per { jump = max(jump, abs(l[i] - prev)); prev = l[i]; rms += l[i] * l[i]
            pcm.append(Int16(max(-1, min(1, l[i])) * 32000)); pcm.append(Int16(max(-1, min(1, r[i])) * 32000)) }
        if f % 30 == 0 || jump > 0.5 {
            let st = g.sound.state
            print(String(format: "t=%5.2f agl %5.1f spd %4.1f %@ crashed %d  hz %5.1f power %.2f run %.0f gain %.2f reflect %.4f  touches %d  rms %.3f jump %.2f", Float(f) / 60,
                         g.aircraft.pos.y - g.terrain.height(g.aircraft.pos.x, g.aircraft.pos.z), length(g.aircraft.vel), g.aircraft.onGround ? "gnd" : "air", g.aircraft.crashed ? 1 : 0,
                         st.shaftHz, st.power, st.running, st.gain, st.reflect, g.sound.touchCount, (rms / Float(per)).squareRoot(), jump))
        }
    }
    writeWav(pcm, sampleRate: 44100, to: CommandLine.arguments[ci + 1])
    exit(0)
}
if CommandLine.arguments.contains("--powerlist") {
    // what drives every aircraft, as shown in the aircraft browser
    for a in AircraftLibrary.all { print("\(a.category.padding(toLength: 17, withPad: " ", startingAt: 0)) \(a.name.padding(toLength: 32, withPad: " ", startingAt: 0)) \(a.powerPlant)") }
    exit(0)
}
if CommandLine.arguments.contains("--glidetest") {
    // every airplane, throttle closed and hands off: the speed it settles at, and the up elevator a slow approach takes
    let terrain = Terrain(site: SiteSpec.all[0])
    print("category          name                            margin  hands-off glide   up elevator to hold")
    print("                                                  (glide)  (x stall)        1.2 x stall  1.1 x stall")
    for spec in AircraftLibrary.all where spec.kind == .airplane {
        let ac = Aircraft(spec); ac.unlimitedBattery = true
        ac.reset(pos: V3(0, 400, 0), heading: 0, speed: spec.stallSpeed * 1.5)
        let c = Controls()
        var sum: Float = 0, n: Float = 0
        for i in 0..<14000 { ac.step(dt: 0.001, c: c, terrain: terrain, wind: .zero, rollMu: 0); if i >= 9000 { sum += length(ac.vel); n += 1 } }
        func elev(_ k: Float) -> Float {
            let v = spec.stallSpeed * k
            var lo: Float = -4 * deg, hi: Float = 16 * deg
            for _ in 0..<12 { let mid = (lo + hi) / 2; if pitchBalance(spec, alpha: mid, speed: v, throttle: 0).lift < spec.mass * gravity { lo = mid } else { hi = mid } }
            let a = (lo + hi) / 2
            let m0 = pitchBalance(spec, alpha: a, speed: v, throttle: 0).moment, m1 = pitchBalance(spec, alpha: a, speed: v, throttle: 0, elevator: 0.5).moment
            return abs(m1 - m0) > 1e-6 ? -m0 / (m1 - m0) * 0.5 : 0
        }
        print(String(format: "%@ %@ %4.0f%%     %5.2f          %5.0f%%       %5.0f%%", spec.category.padding(toLength: 17, withPad: " ", startingAt: 0),
                     spec.name.padding(toLength: 30, withPad: " ", startingAt: 0), measuredMargin(spec, throttle: 0) * 100, sum / n / spec.stallSpeed, elev(1.2) * 100, elev(1.1) * 100))
    }
    exit(0)
}
if CommandLine.arguments.contains("--parktest") {
    // every photo site: the model must sit still on the ground where it starts, clear of every obstacle
    var bad = 0, keep: [Game] = []
    for (i, site) in SiteSpec.all.enumerated() where site.panorama != nil {
        var worst: Float = 0, note = ""
        for ac in [0, 20, 60, 110, 150, 170] where ac < AircraftLibrary.all.count {
            let g = Game(site: i, aircraft: ac); keep.append(g)
            let p0 = g.aircraft.pos
            for _ in 0..<360 { g.frame(dt: 1 / 60) }
            let p = g.aircraft.pos, moved = length(p - p0), above = p.y - g.terrain.height(p.x, p.z)
            if g.aircraft.spec.handLaunch { continue }
            worst = max(worst, moved)
            if g.aircraft.crashed { note += " CRASHED(\(g.aircraft.spec.name))" }
            if above > g.aircraft.restHeight + 0.3 || above < -0.05 { note += String(format: " height %.2f (%@)", above, g.aircraft.spec.name) }
            for o in site.obstacles {
                let c = Panoramas.position(o, north: site.north)
                let d = hypot(p0.x - c.x, p0.z - c.y) - o.radius
                if d < 3 { note += String(format: " obstacle %.1f m from start", d) ; break }
            }
        }
        let ok = worst < 0.6 && note.isEmpty
        if !ok { bad += 1 }
        print(String(format: "PARK %@ slope %.1f  moved %.2f m %@%@", site.name.padding(toLength: 30, withPad: " ", startingAt: 0), site.slope, worst, ok ? "ok" : "FAIL", note))
    }
    print(bad == 0 ? "PARK all ok" : "PARK \(bad) sites failed")
    exit(0)
}
if CommandLine.arguments.contains("--balancetest") {
    runBalanceTest()
    exit(0)
}

if CommandLine.arguments.contains("--handlingtest") {
    let t0 = Date(); _ = AircraftLibrary.all.count
    print(String(format: "LIBRARY built and calibrated in %.2f s", Date().timeIntervalSince(t0)))
    runHandlingTest()
    exit(0)
}

if CommandLine.arguments.contains("--envtest") {
    runEnvTest()
    exit(0)
}

if CommandLine.arguments.contains("--physicstest") {
    runPhysicsTest()
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
    runAutorotationTest()
    exit(0)
}

if let ti = CommandLine.arguments.firstIndex(of: "--formtrace"), ti + 2 < CommandLine.arguments.count {
    let g = Game(site: 0, aircraft: Int(CommandLine.arguments[ti + 1]) ?? 0)
    g.aiPartners = true; g.unlimitedBattery = true
    if CommandLine.arguments[ti + 2] == "1" { g.leadEpoch = 1; g.autopilotOn = true }
    for f in 0..<(60 * 120) {
        g.frame(dt: 1 / 60)
        if CommandLine.arguments.contains("--finewing"), f > 2400, f < 3000, f % 12 == 0, let w = g.wingmen.first(where: { $0.id != g.leadID }) {
            let a = w.aircraft
            print(String(format: "  %.1f roll %+.2f p %+.2f yawrate %+.2f pitch %+.2f ail %+.2f ele %+.2f thr %.2f v %.1f track %+.2f hdg %+.2f stall %.2f slip %+.2f", Float(f) / 60, a.roll, -a.omega.z, a.omega.y, a.pitch,
                         w.controls.aileron, w.controls.elevator, w.controls.throttle, a.airspeed, atan2(a.vel.x, -a.vel.z), atan2(a.forward.x, -a.forward.z), a.wingStall,
                         asin(clampf(dot(normalize(a.vel), a.right), -1, 1))))
        }
        if CommandLine.arguments.contains("--fine"), f > 600, f < 1200, f % 12 == 0, let w = g.wingmen.first(where: { $0.id == g.leadID }) {
            let a = w.aircraft
            print(String(format: "  %.1f roll %+.2f p %+.2f yawrate %+.2f pitch %+.2f ail %+.2f ele %+.2f thr %.2f v %.1f hdg %+.2f stall %.2f slip %+.2f", Float(f) / 60, a.roll, -a.omega.z, a.omega.y, a.pitch,
                         w.controls.aileron, w.controls.elevator, w.controls.throttle, a.airspeed, atan2(a.forward.x, -a.forward.z), a.wingStall,
                         asin(clampf(dot(normalize(a.vel), a.right), -1, 1))))
        }
        guard f % 120 == 0, let lead = g.flying(g.leadID) else { continue }
        var line = String(format: "t %3d lead %@ (%4.0f %3.0f %4.0f) v %4.1f roll %+.2f%@", f / 60, g.name(of: g.leadID), lead.pos.x, lead.pos.y, lead.pos.z, length(lead.vel), lead.roll, lead.crashed ? " CRASHED" : "")
        let (fw, r) = Formation.frame(of: lead)
        for (k, id) in g.order.enumerated() where k >= 1 {
            guard let w = g.wingmen.first(where: { $0.id == id }), let sl = g.slot(k) else { continue }
            let e = sl - w.aircraft.pos
            line += String(format: " | #%d right %+6.1f up %+6.1f ahead %+6.1f v %4.1f thr %.2f roll %+.2f%@", k + 1, dot(e, r), e.y, dot(e, fw), w.aircraft.airspeed, w.controls.throttle, w.aircraft.roll, w.aircraft.crashed ? " CRASHED" : "")
        }
        print(line)
    }
    exit(0)
}
if CommandLine.arguments.contains("--formtest") {
    // Computer partners, flown headless: how closely they hold their slots behind a computer lead, and behind
    // this pilot's own wing on its autopilot.
    for (i, spec) in AircraftLibrary.all.enumerated() {
        for mode in 0..<2 {
            let g = Game(site: 0, aircraft: i)
            g.aiPartners = true; g.unlimitedBattery = true
            if mode == 1 { g.leadEpoch = 1; g.autopilotOn = true }
            var sum: Float = 0, n: Float = 0, worst: Float = 0, crashes = 0
            var was = [UInt32: Bool]()
            for f in 0..<(60 * 150) {
                g.frame(dt: 1 / 60)
                for (k, id) in g.order.enumerated() {
                    guard let w = g.wingmen.first(where: { $0.id == id }) else { continue }
                    if w.aircraft.crashed && was[id] != true { crashes += 1 }
                    was[id] = w.aircraft.crashed
                    guard k >= 1, f > 60 * 45, !w.aircraft.crashed, let sl = g.slot(k) else { continue }
                    let e = distance(sl, w.aircraft.pos)
                    sum += e * e; n += 1; worst = max(worst, e)
                }
            }
            let lead = g.flying(g.leadID)
            print(String(format: "FORM %-24@ %@  slot rms %5.2f m  worst %6.2f m  crashes %d  lead %.0f m up at %.0f m/s  spacing %.1f m", spec.name as NSString,
                         mode == 0 ? "computer lead" : "autopilot lead", n > 0 ? sqrt(sum / n) : -1, worst, crashes,
                         (lead?.pos.y ?? 0) - g.terrain.pilotPos.y, lead?.airspeed ?? 0, g.spacingMetres))
            fflush(stdout)
        }
    }
    exit(0)
}

// MARK: - Application

final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?
    convenience init(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = [.command], _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mods
        target = self
        self.handler = handler
    }
    @objc private func fire() { handler?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var windowedFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)

    /// Cover the whole screen, or go back to a normal window. Instant: no system animation.
    func setFullScreen(_ on: Bool) {
        guard let w = window as? FlightWindow, on != w.covers else { return }
        if on {
            windowedFrame = w.frame
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
            w.covers = true
            w.setFrame((w.screen ?? NSScreen.main)?.frame ?? windowedFrame, display: true)
        } else {
            w.covers = false
            NSApp.presentationOptions = []
            w.setFrame(windowedFrame, display: true)
        }
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = on }
        w.isMovable = !on
        game.hud.fullscreen = on
    }
    var game: Game!
    var renderer: Renderer!
    var setupWindow: NSWindow?

    func arg(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        var siteArg = Int(arg("--site") ?? "") ?? 0
        if let p = arg("--pano") { SiteSpec.all.append(Panoramas.site(for: URL(fileURLWithPath: p))); siteArg = SiteSpec.all.count - 1 }
        var acArg = Int(arg("--aircraft") ?? "") ?? 0
        let interactive = CommandLine.arguments.count == 1          // launched normally, not by a test command line
        if interactive {
            // restore the last aircraft and site
            if let n = UserDefaults.standard.string(forKey: "lastAircraft"), let i = AircraftLibrary.all.firstIndex(where: { $0.name == n }) { acArg = i }
            if let n = UserDefaults.standard.string(forKey: "lastSite"), let i = SiteSpec.all.firstIndex(where: { $0.name == n }) { siteArg = i }
        }
        game = Game(site: siteArg, aircraft: acArg)
        game.netAllowed = interactive || CommandLine.arguments.contains("--net")
        if let n = arg("--name") { game.pilotName = n }
        if CommandLine.arguments.contains("--noai") { game.aiPartners = false }
        if CommandLine.arguments.contains("--lead") { game.leadEpoch = 1 }
        if let f = Int(arg("--formation") ?? ""), let k = FormationKind(rawValue: f) { game.formation = k }
        if CommandLine.arguments.contains("--joinup") { for _ in 0..<600 { game.frame(dt: 1 / 60) }; game.joinUp(quiet: true) }
        if CommandLine.arguments.contains("--menu") { game.hud.overlay = .menu }
        if interactive || CommandLine.arguments.contains("--splash") { game.hud.overlay = .splash }
        if let o = arg("--overlay") { game.hud.overlay = ["aircraft": .aircraft, "sites": .sites, "environment": .environment, "help": .help, "menu": .menu, "splash": .splash, "formation": .formation][o] ?? .none }
        game.hud.openControllerSetup = { [unowned self] in self.showSetup() }
        if let c = Int(arg("--cam") ?? "") { game.cameraMode = c }
        if let z = Int(arg("--zoom") ?? "") { game.zoomMode = z }
        if let t = Int(arg("--tod") ?? "") { game.timeOfDay = t }
        if CommandLine.arguments.contains("--auto") { game.autopilotOn = true }
        if CommandLine.arguments.contains("--balloons") { game.toggleChallenge() }
        let args = CommandLine.arguments
        if args.contains("--smoke") { game.smokeOn = true }
        if let q = Int(arg("--quality") ?? "") { game.quality = q }
        if args.contains("--obstacles") { game.showObstacles = true }
        if let c = arg("--view")?.split(separator: ",").compactMap({ Float($0) }), c.count == 6 { game.fixedView = (V3(c[0], c[1], c[2]), V3(c[3], c[4], c[5])) }
        if let c = arg("--closeup")?.split(separator: ",").compactMap({ Float($0) }), c.count == 3 { game.closeup = V3(c[0], c[1], c[2]) }
        if args.contains("--gearup") { game.gearUp = true }
        if args.contains("--flaps") { game.flapSetting = 1 }
        if let ff = Float(arg("--ff") ?? "") { for _ in 0..<Int(ff * 60) { game.frame(dt: 1 / 60) } }
        if args.contains("--treehit") {     // test hook: fly into the first tree of a photo site
            if let url = game.site.panorama { game.panoMask = PanoMask(url: url) }
            let eyePos = game.terrain.pilotPos + V3(0, game.site.eyeHeight, 0)
            if let o = game.site.obstacles.first(where: { $0.height > 6 }) {
                let c = Panoramas.position(o, north: game.site.north)
                let away = normalize(V3(c.x, 0, c.y))
                // approach from the pilot's side at a height where the picture shows the tree
                var hgt = o.height * 0.5
                for k in stride(from: Float(0.2), through: 1.2, by: 0.1) {
                    let probe = V3(c.x, game.terrain.height(c.x, c.y) + o.height * k, c.y) - away * (o.radius * 0.5)
                    if game.panoMask?.isSolid(probe - eyePos, north: game.site.north, horizon: game.site.horizon) == true { hgt = o.height * k; break }
                }
                let from = V3(c.x, game.terrain.height(c.x, c.y) + hgt, c.y) - away * (o.radius * 0.75 + 4)
                game.aircraft.reset(pos: from, heading: atan2(-away.x, -away.z), speed: 12)
                var frames = 0
                while frames < 120 && !game.aircraft.crashed { game.frame(dt: 1 / 60); frames += 1 }
                print(String(format: "TREEHIT %@: tree %.0f m away, %.0f m tall; %@ after %.2f s at %.1f m up; %d particles", game.site.displayName, o.distance, o.height,
                             game.aircraft.crashed ? "hit" : "NOT hit", Float(frames) / 60, game.aircraft.pos.y - game.terrain.height(c.x, c.y), game.particles.count))
                for _ in 0..<18 { game.frame(dt: 1 / 60) }
            }
        }
        if args.contains("--crash") {       // test hook: dive into the ground
            game.aircraft.pos.y = game.terrain.height(game.aircraft.pos.x, game.aircraft.pos.z) + 2.5
            game.aircraft.vel = V3(9, -14, 0)
            for _ in 0..<40 { game.frame(dt: 1 / 60) }
        }

        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = FlightWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "FormationFlightX"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.76, green: 0.13, blue: 0.1, alpha: 1)
        window.minSize = NSSize(width: 1000, height: 640)
        window.center()
        window.collectionBehavior = [.fullScreenNone]
        let container = NSView(frame: frame)
        container.wantsLayer = true
        let mtk = MTKView(frame: frame)
        mtk.autoresizingMask = [.width, .height]
        guard let r = Renderer(view: mtk, game: game) else {
            let a = NSAlert(); a.messageText = "Metal is not available on this Mac."; a.runModal(); NSApp.terminate(nil); return
        }
        renderer = r
        if let shot = arg("--shot") {
            mtk.framebufferOnly = false
            r.shotPath = shot
            r.shotAfter = Double(arg("--after") ?? "") ?? 1.5
        }
        mtk.delegate = r
        container.addSubview(mtk)
        let hud = NSHostingView(rootView: HUDView(m: game.hud))
        hud.frame = frame
        hud.autoresizingMask = [.width, .height]
        container.addSubview(hud)
        window.contentView = container
        // Full screen without macOS's own full-screen mode: that one slides the whole screen sideways into a new
        // Space, which takes a second and is what made opening the app slow. Here the window simply covers the
        // screen, with the menu bar and Dock tucked away, at once.
        game.hud.splashGo = true
        window.makeKeyAndOrderFront(nil)
        if interactive || CommandLine.arguments.contains("--fullscreen") { setFullScreen(true) }
        NSApp.activate(ignoringOtherApps: true)
        buildMenus()
        if CommandLine.arguments.contains("--setup") { showSetup() }
        if CommandLine.arguments.contains("--perf") {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
                let iv = self.renderer.statIntervals.sorted(), cpu = self.renderer.statCpu.sorted()
                let pr = self.renderer.statPresented.sorted(); self.renderer.statPresented = []
                self.renderer.statIntervals = []; self.renderer.statCpu = []
                print(self.game.sound.stats())
                guard iv.count > 4, cpu.count > 4 else { return }
                let med = iv[iv.count / 2]; _ = med
                let late = iv.filter { $0 > med * 1.5 }.count
                let jitter = iv.map { abs($0 - med) }.reduce(0, +) / Float(iv.count)
                let lateOnScreen = pr.filter { $0 > 25 }.count
                let adv = self.game.advanceMs.sorted(); self.game.advanceMs = []
                if adv.count > 10 { print(String(format: "MOTION per-frame advance min %.2f max %.2f ms (spread %.2f ms)", adv[1], adv[adv.count - 2], adv[adv.count - 2] - adv[1])) }
                print(String(format: "PERF frames %d  on-screen %d late %d max %.1f ms | callback late %d jitter %.2f ms  cpu med %.1f max %.1f ms  gpu %.1f ms  scale %.2f  screen %d Hz",
                             iv.count, pr.count, lateOnScreen, pr.last ?? 0, late, jitter, cpu[cpu.count / 2], cpu.last!, self.game.gpuMs, self.game.renderScale, NSScreen.main?.maximumFramesPerSecond ?? 0)); fflush(stdout)
            }
        }
        if CommandLine.arguments.contains("--netlog") {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [unowned self] _ in
                let g = self.game!, now = CACurrentMediaTime()
                var line = "NET \(g.pilotName) [\(g.net.status)] lead \(g.name(of: g.leadID)) site \(g.siteIndex)"
                for w in g.wingmen { line += String(format: " | %@ %@ %.0f m away%@", w.name, w.present(now) ? "flying" : "absent", distance(w.aircraft.pos, g.aircraft.pos), w.ai != nil ? " (computer)" : "") }
                if let e = g.slotError { line += String(format: " | slot error %.1f m", length(e)) }
                print(line); fflush(stdout)
            }
        }
        if CommandLine.arguments.contains("--printwin") { print("WINDOW \(window.windowNumber)"); fflush(stdout) }

        // the mouse pointer gets out of the way after five seconds without the mouse being touched, and comes
        // back the moment it moves; only while the flight window itself is in front
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [unowned self] _ in
            guard NSApp.isActive, self.window.isKeyWindow else { return }
            let kinds: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged, .scrollWheel]
            let idle = kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
            if idle >= 5 { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [unowned self] e in
            guard e.window === self.window else { return e }
            // while a menu or browser is open the keyboard belongs to it; Esc steps back
            if self.game.hud.overlay == .splash {
                if e.type == .keyDown { self.game.hud.overlay = .menu }
                return nil
            }
            if self.game.hud.overlay != .none {
                if e.type == .keyDown && e.keyCode == 53 {
                    let o = self.game.hud.overlay
                    self.game.hud.overlay = o != .menu && self.game.cameFromMenu ? .menu : .none
                    return nil
                }
                if self.game.simHeld || self.game.hud.overlay == .help { self.game.input.keys.removeAll(); return e }
            } else if e.type == .keyDown && !e.modifierFlags.contains(.command) {
                if e.keyCode == 53 { self.game.cameFromMenu = false; self.game.hud.overlay = .menu; return nil }
                if e.keyCode == 48 { self.game.cameFromMenu = false; self.game.hud.overlay = .aircraft; return nil }
            }
            if e.type == .flagsChanged {
                if e.modifierFlags.contains(.shift) { self.game.input.keys.insert(56) } else { self.game.input.keys.remove(56); self.game.input.keys.remove(60) }
                return e
            }
            if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { return e }
            if e.type == .keyDown {
                if !e.isARepeat { self.game.input.keys.insert(e.keyCode); self.game.keyDown(e.keyCode) }
                else if e.keyCode == 24 || e.keyCode == 27 { self.game.keyDown(e.keyCode) }          // trim keys repeat while held
            } else {
                self.game.input.keys.remove(e.keyCode)
            }
            return nil
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [unowned self] _ in
            self.game.input.keys.removeAll()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenus() {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach { m.addItem($0) }
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = m
            main.addItem(top)
        }
        let g = game!
        menu("FormationFlightX", [
            ClosureMenuItem("About FormationFlightX") { NSApp.orderFrontStandardAboutPanel(nil) },
            .separator(),
            ClosureMenuItem("Hide FormationFlightX", key: "h") { NSApp.hide(nil) },
            ClosureMenuItem("Quit FormationFlightX", key: "q") { NSApp.terminate(nil) },
        ])
        var acItems: [NSMenuItem] = AircraftLibrary.all.enumerated().map { i, sp in ClosureMenuItem(sp.name, key: i < 9 ? "\(i + 1)" : "") { g.selectAircraft(i) } }
        acItems.insert(ClosureMenuItem("Choose Wing…", key: "a", mods: [.command, .shift]) { g.cameFromMenu = false; g.hud.overlay = .aircraft }, at: 0)
        acItems.insert(.separator(), at: 1)
        acItems.append(.separator())
        acItems.append(ClosureMenuItem("Next Wing", key: "]") { g.keyDown(30) })
        acItems.append(ClosureMenuItem("Previous Wing", key: "[") { g.keyDown(33) })
        menu("Wing", acItems)
        var siteItems: [NSMenuItem] = SiteSpec.all.enumerated().map { i, sp in ClosureMenuItem(sp.displayName) { g.chooseSite(i) } }
        siteItems.insert(ClosureMenuItem("Choose Flying Site…", key: "s", mods: [.command, .shift]) { g.cameFromMenu = false; g.hud.overlay = .sites }, at: 0)
        siteItems.insert(.separator(), at: 1)
        menu("Flying Site", siteItems)
        var formItems: [NSMenuItem] = [
            ClosureMenuItem("Formation and Pilots…", key: "f", mods: [.command, .shift]) { g.cameFromMenu = g.hud.overlay == .menu; g.hud.overlay = .formation },
            .separator(),
            ClosureMenuItem("Join Up on the Lead", key: "j") { g.keyDown(38) },
            ClosureMenuItem("Take the Lead / Hand It Back", key: "u") { g.takeLead() },
            ClosureMenuItem("Computer Partners On / Off") { g.keyDown(5) },
            .separator(),
        ]
        formItems += FormationKind.allCases.map { k in ClosureMenuItem(k.name) { if g.isLead { g.formation = k; g.say("Formation: " + k.name) } else { g.nextFormation() } } }
        formItems.append(.separator())
        formItems += Formation.spacingNames.enumerated().map { i, n in ClosureMenuItem("Spacing: " + n) { if g.isLead { g.spacing = i; g.say("Spacing: " + n) } else { g.nextSpacing() } } }
        menu("Formation", formItems)
        menu("Simulation", [
            ClosureMenuItem("Menu Music On / Off") { g.musicEnabled.toggle(); g.say(g.musicEnabled ? "Menu music on" : "Menu music off") },
            ClosureMenuItem("Main Menu") { g.cameFromMenu = false; g.hud.overlay = .menu },
            ClosureMenuItem("Weather…", key: "e", mods: [.command, .shift]) { g.cameFromMenu = g.hud.overlay == .menu; g.hud.overlay = .environment },
            .separator(),
            ClosureMenuItem("Reset Aircraft", key: "r") { g.resetAircraft() },
            ClosureMenuItem("Pause / Resume", key: "p") { g.paused.toggle() },
            ClosureMenuItem("Slow Motion") { g.keyDown(17) },
            .separator(),
            ClosureMenuItem("Balloon Burst Challenge", key: "b") { g.toggleChallenge() },
            ClosureMenuItem("Autopilot for Your Own Wing", key: "k") { g.keyDown(40) },
            ClosureMenuItem("Unlimited Battery On / Off") { g.unlimitedBattery.toggle(); g.say(g.unlimitedBattery ? "Unlimited battery" : "Battery drains with use") },
        ])
        var envItems: [NSMenuItem] = [0, 2, 5, 8, 12].map { s in ClosureMenuItem("Wind \(s) m/s") { g.env.windSpeed = Float(s); g.say("Wind \(s) m/s") } }
        envItems.append(.separator())
        envItems += [("North", 0), ("East", 90), ("South", 180), ("West", 270)].map { n, d in
            ClosureMenuItem("Wind from \(n)") { g.env.windFrom = Float(d); g.say("Wind from \(n)") }
        }
        envItems.append(.separator())
        envItems += [("Smooth air", 0), ("Light turbulence", 0.3), ("Gusty", 0.8)].map { n, t in
            ClosureMenuItem(n) { g.env.turbulence = Float(t); g.say(n) }
        }
        envItems.append(.separator())
        envItems += Environment.presets.enumerated().map { i, n in ClosureMenuItem("Preset: " + n) { g.env.apply(preset: i); g.say(n) } }
        envItems.append(ClosureMenuItem("Thermals On / Off") { g.env.thermalsOn.toggle(); g.say(g.env.thermalsOn ? "Thermals on" : "Thermals off") })
        envItems.append(.separator())
        envItems += Game.timeNames.enumerated().map { i, n in ClosureMenuItem(n) { g.timeOfDay = i; g.say(n) } }
        menu("Environment", envItems)
        var viewItems: [NSMenuItem] = Game.cameraNames.enumerated().map { i, n in ClosureMenuItem("Camera: " + n) { g.cameraMode = i; g.keyDown(8); g.keyDown(8); g.keyDown(8) } }
        viewItems.append(.separator())
        viewItems += Game.zoomNames.enumerated().map { i, n in ClosureMenuItem("Zoom: " + n) { g.zoomMode = i; g.say("Zoom: " + n) } }
        viewItems.append(.separator())
        viewItems += Game.qualityNames.enumerated().map { i, n in ClosureMenuItem("Graphics: " + n) { g.quality = i; g.say("Graphics quality: " + n) } }
        viewItems.append(.separator())
        viewItems.append(ClosureMenuItem("Show / Hide HUD") { g.hud.visible.toggle() })
        viewItems.append(ClosureMenuItem("Keyboard Controls") { g.cameFromMenu = g.hud.overlay == .menu; g.hud.overlay = g.hud.overlay == .help ? .none : .help })
        viewItems.append(ClosureMenuItem("Toggle Full Screen", key: "f", mods: [.command, .control]) { [unowned self] in self.setFullScreen(!((self.window as? FlightWindow)?.covers ?? false)) })
        menu("View", viewItems)
        menu("Controller", [
            ClosureMenuItem("Controller Setup…", key: ",") { [unowned self] in self.showSetup() },
            ClosureMenuItem("Switch High / Low Rates", key: "l") { g.keyDown(37) },
            ClosureMenuItem("Mute Sound", key: "m") { g.keyDown(46) },
        ])
        NSApp.mainMenu = main
    }

    private func showSetup() {
        if setupWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Controller Setup"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SetupView(model: SetupModel(input: game.input)))
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            setupWindow = w
        }
        setupWindow?.makeKeyAndOrderFront(nil)
    }
}

final class SetupModel: ObservableObject {
    let input: InputManager
    @Published var values = [Float](repeating: 0, count: 4)
    @Published var device = ""
    @Published var connected = false
    @Published var calibrating = false
    @Published var s: InputSettings { didSet { input.settings = s } }
    @Published var listening: String? = nil         // action waiting for a switch or button to be moved
    private var seenAxes: [Float] = [], seenButtons: [Bool] = []
    func listen(_ id: String) {
        if listening == id { listening = nil; return }
        listening = id; seenAxes = input.hid.axes; seenButtons = input.hid.buttons
    }
    func clear(_ id: String) { var b = s.bindings ?? [:]; b[id] = nil; s.bindings = b; if listening == id { listening = nil } }
    func setFollow(_ id: String, _ on: Bool) { var b = s.bindings ?? [:]; b[id]?.follow = on; s.bindings = b }
    private func bind(_ id: String, _ c: ControlBinding) { var b = s.bindings ?? [:]; b[id] = c; s.bindings = b; listening = nil }
    /// While waiting, the first button that changes or switch axis that moves a long way is taken.
    private func watch() {
        guard let id = listening else { return }
        for (i, on) in input.hid.buttons.enumerated() where i < seenButtons.count && on != seenButtons[i] { bind(id, ControlBinding(axis: false, index: i)); return }
        for (i, v) in input.hid.axes.enumerated() where i < seenAxes.count && !s.axis.contains(i) && abs(v - seenAxes[i]) > 0.6 { bind(id, ControlBinding(axis: true, index: i)); return }
    }
    private var timer: Timer?
    init(input: InputManager) {
        self.input = input
        s = input.settings
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let m = self else { return }
            m.values = (0..<4).map { m.input.channel($0) }
            m.watch()
            m.connected = m.input.hid.connected
            m.device = m.connected ? m.input.hid.name : "No USB transmitter or joystick detected"
        }
    }
    func calibrate() {
        if calibrating { input.finishCalibration(); s = input.settings } else { input.startCalibration() }
        calibrating = input.calibrating
    }
    func resetCalibration() { input.resetCalibration(); s = input.settings; calibrating = false }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    private func pct(_ title: String, _ v: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: v, in: range)
            Text(String(format: "%.0f %%", v.wrappedValue * 100)).monospacedDigit().frame(width: 50, alignment: .trailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USB transmitter").font(.headline)
            Text(model.device).foregroundColor(model.connected ? .primary : .secondary)
            ForEach(0..<4, id: \.self) { i in
                HStack {
                    Text(InputSettings.channelNames[i]).frame(width: 70, alignment: .leading)
                    Picker("", selection: $model.s.axis[i]) {
                        ForEach(0..<9, id: \.self) { Text(InputSettings.axisNames[$0]).tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Toggle("Reverse", isOn: $model.s.invert[i])
                    ProgressView(value: Double(model.values[i] + 1) / 2).frame(width: 110)
                    Text(String(format: "%+.2f", model.values[i])).monospacedDigit().frame(width: 48)
                }
            }
            HStack {
                Button(model.calibrating ? "Done — sticks are centred" : "Calibrate…") { model.calibrate() }
                Button("Reset Calibration") { model.resetCalibration() }.disabled(model.calibrating)
            }
            Text(model.calibrating
                 ? "Move both sticks through their full travel several times, then let them centre (throttle can stay anywhere) and click Done."
                 : "After calibrating, each bar should reach −1 and +1 at the stick ends. Throttle should read −1 at idle and elevator +1 with the stick pulled back; tick Reverse if not.")
                .font(.caption).foregroundColor(model.calibrating ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("Stick mode").font(.headline)
            Picker("", selection: $model.s.stickMode) {
                ForEach(1...4, id: \.self) { Text(InputSettings.modeNames[$0 - 1]).tag($0) }
            }.labelsHidden()
            Text("Sets the stick layout for gamepads and the on-screen stick display. A transmitter's mode is fixed by its hardware.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("Rates and expo").font(.headline)
            Toggle("Use my own low rate and expo for every aircraft", isOn: Binding(get: { model.s.ownRates ?? false }, set: { model.s.ownRates = $0 }))
            Group {
                pct("Low rate", $model.s.lowRate, 0.3...1)
                pct("Aileron expo", $model.s.expo[0], 0...0.8)
                pct("Elevator expo", $model.s.expo[1], 0...0.8)
                pct("Rudder expo", $model.s.expo[2], 0...0.8)
            }.disabled(!(model.s.ownRates ?? false))
            pct("Stick deadband", $model.s.deadband, 0...0.15)
            Toggle("Reverse the pitch stick on multirotors", isOn: Binding(get: { model.s.multiPitchReverse ?? false }, set: { model.s.multiPitchReverse = $0 }))
            Text("Each aircraft comes with a low rate and expo of its own, and every flight starts on low rates. Press L, or use an assigned switch, to change between low and high.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("Switches and buttons").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(InputManager.actions, id: \.id) { a in
                        HStack {
                            Text(a.title).frame(width: 165, alignment: .leading)
                            Text(model.listening == a.id ? "move a switch or press a button…" : InputManager.label(model.s.bindings?[a.id]))
                                .foregroundColor(model.listening == a.id ? .orange : .secondary).frame(width: 150, alignment: .leading).lineLimit(1)
                            Button(model.listening == a.id ? "Cancel" : "Assign") { model.listen(a.id) }
                            Button("Clear") { model.clear(a.id) }.disabled(model.s.bindings?[a.id] == nil)
                            if a.states >= 2, let b = model.s.bindings?[a.id], !b.axis {
                                Toggle("latching", isOn: Binding(get: { b.follow }, set: { model.setFollow(a.id, $0) })).help("On: the button is a switch that stays in position. Off: each press steps to the next setting.")
                            }
                        }.font(.system(size: 12))
                    }
                }
            }.frame(height: 118)
            Text("Click Assign, then move the switch or press the button on your transmitter. A two- or three-position switch sets the state directly; a push button steps through it. The four stick axes cannot be assigned.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(width: 600)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

/// The flight window. When it covers the screen it may sit over the menu bar area, which a titled window is
/// normally kept out of.
final class FlightWindow: NSWindow {
    var covers = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { covers ? frameRect : super.constrainFrameRect(frameRect, to: screen) }
}
