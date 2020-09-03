//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Core
import UIKit

protocol IncomingMsgViewDelegate: AnyObject {
    func incomingMsgView(_ incomingMsgView: IncomingMsgView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int)
}

class IncomingMsgView: UIView, ChatMediaSliderDelegate {
    var currentPage: Int = 0

    func chatMediaSlider(_ view: ChatMediaSlider, currentPage: Int) {
        self.currentPage = currentPage
        MainAppContext.shared.chatData.currentPage = self.currentPage
    }
    
    weak var delegate: IncomingMsgViewDelegate?
    
    // MARK: Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        self.backgroundColor = .clear
        self.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        self.addSubview(mainView)
        
        self.mainView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        self.mainView.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        self.mainView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        self.mainView.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.bubbleRow, self.timeRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.alignment = .leading
        view.spacing = 0
        
        return view
    }()
    
    private lazy var bubbleRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.nameRow, self.quotedRow, self.textRow ])
        view.axis = .vertical
        view.spacing = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .white
        subView.layer.cornerRadius = 20
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()
    
    // MARK: Name Row
    private lazy var nameRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.nameLabel ])
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
        let view = UIStackView(arrangedSubviews: [ self.timeLabel ])
        view.axis = .vertical
        view.spacing = 0
        view.layoutMargins = UIEdgeInsets(top: 1, left: 15, bottom: 0, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
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
    
    // MARK: Quoted Row
    
    private lazy var quotedRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quotedTextVStack, self.quotedImageView ])
        view.axis = .horizontal
        view.spacing = 10

        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 20
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.lavaOrange.withAlphaComponent(0.1)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        view.insertSubview(subView, at: 0)
        view.isHidden = true

        return view
    }()
    
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
    
    private lazy var mediaImageView: ChatMediaSlider = {
        let view = ChatMediaSlider()
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true

//        view.layer.shadowColor = UIColor.black.cgColor
//        view.layer.shadowOpacity = 1
//        view.layer.shadowOffset = .zero
//        view.layer.shadowRadius = 10
        
        view.isHidden = true
        
        view.delegate = self
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var mediaRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.mediaImageView ])
        view.axis = .horizontal
        view.isLayoutMarginsRelativeArrangement = true
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.spacing = 5
        view.isHidden = false
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoMediaPreview(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        return view
    }()
    
    private lazy var textRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.textView ])
        view.axis = .horizontal
        view.spacing = 1
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isUserInteractionEnabled = true
        textView.dataDetectorTypes = .link
        textView.textContainerInset = UIEdgeInsets.zero
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.tintColor = UIColor.link
        textView.textColor = UIColor.darkText
        return textView
    }()

    // MARK: Updates

    func updateWithChatMessage(with chatMessage: ChatMessage, isPreviousMsgSameSender: Bool) {
        let isQuotedMessage = updateQuoted(chatQuoted: chatMessage.quoted, feedPostMediaIndex: Int(chatMessage.feedPostMediaIndex))
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isQuotedMessage: isQuotedMessage,
                   text: chatMessage.text,
                   media: chatMessage.media,
                   timestamp: chatMessage.timestamp)
    }
    
    func updateWithChatGroupMessage(with chatGroupMessage: ChatGroupMessage, isPreviousMsgSameSender: Bool) {
        nameLabel.text = AppContext.shared.contactStore.fullName(for: chatGroupMessage.userId)
        if nameLabel.text == "Unknown Contact" {
            nameLabel.text = "~\(chatGroupMessage.name ?? "Unknown Contact")"
        }
        nameLabel.textColor = getNameColor(for: chatGroupMessage.userId, name: nameLabel.text ?? "", groupId: chatGroupMessage.groupId)
        nameRow.isHidden = false
        
        if (chatGroupMessage.orderedMedia.count == 0) {
            textRow.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        }
        
        updateWith(isPreviousMsgSameSender: isPreviousMsgSameSender,
                   isQuotedMessage: false,
                   text: chatGroupMessage.text,
                   media: chatGroupMessage.media,
                   timestamp: chatGroupMessage.timestamp)
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
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-image/fileURL \(fileURL)")
                        }
                    } else if med.type == .video {
                        if let image = VideoUtils.videoPreviewImage(url: fileURL, size: nil) {
                            self.quotedImageView.image = image
                        } else {
                            DDLogError("IncomingMsgView/quoted/no-video-preview/fileURL \(fileURL)")
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
        
        // text
        let text = text ?? ""
        if text.count <= 3 && text.containsOnlyEmoji {
            self.textView.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        self.textView.text = text
        
        // media
        if let media = media {
            
            if self.textView.text == "" {
                self.textView.isHidden = true
                self.textRow.isHidden = true
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
                
                self.bubbleRow.insertArrangedSubview(self.mediaRow, at: 1)
                
                NSLayoutConstraint(item: self.mediaImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.width).isActive = true
                NSLayoutConstraint(item: self.mediaImageView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.height).isActive = true
                
                self.mediaImageView.configure(with: sliderMediaArr, size: preferredSize)
                
                self.mediaImageView.isHidden = false
                
                if (isQuotedMessage) {
                    self.mediaRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
                }
                self.mediaRow.isHidden = false

            }
        }
        
        // time
        if let timestamp = timestamp {
            self.timeLabel.text = timestamp.chatTimestamp()
        }
    }
    
    func updateMedia(_ sliderMedia: SliderMedia) {
        self.mediaImageView.updateMedia(sliderMedia)
    }
    
    // MARK: reuse
    
    func reset() {
        quotedNameLabel.text = ""
        quotedTextLabel.text = ""
        quotedTextVStack.isHidden = true
        quotedImageView.isHidden = true
        quotedRow.isHidden = true

        mediaImageView.removeConstraints(mediaImageView.constraints)
        mediaImageView.reset()
        mediaRow.isHidden = true
        mediaRow.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        mediaImageView.isHidden = true
        
        textRow.isHidden = false
        textView.isHidden = false
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.text = ""
        
        nameLabel.textColor = .secondaryLabel
        
        timeLabel.text = nil
        
        textRow.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    // MARK: Helpers
    
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
            case 10: return UIColor.systemGray3
            case 11: return UIColor.black
            case 12: return UIColor.brown
            case 13: return UIColor.magenta
            default: return UIColor.secondaryLabel
            }
        }()
        
        return color
    }
    
    @objc func gotoQuotedPreview(_ sender: UIView) {
        delegate?.incomingMsgView(self, previewType: .quoted, mediaIndex: 0)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        delegate?.incomingMsgView(self, previewType: .media, mediaIndex: self.mediaImageView.currentPage)
    }
}


