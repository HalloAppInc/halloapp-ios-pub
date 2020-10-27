//
//  MessageComposerView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import UIKit
import SwiftUI

protocol MessageComposerViewDelegate: AnyObject {
    func messageComposerView(_ messageComposerView: MessageComposerView, text: String, media: [PendingMedia])
}

class MessageComposerView: UIViewController, UITextViewDelegate {
    
    weak var delegate: MessageComposerViewDelegate?
    
    var mediaItemsToPost: [PendingMedia]
    private let imageServer = ImageServer()
    
    init(mediaItemsToPost: [PendingMedia]) {
        self.mediaItemsToPost = mediaItemsToPost
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private lazy var chatMediaSlider: ChatMediaSlider = {
        let chatMediaSlider = ChatMediaSlider()
        return chatMediaSlider
    }()
    
    private lazy var messageComposerBodyView: MessageComposerBodyView = {
        let messageComposerBodyView = MessageComposerBodyView()
        messageComposerBodyView.translatesAutoresizingMaskIntoConstraints = false
        return messageComposerBodyView
    }()
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let vSpacer = UIView()
        vSpacer.translatesAutoresizingMaskIntoConstraints = false
        vSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        vSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        
        let vStack = UIStackView(arrangedSubviews: [ messageComposerBodyView, vSpacer ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.alignment = .fill
        self.view.addSubview(vStack)

        vStack.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        vStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard(_:)))
        self.view.addGestureRecognizer(tapGesture)

        messageComposerBodyView.update(pendingMedia: mediaItemsToPost)
        messageComposerBodyView.cancelButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        messageComposerBodyView.sendButton.addTarget(self, action: #selector(sendAction), for: .touchUpInside)

        imageServer.prepare(mediaItems: mediaItemsToPost) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.messageComposerBodyView.enableSendButton()
            }
        }
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        self.messageComposerBodyView.hideKeyboard()
    }

    @objc func cancelAction() {
        dismiss(animated: false)
    }
    
    @objc func sendAction() {
        let text = messageComposerBodyView.text
        delegate?.messageComposerView(self, text: text, media: mediaItemsToPost)
        dismiss(animated: false)
    }
    
}

class MessageComposerBodyView: UIView, UITextViewDelegate {
    private var placeholderText = "Add a caption"
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder){
        super.init(coder: aDecoder)
        setup()
    }

    private(set) lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = true
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 0, right: 0)
        button.setTitleColor(UIColor.systemGray, for: .normal)
        button.setTitle(Localizations.buttonCancel, for: .normal)
        button.tintColor = UIColor.systemGray
        return button
    }()
    
    private lazy var chatMediaSlider: ChatMediaSlider = {
        let chatMediaSlider = ChatMediaSlider()
        return chatMediaSlider
    }()
    
    private lazy var contactImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.init(systemName: "person.crop.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = UIColor.systemGray
        return imageView
    }()
    
    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.isScrollEnabled = false
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.delegate = self
        textView.textContainerInset.left = 8
        textView.textContainerInset.right = 8
        textView.tintColor = .lavaOrange
        
        textView.layer.cornerRadius = 10
        textView.clipsToBounds = true
        textView.layer.masksToBounds = true
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
        
    private(set) lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.isEnabled = false
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        button.setTitle("SEND", for: .normal)
        button.setBackgroundColor(.systemGray, for: .disabled)
        button.setBackgroundColor(.lavaOrange, for: .normal)
        button.setTitleColor(.systemGray6, for: .normal)
        button.setTitleColor(.systemGray6, for: .disabled)
        
        button.titleLabel?.tintColor = UIColor.link
        button.layer.cornerRadius = 15
        button.clipsToBounds = true
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        return button
    }()
        
    
    private lazy var textViewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.addSubview(self.textView)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        self.textView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        let textViewHeight = round(2 * self.textView.font!.lineHeight)
        self.textView.addConstraint(NSLayoutConstraint(item: self.textView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: textViewHeight))
        
        return view
    }()
    
    private lazy var textRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ textViewContainer, sendButton ])
        view.axis = .horizontal
        view.alignment = .leading
        view.spacing = 10
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private func setup() {
        self.backgroundColor = UIColor.systemGray6
        
        let hSpacer = UIView()
        hSpacer.translatesAutoresizingMaskIntoConstraints = false
        hSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        hSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)

        let hStack = UIStackView(arrangedSubviews: [ self.cancelButton, hSpacer ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .leading
        hStack.spacing = 10

        let vSpacer = UIView()
        vSpacer.translatesAutoresizingMaskIntoConstraints = false
        vSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        vSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        
        let vStack = UIStackView(arrangedSubviews: [ hStack, chatMediaSlider, textRow, vSpacer ])
        
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.spacing = 10
        
        self.addSubview(vStack)
        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        
        hStack.leadingAnchor.constraint(equalTo: vStack.leadingAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: vStack.trailingAnchor).isActive = true
        
        textViewContainer.widthAnchor.constraint(equalTo: vStack.widthAnchor, multiplier: 0.7).isActive = true
        
        setPlaceholderText()
    }

    func update(pendingMedia: [PendingMedia]) {

        var sliderMediaArr: [SliderMedia] = []

        for med in pendingMedia {
            
            let type = med.type == .image ? ChatMessageMediaType.image : ChatMessageMediaType.video
            
            if med.type == .image {
                if let image = med.image {
                    sliderMediaArr.append(SliderMedia(image: image, type: type, order: med.order))
                }
            } else if med.type == .video {
                if let videoURL = med.videoURL {
                    if let image = VideoUtils.videoPreviewImage(url: videoURL, size: nil) {
                        sliderMediaArr.append(SliderMedia(image: image, type: type, order: med.order))
                    }
                }
            }
        }
        
        if !pendingMedia.isEmpty {
            let width: CGFloat = UIScreen.main.bounds.width * 0.9
            var height: CGFloat = UIScreen.main.bounds.height * 0.2
            let preferredSize = CGSize(width: width, height: height)
            
            chatMediaSlider.configure(with: sliderMediaArr, size: preferredSize)
            
            if pendingMedia.count > 1 {
                height += 25
            }
        
            chatMediaSlider.widthAnchor.constraint(equalToConstant: width).isActive = true
            chatMediaSlider.heightAnchor.constraint(equalToConstant: height).isActive = true

            chatMediaSlider.isHidden = false
        }

    }
    
    func enableSendButton() {
        self.sendButton.isEnabled = true
    }
    
    // MARK: Text view
    
    var text: String {
        get {
            if textView.tag == 0 {
                return ""
            }
            return self.textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        set {
            self.textView.text = newValue
            self.textViewDidChange(self.textView)
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
    }

    private func setPlaceholderText() {
        if self.textView.text.isEmpty {
            self.textView.text = placeholderText
            self.textView.textColor = UIColor.systemGray3
            self.textView.tag = 0
        }
    }
    
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if textView.tag == 0 {
            textView.text = ""
            textView.textColor = UIColor.label
            textView.tag = 1
        }
        return true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        setPlaceholderText()
    }
    
    // MARK: Keyboard
    
    func hideKeyboard() {
        self.textView.resignFirstResponder()
    }
    
}
