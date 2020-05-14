//
//  ChatUserView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit
import AVKit

protocol ChatUserViewDelegate: AnyObject {
    func chatUserView(_ chatUserView: ChatUserView)
}

class ChatUserView: UIView {
    
    weak var delegate: ChatUserViewDelegate?
    
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
        self.backgroundColor = UIColor.systemBackground
        self.addSubview(mainView)
        self.mainView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        self.mainView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.mainView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.mainView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
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
        let stackView = UIStackView(arrangedSubviews: [ self.quotedTextVStack, self.quotedImageView ])
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.spacing = 10

        stackView.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stackView.isLayoutMarginsRelativeArrangement = true
        
        let subView = UIView(frame: stackView.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.layer.cornerRadius = 15
        subView.layer.backgroundColor = UIColor.systemGray5.cgColor
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        stackView.insertSubview(subView, at: 0)
        stackView.isHidden = true
        return stackView
    }()
    

    // MARK:
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.tintColor = UIColor.link
        return textView
    }()
    
    private lazy var textStackView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.textView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.spacing = 0
        return view
    }()
    
    private lazy var sentTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkSingle")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        imageView.isHidden = true
        return imageView
    }()
    
    private lazy var deliveredTickImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "CheckmarkDouble")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor.systemGray3
        imageView.isHidden = true
        return imageView
    }()
        
    private lazy var sentTickStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.sentTickImageView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.spacing = 0
        return view
    }()
    
    private lazy var deliveredTickStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.deliveredTickImageView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.spacing = 0
        return view
    }()
    
    private lazy var textRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ spacer, self.textStackView, self.sentTickStack, self.deliveredTickStack ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.alignment = .bottom
        view.spacing = 1

        let sentTickSize: CGFloat = 12.0
        let deliveredTickSize: CGFloat = 15.0
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: sentTickSize).isActive = true
        NSLayoutConstraint(item: self.sentTickImageView, attribute: .height, relatedBy: .equal, toItem: self.sentTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: self.deliveredTickImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: deliveredTickSize).isActive = true
        NSLayoutConstraint(item: self.deliveredTickImageView, attribute: .height, relatedBy: .equal, toItem: self.deliveredTickImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true

        return view
    }()
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedRow, self.textRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical

        view.spacing = 0
        return view
    }()


    // MARK: Update
    
    func updateWith(with chatMessage: ChatMessage) {

        switch chatMessage.senderStatus {
        case .seen:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemBlue
            self.deliveredTickImageView.isHidden = false
            self.deliveredTickImageView.tintColor = UIColor.systemBlue
        case .delivered:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = false
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        case .sentOut:
            self.sentTickImageView.isHidden = false
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = true
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        default:
            self.sentTickImageView.isHidden = true
            self.sentTickImageView.tintColor = UIColor.systemGray3
            self.deliveredTickImageView.isHidden = true
            self.deliveredTickImageView.tintColor = UIColor.systemGray3
        }
        
        let text = chatMessage.text ?? ""
        self.textView.text = text
        
        if let quoted = chatMessage.quoted {
            if let userId = quoted.userId {
                self.quotedNameLabel.text = AppContext.shared.contactStore.fullName(for: userId)
            }
            self.quotedTextLabel.text = quoted.text ?? ""

            // TODO: need to optimize
            if let media = quoted.media {

                if let med = media.first(where: { $0.order == chatMessage.feedPostMediaIndex }) {
                    let fileURL = AppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if med.type == .image {
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            self.quotedImageView.image = image
                        }
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

    // MARK: Reuse
    
    func reset() {
        self.quotedNameLabel.text = ""
        self.quotedTextLabel.text = ""
        self.quotedTextVStack.isHidden = true
        self.quotedImageView.isHidden = true
        self.quotedRow.isHidden = true
        
        self.textView.text = ""
        self.sentTickImageView.isHidden = true
        self.sentTickImageView.tintColor = UIColor.systemGray3
        self.deliveredTickImageView.isHidden = true
        self.deliveredTickImageView.tintColor = UIColor.systemGray3
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
        self.delegate?.chatUserView(self)
    }
    
}


