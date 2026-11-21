import simd
import Foundation

// The pieces flying sites are furnished with: houses with roofs, masts and cables, conveyors, turbines, boats,
// airliners, needles of rock. Each one draws itself (into `decor`, or as boxes) and leaves behind the solids a
// wing can hit.

func sc(_ r: Float, _ g: Float, _ b: Float, _ gloss: Float = 0.06) -> V4 { V4(r, g, b, gloss) }

extension Terrain {
    /// Ground or water level, whichever is higher.
    func gnd(_ x: Float, _ z: Float) -> Float { max(height(x, z), site.waterLevel ?? -1e9) }
    private func yq(_ yaw: Float) -> simd_quatf { simd_quatf(angle: yaw, axis: V3(0, 1, 0)) }
    /// A colour that tells the shader what kind of surface it is on.
    func surf(_ c: V4, _ kind: Int) -> V4 { V4(c.x, c.y, c.z, Float(kind) + min(c.w, 0.9)) }

    /// Something to hit that is drawn by other means.
    func guardBox(_ c: V3, _ size: V3, yaw: Float = 0) { boxes.append(SolidBox(c: c, half: size / 2, yaw: yaw, color: .zero, hidden: true)) }

    /// A straight member from a to b: a girder, a conveyor, a jib, a blade. `w` is its width, `h` its depth.
    func beam(_ a: V3, _ b: V3, w: Float, h: Float, _ color: V4, kind: Int = 0, solid: Bool = true, show: Bool = true) {
        let d = b - a, len = length(d)
        guard len > 0.01 else { return }
        let ex = d / len
        var ez = cross(ex, V3(0, 1, 0))
        ez = length(ez) < 0.01 ? V3(0, 0, 1) : normalize(ez)
        let q = simd_quatf(simd_float3x3(columns: (ex, cross(ez, ex), ez)))
        if solid { boxes.append(SolidBox(c: (a + b) / 2, half: V3(len / 2, h / 2, w / 2), color: color, kind: kind, rot: q, hidden: !show)) }
        else if show { decor.box(center: (a + b) / 2, size: V3(len, h, w), color: surf(color, kind), rot: q) }
    }

    /// An upright round thing: a mast, a tank, a tower.
    func column(_ x: Float, _ z: Float, r: Float, h: Float, lift: Float = 0, _ color: V4, kind: Int = 0, base: Float? = nil, hidden: Bool = false) {
        let y = (base ?? gnd(x, z)) + lift
        boxes.append(SolidBox(c: V3(x, y + h / 2, z), half: V3(r, h / 2, r), color: color, kind: kind, round: true, hidden: hidden))
    }

    /// A pitched roof over a rectangle whose eaves are at `c`; the ridge runs the long way. Hipped, the ends slope too.
    func roof(_ c: V3, _ sx: Float, _ sz: Float, rise: Float, yaw: Float, _ plain: V4, gable: V4, over: Float = 0.5, hip: Bool = false, tiled: Bool = true) {
        if sz > sx { roof(c, sz, sx, rise: rise, yaw: yaw + .pi / 2, plain, gable: gable, over: over, hip: hip, tiled: tiled); return }
        let color = tiled && plain.w < 1.5 ? surf(plain, 10) : plain
        let q = yq(yaw), w = sx / 2 + over, d = sz / 2 + over, rx = hip ? max(w - d, 0) : w
        func P(_ x: Float, _ y: Float, _ z: Float) -> V3 { c + q.act(V3(x, y, z)) }
        decor.quad(P(-w, 0, d), P(w, 0, d), P(rx, rise, 0), P(-rx, rise, 0), color)
        decor.quad(P(w, 0, -d), P(-w, 0, -d), P(-rx, rise, 0), P(rx, rise, 0), color)
        let end = hip ? color : gable, e = hip ? w : sx / 2, ed = hip ? d : sz / 2
        decor.tri(P(-e, 0, -ed), P(-e, 0, ed), P(-rx, rise, 0), end)
        decor.tri(P(e, 0, ed), P(e, 0, -ed), P(rx, rise, 0), end)
    }

    /// A house: walls, a pitched roof, and something to hit where the roof is.
    func house(_ x: Float, _ z: Float, _ sx: Float, _ sz: Float, wall h: Float, rise: Float, yaw: Float = 0, _ color: V4, roof rc: V4, kind: Int = 4, hip: Bool = false, lift: Float = 0) {
        let g = gnd(x, z) + lift, sunk: Float = lift > 0 ? 0 : 3                 // walls go down into sloping ground
        boxes.append(SolidBox(c: V3(x, g + (h - sunk) / 2, z), half: V3(sx / 2, (h + sunk) / 2, sz / 2), yaw: yaw, color: color, kind: kind))
        roof(V3(x, g + h, z), sx, sz, rise: rise, yaw: yaw, rc, gable: surf(color, kind), hip: hip)
        let long = sx >= sz
        guardBox(V3(x, g + h + rise * 0.3, z), V3(long ? sx : sx * 0.55, rise * 0.6, long ? sz * 0.55 : sz), yaw: yaw)
    }

    /// A hanging cable or wire between two points.
    func cable(_ a: V3, _ b: V3, sag: Float, r: Float = 0.05, _ color: V4, solid: Bool = true, parts: Int = 6) {
        func p(_ t: Float) -> V3 { a + (b - a) * t - V3(0, sag * 4 * t * (1 - t), 0) }
        for k in 0..<parts {
            let p0 = p(Float(k) / Float(parts)), p1 = p(Float(k + 1) / Float(parts))
            decor.cylinder(from: p0, to: p1, r0: r, r1: r, seg: 4, color: color)
            if solid { beam(p0, p1, w: 0.3, h: 0.3, color, show: false) }
        }
    }

    /// Something flat on level ground: paving, an apron, a painted line.
    func slab(_ x: Float, _ z: Float, _ sx: Float, _ sz: Float, yaw: Float = 0, _ color: V4, lift: Float = 0.04, base: Float? = nil) {
        decor.box(center: V3(x, (base ?? gnd(x, z)) + lift, z), size: V3(sx, 0.05, sz), color: color, rot: yq(yaw))
    }

    /// A track or road laid over the ground, following it.
    func road(_ pts: [SIMD2<Float>], width: Float, _ color: V4) {
        for i in 0..<(pts.count - 1) {
            let a = pts[i], d = pts[i + 1] - a, len = simd_length(d)
            guard len > 1 else { continue }
            let side = SIMD2(-d.y, d.x) / len * (width / 2), n = max(Int(len / 5), 1)
            func P(_ p: SIMD2<Float>) -> V3 { V3(p.x, height(p.x, p.y) + 0.14, p.y) }
            for k in 0..<n {
                let p0 = a + d * (Float(k) / Float(n)), p1 = a + d * (Float(k + 1) / Float(n))
                decor.quad(P(p0 - side), P(p1 - side), P(p1 + side), P(p0 + side), color)
            }
        }
    }

    /// A street lamp. Its head is lit, and glows after sunset.
    func lamp(_ x: Float, _ z: Float, h: Float = 9, toward: V3 = V3(0, 0, -1), reach: Float = 1.8) {
        let p = V3(x, gnd(x, z), z), top = p + V3(0, h, 0), grey = V4(0.3, 0.32, 0.34, 0.3)
        decor.cylinder(from: p, to: top, r0: 0.11, r1: 0.07, seg: 6, color: grey)
        decor.cylinder(from: top, to: top + toward * reach, r0: 0.06, r1: 0.05, seg: 5, color: grey)
        decor.box(center: top + toward * reach - V3(0, 0.1, 0), size: V3(0.55, 0.14, 0.55), color: V4(1, 0.93, 0.78, 8))
        column(x, z, r: 0.2, h: h, grey, hidden: true)
    }

    /// A floodlight mast.
    func floodlight(_ x: Float, _ z: Float, h: Float = 32, facing: Float = 0) {
        column(x, z, r: 0.45, h: h, sc(0.6, 0.62, 0.64, 0.4))
        boxes.append(SolidBox(c: V3(x, gnd(x, z) + h + 1.4, z), half: V3(3, 1.4, 0.4), yaw: facing, color: V4(1, 0.97, 0.88, 0.5), kind: 8))
    }

    /// A bank of seats: seven steps, a back wall, a roof.
    func stand(_ x: Float, _ z: Float, len: Float, yaw: Float, seats: V4) {
        let q = yq(yaw), g = gnd(x, z), base = V3(x, g, z)
        for k in 0..<7 {
            let c = base + q.act(V3(0, 0, -Float(k) * 1.6 - 0.8)), h = Float(k + 1) * 1.1
            boxes.append(SolidBox(c: c + V3(0, h / 2, 0), half: V3(len / 2, h / 2, 0.8), yaw: yaw, color: k % 2 == 0 ? seats : V4(seats.x * 0.8, seats.y * 0.8, seats.z * 0.8, seats.w)))
        }
        boxes.append(SolidBox(c: base + q.act(V3(0, 6.5, -11.6)), half: V3(len / 2, 6.5, 0.4), yaw: yaw, color: sc(0.62, 0.62, 0.6), kind: 6))
        boxes.append(SolidBox(c: base + q.act(V3(0, 13.3, -5.5)), half: V3(len / 2 + 1, 0.3, 7), yaw: yaw, color: sc(0.86, 0.87, 0.88, 0.3), kind: 5))
        for s: Float in [-1, 1] { boxes.append(SolidBox(c: base + q.act(V3(s * (len / 2 - 0.3), 6.5, -5.8)), half: V3(0.3, 6.5, 5.8), yaw: yaw, color: sc(0.62, 0.62, 0.6), kind: 6)) }
    }

    /// A wind turbine: an 80 m tower, three 40 m blades. `facing` is the compass direction the rotor looks in.
    func turbine(_ x: Float, _ z: Float, facing: Float, phase: Float) {
        let g = gnd(x, z), hubH: Float = 80, white = sc(0.93, 0.93, 0.92, 0.35)
        decor.cylinder(from: V3(x, g - 1, z), to: V3(x, g + hubH, z), r0: 2.4, r1: 1.4, seg: 18, color: white)
        column(x, z, r: 2.3, h: hubH, white, hidden: true)
        let n = V3(sin(facing * deg), 0, -cos(facing * deg)), side = V3(-n.z, 0, n.x)
        let top = V3(x, g + hubH + 1.6, z)
        beam(top - n * 5, top + n * 5.5, w: 3.6, h: 3.6, white)
        let hub = top + n * 7
        decor.ellipsoid(center: hub, radii: V3(2, 2, 2), color: white, seg: 10, rings: 6)
        for k in 0..<3 {
            let a = phase + Float(k) * 2.0944, d = V3(0, cos(a), 0) + side * sin(a)
            beam(hub + d * 1.5, hub + d * 22, w: 0.7, h: 3.2, white)
            beam(hub + d * 22, hub + d * 40, w: 0.45, h: 1.7, white)
        }
    }

    /// A lattice pylon carrying a power line that runs along `along`. Returns where its six wires hang.
    @discardableResult func pylon(_ x: Float, _ z: Float, along: V3, h: Float = 36) -> [V3] {
        let base = V3(x, gnd(x, z), z), steel = sc(0.6, 0.62, 0.64, 0.4), side = V3(-along.z, 0, along.x)
        let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        func leg(_ i: Int, _ t: Float) -> V3 {                      // corner i at height fraction t of the tapering part
            let w = 3.2 - 2.4 * t
            return base + V3(0, h * 0.64 * t, 0) + side * (corners[i].0 * w) + along * (corners[i].1 * w)
        }
        for i in 0..<4 {
            decor.cylinder(from: leg(i, 0), to: leg(i, 1), r0: 0.16, r1: 0.11, seg: 4, color: steel)
            decor.cylinder(from: leg(i, 1), to: base + V3(0, h, 0), r0: 0.11, r1: 0.07, seg: 4, color: steel)
            for k in 0..<5 {
                let t0 = Float(k) / 5, t1 = Float(k + 1) / 5, j = (i + 1) % 4
                decor.cylinder(from: k % 2 == 0 ? leg(i, t0) : leg(j, t0), to: k % 2 == 0 ? leg(j, t1) : leg(i, t1), r0: 0.06, r1: 0.06, seg: 3, color: steel)
            }
        }
        guardBox(base + V3(0, h / 2, 0), V3(3.4, h, 3.4))
        var hang: [V3] = []
        for (f, half) in [(Float(0.68), Float(7)), (0.82, 8.5), (0.95, 6)] {
            let c = base + V3(0, h * f, 0)
            beam(c - side * half, c + side * half, w: 0.45, h: 0.45, steel)
            hang += [c - side * half - V3(0, 1.3, 0), c + side * half - V3(0, 1.3, 0)]
        }
        return hang
    }

    /// The wires between two pylons.
    func wires(_ a: [V3], _ b: [V3], sag: Float = 5) {
        for i in 0..<min(a.count, b.count) { cable(a[i], b[i], sag: sag, r: 0.04, V4(0.12, 0.12, 0.13, 0.2), parts: 8) }
    }

    /// An airliner parked with its nose toward -z before `yaw` turns it.
    func airliner(_ x: Float, _ z: Float, yaw: Float, tail: V4, scale k: Float = 1) {
        var m = MeshBuilder()
        let white = V4(0.93, 0.93, 0.94, 0.5), grey = V4(0.6, 0.62, 0.65, 0.5), up = V3(0, 1, 0)
        m.body([(-15, 0.2, 0.2, 3.2), (-13.5, 1.1, 1.1, 3.4), (-11, 1.7, 1.75, 3.6), (8, 1.7, 1.75, 3.6), (13, 0.9, 1.0, 4.2), (15.5, 0.25, 0.3, 4.6)].map { (z: Float($0.0), w: Float($0.1), h: Float($0.2), y: Float($0.3)) }, seg: 14, color: white)
        for s: Float in [-1, 1] {
            m.wing(root: V3(s * 1.5, 2.9, -3), tip: V3(s * 15, 3.6, 2.5), rootChord: 5.5, tipChord: 1.8, thick: 0.12, up: up, top: white, bottom: grey)
            m.wing(root: V3(s * 0.8, 4.6, 11.3), tip: V3(s * 5.6, 4.9, 13.4), rootChord: 3, tipChord: 1.3, thick: 0.1, up: up, top: white, bottom: grey)
            m.cylinder(from: V3(s * 5.2, 2.0, -3.8), to: V3(s * 5.2, 2.0, 0.6), r0: 0.95, r1: 0.8, seg: 12, color: grey)
            m.box(center: V3(s * 1.74, 4.0, -1.5), size: V3(0.04, 0.34, 19), color: V4(0.05, 0.07, 0.1, 0.9))
            m.cylinder(from: V3(s * 2.6, 0.5, 0.6), to: V3(s * 2.6, 2.6, 0.6), r0: 0.5, r1: 0.14, seg: 8, color: V4(0.08, 0.08, 0.08, 0.1))
        }
        m.wing(root: V3(0, 5.2, 9.6), tip: V3(0, 10.6, 13.6), rootChord: 4.6, tipChord: 1.8, thick: 0.1, up: V3(1, 0, 0), top: tail, bottom: tail)
        m.cylinder(from: V3(0, 0.45, -11), to: V3(0, 2.2, -11), r0: 0.42, r1: 0.12, seg: 8, color: V4(0.08, 0.08, 0.08, 0.1))
        let p = V3(x, gnd(x, z), z), q = yq(yaw)
        decor.append(m, M4.translation(p) * M4.rotation(yaw, V3(0, 1, 0)) * M4(diagonal: V4(k, k, k, 1)))
        guardBox(p + V3(0, 3.6 * k, 0), V3(3.6, 4, 31) * k, yaw: yaw)
        guardBox(p + q.act(V3(0, 3.3, 0.5) * k), V3(30, 1.4, 7) * k, yaw: yaw)
        guardBox(p + q.act(V3(0, 8, 12) * k), V3(1, 6, 5) * k, yaw: yaw)
    }

    /// A boat lying to her anchor: a yacht with her sails up, or a motor boat with a cabin. Only where there is water.
    func boat(_ x: Float, _ z: Float, yaw: Float, len L: Float, sail: Bool, _ color: V4) {
        guard let wl = site.waterLevel, height(x, z) < wl - 0.6 else { return }
        var m = MeshBuilder()
        let B = L * 0.16
        func ring(_ zz: Float, _ w: Float, _ keel: Float) -> [V3] { [V3(-w, 0.7, zz), V3(w, 0.7, zz), V3(w * 0.55, -keel, zz), V3(-w * 0.55, -keel, zz)] }
        m.loft([ring(-L / 2, 0.06, 0.1), ring(-L * 0.25, B * 0.8, 0.5), ring(L * 0.2, B, 0.5), ring(L / 2, B * 0.75, 0.3)], color: color)
        m.box(center: V3(0, 0.72, L * 0.06), size: V3(B * 1.6, 0.06, L * 0.78), color: V4(0.62, 0.5, 0.36, 0.1))
        if sail {
            let cloth = V4(0.95, 0.94, 0.9, 0)
            m.cylinder(from: V3(0, 0.7, -L * 0.1), to: V3(0, 0.7 + L * 1.2, -L * 0.1), r0: 0.07, r1: 0.04, seg: 6, color: V4(0.8, 0.8, 0.82, 0.5))
            m.tri(V3(0, 1.5, -L * 0.08), V3(0, L * 1.15, -L * 0.09), V3(0, 1.5, L * 0.42), cloth)
            m.tri(V3(0, 1.1, -L * 0.48), V3(0, L * 0.95, -L * 0.12), V3(0.25, 1.1, -L * 0.14), cloth)
        } else {
            m.box(center: V3(0, 1.4, L * 0.1), size: V3(B * 1.2, 1.4, L * 0.3), color: V4(0.92, 0.92, 0.9, 0.3))
            m.box(center: V3(0, 1.65, L * 0.1 - L * 0.151), size: V3(B * 1.05, 0.5, 0.04), color: V4(0.06, 0.09, 0.12, 0.9))
        }
        let p = V3(x, wl, z)
        decor.append(m, M4.translation(p) * M4.rotation(yaw, V3(0, 1, 0)))
        guardBox(p + V3(0, sail ? 0.4 : 1.0, 0), V3(B * 2, sail ? 1.6 : 2.8, L), yaw: yaw)
        if sail { let o = p + yq(yaw).act(V3(0, 0, -L * 0.1)); column(o.x, o.z, r: 0.35, h: L * 1.2, .zero, base: wl + 0.7, hidden: true) }
    }

    /// A needle or stack of rock.
    func rockSpire(_ x: Float, _ z: Float, r: Float, h: Float, _ color: V4, base: Float? = nil) {
        let g = base ?? gnd(x, z), seed = Int32(truncatingIfNeeded: Int(x * 3 + z * 7)), n = 7, seg = 9
        var rings: [[V3]] = []
        for i in 0...n {
            // craggy: every level has its own outline, and the whole thing leans a little this way and that
            let t = Float(i) / Float(n), rr = r * (1 - 0.4 * t) * (0.72 + 0.56 * vnoise(t * 4.3, 1.3, seed)) * (i == n ? 0.6 : 1)
            let lean = V3(vnoise(t * 1.7 + 3, 0.5, seed) - 0.5, 0, vnoise(t * 1.7 + 9, 2.5, seed) - 0.5) * (r * 0.5)
            rings.append((0..<seg).map { j in
                let a = Float(j) / Float(seg) * 2 * .pi, k = 0.62 + 0.76 * vnoise(cos(a) * 2.3 + 5, sin(a) * 2.3 + t * 3.5 + 5, seed)
                return V3(x + cos(a) * rr * k, g - 2 + (h + 2) * t, z + sin(a) * rr * k) + lean
            })
        }
        decor.loft(rings, color: surf(color, 9))
        for i in 0..<3 {
            let t = Float(i) / 3
            boxes.append(SolidBox(c: V3(x, g + h * (t + 1.0 / 6), z), half: V3(r * (0.95 - 0.5 * t * t), h / 6, r), color: .zero, round: true, hidden: true))
        }
    }

    /// A heap of gravel, sand or coal.
    func pile(_ x: Float, _ z: Float, r: Float, h: Float, _ color: V4) {
        let g = gnd(x, z)
        var rings: [[V3]] = []
        for (t, f) in [(Float(0), Float(1)), (0.5, 0.52), (0.85, 0.2), (1, 0.03)] {
            rings.append((0..<20).map { j in let a = Float(j) / 20 * 2 * .pi; return V3(x + cos(a) * r * f, g - 0.5 + (h + 0.5) * t, z + sin(a) * r * f) })
        }
        decor.loft(rings, color: surf(color, 9))
        for (t, f) in [(Float(0), Float(0.85)), (0.33, 0.55), (0.66, 0.25)] {
            boxes.append(SolidBox(c: V3(x, g + h * (t + 1.0 / 6), z), half: V3(r * f, h / 6, r * f), color: .zero, round: true, hidden: true))
        }
    }

    /// A round storage tank with a shallow cone for a roof.
    func tank(_ x: Float, _ z: Float, r: Float, h: Float, _ color: V4, lift: Float = 0) {
        column(x, z, r: r, h: h, lift: lift, color, kind: 6)
        let top = V3(x, gnd(x, z) + lift + h, z)
        decor.cylinder(from: top, to: top + V3(0, r * 0.22, 0), r0: r, r1: 0.3, seg: 24, color: V4(color.x * 0.85, color.y * 0.85, color.z * 0.85, 0.2))
    }

    /// A lorry; `dump` gives it a tipper body.
    func truck(_ x: Float, _ z: Float, yaw: Float, _ color: V4, dump: Bool = false, k: Float = 1) {
        var m = MeshBuilder()
        let tyre = V4(0.05, 0.05, 0.05, 0.05)
        m.box(center: V3(0, 0.95, 0.4), size: V3(2.2, 0.5, 8), color: V4(0.12, 0.12, 0.13, 0.1))
        m.box(center: V3(0, 2.1, -2.9), size: V3(2.4, 2.2, 2.0), color: color)
        m.box(center: V3(0, 2.5, -3.92), size: V3(2.1, 0.9, 0.05), color: V4(0.06, 0.09, 0.12, 0.9))
        if dump {
            m.loft([[V3(-1.4, 1.3, -1.7), V3(1.4, 1.3, -1.7), V3(1.4, 3.1, -2.1), V3(-1.4, 3.1, -2.1)], [V3(-1.4, 1.3, 4.3), V3(1.4, 1.3, 4.3), V3(1.4, 2.9, 4.6), V3(-1.4, 2.9, 4.6)]], color: color)
        } else {
            m.box(center: V3(0, 2.6, 1.5), size: V3(2.5, 2.8, 5.8), color: V4(0.85, 0.85, 0.83, 0.2))
        }
        for s: Float in [-1, 1] { for zz: Float in [-2.9, 1.6, 3.2] { m.cylinder(from: V3(s * 0.85, 0.6, zz), to: V3(s * 1.25, 0.6, zz), r0: 0.6, r1: 0.6, seg: 10, color: tyre) } }
        let p = V3(x, gnd(x, z), z)
        decor.append(m, M4.translation(p) * M4.rotation(yaw, V3(0, 1, 0)) * M4(diagonal: V4(k, k, k, 1)))
        guardBox(p + V3(0, 1.7 * k, 0), V3(2.8, 3.4, 8.6) * k, yaw: yaw)
    }

    /// A parked car.
    func motorcar(_ x: Float, _ z: Float, yaw: Float, _ color: V4) {
        var m = MeshBuilder()
        m.box(center: V3(0, 0.62, 0), size: V3(1.75, 0.62, 4.2), color: color)
        m.box(center: V3(0, 1.18, 0.15), size: V3(1.55, 0.52, 2.2), color: V4(0.06, 0.08, 0.1, 0.9))
        m.box(center: V3(0, 1.45, 0.15), size: V3(1.5, 0.05, 2.0), color: color)
        for s: Float in [-1, 1] { for zz: Float in [-1.35, 1.35] { m.cylinder(from: V3(s * 0.7, 0.32, zz), to: V3(s * 0.92, 0.32, zz), r0: 0.32, r1: 0.32, seg: 10, color: V4(0.05, 0.05, 0.05, 0.05)) } }
        let p = V3(x, gnd(x, z), z)
        decor.append(m, M4.translation(p) * M4.rotation(yaw, V3(0, 1, 0)))
        guardBox(p + V3(0, 0.75, 0), V3(1.9, 1.5, 4.3), yaw: yaw)
    }

    /// A conveyor belt in its casing, on trestles wherever it runs high.
    func conveyor(_ a: V3, _ b: V3, _ color: V4, every: Float = 45) {
        beam(a, b, w: 2.6, h: 1.9, color, kind: 5)
        let n = max(Int(length(b - a) / every), 1), d = normalize(V3(b.x - a.x, 0, b.z - a.z)), side = V3(-d.z, 0, d.x)
        for k in 1...n {
            let p = a + (b - a) * (Float(k) / Float(n + 1))
            for s: Float in [-1, 1] {
                let q = p + side * (s * 1.5), g = gnd(q.x, q.z)
                if p.y - 1 - g > 2.5 { column(q.x, q.z, r: 0.22, h: p.y - 0.9 - g, sc(0.4, 0.42, 0.45, 0.3)) }
            }
        }
    }

    /// An aircraft hangar with an arched roof; its doors face the way `yaw` turns -z.
    func hangar(_ x: Float, _ z: Float, w: Float, d: Float, h: Float, yaw: Float, _ color: V4) {
        let q = yq(yaw), c = V3(x, gnd(x, z), z)
        var rings: [[V3]] = []
        for zz in [-d / 2, d / 2] {
            rings.append(((0...10).map { k -> V3 in
                let a = Float(k) / 10 * .pi
                return V3(-cos(a) * w / 2, h * 0.45 + sin(a) * h * 0.55, zz)
            } + [V3(w / 2, 0, zz), V3(-w / 2, 0, zz)]).map { c + q.act($0) })
        }
        decor.loft(rings, color: surf(color, 5))
        decor.box(center: c + q.act(V3(0, h * 0.32, -d / 2 - 0.06)), size: V3(w * 0.76, h * 0.64, 0.2), color: V4(0.33, 0.35, 0.38, 0.4), rot: q)
        guardBox(c + V3(0, h * 0.45, 0), V3(w, h * 0.9, d), yaw: yaw)
    }

    /// A cooling tower: a waisted concrete shell, open at the top.
    func coolingTower(_ x: Float, _ z: Float, h: Float = 105, r: Float = 40) {
        let g = gnd(x, z), prof: [(Float, Float)] = [(0, 1), (0.12, 0.88), (0.3, 0.74), (0.5, 0.63), (0.72, 0.565), (0.88, 0.59), (1, 0.63)]
        let rings = prof.map { p in (0..<28).map { j -> V3 in let a = Float(j) / 28 * 2 * .pi; return V3(x + cos(a) * r * p.1, g + h * p.0, z + sin(a) * r * p.1) } }
        decor.loft(rings, color: surf(sc(0.72, 0.71, 0.68), 6), caps: false)
        for i in 0..<(prof.count - 1) {
            let y0 = g + h * prof[i].0, y1 = g + h * prof[i + 1].0
            boxes.append(SolidBox(c: V3(x, (y0 + y1) / 2, z), half: V3(r * max(prof[i].1, prof[i + 1].1), (y1 - y0) / 2, r), color: .zero, round: true, hidden: true))
        }
    }

    /// A chimney stack, banded red and white at the top.
    func chimney(_ x: Float, _ z: Float, h: Float = 150) {
        let n = 8, seg = h / Float(n)
        for k in 0..<n {
            let col = k < n - 3 ? sc(0.68, 0.67, 0.64) : ((n - k) % 2 == 1 ? sc(0.8, 0.14, 0.1, 0.2) : sc(0.94, 0.94, 0.92, 0.2))
            column(x, z, r: 5.6 - 0.28 * Float(k), h: seg, lift: Float(k) * seg, col, kind: k < n - 3 ? 6 : 0)
        }
    }

    /// A market stall, a tent: a ridge of cloth on four poles, or pegged to the ground.
    func canopy(_ x: Float, _ z: Float, _ sx: Float, _ sz: Float, yaw: Float, _ cloth: V4, poles: Float = 2.2) {
        let g = gnd(x, z), q = yq(yaw)
        if poles > 0 { for s: Float in [-1, 1] { for t: Float in [-1, 1] {
            let p = V3(x, g, z) + q.act(V3(s * sx / 2, 0, t * sz / 2))
            decor.cylinder(from: p, to: p + V3(0, poles, 0), r0: 0.05, r1: 0.05, seg: 5, color: V4(0.4, 0.3, 0.2, 0.05))
        } } }
        roof(V3(x, g + poles, z), sx, sz, rise: poles > 0 ? 0.9 : min(sx, sz) * 0.55, yaw: yaw, cloth, gable: cloth, over: 0.2, tiled: false)
        guardBox(V3(x, g + (poles + 0.9) / 2, z), V3(sx, poles + 0.9, sz), yaw: yaw)
    }

    /// A sheep, a cow: a body, a head, four legs. Only to look at.
    func beast(_ x: Float, _ z: Float, yaw: Float, size k: Float, _ color: V4) {
        var m = MeshBuilder()
        m.ellipsoid(center: V3(0, 0.62, 0), radii: V3(0.3, 0.3, 0.55), color: color, seg: 8, rings: 5)
        m.ellipsoid(center: V3(0, 0.78, -0.62), radii: V3(0.13, 0.15, 0.2), color: V4(0.12, 0.11, 0.1, 0), seg: 6, rings: 4)
        for s: Float in [-1, 1] { for zz: Float in [-0.32, 0.32] { m.cylinder(from: V3(s * 0.16, 0, zz), to: V3(s * 0.16, 0.45, zz), r0: 0.045, r1: 0.05, seg: 5, color: V4(0.12, 0.11, 0.1, 0)) } }
        decor.append(m, M4.translation(V3(x, gnd(x, z), z)) * M4.rotation(yaw, V3(0, 1, 0)) * M4(diagonal: V4(k, k, k, 1)))
    }
}
