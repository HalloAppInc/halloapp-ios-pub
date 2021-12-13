//
//  File.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Core
import MarkdownKit
import UIKit

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 50
}

protocol InboundMsgViewCellDelegate: AnyObject {
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, previewQuotedMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didLongPressOn msgId: String)
    func inboundMsgViewCell(_ inboundMsgViewCell: InboundMsgViewCell, didCompleteVoiceNote msgId: String)
}

class InboundMsgViewCell: MsgViewCell, MsgUIProtocol {
    weak var delegate: InboundMsgViewCellDelegate?

    static private let voiceNoteDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

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
        
        contentView.addSubview(mainView)
        
        mainView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        
        let mainViewBottomConstraint = mainView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)
        mainViewBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        mainViewBottomConstraint.isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ dateColumn, bubbleRow ])
        view.axis = .vertical
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var bubbleRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ bubbleWrapper, spacer ])
        view.axis = .horizontal

        view.translatesAutoresizingMaskIntoConstraints = false
        bubbleWrapper.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bubbleWrapper.widthAnchor.constraint(lessThanOrEqualToConstant: CGFloat(MaxWidthOfMsgBubble).rounded()).isActive = true

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureCellAction))
        panGestureRecognizer.delegate = self
        view.addGestureRecognizer(panGestureRecognizer)

        return view
    }()

    private lazy var bubbleWrapper: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quotedRow, nameRow, linkPreviewRow, mediaRow, textRow ])
        view.axis = .vertical
        view.spacing = 0
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        view.clipsToBounds = true
        
        view.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        view.isLayoutMarginsRelativeArrangement = true
        
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
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ spacer, timeLabel ])
        view.axis = .horizontal
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 5, left: 5, bottom: 0, right: 5)
        view.isLayoutMarginsRelativeArrangement = true

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
        view.alignment = .top
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        quotedImageView.widthAnchor.constraint(equalToConstant: Constants.QuotedMediaSize).isActive = true
        quotedImageView.heightAnchor.constraint(equalToConstant: Constants.QuotedMediaSize).isActive = true
        
        let baseSubView = UIView(frame: view.bounds)
        baseSubView.layer.cornerRadius = 15
        baseSubView.layer.masksToBounds = true
        baseSubView.clipsToBounds = true
        baseSubView.backgroundColor = UIColor.feedBackground
        baseSubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(baseSubView, at: 0)
        
        let subView = UIView(frame: baseSubView.bounds)
        subView.layer.cornerRadius = 15
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.chatOwnBubbleBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 1)
        
        view.isHidden = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(jumpToQuotedMsg(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
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
        let baseFont = UIFont.preferredFont(forTextStyle: .footnote)
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
        view.font = UIFont.preferredFont(forTextStyle: .footnote)
        view.textColor = UIColor.systemGray
        view.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]
        view.translatesAutoresizingMaskIntoConstraints = false

        view.delegate = self

        return view
    }()
    
    private lazy var quotedImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        
        view.layer.cornerRadius = 3
        view.layer.masksToBounds = true
        view.isHidden = true
                
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
        view.alignment = .fill
        view.spacing = 1
        view.layoutMargins = UIEdgeInsets(top: 10, left: 7, bottom: 7, right: 7)
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
        textView.font = UIFont.preferredFont(forTextStyle: TextFontStyle)
        textView.textColor = UIColor.primaryBlackWhite
        textView.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]

        textView.delegate = self

        return textView
    }()

    // MARK: Voice Note Row
    private lazy var voiceNoteRow: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(voiceNoteAvatarView)
        view.addSubview(voiceNoteView)
        view.addSubview(voiceNoteTimeLabel)

        view.heightAnchor.constraint(equalToConstant: 28).isActive = true
        voiceNoteAvatarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10).isActive = true
        voiceNoteAvatarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10).isActive = true
        voiceNoteAvatarView.trailingAnchor.constraint(equalTo: voiceNoteView.leadingAnchor, constant: -10).isActive = true
        voiceNoteView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        voiceNoteView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        voiceNoteTimeLabel.leadingAnchor.constraint(equalTo: voiceNoteView.leadingAnchor, constant: 36).isActive = true
        voiceNoteTimeLabel.topAnchor.constraint(equalTo: voiceNoteView.bottomAnchor, constant: 6).isActive = true

        return view
    }()

    private lazy var voiceNoteView: AudioView = {
        let view = AudioView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layoutMargins = UIEdgeInsets(top: 8, left: 4, bottom: 0, right: 12)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 28),
            view.widthAnchor.constraint(equalToConstant: MaxWidthOfMsgBubble - 96),
        ])

        return view
    } ()

    private lazy var voiceNoteTimeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return label
    }()

    private lazy var voiceNoteAvatarView: AvatarView = {
        let avatar = AvatarView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.widthAnchor.constraint(equalToConstant: 35).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 35).isActive = true

        return avatar
    }()

    func playVoiceNote() {
        voiceNoteView.play()
    }

    func pauseVoiceNote() {
        voiceNoteView.pause()
    }

    // MARK: Link Preview Row
    private lazy var linkPreviewRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ chatLinkPreviewView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.spacing = 0

        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.clipsToBounds = true
        chatLinkPreviewView.heightAnchor.constraint(equalToConstant: 85).isActive = true
        return view
    }()

    private lazy var chatLinkPreviewView: ChatLinkPreviewView = {
        let view = ChatLinkPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: Updates

    enum DisplayText {
        case retracted
        case unsupported
        case rerequesting
        case normal(String, orderedMentions: [ChatMention])
    }

    func updateWithChatMessage(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool) {
        messageID = chatMessage.id

        var quoteMediaIndex: Int = 0
        if chatMessage.feedPostId != nil {
            quoteMediaIndex = Int(chatMessage.feedPostMediaIndex)
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showFullScreenQuotedFeedImage(_:)))
            quotedImageView.isUserInteractionEnabled = true
            quotedImageView.addGestureRecognizer(tapGesture)
        }
        if chatMessage.chatReplyMessageID != nil {
            quoteMediaIndex = Int(chatMessage.chatReplyMessageMediaIndex)
        }
        let isQuotedMessage = updateQuoted(chatQuoted: chatMessage.quoted, mediaIndex: quoteMediaIndex)

        let displayText: DisplayText = {
            switch chatMessage.incomingStatus {
            case .retracted:
                return .retracted
            case .rerequesting:
                return .rerequesting
            case .unsupported:
                return .unsupported
            case .error, .haveSeen, .none, .sentSeenReceipt, .played, .sentPlayedReceipt:
                return .normal(chatMessage.text ?? "", orderedMentions: [])
            }
        }()

        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
                   isQuotedMessage: isQuotedMessage,
                   isPlayed: [.played, .sentPlayedReceipt].contains(chatMessage.incomingStatus),
                   displayText: displayText,
                   media: chatMessage.media,
                   linkPreview: chatMessage.linkPreviews?.first,
                   timestamp: chatMessage.timestamp)

        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(gotoMsgInfo(_:)))
        bubbleWrapper.isUserInteractionEnabled = true
        bubbleWrapper.addGestureRecognizer(gesture)
    }

    func updateQuoted(chatQuoted: ChatQuoted?, mediaIndex: Int) -> Bool {
        var isQuotedMessage = false

        if let quoted = chatQuoted {
            isQuotedMessage = true

            guard let userID = quoted.userId else { return false }
            
            quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID)

            if let mentionText = MainAppContext.shared.contactStore.textWithMentions(
                quoted.text,
                mentions: quoted.orderedMentions) {
                let ham = HAMarkdown(font: UIFont.preferredFont(forTextStyle: .footnote), color: UIColor.systemGray)
                quotedTextView.attributedText = ham.parse(mentionText)
            }

            let text = quotedTextView.text ?? ""
            if text.count <= 3 && text.containsOnlyEmoji {
                quotedTextView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
            }

            if let media = quoted.media, let item = media.first(where: { $0.order == mediaIndex }) {
                let fileURL = item.mediaUrl

                quotedImageView.isUserInteractionEnabled = FileManager.default.fileExists(atPath: fileURL.path)
                quotedImageView.isHidden = false

                if let thumbnailData = item.previewData, item.type != .audio {
                    quotedImageView.image = UIImage(data: thumbnailData)
                } else {
                    switch item.type {
                    case .image:
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            quotedImageView.contentMode = .scaleAspectFill
                            quotedImageView.image = image
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-image/fileURL \(fileURL)")
                        }
                    case .video:
                        if let image = VideoUtils.videoPreviewImage(url: fileURL) {
                            quotedImageView.contentMode = .scaleAspectFill
                            quotedImageView.image = image
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-video-preview/fileURL \(fileURL)")
                        }
                    case .audio:
                        quotedImageView.image = nil
                        quotedImageView.isHidden = true

                        let text = NSMutableAttributedString()

                        if let icon = UIImage(named: "Microphone")?.withTintColor(.systemGray) {
                            let attachment = NSTextAttachment(image: icon)
                            attachment.bounds = CGRect(x: 0, y: -2, width: 13, height: 13)

                            text.append(NSAttributedString(attachment: attachment))
                        }

                        text.append(NSAttributedString(string: Localizations.chatMessageAudio))

                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            let duration = Self.voiceNoteDurationFormatter.string(from: AVURLAsset(url: fileURL).duration.seconds) ?? ""
                            text.append(NSAttributedString(string: " (" + duration + ")"))
                        }

                        quotedTextView.attributedText = text.with(
                            font: UIFont.preferredFont(forTextStyle: .footnote),
                            color: UIColor.systemGray)
                    }
                }


            }
            
            quotedRow.isHidden = false
        }
        
        return isQuotedMessage
    }
    
    
    func updateWith(isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool, isQuotedMessage: Bool, isPlayed: Bool, displayText: DisplayText, media: Set<ChatMedia>?, linkPreview: ChatLinkPreview?, timestamp: Date?) {
        if isPreviousMsgSameSender {
            contentView.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 0, right: 18)
        } else {
            contentView.layoutMargins = UIEdgeInsets(top: 12, left: 18, bottom: 0, right: 18)
        }

        var showRightToLeft: Bool = false

        let isVoiceNote = media?.count == 1 && media?.first?.type == .audio

        if isVoiceNote, let item = media?.first {
            var url: URL? = nil
            if let path = item.relativeFilePath {
                url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(path, isDirectory: false)
            }

            voiceNoteView.delegate = self

            if url == nil {
                voiceNoteView.state = .loading
            } else {
                voiceNoteView.state = isPlayed ? .played : .normal
            }

            if voiceNoteView.url != url {
                voiceNoteTimeLabel.text = "0:00"
                voiceNoteView.url = url
            }

            if let userId = item.message?.userId {
                voiceNoteAvatarView.configure(with: userId, using: MainAppContext.shared.avatarStore)
            }

            if voiceNoteRow.superview == nil {
                bubbleWrapper.insertArrangedSubview(voiceNoteRow, at: bubbleWrapper.arrangedSubviews.count - 1)
            }

            textRow.layoutMargins.top = 2
        } else {
            textRow.layoutMargins.top = 10
        }

        // text
        switch displayText {
        case .normal(let text, _):
            showRightToLeft = text.isRightToLeftLanguage()
            if text.count <= 4 && text.containsOnlyEmoji {
                textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
            }
            if let font = textView.font, let color = textView.textColor {
                let ham = HAMarkdown(font: font, color: color)
                textView.attributedText = ham.parse(text)
            }
        case .rerequesting:
            textView.text = "🕓 " + Localizations.chatMessageWaiting
            textView.textColor = .chatTime
            textView.font = UIFont.preferredFont(forTextStyle: TextFontStyle).withItalicsIfAvailable
        case .retracted:
            textView.text = Localizations.chatMessageDeleted
            textView.textColor = .chatTime
        case .unsupported:
            let attributedText = NSMutableAttributedString(string: "⚠️ " + Localizations.chatMessageUnsupported)
            if let url = AppContext.appStoreURL {
                let link = NSMutableAttributedString(string: Localizations.linkUpdateYourApp)
                link.addAttribute(.link, value: url, range: link.utf16Extent)
                attributedText.append(NSAttributedString(string: " "))
                attributedText.append(link)
            }
            textView.attributedText = attributedText.with(
                font: UIFont.preferredFont(forTextStyle: TextFontStyle).withItalicsIfAvailable,
                color: .chatTime)
        }

        if !showRightToLeft {
            textView.makeTextWritingDirectionLeftToRight(nil)
        } else {
            textView.makeTextWritingDirectionRightToLeft(nil)
        }
        
        // link preview
        if let linkPreview = linkPreview {
            chatLinkPreviewView.configure(chatLinkPreview: linkPreview)
            linkPreviewRow.isHidden = false
            bubbleWrapper.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }

        // media
        if let media = media, !isVoiceNote {
            
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
                
                mediaImageView.configure(with: sliderMediaArr, size: preferredSize, msgID: messageID)
                
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

        // hide textView if there's no text, used mainly for media messages with no text
        if textView.attributedText != nil, textView.attributedText.length == 0 {
            textView.isHidden = true
        } else {
            textView.isHidden = false
        }
    }

    func updateMedia(_ media: ChatMedia) {
        guard let relativeFilePath = media.relativeFilePath else { return }
        let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        switch media.type {
        case .video:
            guard let image = VideoUtils.videoPreviewImage(url: url) else { return }
            mediaImageView.updateMedia(SliderMedia(image: image, type: .image, order: Int(media.order)))
            break
        case .image:
            guard let image = UIImage(contentsOfFile: url.path) else { return }
            mediaImageView.updateMedia(SliderMedia(image: image, type: .image, order: Int(media.order)))
        case .audio:
            voiceNoteView.url = url
            if voiceNoteView.state == .loading, let status = media.message?.incomingStatus {
                voiceNoteView.state = [.played, .sentPlayedReceipt].contains(status) ? .played : .normal
            }
        }
    }
    
    func updateLinkPreviewMedia(_ media: ChatMedia) {
        guard let relativeFilePath = media.relativeFilePath else { return }
        let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        switch media.type {
        case .image:
            guard let image = UIImage(contentsOfFile: url.path) else { return }
            chatLinkPreviewView.show(image: image)
        case .video, .audio:
            break
        }
    }
    
    // MARK: reuse
    
    func reset() {
        messageID = nil
        indexPath = nil
        
        contentView.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 0, right: 18)
        contentView.backgroundColor = UIColor.primaryBg // need to reset since animation of highlighting can be ongoing when jumping
        
        nameRow.isHidden = true
        nameLabel.text = ""
        nameLabel.textColor = .secondaryLabel
        
        quotedRow.subviews[1].backgroundColor = UIColor.chatOwnBubbleBg
        quotedRow.isHidden = true
        quotedNameLabel.textColor = UIColor.label
        quotedNameLabel.text = ""
        quotedTextView.font = UIFont.preferredFont(forTextStyle: .footnote)
        quotedTextView.attributedText = nil
        quotedImageView.isHidden = true

        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        mediaImageView.reset()
        mediaImageView.removeConstraints(mediaImageView.constraints)
        
        // Reset of Link Previews
        linkPreviewRow.isHidden = true

        textRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.font = UIFont.preferredFont(forTextStyle: TextFontStyle)
        textView.textColor = UIColor.primaryBlackWhite
        textView.attributedText = nil
        textView.isHidden = false

        voiceNoteView.delegate = nil
        voiceNoteRow.removeFromSuperview()
        
        timeLabel.isHidden = false
        timeLabel.text = nil
    }

    @objc func jumpToQuotedMsg(_ sender: UIView) {
        delegate?.inboundMsgViewCell(self)
    }
    
    @objc func showFullScreenQuotedFeedImage(_ sender: UIView) {
        delegate?.inboundMsgViewCell(self, previewQuotedMediaAt: 0, withDelegate: quotedImageView)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        delegate?.inboundMsgViewCell(self, previewMediaAt: mediaImageView.currentPage, withDelegate: mediaImageView)
    }
    
    @objc func gotoMsgInfo(_ recognizer: UILongPressGestureRecognizer) {
        guard let messageID = messageID else { return }
        guard let bubbleWrapperFirstSubview = bubbleWrapper.subviews.first else { return }

        if (recognizer.state == .began) {
            UIView.animate(withDuration: 0.5, animations: {
                bubbleWrapperFirstSubview.backgroundColor = .systemGray4
            })

            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            delegate?.inboundMsgViewCell(self, didLongPressOn: messageID)
        } else if (recognizer.state == .ended || recognizer.state == .cancelled) {
            UIView.animate(withDuration: 3.0, animations: {
                bubbleWrapperFirstSubview.backgroundColor = .secondarySystemGroupedBackground
            })
        }
    }
}

extension InboundMsgViewCell: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        voiceNoteTimeLabel.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
        guard let messageID = messageID else { return }
        voiceNoteView.state = .played
        MainAppContext.shared.chatData.markPlayedMessage(for: messageID)
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
        guard completed else { return }
        guard let messageID = messageID else { return }
        delegate?.inboundMsgViewCell(self, didCompleteVoiceNote: messageID)
    }
}

// MARK: UIGestureRecognizer Delegates
extension InboundMsgViewCell {

    // used for swiping to reply
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity: CGPoint = panGestureRecognizer.velocity(in: bubbleRow)
        if velocity.x < 0 { return false }
        return abs(Float(velocity.x)) > abs(Float(velocity.y))
    }
}
