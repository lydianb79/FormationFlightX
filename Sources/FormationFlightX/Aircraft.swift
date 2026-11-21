import simd
import Foundation

// Body frame: +X right, +Y up, -Z forward.
// Body rates: +x pitch up, +y yaw left, +z roll left.

enum AircraftKind { case airplane, multirotor, helicopter }

struct Controls {
    var aileron: Float = 0      // + roll right
    var elevator: Float = 0     // + pitch up (stick back)
    var rudder: Float = 0       // + yaw right
    var throttle: Float = 0     // 0...1 (collective for helicopters)
    var mode: Int = 0
    var flaps: Float = 0        // 0...1
    var gearUp = false
    var rotorSpeed = 2          // helicopters: head speed setting, 0 low, 1 normal, 2 high
    var hold = false            // helicopter throttle hold (engine disengaged)
    var brake: Float = 0        // wheel brakes 0...1
}

/// One lifting panel. Forces are computed from its own local airflow, so stall,
/// spin, damping and prop-wash effects fall out of the geometry.
struct AeroSurface {
    var pos: V3
    var normal: V3
    var chordDir: V3 = V3(0, 0, -1)
    var area: Float
    var ar: Float
    var liftSlope: Float
    var stall: Float = 0.25
    var cd0: Float = 0.012
    var alpha0: Float = 0
    var flapCh: Int = -1        // 0 aileron, 1 elevator, 2 rudder
    var flapGain: Float = 0     // change of effective alpha (rad) at full deflection
    var wash: Float = 0         // fraction of prop wash seen by this panel
    var flapsGain: Float = 0    // landing flaps: change of effective alpha (rad) when fully down
    var isWing = false          // main wing panel: contributes to the downwash on the tail
    var load: Float = 1         // local section loading relative to the wing average (taper makes tips work harder)
    var chord: Float = 0.2
    var stallWidth: Float = 0.14    // how abruptly the section lets go (rad): small = sharp break
    var hyst: Float = 0.04          // the flow reattaches this far below the stall angle (rad)
    var postStall: Float = 1.0      // lift retained once fully stalled
    var downwash: Float = 0         // 1 for a tailplane sitting in the wing's downwash
    var swirl: Float = 0            // 1 for a fin in the propeller's spiral slipstream
    var elevGain: Float = 0         // elevons: extra change of effective alpha (rad) at full elevator
    var cm0: Float = 0              // section pitching moment (reflexed sections are positive: nose-up)
}

struct Propulsor {
    var pos: V3
    var staticThrust: Float
    var pitchSpeed: Float
    var diameter: Float
    var torqueK: Float = 0.03
    var tau: Float = 0.7            // rotor inertia: larger = slower to change speed
    var momentum: Float = 0         // angular momentum at full speed (kg m^2/s), for gyroscopic effects
    var spinDir: Float = 1          // +1 clockwise seen from behind
    var axis = V3(0, 0, -1)         // thrust direction: models other than flat foamies have the motor angled right and down
    var pFactor: Float = 0.18       // sideways shift of the thrust centre per radian of inflow angle, in diameters
}

struct Contact {
    var pos: V3
    var wheel = false
    var steer: Float = 0
    var crashSpeed: Float = 3
    var mu: Float = 0.5
    var float = false           // part of a float: buoyant on water
}

struct MultiSpec {
    var motors: [V3]
    var dirs: [Float]
    var maxThrust: Float
    var kYaw: Float = 0.016
    var maxRate: Float = 6.5
    var maxYaw: Float = 4.0
    var maxAngle: Float = 0.7
    // acro
    var acroRate: Float = 0         // roll and pitch rate at full stick in acro (rad/s); 0 = 1.6 x maxRate
    var acroYaw: Float = 0          // yaw rate at full stick in acro (rad/s); 0 = 1.5 x maxYaw
    var center: Float = 0.3         // stick sensitivity around the centre, as a fraction of the full rate
    var idle: Float = 0.07          // motor speed at zero throttle while flying, as a fraction of full speed
    var tau: Float = 0.03           // motor and propeller spin-up time (s)
    var pitchSpeed: Float = 24      // air speed through the propellers at which they stop pulling (m/s at full speed)
    var propR: Float = 0.12         // propeller radius (m)
    var rotorDrag: Float = 0.1      // sideways drag of the spinning propellers
    var gain: Float = 30            // how hard the flight controller chases the commanded rate (1/s)
    var ducted = false              // propellers in ducts: more drag, less propwash wobble
}

/// Stick-to-rate curve of a flight controller: gentle round the centre, steep toward the ends.
func rateCurve(_ x: Float, center: Float, full: Float) -> Float {
    let a = abs(x)
    return x * full * (center + (1 - center) * a * a * a)
}

struct HeliSpec {
    var rotorR: Float
    var hub: V3
    var rpm: Float
    var sigma: Float
    var collMax: Float
    var maxMoment: Float
    var tailMax: Float
    var maxRate: Float
    var maxYaw: Float
}

extension AircraftSpec {
    var thrustToWeight: Float {
        switch kind {
        case .airplane: return props.reduce(0) { $0 + $1.staticThrust } / (mass * gravity)
        case .multirotor: return (multi.map { $0.maxThrust * Float($0.motors.count) } ?? 0) / (mass * gravity)
        case .helicopter: return 4
        }
    }
    /// Throttle stick position at which a multirotor hovers.
    var hoverThrottle: Float {
        guard let m = multi else { return 0.5 }
        let speed = sqrt(mass * gravity / (Float(m.motors.count) * m.maxThrust))
        return clampf((speed - m.idle) / (1 - m.idle), 0, 1)
    }
    /// 1 (easy) to 5 (expert)
    var difficulty: Int {
        switch category {
        case "Trainers & Sport": return name.contains("Racer") ? 3 : 1
        case "Scale Civil": return 2
        case "Gliders": return 2
        case "Wings": return ["Race", "Speed"].contains { name.contains($0) } ? 4 : (name.contains("Delta") || name.contains("Slope") ? 3 : 2)
        case "FPV Aircrafts":
            if ["Race", "Speed", "Chupito"].contains(where: { name.contains($0) }) { return 4 }
            if ["Delta", "Slope", "F-01", "Combat"].contains(where: { name.contains($0) }) { return 3 }
            return ["Hunter", "Drift", "Penguin", "Ranger", "Altus"].contains { name.contains($0) } ? 1 : 2
        case "Aerobatic", "Foam 3D": return 3
        case "Warbirds", "Jets": return 4
        case "Helicopters": return (heli?.maxRate ?? 5) < 4.5 ? 4 : 5
        case "Multirotors": return thrustToWeight > 6 ? 4 : (thrustToWeight > 4 ? 3 : 2)
        default: return 3
        }
    }
    var features: [String] {
        var f: [String] = []
        if hasFlaps { f.append("Flaps") }
        if hasRetracts { f.append("Retractable gear") }
        if hasFloats { f.append("Floats") }
        if surfaces.contains(where: { $0.elevGain != 0 }) { f.append("Elevons") }
        if handLaunch { f.append("Hand launch") }
        if props.count > 1 { f.append("Twin engine") }
        if kind == .helicopter { f.append("Collective pitch"); f.append("Autorotation") }
        if modes.count > 1 { f.append(modes.joined(separator: " / ")) }
        return f
    }
    /// True when the model burns fuel (piston engine or turbine) rather than running on a battery.
    var burnsFuel: Bool { kind == .airplane && (engineSound == 1 || engineSound == 3) }
    /// What drives it: a brushless electric motor, or an engine and of what kind.
    var powerPlant: String {
        func count(_ n: Int, _ one: String, _ many: String) -> String { n > 1 ? "\(n) \(many)" : one }
        switch kind {
        case .helicopter: return "Brushless electric motor"
        case .multirotor: return count(multi?.motors.count ?? 4, "Brushless electric motor", "brushless electric motors")
        case .airplane:
            let n = props.count
            if n == 0 || props.allSatisfy({ $0.staticThrust <= 0 }) { return "None (unpowered)" }
            switch engineSound {
            case 1:
                return count(n, "Piston engine", "piston engines")
            case 2: return count(n, "Electric ducted fan", "electric ducted fans") + " (brushless motor)"
            case 3: return count(n, "Turboprop engine", "turboprop engines")
            default: return count(n, "Brushless electric motor", "brushless electric motors")
            }
        }
    }
    var sizeLabel: String { kind == .airplane ? "Wingspan" : (kind == .helicopter ? "Rotor diameter" : "Motor to motor") }
}

enum Anim { case fixed, spin(Int), hinge(Int, Float) }

struct Part {
    var mesh: MeshBuilder
    var pivot: V3 = .zero
    var axis: V3 = V3(0, 1, 0)
    var anim: Anim = .fixed
    var detach = false          // fixed part that can break off in a crash
    var blur = 0                // spinning parts: 1 = blades (hidden at speed), 2 = translucent disc shown at speed
    var center = V3.zero        // its centre, for tumbling
}

struct AircraftSpec {
    var name: String
    var kind: AircraftKind
    var blurb: String
    var mass: Float
    var inertia: V3
    var span: Float
    var surfaces: [AeroSurface] = []
    var props: [Propulsor] = []
    var contacts: [Contact] = []
    var cdA: Float = 0.01
    var multi: MultiSpec? = nil
    var heli: HeliSpec? = nil
    var handLaunch = false
    var category = "Sport"
    var stallSpeed: Float = 9
    var hasFlaps = false
    var hasRetracts = false
    var hasFloats = false
    var construction = "Balsa and film"
    var mac: Float = 0.25           // mean aerodynamic chord
    var cgShift: Float = 0          // how far the wing was moved back to reach that margin when test-flown
    var trimSetting: Float = 0      // tailplane incidence (rad) or reflex chosen for level cruise
    var rollTrim: Float = 0         // aileron trim that holds the wings level against the propeller's torque in the cruise
    var designMargin: Float = 0.1   // static margin the balance was set for, as a fraction of the mean chord
    var wingArea: Float = 0.4
    var downwashK: Float = 0        // downwash angle at the tail per unit wing lift coefficient
    var endurance: Float = 240      // seconds of full-throttle running on a fresh battery
    var smokePos = V3(0, 0, 0.2)
    var parts: [Part] = []
    var modes: [String] = []
    var defaultMode = 0             // flight mode selected when the aircraft is chosen
    var lowRate: Float = 0.6        // control throw on low rates that suits this aircraft
    var expo: Float = 0.3           // stick expo that suits this aircraft
    var soundBase: Float = 120   // blade-pass frequency (Hz) at full power
    var engineSound = 0          // 0 electric, 1 piston, 2 ducted fan, 3 turboprop
    var cylinders = 4
    var radial = false
    var blades = 2
    var eyeOffset: V3 = V3(0, 0.15, 0.05)
}

final class Aircraft {
    let spec: AircraftSpec
    var pos = V3.zero, vel = V3.zero, omega = V3.zero
    var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var servo = V3.zero
    var levels: [Float]
    var spin: [Float]
    var vi: Float = 0
    var yawI: Float = 0
    var crashed = false
    var onGround = false
    var airspeed: Float = 0
    // pose used for drawing and the camera: the physics state carried forward by the part of a step not yet simulated
    var renderPos = V3.zero
    var renderQ = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    func updateRenderPose(ahead t: Float) {
        renderPos = pos + vel * t
        let w = length(omega)
        renderQ = w > 1e-6 ? simd_normalize(q * simd_quatf(angle: w * t, axis: omega / w)) : q
    }
    var flap: Float = 0             // actual flap position 0...1
    var battery: Float = 1          // state of charge 0...1
    var unlimitedBattery = false
    var stallT: [Float]             // per surface: 0 attached flow ... 1 fully stalled
    var stalled: [Bool]
    private var eps: Float = 0      // downwash angle at the tail
    private var wingStallNow: Float = 0     // stalled fraction of the wing, from the previous step
    private var groundPhi: Float = 1   // 1 in free air, falling toward 0 as the wing nears the ground
    private var buffet: Float = 0
    private var tqPrev = V3.zero            // multirotor: last torque demand, for the controller's lead term
    var vortexRing: Float = 0       // helicopter: 0...1 how deep in vortex ring state
    private var motorLoad: Float = 0
    /// How hard the motor is working, 0 (throttle closed, propeller windmilling) to about 1.
    var engineLoad: Float { motorLoad }
    /// Fraction of the main wing that is stalled (for the display and tests).
    var wingStall: Float {
        var a: Float = 0, t: Float = 0
        for (i, sf) in spec.surfaces.enumerated() where sf.isWing { a += sf.area; t += sf.area * stallT[i] }
        return a > 0 ? t / a : 0
    }
    var gear: Float = 0             // 0 down, 1 retracted
    var crashImpact: Float = 0      // speed of the impact that caused the crash
    /// Hardest fresh ground contact since the game last looked: speed into the ground (m/s), and what touched what.
    var touchImpact: Float = 0, touchWheel = false, touchWater = false
    private var offGround: [Float] = []         // per contact point: time since it last touched
    var detached = Set<Int>()       // parts that have broken off
    let kSpring: Float, cDamp: Float
    let restHeight: Float
    private let wingY: Float
    private var want: [Float]

    init(_ spec: AircraftSpec) {
        self.spec = spec
        let n = max(spec.props.count, spec.multi?.motors.count ?? 0, 2)
        levels = [Float](repeating: 0, count: n)
        spin = [Float](repeating: 0, count: n)
        want = [Float](repeating: 0, count: n)
        stallT = [Float](repeating: 0, count: spec.surfaces.count)
        stalled = [Bool](repeating: false, count: spec.surfaces.count)
        kSpring = spec.mass * gravity / 0.03
        cDamp = 0.5 * sqrt(kSpring * spec.mass)
        restHeight = -(spec.contacts.map { $0.pos.y }.min() ?? 0)
        wingY = spec.surfaces.first { $0.isWing }?.pos.y ?? 0
    }

    var power: Float {
        let n = spec.kind == .airplane ? max(spec.props.count, 1) : levels.count
        return levels.prefix(n).reduce(0, +) / Float(n)
    }
    var forward: V3 { q.act(V3(0, 0, -1)) }
    var up: V3 { q.act(V3(0, 1, 0)) }
    var right: V3 { q.act(V3(1, 0, 0)) }
    var pitch: Float { asin(clampf(forward.y, -1, 1)) }
    var roll: Float { atan2(-right.y, up.y) }

    func reset(pos p: V3, heading: Float, speed: Float = 0) {
        q = simd_quatf(angle: heading, axis: V3(0, 1, 0))
        pos = p; vel = q.act(V3(0, 0, -speed)); omega = .zero; servo = .zero
        for i in levels.indices { levels[i] = 0 }
        vi = 0; yawI = 0; crashed = false; onGround = false
        flap = 0; gear = 0; crashImpact = 0; detached = []; touchImpact = 0
        for i in offGround.indices { offGround[i] = 0 }
        battery = 1; eps = 0; motorLoad = 0; vortexRing = 0; groundPhi = 1
        for i in stallT.indices { stallT[i] = 0; stalled[i] = false }
        if spec.kind == .helicopter { levels[0] = 1 }    // rotor already at speed
    }

    /// Animation input for hinged parts: 0-2 control surfaces, 3 flaps, 4 landing gear.
    func animValue(_ ch: Int) -> Float {
        switch ch {
        case 0...2: return servo[ch]
        case 3: return flap
        case 4: return gear
        case 5: return clampf(servo.x + servo.y, -1, 1)      // right elevon
        default: return clampf(servo.y - servo.x, -1, 1)     // left elevon
        }
    }

    /// Section lift and drag. Below the stall the lift is linear; above it the section behaves like a
    /// flat plate. `i` selects the surface's stall state, which lags behind the airflow and has hysteresis.
    private func liftDrag(_ alpha: Float, _ s: AeroSurface, _ i: Int, speed: Float, dt: Float) -> (Float, Float) {
        var a = alpha
        if a > .pi { a -= 2 * .pi } else if a < -.pi { a += 2 * .pi }
        let aL = abs(a) * s.load
        let onset = stalled[i] ? s.stall - s.hyst : s.stall
        let target = smoothstep(onset, onset + s.stallWidth, aL)
        if target > 0.6 { stalled[i] = true } else if aL < s.stall - s.hyst { stalled[i] = false }
        // separation and reattachment take a few chord lengths of travel
        let tau = clampf(3 * s.chord / max(speed, 1), 0.008, 0.15)
        stallT[i] += (target - stallT[i]) * min(1, dt / tau)
        let t = stallT[i]
        // close to the ground the wingtip vortices are cut off: more lift, much less induced drag
        let ge: Float = s.isWing ? groundPhi : 1
        let clLin = s.liftSlope * a * s.load * (1 + 0.1 * (1 - ge))
        let cdLin = s.cd0 + clLin * clLin / (.pi * s.ar * 0.8) * ge
        let sa = sin(a)
        // Past the stall a model wing keeps most of its lift and sheds it gradually as the angle grows,
        // until it is just a flat plate in the airflow.
        let plate = 1.1 * abs(sin(2 * a))
        let keep = s.liftSlope * s.stall * s.postStall * (1 - 0.5 * smoothstep(s.stall, s.stall + 0.6, aL))
        let clP = (abs(a) < .pi / 2 ? max(plate, keep) : plate) * (sin(2 * a) < 0 ? -1 : 1)
        let cdP = s.cd0 + 1.5 * sa * sa
        return (clLin + (clP - clLin) * t, cdLin + (cdP - cdLin) * t)
    }

    func step(dt: Float, c: Controls, terrain: Terrain, wind: V3, rollMu: Float) {
        let R = simd_float3x3(q)
        let Rt = R.transpose
        servo += (V3(c.aileron, c.elevator, c.rudder) - servo) * min(1, dt / 0.04)
        if spec.hasFlaps { flap += clampf(c.flaps - flap, -dt / 1.5, dt / 1.5) }
        if spec.hasRetracts { gear += clampf((c.gearUp && !crashed ? 1 : 0) - gear, -dt / 1.2, dt / 1.2) }
        let va = Rt * (vel - wind)            // velocity through the air, body frame
        airspeed = length(va)
        var fb = V3.zero                       // body-frame force
        var tb = V3.zero                       // body-frame torque
        let thr = crashed ? 0 : clampf(c.throttle, 0, 1)

        switch spec.kind {
        case .airplane:
            var washV: Float = 0, swirlV: Float = 0, draw: Float = 0
            var washZ: Float = 0, washR: Float = 0.1         // where the slipstream starts, and its radius
            let vfwd = -va.z
            // inflow angle at the propeller: nose-up attitude and sideslip tilt the disc to the airflow
            let aoa = vfwd > 1 ? clampf(atan2(-va.y, vfwd), -0.6, 0.6) : 0
            let slip = vfwd > 1 ? clampf(atan2(va.x, vfwd), -0.6, 0.6) : 0
            // battery voltage relative to a fresh pack at full load: rises when unloaded, sags as it empties
            let volts = 1 + 0.1 * (1 - motorLoad) - 0.22 * (1 - battery) * (1 - battery)
            let cutoff: Float = battery < 0.03 ? 0.3 : 1          // low-voltage cut: enough left to land
            var loadSum: Float = 0
            for (i, p) in spec.props.enumerated() {
                let n = levels[i]                                  // shaft speed, 1 = static full throttle
                let ct = clampf(1 - vfwd / (p.pitchSpeed * max(n, 0.05)), -0.3, 1)
                let T = p.staticThrust * n * n * ct
                // electric motor: torque falls off as the speed approaches the no-load speed; the propeller's
                // load grows with speed squared and eases as the aircraft flies faster
                let qm = clampf((thr * cutoff * volts - 0.82 * n) / 0.18, -0.05, 2.2)
                let ql = n * n * (0.35 + 0.65 * max(ct, 0))
                levels[i] = clampf(n + (qm - ql) / p.tau * dt, 0, 1.4)
                loadSum += clampf(qm, 0, 1.5)
                draw += max(qm, 0) * n
                let f = p.axis * T
                // P-factor: the down-going blade bites harder, so thrust acts off-centre
                let off = T > 0 ? V3(aoa, slip, 0) * (p.pFactor * p.diameter * p.spinDir) : V3.zero
                fb += f; tb += cross(p.pos + off, f)
                tb.z += p.torqueK * p.staticThrust * p.diameter * max(qm, 0) * p.spinDir      // torque reaction
                tb -= cross(omega, V3(0, 0, -p.momentum * n * p.spinDir))                     // gyroscopic precession
                if T > 0 {
                    let A = Float.pi * p.diameter * p.diameter / 4
                    let v0 = max(vfwd, 0)
                    let w = -v0 + sqrt(v0 * v0 + 2 * T / (rho * A))
                    if w > washV { washZ = p.pos.z; washR = p.diameter / 2 }
                    washV = max(washV, w)
                    if abs(p.pos.x) < 0.01 { swirlV = 0.018 * w * p.spinDir }          // spiral slipstream
                }
                spin[i] += (n > 0.01 ? 12 + 45 * sqrt(min(n, 1)) : 0) * dt
            }
            let np = Float(max(spec.props.count, 1))
            motorLoad += (loadSum / np - motorLoad) * min(1, dt / 0.05)
            if !unlimitedBattery { battery = max(0, battery - draw / np * dt / spec.endurance) }

            do {
                // height of the wing itself, not the fuselage, above the surface (or the water)
                let wingOff = R * V3(0, wingY, 0)
                let surfaceY = max(terrain.height(pos.x, pos.z), terrain.site.waterLevel ?? -1e9)
                let hg = max(pos.y + wingOff.y - surfaceY, 0.03)
                let r = 16 * hg / spec.span
                groundPhi = r * r / (1 + r * r)
            }
            var wingCl: Float = 0, wingArea: Float = 0
            var stallSum: Float = 0, stallArea: Float = 0
            for (i, s) in spec.surfaces.enumerated() {
                var v = va + cross(omega, s.pos)
                // The slipstream is a narrow tube that trails straight back from the propeller. A surface moving
                // across it (a tail swinging in a fast pitch or yaw, or the whole aircraft sliding sideways) has
                // left the tube by the time the air arrives, so it loses the blast.
                var inWash = s.wash
                if inWash > 0 && washV > 0.5 {
                    let drift = abs(dot(v, s.normal)) * abs(s.pos.z - washZ) / (washV + max(-va.z, 0))
                    let d = drift / (3.5 * washR)
                    inWash /= 1 + d * d
                }
                v.z -= inWash * washV
                v.x -= s.swirl * inWash * swirlV
                let vf = dot(v, s.chordDir), vn = dot(v, s.normal)
                let sp2 = vf * vf + vn * vn
                if sp2 < 1e-6 { continue }
                let sp = sqrt(sp2)
                var alpha = atan2(-vn, vf) + s.alpha0 - s.downwash * eps
                // control surfaces lose their bite in separated flow
                // and a hinged surface turns the flow less and less as its deflection grows: past about 25 degrees
                // of effective camber change the extra throw mostly adds drag
                // A hinged control works like a flap: it adds lift of its own and only nudges the whole surface toward
                // the stall, so an aileron, elevator or rudder still bites when its surface is already at a large
                // angle to the air (a hover in wind, a harrier, a spin). It needs air flowing along the chord to work.
                // Its effect also tails off as the throw grows past about 25 degrees.
                let dElev = s.elevGain * servo[1]
                let throw_ = (s.flapCh >= 0 ? s.flapGain * servo[s.flapCh] : 0) + dElev
                let hinge = throw_ != 0 ? 0.45 * tanh(throw_ / 0.45) * max(vf / sp, 0) : 0
                alpha += 0.3 * hinge
                alpha += s.flapsGain * flap
                var (cl, cd) = liftDrag(alpha, s, i, speed: sp, dt: dt)
                if hinge != 0 {
                    let dcl = s.liftSlope * s.load * 0.7 * hinge * (1 - 0.35 * stallT[i])
                    cl += dcl; cd += dcl * dcl / (.pi * s.ar * 0.8) + 0.25 * hinge * hinge
                }
                if s.isWing { stallSum += stallT[i] * s.area; stallArea += s.area }
                // a tailplane behind a stalled wing sits in its wake and loses much of its bite, except where the propeller blows on it
                let blanket: Float = s.downwash > 0 ? 1 - 0.5 * wingStallNow * (1 - 0.7 * inWash) * s.downwash : 1
                let qS = 0.5 * rho * sp2 * s.area * blanket
                if s.flapsGain != 0 { cd += 0.07 * flap; tb.x -= qS * s.chord * 0.18 * flap }
                // a tailless wing is trimmed and pitched by its own section: reflex, and elevons moving the centre of lift
                if s.cm0 != 0 || dElev != 0 { tb.x += qS * s.chord * (s.cm0 - 0.3 * s.liftSlope * dElev) * (1 - 0.85 * stallT[i]) }      // flaps drag, and pitch the nose down
                if s.isWing && abs(s.pos.x) < spec.span * 0.3 { wingCl += cl * s.area * sp2; wingArea += s.area }
                let u = (s.chordDir * vf + s.normal * vn) / sp
                let l = (s.normal * vf - s.chordDir * vn) / sp
                let f = (l * cl - u * cd) * qS
                // in separated flow the centre of pressure moves back toward mid-chord, which steadies a stalled wing
                let cp = s.pos - s.chordDir * (0.25 * s.chord * stallT[i])
                fb += f; tb += cross(cp, f)
            }
            if stallArea > 0 { wingStallNow = stallSum / stallArea }
            // downwash behind the wing reduces the tail's angle of attack; when the wing stalls it collapses
            // It is the lift the wing is actually making that deflects the air, and the deflection is an angle only
            // relative to the speed of the air reaching the tail. Hanging on the propeller the wing makes next to no
            // lift while the tail sits in a fast stream, so there is next to no downwash.
            if wingArea > 0 {
                let vt = airspeed + 0.8 * washV
                let target = clampf(spec.downwashK * wingCl / (wingArea * max(vt * vt, 1)) * groundPhi, -0.3, 0.3)
                eps += (target - eps) * min(1, dt / 0.15)
            }
            fb -= va * (0.5 * rho * (spec.cdA + (spec.hasRetracts ? 0.004 * (1 - gear) : 0)) * airspeed)

        case .multirotor:
            // Motors are commanded in speed, thrust goes with speed squared: hover sits around a third of the stick
            // on a powerful machine, not a tenth. `levels` holds each motor's speed, 1 = full.
            let m = spec.multi!
            let n = m.motors.count
            // sitting on the ground with the throttle closed the motors are stopped; anywhere else they idle and the
            // controller keeps full authority, so a flip or a dive with the stick at zero stays under control
            let flying = thr > 0.03 || !onGround
            let load = levels.reduce(0, +) / Float(n)
            let sag = 1 - 0.1 * load * load                          // battery voltage drops under load
            if flying && !crashed {
                var wd: V3
                if c.mode == 0 {
                    var fh = R * V3(0, 0, -1); fh.y = 0
                    fh = length(fh) > 0.15 ? normalize(fh) : V3(0, 0, -1)
                    let hr = cross(fh, V3(0, 1, 0))
                    let t = normalize(V3(0, 1, 0) - fh * tan(c.elevator * m.maxAngle) + hr * tan(c.aileron * m.maxAngle))
                    let eb = Rt * cross(R * V3(0, 1, 0), t)
                    wd = V3(clampf(eb.x * 9, -m.maxRate, m.maxRate), -c.rudder * m.maxYaw, clampf(eb.z * 9, -m.maxRate, m.maxRate))
                } else {
                    let full = m.acroRate > 0 ? m.acroRate : m.maxRate * 1.6, fullYaw = m.acroYaw > 0 ? m.acroYaw : m.maxYaw * 1.5
                    wd = V3(rateCurve(c.elevator, center: m.center, full: full), -rateCurve(c.rudder, center: m.center, full: fullYaw),
                            -rateCurve(c.aileron, center: m.center, full: full))
                }
                var tq = spec.inertia * ((wd - omega) * V3(m.gain, 0.4 * m.gain, m.gain))
                // the controller leads its demand by the motors' spin-up time, so the rate settles without overshoot
                let lead = (tq - tqPrev) * (m.tau / dt)
                tqPrev = tq
                let cap = simd_abs(tq) * 2.5 + spec.inertia * 2
                tq += simd_clamp(lead, -cap, cap)
                var sx: Float = 0, sz: Float = 0
                for p in m.motors { sx += p.x * p.x; sz += p.z * p.z }
                let cmd = m.idle + (1 - m.idle) * thr
                var base = cmd * cmd * m.maxThrust
                var lo: Float = 0, hi: Float = 0
                for i in 0..<n {
                    let p = m.motors[i]
                    let yaw = clampf(tq.y * m.dirs[i] / (Float(n) * m.kYaw), -0.2 * m.maxThrust, 0.2 * m.maxThrust)
                    want[i] = -tq.x * p.z / sz + tq.z * p.x / sx + yaw
                    lo = min(lo, want[i]); hi = max(hi, want[i])
                }
                // Mixing with priority for attitude: if the corrections do not fit between idle and full power,
                // shrink them to fit, then move the collective thrust so that none is cut off
                let tMin = m.idle * m.idle * m.maxThrust, tMax = m.maxThrust
                let k = min(1, (tMax - tMin) / max(hi - lo, 1e-6))
                base = clampf(base, tMin - lo * k, tMax - hi * k)
                for i in 0..<n { want[i] = sqrt(clampf(base + want[i] * k, tMin, tMax) / m.maxThrust) }
            } else {
                for i in 0..<n { want[i] = 0 }
            }
            // Vortex ring / propwash: sinking back through its own downwash at low sideways speed the machine
            // loses lift and wobbles; flying out sideways or powering through cures it
            let disc = Float.pi * m.propR * m.propR * Float(n)
            let vHover = sqrt(spec.mass * gravity / (2 * rho * disc))
            let vin = sqrt(va.x * va.x + va.z * va.z)
            let wash = smoothstep(0.35 * vHover, 0.8 * vHover, -va.y) * (1 - smoothstep(1.4 * vHover, 2.2 * vHover, -va.y)) * (1 - smoothstep(0.5 * vHover, 1.3 * vHover, vin)) * min(1, load * 3)
            vortexRing += (wash - vortexRing) * min(1, dt / 0.15)
            buffet += dt
            let agl = pos.y - terrain.height(pos.x, pos.z)
            let span = spec.span
            let cushion: Float = agl < span ? 1 + 0.12 * (1 - max(agl, 0) / span) * max(R.columns.1.y, 0) : 1      // ground effect
            var sum: Float = 0
            for i in 0..<n {
                let w = min(want[i], sag)
                levels[i] += (w - levels[i]) * min(1, dt / (w > levels[i] ? m.tau : m.tau * 1.5))
                // a propeller pulls less the faster the air already moves through it, and more when it is pushed
                // against the air; the same effect resists rotation
                let through = va.y + cross(omega, m.motors[i]).y
                let inflow = clampf(1 - through / (m.pitchSpeed * max(levels[i], 0.25)), 0.15, 1.4)
                let shake = sin(buffet * (31 + 7 * Float(i)) + Float(i) * 1.7) * 0.6 + sin(buffet * (53 + 5 * Float(i)) + Float(i)) * 0.4
                let T = levels[i] * levels[i] * m.maxThrust * inflow * cushion * (1 - vortexRing * (0.13 + (m.ducted ? 0.04 : 0.1) * shake))
                fb.y += T
                tb += cross(m.motors[i], V3(0, T, 0))
                tb.y += m.dirs[i] * m.kYaw * T
                sum += levels[i]
                spin[i] += (levels[i] > 0.01 ? 14 + 50 * levels[i] : 0) * m.dirs[i] * dt
            }
            // the flat frame and the propeller discs drag far more when moved face-on than edge-on
            let q = 0.5 * rho * spec.cdA * airspeed
            fb -= V3(va.x, 2.6 * va.y, va.z) * q
            fb -= V3(va.x, 0, va.z) * (m.rotorDrag * sum * spec.mass / 1.2)

        case .helicopter:
            // Rotor speed is a real state: the governed engine drives it, aerodynamic torque loads it,
            // and with throttle hold it is driven only by the airflow (autorotation).
            let h = spec.heli!
            let om0 = h.rpm * 2 * .pi / 60
            let lv = levels[0]
            let om = om0 * lv
            let tip = max(om * h.rotorR, 1)
            let A = Float.pi * h.rotorR * h.rotorR
            // The throttle stick is collective pitch, symmetric about its centre, in both flight modes; the rotor is
            // held at a set speed by the governor, chosen with a three-position switch. Mode 0, Stabilized: the cyclic
            // stick commands a lean angle and the machine levels itself when it is released. Mode 1, Acro: the cyclic
            // commands a rate of rotation and the attitude stays where it is put.
            let theta = (2 * thr - 1) * h.collMax
            let headSpeed: Float = [0.8, 0.9, 1.0][min(max(c.rotorSpeed, 0), 2)]
            let vc = va.y
            let vin = sqrt(va.x * va.x + va.z * va.z)
            let lam = (vc + vi) / tip
            var T = 0.5 * rho * 5.7 * h.sigma * A * tip * tip * (theta / 3 - lam / 2)
            let agl = pos.y - terrain.height(pos.x, pos.z)
            let side: Float = theta >= 0 ? 1 : -1                // which way the rotor is blowing: -1 when flown inverted on negative pitch
            if agl < h.rotorR * 1.5 { T *= 1 + 0.12 * (1 - max(agl, 0) / (h.rotorR * 1.5)) * max(R.columns.1.y * side, 0) }
            // Vortex ring state: descending into its own downwash at low airspeed, the rotor loses lift and
            // shakes. More collective makes it worse; flying forward out of the column cures it.
            let vHover = sqrt(spec.mass * gravity / (2 * rho * A))
            let vrs = smoothstep(0.45 * vHover, 0.8 * vHover, -vc * side) * (1 - smoothstep(1.5 * vHover, 2.1 * vHover, -vc * side)) * (1 - smoothstep(0.5 * vHover, 1.1 * vHover, vin)) * lv
            vortexRing += (vrs - vortexRing) * min(1, dt / 0.3)
            buffet += dt
            let shake = sin(buffet * 17) * 0.5 + sin(buffet * 29 + 1) * 0.3 + sin(buffet * 43 + 2) * 0.2
            T *= 1 - vortexRing * (0.42 + 0.2 * shake)
            // Retreating blade stall at high forward speed: lift is lost on the side where the blade moves backward
            let mu = vin / tip
            let rbs = smoothstep(0.3, 0.45, mu)
            T *= 1 - 0.3 * rbs
            let viT = T / (2 * rho * A * max(sqrt(vin * vin + (vc + vi) * (vc + vi)), 1.5))
            vi += (viT - vi) * min(1, dt / 0.08)
            let hForce = 0.25 * spec.mass / 3.2 * lv                // in-plane drag of the turning rotor
            let f = V3(-hForce * va.x, T, -hForce * va.z)
            fb += f; tb += cross(h.hub, f)
            // Blade flapping: the disc tilts away from the oncoming air, so the nose rises with forward speed
            // and the machine rolls away from a sideways slide. The flight controller has to hold against it.
            let kFlap = 30 * spec.mass / 3.2 * lv * lv
            tb.x += kFlap * (-va.z) / tip + rbs * 0.6 * h.maxMoment + vortexRing * shake * 0.35 * h.maxMoment
            tb.z += kFlap * va.x / tip - rbs * 0.3 * h.maxMoment
            tb.y -= 0.002 * spec.mass * va.x * max(airspeed, 1)                  // fin weathervanes into the airflow
            let pScale = spec.mass / 3.2
            let qMax = 600 * pScale / om0
            let qEng: Float = (crashed || c.hold) ? 0 : clampf(40 * (headSpeed - lv), 0, 1) * qMax
            let qAero = (T * (vc + vi) + 70 * pScale * lv * lv * lv) / max(om, 20)
            let iRot = 0.04 * spec.mass * h.rotorR * h.rotorR
            levels[0] = clampf(lv + (qEng - qAero - (crashed ? qMax : 0)) / iRot / om0 * dt, 0, 1.3)
            tb.y += qEng                       // only engine torque is reacted by the airframe
            if !crashed {
                let auth = min(lv * lv, 1.2)
                var wx: Float, wz: Float
                if c.mode == 0 {
                    var fh = R * V3(0, 0, -1); fh.y = 0
                    fh = length(fh) > 0.15 ? normalize(fh) : V3(0, 0, -1)
                    let hr = cross(fh, V3(0, 1, 0))
                    let t = normalize(V3(0, 1, 0) - fh * tan(c.elevator * 0.75) + hr * tan(c.aileron * 0.75))
                    let eb = Rt * cross(R * V3(0, 1, 0), t)
                    wx = clampf(eb.x * 7, -0.6 * h.maxRate, 0.6 * h.maxRate); wz = clampf(eb.z * 7, -0.6 * h.maxRate, 0.6 * h.maxRate)
                } else {
                    let full = h.maxRate
                    wx = rateCurve(c.elevator, center: 0.45, full: full); wz = -rateCurve(c.aileron, center: 0.45, full: full)
                }
                let ex = wx - omega.x
                let ez = wz - omega.z
                tb.x += clampf(spec.inertia.x * 40 * ex, -h.maxMoment * auth, h.maxMoment * auth)
                tb.z += clampf(spec.inertia.z * 40 * ez, -h.maxMoment * auth, h.maxMoment * auth)
                let ey = -rateCurve(c.rudder, center: 0.5, full: h.maxYaw) - omega.y
                yawI = clampf(yawI + spec.inertia.y * 160 * ey * dt, -h.tailMax, h.tailMax)
                // the tail rotor loses bite when it slides sideways into its own wake
                let tailLoss = smoothstep(2, 5, va.x) * (1 - smoothstep(9, 13, va.x))
                let tAuth = auth * (1 - 0.55 * tailLoss)
                tb.y += clampf(spec.inertia.y * 35 * ey + yawI, -h.tailMax * tAuth, h.tailMax * tAuth)
            }
            fb -= va * (0.5 * rho * spec.cdA * airspeed)
            spin[0] += 32 * levels[0] * dt
            spin[1] += 55 * levels[0] * dt
        }

        // Ground contact
        var fw = V3(0, -spec.mass * gravity, 0)
        var touching = false
        let waterLevel = terrain.site.waterLevel
        let kFloat = spec.mass * gravity / (4 * 0.05), cFloat = 0.7 * sqrt(kFloat * spec.mass)
        if offGround.count != spec.contacts.count { offGround = [Float](repeating: 0, count: spec.contacts.count) }
        for (ci, cp) in spec.contacts.enumerated() {
            offGround[ci] += dt
            let rw = R * cp.pos
            let pw = pos + rw
            if cp.wheel && gear > 0.5 { continue }
            var ground = terrain.height(pw.x, pw.z)
            var water = false
            if let wl = waterLevel, wl > ground { ground = wl; water = true }
            let surf = terrain.surface(pw.x, pw.z)
            // wheels feel the small bumps of grass and dirt
            if !water && cp.wheel { ground += surf.rough * (vnoise(pw.x * 2.3, pw.z * 2.3, 91) - 0.5) }
            let d = ground - pw.y
            if d <= 0 { continue }
            let vp = vel + R * cross(omega, cp.pos)
            // a point that comes down after being clear of the ground for a moment makes a sound
            if offGround[ci] > 0.08 && (!water || cp.float || spec.hasFloats) {
                let hit = water ? -vp.y : -dot(vp, terrain.normal(pw.x, pw.z))
                if hit > touchImpact { touchImpact = hit; touchWheel = cp.wheel; touchWater = water }
            }
            offGround[ci] = 0
            if water {
                guard cp.float else {
                    // anything but a float digging into the water trips a floatplane over
                    if spec.hasFloats && !crashed && d > 0.05 { crashed = true; crashImpact = max(length(vel) * 0.5, 3) }
                    continue
                }
                touching = true
                if !crashed && -vp.y > cp.crashSpeed { crashed = true; crashImpact = -vp.y }
                let N = max(0, kFloat * min(d, 0.3) - cFloat * vp.y)
                var f = V3(0, N, 0)
                var fwd = R * V3(0, 0, -1); fwd.y = 0
                if length(fwd) > 0.05 {
                    fwd = normalize(fwd)
                    let side = V3(-fwd.z, 0, fwd.x)
                    let vr = dot(vp, fwd), vs = dot(vp, side)
                    // hull drag peaks at the "hump" before the float climbs onto its step and planes
                    let hull = 0.07 + 0.22 * exp(-pow((abs(vr) - 3) / 2.2, 2))
                    f -= fwd * (N * hull * clampf(vr / 0.3, -1, 1)) + side * (N * 0.9 * clampf(vs / 0.5, -1, 1))
                    tb.y -= servo.z * N * 0.04 * clampf(vr, 0, 3)          // water rudders
                }
                fw += f
                tb += Rt * cross(rw, f)
                continue
            }
            touching = true
            let n = terrain.normal(pw.x, pw.z)
            let vn = dot(vp, n)
            if !crashed && (-vn > cp.crashSpeed || (!cp.wheel && !cp.float && cp.crashSpeed < 3.2 && length(vp) > 13)) { crashed = true; crashImpact = max(-vn, length(vp) * 0.6) }
            let N = max(0, kSpring * min(d, 0.25) - cDamp * vn)
            var f = n * N
            let vt = vp - n * vn
            if cp.wheel && !crashed {
                let ang = cp.steer * servo.z * 0.45
                var fwd = R * V3(-sin(ang), 0, -cos(ang))
                fwd -= n * dot(fwd, n)
                let lf = length(fwd)
                if lf > 0.05 {
                    fwd /= lf
                    let side = cross(n, fwd)
                    let vr = dot(vt, fwd), vs = dot(vt, side)
                    // rolling resistance of the surface, plus brakes on the main wheels
                    let roll = surf.roll + (cp.steer == 0 ? c.brake * 0.55 * surf.grip : 0)
                    // tyre: side force builds with the slip angle, peaks, then falls away once the tyre slides
                    let x = atan2(vs, abs(vr) + 0.6) / 0.16
                    let ax = abs(x)
                    let lat = surf.grip * (ax < 1 ? ax * (1.5 - 0.5 * ax * ax) : 0.72 + 0.28 * exp(-(ax - 1) * 1.5)) * (x < 0 ? -1 : 1)
                    f -= (fwd * (roll * clampf(vr / 0.2, -1, 1)) + side * lat) * N
                }
            } else {
                let sp = length(vt)
                if sp > 1e-4 { f -= vt * (N * (crashed ? 0.7 : cp.mu) * min(1, sp / 0.2) / sp) }
            }
            fw += f
            tb += Rt * cross(rw, f)
        }
        onGround = touching
        if touching && !crashed && (R * V3(0, 1, 0)).y < -0.2 { crashed = true; crashImpact = 3 }

        // Integrate
        vel += (fw + R * fb) / spec.mass * dt
        pos += vel * dt
        let I = spec.inertia
        omega += (tb - cross(omega, I * omega)) / I * dt
        let wm = length(omega)
        if wm > 80 { omega *= 80 / wm }
        if wm > 1e-7 { q = simd_normalize(q * simd_quatf(angle: min(wm, 80) * dt, axis: omega / wm)) }
    }
}
