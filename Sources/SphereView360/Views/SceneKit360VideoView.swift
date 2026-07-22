import AVFoundation
import SceneKit
import SwiftUI
import UIKit

private typealias PlatformColor = UIColor

struct SceneKit360VideoView: UIViewRepresentable {
    let player: AVPlayer?
    let resetID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(resetID: resetID)
    }

    func makeUIView(context: Context) -> SphereSceneView {
        let view = SphereSceneView(frame: .zero)
        view.setPlayer(player)
        return view
    }

    func updateUIView(_ uiView: SphereSceneView, context: Context) {
        uiView.setPlayer(player)

        if context.coordinator.resetID != resetID {
            context.coordinator.resetID = resetID
            uiView.resetCamera(animated: true)
        }
    }

    final class Coordinator {
        var resetID: UUID

        init(resetID: UUID) {
            self.resetID = resetID
        }
    }
}

final class SphereSceneView: SCNView {
    private enum CameraControl {
        static let mouseDragRadiansPerPoint: CGFloat = 0.006
        static let preciseScrollRadiansPerPoint: CGFloat = 0.0045
        static let magnifyFieldOfViewScale: CGFloat = 28
        static let minimumPitch: CGFloat = -.pi / 2 + 0.04
        static let maximumPitch: CGFloat = .pi / 2 - 0.04
        static let minimumFieldOfView: CGFloat = 35
        static let maximumFieldOfView: CGFloat = 104
        static let defaultFieldOfView: CGFloat = 76
    }

    private let sphereMaterial = SCNMaterial()
    private let cameraNode = SCNNode()
    private weak var currentPlayer: AVPlayer?
    private var yaw: CGFloat = 0
    private var pitch: CGFloat = 0
    private var fieldOfView: CGFloat = CameraControl.defaultFieldOfView

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        configureScene()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScene()
    }

    func setPlayer(_ player: AVPlayer?) {
        guard currentPlayer !== player else {
            return
        }

        currentPlayer = player

        if let player {
            sphereMaterial.diffuse.contents = player
        } else {
            sphereMaterial.diffuse.contents = PlatformColor.black
        }
    }

    func resetCamera(animated: Bool) {
        yaw = 0
        pitch = 0
        fieldOfView = CameraControl.defaultFieldOfView

        guard animated else {
            applyCamera()
            return
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.18
        applyCamera()
        SCNTransaction.commit()
    }

    private func configureScene() {
        backgroundColor = .black
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        isPlaying = true
        rendersContinuously = true

        let scene = SCNScene()
        self.scene = scene

        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 160

        sphereMaterial.lightingModel = .constant
        sphereMaterial.isDoubleSided = false
        sphereMaterial.cullMode = .front
        sphereMaterial.diffuse.contents = PlatformColor.black
        sphereMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        sphereMaterial.diffuse.wrapS = .repeat
        sphereMaterial.diffuse.wrapT = .clamp

        sphere.firstMaterial = sphereMaterial

        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        camera.fieldOfView = fieldOfView

        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)

        pointOfView = cameraNode
        configurePlatformInput()
        applyCamera()
    }

    private func configurePlatformInput() {
        isUserInteractionEnabled = true

        let oneFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = self
        addGestureRecognizer(oneFingerPan)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    private func applyCamera() {
        cameraNode.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
        cameraNode.camera?.fieldOfView = fieldOfView
    }

    private func rotateCamera(deltaX: CGFloat, deltaY: CGFloat, sensitivity: CGFloat) {
        yaw += deltaX * sensitivity
        pitch += deltaY * sensitivity
        pitch = min(max(pitch, CameraControl.minimumPitch), CameraControl.maximumPitch)
        applyCamera()
    }

    private func zoomCamera(delta: CGFloat) {
        fieldOfView -= delta
        fieldOfView = min(
            max(fieldOfView, CameraControl.minimumFieldOfView),
            CameraControl.maximumFieldOfView
        )
        applyCamera()
    }

    @objc private func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        rotateCamera(
            deltaX: translation.x,
            deltaY: -translation.y,
            sensitivity: CameraControl.mouseDragRadiansPerPoint
        )
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        rotateCamera(
            deltaX: translation.x,
            deltaY: -translation.y,
            sensitivity: CameraControl.preciseScrollRadiansPerPoint
        )
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let scaleDelta = recognizer.scale - 1
        zoomCamera(delta: scaleDelta * CameraControl.magnifyFieldOfViewScale)
        recognizer.scale = 1
    }
}

extension SphereSceneView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
