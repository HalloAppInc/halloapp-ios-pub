//
//  HalloApp
//
//  Created by Tony Jiang on 4/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Core
import UIKit

protocol OutgoingMsgViewDelegate: AnyObject {
    func outgoingMsgView(_ outgoingMsgView: OutgoingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int)
}

class OutgoingMsgView: UIView {
    
    weak var delegate: OutgoingMsgViewDelegate?
    
    // MARK: Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        self.backgroundColor = .clear
        self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        self.addSubview(self.mainView)
        
        self.mainView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        self.mainView.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.mainView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.mainView.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    // MARK: Quoted Row
    
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
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoQuotedPreview(_:)))
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
        subView.backgroundColor = .systemGray5
        subView.layer.cornerRadius = 20
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        stackView.insertSubview(subView, at: 0)
        stackView.isHidden = true
        
        return stackView
    }()
    
    // MARK: Media Row
    
    private lazy var mediaImageView: ChatMediaSlider = {
        let view = ChatMediaSlider()
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        view.isHidden = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.mediaImageView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.spacing = 0
        view.isHidden = false
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoMediaPreview(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        return view
    }()
    
    // MARK: Text Row
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
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
    
    private lazy var bubbleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedRow, self.textRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.spacing = 0
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .systemBackground
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    private lazy var timeRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.timeLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 1, left: 0, bottom: 0, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.bubbleRow, self.timeRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.alignment = .trailing
        view.spacing = 0
        
        return view
    }()
    
    // MARK: Update
    
    func updateWithChatMessage(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool) {
        let isQuotedMessage = updateQuoted(chatQuoted: chatMessage.quoted, feedPostMediaIndex: Int(chatMessage.feedPostMediaIndex))
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isQuotedMessage: isQuotedMessage,
                   text: chatMessage.text,
                   media: chatMessage.media,
                   timestamp: chatMessage.timestamp)
        
        updateChatMessageOutboundStatus(chatMessage.outgoingStatus)
    }
    
    func updateWithChatGroupMessage(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool) {
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isQuotedMessage: false,
                   text: chatGroupMessage.text,
                   media: chatGroupMessage.media,
                   timestamp: chatGroupMessage.timestamp)
        updateChatGroupMessageOutboundStatus(chatGroupMessage.outboundStatus)
    }
    
    func updateQuoted(chatQuoted: ChatQuoted?, feedPostMediaIndex: Int) -> Bool {

        var isQuotedMessage = false
        
        if let quoted = chatQuoted {
            isQuotedMessage = true
            if let userId = quoted.userId {
                self.quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
            }
            self.quotedTextLabel.text = quoted.text ?? ""

            // TODO: need to optimize
            if let media = quoted.media {

                if let med = media.first(where: { $0.order == feedPostMediaIndex }) {
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if med.type == .image {
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            self.quotedImageView.image = image
                        }
                    } else if med.type == .video {
                        if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
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
        
        return isQuotedMessage
    }
    
    func updateWith(isPreviousMsgSameSender: Bool, isQuotedMessage: Bool, text: String?, media: Set<ChatMedia>?, timestamp: Date?) {
        if isPreviousMsgSameSender {
            self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        } else {
            self.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 0, right: 0)
        }
        
        // media
        if let media = media {
            
            self.mediaImageView.reset()
            
            var sliderMediaArr: [SliderMedia] = []
            
            var mediaArr = Array(media)
            mediaArr.sort { $0.order < $1.order }
            
            let preferredSize = self.preferredSize(for: mediaArr)
            
            for med in mediaArr {
                
                let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)
                
                if med.type == .image {
                    if let image = UIImage(contentsOfFile: fileURL.path) {
                        sliderMediaArr.append(SliderMedia(image: image, type: med.type, order: Int(med.order)))
                    } else {
                        sliderMediaArr.append(SliderMedia(image: nil, type: med.type, order: Int(med.order)))
                    }
                } else if med.type == .video {
                    if let image = VideoUtils.videoPreviewImage(url: fileURL, size: preferredSize) {
                        sliderMediaArr.append(SliderMedia(image: image, type: med.type, order: Int(med.order)))
                    } else {
                        sliderMediaArr.append(SliderMedia(image: nil, type: med.type, order: Int(med.order)))
                    }
                }
            }
            
            if !media.isEmpty {
       
                self.mediaImageView.configure(with: sliderMediaArr, size: preferredSize)
                
                NSLayoutConstraint(item: self.mediaImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.width).isActive = true
                NSLayoutConstraint(item: self.mediaImageView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.height).isActive = true

                self.mediaImageView.isHidden = false
                
                if (isQuotedMessage) {
                    self.mediaRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 0, right: 10)
                }
                self.mediaRow.isHidden = false
                
                self.bubbleRow.insertArrangedSubview(self.mediaRow, at: 1)
            }
        }
        
        // text
        let text = text ?? ""
        if text.count <= 3 && text.containsOnlyEmoji {
            self.textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        self.textView.text = text
        
        // time
        if let timestamp = timestamp {
            self.timeLabel.text = timestamp.chatTimestamp()
        }
    }
    
    func updateChatMessageOutboundStatus(_ outboundStatus: ChatMessage.OutgoingStatus) {
        // ticks
        switch outboundStatus {
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
    }
    
    func updateChatGroupMessageOutboundStatus(_ outboundStatus: ChatGroupMessage.OutboundStatus) {
        // ticks
        switch outboundStatus {
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
    }
    
    // MARK: Reuse
    
    func reset() {
        self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        
        self.quotedNameLabel.text = ""
        self.quotedTextLabel.text = ""
        self.quotedTextVStack.isHidden = true
        self.quotedImageView.isHidden = true
        self.quotedRow.isHidden = true
        
        self.mediaImageView.reset()
        self.mediaImageView.removeConstraints(mediaImageView.constraints)
        self.mediaRow.isHidden = true
        self.mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.mediaImageView.isHidden = true
        
        self.textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.textView.text = ""
        self.sentTickImageView.isHidden = true
        self.sentTickImageView.tintColor = UIColor.systemGray3
        self.deliveredTickImageView.isHidden = true
        self.deliveredTickImageView.tintColor = UIColor.systemGray3
        
        self.timeLabel.text = nil
    }
    
    func preferredSize(for media: [ChatMedia]) -> CGSize {
        guard !media.isEmpty else { return CGSize(width: 0, height: 0) }
        
        var width = CGFloat(UIScreen.main.bounds.width * 0.8).rounded()
        let tallestItem = media.max { return $0.size.height < $1.size.height }
        let tallestItemAspectRatio = tallestItem!.size.height / tallestItem!.size.width
        let maxAllowedAspectRatio: CGFloat = 5/4
        let preferredRatio = min(maxAllowedAspectRatio, tallestItemAspectRatio)
        
        let height = (width * preferredRatio).rounded()
        if media.count == 1 {
            width = height/tallestItemAspectRatio
        }
        return CGSize(width: width, height: height)
    }
    
    @objc func gotoQuotedPreview(_ sender: UIView) {
        self.delegate?.outgoingMsgView(self, previewType: .quoted, mediaIndex: 0)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        self.delegate?.outgoingMsgView(self, previewType: .media, mediaIndex: self.mediaImageView.currentPage)
    }
}

