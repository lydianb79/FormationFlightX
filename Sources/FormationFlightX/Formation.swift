import simd
import Foundation

/// The shapes a three-ship can fly. Number 1 leads; numbers 2 and 3 hold a slot relative to the lead.
enum FormationKind: Int, CaseIterable {
    case vic, echelonRight, echelonLeft, trail, abreast

    var name: String { ["Vic", "Echelon right", "Echelon left", "Line astern", "Line abreast"][rawValue] }
    var blurb: String {
        ["Number 2 on the right, number 3 on the left, both stepped back",
         "Both wingmen stepped back to the right of the lead",
         "Both wingmen stepped back to the left of the lead",
         "One behind the other, each a little lower than the one ahead",
         "Side by side, wingtip to wingtip with the lead"][rawValue]
    }

    /// Slot of wingman `n` (1 or 2) in spacings: x to the lead's right, y up, z behind the lead.
    func offset(_ n: Int) -> V3 {
        let k = Float(n)
        switch self {
        case .vic: return V3(n == 1 ? 1 : -1, 0, 0.8)
        case .echelonRight: return V3(k, 0, 0.8 * k)
        case .echelonLeft: return V3(-k, 0, 0.8 * k)
        case .trail: return V3(0, -0.25 * k, 1.6 * k)
        case .abreast: return V3(n == 1 ? 1 : -1, 0, 0)
        }
    }
}

enum Formation {
    static let spacingNames = ["Tight", "Normal", "Loose"]
    /// Distance between neighbours, centre to centre, in wingspans of the lead's aircraft.
    static let spacingSpans: [Float] = [1.5, 2.5, 5]

    static func spacing(_ i: Int, span: Float) -> Float { spacingSpans[min(max(i, 0), 2)] * max(span, 0.8) }

    /// The lead's direction of travel over the ground, and the direction to its right.
    static func frame(of lead: Aircraft) -> (fwd: V3, right: V3) {
        var f = V3(lead.vel.x, 0, lead.vel.z)
        if length(f) < 2 { f = lead.forward; f.y = 0 }
        f = length(f) > 0.01 ? normalize(f) : V3(0, 0, -1)
        return (f, cross(f, V3(0, 1, 0)))
    }

    /// Where wingman `n` belongs right now.
    static func slot(_ n: Int, lead: Aircraft, kind: FormationKind, spacing s: Float) -> V3 {
        let (f, r) = frame(of: lead)
        let o = kind.offset(n) * s
        return lead.pos + r * o.x + V3(0, o.y, 0) - f * o.z
    }
}

/// Another aircraft in the formation: a pilot on the network, or a computer-flown partner.
final class Wingman {
    let id: UInt32
    var name: String
    var specIndex: Int
    var aircraft: Aircraft
    var ai: FormationPilot?             // nil: a pilot on the network
    var controls = Controls()
    var smoke = false
    var crashTimer: Float = 0
    // network pilots
    var leadEpoch: UInt32 = 0
    var lastHello = 0.0, lastState = 0.0        // local time of the latest messages
    var hello = NetHello()
    private var base = NetState()               // latest state, and the local time at which it was true
    private var baseTime = 0.0
    private var clockOff = Double.infinity      // sender's clock to ours, estimated from the fastest deliveries
    private var errPos = V3.zero                // what is drawn minus what is predicted: eased to zero, so corrections never jump
    private var errQ = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var hasState = false

    init(id: UInt32, name: String, specIndex: Int) {
        self.id = id; self.name = name
        self.specIndex = min(max(specIndex, 0), AircraftLibrary.all.count - 1)
        aircraft = Aircraft(AircraftLibrary.all[self.specIndex])
        aircraft.unlimitedBattery = true
    }

    /// Flying and up to date: drawn, and part of the formation.
    func present(_ now: Double) -> Bool { ai != nil || (hasState && now - lastState < 1.0) }

    private func predict(_ t: Double) -> (V3, simd_quatf) {
        let age = Float(min(max(t - baseTime, 0), 0.5))
        let p = base.pos + base.vel * age
        let w = length(base.omega)
        let q = w > 1e-5 && !base.crashed ? simd_normalize(base.q * simd_quatf(angle: w * age, axis: base.omega / w)) : base.q
        return (p, q)
    }

    /// A new state from the network, received at local time `at`.
    func receive(_ s: NetState, at: Double) {
        if hasState && s.time <= base.time && at - lastState < 1 { return }     // out of order
        let now = at
        // The fastest delivery so far gives the clock difference; later, slower packets are placed by their own
        // time stamps, so jitter on the network does not shake the aircraft. The estimate creeps up slowly in
        // case the clocks drift apart.
        let off = at - s.time
        clockOff = clockOff.isFinite && abs(off - clockOff) < 1 ? min(clockOff + 0.0002, off) : off
        let was = hasState && now - lastState < 1 ? predict(now) : nil
        if s.spec != base.spec || !hasState {
            specIndex = min(Int(s.spec), AircraftLibrary.all.count - 1)
            aircraft = Aircraft(AircraftLibrary.all[specIndex])
        }
        base = s; baseTime = s.time + clockOff; lastState = at; hasState = true
        let (p, q) = predict(now)
        if let (wp, wq) = was, distance(wp + errPos, p) < 8 {
            errPos = wp + errPos - p
            errQ = simd_normalize(q.inverse * (wq * errQ))
        } else {
            errPos = .zero; errQ = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        smoke = s.smoke
    }

    /// Move a network pilot's aircraft to where it is now.
    func extrapolate(now: Double, dt: Float) {
        guard hasState else { return }
        let k = exp(-dt * 12)
        errPos *= k
        errQ = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), errQ, k)
        let (p, q) = predict(now)
        let ac = aircraft
        ac.pos = p + errPos; ac.q = simd_normalize(q * errQ); ac.vel = base.vel; ac.omega = base.omega
        ac.servo = base.servo; ac.crashed = base.crashed; ac.airspeed = length(base.vel)
        for i in ac.levels.indices { ac.levels[i] = base.level }
        for i in ac.spin.indices { ac.spin[i] += (base.level > 0.01 ? 12 + 45 * sqrt(min(base.level, 1)) : 0) * dt }
        ac.renderPos = ac.pos; ac.renderQ = ac.q
    }
}

/// Computer pilot for a formation partner. As the lead it flies a wide, steady racetrack that is easy to
/// follow; as a wingman it holds its slot on whoever leads.
struct FormationPilot {
    var wp = 0
    private var thrI: Float = 0.55, pitchI: Float = 0
    /// Racetrack corners relative to the pilot's position (x east, z south): long straights, wide turns.
    static let circuit: [SIMD2<Float>] = [SIMD2(190, -70), SIMD2(190, -300), SIMD2(-190, -300), SIMD2(-190, -70)]
    static let altitude: Float = 38

    private func inner(_ ac: Aircraft, rollT: Float, pitchT: Float, throttle: Float) -> Controls {
        var c = Controls()
        c.aileron = clampf(2.5 * (rollT - ac.roll) + 0.25 * ac.omega.z, -1, 1)
        c.elevator = clampf(3 * (pitchT - ac.pitch) - 0.3 * ac.omega.x + 0.25 * abs(ac.roll), -1, 1)
        c.rudder = clampf(0.3 * (rollT - ac.roll), -0.5, 0.5)
        c.throttle = throttle
        return c
    }

    private func headingError(_ ac: Aircraft, to d: V3) -> Float {
        // steer by where the aircraft is going, not where the nose points: a tailless wing wags its nose, and
        // feeding that back into the bank keeps the wag alive
        var fh = V3(ac.vel.x, 0, ac.vel.z)
        if length(fh) < 3 { fh = ac.forward; fh.y = 0 }
        fh = length(fh) > 0.01 ? normalize(fh) : V3(0, 0, -1)
        var dh = d; dh.y = 0
        guard length(dh) > 0.01 else { return 0 }
        dh = normalize(dh)
        return atan2(-cross(fh, dh).y, dot(fh, dh))
    }

    /// Speed the lead holds: comfortably above the stall, with power in hand for the wingmen to catch up.
    static func cruise(_ spec: AircraftSpec) -> Float { clampf(spec.stallSpeed * 1.9, 9, 24) }

    /// `reach` is how far the outermost wingman sits to the side. The lead turns wide enough for the wingman on
    /// the inside to keep flying and the one on the outside to keep up: their speeds differ from the lead's by
    /// the ratio of that distance to the turn radius.
    mutating func lead(_ ac: Aircraft, terrain: Terrain, reach: Float = 3, dt: Float) -> Controls {
        let home = terrain.pilotPos
        let target = FormationPilot.circuit[wp]
        let to = V3(home.x + target.x - ac.pos.x, 0, home.z + target.y - ac.pos.z)
        let vc = FormationPilot.cruise(ac.spec)
        let radius = clampf(9 * reach, vc * vc / (gravity * tan(0.5)), 95)
        let maxBank = atan(vc * vc / (gravity * radius))
        if length(to) < max(55, radius + 12) { wp = (wp + 1) % FormationPilot.circuit.count }
        let herr = headingError(ac, to: to)
        let ground = max(terrain.height(ac.pos.x, ac.pos.z), terrain.site.waterLevel ?? -1e9)
        let altT = max(home.y + FormationPilot.altitude, ground + 22)
        // after a hand launch, climb straight ahead before the first turn so the others can form up behind
        let low = ac.pos.y - ground < 12
        let rollT = low ? 0 : clampf(herr * 1.1, -maxBank, maxBank)
        let pitchT = clampf(0.02 * (altT - ac.pos.y) - 0.04 * ac.vel.y, -0.14, 0.24)
        let v = FormationPilot.cruise(ac.spec)
        thrI = clampf(thrI + 0.04 * (v - ac.airspeed) * dt, 0.15, 0.85)
        return inner(ac, rollT: rollT, pitchT: pitchT, throttle: clampf(thrI + 0.1 * (v - ac.airspeed) + 0.01 * (altT - ac.pos.y), 0.1, 1))
    }

    mutating func follow(_ ac: Aircraft, lead: Aircraft, slot: V3, terrain: Terrain, dt: Float) -> Controls {
        let (f, r) = Formation.frame(of: lead)
        let e = slot - ac.pos
        let along = dot(e, f), ey = e.y
        let vl = max(length(lead.vel), FormationPilot.cruise(ac.spec) * 0.7)
        // steer for a point ahead of the slot: far away this is a pursuit, close in it becomes the lead's heading
        // with a correction in proportion to the sideways error
        let look = max(16, 1.6 * vl)
        var aim = e + f * look
        if along < -0.6 * look { aim = f * look + r * clampf(dot(e, r), -look, look) }      // in front of the slot: do not turn back
        let herr = headingError(ac, to: aim)
        let near = length(e) < 40
        let ground = max(terrain.height(ac.pos.x, ac.pos.z), terrain.site.waterLevel ?? -1e9)
        let low = ac.pos.y - ground < 5
        // Speed first: close to the stall a wing that is asked to climb or to bank hard only mushes and wallows,
        // so both are allowed only as far as the speed in hand permits.
        let vs = ac.spec.stallSpeed
        let margin = clampf((ac.airspeed - 1.2 * vs) / (0.5 * vs), 0, 1)
        let maxBank = 0.9 * (0.35 + 0.65 * margin)
        // a wide wing answers the ailerons with a slow swing of the nose; steering it as sharply as a small one keeps that swing going
        let steer = 1.8 / clampf(ac.spec.span / 1.5, 1, 1.6)
        let rollT = low ? 0 : clampf(steer * herr + (near ? lead.roll : 0), -maxBank, maxBank)
        // speed: the lead's, faster when behind the slot and slower when ahead of it
        // Speeds are compared over the ground, because that is how the slot moves; the wind then needs no thought.
        let vg = length(V3(ac.vel.x, 0, ac.vel.z))
        var dv = vl + clampf(0.55 * along, -0.3 * vl, 7) - vg
        dv = max(dv, ac.spec.stallSpeed * 1.25 - ac.airspeed)           // never slow down into the stall
        // height: the lead's flight path, plus a correction for the height error and its rate
        let gamma = near ? asin(clampf(lead.vel.y / max(length(lead.vel), 3), -0.5, 0.5)) : 0
        pitchI = clampf(pitchI + 0.02 * clampf(ey, -3, 3) * dt, -0.15, 0.15)
        var pitchT = gamma + min(clampf(0.05 * ey + 0.05 * (lead.vel.y - ac.vel.y), -0.25, 0.3) + pitchI, 0.04 + 0.26 * margin)
        // A wing has no brakes. Sliding ahead of the slot with more speed than wanted, the only way to lose it is
        // to stop descending and let the nose come up a little: height is cheap to give back afterwards.
        let over = clampf((-along - 0.8) / 5, 0, 1) * clampf(-dv / 1.5, 0, 1)
        pitchT = max(pitchT, gamma - 0.25 * (1 - over)) + 0.1 * over
        if low { pitchT = max(pitchT, 0.12) }
        thrI = clampf(thrI + (0.05 * dv + (near ? 0.015 * clampf(along, -4, 4) : 0)) * dt, 0.1, 0.9)
        return inner(ac, rollT: rollT, pitchT: pitchT, throttle: clampf(thrI + 0.16 * dv, 0, 1))
    }
}
