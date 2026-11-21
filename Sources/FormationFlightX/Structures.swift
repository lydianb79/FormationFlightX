import simd
import Foundation

// Things built on a flying site that a wing can hit or has to fly through: race gates, pylons, walls with
// windows, container stacks, city blocks, bridges. Every one is a box (or a few), which keeps both the picture
// and the collision test simple.

/// A solid box standing on the site. `yaw` turns it about the vertical; `rot`, when set, turns it any way at all.
/// A round one is an upright cylinder of radius `half.x`.
struct SolidBox {
    var c: V3, half: V3
    var yaw: Float = 0
    var color: V4
    var kind = 0            // surface: 0 plain, 2 offices, 3 glass tower, 4 houses, 5 corrugated sheet, 6 concrete panels, 7 brick or stone,
                            // 8 a lamp, 9 rock, 10 roof tiles, 11 timber boards
    var rot: simd_quatf? = nil
    var round = false
    var hidden = false      // hit but not drawn: something in `decor` shows it
    var orientation: simd_quatf { rot ?? simd_quatf(angle: yaw, axis: V3(0, 1, 0)) }
}

/// A gate to fly through. `c` is the middle of the opening; the heading is the way through it
/// (0 = away from the pilots, 90 = to their right).
struct Gate {
    var c: V3
    var heading: Float
    var w: Float, h: Float
    var dir: V3 { V3(sin(heading * deg), 0, -cos(heading * deg)) }
    var right: V3 { V3(cos(heading * deg), 0, sin(heading * deg)) }
}

extension Terrain {
    func ground(_ x: Float, _ z: Float) -> Float { max(height(x, z), site.waterLevel ?? -1e9) }

    /// A box whose base stands `lift` above the ground at (x, z).
    func add(_ x: Float, _ z: Float, _ size: V3, lift: Float = 0, yaw: Float = 0, _ color: V4, kind: Int = 0, base: Float? = nil) {
        let y = (base ?? ground(x, z)) + lift
        boxes.append(SolidBox(c: V3(x, y + size.y / 2, z), half: size / 2, yaw: yaw, color: color, kind: kind))
    }
    /// The same, taking the colour and the kind of surface together.
    func add(_ x: Float, _ z: Float, _ size: V3, lift: Float = 0, _ look: (V4, Int)) { add(x, z, size, lift: lift, look.0, kind: look.1) }

    /// A race gate: two striped posts and a bar across the top; raised gates get a bar underneath as well.
    func addGate(_ x: Float, _ z: Float, heading: Float, w: Float = 9, h: Float = 6, lift: Float = 1) {
        let g0 = ground(x, z)
        let gate = Gate(c: V3(x, g0 + lift + h / 2, z), heading: heading, w: w, h: h)
        let n = gates.count
        let a = n % 2 == 0 ? sc(0.98, 0.45, 0.08, 0.3) : sc(0.1, 0.6, 0.92, 0.3), white = sc(0.95, 0.95, 0.95, 0.3)
        let yaw = -heading * deg
        for side: Float in [-1, 1] {
            let p = gate.c + gate.right * (side * (w / 2 + 0.25))
            let top = lift + h + 0.5, seg = top / 4
            for k in 0..<4 {
                boxes.append(SolidBox(c: V3(p.x, g0 + (Float(k) + 0.5) * seg, p.z), half: V3(0.25, seg / 2, 0.25), yaw: yaw, color: k % 2 == 0 ? a : white))
            }
        }
        boxes.append(SolidBox(c: V3(x, g0 + lift + h + 0.25, z), half: V3(w / 2 + 0.5, 0.25, 0.25), yaw: yaw, color: a))
        if lift > 2 { boxes.append(SolidBox(c: V3(x, g0 + lift - 0.25, z), half: V3(w / 2 + 0.5, 0.25, 0.25), yaw: yaw, color: a)) }
        gates.append(gate)
    }

    /// A wall across the way with a window to fly through. `heading` is the way through the window.
    func addWindowWall(_ x: Float, _ z: Float, heading: Float, width: Float, height: Float, hole: (w: Float, h: Float, sill: Float), _ color: V4) {
        let yaw = -heading * deg, r = V3(cos(heading * deg), 0, sin(heading * deg)), g0 = ground(x, z)
        let side = (width - hole.w) / 2
        for s: Float in [-1, 1] {
            let p = V3(x, 0, z) + r * (s * (hole.w / 2 + side / 2))
            boxes.append(SolidBox(c: V3(p.x, g0 + height / 2, p.z), half: V3(side / 2, height / 2, 0.6), yaw: yaw, color: color))
        }
        if hole.sill > 0.1 { boxes.append(SolidBox(c: V3(x, g0 + hole.sill / 2, z), half: V3(hole.w / 2, hole.sill / 2, 0.6), yaw: yaw, color: color)) }
        let over = height - hole.sill - hole.h
        if over > 0.1 { boxes.append(SolidBox(c: V3(x, g0 + height - over / 2, z), half: V3(hole.w / 2, over / 2, 0.6), yaw: yaw, color: color)) }
    }

    /// Everything that stands on this site. Called once, when the terrain is made.
    func layoutStructures() {
        var rng = LCG(UInt64(site.seed) + 777)
        let concrete = sc(0.62, 0.62, 0.6), steel = sc(0.5, 0.52, 0.56, 0.4), yellow = sc(0.95, 0.75, 0.1, 0.3), red = sc(0.8, 0.15, 0.12, 0.3)
        switch site.layout {
        case 1:     // stadium circuit: an eight-gate loop on open grass, all left turns
            let track: [(Float, Float, Float, Float)] = [(25, -50, 0, 1), (30, -120, 350, 1), (0, -170, 290, 7), (-60, -175, 250, 1),
                                                         (-110, -140, 190, 1), (-115, -80, 170, 9), (-85, -35, 110, 1), (-30, -22, 80, 1)]
            for g in track { addGate(g.0, g.1, heading: g.2, lift: g.3) }
            // grandstands along the far side, and marker pylons inside the turns
            for p: (Float, Float) in [(0, -110), (-70, -110), (-50, -70)] { add(p.0, p.1, V3(1.2, 14, 1.2), yellow) }
        case 2:     // forest slalom: gates in a ride cut through the trees, clockwise
            let track: [(Float, Float, Float, Float)] = [(20, -60, 0, 1), (40, -150, 20, 1), (110, -220, 70, 1), (200, -200, 130, 1),
                                                         (230, -120, 180, 1), (190, -55, 235, 1), (105, -32, 275, 1)]
            for g in track { addGate(g.0, g.1, heading: g.2, w: 8, h: 6, lift: g.3) }
            // the forest closes in along both sides of the ride
            for i in gates.indices {
                let a = gates[i].c, c = gates[(i + 1) % gates.count].c
                let ab = V3(c.x - a.x, 0, c.z - a.z), len = length(ab), side = V3(-ab.z, 0, ab.x) / max(len, 1)
                var d: Float = 0
                while d < len {
                    for s: Float in [-1, 1] {
                        let p = a + ab * (d / len) + side * (s * rng.range(17, 46))
                        if abs(p.x) < 60 && p.z > -40 { continue }                  // not on the field itself
                        trees.append(Tree(p: V3(p.x, height(p.x, p.z), p.z), h: rng.range(12, 20)))
                    }
                    d += 5
                }
            }
        case 3:     // canyon run: east along the canyon floor, then back over the rim through high gates
            func zc(_ x: Float) -> Float { -170 + 80 * sin(x / 210) }
            for x: Float in [-380, -260, -140, -20, 100, 220, 340] {
                let slope = 80 / 210 * cos(x / 210)                     // dz/dx of the canyon's line
                addGate(x, zc(x), heading: 90 + atan(slope) / deg, w: 12, h: 8, lift: 4)
            }
            for (x, z) in [(Float(430), Float(-60)), (120, -45), (-200, -45), (-470, -70)] { addGate(x, z, heading: 270, w: 12, h: 8, lift: 14) }
        case 4:     // pylon park: things to fly round, through and under
            for k in 0..<7 { for b in 0..<6 {                                                                                       // slalom line, banded
                add(-150 + Float(k) * 50, -70, V3(1.6, 26.0 / 6, 1.6), lift: Float(b) * 26 / 6, (k + b) % 2 == 0 ? red : sc(0.95, 0.95, 0.95, 0.3))
            } }
            addWindowWall(-120, -150, heading: 90, width: 46, height: 22, hole: (10, 7, 6), sc(0.85, 0.5, 0.15))
            addWindowWall(-20, -150, heading: 90, width: 46, height: 22, hole: (7, 5, 11), sc(0.2, 0.55, 0.8))
            addWindowWall(80, -150, heading: 90, width: 46, height: 22, hole: (14, 5, 2), sc(0.3, 0.7, 0.35))
            // an arch, a low bar, and a tunnel
            for s: Float in [-1, 1] { add(60 + s * 11, -230, V3(5, 20, 5), concrete) }
            add(60, -230, V3(27, 4, 5), lift: 20, concrete)
            for s: Float in [-1, 1] { add(-60 + s * 14, -230, V3(1, 5, 1), yellow) }
            add(-60, -230, V3(29, 0.6, 0.6), lift: 5, yellow)
            for s: Float in [-1, 1] { add(170, -110 + s * 5.5, V3(46, 8, 1), sc(0.5, 0.5, 0.52)) }
            add(170, -110, V3(46, 1, 12), lift: 8, sc(0.45, 0.45, 0.48))
            // two hoops high up
            for (x, z, hd) in [(Float(-170), Float(-120), Float(0)), (140, -40, 90)] { addGate(x, z, heading: hd, w: 10, h: 10, lift: 20) }
            gates.removeAll()                                            // hoops here are for fun, not for timing
        case 5:     // container yard: lanes between stacks, cranes to fly under
            let paint = [sc(0.7, 0.2, 0.15, 0.2), sc(0.15, 0.35, 0.6, 0.2), sc(0.85, 0.55, 0.1, 0.2), sc(0.2, 0.5, 0.35, 0.2), sc(0.55, 0.55, 0.58, 0.2), sc(0.5, 0.2, 0.4, 0.2)]
            for row in 0..<7 {
                let z = -42 - Float(row) * 24
                var x: Float = -250
                while x <= 250 {
                    defer { x += 12.7 }
                    if abs(x - 8) < 20 || rng.next() < 0.14 { continue }            // the lane ahead of the launch, and gaps to dart through
                    let levels = 1 + Int(rng.next() * rng.next() * 5)
                    for l in 0..<levels { add(x, z, V3(12.2, 2.6, 5), lift: Float(l) * 2.6, paint[Int(rng.next() * 5.99)], kind: 5) }
                }
            }
            for x: Float in [-130, 130] {                                           // gantry cranes across the lanes
                for z: Float in [-30, -200] { for s: Float in [-1, 1] { add(x + s * 9, z, V3(1.6, 34, 1.6), yellow) } }
                add(x, -115, V3(22, 3, 180), lift: 34, yellow)
                add(x, -90, V3(6, 4, 8), lift: 30, steel)
            }
            for x: Float in [-240, 240] { add(x, -20, V3(0.8, 30, 0.8), steel); add(x, -20, V3(5, 1, 2), lift: 30, steel) }      // light masts
        case 6:     // downtown: blocks of towers on a grid of streets
            let glass = [sc(0.36, 0.46, 0.56, 0.5), sc(0.5, 0.52, 0.55, 0.3), sc(0.62, 0.56, 0.48, 0.15), sc(0.3, 0.36, 0.42, 0.5), sc(0.7, 0.68, 0.64, 0.15), sc(0.42, 0.34, 0.3, 0.15)]
            var rows: [Float] = (0..<5).map { -42 - 84 * Float($0) }
            rows += [42, 126, 210]
            for cz in rows {
                for i in -6..<6 {
                    let cx = (Float(i) + 0.5) * 84
                    if cz == 42 && abs(cx) < 130 { continue }                       // the square where the pilots stand
                    add(cx, cz, V3(60, 0.25, 60), sc(0.58, 0.58, 0.56))             // the block's pavement
                    let pick = rng.next(), far = min(1, (abs(cx) + abs(cz)) / 500)
                    if pick < 0.5 {
                        let w = rng.range(30, 50), d = rng.range(30, 50)
                        add(cx, cz, V3(w, rng.range(28, 60) + 60 * rng.next() * (1 - 0.5 * far), d), { let c = glass[Int(rng.next() * 5.99)]; return (c, c.w >= 0.45 ? 3 : 2) }())
                    } else if pick < 0.85 {
                        let h1 = rng.range(18, 70), h2 = rng.range(14, 50)
                        add(cx - 15, cz, V3(26, h1, rng.range(34, 52)), { let c = glass[Int(rng.next() * 5.99)]; return (c, c.w >= 0.45 ? 3 : 2) }())
                        add(cx + 15, cz, V3(26, h2, rng.range(34, 52)), { let c = glass[Int(rng.next() * 5.99)]; return (c, c.w >= 0.45 ? 3 : 2) }())
                    } else {
                        add(cx, cz, V3(52, rng.range(6, 10), 52), { let c = glass[Int(rng.next() * 5.99)]; return (c, c.w >= 0.45 ? 3 : 2) }())       // a low hall
                    }
                }
            }
            // walkways across the avenue ahead: fly under or over
            add(0, -126, V3(26, 3.5, 8), lift: 26, steel)
            add(0, -294, V3(26, 3.5, 8), lift: 44, steel)
            add(84, -84, V3(8, 3.5, 26), lift: 34, steel)
            add(-84, -168, V3(8, 3.5, 26), lift: 20, steel)
        case 7:     // harbour town: low streets, quay cranes, ships, and a bridge out over the water
            let walls = [sc(0.8, 0.74, 0.62, 0.1), sc(0.7, 0.42, 0.32, 0.1), sc(0.6, 0.66, 0.7, 0.1), sc(0.85, 0.82, 0.76, 0.1), sc(0.5, 0.36, 0.3, 0.1)]
            for cz in [Float(-45), -95, -145, 110, 160] {
                var cx: Float = -360
                while cx <= 360 {
                    defer { cx += 46 }
                    if abs(cx - 6) < 30 && cz < 0 { continue }                      // the street ahead of the launch
                    if cz > 0 && abs(cx) < 110 && cz < 140 { continue }             // the pilots' quay-side square
                    if rng.next() < 0.1 { continue }
                    let h = rng.range(7, 26), w = rng.range(26, 36), d = rng.range(24, 34), col = walls[Int(rng.next() * 4.99)]
                    if h < 15 { house(cx, cz, w, d, wall: h, rise: rng.range(4, 6.5), col, roof: rng.next() < 0.6 ? sc(0.56, 0.26, 0.18, 0.05) : sc(0.26, 0.27, 0.31, 0.1)) }
                    else { add(cx, cz, V3(w, h, d), col, kind: 2) }
                }
            }
            for x: Float in [-260, -120, 150, 290] {                                // quay cranes, booms out over the water
                for s: Float in [-1, 1] { add(x + s * 8, -205, V3(1.8, 40, 1.8), red); add(x + s * 8, -222, V3(1.8, 40, 1.8), red) }
                add(x, -235, V3(5, 4, 80), lift: 40, red)
                add(x, -213, V3(8, 6, 10), lift: 44, steel)
            }
            for (x, z) in [(Float(-190), Float(-262)), (220, -270)] {               // ships alongside
                add(x, z, V3(110, 11, 18), sc(0.14, 0.18, 0.3, 0.2), base: site.waterLevel ?? 0)
                add(x + 38, z, V3(16, 16, 14), lift: 11, sc(0.9, 0.9, 0.88, 0.2), base: site.waterLevel ?? 0)
                for k in 0..<5 { add(x - 40 + Float(k) * 13, z, V3(12.2, 5.2, 12), lift: 11, walls[k % 5], kind: 5, base: site.waterLevel ?? 0) }
            }
            let wl = site.waterLevel ?? 0                                           // the bridge: deck 26 m up, two towers
            add(0, -420, V3(760, 3, 16), lift: 26, sc(0.4, 0.42, 0.45, 0.2), base: wl)
            for x: Float in [-300, -150, 0, 150, 300] { for s: Float in [-1, 1] { add(x, -420 + s * 6, V3(4, 26, 3), concrete, base: wl) } }
            for x: Float in [-150, 150] { for s: Float in [-1, 1] { add(x, -420 + s * 9, V3(4, 78, 3), red, base: wl) }; add(x, -420, V3(4, 4, 18), lift: 74, red, base: wl) }
        default: break
        }
        furnish()
        // trees give way to what was built, and to the way through the gates
        if !boxes.isEmpty || !gates.isEmpty {
            let path = gates.map { $0.c }
            trees.removeAll { t in
                for b in boxes where b.rot == nil && abs(t.p.x - b.c.x) < max(b.half.x, b.half.z) + 4 && abs(t.p.z - b.c.z) < max(b.half.x, b.half.z) + 4 { return true }
                for i in path.indices {
                    let a = path[i], c = path[(i + 1) % path.count]
                    let ab = V3(c.x - a.x, 0, c.z - a.z), ap = V3(t.p.x - a.x, 0, t.p.z - a.z)
                    let k = clampf(dot(ap, ab) / max(dot(ab, ab), 1), 0, 1)
                    if length(ap - ab * k) < 15 { return true }
                }
                return false
            }
        }
    }

    /// Whether something `reach` metres across at `p` touches anything built here.
    func strikes(_ p: V3, reach: Float) -> Bool {
        for b in boxes {
            let d = p - b.c
            if let q = b.rot {
                let m = length(b.half) + reach
                if abs(d.x) > m || abs(d.y) > m || abs(d.z) > m { continue }
                let l = q.inverse.act(d)
                if abs(l.x) < b.half.x + reach && abs(l.y) < b.half.y + reach && abs(l.z) < b.half.z + reach { return true }
                continue
            }
            if abs(d.y) > b.half.y + reach { continue }
            if b.round {
                let r = b.half.x + reach
                if d.x * d.x + d.z * d.z < r * r { return true }
                continue
            }
            let m = max(b.half.x, b.half.z) * 1.42 + reach
            if abs(d.x) > m || abs(d.z) > m { continue }
            let c = cos(b.yaw), s = sin(b.yaw)
            let lx = d.x * c - d.z * s, lz = d.x * s + d.z * c
            if abs(lx) < b.half.x + reach && abs(lz) < b.half.z + reach { return true }
        }
        return false
    }

    /// The picture of everything built here, to go in with the rest of the scenery.
    func buildStructureMesh(into m: inout MeshBuilder) {
        var rng = LCG(UInt64(site.seed) + 4242)
        for b in boxes where !b.hidden {
            let q = b.orientation
            // the shader reads the kind of surface from the whole part of alpha, the gloss from the fraction
            // anything plain and brown is timber, and is drawn boarded
            let c = b.color, timber = b.kind == 0 && c.x > c.y * 1.15 && c.y > c.z * 1.1 && c.x > 0.25 && c.x < 0.62
            let col = V4(c.x, c.y, c.z, Float(timber ? 11 : b.kind) + min(c.w, 0.9))
            if b.round {
                m.cylinder(from: b.c - V3(0, b.half.y, 0), to: b.c + V3(0, b.half.y, 0), r0: b.half.x, r1: b.half.x, seg: b.half.x > 3 ? 24 : 12, color: col)
                continue
            }
            m.box(center: b.c, size: b.half * 2, color: col, rot: q)
            guard b.kind == 2 || b.kind == 3, b.half.y > 6, b.rot == nil else { continue }
            // roofs of the larger buildings: a parapet, plant rooms, air handlers, a mast now and then
            let top = b.c + V3(0, b.half.y, 0), grey = V4(0.42, 0.42, 0.44, 0.1)
            for (dx, dz, sx, sz) in [(Float(0), Float(1), b.half.x, Float(0.2)), (0, -1, b.half.x, 0.2), (1, 0, 0.2, b.half.z), (-1, 0, 0.2, b.half.z)] {
                m.box(center: top + q.act(V3(dx * (b.half.x - 0.2), 0.45, dz * (b.half.z - 0.2))), size: V3(sx * 2, 0.9, sz * 2), color: V4(b.color.x * 0.8, b.color.y * 0.8, b.color.z * 0.8, 0.05), rot: q)
            }
            m.box(center: top + q.act(V3(b.half.x * rng.range(-0.3, 0.3), 1.6, b.half.z * rng.range(-0.3, 0.3))), size: V3(b.half.x * 0.6, 3.2, b.half.z * 0.5), color: grey, rot: q)
            for _ in 0..<Int(rng.range(2, 6)) {
                let o = V3(b.half.x * rng.range(-0.8, 0.8), 0.7, b.half.z * rng.range(-0.8, 0.8))
                m.box(center: top + q.act(o), size: V3(rng.range(1.5, 3.5), 1.4, rng.range(1.5, 3)), color: V4(0.6, 0.61, 0.62, 0.3), rot: q)
            }
            if b.half.y > 30 && rng.next() < 0.5 {
                let o = top + q.act(V3(b.half.x * 0.3, 3.2, 0))
                m.cylinder(from: o, to: o + V3(0, rng.range(8, 20), 0), r0: 0.25, r1: 0.08, seg: 6, color: V4(0.8, 0.8, 0.82, 0.4))
            }
        }
        m.append(decor)
    }
}

// MARK: - Racing

extension Game {
    /// Start the lap count again: after a launch, a change of site, or a restart of the session.
    func resetRace() {
        raceNext = 0; raceRunning = false; raceTime = 0; raceLaps = 0
        racePrev = aircraft.pos
    }

    /// Whether the wing went through the next gate since the last frame, and what follows from it.
    func updateRace(dt: Float) {
        let gates = terrain.gates
        guard !gates.isEmpty else { gateMarker = nil; return }
        let g = gates[min(raceNext, gates.count - 1)]
        gateMarker = (g.c, g.dir, g.w, g.h)
        if raceRunning && !aircraft.crashed { raceTime += dt }
        let p0 = racePrev, p1 = aircraft.pos
        racePrev = p1
        let s0 = dot(p0 - g.c, g.dir), s1 = dot(p1 - g.c, g.dir)
        guard !aircraft.crashed, s0 < 0, s1 >= 0, s1 - s0 < 30 else { return }
        let hit = p0 + (p1 - p0) * (-s0 / (s1 - s0)) - g.c
        guard abs(dot(hit, g.right)) < g.w / 2, abs(hit.y) < g.h / 2 else { return }
        if raceNext == 0 {
            if raceRunning {
                raceLaps += 1
                let t = raceTime
                let best = raceBest.map { t < $0 } ?? true
                if best { raceBest = t }
                say(String(format: "Lap %d: %.2f s%@", raceLaps, t, best ? "  ·  best lap" : ""), 4)
                if together { sendChat(String(format: "Lap %d at %@ in %.2f s%@", raceLaps, site.displayName, t, best ? " (my best)" : "")) }
            } else {
                say("Through the start gate: the clock is running", 2.5)
            }
            raceRunning = true; raceTime = 0
        }
        raceNext = (raceNext + 1) % gates.count
    }

    /// The race line for the display: which gate is next, the running lap and the best one.
    var raceStatus: String {
        let n = terrain.gates.count
        guard n > 0 else { return "" }
        var s = raceRunning ? String(format: "Gate %d/%d   %.1f s", raceNext == 0 ? n : raceNext, n, raceTime) : "Fly through the start gate"
        if raceLaps > 0 { s += "   lap \(raceLaps + 1)" }
        if let b = raceBest { s += String(format: "   best %.2f s", b) }
        return s
    }
}
