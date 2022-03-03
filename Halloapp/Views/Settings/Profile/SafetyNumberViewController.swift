//
//  SafetyNumberViewController.swift
//  HalloApp
//
//  Created by Garrett on 5/12/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

final class SafetyNumberViewController: UIViewController {

    init(currentUser: SafetyNumberData, contact: SafetyNumberData, contactName: String, dismissAction: (() -> Void)?) {

        self.safetyNumberManager = SafetyNumberManager(currentUser: currentUser, otherUser: contact)
        self.dismissAction = dismissAction
        self.contactName = contactName

        super.init(nibName: nil, bundle: nil)

        if let number = safetyNumberManager.safetyNumber {
            numberLabel.text = formattedSafetyNumber(number)
        }

        if let qrCodeData = safetyNumberManager.qrCodeDataToDisplay {
            let image = UIImage.qrCodeImage(for: qrCodeData, size: CGSize(width: 200, height: 200))
            qrView.setQRCodeImage(image)
            qrView.addTarget(self, action: #selector(didTapQRView), for: .touchUpInside)
        }

        statusLabel.text = contactName
        infoLabel.text = Localizations.safetyNumberInstructions(name: contactName)

        if dismissAction != nil {
            navigationItem.leftBarButtonItem = .init(image: UIImage(named: "ReplyPanelClose"), style: .plain, target: self, action: #selector(didTapDismiss))
        }
        navigationItem.title = Localizations.safetyNumberTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .feedBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.layoutMargins = UIEdgeInsets(top: 8, left: 24, bottom: 8, right: 24)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.numberOfLines = 0

        qrView.translatesAutoresizingMaskIntoConstraints = false

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.numberOfLines = 5
        numberLabel.textColor = .label
        numberLabel.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        numberLabel.textAlignment = .center

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.numberOfLines = 0
        infoLabel.textColor = .label
        infoLabel.textAlignment = .center
        infoLabel.font = .preferredFont(forTextStyle: .footnote)

        scrollView.addSubview(statusLabel)
        scrollView.addSubview(qrView)
        scrollView.addSubview(numberLabel)
        scrollView.addSubview(infoLabel)
        view.addSubview(scrollView)

        statusLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor).isActive = true
        statusLabel.constrainMargins([.leading, .trailing], to: scrollView)

        qrView.constrain([.centerX], to: scrollView)
        qrView.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor).isActive = true
        qrView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16).isActive = true
        qrView.widthAnchor.constraint(equalTo: qrView.heightAnchor).isActive = true

        numberLabel.constrainMargins([.leading, .trailing], to: scrollView)
        numberLabel.topAnchor.constraint(equalTo: qrView.bottomAnchor, constant: 24).isActive = true

        infoLabel.constrainMargins([.leading, .trailing], to: scrollView)
        infoLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 24).isActive = true
        infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor).isActive = true

        scrollView.constrain(to: view)
    }

    func withNavigationController() -> UIViewController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .fullScreen

        return controller
    }

    private let scrollView = UIScrollView()
    private let statusLabel = UILabel()
    private let qrView = QRView()
    private let numberLabel = UILabel()
    private let infoLabel = UILabel()

    private let contactName: String
    private let safetyNumberManager: SafetyNumberManager
    private let dismissAction: (() -> Void)?

    @objc
    private func didTapDismiss() {
        dismissAction?()
    }

    @objc
    private func didTapQRView() {
        let vc = QRCodeScannerViewController(delegate: self)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func formattedSafetyNumber(_ safetyNumber: String) -> String {
        var output = ""
        let chunks = safetyNumber.splitIntoChunks(ofLength: 5)
        for (i, chunk) in chunks.enumerated() {
            let isLastChunkOnLine = (i % 4) == 3
            output += chunk
            output += isLastChunkOnLine ? "\n\n" : "   "
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SafetyNumberViewController: QRCodeScannerDelegate {

    private func popQRScannerAndShowAlert(title: String?, message: String?) {
        navigationController?.popToViewController(self, animated: true)

        let vc = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert)
        vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
        navigationController?.present(vc, animated: true, completion: nil)
    }

    func qrCodeScanner(_ scanner: QRCodeScannerViewController, didScanCodeWithData data: Data) {
        switch safetyNumberManager.verify(qrCodeData: data) {
        case .invalid, .unsupportedOrInvalid:
            scanner.showMessage(
                Localizations.safetyNumberNotVerified(contactName: contactName),
                for: 3)
        case .success:
            popQRScannerAndShowAlert(
                title: Localizations.safetyNumberTitle,
                message: Localizations.safetyNumberVerified(contactName: contactName))
        }
    }

    func qrCodeScanner(_ scanner: QRCodeScannerViewController, didEndWithError error: QRCodeScannerError) {
        switch error {
        case .deviceError:
            popQRScannerAndShowAlert(
                title: nil,
                message: Localizations.cameraError)
        case .unauthorized:
            popQRScannerAndShowAlert(
                title: nil,
                message: Localizations.cameraAccessPrompt)
        }
    }
}

final class QRView: UIControl {
    override init(frame: CGRect) {

        super.init(frame: frame)

        backgroundView.backgroundColor = .feedPostBackground

        label.text = Localizations.safetyNumberScan
        label.numberOfLines = 0
        label.textAlignment = .center

        addSubview(backgroundView)
        addSubview(imageView)
        addSubview(label)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.constrain(to: self)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor).isActive = true
        imageView.constrain([.centerX, .centerY], to: self)
        imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.65).isActive = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.constrain([.leading, .trailing], to: self)
        label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16).isActive = true
        label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                updateMask()
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self.point(inside: point, with: event) ? self : nil
    }

    func setQRCodeImage(_ image: UIImage?) {
        imageView.image = image
    }

    private let backgroundView = UIView()
    private let imageView = UIImageView()
    private let label = UILabel()

    private func updateMask() {
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: bounds).cgPath
        backgroundView.layer.mask = mask
        backgroundView.layer.masksToBounds = true
    }
}

extension Localizations {
    static func safetyNumberInstructions(name: String) -> String {
        let format = NSLocalizedString(
            "safety.number.instructions",
            value: "To verify the security of your connection with %@, check that the numbers above match the ones shown on their device, or scan the QR code on their phone.",
            comment: "Instructions for how to use the safety number verification UI")
        return String(format: format, name)
    }

    static var safetyNumberTitle: String {
        NSLocalizedString(
            "safety.number.title",
            value: "Verify Safety Number",
            comment: "Title for screen that allows users to verify a contact's safety number")
    }

    static func safetyNumberVerified(contactName: String) -> String {
        let format = NSLocalizedString(
            "safety.number.verified",
            value: "Successfully verified safety number for %@!",
            comment: "Message to show when safety number is succesfully verified")
        return String(format: format, contactName)
    }

    static func safetyNumberNotVerified(contactName: String) -> String {
        let format = NSLocalizedString(
            "safety.number.not.verified",
            value: "Unable to verify safety number for %@",
            comment: "Message to show when safety number cannot be succesfully verified")
        return String(format: format, contactName)
    }

    static var safetyNumberScan: String {
        NSLocalizedString(
            "safety.number.scan",
            value: "Tap to Scan",
            comment: "Title for button that will open QR code scanner used to verify a contact's safety number")
    }

    static var cameraError: String {
        NSLocalizedString(
            "camera.error",
            value: "Camera error",
            comment: "Generic error when trying to use camera"
        )
    }
}
