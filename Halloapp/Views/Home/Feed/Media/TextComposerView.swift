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
        let cardView = UIStackView(arrangedSubviews: [textView, linkPreviewView])
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.axis = .vertical
        cardView.spacing = 8
        cardView.isLayoutMarginsRelativeArrangement = true
        cardView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = ComposerConstants.backgroundRadius
        cardView.layer.shadowOpacity = 1
        cardView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)

        let paddingView = UIView()
        paddingView.translatesAutoresizingMaskIntoConstraints = false
        paddingView.addSubview(cardView)

        NSLayoutConstraint.activate([
            paddingView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: -12),
            paddingView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: 12),
            paddingView.topAnchor.constraint(equalTo: cardView.topAnchor),
            paddingView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        return paddingView
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

        textView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])

        return textView
    }()

    private lazy var placeholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20)
        label.textColor = .label.withAlphaComponent(0.4)

        return label
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

        placeholder.text = Localizations.writePost
    }

    public func update(with input: MentionInput, mentionables: [MentionableUser]) {
        textView.text = input.text
        textView.mentions = input.mentions
        textView.font = ComposerConstants.getFontSize(textSize: input.text.count, isPostWithMedia: false)
        placeholder.isHidden = !input.text.isEmpty

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

private extension Localizations {
    static var writePost: String {
        NSLocalizedString("composer.placeholder.text.post", value: "Write a post", comment: "Placeholder text in text post composer screen.")
    }
}
