import SceneKit
import SwiftUI
import UIKit

/// A 3D preview: the piece as it will crochet up (one colored patch per stitch, rounds in
/// alternating shades) and, optionally, the target shape as a ghost around it.
struct ShapeSceneView: UIViewRepresentable {
    var model: StitchModel
    var ghost: Profile?
    var yarn: UIColor

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        context.coordinator.rebuild(view, model: model, ghost: ghost, yarn: yarn, reframe: true)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        guard c.model != model || c.ghost != ghost || c.yarn != yarn else { return }
        let sizeChanged = abs((c.model?.height ?? 0) - model.height) > 0.5 || abs((c.model?.maxRadius ?? 0) - model.maxRadius) > 0.5
        c.rebuild(view, model: model, ghost: ghost, yarn: yarn, reframe: sizeChanged)
    }

    final class Coordinator {
        var model: StitchModel?
        var ghost: Profile?
        var yarn: UIColor?
        private let pieceNode = SCNNode()
        private let ghostNode = SCNNode()
        private let cameraNode = SCNNode()
        private var installed = false

        func rebuild(_ view: SCNView, model: StitchModel, ghost: Profile?, yarn: UIColor, reframe: Bool) {
            self.model = model; self.ghost = ghost; self.yarn = yarn
            guard let scene = view.scene else { return }
            if !installed {
                scene.rootNode.addChildNode(pieceNode)
                scene.rootNode.addChildNode(ghostNode)
                cameraNode.camera = SCNCamera()
                cameraNode.camera?.zNear = 0.05
                cameraNode.camera?.zFar = 2000
                scene.rootNode.addChildNode(cameraNode)
                installed = true
            }
            pieceNode.geometry = Self.stitchGeometry(model, yarn: yarn)
            ghostNode.geometry = ghost.map { Self.ghostGeometry($0) }

            let h = max(model.height, ghost?.height ?? 0, 1)
            let r = max(model.maxRadius, ghost?.maxRadius ?? 0, 1)
            pieceNode.position = SCNVector3(0, Float(-h / 2), 0)
            ghostNode.position = pieceNode.position
            if reframe || view.pointOfView == nil {
                let size = Float(max(h, 2 * r))
                cameraNode.position = SCNVector3(0, size * 0.35, size * 2.1)
                cameraNode.look(at: SCNVector3(0, 0, 0))
                view.pointOfView = cameraNode
                view.defaultCameraController.target = SCNVector3(0, 0, 0)
            }
        }

        static func stitchGeometry(_ model: StitchModel, yarn: UIColor) -> SCNGeometry {
            stitchGeometry(model, palette: [yarn])
        }

        /// One patch per stitch; each round in its own colour from `palette` (by `model.bandColors`).
        static func stitchGeometry(_ model: StitchModel, palette: [UIColor]) -> SCNGeometry {
            let rgb: [SIMD3<Float>] = (palette.isEmpty ? [UIColor.systemPink] : palette).map { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                return SIMD3<Float>(Float(r), Float(g), Float(b))
            }
            let mesh = StitchMesh(model)
            var colors: [Float] = []
            colors.reserveCapacity(mesh.positions.count * 4)
            for (i, ci) in mesh.colorIndex.enumerated() {
                let c = rgb[min(max(0, ci), rgb.count - 1)] * mesh.shade[i]
                colors.append(contentsOf: [c.x, c.y, c.z, 1])
            }
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count / 4,
                                                usesFloatComponents: true, componentsPerVector: 4,
                                                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                                dataStride: MemoryLayout<Float>.size * 4)
            let positions = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
            let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), colorSource],
                                       elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.isDoubleSided = true
            material.lightingModel = .blinn
            geometry.materials = [material]
            return geometry
        }

        static func ghostGeometry(_ profile: Profile) -> SCNGeometry {
            let segments = 64
            var positions: [SCNVector3] = []
            var indices: [UInt32] = []
            for p in profile.points {
                for k in 0...segments {
                    let ang = 2 * Double.pi * Double(k) / Double(segments)
                    positions.append(SCNVector3(Float(p.x * cos(ang)), Float(p.y), Float(p.x * sin(ang))))
                }
            }
            let ring = UInt32(segments + 1)
            for j in 0..<UInt32(max(0, profile.points.count - 1)) {
                for k in 0..<UInt32(segments) {
                    let a = j * ring + k, b = a + 1, c = a + ring, d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions)],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemTeal
            material.transparency = 0.18
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            material.lightingModel = .constant
            geometry.materials = [material]
            return geometry
        }
    }
}
