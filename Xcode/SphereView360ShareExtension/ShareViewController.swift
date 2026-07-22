import AVFoundation
import Foundation
import UIKit

final class ShareViewController: UIViewController {
    private let sceneView = SphereSceneView(frame: .zero)
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var player: AVPlayer?

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(sceneView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "Loading video..."
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 3
        rootView.addSubview(messageLabel)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        rootView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, multiplier: 0.72),

            doneButton.trailingAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedVideo()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
    }

    @objc private func done() {
        player?.pause()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func loadSharedVideo() {
        SharedVideoLoader.loadFirstVideoURL(from: extensionContext) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleLoadedVideo(result)
            }
        }
    }

    private func handleLoadedVideo(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none
            self.player = player
            messageLabel.isHidden = true
            sceneView.setPlayer(player)
            sceneView.resetCamera(animated: false)
            player.play()
        case .failure(let error):
            messageLabel.text = error.localizedDescription
            messageLabel.isHidden = false
        }
    }
}
