import simd
import Foundation

// What stands on each flying site beyond its gates and obstacles: the second series of sites complete, and the
// furnishing of the first. Called once from layoutStructures(), after the first series has built its own.

extension Terrain {
    func furnish() {
        var rng = LCG(UInt64(site.seed) + 1717)
        let concrete = sc(0.62, 0.62, 0.6), steel = sc(0.5, 0.52, 0.56, 0.4), dark = sc(0.2, 0.22, 0.25, 0.3), yellow = sc(0.95, 0.75, 0.1, 0.3)
        let red = sc(0.8, 0.15, 0.12, 0.3), white = sc(0.93, 0.93, 0.91, 0.2), wood = sc(0.42, 0.31, 0.21), tile = sc(0.58, 0.26, 0.17, 0.05)
        let slate = sc(0.25, 0.26, 0.3, 0.1), stone = sc(0.6, 0.57, 0.5), gravel = sc(0.52, 0.5, 0.45), tarmac = sc(0.2, 0.2, 0.22, 0.1)
        let hw = site.runwayWid / 2
        func P(_ x: Float, _ z: Float, _ up: Float = 0) -> V3 { V3(x, gnd(x, z) + up, z) }
        func tree(_ x: Float, _ z: Float, _ h: Float) { trees.append(Tree(p: V3(x, height(x, z), z), h: h)) }

        switch site.layout {
        case 1:     // stadium: stands, floodlights, boards, a chequered line under the start gate, a scoreboard
            for x: Float in [-150, -50, 50, 150] { stand(x, -222, len: 92, yaw: 0, seats: abs(x) > 100 ? sc(0.2, 0.35, 0.65) : sc(0.75, 0.2, 0.18)) }
            for (x, z) in [(Float(-225), Float(-205)), (225, -205), (-225, 48), (225, 48)] { floodlight(x, z, facing: x > 0 ? -0.7 : 0.7) }
            let ads = [sc(0.1, 0.3, 0.7, 0.3), white, sc(0.85, 0.6, 0.1, 0.3), sc(0.1, 0.5, 0.3, 0.3), red]
            for i in 0..<28 { add(-189 + Float(i) * 14, -208, V3(13.4, 1.1, 0.25), ads[i % 5]) }
            for k in 0..<10 { for j in 0..<2 { slab(20.5 + Float(k), -50.5 + Float(j), 1, 1, (k + j) % 2 == 0 ? sc(0.05, 0.05, 0.05) : white) } }
            for s: Float in [-1, 1] { add(-178 + s * 5, -118, V3(0.8, 8, 0.8), steel) }
            add(-178, -118, V3(15, 6, 0.8), lift: 8, dark)
            for k in 0..<3 { slab(-178 - 4.5 + Float(k) * 4.5, -117.5, 3.4, 0.05, V4(1, 0.8, 0.3, 8), lift: 9.5 + Float(k) * 1.6) }
        case 2:     // forest: a high seat at the edge of the ride, stacks of logs
            let hx: Float = -46, hz: Float = -96
            for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(hx + s * 1.2, hz + t * 1.2, r: 0.12, h: 6, wood) } }
            add(hx, hz, V3(3.2, 2.2, 3.2), lift: 6, wood)
            roof(P(hx, hz, 8.2), 3.2, 3.2, rise: 1.2, yaw: 0, slate, gable: wood, hip: true)
            for (x, z, yaw) in [(Float(-70), Float(-28), Float(0.3)), (72, 28, 1.2), (150, -20, 0.1)] {
                let q = simd_quatf(angle: yaw, axis: V3(0, 1, 0)), p = P(x, z)
                for (i, row) in [3, 2, 1].enumerated() { for k in 0..<row {
                    let o = V3(0, 0.3 + Float(i) * 0.52, (Float(k) - Float(row - 1) / 2) * 0.62)
                    decor.cylinder(from: p + q.act(o - V3(2.2, 0, 0)), to: p + q.act(o + V3(2.2, 0, 0)), r0: 0.3, r1: 0.28, seg: 8, color: V4(0.44, 0.32, 0.2, 0.02))
                } }
                guardBox(p + V3(0, 0.8, 0), V3(4.4, 1.6, 2), yaw: yaw)
            }
        case 3:     // canyon: a footbridge from rim to rim, needles of rock on the far rim
            let zc: Float = -170 + 80 * sin(40.0 / 210)
            let a = P(40, zc + 88, 1), b = P(40, zc - 88, 1)
            beam(a, b, w: 2.4, h: 0.4, wood)
            for s: Float in [-1, 1] {
                column(40 + s * 1.3, a.z, r: 0.2, h: 6, wood); column(40 + s * 1.3, b.z, r: 0.2, h: 6, wood)
                cable(a + V3(s * 1.3, 5, 0), b + V3(s * 1.3, 5, 0), sag: 4.2, steel, solid: false, parts: 10)
            }
            let rock = sc(0.7, 0.47, 0.3)
            for (x, z, r, h) in [(Float(-120), Float(-300), Float(9), Float(40)), (-96, -316, 6, 26), (260, -310, 10, 46), (520, -250, 8, 34)] { rockSpire(x, z, r: r, h: h, rock) }
        case 5:     // container yard: sheds, rails, lorries, lights
            add(-150, 112, V3(120, 14, 44), sc(0.55, 0.6, 0.64, 0.2), kind: 5); roof(P(-150, 112, 14), 120, 44, rise: 4, yaw: 0, sc(0.42, 0.44, 0.47, 0.2), gable: surf(sc(0.55, 0.6, 0.64, 0.2), 5), over: 0.3)
            add(170, 104, V3(76, 10, 30), sc(0.66, 0.5, 0.3, 0.2), kind: 5); roof(P(170, 104, 10), 76, 30, rise: 3, yaw: 0, sc(0.42, 0.44, 0.47, 0.2), gable: surf(sc(0.66, 0.5, 0.3, 0.2), 5), over: 0.3)
            for dz: Float in [-0.75, 0.75] { slab(0, 46 + dz, 560, 0.14, steel, lift: 0.1) }
            for k in 0..<140 { slab(-278 + Float(k) * 4, 46, 0.25, 2.4, sc(0.3, 0.24, 0.18), lift: 0.03) }
            for (x, c) in [(Float(-60), red), (-20, sc(0.15, 0.35, 0.6, 0.3)), (70, white)] { truck(x, 62, yaw: 1.57 + rng.range(-0.1, 0.1), c) }
            for row in 0..<6 { slab(0, -54 - Float(row) * 24, 520, 0.3, yellow) }
            for x: Float in [-240, 240] { boxes.append(SolidBox(c: P(x, -20, 31.4), half: V3(2.6, 0.5, 1), color: V4(1, 0.96, 0.85, 0.5), kind: 8)) }
        case 6:     // downtown: road markings, street lamps, parked cars, a fountain and trees on the square
            var z: Float = -30
            while z > -420 { slab(0, z, 0.35, 5, white); z -= 12 }
            for cz: Float in [-84, -168, -252, -336] { var x: Float = -330; while x <= 330 { if abs(x) > 14 { slab(x, cz, 5, 0.35, white) }; x += 12 } }
            for k in 0..<10 { slab(-9 + Float(k) * 2, -16, 1, 5, white); slab(-9 + Float(k) * 2, -68, 1, 5, white) }
            z = -30
            while z > -420 { lamp(16.5, z, h: 10, toward: V3(-1, 0, 0), reach: 3.2); lamp(-16.5, z, h: 10, toward: V3(1, 0, 0), reach: 3.2); z -= 42 }
            let paints = [sc(0.6, 0.06, 0.06, 0.8), sc(0.82, 0.83, 0.85, 0.8), sc(0.06, 0.16, 0.38, 0.8), sc(0.1, 0.1, 0.11, 0.8), sc(0.5, 0.52, 0.5, 0.8), sc(0.85, 0.7, 0.1, 0.8)]
            z = -136
            while z > -420 { for s: Float in [-1, 1] where rng.next() < 0.5 && abs(z.truncatingRemainder(dividingBy: 84)) > 16 { motorcar(s * 10.7, z, yaw: s > 0 ? 0 : .pi, paints[Int(rng.next() * 5.99)]) }; z -= 7 }
            column(-34, 48, r: 5, h: 0.8, stone, kind: 7); column(-34, 48, r: 0.7, h: 3.6, stone); column(-34, 48, r: 2, h: 0.4, lift: 2.2, stone)
            for (x, zz) in [(Float(-70), Float(36)), (-70, 60), (60, 36), (60, 60), (95, 48), (-105, 48)] { tree(x, zz, 9) }
            for x: Float in [-60, -20, 40, 80] { lamp(x, 72, h: 6, toward: V3(0, 0, -1), reach: 0.8) }
        case 7:     // harbour: a lighthouse on the mole, stays on the bridge, boats, bollards, quay lamps
            let wl = site.waterLevel ?? 0
            column(345, -300, r: 8, h: 4, concrete, kind: 7, base: wl - 1)
            for k in 0..<5 { column(345, -300, r: 3.4 - 0.3 * Float(k), h: 5, lift: Float(k) * 5, k % 2 == 0 ? white : red, base: wl + 3) }
            column(345, -300, r: 3.2, h: 0.5, dark, base: wl + 28); column(345, -300, r: 1.8, h: 3, V4(1, 0.95, 0.7, 0.5), kind: 8, base: wl + 28.5)
            decor.cylinder(from: V3(345, wl + 31.5, -300), to: V3(345, wl + 34, -300), r0: 2.2, r1: 0.1, seg: 12, color: red)
            for tx: Float in [-150, 150] { for s: Float in [-1, 1] { for d: Float in [35, 70, 105, 140] { for e: Float in [-1, 1] {
                cable(V3(tx, wl + 77, -420 + s * 9), V3(tx + e * d, wl + 29.5, -420 + s * 8), sag: 0, r: 0.12, sc(0.75, 0.75, 0.78, 0.4), solid: false, parts: 1)
            } } } }
            for (x, z, yaw, len, sail) in [(Float(60), Float(-300), Float(0.5), Float(9), true), (-30, -335, 2.2, 8, true), (-330, -330, 1.0, 10, true), (120, -365, 1.3, 12, false), (20, -390, 0.2, 7, true)] {
                boat(x, z, yaw: yaw, len: len, sail: sail, sail ? white : sc(0.16, 0.3, 0.5, 0.3))
            }
            var x: Float = -360
            while x <= 360 { column(x, -229, r: 0.3, h: 0.7, dark); if abs(x - 8) > 30 && Int(x) % 80 == 0 { lamp(x, -196, h: 9, toward: V3(0, 0, -1)) }; x += 20 }
        case 8:     // lakeside loop: eight gates round the lake, every other one standing in the water
            for k in 0..<8 {
                let a = Float(k) * .pi / 4, over = k % 2 == 1, f: Float = over ? 0.7 : 1.14
                addGate(185 * f * sin(a), -270 + 120 * f * cos(a), heading: atan2(185 * cos(a), 120 * sin(a)) / deg, w: 10, h: 7, lift: over ? 3 : 1)
                if over { for s: Float in [-1, 1] { column(185 * (f + s * 0.09) * sin(a), -270 + 120 * (f + s * 0.09) * cos(a), r: 0.45, h: 1.3, red, base: (site.waterLevel ?? 0) - 0.3) } }
            }
            let wl = site.waterLevel ?? 0
            for k in 0..<13 {
                add(-72, -150 - Float(k) * 4, V3(3, 0.3, 4), lift: 0.9, wood, base: wl)
                if k % 3 == 0 { for s: Float in [-1, 1] { column(-72 + s * 1.4, -150 - Float(k) * 4, r: 0.14, h: 2.6, wood, base: wl - 1.2) } }
            }
            house(-150, -176, 11, 8, wall: 3.4, rise: 2.6, yaw: 0.25, sc(0.5, 0.2, 0.16), roof: slate)
            for (x, z, yaw, len, sail) in [(Float(12), Float(-276), Float(0.6), Float(8), true), (-44, -250, 2.1, 7, true), (52, -302, 1.0, 6, false), (-64, -206, 0.1, 4.5, false)] {
                boat(x, z, yaw: yaw, len: len, sail: sail, sail ? white : sc(0.7, 0.2, 0.15, 0.3))
            }
            var ring: [SIMD2<Float>] = []
            for k in 0...48 { let a = Float(k) / 48 * 2 * .pi; ring.append(SIMD2(185 * 1.3 * sin(a), -270 + 120 * 1.36 * cos(a))) }
            road(ring, width: 2, sc(0.52, 0.47, 0.36))
            for (x, z) in [(Float(-30), Float(-126)), (40, -124), (120, -150)] { add(x, z, V3(1.8, 0.45, 0.5), wood); add(x, z + 0.3, V3(1.8, 0.5, 0.08), lift: 0.45, wood) }
        case 9:     // wind farm: seven turbines, a measuring mast on guys, a substation and its line of pylons
            let spots: [(Float, Float)] = [(-330, -190), (-110, -212), (110, -190), (330, -215), (-220, -430), (0, -452), (220, -430)]
            for (i, p) in spots.enumerated() { turbine(p.0, p.1, facing: 265 + rng.range(-6, 6), phase: 0.35 + Float(i) * 0.47) }
            road([SIMD2(-330, -178), SIMD2(-110, -200), SIMD2(110, -178), SIMD2(330, -203)], width: 4, gravel)
            road([SIMD2(-220, -418), SIMD2(0, -440), SIMD2(220, -418)], width: 4, gravel)
            road([SIMD2(110, -178), SIMD2(150, -60), SIMD2(150, 120)], width: 4, gravel)
            let mx: Float = -430, mz: Float = 70
            for k in 0..<6 { column(mx, mz, r: 0.35, h: 15, lift: Float(k) * 15, k % 2 == 0 ? red : white) }
            for a: Float in [0.5, 2.6, 4.7] { for lvl: Float in [45, 88] {
                cable(P(mx, mz, lvl), P(mx + cos(a) * 46, mz + sin(a) * 46, 0.3), sag: 0.6, r: 0.03, dark, parts: 3)
            } }
            let sx: Float = 150, sz: Float = 150
            slab(sx, sz, 44, 32, gravel)
            for k in 0..<3 { add(sx - 12 + Float(k) * 12, sz + 4, V3(5, 4.4, 7), sc(0.45, 0.5, 0.48, 0.2), kind: 5); column(sx - 12 + Float(k) * 12, sz + 4, r: 0.5, h: 2, lift: 4.4, sc(0.7, 0.5, 0.4, 0.4)) }
            house(sx - 4, sz - 10, 9, 5, wall: 3, rise: 1.4, concrete, roof: slate, kind: 6)
            for s: Float in [-1, 1] { add(sx, sz + s * 16, V3(44, 2, 0.12), sc(0.5, 0.52, 0.54, 0.4)); add(sx + s * 22, sz, V3(0.12, 2, 32), sc(0.5, 0.52, 0.54, 0.4)) }
            let along = normalize(V3(1, 0, 0.09))
            var prev = pylon(230, 157, along: along)
            for (x, z) in [(Float(460), Float(178)), (690, 199), (920, 220)] { let next = pylon(x, z, along: along); wires(prev, next); prev = next }
            for (i, p) in [(Float(-300), Float(-60)), (-260, -90), (-280, -110), (260, -70), (300, -90), (60, -330), (90, -350), (-60, -320)].enumerated() {
                beast(p.0, p.1, yaw: Float(i) * 1.3, size: 1, sc(0.9, 0.89, 0.84, 0))
            }
        case 10:    // old town
            let plaster = [sc(0.86, 0.8, 0.66), sc(0.8, 0.62, 0.48), sc(0.9, 0.87, 0.8), sc(0.72, 0.56, 0.4), sc(0.78, 0.72, 0.6), sc(0.84, 0.7, 0.62)]
            for rz: Float in [-52, -96, -140, -184, 84, 128] {
                var x: Float = -335
                while x < 335 {
                    let w = rng.range(11, 19)
                    defer { x += w + (rng.next() < 0.12 ? 7 : 0.3) }
                    let cx = x + w / 2
                    if abs(cx - 7) < 16 + w / 2 || abs(cx + 150) < 11 + w / 2 || abs(cx - 165) < 11 + w / 2 { continue }      // the main street and two cross streets
                    house(cx, rz + rng.range(-1, 1), w, rng.range(13, 17), wall: rng.range(6.5, 12.5), rise: rng.range(3.5, 6), plaster[Int(rng.next() * 5.99)], roof: rng.next() < 0.78 ? tile : slate)
                }
            }
            // the wall along the river, its gate on the main street, round towers
            var wx: Float = -340
            while wx <= 340 {
                if abs(wx - 7) > 14 {
                    add(wx, -214, V3(20, 9, 3), stone, kind: 7)
                    for k in 0..<4 { add(wx - 7.5 + Float(k) * 5, -215.2, V3(2.4, 1.2, 0.6), lift: 9, stone, kind: 7) }
                }
                wx += 20
            }
            for s: Float in [-1, 1] {
                add(7 + s * 11, -214, V3(8, 17, 8), stone, kind: 7)
                roof(P(7 + s * 11, -214, 17), 8, 8, rise: 6, yaw: 0, tile, gable: tile, hip: true)
                guardBox(P(7 + s * 11, -214, 19), V3(5, 4, 5))
            }
            add(7, -214, V3(14, 5, 6), lift: 10, stone, kind: 7)
            roof(P(7, -214, 15), 14, 6, rise: 3, yaw: 0, tile, gable: surf(stone, 7))
            for tx: Float in [-340, -170, 170, 340] {
                column(tx, -214, r: 5.5, h: 14, stone, kind: 7)
                decor.cylinder(from: P(tx, -214, 14), to: P(tx, -214, 21), r0: 6.2, r1: 0.1, seg: 16, color: tile)
                column(tx, -214, r: 3, h: 4, lift: 14, .zero, hidden: true)
            }
            // the bridge on the main street, and the aqueduct beyond the river
            let wl = site.waterLevel ?? 0
            add(7, -262, V3(10, 1.3, 70), lift: 0.3, stone, kind: 7, base: 0)
            for dz: Float in [-13, 13] { add(7, -262 + dz, V3(10, 4, 3.4), stone, kind: 7, base: wl - 2) }
            for s: Float in [-1, 1] { add(7 + s * 4.7, -262, V3(0.5, 1, 70), lift: 1.6, stone, kind: 7, base: 0) }
            var ax: Float = -330
            while ax <= 132 { add(ax, -330, V3(4.4, 21, 5.4), stone, kind: 7); ax += 22 }
            add(-99, -330, V3(470, 3.4, 5.4), lift: 21, stone, kind: 7)
            // church, town hall, fountain, market
            house(-105, 14, 14, 30, wall: 11, rise: 7, stone, roof: slate, kind: 7)
            add(-105, -9, V3(8.5, 34, 8.5), stone, kind: 7)
            decor.cylinder(from: P(-105, -9, 34), to: P(-105, -9, 53), r0: 6.2, r1: 0.1, seg: 4, color: slate)
            column(-105, -9, r: 2.6, h: 14, lift: 34, .zero, hidden: true)
            for s: Float in [-1, 1] { slab(-105, -9 + s * 4.3, 2.2, 2.2, V4(0.95, 0.93, 0.85, 8), lift: 27) }
            house(108, 14, 30, 20, wall: 15, rise: 7, plaster[2], roof: tile, hip: true)
            add(108, 2, V3(6, 26, 6), plaster[2], kind: 4); roof(P(108, 2, 26), 6, 6, rise: 5, yaw: 0, slate, gable: slate, hip: true)
            column(-36, -6, r: 3.4, h: 0.9, stone, kind: 7); column(-36, -6, r: 0.5, h: 3.6, stone)
            let cloths = [sc(0.8, 0.2, 0.15), sc(0.9, 0.85, 0.7), sc(0.2, 0.4, 0.65), sc(0.85, 0.6, 0.15), sc(0.25, 0.5, 0.3)]
            for (i, p) in [(Float(-62), Float(34)), (-52, 44), (-40, 32), (-28, 46), (-64, 52), (38, 34), (50, 46), (62, 32), (44, 56)].enumerated() {
                canopy(p.0, p.1, 3.4, 2.6, yaw: Float(i) * 0.4, cloths[i % 5])
            }
            for (x, z) in [(Float(-78), Float(-22)), (-20, 58), (24, 58), (78, -22), (78, 44)] { tree(x, z, 10) }
            for z: Float in [-60, -104, -148, -192] { lamp(26, z, h: 6, toward: V3(-1, 0, 0), reach: 1.2); lamp(-12, z, h: 6, toward: V3(1, 0, 0), reach: 1.2) }
            // a windmill in the fields across the river
            let mwx: Float = 170, mwz: Float = -360
            column(mwx, mwz, r: 4.2, h: 13, white, kind: 7)
            decor.cylinder(from: P(mwx, mwz, 13), to: P(mwx, mwz, 17.5), r0: 4.6, r1: 0.2, seg: 14, color: slate)
            let hub = P(mwx, mwz, 12.5) + V3(0, 0, 4.9)
            for k in 0..<4 { let a = 0.5 + Float(k) * .pi / 2; beam(hub, hub + V3(cos(a), sin(a), 0) * 12, w: 0.2, h: 2.2, sc(0.85, 0.8, 0.7)) }
        case 11:    // gravel works
            let ochre = sc(0.72, 0.6, 0.36), belt = sc(0.24, 0.26, 0.3, 0.2), sheet = sc(0.5, 0.56, 0.62, 0.2), mint = sc(0.56, 0.7, 0.62, 0.2), sand = sc(0.74, 0.68, 0.52)
            add(110, -150, V3(22, 46, 18), ochre, kind: 6); add(124, -160, V3(8, 54, 8), ochre, kind: 6); add(110, -127, V3(30, 20, 28), ochre, kind: 6)
            add(110, -150, V3(24, 1.2, 20), lift: 46, sc(0.4, 0.4, 0.42)); add(101, -141, V3(4, 3, 0.4), lift: 38, red)
            let g0 = gnd(110, -150)
            conveyor(P(-218, -170, 2.5), V3(99, g0 + 39, -152), belt)
            conveyor(V3(121, g0 + 30, -146), V3(250, g0 + 21, -108), belt); pile(253, -103, r: 27, h: 18, gravel)
            conveyor(V3(118, g0 + 26, -160), V3(228, g0 + 19, -238), belt); pile(231, -243, r: 25, h: 16, sand)
            pile(322, -170, r: 30, h: 19, sand); pile(-66, -266, r: 22, h: 13, gravel); pile(305, -62, r: 20, h: 12, sc(0.4, 0.39, 0.37))
            add(10, -232, V3(44, 16, 24), sheet, kind: 5); roof(P(10, -232, 16), 44, 24, rise: 4, yaw: 0, sc(0.4, 0.42, 0.46, 0.2), gable: surf(sheet, 5), over: 0.3)
            add(-95, -100, V3(64, 11, 20), mint, kind: 5); roof(P(-95, -100, 11), 64, 20, rise: 3, yaw: 0, sc(0.4, 0.42, 0.46, 0.2), gable: surf(mint, 5), over: 0.3)
            conveyor(V3(32, g0 + 14, -230), V3(100, g0 + 25, -158), belt)
            for hx: Float in [44, 57] {
                for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(hx + s * 2.5, -112 + t * 2.5, r: 0.2, h: 5, steel) } }
                add(hx, -112, V3(6.4, 5, 6.4), lift: 5, sc(0.3, 0.42, 0.6, 0.2), kind: 5)
            }
            // the tower crane
            add(190, -40, V3(2, 43, 2), red)
            let jib = P(190, -40, 44)
            beam(jib - V3(13, 0, 0), jib + V3(48, 0, 0), w: 1.2, h: 1.6, red)
            add(180, -40, V3(5, 2.6, 2.2), lift: 40.4, concrete); add(191.5, -41.8, V3(2, 2.4, 2), lift: 40.6, white)
            beam(jib + V3(0, 6, 0), jib + V3(30, 0.8, 0), w: 0.2, h: 0.2, red); beam(jib + V3(0, 6, 0), jib - V3(12, -0.8, 0), w: 0.2, h: 0.2, red); add(190, -40, V3(1, 6, 1), lift: 44, red)
            cable(jib + V3(34, -0.8, 0), jib + V3(34, -19, 0), sag: 0, r: 0.04, dark, parts: 1)
            tank(150, 72, r: 9, h: 4, concrete); tank(172, 96, r: 9, h: 4, concrete)
            for l in 0..<2 { add(-46, 48, V3(6.1, 2.6, 2.5), lift: Float(l) * 2.6, white, kind: 5) }
            truck(-24, -52, yaw: 0.4, yellow, dump: true, k: 1.3); truck(72, -62, yaw: -1.2, yellow, dump: true, k: 1.3); truck(-30, 60, yaw: 1.57, sc(0.2, 0.36, 0.6, 0.3))
            for (x, z) in [(Float(-60), Float(-30)), (70, -20), (170, -110), (-150, -150)] { lamp(x, z, h: 12, toward: V3(0, 0, -1), reach: 2) }
            // an excavator on the pit floor
            let e = P(-392, -168)
            decor.box(center: e + V3(0, 1.7, 0), size: V3(3.2, 2, 4.4), color: yellow); decor.box(center: e + V3(0, 0.5, 0), size: V3(3.4, 1, 5), color: dark)
            beam(e + V3(0, 2.4, -1.5), e + V3(0, 6.2, -6), w: 0.6, h: 0.7, yellow, solid: false); beam(e + V3(0, 6.2, -6), e + V3(0, 1.4, -8.6), w: 0.5, h: 0.6, yellow, solid: false)
            guardBox(e + V3(0, 3, -3), V3(3.4, 6.5, 12))
        case 12:    // power station
            for cx: Float in [-255, -128] { coolingTower(cx, -245) }
            add(150, -278, V3(70, 46, 60), sc(0.62, 0.62, 0.6), kind: 6); add(150, -216, V3(124, 30, 42), sc(0.5, 0.56, 0.62, 0.2), kind: 5)
            roof(P(150, -216, 30), 124, 42, rise: 4, yaw: 0, sc(0.4, 0.42, 0.46, 0.2), gable: surf(sc(0.5, 0.56, 0.62, 0.2), 5), over: 0.3)
            for cx: Float in [95, 205] { chimney(cx, -326) }
            let g0 = gnd(150, -278), coal = sc(0.09, 0.09, 0.1)
            conveyor(P(430, -150, 4), V3(187, g0 + 50, -262), dark, every: 60)
            pile(442, -134, r: 30, h: 14, coal); pile(476, -178, r: 26, h: 12, coal); pile(404, -188, r: 28, h: 13, coal)
            beam(V3(88, g0 + 9, -222), V3(-92, g0 + 9, -240), w: 3, h: 2, steel)
            for f: Float in [0.2, 0.5, 0.8] { let p = V3(88, 0, -222) + V3(-180, 0, -18) * f; column(p.x, p.z, r: 0.35, h: 8, steel) }
            // switchyard, and the line leaving it
            slab(-390, -55, 150, 60, gravel)
            for i in 0..<5 {
                let x = -440 + Float(i) * 26
                for z: Float in [-72, -38] { column(x, z, r: 0.3, h: 12, steel) }
                beam(P(x, -72, 12), P(x, -38, 12), w: 0.5, h: 0.5, steel)
                add(x, -55, V3(6, 5, 8), sc(0.45, 0.5, 0.48, 0.2), kind: 5)
            }
            let along = V3(0, 0, 1)
            var prev = pylon(-500, -55, along: along)
            for z: Float in [170, 395, 620] { let next = pylon(-500, z, along: along); wires(prev, next); prev = next }
            add(-70, 92, V3(52, 14, 18), sc(0.7, 0.68, 0.64, 0.15), kind: 2)
            for (x, z) in [(Float(300), Float(62)), (336, 98), (264, 98)] { tank(x, z, r: 13, h: 15, white) }
            house(70, 66, 8, 6, wall: 3, rise: 1.4, concrete, roof: slate, kind: 6)
            for x: Float in [-90, -30, 40, 100] { lamp(x, 40, h: 11, toward: V3(0, 0, -1), reach: 2.5) }
            for (x, c) in [(Float(20), red), (36, white)] { truck(x, 78, yaw: 1.57, c) }
        case 13:    // vineyard: the estate on its knoll, a road to it lined with cypresses, a chapel
            let ex: Float = 230, ez: Float = -235, wall = sc(0.88, 0.8, 0.62)
            house(ex, ez, 26, 12, wall: 8, rise: 4, yaw: 0.3, wall, roof: tile)
            add(ex + 15, ez - 9, V3(6.5, 17, 6.5), yaw: 0.3, wall, kind: 4); roof(P(ex + 15, ez - 9, 17), 6.5, 6.5, rise: 3, yaw: 0.3, tile, gable: tile, over: 0.7, hip: true)
            house(ex - 26, ez + 16, 18, 9, wall: 5, rise: 3, yaw: 1.87, stone, roof: tile, kind: 7)
            let way: [SIMD2<Float>] = [SIMD2(-10, 74), SIMD2(70, 60), SIMD2(140, -20), SIMD2(180, -120), SIMD2(214, -212)]
            road(way, width: 4, sc(0.72, 0.66, 0.52))
            for i in 1..<way.count {
                let a = way[i - 1], d = way[i] - a, n = Int(simd_length(d) / 15), side = SIMD2(-d.y, d.x) / simd_length(d) * 5
                for k in 0..<n { for s: Float in [-1, 1] { let p = a + d * (Float(k) / Float(n)) + side * s; if p.y < 30 { tree(p.x, p.y, 13) } } }
            }
            house(-262, -300, 6, 9, wall: 4.5, rise: 3, yaw: 0.2, sc(0.92, 0.9, 0.84), roof: tile)
            add(-262, -306, V3(2.2, 9, 2.2), sc(0.92, 0.9, 0.84), kind: 7)
        case 14:    // airport
            slab(0, 100, 440, 92, tarmac)
            for tx: Float in [-180, 180] { slab(tx, 35, 18, 42, tarmac); slab(tx, 35, 0.3, 42, yellow, lift: 0.07) }
            slab(0, 62, 380, 0.3, yellow, lift: 0.07)
            add(0, 174, V3(134, 13, 26), sc(0.42, 0.56, 0.66, 0.7), kind: 3); add(0, 158, V3(112, 0.6, 7), lift: 5, white)
            for x: Float in [-50, 0, 50] { column(x, 155, r: 0.3, h: 5, steel) }
            column(-170, 162, r: 3.2, h: 26, white, kind: 6); add(-170, 162, V3(10, 4.6, 10), lift: 26, sc(0.3, 0.42, 0.5, 0.8), kind: 3); add(-170, 162, V3(11.4, 0.6, 11.4), lift: 30.6, white)
            column(-170, 162, r: 0.12, h: 7, lift: 31.2, steel)
            for (i, hx) in [Float(210), 272, 334].enumerated() { hangar(hx, 176, w: 54, d: 40, h: 15, yaw: 0, [sc(0.72, 0.74, 0.76, 0.3), sc(0.62, 0.68, 0.72, 0.3), sc(0.75, 0.72, 0.66, 0.3)][i]) }
            for (i, x) in [Float(-100), -30, 40].enumerated() { airliner(x, 112, yaw: .pi, tail: [sc(0.1, 0.25, 0.6, 0.5), sc(0.75, 0.12, 0.1, 0.5), sc(0.1, 0.45, 0.4, 0.5)][i]) }
            airliner(150, 96, yaw: 2.2, tail: sc(0.9, 0.6, 0.1, 0.5), scale: 0.36); airliner(176, 104, yaw: 2.0, tail: red, scale: 0.3)
            for (x, z) in [(Float(-300), Float(160)), (-322, 182), (-278, 182)] { tank(x, z, r: 8, h: 9, white) }
            column(-235, 186, r: 1, h: 14, concrete); decor.box(center: P(-235, 186, 15.5), size: V3(7, 2.4, 0.4), color: sc(0.8, 0.3, 0.1, 0.3), rot: simd_quatf(angle: 0.6, axis: V3(0, 1, 0)))
            guardBox(P(-235, 186, 15.5), V3(7, 3, 7))
            for s: Float in [-1, 1] { for k in 0..<8 {
                let x = s * (334 + Float(k) * 26), hgt = 0.6 + Float(k) * 0.35
                decor.cylinder(from: P(x, 0), to: P(x, 0, hgt), r0: 0.05, r1: 0.05, seg: 5, color: steel)
                for dz: Float in [-3, 0, 3] { decor.box(center: P(x, dz, hgt), size: V3(0.3, 0.2, 0.3), color: V4(1, 0.95, 0.8, 8)) }
                decor.box(center: P(x, 0, hgt), size: V3(0.08, 0.08, 6.4), color: steel)
                guardBox(P(x, 0, hgt / 2), V3(0.4, hgt, 6.6))
            } }
            var lx: Float = -320
            while lx <= 320 { for s: Float in [-1, 1] { decor.box(center: P(lx, s * (hw + 0.8), 0.15), size: V3(0.2, 0.3, 0.2), color: V4(0.9, 0.95, 1, 8)) }; lx += 40 }
            slab(0, 212, 150, 26, tarmac)
            let paints = [sc(0.6, 0.06, 0.06, 0.8), sc(0.82, 0.83, 0.85, 0.8), sc(0.06, 0.16, 0.38, 0.8), sc(0.1, 0.1, 0.11, 0.8), sc(0.5, 0.52, 0.5, 0.8)]
            for k in 0..<22 where rng.next() < 0.75 { motorcar(-66 + Float(k) * 6, k % 2 == 0 ? 206 : 218, yaw: 1.57, paints[Int(rng.next() * 4.99)]) }
            truck(-140, 78, yaw: 1.57, yellow, k: 0.8)
        case 15:    // glacier valley: hay barns on the pasture, a chapel, boulders left by the ice
            for (x, z, yaw) in [(Float(-180), Float(64), Float(0.3)), (214, -92, 1.1), (262, 44, 0.2), (-262, -58, 2.0), (150, 150, 0.7), (-40, -420, 0.4)] {
                house(x, z, 6.5, 5.5, wall: 2.8, rise: 2.2, yaw: yaw, sc(0.34, 0.24, 0.16), roof: sc(0.3, 0.28, 0.27), kind: 0)
            }
            house(-96, 112, 5, 8, wall: 4, rise: 3.5, yaw: 0.1, white, roof: slate, kind: 7)
            add(-96, 107, V3(2.4, 8, 2.4), yaw: 0.1, white, kind: 7); roof(P(-96, 107, 8), 2.4, 2.4, rise: 3, yaw: 0.1, slate, gable: slate, hip: true)
            for _ in 0..<26 {
                let x = rng.range(-200, 200), z = rng.range(-760, -430)
                if height(x, z) < (site.waterLevel ?? -99) + 1 { continue }
                rockSpire(x, z, r: rng.range(1.5, 5), h: rng.range(2, 6), sc(0.5, 0.5, 0.49))
            }
            for (i, p) in [(Float(120), Float(-60)), (140, -80), (160, -50), (-200, -20), (-220, 10), (90, 90), (-150, 130)].enumerated() {
                beast(p.0, p.1, yaw: Float(i) * 1.1, size: 2.1, i % 3 == 0 ? sc(0.9, 0.88, 0.82, 0) : sc(0.42, 0.28, 0.2, 0))
            }
        case 16:    // lighthouse point
            let wl = site.waterLevel ?? 0, lx: Float = 205, lz: Float = -236, rock = sc(0.42, 0.39, 0.35)
            for k in 0..<5 { column(lx, lz, r: 4.3 - 0.36 * Float(k), h: 5.6, lift: Float(k) * 5.6, k % 2 == 0 ? white : red) }
            column(lx, lz, r: 4.2, h: 0.5, lift: 28, dark); column(lx, lz, r: 2.1, h: 3.2, lift: 28.5, V4(1, 0.95, 0.7, 0.5), kind: 8)
            decor.cylinder(from: P(lx, lz, 31.7), to: P(lx, lz, 34.5), r0: 2.6, r1: 0.1, seg: 12, color: red)
            house(lx - 22, lz + 26, 12, 8, wall: 3.6, rise: 2.8, yaw: 0.4, white, roof: slate)
            road([SIMD2(34, 42), SIMD2(110, -20), SIMD2(160, -130), SIMD2(196, -216)], width: 2.6, sc(0.66, 0.6, 0.48))
            for (x, z, r, h) in [(Float(-70), Float(-262), Float(15), Float(52)), (-135, -325, 11, 40), (30, -372, 19, 60), (340, -430, 14, 46)] { rockSpire(x, z, r: r, h: h, rock, base: wl - 14) }
            for s: Float in [-1, 1] { rockSpire(-218 + s * 21, -276, r: 10, h: 44, rock, base: wl - 14) }
            decor.blob(center: V3(-218, wl + 28, -276), radii: V3(35, 6.5, 10), color: surf(rock, 9), seg: 14, rings: 7, seed: 5, lump: 0.25, under: 0.75)
            guardBox(V3(-218, wl + 28, -276), V3(60, 10, 15))
            for (x, z, yaw, len, sail) in [(Float(80), Float(-330), Float(0.4), Float(10), true), (-20, -300, 2.0, 8, true), (150, -430, 1.2, 14, false), (-290, -390, 0.2, 9, true), (-120, -420, 2.6, 12, false)] {
                boat(x, z, yaw: yaw, len: len, sail: sail, sail ? white : sc(0.16, 0.3, 0.5, 0.3))
            }
            var fx: Float = -130
            while fx <= 110 {
                let p = P(fx, -104)
                decor.cylinder(from: p, to: p + V3(0, 1.15, 0), r0: 0.05, r1: 0.045, seg: 5, color: V4(0.4, 0.32, 0.24, 0.02))
                if fx < 110 { let q = P(fx + 4, -104); for y: Float in [0.5, 1.05] { decor.cylinder(from: p + V3(0, y, 0), to: q + V3(0, y, 0), r0: 0.008, r1: 0.008, seg: 3, color: V4(0.45, 0.45, 0.45, 0.2)) } }
                fx += 4
            }
            for (i, p) in [(Float(-160), Float(-40)), (-180, -60), (-150, -70), (130, -50), (-200, 40), (-220, 60)].enumerated() { beast(p.0, p.1, yaw: Float(i) * 0.9, size: 1, sc(0.9, 0.89, 0.84, 0)) }
        case 17:    // monument mesa: three needles, an arch, a trading post on a dirt road with its telegraph line
            let rock = sc(0.5, 0.25, 0.16)
            for (x, z, r, h) in [(Float(-250), Float(-430), Float(12), Float(78)), (-218, -452, 9, 52), (215, -390, 13, 88), (330, -250, 10, 40)] { rockSpire(x, z, r: r, h: h, rock) }
            for s: Float in [-1, 1] { rockSpire(-30 + s * 25, -300, r: 11, h: 46, rock) }
            decor.blob(center: P(-30, -300, 47), radii: V3(41, 8, 11.5), color: surf(rock, 9), seg: 14, rings: 7, seed: 9, lump: 0.25, under: 0.75)
            guardBox(P(-30, -300, 47), V3(66, 12, 17))
            road([SIMD2(-520, 96), SIMD2(-100, 74), SIMD2(200, 84), SIMD2(560, 62)], width: 5, sc(0.6, 0.33, 0.21))
            var last: V3? = nil
            for x in stride(from: Float(-500), through: 540, by: 60) {
                let z: Float = 64 + 6 * sin(x / 200)
                column(x, z, r: 0.13, h: 7, wood); beam(P(x, z, 6.5) - V3(0, 0, 0.9), P(x, z, 6.5) + V3(0, 0, 0.9), w: 0.12, h: 0.12, wood, solid: false)
                if let l = last { for dz: Float in [-0.8, 0.8] { cable(l + V3(0, 0, dz), P(x, z, 6.6) + V3(0, 0, dz), sag: 0.9, r: 0.012, dark, solid: false, parts: 4) } }
                last = P(x, z, 6.6)
            }
            house(124, 112, 13, 8, wall: 3.2, rise: 1.3, yaw: 0.1, sc(0.72, 0.5, 0.36), roof: sc(0.46, 0.28, 0.2), kind: 7)
            truck(104, 100, yaw: 0.6, sc(0.45, 0.22, 0.14, 0.1), k: 0.75)
        case 18:    // ski resort: pistes and the lift line cut through the forest; pylons, cable, chairs; chalets
            let a = SIMD2<Float>(120, -60), b = SIMD2<Float>(300, -1250), ab = b - a
            trees.removeAll { t in
                let p = SIMD2(t.p.x, t.p.z), k = clampf(simd_dot(p - a, ab) / simd_dot(ab, ab), 0, 1)
                if simd_length(p - a - ab * k) < 13 { return true }
                return t.p.z < -80 && (0..<3).contains { abs(t.p.x - SiteSpec.pisteX($0, t.p.z)) < 22 }
            }
            var prev: V3? = nil
            for k in 0...11 {
                let p = a + ab * (Float(k) / 11), top = P(p.x, p.y, 11)
                column(p.x, p.y, r: 0.45, h: 11, steel); beam(top - V3(3.2, 0, 0), top + V3(3.2, 0, 0), w: 0.4, h: 0.4, steel)
                if let q = prev { for s: Float in [-1, 1] {
                    let c0 = q + V3(s * 2.9, 0, 0), c1 = top + V3(s * 2.9, 0, 0)
                    cable(c0, c1, sag: 1.6, r: 0.05, dark, parts: 4)
                    for j in 1...3 {
                        let t = Float(j) / 4, h = c0 + (c1 - c0) * t - V3(0, 1.6 * 4 * t * (1 - t), 0)
                        decor.cylinder(from: h, to: h - V3(0, 2.3, 0), r0: 0.04, r1: 0.04, seg: 4, color: steel)
                        decor.box(center: h - V3(0, 2.4, 0), size: V3(1.9, 0.12, 0.6), color: sc(0.8, 0.15, 0.1, 0.2)); decor.box(center: h - V3(0, 2.0, 0.3), size: V3(1.9, 0.7, 0.08), color: sc(0.8, 0.15, 0.1, 0.2))
                    }
                } }
                prev = top
            }
            let timber = sc(0.36, 0.25, 0.17), snow = sc(0.96, 0.97, 0.99, 0.1)
            house(120, -50, 12, 14, wall: 6, rise: 3, timber, roof: snow); house(300, -1262, 12, 12, wall: 6, rise: 3, timber, roof: snow)
            for (x, z, yaw) in [(Float(-74), Float(72), Float(0.2)), (-112, 44, 1.4), (70, 84, -0.2), (150, 64, 0.5), (204, 24, 1.2), (-160, 92, 0.1), (240, 78, 0.3)] {
                house(x, z, 11, 9, wall: 5, rise: 3.6, yaw: yaw, timber, roof: snow)
            }
            add(-214, 56, V3(42, 16, 16), sc(0.86, 0.8, 0.7), kind: 4); roof(P(-214, 56, 16), 42, 16, rise: 6, yaw: 0, snow, gable: surf(sc(0.86, 0.8, 0.7), 4))
            for k in 0..<14 {
                let z = -150 - Float(k) * 22, x = SiteSpec.pisteX(1, z) + (k % 2 == 0 ? 4 : -4), p = P(x, z)
                decor.cylinder(from: p, to: p + V3(0, 1.8, 0), r0: 0.03, r1: 0.03, seg: 4, color: k % 2 == 0 ? red : sc(0.1, 0.3, 0.8))
            }
        default: break
        }

        // ---- the open sites of the first series
        switch site.key {
        case "downs":       // a ring of standing stones, sheep on the hill
            for k in 0..<11 {
                let a = Float(k) / 11 * 2 * .pi, x = -140 + cos(a) * 13, z = -165 + sin(a) * 13
                boxes.append(SolidBox(c: P(x, z, 1.5), half: V3(0.7, 1.7, 0.4), yaw: -a + .pi / 2, color: sc(0.52, 0.51, 0.48), kind: 9))
            }
            add(-140 + 13, -165, V3(1, 0.6, 5.4), lift: 3.2, sc(0.52, 0.51, 0.48), kind: 9)
            column(165, -92, r: 0.3, h: 1.3, white)
            for i in 0..<34 {
                let x = rng.range(-320, 320), z = rng.range(-330, 250)
                if abs(x) < site.runwayLen / 2 + 20 && abs(z) < 70 { continue }
                beast(x, z, yaw: Float(i) * 1.7, size: 1, sc(0.9, 0.89, 0.84, 0))
            }
        case "terraces":    // huts on stilts among the paddies, a pagoda
            let straw = sc(0.62, 0.52, 0.3), bamboo = sc(0.5, 0.4, 0.24)
            for (x, z, yaw) in [(Float(-150), Float(-90), Float(0.3)), (170, -140, 1.2), (-90, 150, 0.5), (220, 120, 2.0), (120, 170, 0.1)] {
                for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(x + s * 1.8, z + t * 1.4, r: 0.1, h: 1.6, bamboo) } }
                house(x, z, 5, 4, wall: 2.2, rise: 2.4, yaw: yaw, bamboo, roof: straw, kind: 0, hip: true, lift: 1.6)
            }
            let px: Float = -210, pz: Float = -230
            for k in 0..<3 {
                let w = 9 - Float(k) * 2.4, y = Float(k) * 5
                add(px, pz, V3(w, 4, w), lift: y, sc(0.7, 0.2, 0.14), kind: 7)
                roof(P(px, pz, y + 4), w + 2.4, w + 2.4, rise: 1.6, yaw: 0, sc(0.2, 0.26, 0.24), gable: slate, over: 0.6, hip: true)
            }
        case "outback":     // a water tower, a wind pump, a road train on the apron
            for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(-122 + s * 2.4, 122 + t * 2.4, r: 0.16, h: 10, steel) } }
            tank(-122, 122, r: 3.6, h: 4, sc(0.7, 0.72, 0.72, 0.4), lift: 10)
            column(150, -150, r: 0.18, h: 9, steel)
            for k in 0..<12 { let a = Float(k) / 12 * 2 * .pi, h = P(150, -150, 9) + V3(0, 0, 0.5); beam(h, h + V3(cos(a), sin(a), 0) * 1.5, w: 0.04, h: 0.5, sc(0.75, 0.75, 0.76, 0.5), solid: false) }
            truck(40, 96, yaw: 1.57, sc(0.7, 0.2, 0.1, 0.3)); truck(49.5, 96, yaw: 1.57, white)
        case "karst":       // a pagoda and fishermen's huts on the valley floor
            let px: Float = -170, pz: Float = -150
            for k in 0..<4 {
                let w = 8 - Float(k) * 1.6, y = Float(k) * 4.4
                add(px, pz, V3(w, 3.6, w), lift: y, sc(0.66, 0.2, 0.14), kind: 7)
                roof(P(px, pz, y + 3.6), w + 2.4, w + 2.4, rise: 1.4, yaw: 0, sc(0.22, 0.28, 0.26), gable: slate, over: 0.6, hip: true)
            }
            for (x, z, yaw) in [(Float(150), Float(-120), Float(0.4)), (176, -104, 1.3), (-120, 120, 0.2), (200, 90, 0.9)] {
                house(x, z, 6, 4.6, wall: 2.6, rise: 2, yaw: yaw, sc(0.5, 0.4, 0.26), roof: sc(0.56, 0.48, 0.3), kind: 0)
            }
        case "caldera":     // an observatory, and blocks thrown out by the last eruption
            column(-200, 124, r: 5, h: 4.5, white, kind: 6)
            decor.ellipsoid(center: P(-200, 124, 4.5), radii: V3(5, 5, 5), color: sc(0.9, 0.9, 0.92, 0.5), seg: 16, rings: 8)
            column(-200, 124, r: 3.6, h: 4, lift: 4.5, .zero, hidden: true)
            house(-184, 136, 9, 6, wall: 3, rise: 1.2, yaw: 0.3, concrete, roof: slate, kind: 6)
            for _ in 0..<40 {
                let x = rng.range(-340, 340), z = rng.range(-360, 240)
                if abs(x) < site.runwayLen / 2 + 30 && abs(z) < 90 { continue }
                rockSpire(x, z, r: rng.range(0.8, 3), h: rng.range(1, 4.5), sc(0.24, 0.21, 0.2))
            }
        case "archipelago", "atoll":    // a jetty, boats at anchor, huts on stilts over the shallows
            let wl = site.waterLevel ?? 0, atoll = site.key == "atoll"
            var z: Float = atoll ? -28 : -200, n = 0
            while n < 60 && z > -420 {                                    // walk out from the field until the water is deep enough, then build
                if height(-52, z) < wl - 0.9 { break }
                z -= 4; n += 1
            }
            for k in -3..<9 {
                add(-52, z - Float(k) * 4, V3(2.6, 0.25, 4), lift: 0.8, wood, base: wl)
                if k % 2 == 0 { for s: Float in [-1, 1] { column(-52 + s * 1.2, z - Float(k) * 4, r: 0.12, h: 3, wood, base: wl - 1.6) } }
            }
            for (dx, dz, yaw, len, sail) in [(Float(14), Float(-44), Float(0.5), Float(8), true), (-40, -70, 2.0, 7, true), (60, -90, 1.1, 6, false), (-90, -40, 0.3, 5, false)] {
                boat(-52 + dx, z + dz, yaw: yaw, len: len, sail: sail, sail ? white : sc(0.75, 0.25, 0.15, 0.3))
            }
            for (dx, dz) in [(Float(-70), Float(-16)), (-96, -30), (-122, -14)] {
                let x = -52 + dx, zz = z + dz
                guard height(x, zz) < wl - 0.3 else { continue }
                for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(x + s * 2, zz + t * 1.6, r: 0.12, h: 3.2, wood, base: wl - 1.6) } }
                house(x, zz, 5.4, 4.4, wall: 2.3, rise: 2.4, yaw: 0, sc(0.56, 0.44, 0.28), roof: sc(0.62, 0.54, 0.32), kind: 0, hip: true, lift: 1.6)
            }
            if atoll { beam(V3(150, wl - 1.5, 118), V3(196, wl + 6, 134), w: 9, h: 7, sc(0.36, 0.2, 0.14, 0.05), kind: 5) }    // a wreck on the ocean side
        case "badlands":    // the headframe of an old mine, its shack, hoodoos in the clay hills
            let mx: Float = -128, mz: Float = 98, rust = sc(0.4, 0.24, 0.17, 0.05)
            for s: Float in [-1, 1] { beam(P(mx + s * 5, mz), P(mx, mz, 16), w: 0.4, h: 0.4, rust); beam(P(mx, mz + s * 3), P(mx, mz, 16), w: 0.4, h: 0.4, rust) }
            add(mx, mz, V3(2.4, 2, 2.4), lift: 15, rust, kind: 5)
            house(mx + 14, mz + 6, 8, 5, wall: 2.6, rise: 1.4, yaw: 0.2, sc(0.5, 0.4, 0.3), roof: rust, kind: 5)
            truck(mx - 14, mz - 6, yaw: 0.9, rust, k: 0.7)
            for _ in 0..<16 {
                let a = rng.range(0, 2 * .pi), r = rng.range(190, 360), x = cos(a) * r, z = sin(a) * r
                if z < 0 && abs(x) < 60 { continue }
                rockSpire(x, z, r: rng.range(2.5, 5), h: rng.range(9, 22), sc(0.66, 0.42, 0.32))
            }
        case "oasis":       // a mud-brick fort, tents by the pool, a well
            let mud = sc(0.74, 0.6, 0.42), fx: Float = 150, fz: Float = 98
            for s: Float in [-1, 1] { add(fx, fz + s * 20, V3(40, 6, 2), mud, kind: 7); add(fx + s * 20, fz, V3(2, 6, 40), mud, kind: 7) }
            for s: Float in [-1, 1] { for t: Float in [-1, 1] { add(fx + s * 20, fz + t * 20, V3(6, 9, 6), mud, kind: 7) } }
            add(fx, fz + 4, V3(14, 8, 12), mud, kind: 7)
            for (x, z, yaw) in [(Float(-42), Float(-96), Float(0.4)), (-26, -112, 1.2), (-58, -80, 0.1), (-70, -102, 0.8)] { canopy(x, z, 5.5, 4.2, yaw: yaw, sc(0.3, 0.26, 0.24), poles: 0) }
            column(-30, -84, r: 1, h: 0.8, stone, kind: 7)
            for s: Float in [-1, 1] { column(-30 + s * 1.1, -84, r: 0.07, h: 2.2, wood) }
        case "icelake":     // fishing huts out on the ice, a rink with its boards and goals
            let huts = [sc(0.75, 0.16, 0.12), sc(0.15, 0.35, 0.6), sc(0.9, 0.75, 0.15), sc(0.2, 0.5, 0.32), sc(0.85, 0.5, 0.15)]
            for (i, p) in [(Float(-190), Float(-170)), (-150, -90), (-90, -200), (-60, -110), (70, -210), (210, -200), (240, -110), (-240, 60), (190, 80)].enumerated() {
                house(p.0, p.1, 2.8, 2.8, wall: 2.2, rise: 0.9, yaw: Float(i) * 0.5, huts[i % 5], roof: slate, kind: 0)
            }
            let rx: Float = 130, rz: Float = -110
            for s: Float in [-1, 1] { add(rx, rz + s * 15, V3(60, 1, 0.3), white); add(rx + s * 30, rz, V3(0.3, 1, 30), white) }
            slab(rx, rz, 0.4, 30, red); for s: Float in [-1, 1] { slab(rx + s * 18, rz, 0.3, 30, sc(0.1, 0.3, 0.8)) }
            for s: Float in [-1, 1] { add(rx + s * 26, rz, V3(1, 1.2, 1.8), red) }
        case "tundra":      // a research station on legs, a radio mast, fuel tanks, a line of marker flags
            let orange = sc(0.9, 0.42, 0.1, 0.3)
            for k in 0..<4 {
                let x = -120 + Float(k) * 13.5
                for s: Float in [-1, 1] { for t: Float in [-1, 1] { column(x + s * 5, 62 + t * 1.6, r: 0.14, h: 1.7, steel) } }
                add(x, 62, V3(12, 3.2, 4.6), lift: 1.7, k % 2 == 0 ? orange : sc(0.2, 0.36, 0.6, 0.3), kind: 5)
            }
            column(-134, 76, r: 3.2, h: 2.4, white, kind: 6); decor.ellipsoid(center: P(-134, 76, 2.4), radii: V3(3.2, 3.2, 3.2), color: white, seg: 14, rings: 7)
            column(-134, 76, r: 2.3, h: 2.6, lift: 2.4, .zero, hidden: true)
            let mx: Float = 150, mz: Float = 84
            for k in 0..<4 { column(mx, mz, r: 0.25, h: 10, lift: Float(k) * 10, k % 2 == 0 ? red : white) }
            for a: Float in [0.3, 2.4, 4.5] { cable(P(mx, mz, 38), P(mx + cos(a) * 24, mz + sin(a) * 24, 0.3), sag: 0.4, r: 0.03, dark, parts: 3) }
            for k in 0..<3 {
                let c = P(-60 + Float(k) * 5, 84, 1.4)
                decor.cylinder(from: c - V3(0, 0, 3), to: c + V3(0, 0, 3), r0: 1.2, r1: 1.2, seg: 12, color: sc(0.8, 0.8, 0.78, 0.4))
                guardBox(c, V3(2.4, 2.6, 6))
            }
            for k in 0..<12 {
                let p = P(-60 + Float(k) * 22, -70 - 14 * sin(Float(k) * 0.6))
                decor.cylinder(from: p, to: p + V3(0, 2.2, 0), r0: 0.025, r1: 0.025, seg: 4, color: dark)
                decor.tri(p + V3(0, 2.2, 0), p + V3(0, 1.8, 0), p + V3(0.7, 2.0, 0.1), red)
            }
        default: break
        }
    }
}
