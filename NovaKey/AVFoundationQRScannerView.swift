//
//  AVFoundationQRScannerView.swift
//  NovaKey
//
//  Fallback QR scanner (works on real devices even when VisionKit/DataScanner isn’t available)
//
//  - Uses AVFoundation AVCaptureSession
//  - Returns first QR payload via onResult, then stops
//  - Has a Cancel button
//

import SwiftUI
import AVFoundation
import UIKit

struct AVFoundationQRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = ScannerVC()
        vc.onResult = onResult
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - Scanner VC

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

        var onResult: ((String) -> Void)?
        var onCancel: (() -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didFinish = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            // Camera permission check
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupCamera()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        granted ? self.setupCamera() : self.cancelTapped()
                    }
                }
            default:
                cancelTapped()
            }

            addCancelButton()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stopSession()
        }

        private func setupCamera() {
            guard !session.isRunning else { return }

            session.beginConfiguration()
            session.sessionPreset = .high

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                session.commitConfiguration()
                cancelTapped()
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                cancelTapped()
                return
            }
            session.addOutput(output)

            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            session.commitConfiguration()

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview

            session.startRunning()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        private func stopSession() {
            if session.isRunning {
                session.stopRunning()
            }
        }

        // MARK: - Metadata delegate

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didFinish else { return }

            for obj in metadataObjects {
                guard let code = obj as? AVMetadataMachineReadableCodeObject,
                      code.type == .qr,
                      let payload = code.stringValue,
                      !payload.isEmpty
                else { continue }

                didFinish = true
                stopSession()

                // Ensure we call back once
                DispatchQueue.main.async { [weak self] in
                    self?.onResult?(payload)
                }
                return
            }
        }

        // MARK: - UI

        private func addCancelButton() {
            let cancel = UIButton(type: .system)

            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.filled()
                config.title = "Cancel"
                config.baseForegroundColor = .white
                config.baseBackgroundColor = UIColor(white: 0.1, alpha: 0.75)
                config.cornerStyle = .medium
                config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                cancel.configuration = config
            } else {
                cancel.setTitle("Cancel", for: .normal)
                cancel.tintColor = .white
                cancel.backgroundColor = UIColor(white: 0.1, alpha: 0.75)
                cancel.layer.cornerRadius = 10
                cancel.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
            }

            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

            cancel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(cancel)

            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12)
            ])
        }

        @objc private func cancelTapped() {
            guard !didFinish else { return }
            didFinish = true
            stopSession()
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
        }
    }
}
