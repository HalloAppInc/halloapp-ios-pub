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
        static let codeSpacing: CGFloat = 30
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
        view.addSubview(QRImage)
        view.addSubview(primaryLabel)
        view.addSubview(secondaryLabel)
        applyConstraints()
        
        if let link = inviteLink {
            if let code = HalloCode(size: CGSize(width: Constants.QRCodeSize, height: Constants.QRCodeSize), string: link) {
                QRImage.image = code.image
            }
        }
    }
    
    private func applyConstraints() {
        QRImage.widthAnchor.constraint(equalToConstant: Constants.QRCodeSize).isActive = true
        QRImage.heightAnchor.constraint(equalToConstant: Constants.QRCodeSize).isActive = true
        QRImage.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        let imageCenter = QRImage.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        imageCenter.constant = primaryLabel.bounds.height + secondaryLabel.bounds.height + Constants.codeSpacing + Constants.labelSpacing
        imageCenter.isActive = true
        
        secondaryLabel.widthAnchor.constraint(equalTo: QRImage.widthAnchor).isActive = true
        secondaryLabel.centerXAnchor.constraint(equalTo: QRImage.centerXAnchor).isActive = true
        let secondaryBottom = secondaryLabel.bottomAnchor.constraint(equalTo: QRImage.topAnchor)
        secondaryBottom.constant = -Constants.codeSpacing
        secondaryBottom.isActive = true
        
        primaryLabel.widthAnchor.constraint(equalTo: QRImage.widthAnchor).isActive = true
        primaryLabel.centerXAnchor.constraint(equalTo: QRImage.centerXAnchor).isActive = true
        let primaryBottom = primaryLabel.bottomAnchor.constraint(equalTo: secondaryLabel.topAnchor)
        primaryBottom.constant = -Constants.labelSpacing
        primaryBottom.isActive = true
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
        return UIGraphicsImageRenderer(bounds: self.bounds).image { context in
            self.layer.render(in: context.cgContext)
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


