import simd
import Foundation

typealias V3 = SIMD3<Float>
typealias V4 = SIMD4<Float>
typealias M4 = simd_float4x4

let gravity: Float = 9.81
let rho: Float = 1.225
let deg: Float = .pi / 180

@inline(__always) func clampf(_ x: Float, _ a: Float, _ b: Float) -> Float { min(max(x, a), b) }
@inline(__always) func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = clampf((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
}
func rgb(_ r: Float, _ g: Float, _ b: Float) -> V4 { V4(r, g, b, 1) }
func mix(_ a: V4, _ b: V4, _ t: Float) -> V4 { a + (b - a) * t }

extension M4 {
    static let identity = matrix_identity_float4x4
    static func translation(_ t: V3) -> M4 {
        var m = matrix_identity_float4x4
        m.columns.3 = V4(t.x, t.y, t.z, 1)
        return m
    }
    static func rotation(_ angle: Float, _ axis: V3) -> M4 { M4(simd_quatf(angle: angle, axis: axis)) }
    /// Right-handed perspective, Metal clip space. Pass near/far swapped for reverse-Z.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> M4 {
        let y = 1 / tan(fovY * 0.5), x = y / aspect, z = far / (near - far)
        return M4(columns: (V4(x, 0, 0, 0), V4(0, y, 0, 0), V4(0, 0, z, -1), V4(0, 0, z * near, 0)))
    }
    static func ortho(halfSize s: Float, near n: Float, far f: Float) -> M4 {
        M4(columns: (V4(1 / s, 0, 0, 0), V4(0, 1 / s, 0, 0), V4(0, 0, 1 / (n - f), 0), V4(0, 0, n / (n - f), 1)))
    }
    static func lookAt(eye: V3, target: V3, up: V3) -> M4 {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return M4(columns: (V4(s.x, u.x, -f.x, 0), V4(s.y, u.y, -f.y, 0), V4(s.z, u.z, -f.z, 0),
                            V4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
    }
}

struct LCG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next() -> Float {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float((s >> 40) & 0xFFFFFF) / Float(0x1000000)
    }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * next() }
}

func hash2(_ x: Int32, _ y: Int32, _ s: Int32) -> Float {
    var h = UInt32(bitPattern: x &* 374761393 &+ y &* 668265263 &+ s &* 362437)
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
}
func vnoise(_ x: Float, _ y: Float, _ s: Int32) -> Float {
    let fx = floor(x), fy = floor(y)
    let ix = Int32(fx), iy = Int32(fy)
    var tx = x - fx, ty = y - fy
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    let a = hash2(ix, iy, s), b = hash2(ix + 1, iy, s), c = hash2(ix, iy + 1, s), d = hash2(ix + 1, iy + 1, s)
    return lerp(lerp(a, b, tx), lerp(c, d, tx), ty)
}
/// Fractal noise, roughly 0...1 with mean 0.5
func fbm(_ x: Float, _ y: Float, _ s: Int32, _ oct: Int = 5) -> Float {
    var a: Float = 0.5, sum: Float = 0, norm: Float = 0, px = x, py = y
    for i in 0..<oct {
        sum += a * vnoise(px, py, s &+ Int32(i) &* 17)
        norm += a; a *= 0.5; px *= 2.03; py *= 2.03
    }
    return sum / norm
}
