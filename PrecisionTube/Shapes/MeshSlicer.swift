import Foundation
import ModelIO
import simd

enum MeshAxis: String, CaseIterable, Identifiable {
    case y = "Y up", z = "Z up", x = "X up"
    var id: String { rawValue }
    var index: Int { self == .x ? 0 : (self == .y ? 1 : 2) }
}

enum MeshSlicerError: LocalizedError {
    case unreadable, noTriangles
    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file couldn't be opened as a 3D model. Try USDZ, OBJ, STL or PLY."
        case .noTriangles: return "The model has no surfaces to measure."
        }
    }
}

/// Reads a 3D model and turns it into a round profile: it slices the model across the chosen
/// "up" axis and measures the outline (convex hull) of every slice. Works best for one-piece
/// rounded shapes; arms, legs and ears are best made as separate pieces.
enum MeshSlicer {
    /// All triangles of the model, three corners each, in model space.
    static func triangles(from url: URL) throws -> [SIMD3<Float>] {
        let ext = url.pathExtension.lowercased()
        guard MDLAsset.canImportFileExtension(ext) else { throw MeshSlicerError.unreadable }
        let asset = MDLAsset(url: url)
        var out: [SIMD3<Float>] = []
        let meshes = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? []
        for mesh in meshes {
            let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { continue }
            let start = positions.dataStart
            let stride = positions.stride
            let vertexCount = mesh.vertexCount
            func vertex(_ i: Int) -> SIMD3<Float>? {
                guard i >= 0, i < vertexCount else { return nil }
                let p = (start + i * stride).assumingMemoryBound(to: Float.self)
                let v = transform * SIMD4<Float>(p[0], p[1], p[2], 1)
                return SIMD3(v.x, v.y, v.z)
            }
            guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { continue }
            for sub in submeshes {
                let map = sub.indexBuffer.map()
                let bytes = map.bytes
                func index(_ i: Int) -> Int {
                    switch sub.indexType {
                    case .uInt8: return Int(bytes.load(fromByteOffset: i, as: UInt8.self))
                    case .uInt16: return Int(bytes.load(fromByteOffset: i * 2, as: UInt16.self))
                    default: return Int(bytes.load(fromByteOffset: i * 4, as: UInt32.self))
                    }
                }
                let n = sub.indexCount
                switch sub.geometryType {
                case .triangles:
                    var i = 0
                    while i + 2 < n {
                        if let a = vertex(index(i)), let b = vertex(index(i + 1)), let c = vertex(index(i + 2)) {
                            out.append(a); out.append(b); out.append(c)
                        }
                        i += 3
                    }
                case .quads:
                    var i = 0
                    while i + 3 < n {
                        if let a = vertex(index(i)), let b = vertex(index(i + 1)), let c = vertex(index(i + 2)), let d = vertex(index(i + 3)) {
                            out.append(contentsOf: [a, b, c, a, c, d])
                        }
                        i += 4
                    }
                default:
                    continue
                }
            }
        }
        if out.isEmpty { throw MeshSlicerError.noTriangles }
        return out
    }

    /// Profile with height 1 (radius in the same units), bottom pole to top pole.
    static func normalizedProfile(triangles: [SIMD3<Float>], axis: MeshAxis, slices: Int = 160) -> Profile? {
        let up = axis.index
        let u = (up + 1) % 3, v = (up + 2) % 3
        var minH = Float.greatestFiniteMagnitude, maxH = -Float.greatestFiniteMagnitude
        for p in triangles { minH = min(minH, p[up]); maxH = max(maxH, p[up]) }
        let H = maxH - minH
        guard H > 0 else { return nil }
        let dz = H / Float(slices)
        var buckets = Array(repeating: [SIMD2<Double>](), count: slices)

        var t = 0
        while t + 2 < triangles.count {
            let tri = [triangles[t], triangles[t + 1], triangles[t + 2]]
            t += 3
            let hs = tri.map { $0[up] }
            let lo = hs.min()!, hi = hs.max()!
            guard hi > lo else { continue }
            var k = max(0, Int(((lo - minH) / dz - 0.5).rounded(.up)))
            let kEnd = min(slices - 1, Int(((hi - minH) / dz - 0.5).rounded(.down)))
            while k <= kEnd {
                let z = minH + (Float(k) + 0.5) * dz
                for (i, j) in [(0, 1), (1, 2), (2, 0)] {
                    let h1 = hs[i], h2 = hs[j]
                    if (h1 - z) * (h2 - z) < 0 {
                        let f = (z - h1) / (h2 - h1)
                        let p = tri[i] + (tri[j] - tri[i]) * f
                        buckets[k].append(SIMD2(Double(p[u]), Double(p[v])))
                    }
                }
                k += 1
            }
        }

        var points: [SIMD2<Double>] = [SIMD2(0, 0)]
        for k in 0..<slices {
            let perimeter = hullPerimeter(buckets[k])
            let r = perimeter / (2 * Double.pi) / Double(H)
            let z = (Double(k) + 0.5) / Double(slices)
            if r > 0 { points.append(SIMD2(r, z)) }
        }
        points.append(SIMD2(0, 1))
        return points.count > 3 ? Profile(points: points) : nil
    }

    private static func hullPerimeter(_ pts: [SIMD2<Double>]) -> Double {
        guard pts.count >= 3 else { return 0 }
        let sorted = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Double>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        guard hull.count >= 2 else { return 0 }
        var total = 0.0
        for i in 0..<hull.count { total += simd_distance(hull[i], hull[(i + 1) % hull.count]) }
        return total
    }
}
