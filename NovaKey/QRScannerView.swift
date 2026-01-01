//
//  QRScannerView.swift
//  NovaKey
//
//  Created by Robert Osborne on 12/22/25.
//

import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct QRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        // DataScanner is iOS 16+, but may be unsupported on some devices
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            // Fall back to a simple controller and immediately cancel
            let vc = UIViewController()
            DispatchQueue.main.async { onCancel() }
            return vc
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator

        // Start scanning as soon as it appears
        DispatchQueue.main.async {
            do { try scanner.startScanning() }
            catch { onCancel() }
        }

        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onCancel: onCancel)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onResult: (String) -> Void
        let onCancel: () -> Void
        private var didFinish = false

        init(onResult: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onResult = onResult
            self.onCancel = onCancel
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !didFinish else { return }

            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    didFinish = true
                    DispatchQueue.main.async {
                        dataScanner.stopScanning()
                        A11yAnnounce.say("QR code scanned.")
                        self.onResult(payload)
                    }
                    return
                }
            }
        }

        func dataScannerDidCancel(_ dataScanner: DataScannerViewController) {
            DispatchQueue.main.async {
                dataScanner.stopScanning()
                self.onCancel()
            }
        }
    }
}
