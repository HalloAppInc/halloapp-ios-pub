//
//  File.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit

fileprivate struct Constants {
    static let SpaceBetweenBubbles:CGFloat = 7
    static let TextFontStyle: UIFont.TextStyle = .subheadline
    static let MaxWidthOfMsgBubble:CGFloat = UIScreen.main.bounds.width * 0.8
}

protocol InboundMsgViewCellDelegate: AnyObject {
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewQuotedMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didLongPressOn msgId: String)
}

class InboundMsgViewCell: UITableViewCell {
    
    weak var delegate: InboundMsgViewCellDelegate?
    public var messageID: String? = nil
    public var indexPath: IndexPath? = nil
    
    public var mediaIndex: Int {
        get {
            return mediaImageView.currentPage
        }
    }
    
    var currentPage: Int = 0

    func chatMediaSlider(_ view: ChatMediaSlider, currentPage: Int) {
        self.currentPage = currentPage
        MainAppContext.shared.chatData.currentPage = self.currentPage
    }
    
    // MARK: Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func prepareForReuse() {
        super.prepareForReuse()
        reset()
    }
    
    private func setup() {
        selectionStyle = .none
        backgroundColor = UIColor.feedBackground
        
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 3, right: 0)
        
        contentView.addSubview(mainView)
        
        mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = false
        
        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
        
        mainView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(Constants.MaxWidthOfMsgBubble).rounded()).isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ bubbleRow ])
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var bubbleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quotedRow, nameRow, mediaRow, textRow ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)
        
        textRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        return view
    }()
    
    // MARK: Name Row
    private lazy var nameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 10, left: 15, bottom: 5, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.boldSystemFont(ofSize: 14)
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
        view.layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 0, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // font point 11
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    // MARK: Quoted Row
    
    private lazy var quotedRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quotedTextVStack, quotedImageView ])
        view.axis = .horizontal
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let baseSubView = UIView(frame: view.bounds)
        baseSubView.layer.cornerRadius = 20
        baseSubView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        baseSubView.layer.masksToBounds = true
        baseSubView.clipsToBounds = true
        baseSubView.backgroundColor = UIColor.feedBackground
        baseSubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(baseSubView, at: 0)
        
        let subView = UIView(frame: baseSubView.bounds)
        subView.layer.cornerRadius = 20
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatOwnBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 1)
        
        view.isHidden = true

        return view
    }()
    
    private lazy var quotedTextVStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ quotedNameLabel, quotedTextView, spacer ])
        view.axis = .vertical
        view.spacing = 3
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var quotedNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textColor = UIColor.label
        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        label.font = boldFont
        return label
    }()
    
    private lazy var quotedTextView: UnselectableUITextView = {
        let view = UnselectableUITextView()
        view.isScrollEnabled = false
        view.isEditable = false
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.dataDetectorTypes = .link
        view.textContainerInset = UIEdgeInsets.zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
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
    
    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ mediaImageView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.spacing = 5
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoMediaPreview(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        view.isHidden = true
        return view
    }()
    
    private lazy var mediaImageView: ChatMediaSlider = {
        let view = ChatMediaSlider()
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true

        view.isHidden = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var textRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ textView, timeRow ])
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 1
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var textView: UnselectableUITextView = {
        let textView = UnselectableUITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        textView.tintColor = UIColor.link
        return textView
    }()

    // MARK: Updates

    func updateWithChatMessage(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        messageID = chatMessage.id
        
        var quoteMediaIndex: Int = 0
        if chatMessage.feedPostId != nil {
            quoteMediaIndex = Int(chatMessage.feedPostMediaIndex)
        }
        if chatMessage.chatReplyMessageID != nil {
            quoteMediaIndex = Int(chatMessage.chatReplyMessageMediaIndex)
        }
        let isQuotedMessage = updateQuoted(chatQuoted: chatMessage.quoted, mediaIndex: quoteMediaIndex)

        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
                   isQuotedMessage: isQuotedMessage,
                   text: chatMessage.text,
                   media: chatMessage.media,
                   timestamp: chatMessage.timestamp)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoMsgInfo(_:)))
        bubbleRow.isUserInteractionEnabled = true
        bubbleRow.addGestureRecognizer(tapGesture)
    }
    
    func updateWithChatGroupMessage(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        messageID = chatGroupMessage.id
        
        if !isPreviousMsgSameSender, let userId = chatGroupMessage.userId {
            nameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
            nameLabel.textColor = getNameColor(for: userId, name: nameLabel.text ?? "", groupId: chatGroupMessage.groupId)
            nameRow.isHidden = false
            
            if (chatGroupMessage.orderedMedia.count == 0) {
                textRow.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
            }
        }
        
        var quoteMediaIndex: Int = 0
        if chatGroupMessage.chatReplyMessageID != nil {
            quoteMediaIndex = Int(chatGroupMessage.chatReplyMessageMediaIndex)
        }
        let isQuotedMessage = updateQuoted(chatQuoted: chatGroupMessage.quoted, mediaIndex: quoteMediaIndex, groupID: chatGroupMessage.groupId)
        
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
                   isQuotedMessage: isQuotedMessage,
                   text: chatGroupMessage.text,
                   media: chatGroupMessage.media,
                   timestamp: chatGroupMessage.timestamp)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoMsgInfo(_:)))
        bubbleRow.isUserInteractionEnabled = true
        bubbleRow.addGestureRecognizer(tapGesture)
    }
        
    func updateQuoted(chatQuoted: ChatQuoted?, mediaIndex: Int, groupID: GroupID? = nil) -> Bool {

        var isQuotedMessage = false
        
        if let quoted = chatQuoted {
            isQuotedMessage = true
            
            guard let userID = quoted.userId else { return false }
            
            quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID)
            
            if let groupID = groupID, userID != MainAppContext.shared.userData.userId {
                quotedNameLabel.textColor = getNameColor(for: userID, name: quotedNameLabel.text ?? "", groupId: groupID)
                quotedRow.subviews[1].backgroundColor = quotedNameLabel.textColor.withAlphaComponent(0.1)
            }
            
            let mentionText = MainAppContext.shared.contactStore.textWithMentions(
                quoted.text,
                orderedMentions: quoted.orderedMentions)
            quotedTextView.attributedText = mentionText?.with(font: quotedTextView.font, color: quotedTextView.textColor)

            let text = quotedTextView.text ?? ""
            if text.count <= 3 && text.containsOnlyEmoji {
                quotedTextView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
            }
            
            // TODO: need to optimize
            if let media = quoted.media {

                if let med = media.first(where: { $0.order == mediaIndex }) {
                    let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(med.relativeFilePath ?? "", isDirectory: false)

                    if med.type == .image {
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            quotedImageView.image = image
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-image/fileURL \(fileURL)")
                        }
                    } else if med.type == .video {
                        if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
                            quotedImageView.image = image
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-video-preview/fileURL \(fileURL)")
                        }
                    }

                    let imageSize: CGFloat = 80.0

                    NSLayoutConstraint(item: quotedImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
                    NSLayoutConstraint(item: quotedImageView, attribute: .height, relatedBy: .equal, toItem: quotedImageView, attribute: .width, multiplier: 1, constant: 0).isActive = true

                    quotedImageView.isHidden = false
                }

            }
            
            quotedRow.isHidden = false
        }
        
        return isQuotedMessage
    }
    
    
    func updateWith(isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool, isQuotedMessage: Bool, text: String?, media: Set<ChatMedia>?, timestamp: Date?) {
        
        if isNextMsgSameSender {
            contentView.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 3, right: 0)
        } else {
            contentView.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 12, right: 0)
        }
                
        // text
        let text = text ?? ""
        if text.count <= 3 && text.containsOnlyEmoji {
            textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        
        self.textView.text = text
        
        // media
        if let media = media {
            
            if textView.text == "" {
                textView.isHidden = true
            }
            
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
                    // TODO: store thumbnails cause it's too slow to generate on the fly
                    if let image = VideoUtils.videoPreviewImage(url: fileURL, size: preferredSize) {
                        sliderMediaArr.append(SliderMedia(image: image, type: med.type, order: Int(med.order)))
                    } else {
                        sliderMediaArr.append(SliderMedia(image: nil, type: med.type, order: Int(med.order)))
                    }
                }
                
            }
            
            if !media.isEmpty {

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
        
        // time
        if let timestamp = timestamp {
            timeLabel.text = timestamp.chatTimestamp()
        }
    }
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        mediaImageView.updateMedia(sliderMedia)
    }
    
    // MARK: reuse
    
    func reset() {
        messageID = nil
        indexPath = nil
        
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 13, right: 0)
        
        nameRow.isHidden = true
        nameLabel.text = ""
        nameLabel.textColor = .secondaryLabel
        
        quotedRow.subviews[1].backgroundColor = UIColor.chatOwnBubbleBg
        quotedRow.isHidden = true
        quotedNameLabel.textColor = UIColor.label
        quotedNameLabel.text = ""
        quotedTextView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        quotedTextView.text = ""
        quotedImageView.removeConstraints(quotedImageView.constraints)
        quotedImageView.isHidden = true
        
        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        mediaImageView.reset()
        mediaImageView.removeConstraints(mediaImageView.constraints)
        
        textRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.isHidden = false
        textView.text = ""
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        
        timeLabel.isHidden = false
        timeLabel.text = nil
    }

    // MARK: Helpers
    
    func preferredSize(for media: [ChatMedia]) -> CGSize {
        guard !media.isEmpty else { return CGSize(width: 0, height: 0) }
        
        let maxRatio: CGFloat = 5/4 // height/width
        // should be smaller than bubble width to avoid constraint conflicts
        let maxWidth = Constants.MaxWidthOfMsgBubble - 10
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
    
    func getNameColor(for userId: UserID, name: String, groupId: GroupID) -> UIColor {
        let groupIdSuffix = String(groupId.suffix(4))
        let userIdSuffix = String(userId.suffix(8))
        let str = "\(groupIdSuffix)\(userIdSuffix)\(name)"
        let colorInt = str.utf8.reduce(0) { return $0 + Int($1) } % 14
        
        // cyan not good
        let color: UIColor = {
            switch colorInt {
            case 0: return UIColor.systemBlue
            case 1: return UIColor.systemGreen
            case 2: return UIColor.systemIndigo
            case 3: return UIColor.systemOrange
            case 4: return UIColor.systemPink
            case 5: return UIColor.systemPurple
            case 6: return UIColor.systemRed
            case 7: return UIColor.systemTeal
            case 8: return UIColor.systemYellow
            case 9: return UIColor.systemGray
            case 10: return UIColor.systemBlue.withAlphaComponent(0.5)
            case 11: return UIColor.systemGreen.withAlphaComponent(0.5)
            case 12: return UIColor.brown
            case 13: return UIColor.magenta
            default: return UIColor.secondaryLabel
            }
        }()
        
        return color
    }
    
    @objc func gotoQuotedPreview(_ sender: UIView) {
        delegate?.inboundMsgViewCell(self, previewQuotedMediaAt: 0, withDelegate: quotedImageView)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        delegate?.inboundMsgViewCell(self, previewMediaAt: mediaImageView.currentPage, withDelegate: mediaImageView)
    }
    
    @objc func gotoMsgInfo(_ sender: UIView) {
        guard let messageID = messageID else { return }
        delegate?.inboundMsgViewCell(self, didLongPressOn: messageID)
    }
}
