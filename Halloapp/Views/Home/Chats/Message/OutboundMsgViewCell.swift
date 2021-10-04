//
//  OutboundMsgView.swift
//  HalloApp
//
//  Created by Tony Jiang on 10/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import Combine
import Core
import UIKit
import CocoaLumberjackSwift

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 50
}

protocol OutboundMsgViewCellDelegate: AnyObject {
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, previewQuotedMediaAt: Int, withDelegate: MediaExplorerTransitionDelegate)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didLongPressOn msgId: String)
    func outboundMsgViewCell(_ outboundMsgViewCell: OutboundMsgViewCell, didCompleteVoiceNote msgId: String)
}

class OutboundMsgViewCell: MsgViewCell, MsgUIProtocol {
    weak var delegate: OutboundMsgViewCellDelegate?

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

    private var cancellableSet: Set<AnyCancellable> = []
 
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
        
        let view = UIStackView(arrangedSubviews: [ spacer, bubbleWrapper ])
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
        let view = UIStackView(arrangedSubviews: [ quotedRow, mediaRow, textRow ])
        view.axis = .vertical
        view.spacing = 0

        view.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        view.isLayoutMarginsRelativeArrangement = true
        
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
        subView.backgroundColor = .secondarySystemGroupedBackground
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
    
    // MARK: Media Row
    
    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ mediaImageView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(gotoMediaPreview(_:)))
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
        view.axis = .horizontal
        view.alignment = .bottom
        view.spacing = 1
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 7, bottom: 7, right: 7)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(uploadProgressView)
        uploadProgressView.topAnchor.constraint(equalTo: view.topAnchor, constant: -17).isActive = true
        uploadProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5).isActive = true
        uploadProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 35).isActive = true
        
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
        textView.font = UIFont.preferredFont(forTextStyle: TextFontStyle)
        textView.textColor = UIColor.chatOwnMsg
        textView.linkTextAttributes = [.foregroundColor: UIColor.chatOwnMsg, .underlineStyle: 1]
    
        textView.delegate = self

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
    
    private lazy var uploadProgressView: PostingProgressView = {
        let view = PostingProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
//        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
//        view.tag = Self.progressViewTag
//        view.cancelButton.addTarget(self, action: #selector(cancelButtonAction), for: .touchUpInside)
        view.isIndeterminate = false
        view.cancelButton.isHidden = true
        view.progress = 0.0
        view.isHidden = true
        
        return view
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
    
    func highlight() {
        UIView.animate(withDuration: 1.0, animations: {
            self.contentView.backgroundColor = .systemYellow
        })
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            UIView.animate(withDuration: 1.0, animations: {
                self.contentView.backgroundColor = .feedBackground
            })
        }
    }
    
    // MARK: Update
    
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
                
        var text = chatMessage.text
        if [.retracting, .retracted].contains(chatMessage.outgoingStatus) {
            textView.textColor = UIColor.chatTime
            text = Localizations.chatMessageDeleted
        }
        
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isNextMsgSameSender: isNextMsgSameSender,
                   isNextMsgSameTime: isNextMsgSameTime,
                   isQuotedMessage: isQuotedMessage,
                   isPlayed: chatMessage.outgoingStatus == .played,
                   text: text,
                   orderedMentions: [],
                   media: chatMessage.media,
                   timestamp: chatMessage.timestamp,
                   statusIcon: statusIcon(chatMessage.outgoingStatus))

        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(gotoMsgInfo(_:)))
        bubbleWrapper.isUserInteractionEnabled = true
        bubbleWrapper.addGestureRecognizer(gesture)
        
        if chatMessage.outgoingStatus == .pending {
            listenForUploadProgress()
        }
    }

    func updateQuoted(chatQuoted: ChatQuoted?, mediaIndex: Int) -> Bool {

        var isQuotedMessage = false
        
        if let quoted = chatQuoted {
            isQuotedMessage = true
            
            guard let userID = quoted.userId else { return false }
            
            quotedNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userID)

            let mentionText = MainAppContext.shared.contactStore.textWithMentions(
                quoted.text,
                mentions: quoted.orderedMentions)
            quotedTextView.attributedText = mentionText?.with(font: quotedTextView.font, color: quotedTextView.textColor)

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
                            DDLogError("OutgoingMsgView/quoted/no-image/fileURL \(fileURL)")
                        }
                    case .video:
                        if let image = VideoUtils.videoPreviewImage(url: fileURL) {
                            quotedImageView.contentMode = .scaleAspectFill
                            quotedImageView.image = image
                        } else {
                            DDLogError("OutgoingMsgView/quoted/no-video-preview/fileURL \(fileURL)")
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
    
    func updateWith(isPreviousMsgSameSender: Bool, isNextMsgSameSender: Bool, isNextMsgSameTime: Bool, isQuotedMessage: Bool, isPlayed: Bool, text: String?, orderedMentions: [ChatMention], media: Set<ChatMedia>?, timestamp: Date?, statusIcon: UIImage?) {
        if isPreviousMsgSameSender {
            contentView.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 0, right: 18)
        } else {
            contentView.layoutMargins = UIEdgeInsets(top: 12, left: 18, bottom: 0, right: 18)
        }

        let isVoiceNote = media?.count == 1 && media?.first?.type == .audio

        if isVoiceNote, let item = media?.first {
            let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(item.relativeFilePath ?? "", isDirectory: false)

            voiceNoteView.delegate = self
            voiceNoteView.state = .played

            if voiceNoteView.url != url {
                voiceNoteTimeLabel.text = "0:00"
                voiceNoteView.url = url
            }

            if let userId = item.message?.userId {
                voiceNoteAvatarView.configure(with: userId, using: MainAppContext.shared.avatarStore)
            }

            bubbleWrapper.insertArrangedSubview(voiceNoteRow, at: bubbleWrapper.arrangedSubviews.count - 1)

            textRow.layoutMargins.top = 2
        } else {
            textRow.layoutMargins.top = 10
        }

        // media
        if let media = media, !isVoiceNote {
            
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

            let playedIcon: UIImage? = {
                if isVoiceNote {
                    if isPlayed {
                        return UIImage(named: "Microphone")?.withTintColor(traitCollection.userInterfaceStyle == .light ? UIColor.chatOwnMsg : UIColor.primaryBlue)
                    } else {
                        return UIImage(named: "Microphone")?.withTintColor(.systemGray)
                    }
                }

                return nil
            } ()

            if let icon = playedIcon {
                let iconAttachment = NSTextAttachment(image: icon)
                iconAttachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)

                result.append(NSAttributedString(string: "  "))
                result.append(NSAttributedString(attachment: iconAttachment))
            }
    
            if let icon = statusIcon {
                let imageSize = icon.size
                let font = UIFont.systemFont(ofSize: timeAndStatusLabel.font.pointSize - 1)
                
                let scale = font.capHeight / imageSize.height
                let iconAttachment = NSTextAttachment(image: icon)
                iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
                
                result.append(NSAttributedString(string: "  "))
                result.append(NSAttributedString(attachment: iconAttachment))
            }

            timeAndStatusLabel.attributedText = result
        }

        // text
        var text = text ?? ""
        var isLargeFontEmoji = false
        var showTextRTL = text.isRightToLeftLanguage() // show RTL languages right to left even when interface is LTR and vice versa
        let isInterfaceRTL = self.effectiveUserInterfaceLayoutDirection == .rightToLeft

        if text.count <= 3 && text.containsOnlyEmoji {
            isLargeFontEmoji = true
            showTextRTL = true // show large emoji text RTL
        }

        let textRatio = isLargeFontEmoji ? 1.2 : 1.7

        var blanks = " \u{2800}" // extra space so links can work
        let numBlanks = timeAndStatusLabel.text?.count ?? 1
        blanks += String(repeating: "\u{00a0}", count: Int(Double(numBlanks)*textRatio)) // nonbreaking spaces

        var font = textView.font ?? UIFont.preferredFont(forTextStyle: TextFontStyle)
        let color = textView.textColor ?? UIColor.chatOwnMsg
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = showTextRTL ? .right : .left

        if isLargeFontEmoji {
            font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }

        let attrText = NSMutableAttributedString(string: "")

        if !showTextRTL && !isInterfaceRTL {
            text += blanks
        }

        attrText.append(NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))

        // when the interface is RTL or when the text is RTL, always show the timestamp on the line below for simplicity
        if isInterfaceRTL || showTextRTL {
            // add newline and pad with spaces to accommodate timestamp below it
            let padStr = "\n \u{2800}\(blanks)"
            let padTimeFont = UIFont.preferredFont(forTextStyle: .body)
            attrText.append(NSMutableAttributedString(string: padStr, attributes: [.font: padTimeFont, .paragraphStyle: paragraph]))
        }

        textView.attributedText = attrText
        if !showTextRTL {
            textView.makeTextWritingDirectionLeftToRight(nil)
        } else {
            textView.makeTextWritingDirectionRightToLeft(nil)
        }
    }
    
    func statusIcon(_ status: ChatMessage.OutgoingStatus) -> UIImage? {
        switch status {
        case .pending: return UIImage(named: "CheckmarkSingle")?.withTintColor(.clear)
        case .sentOut: return UIImage(named: "CheckmarkSingle")?.withTintColor(.systemGray)
        case .delivered: return UIImage(named: "CheckmarkDouble")?.withTintColor(.systemGray)
        case .seen, .played: return UIImage(named: "CheckmarkDouble")?.withTintColor(traitCollection.userInterfaceStyle == .light ? UIColor.chatOwnMsg : UIColor.primaryBlue)
//        case .error: return UIImage(systemName: "arrow.counterclockwise.circle")?.withTintColor(.systemRed)
        default: return nil }
    }

    private func listenForUploadProgress() {
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetMediaUploadProgress.sink { [weak self] (msgID, progress) in
                guard let self = self else { return }
                guard self.messageID == msgID else { return }
                self.uploadProgressView.isHidden = false
                self.uploadProgressView.progress = progress
                if progress >= 1 {
                    self.uploadProgressView.isHidden = true
                }
            }
        )
    }
    
    // MARK: Reuse
    
    func reset() {
        messageID = nil
        indexPath = nil
        
        contentView.layoutMargins = UIEdgeInsets(top: 3, left: 18, bottom: 0, right: 18)
        contentView.backgroundColor = UIColor.primaryBg // need to reset since animation of highlighting can be ongoing when jumping
        
        quotedRow.subviews[1].backgroundColor = .secondarySystemGroupedBackground
        quotedRow.isHidden = true
        quotedNameLabel.textColor = .label
        quotedNameLabel.text = ""
        quotedTextView.font = UIFont.preferredFont(forTextStyle: .footnote)
        quotedTextView.text = ""
        quotedImageView.isHidden = true

        mediaImageView.reset()
        mediaImageView.removeConstraints(mediaImageView.constraints)
        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        
        textView.font = UIFont.preferredFont(forTextStyle: TextFontStyle)
        textView.textColor = UIColor.chatOwnMsg
        textView.text = ""

        voiceNoteView.delegate = nil
        voiceNoteRow.removeFromSuperview()

        timeAndStatusLabel.attributedText = nil
        
        cancellableSet.forEach { $0.cancel() }
        cancellableSet.removeAll()
    }
    
    @objc func jumpToQuotedMsg(_ sender: UIView) {
        delegate?.outboundMsgViewCell(self)
    }
    
    @objc func showFullScreenQuotedFeedImage(_ sender: UIView) {
        delegate?.outboundMsgViewCell(self, previewQuotedMediaAt: 0, withDelegate: quotedImageView)
    }

    @objc func gotoMediaPreview(_ sender: UIView) {
        delegate?.outboundMsgViewCell(self, previewMediaAt: mediaImageView.currentPage, withDelegate: mediaImageView)
    }

    @objc func gotoMsgInfo(_ recognizer: UILongPressGestureRecognizer) {
        guard let messageID = messageID else { return }
        guard let bubbleWrapperFirstSubview = bubbleWrapper.subviews.first else { return }

        if (recognizer.state == .began) {
            UIView.animate(withDuration: 0.5, animations: {
                bubbleWrapperFirstSubview.backgroundColor = .systemGray4
            })

            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            delegate?.outboundMsgViewCell(self, didLongPressOn: messageID)
        } else if (recognizer.state == .ended || recognizer.state == .cancelled) {
            UIView.animate(withDuration: 3.0, animations: {
                bubbleWrapperFirstSubview.backgroundColor = UIColor.chatOwnBubbleBg
            })
        }
    }
}

extension OutboundMsgViewCell: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        voiceNoteTimeLabel.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
        guard completed else { return }
        guard let messageID = messageID else { return }
        delegate?.outboundMsgViewCell(self, didCompleteVoiceNote: messageID)
    }
}

// MARK: UIGestureRecognizer Delegates
extension OutboundMsgViewCell {

    // used for swiping to reply
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity: CGPoint = panGestureRecognizer.velocity(in: bubbleRow)
        if velocity.x < 0 { return false }
        return abs(Float(velocity.x)) > abs(Float(velocity.y))
    }
}
