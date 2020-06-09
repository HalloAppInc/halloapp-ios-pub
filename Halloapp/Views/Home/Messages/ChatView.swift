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
    func chatView(_ chatView: ChatView, previewType: MediaPreviewController.PreviewType, mediaIndex: Int)
}

class ChatView: UIView, ChatMediaSliderDelegate {
    
    var currentPage: Int = 0
    
    func chatMediaSlider(_ view: ChatMediaSlider, currentPage: Int) {
        self.currentPage = currentPage
        MainAppContext.shared.chatData.currentPage = self.currentPage
    }
    
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
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.gotoQuotedPreview(_:)))
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
                        sliderMediaArr.append(SliderMedia(image: image, type: med.type))
                    } else {
                        sliderMediaArr.append(SliderMedia(image: nil, type: med.type))
                    }
                } else if med.type == .video {
                    // TODO: store thumbnails cause it's too slow to generate on the fly
                    if let image = self.videoPreviewImage(url: fileURL) {
                        sliderMediaArr.append(SliderMedia(image: image, type: med.type))
                    } else {
                        sliderMediaArr.append(SliderMedia(image: nil, type: med.type))
                    }
                }
            
            }
            
            if !media.isEmpty {

                self.mediaImageView.configure(with: sliderMediaArr, width: preferredSize.width, height: preferredSize.height, currentPage: self.currentPage)

                NSLayoutConstraint(item: self.mediaImageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.width).isActive = true
                NSLayoutConstraint(item: self.mediaImageView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: preferredSize.height).isActive = true

                self.mediaImageView.isHidden = false

                self.mediaRow.isHidden = false
                
                self.mainView.insertArrangedSubview(self.mediaRow, at: 1)
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
                
        self.mediaImageView.reset()
        self.mediaImageView.removeConstraints(mediaImageView.constraints)
        self.mediaRow.isHidden = true
        self.mediaImageView.isHidden = true
        
        self.textRow.isHidden = false
        self.textView.isHidden = false
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
        self.delegate?.chatView(self, previewType: .quoted, mediaIndex: 0)
    }
    
    @objc func gotoMediaPreview(_ sender: UIView) {
        self.delegate?.chatView(self, previewType: .media, mediaIndex: self.mediaImageView.currentPage)
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

