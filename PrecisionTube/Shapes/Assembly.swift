import SceneKit
import SwiftUI
import UIKit
import simd

/// A whole amigurumi put together: the biggest piece in the middle, pieces that are sewn on
/// ("Sew on ears between rounds 4 & 6 of head") placed there, the rest set beside it.
struct Assembly: Equatable {
    struct Part: Equatable {
        var model: StitchModel
        var transform: simd_float4x4
    }
    var parts: [Part]
    /// How many yarn colours the pattern uses.
    var colorCount: Int
    /// Whether the main piece is drawn magic ring up.
    var mainTopDown: Bool

    static func build(pieces: [PatternToShape.Piece], gauge: Gauge, flip: Bool? = nil) -> Assembly {
        guard !pieces.isEmpty else { return Assembly(parts: [], colorCount: 1, mainTopDown: false) }
        let models = pieces.map {
            // Stuffed pieces round out; sewn-on pieces (ears, arms) stay flatter.
            StitchModel.from(counts: $0.counts, gauge: gauge, heights: $0.heights, colors: $0.colors,
                             collars: $0.collars, puff: $0.attach == nil ? 0.6 : 0.3)
        }
        let main = pieces.indices.max { pieces[$0].counts.reduce(0, +) < pieces[$1].counts.reduce(0, +) } ?? 0
        let topDown = flip ?? pieces[main].topDown
        let mainModel = models[main]
        let H = Float(mainModel.height)

        var parts: [Part] = []
        // Magic ring up: turn it over (rotate half a turn about x) and lift it back above the floor.
        let mainTransform = topDown ? translation(0, H, 0) * rotation(.pi, axis: SIMD3(1, 0, 0)) : matrix_identity_float4x4
        parts.append(Part(model: mainModel, transform: mainTransform))

        /// Where round n of the main piece is: (radius, height above the floor).
        func surface(_ round: Int) -> (r: Float, y: Float) {
            let i = min(max(round, 1), mainModel.roundCount) - 1
            guard i >= 0, i < mainModel.bands.count else { return (Float(mainModel.maxRadius), H / 2) }
            let edge = mainModel.bands[i].top
            return (Float(edge.x), topDown ? H - Float(edge.y) : Float(edge.y))
        }

        var besideX = Float(mainModel.maxRadius) * 1.5
        for j in pieces.indices where j != main {
            let model = models[j]
            let h = Float(model.height)
            let copies = max(1, pieces[j].repeatCount)
            if let attach = pieces[j].attach, attach.target == main {
                let a = surface(attach.rounds.lowerBound), b = surface(attach.rounds.upperBound)
                let r = max(a.r, b.r) * 0.85
                let y = (a.y + b.y) / 2
                // Small sewn-on pieces aren't stuffed: flatten them.
                let flat = scale(1, 1, 0.35)
                if copies >= 2 {
                    // A pair, one on each side, magic-ring end pointing out.
                    parts.append(Part(model: model, transform: translation(r + h, y, 0) * rotation(.pi / 2, axis: SIMD3(0, 0, 1)) * flat))
                    parts.append(Part(model: model, transform: translation(-(r + h), y, 0) * rotation(-.pi / 2, axis: SIMD3(0, 0, 1)) * flat))
                } else {
                    parts.append(Part(model: model, transform: translation(0, y, r + h) * rotation(-.pi / 2, axis: SIMD3(1, 0, 0))))
                }
            } else {
                // Not sewn anywhere we can tell: stand it beside the main piece.
                for _ in 0..<copies {
                    let radius = Float(model.maxRadius)
                    besideX += radius + 0.6
                    parts.append(Part(model: model, transform: translation(besideX, 0, 0)))
                    besideX += radius
                }
            }
        }
        let colors = (pieces.flatMap(\.colors).max() ?? 0) + 1
        return Assembly(parts: parts, colorCount: colors, mainTopDown: topDown)
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }
    private static func rotation(_ angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }
    private static func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(x, y, z, 1))
    }
}

/// 3D view of a whole assembly, each round in its yarn colour.
struct AssemblySceneView: UIViewRepresentable {
    var assembly: Assembly
    var palette: [UIColor]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        context.coordinator.rebuild(view, assembly: assembly, palette: palette)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        guard c.assembly != assembly || c.palette != palette else { return }
        c.rebuild(view, assembly: assembly, palette: palette)
    }

    final class Coordinator {
        var assembly: Assembly?
        var palette: [UIColor] = []
        private let root = SCNNode()
        private let cameraNode = SCNNode()
        private var installed = false

        func rebuild(_ view: SCNView, assembly: Assembly, palette: [UIColor]) {
            let reframe = self.assembly?.parts.count != assembly.parts.count || self.assembly?.mainTopDown != assembly.mainTopDown
                || self.assembly == nil
            self.assembly = assembly
            self.palette = palette
            guard let scene = view.scene else { return }
            if !installed {
                scene.rootNode.addChildNode(root)
                cameraNode.camera = SCNCamera()
                cameraNode.camera?.zNear = 0.05
                cameraNode.camera?.zFar = 2000
                scene.rootNode.addChildNode(cameraNode)
                installed = true
            }
            root.childNodes.forEach { $0.removeFromParentNode() }
            root.simdTransform = matrix_identity_float4x4
            for part in assembly.parts {
                let node = SCNNode(geometry: ShapeSceneView.Coordinator.stitchGeometry(part.model, palette: palette))
                node.simdTransform = part.transform
                root.addChildNode(node)
            }
            // Centre the whole thing.
            let (lo, hi) = root.boundingBox
            let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
            root.position = SCNVector3(-center.x, -center.y, -center.z)
            if reframe || view.pointOfView == nil {
                let size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 1)
                cameraNode.position = SCNVector3(0, size * 0.25, size * 1.7)
                cameraNode.look(at: SCNVector3(0, 0, 0))
                view.pointOfView = cameraNode
                view.defaultCameraController.target = SCNVector3(0, 0, 0)
            }
        }
    }
}
