//
//  OutboundMsgView.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

fileprivate struct Constants {
    static let TextFontStyle: UIFont.TextStyle = .subheadline
    static let MaxWidthOfMsgBubble:CGFloat = UIScreen.main.bounds.width * 0.8
}

protocol OutboundMsgViewCellDelegate: AnyObject {
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewQuotedMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didLongPressOn msgId: String)
}

class OutboundMsgViewCell: UITableViewCell {
    
    weak var delegate: OutboundMsgViewCellDelegate?
    public var messageID: String? = nil
    public var indexPath: IndexPath? = nil
    
    public var mediaIndex: Int {
        get {
            return mediaImageView.currentPage
        }
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
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 18)
        
        contentView.addSubview(mainView)

        mainView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true

        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
        
        mainView.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(Constants.MaxWidthOfMsgBubble).rounded()).isActive = true
    }
    
    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ bubbleRow ])
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
        subView.backgroundColor = UIColor.chatOwnBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        return view
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
        subView.backgroundColor = .secondarySystemGroupedBackground
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
    
    // MARK: Media Row
    
    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ mediaImageView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoMediaPreview(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        view.isHidden = false
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
    
    // MARK: Text Row
    
    private lazy var textRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ spacer, textStackView ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.alignment = .bottom
        view.spacing = 1

        return view
    }()
    
    private lazy var textStackView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ textView ])
        view.axis = .horizontal
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(timeAndStatusRow)
        timeAndStatusRow.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        timeAndStatusRow.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor).isActive = true
        
        return view
    }()

    private lazy var textView: UnselectableUITextView = {
        let textView = UnselectableUITextView()
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        textView.tintColor = UIColor.label
        textView.textColor = UIColor.chatOwnMsg

        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var timeAndStatusRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ timeAndStatusLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 5)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // font point 11
    private lazy var timeAndStatusLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    // MARK: Update
    
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
                   timestamp: chatMessage.timestamp,
                   statusIcon: statusIcon(chatMessage.outgoingStatus))

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoMsgInfo(_:)))
        bubbleRow.isUserInteractionEnabled = true
        bubbleRow.addGestureRecognizer(tapGesture)
    }
    
    func updateWithChatGroupMessage(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        messageID = chatGroupMessage.id

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
                   timestamp: chatGroupMessage.timestamp,
                   statusIcon: statusIcon(chatGroupMessage.outboundStatus))
        
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
                        }
                    } else if med.type == .video {
                        if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
                            quotedImageView.image = image
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
    
    func updateWith(isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool, isQuotedMessage: Bool, text: String?, media: Set<ChatMedia>?, timestamp: Date?, statusIcon: UIImage?) {

        if isNextMsgSameSender {
            contentView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 18)
        } else {
            contentView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 18)
        }
        
        // media
        if let media = media {
            
            mediaImageView.reset()
            
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
                
        // time and status
        if let timestamp = timestamp {
            let result = NSMutableAttributedString(string: timestamp.chatTimestamp())
            
            if let icon = statusIcon {
                let iconAttachment = NSTextAttachment(image: icon)
                result.append(NSAttributedString(string: "  "))
                result.append(NSAttributedString(attachment: iconAttachment))
            }

            timeAndStatusLabel.attributedText = result
        }
        
        // text
        var isLargeFont = false
        let text = text ?? ""
        if text.count <= 3 && text.containsOnlyEmoji {
            isLargeFont = true
            textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }

        let textRatio = isLargeFont ? 0.8 : 1.7
            
        var blanks = " \u{2800}" // extra space so links can work
        let numBlanks = timeAndStatusLabel.text?.count ?? 1
        blanks += String(repeating: "\u{00a0}", count: Int(Double(numBlanks)*textRatio)) // nonbreaking spaces
        textView.text = text + blanks
    }
    
    func statusIcon(_ status: ChatMessage.OutgoingStatus) -> UIImage? {
        switch status {
        case .seen: return UIImage(named: "CheckmarkDouble")?.withTintColor(.chatOwnMsg)
        case .delivered: return UIImage(named: "CheckmarkDouble")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))
        case .sentOut: return UIImage(named: "CheckmarkSingle")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))
        default: return nil }
    }
    
    func statusIcon(_ status: ChatGroupMessage.OutboundStatus) -> UIImage? {
        switch status {
        case .seen: return UIImage(named: "CheckmarkDouble")?.withTintColor(.chatOwnMsg)
        case .delivered: return UIImage(named: "CheckmarkDouble")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))
        case .sentOut: return UIImage(named: "CheckmarkSingle")?.withTintColor(UIColor.chatOwnMsg.withAlphaComponent(0.4))
        default: return nil }
    }
    
    // MARK: Reuse
    
    func reset() {
        messageID = nil
        indexPath = nil
        
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 3, right: 18)
        
        quotedRow.subviews[1].backgroundColor = .secondarySystemGroupedBackground
        quotedRow.isHidden = true
        quotedNameLabel.textColor = .label
        quotedNameLabel.text = ""
        quotedTextView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        quotedTextView.text = ""
        quotedImageView.removeConstraints(quotedImageView.constraints)
        quotedImageView.isHidden = true

        mediaImageView.reset()
        mediaImageView.removeConstraints(mediaImageView.constraints)
        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        
        textView.font = UIFont.preferredFont(forTextStyle: Constants.TextFontStyle)
        textView.text = ""

        timeAndStatusLabel.attributedText = nil
    }
    
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
        delegate?.outboundMsgViewCell(self, previewQuotedMediaAt: 0, withDelegate: quotedImageView)
    }

    @objc func gotoMediaPreview(_ sender: UIView) {
        delegate?.outboundMsgViewCell(self, previewMediaAt: mediaImageView.currentPage, withDelegate: mediaImageView)
    }
    
    @objc func gotoMsgInfo(_ sender: UIView) {
        guard let messageID = messageID else { return }
        delegate?.outboundMsgViewCell(self, didLongPressOn: messageID)
    }
}
