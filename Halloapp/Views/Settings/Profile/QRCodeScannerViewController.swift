//
//  QRCodeScannerViewController.swift
//  HalloApp
//
//  Created by Garrett on 5/13/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import UIKit

protocol QRCodeScannerDelegate: AnyObject {
    func qrCodeScanner(_ scanner: QRCodeScannerViewController, didScanCodeWithData data: Data)
    func qrCodeScanner(_ scanner: QRCodeScannerViewController, didEndWithError error: QRCodeScannerError)
}

enum QRCodeScannerError: Error {
    case unauthorized
    case deviceError
}

class QRCodeScannerViewController: UIViewController {

    init(delegate: QRCodeScannerDelegate) {

        super.init(nibName: nil, bundle: nil)

        messageView.isHidden = true
        messageView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        messageView.backgroundColor = .black
        messageView.layer.cornerRadius = 10

        label.numberOfLines = 0
        label.backgroundColor = .black
        label.textColor = .white
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .callout)

        // Set delegate in initializer in case camera initialization fails
        self.delegate = delegate

        Self.checkCapturePermissions(type: .video) { isAuthorized in
            guard isAuthorized else {
                self.delegate?.qrCodeScanner(self, didEndWithError: .unauthorized)
                return
            }

            if let device = AVCaptureDevice.default(for: .video) {
                self.startRunning(on: device)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let videoPreviewLayer = videoPreviewLayer {
            view.layer.addSublayer(videoPreviewLayer)
        }

        view.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)

        messageView.addSubview(label)
        view.addSubview(messageView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.constrainMargins(to: messageView)

        messageView.translatesAutoresizingMaskIntoConstraints = false
        messageView.constrainMargins([.leading, .trailing, .centerY], to: view)
        messageView.heightAnchor.constraint(equalToConstant: 120).isActive = true
    }

    weak var delegate: QRCodeScannerDelegate?

    func showMessage(_ message: String, for duration: TimeInterval) {
        hideMessageTask?.cancel()
        label.text = message
        messageView.isHidden = false
        view.bringSubviewToFront(messageView)

        let hideMessage = DispatchWorkItem { self.messageView.isHidden = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: hideMessage)
        hideMessageTask = hideMessage
    }

    // MARK: Private

    private let messageView = UIView()
    private let label = UILabel()
    private var hideMessageTask: DispatchWorkItem?

    private func startRunning(on captureDevice: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            let captureSession = AVCaptureSession()
            captureSession.addInput(input)

            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [.qr]

            let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = .resizeAspectFill
            videoPreviewLayer.frame = view.layer.bounds
            view.layer.addSublayer(videoPreviewLayer)

            captureSession.startRunning()

            self.videoPreviewLayer = videoPreviewLayer
            self.captureSession = captureSession

            viewIfLoaded?.layer.addSublayer(videoPreviewLayer)
        } catch {
            DDLogError("QRCodeScanner/startRunning/error [\(error)]")
            if (error as NSError).code == AVError.applicationIsNotAuthorizedToUseDevice.rawValue {
                delegate?.qrCodeScanner(self, didEndWithError: .unauthorized)
            } else {
                delegate?.qrCodeScanner(self, didEndWithError: .deviceError)
            }
        }
    }

    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var scannedData: Data? {
        didSet {
            if let newValue = scannedData, oldValue != newValue {
                delegate?.qrCodeScanner(self, didScanCodeWithData: newValue)
            }
        }
    }

    private static func checkCapturePermissions(type: AVMediaType, permissionHandler: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            permissionHandler(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { granted in
                DispatchQueue.main.async {
                    permissionHandler(granted)
                }
            }

        case .denied,
             .restricted:
            permissionHandler(false)

        @unknown default:
            permissionHandler(false)
        }
    }
}

extension QRCodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let qrCodeObject = metadataObjects.first(where: { $0.type == .qr }) as? AVMetadataMachineReadableCodeObject,
              let descriptor = qrCodeObject.descriptor as? CIQRCodeDescriptor else
        {
            return
        }

        DispatchQueue.main.async {
            self.scannedData = descriptor.finalData
        }
    }
}

extension CIQRCodeDescriptor {
    // adapted from: https://stackoverflow.com/questions/44683242/vision-framework-barcode-detection-for-ios-11
    var finalData: Data? {
        let bytes = errorCorrectedPayload.bytes
        guard bytes.count > 2 else { return nil }

        let representation = (bytes[0] >> 4) & 0x0f
        guard representation == 4 /* byte encoding */ else { return nil }

        var count = (bytes[0] << 4) & 0xf0
        count |= (bytes[1] >> 4) & 0x0f

        var out = Data(count: Int(count))
        guard count > 0 else { return out }

        var prev = (bytes[1] << 4) & 0xf0
        for i in 2..<bytes.count {
            if (i - 2) == count { break }

            let current = prev | ((bytes[i] >> 4) & 0x0f)
            out[i - 2] = current
            prev = (bytes[i] << 4) & 0xf0
        }
        return out
    }
}
