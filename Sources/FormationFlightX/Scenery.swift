import simd
import Foundation

// Scenery is split into four meshes:
//   objects     – buildings, vehicles, people, rocks (vertex alpha = gloss)
//   vegetation  – trees, bushes, hedges (vertex alpha = wind sway weight)
//   grass       – grass tufts and flowers (same shading as vegetation, casts no shadow)
//   treeShadows – soft dark discs under distant trees that are outside the shadow map

private func cg(_ r: Float, _ g: Float, _ b: Float, _ gloss: Float = 0.03) -> V4 { V4(r, g, b, gloss) }
private func leaf(_ r: Float, _ g: Float, _ b: Float) -> V4 { V4(r, g, b, 0) }
private func shade(_ c: V4, _ k: Float) -> V4 { V4(c.x * k, c.y * k, c.z * k, c.w) }

/// Rounded-rectangle-like ring (superellipse) in the XY plane at depth z.
func superRing(x: Float = 0, y: Float, z: Float, w: Float, h: Float, exp e: Float = 2.6, seg: Int = 16) -> [V3] {
    (0..<seg).map { j in
        let a = Float(j) / Float(seg) * 2 * .pi
        let c = cos(a), s = sin(a)
        let cx = (c < 0 ? -1 : 1) * pow(abs(c), 2 / e), sy = (s < 0 ? -1 : 1) * pow(abs(s), 2 / e)
        return V3(x + cx * w, y + sy * h, z)
    }
}

extension MeshBuilder {
    /// Lumpy ellipsoid used for foliage and rocks. Shaded darker underneath; `sway` is added to alpha towards the top.
    mutating func blob(center: V3, radii: V3, color: V4, seg: Int, rings: Int, seed: Int32, lump: Float, sway: Float = 0, under: Float = 0.5) {
        var pts: [[V3]] = [], nrm: [[V3]] = [], col: [[V4]] = []
        for i in 0...rings {
            let phi = -Float.pi / 2 + Float.pi * Float(i) / Float(rings)
            var rp: [V3] = [], rn: [V3] = [], rc: [V4] = []
            for j in 0..<seg {
                let th = Float(j) / Float(seg) * 2 * .pi
                let d = V3(cos(th) * cos(phi), sin(phi), sin(th) * cos(phi))
                let n = 1 + lump * cos(phi) * 2 * (vnoise(d.x * 2.1 + 7.3, d.z * 2.1 + d.y * 1.7 + 3.1, seed) - 0.5)
                rp.append(center + d * radii * n)
                rn.append(normalize(d / radii))
                let t = (d.y + 1) / 2
                let k = (under + (1 - under) * t) * (0.9 + 0.2 * hash2(Int32(i), Int32(j), seed))
                rc.append(V4(color.x * k, color.y * k, color.z * k, color.w + sway * t))
            }
            pts.append(rp); nrm.append(rn); col.append(rc)
        }
        for i in 0..<rings { for j in 0..<seg {
            let k = (j + 1) % seg
            v(pts[i][j], nrm[i][j], col[i][j]); v(pts[i][k], nrm[i][k], col[i][k]); v(pts[i + 1][k], nrm[i + 1][k], col[i + 1][k])
            v(pts[i][j], nrm[i][j], col[i][j]); v(pts[i + 1][k], nrm[i + 1][k], col[i + 1][k]); v(pts[i + 1][j], nrm[i + 1][j], col[i + 1][j])
        } }
    }

    /// Clump of three crossed grass cards. The blade shapes are cut out in the fragment shader;
    /// the normal attribute carries the card's texture coordinates.
    mutating func grassClump(at p: V3, height h: Float, width w: Float, base: V4, tip: V4, rng: inout LCG) {
        let k = rng.range(0.85, 1.15)
        let b0 = V4(base.x * k, base.y * k, base.z * k, 0), t1 = V4(tip.x * k, tip.y * k, tip.z * k, 1)
        let a0 = rng.range(0, .pi)
        for i in 0..<3 {
            let a = a0 + Float(i) * 1.05
            let dir = V3(cos(a), 0, sin(a))
            let s0 = floor(rng.next() * 60)
            let c = p + V3(rng.range(-0.12, 0.12), -0.02, rng.range(-0.12, 0.12))
            let l = c - dir * (w / 2), r = c + dir * (w / 2)
            let top = V3(rng.range(-0.1, 0.1) * h, h, rng.range(-0.1, 0.1) * h)
            v(l, V3(s0, 0, 0), b0); v(r, V3(s0 + 1, 0, 0), b0); v(r + top, V3(s0 + 1, 1, 0), t1)
            v(l, V3(s0, 0, 0), b0); v(r + top, V3(s0 + 1, 1, 0), t1); v(l + top, V3(s0, 1, 0), t1)
        }
    }

    mutating func flower(at p: V3, height: Float, color: V4, rng: inout LCG) {
        let up = V3(0, 1, 0), s = height * 0.1
        let c = p + V3(rng.range(-0.05, 0.05), height, rng.range(-0.05, 0.05))
        let stem = leaf(0.25, 0.45, 0.15)
        v(p - V3(0.006, 0, 0), up, stem); v(p + V3(0.006, 0, 0), up, stem); v(c, up, V4(stem.x, stem.y, stem.z, 1))
        let col = V4(color.x, color.y, color.z, 1)
        v(c + V3(-s, 0, 0), up, col); v(c + V3(s, 0, 0), up, col); v(c + V3(0, s * 1.4, 0), up, col)
        v(c + V3(0, 0, -s), up, col); v(c + V3(0, 0, s), up, col); v(c + V3(0, s * 1.4, 0), up, col)
    }
}

extension Terrain {
    private func gy(_ x: Float, _ z: Float) -> V3 { V3(x, height(x, z), z) }
    private var hw: Float { site.runwayWid / 2 }
    private var hl: Float { site.runwayLen / 2 }

    /// True inside the mown part of the field (runway, pits, parking).
    private func mown(_ x: Float, _ z: Float) -> Bool {
        abs(x) < hl + 14 && z > -hw - 13 && z < hw + 48
    }

    // MARK: Vegetation

    private func deciduous(_ b: inout MeshBuilder, _ t: Tree, _ rng: inout LCG, detail: Bool, autumn: Bool = false) {
        let h = t.h, g = rng.next()
        let bark = leaf(0.27 + 0.06 * g, 0.2 + 0.04 * g, 0.14)
        b.cylinder(from: t.p - V3(0, 0.2, 0), to: t.p + V3(0, h * 0.45, 0), r0: h * 0.035, r1: h * 0.018, seg: detail ? 7 : 5, color: bark)
        let hue = rng.next()
        // autumn woods run from yellow through orange to deep red, with the odd tree still green
        let green = !autumn ? leaf(0.13 + 0.14 * hue, 0.30 + 0.14 * g, 0.07 + 0.05 * hue)
            : (hue < 0.12 ? leaf(0.3, 0.4, 0.12) : leaf(0.5 + 0.3 * g, 0.16 + 0.4 * hue * (0.5 + 0.5 * g), 0.05))
        let seed = Int32(truncatingIfNeeded: Int(t.p.x * 13 + t.p.z * 7))
        if detail {
            for k in 0..<3 {     // a few visible limbs
                let a = Float(k) * 2.1 + g * 6
                b.cylinder(from: t.p + V3(0, h * (0.3 + 0.05 * Float(k)), 0), to: t.p + V3(cos(a) * h * 0.2, h * 0.55, sin(a) * h * 0.2), r0: h * 0.014, r1: h * 0.006, seg: 5, color: bark)
            }
            b.blob(center: t.p + V3(0, h * 0.68, 0), radii: V3(h * 0.26, h * 0.3, h * 0.26), color: green, seg: 9, rings: 6, seed: seed, lump: 0.22, sway: 2)
            for k in 0..<5 {
                let a = Float(k) * 1.257 + g * 6, r = h * rng.range(0.16, 0.24)
                let c = t.p + V3(cos(a) * h * 0.2, h * rng.range(0.5, 0.74), sin(a) * h * 0.2)
                b.blob(center: c, radii: V3(r, r * 0.85, r), color: shade(green, rng.range(0.85, 1.12)), seg: 8, rings: 5, seed: seed &+ Int32(k), lump: 0.25, sway: 2)
            }
        } else {
            b.blob(center: t.p + V3(0, h * 0.66, 0), radii: V3(h * 0.3, h * 0.34, h * 0.3), color: green, seg: 7, rings: 4, seed: seed, lump: 0.25, sway: 2)
            b.blob(center: t.p + V3(h * 0.14, h * 0.52, h * 0.08), radii: V3(h * 0.2, h * 0.2, h * 0.2), color: shade(green, 0.9), seg: 6, rings: 3, seed: seed &+ 1, lump: 0.25, sway: 2)
        }
    }

    private func conifer(_ b: inout MeshBuilder, _ t: Tree, _ rng: inout LCG, detail: Bool, snow: Bool = false) {
        let h = t.h, g = rng.next()
        b.cylinder(from: t.p - V3(0, 0.2, 0), to: t.p + V3(0, h * 0.3, 0), r0: h * 0.025, r1: h * 0.016, seg: 5, color: leaf(0.25, 0.18, 0.12))
        let green = leaf(0.06 + 0.06 * g, 0.2 + 0.1 * g, 0.1 + 0.04 * g)
        let tiers = detail ? 6 : 3, seg = detail ? 9 : 6
        for k in 0..<tiers {
            let f = Float(k) / Float(tiers)
            let y0 = h * (0.16 + 0.8 * f), r = h * 0.22 * (1 - f * 0.85), th = h * 0.9 / Float(tiers) * 1.5
            // drooping skirt: a cone whose rim alternates in radius
            let rim = (0..<seg).map { j -> V3 in
                let a = Float(j) / Float(seg) * 2 * .pi + f * 2
                let rr = r * (j % 2 == 0 ? 1 : 0.72)
                return t.p + V3(cos(a) * rr, y0 - th * 0.12, sin(a) * rr)
            }
            let top = t.p + V3(0, y0 + th, 0)
            let cRim = V4(green.x * 0.75, green.y * 0.75, green.z * 0.75, 1 + 2 * f)
            let cTop = snow ? V4(0.9, 0.93, 0.97, 1.5 + 2 * f) : V4(green.x * 1.15, green.y * 1.15, green.z * 1.15, 1.5 + 2 * f)
            for j in 0..<seg {
                let a = rim[j], c = rim[(j + 1) % seg]
                let n = normalize(V3(a.x - t.p.x, r * 0.6, a.z - t.p.z))
                let n2 = normalize(V3(c.x - t.p.x, r * 0.6, c.z - t.p.z))
                b.v(a, n, cRim); b.v(c, n2, cRim); b.v(top, normalize(n + n2), cTop)
            }
        }
    }

    private func palm(_ b: inout MeshBuilder, _ t: Tree, _ rng: inout LCG) {
        let h = t.h, lean = V3(rng.range(-0.25, 0.25), 0, rng.range(-0.25, 0.25))
        let bark = leaf(0.42, 0.35, 0.26)
        func trunk(_ f: Float) -> V3 { t.p + V3(0, h * f, 0) + lean * (h * f * f) }
        for k in 0..<5 {
            let f0 = Float(k) / 5, f1 = Float(k + 1) / 5
            b.cylinder(from: trunk(f0) - (k == 0 ? V3(0, 0.2, 0) : .zero), to: trunk(f1), r0: 0.2 - 0.02 * Float(k), r1: 0.18 - 0.02 * Float(k), seg: 6, color: bark)
        }
        let top = trunk(1), up = V3(0, 1, 0)
        let green = leaf(0.12 + 0.08 * rng.next(), 0.36 + 0.1 * rng.next(), 0.1)
        let fronds = 9
        for k in 0..<fronds {
            let a = Float(k) / Float(fronds) * 2 * .pi + rng.range(-0.2, 0.2)
            let dir = V3(cos(a), 0, sin(a)), side = V3(-dir.z, 0, dir.x)
            let len = h * rng.range(0.3, 0.42)
            var prev = top, prevW: Float = 0.12
            for j in 1...5 {
                let f = Float(j) / 5
                let p = top + dir * (len * f) + V3(0, len * (0.35 * f - 0.75 * f * f), 0)
                let w = len * 0.16 * (1 - f * 0.85)
                let c0 = V4(green.x * 0.8, green.y * 0.8, green.z * 0.8, 1 + 3 * (f - 0.2)), c1 = V4(green.x, green.y, green.z, 1 + 3 * f)
                b.v(prev - side * prevW, up, c0); b.v(prev + side * prevW, up, c0); b.v(p + side * w, up, c1)
                b.v(prev - side * prevW, up, c0); b.v(p + side * w, up, c1); b.v(p - side * w, up, c1)
                prev = p; prevW = w
            }
        }
    }

    private func acacia(_ b: inout MeshBuilder, _ t: Tree, _ rng: inout LCG, detail: Bool) {
        let h = t.h, g = rng.next()
        let bark = leaf(0.3, 0.24, 0.17)
        let seed = Int32(truncatingIfNeeded: Int(t.p.x * 13 + t.p.z * 7))
        b.cylinder(from: t.p - V3(0, 0.2, 0), to: t.p + V3(0, h * 0.5, 0), r0: h * 0.04, r1: h * 0.028, seg: 6, color: bark)
        for k in 0..<3 {
            let a = Float(k) * 2.1 + g * 6
            b.cylinder(from: t.p + V3(0, h * 0.45, 0), to: t.p + V3(cos(a) * h * 0.4, h * 0.85, sin(a) * h * 0.4), r0: h * 0.022, r1: h * 0.01, seg: 5, color: bark)
        }
        let green = leaf(0.24 + 0.08 * g, 0.36 + 0.06 * g, 0.12)
        b.blob(center: t.p + V3(0, h * 0.92, 0), radii: V3(h * 0.75, h * 0.16, h * 0.75), color: green, seg: detail ? 10 : 7, rings: detail ? 5 : 3, seed: seed, lump: 0.22, sway: 1.5, under: 0.4)
    }

    private func cypress(_ b: inout MeshBuilder, _ t: Tree, _ rng: inout LCG, detail: Bool) {
        let h = t.h
        let seed = Int32(truncatingIfNeeded: Int(t.p.x * 13 + t.p.z * 7))
        b.cylinder(from: t.p - V3(0, 0.2, 0), to: t.p + V3(0, h * 0.15, 0), r0: h * 0.02, r1: h * 0.018, seg: 5, color: leaf(0.28, 0.2, 0.13))
        let g = rng.next()
        b.blob(center: t.p + V3(0, h * 0.54, 0), radii: V3(h * 0.1, h * 0.48, h * 0.1), color: leaf(0.07 + 0.04 * g, 0.2 + 0.06 * g, 0.09), seg: detail ? 8 : 6, rings: detail ? 7 : 4, seed: seed, lump: 0.12, sway: 1.5, under: 0.6)
    }

    private func bush(_ b: inout MeshBuilder, at p: V3, size s: Float, color: V4, rng: inout LCG) {
        let seed = Int32(truncatingIfNeeded: Int(p.x * 31 + p.z * 17))
        let n = 2 + Int(rng.next() * 3)
        for k in 0..<n {
            let o = V3(rng.range(-0.5, 0.5) * s, 0, rng.range(-0.5, 0.5) * s)
            let r = s * rng.range(0.4, 0.7)
            b.blob(center: p + o + V3(0, r * 0.55, 0), radii: V3(r, r * 0.75, r), color: shade(color, rng.range(0.85, 1.15)), seg: 7, rings: 4, seed: seed &+ Int32(k), lump: 0.3, sway: 0.7)
        }
    }

    func buildVegetation() -> MeshBuilder {
        var b = MeshBuilder()
        var rng = LCG(UInt64(site.seed) + 99)
        for t in trees {
            let near = t.p.x * t.p.x + t.p.z * t.p.z < 300 * 300
            switch site.trees {
            case 0: deciduous(&b, t, &rng, detail: near)
            case 2: conifer(&b, t, &rng, detail: near)
            case 3: palm(&b, t, &rng)
            case 4: acacia(&b, t, &rng, detail: near)
            case 5:
                if rng.next() < 0.55 { cypress(&b, t, &rng, detail: near) }
                else { deciduous(&b, Tree(p: t.p, h: t.h * 0.55), &rng, detail: near) }       // olive
            case 6: conifer(&b, t, &rng, detail: near, snow: true)
            case 8:
                if rng.next() < 0.8 { deciduous(&b, t, &rng, detail: near, autumn: true) } else { conifer(&b, t, &rng, detail: near) }
            case 7:
                if rng.next() < 0.68 { deciduous(&b, t, &rng, detail: near) } else { conifer(&b, t, &rng, detail: near) }
            default:
                // desert: scrub and the odd cactus
                if rng.next() > 0.3 {
                    bush(&b, at: t.p, size: t.h * 0.7, color: leaf(0.38, 0.4, 0.22), rng: &rng)
                } else {
                    let h = t.h * 1.6, col = leaf(0.25, 0.4, 0.2)
                    b.cylinder(from: t.p, to: t.p + V3(0, h, 0), r0: 0.16, r1: 0.13, seg: 8, color: col)
                    b.blob(center: t.p + V3(0, h, 0), radii: V3(0.13, 0.13, 0.13), color: col, seg: 8, rings: 3, seed: 3, lump: 0)
                    for s in [Float(-1), 1] where rng.next() > 0.3 {
                        let y = h * rng.range(0.35, 0.6)
                        b.cylinder(from: t.p + V3(0, y, 0), to: t.p + V3(s * 0.45, y + 0.1, 0), r0: 0.1, r1: 0.1, seg: 6, color: col)
                        b.cylinder(from: t.p + V3(s * 0.45, y + 0.05, 0), to: t.p + V3(s * 0.45, y + h * 0.35, 0), r0: 0.1, r1: 0.09, seg: 6, color: col)
                    }
                }
            }
        }
        if site.layout == 13 {
            // vineyards: blocks of rows combing the slopes, each row a low green hedge that follows the ground
            let blocks = SiteSpec.vineBlocks
            for (cx, cz, w, d, ang) in blocks {
                let q = simd_quatf(angle: ang, axis: V3(0, 1, 0))
                var v: Float = -d / 2
                while v <= d / 2 {
                    var u: Float = -w / 2
                    while u <= w / 2 {
                        let o = q.act(V3(u, 0, v)), x = cx + o.x, z = cz + o.z
                        u += 7
                        if (abs(x) < 115 && z > -60 && z < 90) || (x - 230) * (x - 230) + (z + 235) * (z + 235) < 55 * 55 { continue }
                        let g = rng.next()
                        let c = V3(x, (height(x - 3, z) + height(x + 3, z)) / 2 + 0.7, z)
                        let slope = atan2(height(x + o.x * 0 + q.act(V3(3, 0, 0)).x, z + q.act(V3(3, 0, 0)).z) - height(x - q.act(V3(3, 0, 0)).x, z - q.act(V3(3, 0, 0)).z), 6)
                        b.box(center: c, size: V3(7.2, 1.5, 0.9), color: V4(0.2 + 0.1 * g, 0.5 + 0.12 * g, 0.12, 0.25), rot: q * simd_quatf(angle: slope, axis: V3(0, 0, 1)))
                    }
                    v += 3.4
                }
            }
        }
        // bushes and hedges near the field
        let pal = site.pal
        let bushCol = leaf(pal.bush.x, pal.bush.y, pal.bush.z)
        var placed = 0, tries = 0
        while placed < pal.bushCount && tries < 5000 {
            tries += 1
            let x = rng.range(-260, 260), z = rng.range(-230, 260)
            if mown(x, z) || (z < 0 && abs(x) < 150 && z > -120) { continue }
            if fbm(x / 70, z / 70, site.seed + 51) < 0.52 { continue }
            if let wl = site.waterLevel, height(x, z) < wl + 0.4 { continue }
            bush(&b, at: gy(x, z), size: rng.range(0.7, 2.2), color: bushCol, rng: &rng)
            placed += 1
        }
        if site.clubhouse && site.style != 1 && site.surroundings != 3 && site.facility == 0 && site.palette != 4 {
            // hedge behind the pits and along the access road
            var x: Float = -hl - 10
            while x < hl + 10 {
                bush(&b, at: gy(x + rng.range(-0.3, 0.3), hw + 52 + rng.range(-0.4, 0.4)), size: rng.range(1.3, 1.9), color: shade(bushCol, 0.9), rng: &rng)
                x += 1.7
            }
        }
        b.append(buildFlowers())
        return b
    }

    func buildTreeShadows() -> MeshBuilder {
        var b = MeshBuilder()
        let up = V3(0, 1, 0)
        for t in trees where abs(t.p.x) > 235 || abs(t.p.z - site.flatCenterZ) > 235 {
            let r = t.h * ([2, 5, 6].contains(site.trees) ? 0.3 : (site.trees == 4 ? 0.7 : 0.45)), n = 8
            let c = t.p + V3(r * 0.35, 0.12, -r * 0.3)
            for j in 0..<n {
                let a0 = Float(j) / Float(n) * 2 * .pi, a1 = Float(j + 1) / Float(n) * 2 * .pi
                let p0 = V3(c.x + cos(a0) * r, 0, c.z + sin(a0) * r), p1 = V3(c.x + cos(a1) * r, 0, c.z + sin(a1) * r)
                b.v(c, up, V4(0, 0, 0, 0.42))
                b.v(V3(p0.x, height(p0.x, p0.z) + 0.12, p0.z), up, V4(0, 0, 0, 0))
                b.v(V3(p1.x, height(p1.x, p1.z) + 0.12, p1.z), up, V4(0, 0, 0, 0))
            }
        }
        return b
    }

    /// Grass cards (drawn with the cut-out grass material). Long grass grows outside the mown field.
    func buildGrass() -> MeshBuilder {
        var b = MeshBuilder()
        var rng = LCG(UInt64(site.seed) + 500)
        let pilot = pilotPos
        let pal = site.pal
        let base = leaf(pal.grassBase.x, pal.grassBase.y, pal.grassBase.z), tip = leaf(pal.grassTip.x, pal.grassTip.y, pal.grassTip.z)
        let target = pal.grassCount
        var n = 0, tries = 0
        while n < target && tries < target * 12 {
            tries += 1
            let r = 6 + 130 * pow(rng.next(), 1.35), a = rng.range(0, 2 * .pi)
            let x = pilot.x + cos(a) * r, z = pilot.z + sin(a) * r
            if mown(x, z) { continue }
            let patch = fbm(x / 26, z / 26, site.seed + 77)
            if patch < (pal.grassCount < 10000 ? 0.55 : 0.3) { continue }
            if let wl = site.waterLevel, height(x, z) < wl + 0.5 { continue }
            let h = rng.range(0.25, 0.55) * (0.55 + patch)
            b.grassClump(at: gy(x, z), height: h, width: rng.range(0.55, 1.0), base: base, tip: tip, rng: &rng)
            n += 1
        }
        if site.runwayType == 0 {
            // unmown fringe along the asphalt edges
            var x: Float = -hl
            while x < hl {
                for z in [-hw - 0.75, hw + 0.75] where rng.next() < 0.55 {
                    b.grassClump(at: gy(x + rng.range(-0.3, 0.3), z + rng.range(-0.2, 0.2)), height: rng.range(0.1, 0.2), width: rng.range(0.4, 0.7), base: base, tip: tip, rng: &rng)
                }
                x += 0.6
            }
        }
        return b
    }

    /// Wild flowers scattered through the long grass (small coloured triangles, vegetation material).
    func buildFlowers() -> MeshBuilder {
        var b = MeshBuilder()
        guard site.pal.flowers else { return b }
        var rng = LCG(UInt64(site.seed) + 900)
        let pilot = pilotPos
        let cols = [leaf(0.98, 0.95, 0.9), leaf(0.98, 0.85, 0.15), leaf(0.72, 0.42, 0.85), leaf(0.95, 0.4, 0.3)]
        var n = 0, tries = 0
        while n < 2500 && tries < 40000 {
            tries += 1
            let r = 6 + 110 * pow(rng.next(), 1.5), a = rng.range(0, 2 * .pi)
            let x = pilot.x + cos(a) * r, z = pilot.z + sin(a) * r
            if mown(x, z) || fbm(x / 14, z / 14, site.seed + 91) < 0.55 { continue }
            if let wl = site.waterLevel, height(x, z) < wl + 0.5 { continue }
            b.flower(at: gy(x, z), height: rng.range(0.25, 0.5), color: cols[Int(rng.next() * 3.99)], rng: &rng)
            n += 1
        }
        return b
    }

    // MARK: Objects

    private func person(_ b: inout MeshBuilder, at p: V3, facing: Float, shirt: V4, pants: V4, holdingTx: Bool) {
        var m = MeshBuilder()
        let skin = cg(0.85, 0.65, 0.52)
        for s in [Float(-1), 1] {
            m.cylinder(from: V3(s * 0.09, 0, 0), to: V3(s * 0.085, 0.86, 0), r0: 0.065, r1: 0.085, seg: 7, color: pants)
            m.box(center: V3(s * 0.09, 0.04, -0.05), size: V3(0.1, 0.08, 0.26), color: cg(0.15, 0.13, 0.12))
            if holdingTx {
                m.cylinder(from: V3(s * 0.21, 1.4, 0), to: V3(s * 0.2, 1.14, -0.1), r0: 0.05, r1: 0.045, seg: 6, color: shirt)
                m.cylinder(from: V3(s * 0.2, 1.14, -0.1), to: V3(s * 0.08, 1.12, -0.32), r0: 0.042, r1: 0.04, seg: 6, color: skin)
            } else {
                m.cylinder(from: V3(s * 0.22, 1.4, 0), to: V3(s * 0.25, 0.88, 0.02), r0: 0.05, r1: 0.04, seg: 6, color: shirt)
            }
        }
        m.loft([superRing(y: 0.84, z: 0, w: 0.17, h: 0.11, seg: 10).map { V3($0.x, 0.84, $0.y - 0.84) },
                superRing(y: 1.2, z: 0, w: 0.19, h: 0.12, seg: 10).map { V3($0.x, 1.2, $0.y - 1.2) },
                superRing(y: 1.46, z: 0, w: 0.21, h: 0.11, seg: 10).map { V3($0.x, 1.46, $0.y - 1.46) }], color: shirt)
        m.cylinder(from: V3(0, 1.44, 0), to: V3(0, 1.54, 0), r0: 0.05, r1: 0.05, seg: 6, color: skin)
        m.ellipsoid(center: V3(0, 1.64, 0), radii: V3(0.095, 0.115, 0.105), color: skin, seg: 9, rings: 6)
        m.ellipsoid(center: V3(0, 1.7, 0.005), radii: V3(0.102, 0.07, 0.112), color: cg(0.2, 0.25, 0.5), seg: 9, rings: 4)
        m.box(center: V3(0, 1.69, -0.14), size: V3(0.15, 0.015, 0.1), color: cg(0.2, 0.25, 0.5))
        if holdingTx { m.box(center: V3(0, 1.12, -0.36), size: V3(0.19, 0.05, 0.16), color: cg(0.12, 0.12, 0.13, 0.3)) }
        b.append(m, M4.translation(p) * M4.rotation(facing, V3(0, 1, 0)))
    }

    private func car(_ b: inout MeshBuilder, at p: V3, facing: Float, paint: V4, van: Bool = false) {
        var m = MeshBuilder()
        let glass = cg(0.06, 0.08, 0.1, 1), tire = cg(0.05, 0.05, 0.05, 0.05)
        let len: Float = van ? 4.9 : 4.3, wid: Float = van ? 0.95 : 0.88
        let st: [(Float, Float, Float, Float)] = van
            ? [(-0.5, 0.86, 0.3, 0.62), (-0.46, 0.93, 0.45, 0.78), (-0.3, 0.95, 0.62, 0.95), (0.47, 0.95, 0.64, 0.97), (0.5, 0.9, 0.6, 0.95)]
            : [(-0.5, 0.8, 0.2, 0.55), (-0.46, 0.86, 0.27, 0.6), (-0.2, 0.88, 0.3, 0.63), (0.3, 0.88, 0.31, 0.64), (0.47, 0.85, 0.29, 0.64), (0.5, 0.78, 0.2, 0.58)]
        m.loft(st.map { superRing(y: $0.3, z: $0.0 * len, w: wid * $0.1 / 0.88, h: $0.2, exp: 4, seg: 14) }, color: paint)
        if !van {
            // glasshouse
            m.loft([superRing(y: 0.95, z: -0.19 * len, w: 0.74, h: 0.02, exp: 4, seg: 12), superRing(y: 1.12, z: -0.07 * len, w: 0.68, h: 0.2, exp: 4, seg: 12),
                    superRing(y: 1.13, z: 0.2 * len, w: 0.68, h: 0.2, exp: 4, seg: 12), superRing(y: 0.97, z: 0.34 * len, w: 0.72, h: 0.03, exp: 4, seg: 12)], color: glass)
            m.box(center: V3(0, 1.335, 0.06 * len), size: V3(1.3, 0.03, 0.26 * len), color: paint)
        } else {
            m.box(center: V3(0, 1.25, -0.42 * len), size: V3(1.7, 0.5, 0.06), color: glass, rot: simd_quatf(angle: -0.35, axis: V3(1, 0, 0)))
            for s in [Float(-1), 1] { m.box(center: V3(s * wid * 1.08, 1.25, -0.3 * len), size: V3(0.03, 0.42, 0.9), color: glass) }
        }
        for s in [Float(-1), 1] {
            for z in [-0.32 * len, 0.3 * len] {
                m.cylinder(from: V3(s * (wid - 0.12), 0.32, z), to: V3(s * (wid + 0.04), 0.32, z), r0: 0.32, r1: 0.32, seg: 14, color: tire)
                m.cylinder(from: V3(s * (wid + 0.04), 0.32, z), to: V3(s * (wid + 0.05), 0.32, z), r0: 0.19, r1: 0.17, seg: 10, color: cg(0.7, 0.7, 0.72, 0.6))
            }
            m.box(center: V3(s * wid * 0.7, 0.66, -0.5 * len), size: V3(0.3, 0.1, 0.04), color: cg(0.95, 0.95, 0.85, 1))
            m.box(center: V3(s * wid * 0.72, 0.7, 0.5 * len), size: V3(0.26, 0.1, 0.04), color: cg(0.7, 0.05, 0.05, 0.8))
        }
        b.append(m, M4.translation(p) * M4.rotation(facing, V3(0, 1, 0)))
    }

    private func table(_ b: inout MeshBuilder, at p: V3, facing: Float, wood: V4) {
        var m = MeshBuilder()
        m.box(center: V3(0, 0.76, 0), size: V3(1.9, 0.05, 0.8), color: wood)
        for sx in [Float(-0.8), 0.8] { for sz in [Float(-0.3), 0.3] { m.box(center: V3(sx, 0.37, sz), size: V3(0.07, 0.74, 0.07), color: shade(wood, 0.8)) } }
        for sz in [Float(-0.75), 0.75] {
            m.box(center: V3(0, 0.44, sz), size: V3(1.9, 0.045, 0.28), color: wood)
            for sx in [Float(-0.75), 0.75] { m.box(center: V3(sx, 0.21, sz), size: V3(0.06, 0.42, 0.24), color: shade(wood, 0.8)) }
        }
        b.append(m, M4.translation(p) * M4.rotation(facing, V3(0, 1, 0)))
    }

    private func building(_ b: inout MeshBuilder, at c: V3, size: V3, wall plainWall: V4, roof plainRoof: V4, facing: Float, porch: Bool) {
        var m = MeshBuilder()
        // boarded walls, a tiled roof: the shader draws both (see the kinds of surface in Structures.swift)
        let wall = V4(plainWall.x, plainWall.y, plainWall.z, 11 + min(plainWall.w, 0.9)), roof = V4(plainRoof.x, plainRoof.y, plainRoof.z, 10 + min(plainRoof.w, 0.9))
        let w = size.x / 2, d = size.z / 2, h = size.y, ridge = h + size.z * 0.28
        let trim = cg(0.92, 0.92, 0.9), glass = cg(0.2, 0.3, 0.4, 1)
        m.box(center: V3(0, 0.15, 0), size: V3(size.x + 0.2, 0.3, size.z + 0.2), color: cg(0.5, 0.5, 0.5))
        m.box(center: V3(0, h / 2 + 0.15, 0), size: V3(size.x, h, size.z), color: wall)
        let o: Float = 0.5       // roof overhang
        m.quad(V3(-w - o, h, d + o), V3(w + o, h, d + o), V3(w + o, ridge, 0), V3(-w - o, ridge, 0), roof)
        m.quad(V3(w + o, h, -d - o), V3(-w - o, h, -d - o), V3(-w - o, ridge, 0), V3(w + o, ridge, 0), roof)
        m.tri(V3(-w, h, d), V3(-w, h, -d), V3(-w, ridge - 0.15, 0), wall)
        m.tri(V3(w, h, -d), V3(w, h, d), V3(w, ridge - 0.15, 0), wall)
        // front (‑z) door and windows
        m.box(center: V3(w * 0.3, 1.2, -d - 0.02), size: V3(1.05, 2.1, 0.06), color: trim)
        m.box(center: V3(w * 0.3, 1.15, -d - 0.04), size: V3(0.9, 2.0, 0.06), color: cg(0.3, 0.2, 0.13, 0.2))
        for x in [-w * 0.55, -w * 0.1, w * 0.72] {
            m.box(center: V3(x, 1.7, -d - 0.02), size: V3(1.3, 1.1, 0.06), color: trim)
            m.box(center: V3(x, 1.7, -d - 0.04), size: V3(1.15, 0.95, 0.06), color: glass)
        }
        for z in [-d * 0.4, d * 0.4] { m.box(center: V3(-w - 0.04, 1.7, z), size: V3(0.06, 0.95, 1.1), color: glass) }
        m.box(center: V3(-w * 0.5, ridge + 0.2, d * 0.3), size: V3(0.5, 1.1, 0.5), color: cg(0.45, 0.25, 0.2))
        if porch {
            m.quad(V3(-w, h - 0.1, -d), V3(w, h - 0.1, -d), V3(w, h - 0.55, -d - 2.4), V3(-w, h - 0.55, -d - 2.4), roof)
            var x = -w + 0.2
            while x <= w - 0.1 {
                m.box(center: V3(x, (h - 0.5) / 2, -d - 2.2), size: V3(0.12, h - 0.5, 0.12), color: trim)
                x += (size.x - 0.4) / 3
            }
            m.box(center: V3(0, 0.08, -d - 1.2), size: V3(size.x, 0.16, 2.4), color: cg(0.55, 0.42, 0.3))
        }
        b.append(m, M4.translation(c) * M4.rotation(facing, V3(0, 1, 0)))
    }

    func buildScenery() -> MeshBuilder {
        var b = MeshBuilder()
        var rng = LCG(UInt64(site.seed) + 321)
        let white = cg(0.92, 0.92, 0.9, 0.1), wood = cg(0.52, 0.38, 0.24), steel = cg(0.62, 0.63, 0.65, 0.5)

        // --- flight line: fence with two rails, pilot stations, frequency board
        let fz = hw + 10
        var x: Float = -26
        while x <= 26 {
            b.box(center: gy(x, fz) + V3(0, 0.5, 0), size: V3(0.09, 1.0, 0.09), color: white)
            x += 2.6
        }
        for y in [Float(0.5), 0.92] { b.box(center: gy(0, fz) + V3(0, y, 0), size: V3(52, 0.07, 0.04), color: white) }
        for px in [Float(-12), -6, 6, 12] {
            b.box(center: gy(px, hw + 6.4) + V3(0, 0.012, 0), size: V3(1.2, 0.03, 1.2), color: cg(0.42, 0.42, 0.4))
        }
        let board = gy(-22, fz + 1.5)
        for s in [Float(-0.7), 0.7] { b.box(center: board + V3(s, 0.9, 0), size: V3(0.08, 1.8, 0.08), color: wood) }
        b.box(center: board + V3(0, 1.35, 0), size: V3(1.6, 0.9, 0.05), color: cg(0.15, 0.3, 0.2))
        for i in 0..<8 { b.box(center: board + V3(-0.6 + Float(i % 4) * 0.4, 1.5 - Float(i / 4) * 0.35, -0.03), size: V3(0.25, 0.2, 0.02), color: [cg(0.9, 0.2, 0.2), cg(0.95, 0.8, 0.2), cg(0.9, 0.9, 0.9), cg(0.2, 0.5, 0.9)][i % 4]) }

        if site.clubhouse {
        // --- clubhouse with porch, storage container, toilet, flagpole
        let club = gy(-48, hw + 34)
        let wall = site.style == 1 ? cg(0.85, 0.8, 0.7) : (site.style == 2 ? cg(0.42, 0.3, 0.2) : cg(0.7, 0.28, 0.2))
        building(&b, at: club, size: V3(11, 2.9, 6.5), wall: wall, roof: cg(0.22, 0.22, 0.25, 0.15), facing: 0, porch: true)
        let cont = gy(-62, hw + 36)
        b.box(center: cont + V3(0, 1.3, 0), size: V3(2.5, 2.6, 6.1), color: cg(0.15, 0.35, 0.5, 0.2))
        for i in 0..<12 { b.box(center: cont + V3(1.27, 1.3, -2.8 + Float(i) * 0.5), size: V3(0.04, 2.4, 0.12), color: cg(0.12, 0.3, 0.45, 0.2)) }
        let loo = gy(-40, hw + 44)
        b.box(center: loo + V3(0, 1.1, 0), size: V3(1.15, 2.2, 1.15), color: cg(0.1, 0.45, 0.6, 0.3))
        b.box(center: loo + V3(0, 2.25, 0), size: V3(1.3, 0.12, 1.3), color: cg(0.9, 0.9, 0.9, 0.3))
        let flag = gy(-38, hw + 26)
        b.cylinder(from: flag, to: flag + V3(0, 7, 0), r0: 0.05, r1: 0.035, seg: 8, color: steel)
        b.blob(center: flag + V3(0, 7.05, 0), radii: V3(0.07, 0.07, 0.07), color: cg(0.85, 0.7, 0.2, 0.8), seg: 8, rings: 4, seed: 1, lump: 0)

        }
        // --- pits: shade canopy, tables, people
        let s0 = gy(18, hw + 16)
        for (dx, dz) in [(Float(-3.2), Float(-2.2)), (3.2, -2.2), (3.2, 2.2), (-3.2, 2.2)] {
            b.cylinder(from: s0 + V3(dx, 0, dz), to: s0 + V3(dx, 2.3, dz), r0: 0.04, r1: 0.04, seg: 6, color: steel)
        }
        let canopy = cg(0.12, 0.38, 0.7, 0.15)
        let peak = s0 + V3(0, 3.1, 0)
        let corners = [V3(-3.5, 2.3, -2.5), V3(3.5, 2.3, -2.5), V3(3.5, 2.3, 2.5), V3(-3.5, 2.3, 2.5)].map { s0 + $0 }
        for i in 0..<4 { b.tri(corners[i], corners[(i + 1) % 4], peak, i % 2 == 0 ? canopy : shade(canopy, 0.85)) }
        table(&b, at: s0 + V3(-1.3, 0, 0), facing: 0, wood: wood)
        table(&b, at: s0 + V3(1.5, 0, 0.2), facing: 0.1, wood: wood)
        table(&b, at: gy(4, hw + 14), facing: 1.57, wood: wood)
        table(&b, at: gy(-9, hw + 15), facing: 1.4, wood: wood)
        // field boxes and a fuel can on the tables
        b.box(center: s0 + V3(-1.5, 0.9, 0.05), size: V3(0.5, 0.24, 0.3), color: cg(0.75, 0.1, 0.1, 0.4))
        b.box(center: s0 + V3(1.2, 0.86, 0.2), size: V3(0.3, 0.16, 0.2), color: cg(0.9, 0.75, 0.1, 0.4))
        person(&b, at: gy(8, hw + 6.6), facing: 0.15, shirt: cg(0.75, 0.15, 0.12), pants: cg(0.2, 0.25, 0.4), holdingTx: true)
        person(&b, at: gy(10.2, hw + 8), facing: -0.3, shirt: cg(0.9, 0.9, 0.85), pants: cg(0.35, 0.3, 0.22), holdingTx: false)
        person(&b, at: s0 + V3(-2.6, 0, -1.4), facing: 2.4, shirt: cg(0.2, 0.45, 0.25), pants: cg(0.15, 0.15, 0.18), holdingTx: false)
        person(&b, at: gy(-12.5, hw + 12), facing: 0.6, shirt: cg(0.95, 0.75, 0.15), pants: cg(0.3, 0.32, 0.4), holdingTx: false)
        // bins
        for bx in [Float(-4), 24] {
            b.cylinder(from: gy(bx, hw + 20), to: gy(bx, hw + 20) + V3(0, 0.85, 0), r0: 0.27, r1: 0.3, seg: 10, color: cg(0.2, 0.35, 0.22, 0.2))
        }

        if site.clubhouse {
        // --- gravel car park and access road, vehicles
        let park = gy(-27, hw + 40)
        let gravel = site.style == 1 ? cg(0.62, 0.55, 0.45) : cg(0.5, 0.48, 0.44)
        b.box(center: park + V3(0, 0.02, 0), size: V3(30, 0.05, 11), color: gravel)
        b.box(center: gy(-10, hw + 49) + V3(0, 0.02, 0), size: V3(5, 0.05, 9), color: gravel)
        let paints = [cg(0.6, 0.06, 0.06, 0.9), cg(0.82, 0.83, 0.85, 0.9), cg(0.06, 0.16, 0.38, 0.9), cg(0.1, 0.1, 0.11, 0.9), cg(0.5, 0.52, 0.5, 0.9)]
        for i in 0..<5 {
            car(&b, at: gy(-36 + Float(i) * 3.3 + (i > 2 ? 2.5 : 0), hw + 39 + rng.range(-0.4, 0.4)), facing: rng.range(-0.06, 0.06), paint: paints[i], van: i == 3)
        }
        // trailer with a model on it would be nice; a simple box trailer for now
        let tr = gy(-17, hw + 43)
        b.box(center: tr + V3(0, 0.95, 0), size: V3(1.7, 1.3, 3.2), color: cg(0.85, 0.85, 0.82, 0.3))
        for s in [Float(-0.9), 0.9] { b.cylinder(from: tr + V3(s - 0.08, 0.3, 0.3), to: tr + V3(s + 0.08, 0.3, 0.3), r0: 0.3, r1: 0.3, seg: 10, color: cg(0.05, 0.05, 0.05)) }
        b.box(center: tr + V3(0, 0.45, -2.1), size: V3(0.08, 0.08, 1.2), color: steel)

        }
        // --- runway edge cones, windsock pole, wind tee
        x = -hl
        while x <= hl + 0.1 {
            for z in [-hw - 1.2, hw + 1.2] {
                let p = gy(x, z)
                b.box(center: p + V3(0, 0.015, 0), size: V3(0.36, 0.03, 0.36), color: cg(0.9, 0.35, 0.05, 0.2))
                b.cylinder(from: p, to: p + V3(0, 0.3, 0), r0: 0.14, r1: 0.075, seg: 10, color: cg(0.95, 0.4, 0.05, 0.3))
                b.cylinder(from: p + V3(0, 0.3, 0), to: p + V3(0, 0.38, 0), r0: 0.075, r1: 0.055, seg: 10, color: cg(0.95, 0.95, 0.95, 0.3))
                b.cylinder(from: p + V3(0, 0.38, 0), to: p + V3(0, 0.48, 0), r0: 0.055, r1: 0.03, seg: 10, color: cg(0.95, 0.4, 0.05, 0.3))
            }
            x += site.runwayLen / 8
        }
        let wp = windsockBase
        b.cylinder(from: wp, to: wp + V3(0, 5, 0), r0: 0.06, r1: 0.04, seg: 8, color: white)
        b.box(center: wp + V3(0, 0.06, 0), size: V3(0.5, 0.12, 0.5), color: cg(0.55, 0.55, 0.55))

        // --- wider surroundings
        if site.style != 2 && site.surroundings != 3 {
            // power line along the access road
            var px: Float = -260
            while px <= 260 {
                let p = gy(px, hw + 62)
                b.cylinder(from: p - V3(0, 0.3, 0), to: p + V3(0, 8, 0), r0: 0.13, r1: 0.09, seg: 6, color: cg(0.33, 0.25, 0.18))
                b.box(center: p + V3(0, 7.5, 0), size: V3(0.1, 0.1, 2.0), color: cg(0.33, 0.25, 0.18))
                if px < 260 {
                    let q = gy(px + 65, hw + 62)
                    for dz in [Float(-0.9), 0, 0.9] {
                        // sagging wire in four straight pieces
                        for k in 0..<4 {
                            let t0 = Float(k) / 4, t1 = Float(k + 1) / 4
                            func w(_ t: Float) -> V3 { p + (q - p) * t + V3(0, 7.55 - 1.3 * 4 * t * (1 - t), dz) }
                            b.cylinder(from: w(t0), to: w(t1), r0: 0.012, r1: 0.012, seg: 3, color: cg(0.1, 0.1, 0.1))
                        }
                    }
                }
                px += 65
            }
        }
        // field fence on the far side of the runway (post and wire)
        var fx: Float = site.waterLevel == nil && site.surroundings != 3 && site.facility == 0 ? -hl - 60 : 1e9
        let farZ = -hw - 95
        while fx <= hl + 60 {
            let p = gy(fx, farZ)
            b.cylinder(from: p - V3(0, 0.2, 0), to: p + V3(0, 1.15, 0), r0: 0.05, r1: 0.045, seg: 5, color: cg(0.4, 0.32, 0.24))
            if fx < hl + 60 {
                let q = gy(fx + 4, farZ)
                for y in [Float(0.45), 0.8, 1.08] { b.cylinder(from: p + V3(0, y, 0), to: q + V3(0, y, 0), r0: 0.008, r1: 0.008, seg: 3, color: cg(0.45, 0.45, 0.45)) }
            }
            fx += 4
        }
        if site.facility == 1 {
            // airport: apron, taxiway, hangars with arched roofs, control tower, fuel bowser
            let tarmac = cg(0.2, 0.2, 0.22, 0.1)
            b.box(center: gy(120, hw + 62) + V3(0, 0.025, 0), size: V3(170, 0.05, 56), color: tarmac)
            b.box(center: gy(120, hw + 18) + V3(0, 0.025, 0), size: V3(14, 0.05, 34), color: tarmac)
            for (i, hx) in [Float(62), 118, 174].enumerated() {
                let c = gy(hx, hw + 106)
                let wallCol = [cg(0.72, 0.74, 0.76, 0.3), cg(0.62, 0.68, 0.72, 0.3), cg(0.75, 0.72, 0.66, 0.3)][i]
                var rings: [[V3]] = []
                for z in [Float(-14), 14] {
                    rings.append((0...10).map { k in
                        let a = Float(k) / 10 * .pi
                        return c + V3(-cos(a) * 20, 5 + sin(a) * 6.5, z)
                    } + [c + V3(20, 0, z), c + V3(-20, 0, z)])
                }
                b.loft(rings, color: wallCol)
                b.box(center: c + V3(0, 3.6, -14.05), size: V3(30, 7.2, 0.2), color: cg(0.35, 0.37, 0.4, 0.4))       // doors
            }
            let tw = gy(18, hw + 96)
            b.box(center: tw + V3(0, 9, 0), size: V3(6, 18, 6), color: cg(0.82, 0.82, 0.8))
            b.box(center: tw + V3(0, 19.6, 0), size: V3(9, 3.2, 9), color: cg(0.12, 0.2, 0.26, 1))
            b.box(center: tw + V3(0, 21.4, 0), size: V3(10, 0.5, 10), color: cg(0.85, 0.85, 0.85))
            b.cylinder(from: tw + V3(0, 21.6, 0), to: tw + V3(0, 26, 0), r0: 0.08, r1: 0.04, seg: 6, color: steel)
            car(&b, at: gy(84, hw + 70), facing: 1.57, paint: cg(0.9, 0.75, 0.1, 0.8), van: true)
        }
        let farmOK = site.waterLevel.map { height(210, -260) > $0 + 1.5 } ?? true
        switch site.surroundings {
        case 3: break
        case 0 where !farmOK: break
        case 0:
            // farm: barn, silo, shed; hay bales in the fields
            let farm = gy(210, -260)
            building(&b, at: farm, size: V3(18, 5.5, 10), wall: cg(0.55, 0.14, 0.1), roof: cg(0.3, 0.3, 0.33, 0.2), facing: 0.5, porch: false)
            building(&b, at: gy(236, -246), size: V3(9, 3, 7), wall: cg(0.82, 0.8, 0.74), roof: cg(0.42, 0.2, 0.16), facing: 2.0, porch: false)
            let silo = gy(196, -272)
            b.cylinder(from: silo, to: silo + V3(0, 11, 0), r0: 2.2, r1: 2.2, seg: 16, color: cg(0.72, 0.74, 0.76, 0.45))
            b.cylinder(from: silo + V3(0, 11, 0), to: silo + V3(0, 12.6, 0), r0: 2.25, r1: 0.2, seg: 16, color: cg(0.6, 0.62, 0.65, 0.45))
            for _ in 0..<22 {
                let bx = rng.range(-320, 320), bz = rng.range(-330, -110)
                if abs(bx) < 60 && bz > -140 { continue }
                if let wl = site.waterLevel, height(bx, bz) < wl + 1 { continue }
                let p = gy(bx, bz), a = rng.range(0, 3.14)
                let ax = V3(cos(a), 0, sin(a)) * 0.6
                b.cylinder(from: p + V3(0, 0.62, 0) - ax, to: p + V3(0, 0.62, 0) + ax, r0: 0.62, r1: 0.62, seg: 12, color: cg(0.78, 0.66, 0.36))
            }
        case 1:
            // desert: camper, water tank on a stand, scattered rocks
            let rv = gy(-64, hw + 44)
            b.loft([superRing(y: 1.6, z: -3.4, w: 1.1, h: 1.0, exp: 5, seg: 14), superRing(y: 1.65, z: -3.0, w: 1.2, h: 1.15, exp: 5, seg: 14),
                    superRing(y: 1.65, z: 3.3, w: 1.2, h: 1.15, exp: 5, seg: 14)].map { $0.map { $0 + rv + V3(6, 0, 4) } }, color: cg(0.9, 0.9, 0.86, 0.5))
            let tank = gy(60, hw + 40)
            for (dx, dz) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] { b.cylinder(from: tank + V3(dx, 0, dz), to: tank + V3(dx * 0.8, 4, dz * 0.8), r0: 0.07, r1: 0.07, seg: 5, color: steel) }
            b.cylinder(from: tank + V3(0, 4, 0), to: tank + V3(0, 6, 0), r0: 1.3, r1: 1.3, seg: 14, color: cg(0.6, 0.62, 0.6, 0.4))
            for _ in 0..<160 {
                let bx = rng.range(-300, 300), bz = rng.range(-300, 300)
                if mown(bx, bz) && abs(bz) < hw + 3 { continue }
                let s = rng.range(0.15, 0.9)
                b.blob(center: gy(bx, bz) + V3(0, s * 0.25, 0), radii: V3(s, s * 0.55, s * 0.8), color: cg(0.52 + rng.next() * 0.1, 0.42, 0.33), seg: 6, rings: 4, seed: Int32(bx * 7 + bz), lump: 0.35)
            }
        default:
            // alpine: timber hut is the clubhouse; summit cross, boulders, trail sign
            let cross = gy(70, -34)
            b.box(center: cross + V3(0, 2.2, 0), size: V3(0.18, 4.4, 0.18), color: cg(0.35, 0.26, 0.18))
            b.box(center: cross + V3(0, 3.3, 0), size: V3(1.8, 0.18, 0.18), color: cg(0.35, 0.26, 0.18))
            let sign = gy(-30, hw + 20)
            b.box(center: sign + V3(0, 1, 0), size: V3(0.08, 2, 0.08), color: wood)
            for (i, a) in [Float(0.3), -0.5, 1.2].enumerated() {
                b.box(center: sign + V3(0.3 * cos(a), 1.8 - Float(i) * 0.22, 0.3 * sin(a)), size: V3(0.7, 0.14, 0.03), color: cg(0.95, 0.85, 0.2), rot: simd_quatf(angle: -a, axis: V3(0, 1, 0)))
            }
            for _ in 0..<140 {
                let bx = rng.range(-320, 320), bz = rng.range(-340, 200)
                if mown(bx, bz) { continue }
                let s = rng.range(0.2, 1.6)
                b.blob(center: gy(bx, bz) + V3(0, s * 0.2, 0), radii: V3(s, s * 0.6, s * 0.85), color: cg(0.5, 0.5, 0.5), seg: 7, rings: 4, seed: Int32(bx * 5 + bz), lump: 0.4)
            }
        }
        return b
    }
}
