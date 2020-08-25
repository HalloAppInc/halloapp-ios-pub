//
//  InputTextView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreServices
import UIKit

protocol InputTextViewDelegate: AnyObject {

    func maximumHeight(for inputTextView: InputTextView) -> CGFloat
    func inputTextView(_ inputTextView: InputTextView, needsHeightChangedTo newHeight: CGFloat)

    // MARK: UITextViewDelegate Replacements

    func inputTextViewShouldBeginEditing(_ inputTextView: InputTextView) -> Bool
    func inputTextViewDidBeginEditing(_ inputTextView: InputTextView)
    func inputTextViewShouldEndEditing(_ inputTextView: InputTextView) -> Bool
    func inputTextViewDidEndEditing(_ inputTextView: InputTextView)
    func inputTextViewDidChange(_ inputTextView: InputTextView)
    func inputTextViewDidChangeSelection(_ inputTextView: InputTextView)
    func inputTextView(_ inputTextView: InputTextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
}

class InputTextView: UITextView, UITextViewDelegate {

    weak var inputTextViewDelegate: InputTextViewDelegate?

    var scrollIndicatorsShown: Bool = false
    private var lastReportedHeight: CGFloat
    private(set) var mentions = MentionRangeMap()

    var mentionInput: MentionInput {
        MentionInput(text: text, mentions: mentions, selectedRange: selectedRange)
    }

    required init(frame: CGRect) {
        lastReportedHeight = frame.height

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: frame.size.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        super.init(frame: frame, textContainer: textContainer)

        self.delegate = self
        self.showsHorizontalScrollIndicator = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addMention(name: String, userID: UserID, in range: NSRange) {
        var input = mentionInput
        input.addMention(name: name, userID: userID, in: range)
        update(from: input)
    }

    func resetMentions() {
        mentions.removeAll()
    }

    // MARK: Size Calculations

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let height = self.bestHeight(for: self.attributedText)
        return CGSize(width: size.width, height: min(size.height, height))
    }

    private func bestHeightForCurrentText() -> CGFloat {
        return self.bestHeight(for: self.attributedText)
    }

    private func bestHeightForCurrentText(in size: CGSize) -> CGFloat {
        return self.bestHeight(for: self.attributedText, in: size)
    }

    func bestHeight(for text: String?) -> CGFloat {
        return self.bestHeight(for: text, in: CGSize(width: self.bounds.size.width, height: 1e6))
    }

    private func bestHeight(for text: String?, in size: CGSize, textAlignment: NSTextAlignment = .natural) -> CGFloat {
        var attributedText: NSAttributedString?
        if !(text ?? "").isEmpty {
            let font = self.font ?? UIFont.preferredFont(forTextStyle: .body)
            let style = NSMutableParagraphStyle()
            style.alignment = textAlignment;
            attributedText = NSAttributedString(string: text!, attributes: [ .font: font, .paragraphStyle: style ])
        }
        return self.bestHeight(for: attributedText, in: size)
    }

    private func bestHeight(for attributedText: NSAttributedString?) -> CGFloat {
        return self.bestHeight(for: attributedText, in: self.textContainer.size)
    }

    private lazy var tc: NSTextContainer = NSTextContainer(size: .zero)

    private lazy var lm: NSLayoutManager = {
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(self.tc)
        return layoutManager
    }()

    private lazy var ts: NSTextStorage = {
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(self.lm)
        return textStorage
    }()

    private func bestHeight(for attributedText: NSAttributedString?, in size: CGSize) -> CGFloat {
        var attrString: NSAttributedString
        if attributedText == nil || attributedText!.length == 0 {
            let font = self.font ?? UIFont.preferredFont(forTextStyle: .body)
            attrString = NSAttributedString(string: "M", attributes: [ .font: font ] )
        } else {
            attrString = attributedText!
        }

        self.ts.setAttributedString(attrString)
        self.tc.size = size
        self.tc.lineFragmentPadding = self.textContainer.lineFragmentPadding
        self.tc.lineBreakMode = self.textContainer.lineBreakMode
        let textRect = self.lm.usedRect(for: self.tc).integral
        let textViewHeight = (textRect.maxY + self.textContainerInset.top + self.textContainerInset.bottom).rounded()
        return textViewHeight
    }

    // MARK: UITextView

    override var contentSize: CGSize {
        didSet {
            if oldValue != contentSize {
                self.updateTextViewMetrics()
            }
        }
    }

    override var frame: CGRect {
        didSet {
            if self.isFirstResponder {
                // Delay updating the content inset until after the scrolling has stopped.
                self.scrollToVisibleRange(afterDelay: 0.25)
            }
        }
    }

    override var font: UIFont? {
        didSet {
            self.updateTextViewMetrics()
        }
    }

    override var text: String! {
        didSet {
            self.updateTextViewMetrics()
        }
    }

    override var attributedText: NSAttributedString! {
        didSet {
            self.updateTextViewMetrics()
        }
    }

    private func updateTextViewMetrics() {
        let maxHeight = self.inputTextViewDelegate?.maximumHeight(for: self) ?? CGFloat.greatestFiniteMagnitude

        let contentHeight = self.bestHeightForCurrentText()
        let newHeight = min(contentHeight, maxHeight)
        if newHeight != self.lastReportedHeight {
            self.lastReportedHeight = newHeight
            self.inputTextViewDelegate?.inputTextView(self, needsHeightChangedTo: newHeight)
        }
        if newHeight >= maxHeight {
            if !self.scrollIndicatorsShown {
                DispatchQueue.main.async {
                    // Delay flashing to ensure that the scroll indicators are positioned correctly.
                    self.flashScrollIndicators()
                }
                self.scrollIndicatorsShown = true
            }
            // Don't change contentOffset during scrolling -- contentSize changes here could be due to lazy glyph layout.
            if !self.isDragging && !self.isDecelerating {
                self.scrollToVisibleRange(afterDelay: 0)
            }
        } else {
            self.scrollIndicatorsShown = false
        }
    }

    private func scrollToVisibleRange(afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if self.selectedRange.location == self.text.count {
                self.scrollToBottom(animated: false)
            } else {
                self.scrollRangeToVisible(self.selectedRange)
            }
        }
    }

    private func scrollToBottom(animated: Bool) {
        let point = CGPoint(x: 0, y: self.contentSize.height - self.bounds.size.height + self.contentInset.bottom)
        self.setContentOffset(point, animated: animated)
    }

    // MARK: UITextViewDelegate Proxy

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        guard self.inputTextViewDelegate != nil else { return false }
        return self.inputTextViewDelegate!.inputTextViewShouldBeginEditing(self)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.inputTextViewDelegate?.inputTextViewDidBeginEditing(self)
    }

    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        guard self.inputTextViewDelegate != nil else { return true }
        return self.inputTextViewDelegate!.inputTextViewShouldEndEditing(self)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.inputTextViewDelegate?.inputTextViewDidEndEditing(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        self.inputTextViewDelegate?.inputTextViewDidChange(self)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        self.inputTextViewDelegate?.inputTextViewDidChangeSelection(self)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {

        var mentionInput = MentionInput(text: textView.text, mentions: mentions, selectedRange: selectedRange)

        // Treat mentions atomically (editing any part of the mention should remove the whole thing)
        let rangeIncludingImpactedMentions = mentionInput
            .impactedMentionRanges(in: range)
            .reduce(range) { range, mention in NSUnionRange(range, mention) }

        guard inputTextViewDelegate?.inputTextView(self, shouldChangeTextIn: rangeIncludingImpactedMentions, replacementText: text) ?? true else {
            return false
        }

        mentionInput.changeText(in: rangeIncludingImpactedMentions, to: text)

        if range == rangeIncludingImpactedMentions {
            // Update mentions and return true so UITextView can update text without breaking IME
            mentions = mentionInput.mentions
            return true
        } else {
            // Update content ourselves and return false so UITextView doesn't issue conflicting update
            update(from: mentionInput)
            return false
        }
    }

    /// Update all fields to match the input struct. This will interfere with active IME (e.g. Japanese kanji entry)
    private func update(from mentionInput: MentionInput) {
        self.text = mentionInput.text
        self.mentions = mentionInput.mentions
        self.selectedRange = mentionInput.selectedRange
        self.inputTextViewDelegate?.inputTextViewDidChange(self)
    }
}
