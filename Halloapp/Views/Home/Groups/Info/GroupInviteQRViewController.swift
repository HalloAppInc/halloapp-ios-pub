//
//  GroupInviteQRViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Core

fileprivate extension GroupInviteQRViewController {
    struct Constants {
        /// The width and height of `QRImage`.
        static let QRCodeSize: CGFloat = 300
        /// Spacing between `primaryLabel` and `secondaryLabel'. `
        static let labelSpacing: CGFloat = 15
        /// Spacing between `secondaryLabel` and `QRImage`.
        static let codeSpacing: CGFloat = 48
    }
}

class GroupInviteQRViewController: UIViewController {
    private var inviteLink: String?
    private var orignalScreenBrightness: CGFloat = 0.5

    init(for inviteLink: String) {
        self.inviteLink = inviteLink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        addShareButton()
        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        orignalScreenBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.8
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIScreen.main.brightness = orignalScreenBrightness
    }

    private func setupView() {
        view.backgroundColor = .primaryBg
        view.addSubview(containerView)
        containerView.addSubview(QRImage)
        containerView.addSubview(primaryLabel)
        containerView.addSubview(secondaryLabel)
        setupConstraints()
        
        if let link = inviteLink {
            if let code = HalloCode(size: CGSize(width: Constants.QRCodeSize, height: Constants.QRCodeSize), string: link) {
                QRImage.image = code.image
            }
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            QRImage.widthAnchor.constraint(equalToConstant: Constants.QRCodeSize),
            QRImage.heightAnchor.constraint(equalToConstant: Constants.QRCodeSize),
            QRImage.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            QRImage.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            secondaryLabel.widthAnchor.constraint(equalTo: QRImage.widthAnchor),
            secondaryLabel.centerXAnchor.constraint(equalTo: QRImage.centerXAnchor),
            secondaryLabel.bottomAnchor.constraint(equalTo: QRImage.topAnchor, constant: -Constants.codeSpacing),
            primaryLabel.widthAnchor.constraint(equalTo: QRImage.widthAnchor),
            primaryLabel.centerXAnchor.constraint(equalTo: QRImage.centerXAnchor),
            primaryLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            primaryLabel.bottomAnchor.constraint(equalTo: secondaryLabel.topAnchor, constant: -Constants.labelSpacing),
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func addShareButton() {
        let config = UIImage.SymbolConfiguration(weight: .medium)
        let share = UIImage(systemName: "square.and.arrow.up", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        let button = UIBarButtonItem(image: share, style: .plain, target: self, action: #selector(pushedShare))
        button.tintColor = .primaryBlackWhite
        
        navigationItem.rightBarButtonItem = button
    }
    
    @objc private func pushedShare(_ button: UIBarButtonItem) {
        let image = view.asImage()
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        present(activityVC, animated: true, completion: nil)
    }
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var QRImage: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 15
        view.clipsToBounds = true
                
        return view
    }()
    
    private lazy var primaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.joinUsingQRCode
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .gothamFont(forTextStyle: .headline, weight: .medium)
        label.sizeToFit()
        
        return label
    }()
    
    private lazy var secondaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.scanUsingQRCode
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .gothamFont(forTextStyle: .subheadline, weight: .regular)
        label.textColor = .lightGray
        label.sizeToFit()
        
        return label
    }()
}

fileprivate extension UIView {
    func asImage() -> UIImage {
        return UIGraphicsImageRenderer(bounds: self.bounds).image { _ in
            self.drawHierarchy(in: self.bounds, afterScreenUpdates: true)
        }
    }
}


// MARK: - localization

extension Localizations {
    static var joinUsingQRCode: String {
        NSLocalizedString("join.group.using.qr.code",
                   value: "Join my Group on HalloApp!",
                 comment: "Text shown when inviting to a group using a QR code")
    }
    
    static var scanUsingQRCode: String {
        NSLocalizedString("scan.to.join.group.using.qr.code",
                   value: "To join, scan this QR code with your phone camera.",
                 comment: "Text shown to instruct using a QR code for joining a group")
    }
}


