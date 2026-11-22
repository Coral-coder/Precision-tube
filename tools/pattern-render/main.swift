import Foundation

// Renders a pattern file with the app's own code (PatternText, ShapeMath, Assembly,
// StitchMesh) and writes the triangles as JSON for render.py.
// Usage: pattern-render <pattern.txt> <out.json> [stitchesPer10cm roundsPer10cm]

let args = CommandLine.arguments
guard args.count >= 3, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    FileHandle.standardError.write("usage: pattern-render pattern.txt out.json\n".data(using: .utf8)!)
    exit(2)
}
var gauge = Gauge()
if args.count >= 5, let s = Double(args[3]), let r = Double(args[4]) {
    gauge.stitchesPer10cm = s; gauge.roundsPer10cm = r
}
let lines = text.split(separator: "\n").map(String.init)
let pieces = PatternToShape.pieces(from: lines)
for p in pieces {
    print("piece \(p.id) \"\(p.name)\" x\(p.repeatCount) topDown=\(p.topDown)")
    print("  counts  \(p.counts)")
    print("  heights \(p.heights)")
    print("  colors  \(p.colors)")
    if !p.collars.isEmpty { print("  collars \(p.collars)") }
    if let a = p.attach { print("  attach to piece \(a.target) rounds \(a.rounds)") }
    if let e = p.eyes { print("  eyes rounds \(e.rounds), \(e.apart) st apart") }
}
let assembly = Assembly.build(pieces: pieces, gauge: gauge)
print("parts \(assembly.parts.count), colours \(assembly.colorCount), main topDown \(assembly.mainTopDown)")

var verts: [[Float]] = []
var tris: [[Int]] = []
for part in assembly.parts {
    let mesh = StitchMesh(part.model).transformed(by: part.transform)
    let base = verts.count
    for i in mesh.positions.indices {
        let p = mesh.positions[i]
        verts.append([p.x, p.y, p.z, Float(mesh.colorIndex[i]), mesh.shade[i]])
    }
    for t in stride(from: 0, to: mesh.indices.count, by: 3) {
        tris.append([base + Int(mesh.indices[t]), base + Int(mesh.indices[t + 1]), base + Int(mesh.indices[t + 2])])
    }
}
for eye in assembly.eyes {
    let mesh = StitchMesh.sphere(center: eye.center, radius: eye.radius)
    let base = verts.count
    for i in mesh.positions.indices {
        let p = mesh.positions[i]
        verts.append([p.x, p.y, p.z, Float(mesh.colorIndex[i]), mesh.shade[i]])
    }
    for t in stride(from: 0, to: mesh.indices.count, by: 3) {
        tris.append([base + Int(mesh.indices[t]), base + Int(mesh.indices[t + 1]), base + Int(mesh.indices[t + 2])])
    }
}
print("eyes \(assembly.eyes.count)")
let json: [String: Any] = ["vertices": verts.map { $0.map(Double.init) }, "triangles": tris]
let data = try! JSONSerialization.data(withJSONObject: json)
try! data.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(verts.count) vertices, \(tris.count) triangles")
