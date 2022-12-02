//
//  MessageDocumentView.swift
//  Core
//
//  Created by Garrett on 11/18/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import UIKit

public final class MessageDocumentView: UIControl {
    static let previewSize = CGSize(width: 238, height: 124)
    static let cornerRadius = CGFloat(10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        label.font = .scaledSystemFont(ofSize: 15)

        labelBackground.translatesAutoresizingMaskIntoConstraints = false
        labelBackground.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        labelBackground.contentView.addSubview(label)
        addSubview(preview)
        addSubview(labelBackground)

        preview.constrain(to: self)
        preview.heightAnchor.constraint(equalToConstant: Self.previewSize.height).isActive = true
        preview.widthAnchor.constraint(equalToConstant: Self.previewSize.width).isActive = true
        labelBackground.constrain([.leading, .trailing, .bottom], to: self)
        label.constrainMargins(to: labelBackground.contentView)

        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = true

    }

    public func setDocument(url: URL?, name: String?) {
        documentURL = url
        guard let url = url else {
            label.text = nil
            preview.image = nil
            return
        }

        let attrString: NSMutableAttributedString = {
            guard let icon = UIImage(systemName: "doc") else {
                return NSMutableAttributedString(string: "📄")
            }
            return NSMutableAttributedString(attachment: NSTextAttachment(image: icon))
        }()
        if let name = name {
            attrString.append(NSAttributedString(string: " \(name)"))
        }
        label.attributedText = attrString

        FileUtils.generateThumbnail(for: url, size: FileUtils.thumbnailSizeDefault) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let image):
                    guard url == self.documentURL else {
                        // Ignore thumbnail if it arrives after view has been reused
                        return
                    }
                    self.preview.image = image
                case .failure(let error):
                    DDLogError("MessageDocumentView/generateThumbnail/error [\(url.absoluteString)] [\(error)]")
                }
            }
        }
    }

    private let preview = UIImageView()
    private let label = UILabel()
    private let labelBackground = BlurView(effect: UIBlurEffect(style: .prominent), intensity: 0.5)

    private var documentURL: URL?
}
