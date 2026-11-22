import SceneKit
import SwiftUI
import UIKit
import simd

extension Mat4 {
    var simd: simd_float4x4 {
        simd_float4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                                SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
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
                node.simdTransform = part.transform.simd
                root.addChildNode(node)
            }
            for eye in assembly.eyes {
                let sphere = SCNSphere(radius: CGFloat(eye.radius))
                let material = SCNMaterial()
                material.diffuse.contents = UIColor(white: 0.05, alpha: 1)
                material.specular.contents = UIColor.white
                material.shininess = 0.9
                sphere.materials = [material]
                let node = SCNNode(geometry: sphere)
                node.simdPosition = eye.center
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
