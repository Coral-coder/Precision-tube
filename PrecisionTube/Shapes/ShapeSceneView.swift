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
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            yarn.getRed(&r, green: &g, blue: &b, alpha: &a)
            let base = SIMD3<Float>(Float(r), Float(g), Float(b))

            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var colors: [Float] = []
            var indices: [UInt32] = []

            for (i, band) in model.bands.enumerated() {
                let n = max(3, band.stitches)
                let offset = i.isMultiple(of: 2) ? 0.0 : 0.5           // spiral look
                let dr = band.top.x - band.bottom.x, dz = band.top.y - band.bottom.y
                let len = max(1e-6, (dr * dr + dz * dz).squareRoot())
                let pn = SIMD2(dz / len, -dr / len)                     // outward profile normal
                let roundShade: Float = i.isMultiple(of: 2) ? 1.0 : 0.86
                for j in 0..<n {
                    let a0 = 2 * Double.pi * (Double(j) + offset) / Double(n)
                    let a1 = 2 * Double.pi * (Double(j) + 1 + offset) / Double(n)
                    let am = (a0 + a1) / 2
                    let start = UInt32(positions.count)
                    for (rad, z, ang) in [(band.bottom.x, band.bottom.y, a0), (band.bottom.x, band.bottom.y, a1),
                                          (band.top.x, band.top.y, a1), (band.top.x, band.top.y, a0)] {
                        positions.append(SCNVector3(Float(rad * cos(ang)), Float(z), Float(rad * sin(ang))))
                    }
                    let normal = SCNVector3(Float(pn.x * cos(am)), Float(pn.y), Float(pn.x * sin(am)))
                    normals.append(contentsOf: [normal, normal, normal, normal])
                    let stitchShade: Float = j.isMultiple(of: 2) ? 1.0 : 0.92
                    let c = base * roundShade * stitchShade
                    for _ in 0..<4 { colors.append(contentsOf: [c.x, c.y, c.z, 1]) }
                    indices.append(contentsOf: [start, start + 2, start + 1, start, start + 3, start + 2])
                }
            }
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count / 4,
                                                usesFloatComponents: true, componentsPerVector: 4,
                                                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                                dataStride: MemoryLayout<Float>.size * 4)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), colorSource],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
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
