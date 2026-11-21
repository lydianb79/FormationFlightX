import simd
import Metal

/// CPU-side triangle soup: 10 floats per vertex (position, normal, rgba).
struct MeshBuilder {
    var data: [Float] = []
    var count: Int { data.count / 10 }

    mutating func v(_ p: V3, _ n: V3, _ c: V4) {
        data.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, c.x, c.y, c.z, c.w])
    }
    mutating func tri(_ a: V3, _ b: V3, _ c: V3, _ col: V4) {
        var n = cross(b - a, c - a)
        let l = length(n)
        n = l > 1e-12 ? n / l : V3(0, 1, 0)
        v(a, n, col); v(b, n, col); v(c, n, col)
    }
    mutating func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ col: V4) { tri(a, b, c, col); tri(a, c, d, col) }

    mutating func box(center: V3, size: V3, color: V4, rot: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) {
        let h = size * 0.5
        func P(_ x: Float, _ y: Float, _ z: Float) -> V3 { center + rot.act(V3(x * h.x, y * h.y, z * h.z)) }
        quad(P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1), color)
        quad(P(1, -1, -1), P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), color)
        quad(P(1, -1, 1), P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), color)
        quad(P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1), color)
        quad(P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), P(-1, 1, -1), color)
        quad(P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1), color)
    }

    /// Skin a sequence of rings (all with the same point count) with smooth normals.
    mutating func loft(_ rings: [[V3]], color: V4, ringColors: [V4]? = nil, caps: Bool = true) {
        let m = rings[0].count
        let cents = rings.map { $0.reduce(V3.zero, +) / Float(m) }
        func nrm(_ i: Int, _ j: Int) -> V3 {
            let d = rings[i][j] - cents[i]
            let l = length(d)
            if l > 1e-5 { return d / l }
            let o = i == 0 ? cents[0] - cents[1] : cents[i] - cents[i - 1]
            let lo = length(o)
            return lo > 1e-6 ? o / lo : V3(0, 1, 0)
        }
        for i in 0..<(rings.count - 1) {
            for j in 0..<m {
                let k = (j + 1) % m
                let c0 = ringColors?[j] ?? color, c1 = ringColors?[k] ?? color
                let a = rings[i][j], b = rings[i][k], c = rings[i + 1][k], d = rings[i + 1][j]
                v(a, nrm(i, j), c0); v(b, nrm(i, k), c1); v(c, nrm(i + 1, k), c1)
                v(a, nrm(i, j), c0); v(c, nrm(i + 1, k), c1); v(d, nrm(i + 1, j), c0)
            }
        }
        guard caps else { return }
        for i in [0, rings.count - 1] {
            let o = i == 0 ? cents[0] - cents[1] : cents[i] - cents[i - 1]
            let lo = length(o)
            let n = lo > 1e-6 ? o / lo : V3(0, 1, 0)
            for j in 0..<m {
                let k = (j + 1) % m
                v(cents[i], n, ringColors?[j] ?? color); v(rings[i][j], n, ringColors?[j] ?? color); v(rings[i][k], n, ringColors?[k] ?? color)
            }
        }
    }

    /// Fuselage-like body along Z from elliptical stations.
    mutating func body(_ st: [(z: Float, w: Float, h: Float, y: Float)], seg: Int = 12, color: V4, x: Float = 0) {
        let rings = st.map { s in
            (0..<seg).map { j -> V3 in
                let a = Float(j) / Float(seg) * 2 * .pi
                return V3(x + cos(a) * s.w, s.y + sin(a) * s.h, s.z)
            }
        }
        loft(rings, color: color)
    }

    mutating func cylinder(from a: V3, to b: V3, r0: Float, r1: Float, seg: Int = 10, color: V4) {
        let ax = normalize(b - a)
        let ref: V3 = abs(ax.y) < 0.9 ? V3(0, 1, 0) : V3(1, 0, 0)
        let u = normalize(cross(ax, ref)), w = cross(ax, u)
        func ring(_ c: V3, _ r: Float) -> [V3] {
            (0..<seg).map { j in
                let t = Float(j) / Float(seg) * 2 * .pi
                return c + (u * cos(t) + w * sin(t)) * r
            }
        }
        loft([ring(a, r0), ring(b, r1)], color: color)
    }

    mutating func ellipsoid(center: V3, radii: V3, color: V4, seg: Int = 10, rings n: Int = 6) {
        var rs: [[V3]] = []
        for i in 0...n {
            let phi = -Float.pi / 2 + Float.pi * Float(i) / Float(n)
            rs.append((0..<seg).map { j in
                let t = Float(j) / Float(seg) * 2 * .pi
                return center + V3(cos(t) * cos(phi) * radii.x, sin(phi) * radii.y, sin(t) * cos(phi) * radii.z)
            })
        }
        loft(rs, color: color, caps: false)
    }

    /// Wing panel between two leading-edge points; chord runs toward +Z.
    mutating func wing(root: V3, tip: V3, rootChord: Float, tipChord: Float, thick: Float, up: V3, top: V4, bottom: V4) {
        let prof: [(Float, Float)] = [(0, 0), (0.08, 0.75), (0.3, 1), (0.65, 0.7), (1, 0.08), (1, -0.08), (0.65, -0.45), (0.3, -0.7), (0.08, -0.55)]
        func ring(_ le: V3, _ c: Float) -> [V3] { prof.map { le + V3(0, 0, $0.0 * c) + up * ($0.1 * thick * c * 0.5) } }
        let cols = prof.map { $0.1 >= 0 ? top : bottom }
        loft([ring(root, rootChord), ring(tip, tipChord)], color: top, ringColors: cols)
    }

    mutating func append(_ o: MeshBuilder, _ m: M4 = .identity) {
        data.reserveCapacity(data.count + o.data.count)
        var i = 0
        while i < o.data.count {
            let p = m * V4(o.data[i], o.data[i + 1], o.data[i + 2], 1)
            let n = m * V4(o.data[i + 3], o.data[i + 4], o.data[i + 5], 0)
            data.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, o.data[i + 6], o.data[i + 7], o.data[i + 8], o.data[i + 9]])
            i += 10
        }
    }
    mutating func translate(_ d: V3) {
        var i = 0
        while i < data.count { data[i] += d.x; data[i + 1] += d.y; data[i + 2] += d.z; i += 10 }
    }
}

final class GPUMesh {
    let buffer: MTLBuffer
    let count: Int
    init?(_ device: MTLDevice, _ b: MeshBuilder) {
        guard b.count > 0, let buf = device.makeBuffer(bytes: b.data, length: b.data.count * 4, options: .storageModeShared) else { return nil }
        buffer = buf; count = b.count
    }
}

/// A piece of a large static mesh with its bounding sphere, so pieces outside the view can be skipped.
struct MeshChunk { var mesh: MeshBuilder; var center: V3; var radius: Float }

/// Split a triangle soup into square cells on the ground plane.
func chunked(_ b: MeshBuilder, cell: Float) -> [MeshChunk] {
    var groups: [SIMD2<Int32>: MeshBuilder] = [:]
    var i = 0
    while i + 30 <= b.data.count {
        let key = SIMD2<Int32>(Int32(floor(b.data[i] / cell)), Int32(floor(b.data[i + 2] / cell)))
        groups[key, default: MeshBuilder()].data.append(contentsOf: b.data[i..<(i + 30)])
        i += 30
    }
    return groups.values.map { m in
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        var j = 0
        while j < m.data.count {
            let p = V3(m.data[j], m.data[j + 1], m.data[j + 2])
            lo = simd_min(lo, p); hi = simd_max(hi, p); j += 10
        }
        return MeshChunk(mesh: m, center: (lo + hi) / 2, radius: length(hi - lo) / 2)
    }
}
