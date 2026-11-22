import Foundation

/// A 4×4 transform (column-major), so the shape code runs without Apple's simd/SceneKit
/// (it's also run on Linux by tools/pattern-render).
struct Mat4: Equatable {
    var m: [Float]   // 16 values, column-major

    static let identity = Mat4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    static func translation(_ x: Float, _ y: Float, _ z: Float) -> Mat4 {
        var t = identity
        t.m[12] = x; t.m[13] = y; t.m[14] = z
        return t
    }

    static func scale(_ x: Float, _ y: Float, _ z: Float) -> Mat4 {
        Mat4(m: [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1])
    }

    /// Right-handed rotation by `angle` radians about a unit axis.
    static func rotation(_ angle: Float, axis: SIMD3<Float>) -> Mat4 {
        let c = cos(angle), s = sin(angle), t = 1 - c
        let x = axis.x, y = axis.y, z = axis.z
        return Mat4(m: [
            t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0,
            t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
            t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0,
            0, 0, 0, 1,
        ])
    }

    static func * (a: Mat4, b: Mat4) -> Mat4 {
        var r = [Float](repeating: 0, count: 16)
        for col in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a.m[k * 4 + row] * b.m[col * 4 + k] }
                r[col * 4 + row] = sum
            }
        }
        return Mat4(m: r)
    }

    func point(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
              m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
              m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14])
    }

    func direction(_ d: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(m[0] * d.x + m[4] * d.y + m[8] * d.z,
              m[1] * d.x + m[5] * d.y + m[9] * d.z,
              m[2] * d.x + m[6] * d.y + m[10] * d.z)
    }
}

/// The triangles the 3D preview draws: one patch per stitch, each round in its yarn colour.
struct StitchMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// Palette index of each vertex's yarn colour.
    var colorIndex: [Int] = []
    /// Brightness of each vertex (alternating rounds and stitches, so stitches show).
    var shade: [Float] = []
    var indices: [UInt32] = []

    init() {}

    init(_ model: StitchModel) {
        for (i, band) in model.bands.enumerated() {
            let n = max(3, band.stitches)
            let offset = i.isMultiple(of: 2) ? 0.0 : 0.5           // spiral look
            let dr = band.top.x - band.bottom.x, dz = band.top.y - band.bottom.y
            let len = max(1e-6, (dr * dr + dz * dz).squareRoot())
            let pn = SIMD2(dz / len, -dr / len)                     // outward profile normal
            let roundShade: Float = i.isMultiple(of: 2) ? 1.0 : 0.86
            let color = i < model.bandColors.count ? model.bandColors[i] : 0
            for j in 0..<n {
                let a0 = 2 * Double.pi * (Double(j) + offset) / Double(n)
                let a1 = 2 * Double.pi * (Double(j) + 1 + offset) / Double(n)
                let am = (a0 + a1) / 2
                let start = UInt32(positions.count)
                for (rad, z, ang) in [(band.bottom.x, band.bottom.y, a0), (band.bottom.x, band.bottom.y, a1),
                                      (band.top.x, band.top.y, a1), (band.top.x, band.top.y, a0)] {
                    positions.append(SIMD3(Float(rad * cos(ang)), Float(z), Float(rad * sin(ang))))
                }
                let normal = SIMD3(Float(pn.x * cos(am)), Float(pn.y), Float(pn.x * sin(am)))
                let stitchShade: Float = j.isMultiple(of: 2) ? 1.0 : 0.92
                for _ in 0..<4 {
                    normals.append(normal)
                    colorIndex.append(color)
                    shade.append(roundShade * stitchShade)
                }
                indices.append(contentsOf: [start, start + 2, start + 1, start, start + 3, start + 2])
            }
        }
    }

    /// A small ball (safety eye); colour index -1 means black.
    static func sphere(center: SIMD3<Float>, radius: Float, colorIndex: Int = -1, segments: Int = 12) -> StitchMesh {
        var mesh = StitchMesh()
        for i in 0...segments {
            let v = Float.pi * Float(i) / Float(segments)
            for j in 0...segments {
                let u = 2 * Float.pi * Float(j) / Float(segments)
                let n = SIMD3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
                mesh.positions.append(center + n * radius)
                mesh.normals.append(n)
                mesh.colorIndex.append(colorIndex)
                mesh.shade.append(1)
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(segments) {
            for j in 0..<UInt32(segments) {
                let a = i * row + j, b = a + 1, c = a + row, d = c + 1
                mesh.indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return mesh
    }

    func transformed(by t: Mat4) -> StitchMesh {
        var out = self
        out.positions = positions.map { t.point($0) }
        out.normals = normals.map { n in
            let d = t.direction(n)
            let l = max(1e-6, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
            return d / l
        }
        return out
    }
}
