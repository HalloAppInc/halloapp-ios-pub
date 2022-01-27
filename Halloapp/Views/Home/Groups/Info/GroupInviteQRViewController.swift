//
//  GroupInviteQRViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

fileprivate struct Constants {
    static let QRCodeSize:CGFloat = 300
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
        view.addSubview(mainView)
        navigationItem.rightBarButtonItem = shareButton
        mainView.constrain(to: view)

        if let link = inviteLink {
            if let code = HalloCode(size: CGSize(width: Constants.QRCodeSize, height: Constants.QRCodeSize), string: link) {
                QRImage.image = code.image
            }
        }
    }
    
    @objc private func pushedShare(_ button: UIBarButtonItem) {
        guard let image = QRImage.image else {
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        present(activityVC, animated: true, completion: nil)
    }
    
    private lazy var shareButton: UIBarButtonItem = {
        let config = UIImage.SymbolConfiguration(weight: .medium)
        let share = UIImage(systemName: "square.and.arrow.up", withConfiguration: config)?.withRenderingMode(.alwaysOriginal)
        let button = UIBarButtonItem(image: share, style: .plain, target: self, action: #selector(pushedShare))
        
        return button
    }()
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [QRImage])
        view.axis = .vertical
        view.alignment = .center

        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var QRImage: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
}
