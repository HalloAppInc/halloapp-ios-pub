//
//  MessageComposerView.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit
import SwiftUI

class MessageComposerView: UIViewController, UITextViewDelegate, MessageComposerBodyViewDelegate {

    var sendTo: String?
    var mediaItemsToPost: [PendingMedia]?
    private let imageServer = ImageServer()
    
    init(sendTo: String, mediaItemsToPost: [PendingMedia]) {
        self.sendTo = sendTo
        self.mediaItemsToPost = mediaItemsToPost
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
        
    private lazy var chatMediaSlider: ChatMediaSlider = {
        let chatMediaSlider = ChatMediaSlider()
        return chatMediaSlider
    }()
    
    private lazy var messageComposerBodyView: MessageComposerBodyView = {
        let messageComposerBodyView = MessageComposerBodyView()
        messageComposerBodyView.translatesAutoresizingMaskIntoConstraints = false
        messageComposerBodyView.delegate = self
        return messageComposerBodyView
    }()
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        let vSpacer = UIView()
        vSpacer.translatesAutoresizingMaskIntoConstraints = false
        vSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        vSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        
        let vStack = UIStackView(arrangedSubviews: [ self.messageComposerBodyView, vSpacer ])
        if let media = self.mediaItemsToPost {
            self.messageComposerBodyView.update(pendingMedia: media)
        }

        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.alignment = .fill

        self.view.addSubview(vStack)
//        self.view.backgroundColor = UIColor.red
        
        vStack.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        vStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard(_:)))
        self.view.addGestureRecognizer(tapGesture)
    }
     
     override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let media = self.mediaItemsToPost {
            self.imageServer.upload(media) { (allUploadsSuccessful) in
                if allUploadsSuccessful {
                    self.messageComposerBodyView.enableSendButton()
                }
            }
        }
    }
    
    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        self.messageComposerBodyView.hideKeyboard()
    }
    
    func messageComposerBodyView(_ view: MessageComposerBodyView) {
        self.dismiss(animated: false)
    }
    
    func messageComposerBodyView(_ view: MessageComposerBodyView, wantsToSend text: String) {
        guard let sendTo = self.sendTo else { return }
        guard let mediaToSend = self.mediaItemsToPost else { return }
        
        MainAppContext.shared.chatData.sendMessage(toUserId: sendTo, text: text, media: mediaToSend, feedPostId: "", feedPostMediaIndex: 0)

        self.dismiss(animated: false)
    }
    
}

protocol MessageComposerBodyViewDelegate: AnyObject {
    func messageComposerBodyView(_ inputView: MessageComposerBodyView)
    func messageComposerBodyView(_ inputView: MessageComposerBodyView, wantsToSend text: String)
}

class MessageComposerBodyView: UIView, UITextViewDelegate {

    weak var delegate: MessageComposerBodyViewDelegate?
    
    private var placeholderText = "Add a caption"
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder){
        super.init(coder: aDecoder)
        setup()
    }

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = true
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 0, right: 0)
        button.addTarget(self, action: #selector(self.cancelButtonClicked), for: .touchUpInside)
        button.setTitleColor(UIColor.systemGray, for: .normal)
        button.setTitle("Cancel", for: .normal)
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
        textView.backgroundColor = UIColor.clear
        textView.delegate = self
        textView.textContainerInset.left = 8
        textView.textContainerInset.right = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
        
    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
//        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 0, right: 0)
        button.addTarget(self, action: #selector(self.sendButtonClicked), for: .touchUpInside)
        button.setTitleColor(UIColor.link, for: .normal)
        button.setTitleColor(UIColor.systemGray, for: .disabled)
        button.setTitle("Send", for: .normal)
        button.tintColor = UIColor.link
        button.titleLabel?.tintColor = UIColor.link
        return button
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
                

//        let imageSize: CGFloat = 200.0
//        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
//        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true
        
        let textViewContainer = UIView()
        textViewContainer.backgroundColor = UIColor.white
        textViewContainer.translatesAutoresizingMaskIntoConstraints = false
        textViewContainer.addSubview(self.textView)
        self.textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true
        let textViewHeight = round(2 * self.textView.font!.lineHeight)
        self.textView.addConstraint(NSLayoutConstraint(item: self.textView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: textViewHeight))
        
        let vSpacer = UIView()
        vSpacer.translatesAutoresizingMaskIntoConstraints = false
        vSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        vSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        
        
        let vStack = UIStackView(arrangedSubviews: [ hStack, self.chatMediaSlider, textViewContainer, self.sendButton, vSpacer ])
        
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
        

        textViewContainer.widthAnchor.constraint(equalTo: vStack.widthAnchor, multiplier: 0.8).isActive = true
        
        setPlaceholderText()
    }

    func update(pendingMedia: [PendingMedia]) {

        var sliderMediaArr: [SliderMedia] = []

        for med in pendingMedia {
            
            let type = med.type == .image ? ChatMessageMediaType.image : ChatMessageMediaType.video
            
            if med.type == .image {
                if let image = med.image {
                    
                    sliderMediaArr.append(SliderMedia(image: image, type: type))
                }
            } else if med.type == .video {

                if let videoURL = med.videoURL {
                    if let image = VideoUtils().videoPreviewImage(url: videoURL) {
                        sliderMediaArr.append(SliderMedia(image: image, type: type))
                    }
                }
          
            }
        }
        
        if !pendingMedia.isEmpty {
            
            let width: CGFloat = UIScreen.main.bounds.width * 0.8
            let height: CGFloat = UIScreen.main.bounds.height * 0.2

            self.chatMediaSlider.configure(with: sliderMediaArr, width: width, height: height, currentPage: 0)

            NSLayoutConstraint(item: self.chatMediaSlider, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: width).isActive = true
            NSLayoutConstraint(item: self.chatMediaSlider, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: height).isActive = true

            self.chatMediaSlider.isHidden = false

        }

    }
    
    func enableSendButton() {
        self.sendButton.isEnabled = true
    }
    
    // MARK: Text view
    
    var text: String {
        get {
            return self.textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        set {
            self.textView.text = newValue
            self.textViewDidChange(self.textView)
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
    }
    
    @objc func cancelButtonClicked() {
        self.delegate?.messageComposerBodyView(self)
    }
    
    @objc func sendButtonClicked() {
        var textToSend = self.text
        if self.textView.tag == 0 {
            textToSend = ""
        }
        self.delegate?.messageComposerBodyView(self, wantsToSend: textToSend)
    }
    
    private func setPlaceholderText() {
        if self.textView.text.isEmpty {
            self.textView.text = placeholderText
            self.textView.textColor = UIColor.systemGray3
            self.textView.tag = 0
        }
    }
    
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if (textView.tag == 0){
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
