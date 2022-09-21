//
//  TextComposerView.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 25.07.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

protocol TextComposerDelegate: ContentTextViewDelegate {
    func textComposer(_ textComposerView: TextComposerView, didUpdate data: LinkPreviewData?, andImage image: UIImage?)
    func textComposer(_ textComposerView: TextComposerView, didSelect mention: MentionableUser)
    func textComposerDidTapPreviewLink(_ textComposerView: TextComposerView)
}

class TextComposerView: UIStackView {

    weak var delegate: TextComposerDelegate? {
        didSet {
            textView.delegate = delegate
        }
    }

    private lazy var mentionPickerView: HorizontalMentionPickerView = {
        let picker = HorizontalMentionPickerView(config: .composer, avatarStore: MainAppContext.shared.avatarStore)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        picker.clipsToBounds = true
        picker.isHidden = true
        picker.didSelectItem = { [weak self] item in
            guard let self = self else { return }

            self.textView.accept(mention: item)
            self.delegate?.textComposer(self, didSelect: item)
        }

        return picker
    }()

    private lazy var cardView: UIView = {
        let stackView = UIStackView(arrangedSubviews: [textView, linkPreviewView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)

        let cardView = UIView()
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = ComposerConstants.backgroundRadius
        cardView.layer.shadowOpacity = 1
        cardView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        stackView.insertSubview(cardView, at: 0)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: stackView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
        ])

        return stackView
    }()

    private lazy var textView: ContentTextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = ComposerConstants.getFontSize(textSize: 0, isPostWithMedia: false)
        textView.tintColor = .systemBlue
        textView.textColor = ComposerConstants.textViewTextColor
        textView.placeholder = Localizations.writePost
        textView.placeholderColor = .label.withAlphaComponent(0.4)

        NSLayoutConstraint.activate([
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])

        return textView
    }()

    private lazy var linkPreviewView: PostComposerLinkPreviewView = {
        let linkPreviewView = PostComposerLinkPreviewView() { [weak self] resetLink, linkPreviewData, linkPreviewImage in
            guard let self = self else { return }

            self.linkPreviewView.isHidden = resetLink
            self.delegate?.textComposer(self, didUpdate: linkPreviewData, andImage: linkPreviewImage)
        }

        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        linkPreviewView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        linkPreviewView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(previewTappedAction(sender:))))

        return linkPreviewView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 10

        addArrangedSubview(mentionPickerView)
        addArrangedSubview(cardView)
    }

    public func update(with input: MentionInput, mentionables: [MentionableUser]) {
        textView.text = input.text
        textView.mentions = input.mentions
        textView.font = ComposerConstants.getFontSize(textSize: input.text.count, isPostWithMedia: false)

        updateLinkPreviewViewIfNecessary(with: input)
        updateMentionPicker(with: mentionables)
    }
}

// MARK: Link Preview
extension TextComposerView {
    private func updateLinkPreviewViewIfNecessary(with input: MentionInput) {
        if let url = detectLink(text: input.text) {
            linkPreviewView.updateLink(url: url)
            linkPreviewView.isHidden = false
        } else {
            linkPreviewView.isHidden = true
        }
    }

    private func detectLink(text: String) -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = linkDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let url = text[range]
            if let url = URL(string: String(url)) {
                // We only care about the first link
                return url
            }
        }

        return nil
    }

    @objc func previewTappedAction(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            delegate?.textComposerDidTapPreviewLink(self)
        }
    }
}

// MARK: Mentions
extension TextComposerView {
    private func updateMentionPicker(with mentionables: [MentionableUser]) {
        // don't animate the initial load
        let shouldShow = !mentionables.isEmpty
        let shouldAnimate = mentionPickerView.isHidden != shouldShow
        mentionPickerView.updateItems(mentionables, animated: shouldAnimate)

        mentionPickerView.isHidden = !shouldShow
    }
}
