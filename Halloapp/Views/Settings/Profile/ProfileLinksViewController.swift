//
//  ProfileLinksViewController.swift
//  HalloApp
//
//  Created by Tanveer on 11/12/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon
import CocoaLumberjackSwift

class ProfileLinksViewController: BottomSheetViewController {

    let links: [ProfileLink]

    init(links: [ProfileLink]) {
        self.links = links
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("ProfileLinksViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layoutMargins = .init(top: 20, left: 20, bottom: 20, right: 20)

        let stacks =  links.map { link in
            let symbol = link.image
            let text = (link.type.base ?? "") + link.string
            let imageView = UIImageView(image: symbol)
            let label = UILabel()
            let stack = UIStackView(arrangedSubviews: [imageView, label])

            imageView.contentMode = .center
            imageView.tintColor = .primaryBlue
            imageView.translatesAutoresizingMaskIntoConstraints = false

            label.text = text
            label.font = .systemFont(ofSize: 16)
            label.setContentCompressionResistancePriority(.breakable, for: .vertical)
            label.isUserInteractionEnabled = true
            stack.spacing = 8

            let width = imageView.widthAnchor.constraint(equalToConstant: 28)
            let height = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
            width.priority = .breakable
            NSLayoutConstraint.activate([width, height])

            return stack
        }

        let stack = UIStackView(arrangedSubviews: stacks)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapHandler))
        view.addGestureRecognizer(tap)
    }

    @objc
    private func tapHandler(_ gesture: UITapGestureRecognizer) {
        guard let hit = view.hitTest(gesture.location(in: gesture.view), with: nil),
              let string = (hit as? UILabel)?.text else {
            return
        }

        if let url = URL(string: string), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://" + string), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            DDLogError("ProfileLinksViewControler/tapHandler/failed to open link \(string)")
        }
    }
}

extension ProfileLink {

    var image: UIImage? {
        let image: UIImage?
        switch type {
        case .instagram:
            image = UIImage(named: "InstagramOutline")
        case .tiktok:
            image = UIImage(named: "TikTokOutline")
        case .twitter:
            image = UIImage(named: "TwitterOutline")
        case .youtube:
            image = UIImage(named: "YouTubeOutline")
        case .other:
            image = UIImage(systemName: "link")
        }

        return image
    }
}
