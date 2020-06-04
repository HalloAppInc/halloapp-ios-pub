//
//  ChatView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit
import AVKit

protocol ChatViewDelegate: AnyObject {
    func chatView(_ chatView: ChatView)
}

class ChatView: UIView {

    weak var delegate: ChatViewDelegate?
    
    // MARK: Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.backgroundColor = .clear
        self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        self.addSubview(mainView)
        
        self.mainView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        self.mainView.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.mainView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.mainView.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    // MARK: Quoted
    
    private lazy var quotedNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.label
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        return label
    }()
    
    private lazy var quotedTextLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
    }()
    
    private lazy var quotedTextVStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ self.quotedNameLabel, self.quotedTextLabel, spacer ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.axis = .vertical
        view.spacing = 3
        view.isHidden = true
        return view
    }()
    
    private lazy var quotedImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.isHidden = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoPreview(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        return view
    }()
    
    private lazy var quotedRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedTextVStack, self.quotedImageView ])
        view.translatesAutoresizingMaskIntoConstraints = false

        view.axis = .horizontal
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.layer.cornerRadius = 20
        subView.layer.backgroundColor = UIColor.systemBackground.cgColor
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        
        view.insertSubview(subView, at: 0)
        view.isHidden = true

        return view
    }()
    
    private lazy var mediaImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "photo"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var mediaLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "(media is not supported yet)"
        label.isHidden = true
        return label
    }()

    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.mediaImageView, self.mediaLabel ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 5, left: 15, bottom: 0, right: 10)
        view.spacing = 5
        return view
    }()
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = UIColor.systemGray5
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.tintColor = UIColor.link
        return textView
    }()
    
    private lazy var textRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.textView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
//        view.alignment = .bottom
        view.spacing = 1

        return view
    }()
    

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedRow, self.textRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.spacing = 0
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.layer.cornerRadius = 20
        subView.layer.backgroundColor = UIColor.systemGray5.cgColor
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()
    // MARK: Updates
    
    func updateWith(chatMessage: ChatMessage, isPreviousMsgSameSender: Bool) {
        
        if isPreviousMsgSameSender {
            self.layoutMargins = UIEdgeInsets(top: 3, left: 0, bottom: 0, right: 0)
        } else {
            self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        }
        
        let text = chatMessage.text ?? ""
        if text.count <= 3 && text.containsOnlyEmoji {
            self.textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        self.textView.text = text
        
        if let media = chatMessage.media {
            if media.count > 0 {
                self.mediaImageView.isHidden = false
                self.mediaLabel.isHidden = false
            }
        }
        
        if let quoted = chatMessage.quoted {
            if let userId = quoted.userId {
                self.quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
            }
            self.quotedTextLabel.text = quoted.text ?? ""
            
            if let media = quoted.media {

                if let med = media.first(where: { $0.order == chatMessage.feedPostMediaIndex }) {
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if let image = UIImage(contentsOfFile: fileURL.path) {
                        self.quotedImageView.image = image
                    } else if med.type == .video {
                        if let image = self.videoPreviewImage(url: fileURL) {
                            self.quotedImageView.image = image
                        }
                    }

                    let imageSize: CGFloat = 80.0

                    NSLayoutConstraint(item: self.quotedImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
                    NSLayoutConstraint(item: self.quotedImageView, attribute: .height, relatedBy: .equal, toItem: self.quotedImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true

                    self.quotedImageView.isHidden = false
                }
            }
            
            self.quotedTextVStack.isHidden = false
            self.quotedRow.isHidden = false
        }
        
    }
    
    // MARK: reuse
    
    func reset() {
        self.quotedNameLabel.text = ""
        self.quotedTextLabel.text = ""
        self.quotedTextVStack.isHidden = true
        self.quotedImageView.isHidden = true
        self.quotedRow.isHidden = true
                
        self.mediaImageView.isHidden = true
        self.mediaLabel.isHidden = true
        
        self.textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.textView.text = ""
    }

    func videoPreviewImage(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        if let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 2, preferredTimescale: 60), actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        else {
            return nil
        }
    }
    
    @objc func gotoPreview(_ sender: UIView) {
        self.delegate?.chatView(self)
    }
}

fileprivate extension Character {
    var isSimpleEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }
    var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }
    var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}

fileprivate extension String {
    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }
}
