//
//  ChatCallCell.swift
//  HalloApp
//
//  Created by Garrett on 1/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import UIKit

final class ChatCallCell: UITableViewCell {
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(callView)
        backgroundColor = .feedBackground
        callView.translatesAutoresizingMaskIntoConstraints = false
        callView.constrainMargins([.top, .bottom], to: contentView)
        NSLayoutConstraint.activate([
            callView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
            callView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ callData: ChatCallData) {
        callView.configure(callData)
        if callData.wasIncoming {
            callViewAlignmentConstraint = callView.constrainMargin(anchor: .leading, to: contentView)
        } else {
            callViewAlignmentConstraint = callView.constrainMargin(anchor: .trailing, to: contentView)
        }
    }

    override func prepareForReuse() {
        callViewAlignmentConstraint?.isActive = false
    }

    let callView = ChatCallView()
    var callViewAlignmentConstraint: NSLayoutConstraint?

    var delegate: ChatCallViewDelegate? {
        get { callView.delegate }
        set { callView.delegate = newValue }
    }
}

protocol ChatCallViewDelegate: AnyObject {
    func chatCallView(_ callView: ChatCallView, didTapCallButtonWithData callData: ChatCallData)
}

final class ChatCallView: UIView {

    init() {
        super.init(frame: .zero)
        layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        addSubview(bubbleView)
        addSubview(primaryLabel)
        addSubview(timeLabel)
        addSubview(callButton)

        bubbleView.constrain(to: self)
        primaryLabel.constrainMargins([.top, .leading], to: self)
        timeLabel.topAnchor.constraint(equalTo: primaryLabel.bottomAnchor, constant: 4).isActive = true
        timeLabel.constrainMargins([.leading, .bottom], to: self)
        timeLabel.constrain([.trailing], to: primaryLabel)
        callButton.constrainMargins([.centerY, .trailing], to: self)
        callButton.leadingAnchor.constraint(equalTo: primaryLabel.trailingAnchor, constant: 24).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ callData: ChatCallData) {
        let showMissedCall = callData.wasIncoming && !callData.wasSuccessful
        let titleString = NSMutableAttributedString(
            string: showMissedCall ? Localizations.voiceCallMissed : Localizations.voiceCall,
            attributes: [.font: UIFont.systemFont(forTextStyle: .subheadline, weight: .bold)])
        if let duration = durationString(callData.duration) {
            titleString.append(NSAttributedString(
                string: " \(duration)",
                attributes: [.font: UIFont.systemFont(forTextStyle: .subheadline)]))
        }
        bubbleView.backgroundColor = callData.wasIncoming ? .secondarySystemGroupedBackground : .chatOwnBubbleBg
        primaryLabel.attributedText = titleString
        timeLabel.text = callData.timestamp?.chatTimestamp(Date())
        callButton.tintColor = showMissedCall ? .systemRed : .systemBlue
        self.callData = callData
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        callButton.layer.cornerRadius = callButton.bounds.height / 2
    }

    weak var delegate: ChatCallViewDelegate?

    // MARK: Private

    private var callData: ChatCallData?

    private lazy var bubbleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        return view
    }()
    private lazy var primaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .subheadline)
        label.textColor = .label
        return label
    }()
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }()
    private lazy var callButton: UIControl = {
        let button = UIButton(type: .system)
        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 13)
        let phoneIcon = UIImage(systemName: "phone.fill", withConfiguration: iconConfiguration)
        button.setTitle(Localizations.buttonCall, for: .normal)
        button.titleLabel?.font = .systemFont(forTextStyle: .subheadline, weight: .bold)
        button.setImage(phoneIcon, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setBackgroundColor(.feedBackground, for: .normal)
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(didTapCallButton), for: .touchUpInside)
        let extraImageSpacing: CGFloat = 3
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16 + extraImageSpacing)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: extraImageSpacing, bottom: 0, right: -extraImageSpacing)
        return button
    }()

    @objc
    private func didTapCallButton() {
        guard let callData = callData else {
            DDLogError("ChatVallView/didTapCallButton/error [missing-call-data]")
            return
        }
        delegate?.chatCallView(self, didTapCallButtonWithData: callData)
    }

    private func durationString(_ timeInterval: TimeInterval) -> String? {
        guard timeInterval > 0 else {
            return nil
        }
        return Self.durationFormatter.string(from: timeInterval)
    }

    private static var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

extension Localizations {
    static var voiceCall: String {
        NSLocalizedString("call.history.voice.call", value: "Voice call", comment: "Title for call history event. Appears next to details of a successful call.")
    }

    static var voiceCallMissed: String {
        NSLocalizedString("call.history.voice.call.missed", value: "Missed voice call", comment: "Title for call history event. Appears next to details of a missed call.")
    }
}
