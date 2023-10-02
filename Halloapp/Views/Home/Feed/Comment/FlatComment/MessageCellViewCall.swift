//
//  MessageCellViewCall.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

struct ChatCallData: Hashable {
    var userID: UserID
    var timestamp: Date?
    var duration: TimeInterval
    var wasSuccessful: Bool
    var wasIncoming: Bool
    var type: CallType
    var isMissedCall: Bool
}

protocol MessageCellViewCallDelegate: AnyObject {
    func chatCallView(_ callView: MessageCellViewCall, didTapCallButtonWithData callData: ChatCallData)
}

class MessageCellViewCall: UICollectionViewCell {

    private var callData: ChatCallData?
    weak var delegate: MessageCellViewCallDelegate?

    static var elementKind: String {
        return String(describing: MessageCellViewCall.self)
    }

    private static var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var callEventLabel: UILabel = {
        let callEventLabel = UILabel()
        callEventLabel.font = .scaledSystemFont(ofSize: 12, weight: .medium)
        callEventLabel.textColor = UIColor.timeHeaderText
        callEventLabel.textAlignment = .natural
        callEventLabel.translatesAutoresizingMaskIntoConstraints = false
        callEventLabel.numberOfLines = 1
        return callEventLabel
    }()

    private lazy var callEventView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ callEventLabel])
        view.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let subView = UIView(frame: view.bounds)
        subView.backgroundColor = UIColor.timeHeaderBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = false
        subView.translatesAutoresizingMaskIntoConstraints = false
        subView.layer.borderWidth = 0
        subView.layer.borderColor = UIColor.black.withAlphaComponent(0.18).cgColor
        subView.layer.shadowColor = UIColor.black.cgColor
        subView.layer.shadowOpacity = 0.08
        subView.layer.shadowOffset = CGSize(width: 0, height: 1)
        subView.layer.shadowRadius = 0

        view.insertSubview(subView, at: 0)
        subView.constrain(to: view)
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.preservesSuperviewLayoutMargins = true
        self.addSubview(callEventView)
        NSLayoutConstraint.activate([
            callEventView.centerXAnchor.constraint(equalTo: centerXAnchor),
            callEventView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            callEventView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapMissedCallCell))
        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(tapGesture)
    }

    func configure(_ callData: ChatCallData) {
        self.callData = callData
        let showMissedCall = callData.wasIncoming && !callData.wasSuccessful
        let titleString: NSMutableAttributedString
        
        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 15)
        let messagefont = UIFont.scaledSystemFont(ofSize: 12, weight: .medium)
        let name = UserProfile.find(with: callData.userID, in: MainAppContext.shared.mainDataStore.viewContext)?.name ?? ""

        // Call icon
        switch callData.type {
        case .audio:
            let messageString = showMissedCall ? Localizations.voiceCallMissed : (callData.wasIncoming ? Localizations.incomingCall(name: name) : Localizations.outgoingCall(name: name))
            titleString = NSMutableAttributedString(
                string: messageString,
                attributes: [.font: messagefont, .foregroundColor: UIColor.timeHeaderText])
            
            if showMissedCall {
                titleString.addAttribute(.link, value: "", range: titleString.utf16Extent)
            }
            let phoneIcon = UIImage(systemName: "phone.fill", withConfiguration: iconConfiguration)
            if let phoneIcon = phoneIcon {
                let icon = showMissedCall ? phoneIcon.withTintColor(.systemRed) : phoneIcon.withTintColor(.timeHeaderText)
                titleString.insert(getIconAttributedString(icon), at: 0)
            }
        case .video:
            let messageString = showMissedCall ? Localizations.videoCallMissed : (callData.wasIncoming ? Localizations.incomingCall(name: name) : Localizations.outgoingCall(name: name))
            titleString = NSMutableAttributedString(
                string: messageString,
                attributes: [.font: messagefont, .foregroundColor: UIColor.timeHeaderText])
            if showMissedCall {
                titleString.addAttribute(.link, value: "", range: titleString.utf16Extent)
            }
            let videoIcon = UIImage(systemName: "video.fill", withConfiguration: iconConfiguration)
            if let videoIcon = videoIcon {
                let icon = showMissedCall ? videoIcon.withTintColor(.systemRed) : videoIcon.withTintColor(.timeHeaderText)
                titleString.insert(getIconAttributedString(icon), at: 0)
            }
        }
        // Call duration
        if let duration = durationString(callData.duration) {
            titleString.append(NSAttributedString(
                string: " - \(duration) ",
                attributes: [.font: messagefont, .foregroundColor: UIColor.timeHeaderText]))
        }
        // Call timestamp
        if let timeStamp = callData.timestamp?.chatDisplayTimestamp(Date()) {
            titleString.append(NSAttributedString(
                string: "  " + timeStamp,
                attributes: [.font: UIFont.scaledSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.chatTime] ))
        }
        callEventLabel.attributedText = titleString
    }

    private func getIconAttributedString(_ icon: UIImage) -> NSAttributedString {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let iconFont = UIFont(descriptor: fontDescriptor, size: 15)
        let imageSize = icon.size
        let iconAttachment = NSTextAttachment(image: icon)
        let scale = iconFont.capHeight / imageSize.height
        iconAttachment.bounds.size = CGSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
        let attrText = NSMutableAttributedString(attachment: iconAttachment)
        attrText.append(NSAttributedString(string: "   "))
        return attrText
    }

    private func durationString(_ timeInterval: TimeInterval) -> String? {
        guard timeInterval > 0 else {
            return nil
        }
        return MessageCellViewCall.durationFormatter.string(from: timeInterval)
    }

    @objc private func didTapMissedCallCell() {
        guard let callData = callData else {
            DDLogError("MessageCellViewCall/didTapMissedCallCell/error [missing-call-data]")
            return
        }
        guard callData.wasIncoming && !callData.wasSuccessful else { return }
        delegate?.chatCallView(self, didTapCallButtonWithData: callData)
    }
}
