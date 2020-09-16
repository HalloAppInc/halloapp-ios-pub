//
//  HalloApp
//
//  Created by Tony Jiang on 4/21/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

fileprivate struct Constants {
    static let TextFontStyle: UIFont.TextStyle = .subheadline
}

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

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        backgroundColor = .clear
        layoutMargins = UIEdgeInsets(top: 3, left: 0, bottom: 0, right: 0)
        addSubview(mainView)
        
        mainView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
    }
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ bubbleRow, timeRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.alignment = .trailing
        view.spacing = 0
        
        return view
    }()
    
    private lazy var bubbleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quotedRow, textRow ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.lavaOrange.withAlphaComponent(0.1)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        return view
    }()
    
    // MARK: Quoted Row
    
    private lazy var quotedRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedTextVStack, self.quotedImageView ])
        view.axis = .horizontal
        view.spacing = 10
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .white
        subView.layer.cornerRadius = 20
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        
        view.insertSubview(subView, at: 0)
        view.isHidden = true
        
        return view
    }()
    
    private lazy var quotedTextVStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ self.quotedNameLabel, self.quotedTextView, spacer ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.axis = .vertical
        view.spacing = 3
        view.isHidden = true
        return view
    }()
    
    private lazy var quotedNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        label.font = boldFont
        label.textColor = .darkText
        return label
    }()
        
    private lazy var quotedTextView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.isEditable = false
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.dataDetectorTypes = .link
        view.textContainerInset = UIEdgeInsets.zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        view.textColor = .darkText
        view.tintColor = UIColor.link
        view.translatesAutoresizingMaskIntoConstraints = false
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
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        textView.tintColor = UIColor.link
        textView.translatesAutoresizingMaskIntoConstraints = false
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
        view.axis = .vertical
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var deliveredTickStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.deliveredTickImageView ])
        view.axis = .vertical
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
            
    private lazy var textRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ spacer, self.textStackView, self.sentTickStack, self.deliveredTickStack ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
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
        let view = UIStackView(arrangedSubviews: [ timeLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 1, left: 15, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    

    
    // MARK: Update
    
    func updateWithChatMessage(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        let isQuotedMessage = updateQuoted(chatQuoted: chatMessage.quoted, feedPostMediaIndex: Int(chatMessage.feedPostMediaIndex))
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
                   isQuotedMessage: isQuotedMessage,
                   text: chatMessage.text,
                   media: chatMessage.media,
                   timestamp: chatMessage.timestamp)
        
        updateChatMessageOutboundStatus(chatMessage.outgoingStatus)
    }
    
    func updateWithChatGroupMessage(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
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
                quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
            }
            quotedTextView.text = quoted.text ?? ""

            // TODO: need to optimize
            if let media = quoted.media {

                if let med = media.first(where: { $0.order == feedPostMediaIndex }) {
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if med.type == .image {
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            quotedImageView.image = image
                        }
                    } else if med.type == .video {
                        if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
                            quotedImageView.image = image
                        }
                    }

                    let imageSize: CGFloat = 80.0

                    NSLayoutConstraint(item: self.quotedImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
                    NSLayoutConstraint(item: self.quotedImageView, attribute: .height, relatedBy: .equal, toItem: quotedImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true

                    quotedImageView.isHidden = false
                }

            }
            
            quotedTextVStack.isHidden = false
            quotedRow.isHidden = false
        }
        
        return isQuotedMessage
    }
    
    func updateWith(isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool, isQuotedMessage: Bool, text: String?, media: Set<ChatMedia>?, timestamp: Date?) {

        if isNextMsgSameSender {
            timeRow.layoutMargins = UIEdgeInsets(top: 1, left: 15, bottom: 3, right: 0)
        } else {
            timeRow.layoutMargins = UIEdgeInsets(top: 1, left: 15, bottom: 10, right: 0)
        }
        
        if isNextMsgSameTime {
            timeRow.isHidden = true
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
                bubbleRow.insertArrangedSubview(self.mediaRow, at: 1)
                
                var preferredHeight = preferredSize.height
                if media.count > 1 {
                    preferredHeight += 25
                }
                mediaImageView.widthAnchor.constraint(equalToConstant: preferredSize.width).isActive = true
                mediaImageView.heightAnchor.constraint(equalToConstant: preferredHeight).isActive = true
                
                mediaImageView.configure(with: sliderMediaArr, size: preferredSize)
                
                mediaImageView.isHidden = false
                
                if (isQuotedMessage) {
                    mediaRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
                }
                mediaRow.isHidden = false
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
        quotedNameLabel.text = ""
        quotedTextView.text = ""
        quotedTextVStack.isHidden = true
        quotedImageView.isHidden = true
        quotedRow.isHidden = true
        
        mediaImageView.reset()
        mediaImageView.removeConstraints(mediaImageView.constraints)
        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        textView.text = ""
        sentTickImageView.isHidden = true
        sentTickImageView.tintColor = UIColor.systemGray3
        deliveredTickImageView.isHidden = true
        deliveredTickImageView.tintColor = UIColor.systemGray3
        
        timeRow.isHidden = false
        timeRow.layoutMargins = UIEdgeInsets(top: 1, left: 15, bottom: 10, right: 0)
        timeLabel.isHidden = false
        timeLabel.text = nil
    }
    
    func preferredSize(for media: [ChatMedia]) -> CGSize {
        guard !media.isEmpty else { return CGSize(width: 0, height: 0) }
        
        let maxRatio: CGFloat = 5/4 // height/width
        let maxWidth = CGFloat(UIScreen.main.bounds.width * 0.8)
        let maxHeight = maxWidth*maxRatio
        
        var tallest: CGFloat = 0
        var widest: CGFloat = 0
        for med in media {
            let ratio = med.size.height/med.size.width
            let height = maxWidth*ratio
            let width = maxHeight/ratio
            
            tallest = max(tallest, height)
            widest = max(widest, width)
        }
        
        tallest = min(tallest, maxHeight)
        widest = min(widest, maxWidth)
        return CGSize(width: widest, height: tallest)
    }
    
    @objc func gotoQuotedPreview(_ sender: UIView) {
        self.delegate?.outgoingMsgView(self, previewType: .quoted, mediaIndex: 0)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        self.delegate?.outgoingMsgView(self, previewType: .media, mediaIndex: self.mediaImageView.currentPage)
    }
}

