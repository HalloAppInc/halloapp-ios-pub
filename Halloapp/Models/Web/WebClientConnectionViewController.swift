//
//  WebClientConnectionViewController.swift
//  HalloApp
//
//  Created by Garrett on 6/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import Core
import UIKit

final class WebClientConnectionViewController: UIViewController {

    init(manager: WebClientManager?) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
        manager?
            .state
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let statusLabel = UILabel()
    let actionButton = UIButton()
    let manager: WebClientManager?
    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(didTapAction), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [statusLabel, actionButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        view.addSubview(stackView)

        stackView.constrain(to: view)

        update()
    }

    private func update() {
        statusLabel.text = statusText
        actionButton.setTitleColor(.blue, for: .normal)
        if let actionText = actionText {
            actionButton.isEnabled = true
            actionButton.setTitle(actionText, for: .normal)
        } else {
            actionButton.isEnabled = false
            actionButton.setTitle("Wait", for: .normal)
        }
    }

    private var statusText: String {

        guard let manager = manager else {
            return "ERROR [no web client manager]"
        }

        switch manager.state.value {
        case .disconnected:
            return "Disconnected"
        case .registering(let key):
            return "Connecting [\(key.base64PrefixForLogs())]"
        case .awaitingHandshake:
            return "Waiting for Connection [\(manager.webStaticKey?.base64PrefixForLogs() ?? "nil")]"
        case .handshaking:
            return "Handshaking [\(manager.webStaticKey?.base64PrefixForLogs() ?? "nil")]"
        case .connected:
            return "Connected [\(manager.webStaticKey?.base64PrefixForLogs() ?? "nil")]"
        }
    }

    private var actionText: String? {
        guard let manager = manager else {
            return nil
        }
        switch manager.state.value {
        case .connected, .handshaking, .awaitingHandshake:
            return "Disconnect"
        case .disconnected:
            return "Connect"
        case .registering:
            return nil
        }
    }

    private func presentQRCodeScanner() {
        let vc = QRCodeScannerViewController(delegate: self)
        present(vc, animated: true)
    }

    @objc
    private func didTapAction() {
        guard let manager = manager else {
            DDLogError("WebClientConnection/action-button/error [no-manager]")
            return
        }
        switch manager.state.value {
        case .disconnected:
            presentQRCodeScanner()
        case .connected, .handshaking, .awaitingHandshake:
            manager.disconnect()
        case .registering:
            DDLogError("WebClientConnection/action-button/error [should-be-disabled]")
        }
    }
}

extension WebClientConnectionViewController: QRCodeScannerDelegate {

    private func popQRScannerAndShowAlert(title: String?, message: String?) {
        // Dispatch in case scanner has not been presented yet
        DispatchQueue.main.async { [weak self] in
            let vc = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert)
            vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            self?.dismiss(animated: true) { [weak self] in
                self?.present(vc, animated: true, completion: nil)
            }
        }
    }

    func qrCodeScanner(_ scanner: QRCodeScannerViewController, didScanCodeWithData data: Data) {
            switch WebClientQRCodeResult.from(qrCodeData: data) {
            case .valid(let staticKey):
                manager?.connect(staticKey: staticKey)
                dismiss(animated: true)
            case .invalid, .unsupportedOrInvalid:
                popQRScannerAndShowAlert(title: nil, message: "Could not read QR code")
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
                message: Localizations.cameraPermissionsBody)
        }
    }

}
