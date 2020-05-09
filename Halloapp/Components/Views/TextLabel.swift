//
//  TextLabel.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import UIKit

fileprivate class LayoutManager: NSLayoutManager {

    override func usedRect(for container: NSTextContainer) -> CGRect {
        self.glyphRange(for: container)
        return super.usedRect(for: container)
    }
}

struct AttributedTextLink: Equatable {
    let text: String
    let textCheckingResult: NSTextCheckingResult.CheckingType
    let url: URL?
    var rects: [ CGRect ] = []
}

extension NSTextCheckingResult.CheckingType {
    static let readMoreLink = NSTextCheckingResult.CheckingType(rawValue: 1 << 34)
}

protocol TextLabelDelegate: AnyObject {
    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink)
}

class TextLabel: UILabel {

    weak var delegate: TextLabelDelegate?

    private let textStorage: NSTextStorage
    private let textContainer: NSTextContainer
    private let layoutManager: NSLayoutManager

    override init(frame: CGRect) {
        textContainer = NSTextContainer()
        textContainer.lineFragmentPadding = 0

        layoutManager = LayoutManager()
        layoutManager.usesFontLeading = false
        layoutManager.addTextContainer(textContainer)

        textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        super.init(frame: .zero)

        self.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        textContainer = NSTextContainer()
        textContainer.lineFragmentPadding = 0

        layoutManager = LayoutManager()
        layoutManager.usesFontLeading = false
        layoutManager.addTextContainer(textContainer)

        textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        super.init(coder: coder)

        self.isUserInteractionEnabled = true
    }

    // MARK: UILabel

    override var text: String? {
        didSet {
            self.invalidateTextStorage()
        }
    }

    override var attributedText: NSAttributedString? {
        didSet {
            self.invalidateTextStorage()
        }
    }

    override var font: UIFont! {
        didSet {
            self.invalidateTextStorage()
        }
    }

    override var numberOfLines: Int {
        didSet {
            self.invalidateTextStorage()
        }
    }

    // MARK: Text Metrics & Drawing

    private var textStorageIsValid = false

    private var textRect: CGRect = .zero

    private var lastValidCharacterIndex: Int = NSNotFound // NSNotFound == full range is valid

    private var readMoreLink: AttributedTextLink?

    override var intrinsicContentSize: CGSize {
        get {
            var maxLayoutWidth = self.preferredMaxLayoutWidth
            if maxLayoutWidth == 0 {
                maxLayoutWidth = self.bounds.width
            }
            if maxLayoutWidth == 0 {
                maxLayoutWidth = CGFloat.greatestFiniteMagnitude
            }
            return self.sizeThatFits(CGSize(width: maxLayoutWidth, height: CGFloat.greatestFiniteMagnitude))
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let maxSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        var textSize = self.textBoundingRect(with: maxSize).size
        textSize.width = ceil(textSize.width)
        textSize.height = ceil(textSize.height)
        return textSize
    }

    override func draw(_ rect: CGRect) {
        self.prepareTextStorageIfNeeded()

        // Background for highlighted link
        if let link = self.highlightedLink {
            UIColor.systemGray.withAlphaComponent(0.5).setFill()
            for rect in link.rects {
                let linkRect = rect.integral.inset(by: UIEdgeInsets(top: -2, left: -2, bottom: -2, right: -2))
                let bezierPath = UIBezierPath(roundedRect: linkRect, cornerRadius: 3)
                bezierPath.fill()
            }
        }

        self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
            let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
    }

    private func textBoundingRect(with size: CGSize) -> CGRect {
        self.prepareTextStorageIfNeeded()

        if self.textContainer.size != size {
            self.textContainer.size = size
            self.truncateAndAppendReadMoreLinkIfNeeded()
            performLayoutBlock { (textStorage, textContainer, layoutManager) in
                self.textRect = layoutManager.usedRect(for: textContainer)
            }
            self.performHyperlinkDetectionIfNeeded()
        }
        return textRect
    }

    private func prepareTextStorageIfNeeded() {
        // FIXME: Access to this variable isn't thread safe.
        guard !self.textStorageIsValid else { return }

        if let attributedText = self.attributedText {
            let mutableAttributedText: NSMutableAttributedString = attributedText.mutableCopy() as! NSMutableAttributedString
            mutableAttributedText.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: mutableAttributedText.length))
            mutableAttributedText.removeAttribute(.shadow, range: NSRange(location: 0, length: mutableAttributedText.length))
            self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
                textStorage.setAttributedString(mutableAttributedText)
            }

            self.needsDetectHyperlinks = true
        }
        self.textStorageIsValid = true
    }

    private func invalidateTextStorage() {
        self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
            textStorage.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
            textContainer.size = .zero
        }
        self.textStorageIsValid = false
    }

    private func truncate(textStorage: NSTextStorage, forLayoutManager layoutManaged: NSLayoutManager, ofTextContainer textContainer: NSTextContainer, toLineCount maxLineCount: Int) -> NSRange {
        assert(textContainer.maximumNumberOfLines == 0, "textContainer.maximumNumberOfLines not 0")
        let glyphCount = layoutManager.numberOfGlyphs
        var lastLineGlyphRange = NSRange(location: 0, length: 0)
        var lineCount = 0
        var startGlyphIndex = 0
        while (startGlyphIndex < glyphCount && lineCount < maxLineCount) {
            layoutManager.lineFragmentRect(forGlyphAt: startGlyphIndex, effectiveRange: &lastLineGlyphRange)
            startGlyphIndex = NSMaxRange(lastLineGlyphRange)
            lineCount += 1
        }
        guard startGlyphIndex != glyphCount else {
            return NSRange(location: NSNotFound, length: 0)
        }
        textContainer.maximumNumberOfLines = maxLineCount
        layoutManager.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: textStorage.length), changeInLength: 0, actualCharacterRange: nil)
        var truncatedGlyphRange = layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lastLineGlyphRange.location)
        textContainer.maximumNumberOfLines = 0
        layoutManager.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: textStorage.length), changeInLength: 0, actualCharacterRange: nil)
        if truncatedGlyphRange.location == NSNotFound {
            // The last line may not be truncated if it is shown in full. In this case, we need to back
            // up the character index by 1 to remove the trailing newline character.
            let index = NSMaxRange(lastLineGlyphRange)
            truncatedGlyphRange = NSRange(location: index, length: glyphCount - index)
            var charRangeToDelete = layoutManager.characterRange(forGlyphRange: truncatedGlyphRange, actualGlyphRange: nil)
            if charRangeToDelete.location > 0 {
                charRangeToDelete.location -= 1
                charRangeToDelete.length += 1
            }
            textStorage.replaceCharacters(in: charRangeToDelete, with: "")
            return charRangeToDelete
        } else {
            self.needsDetectHyperlinks = true

            // Add an ellipsis only if the default truncation behavior results in an ellipsis.
            truncatedGlyphRange.length = glyphCount - truncatedGlyphRange.location
            let charRangeToReplace = layoutManager.characterRange(forGlyphRange: truncatedGlyphRange, actualGlyphRange:nil)
            textStorage.replaceCharacters(in: charRangeToReplace, with: "\u{2026}")
            return charRangeToReplace
        }
    }

    private func truncateAndAppendReadMoreLinkIfNeeded() {
        self.readMoreLink = nil

        guard self.numberOfLines != 0 else { return }
        guard self.layoutManager.numberOfGlyphs > 10 else { return }

        var replacedRange = NSRange(location: NSNotFound, length: 0)
        self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
            replacedRange = self.truncate(textStorage: textStorage, forLayoutManager: layoutManager, ofTextContainer: textContainer, toLineCount: self.numberOfLines)
        }
        guard replacedRange.location != NSNotFound else {
            return
        }
        if replacedRange.location > 0 {
            self.lastValidCharacterIndex = replacedRange.location - 1
        }

        let readMoreLinkCharacterIndex = self.textStorage.length
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 6
        let readMoreLinkText = "\n\("Read more")" // TODO: localize
        let attributes: [ NSAttributedString.Key: Any ] = [ .font: UIFont.systemFont(ofSize: self.font.pointSize, weight: .medium),
                                                            .foregroundColor: UIColor.systemGray,
                                                            .paragraphStyle: style ]
        self.textStorage.append(NSAttributedString(string: readMoreLinkText, attributes: attributes))

        self.readMoreLink = AttributedTextLink(text: readMoreLinkText, textCheckingResult: .readMoreLink, url: nil)
        let readMoreRange = NSRange(location: readMoreLinkCharacterIndex + 1, length: self.textStorage.length - readMoreLinkCharacterIndex - 1)
        self.readMoreLink?.rects = self.rects(for: readMoreRange, in: self.textContainer, with: self.layoutManager)
        self.links = [ self.readMoreLink! ]
    }

    // MARK: Thread safety

    /**
     * This setup is to allow updating the text objects off the main thread.
     */
    private let textObjectsLock = NSLock()

    private func performLayoutBlock(block: (NSTextStorage, NSTextContainer, NSLayoutManager) -> ()) {
        self.textObjectsLock.lock()
        block(self.textStorage, self.textContainer, self.layoutManager)
        self.textObjectsLock.unlock()
    }

    // MARK: Hyperlinks

    var hyperlinkDetectionIgnoreRange: Range<String.Index>? {
        didSet {
            self.invalidateTextStorage()
        }
    }

    private var needsDetectHyperlinks = false

    private var links: [AttributedTextLink]?

    private static let linkAttributes: [ NSAttributedString.Key: Any ] =
        [ NSAttributedString.Key.foregroundColor: UIColor.systemBlue ]

    private static let addressAttributes: [ NSAttributedString.Key: Any ] =
        [ NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
          NSAttributedString.Key.underlineColor: UIColor.label.withAlphaComponent(0.5) ]

    static private let detectionQueue = DispatchQueue(label: "hyperlink-detection")

    static private let dataDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)

    private func performHyperlinkDetectionIfNeeded() {
        guard self.needsDetectHyperlinks else { return }
        self.needsDetectHyperlinks = false
        TextLabel.detectionQueue.async {
            self.reallyDetectHyperlinks()
        }
    }

    private func reallyDetectHyperlinks() {
        var text: String = ""
        self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
            text = textStorage.string
        }
        let links = self.detectSystemDataTypes(in: text, ignoredRange: self.hyperlinkDetectionIgnoreRange)
        DispatchQueue.main.async {
            self.links = links
            if self.readMoreLink != nil {
                self.links?.append(self.readMoreLink!)
            }
            self.setNeedsDisplay()
        }
    }

    private func textAttributes(for textCheckingType: NSTextCheckingResult.CheckingType) -> [ NSAttributedString.Key: Any ] {
        if textCheckingType == .address || textCheckingType == .date {
            return TextLabel.addressAttributes
        } else {
            return TextLabel.linkAttributes
        }
    }

    private func detectSystemDataTypes(in text: String, ignoredRange: Range<String.Index>? = nil) -> [AttributedTextLink] {
        var results: [AttributedTextLink] = []
        let matches = TextLabel.dataDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        for match in matches {
            if let range = Range(match.range, in: text) {
                if ignoredRange != nil && ignoredRange!.overlaps(range) {
                    continue
                }
                // Don't linkify if up against truncation boundary, as the extracted data could be based on
                // a partial string and could therefore be invalid.
                guard NSIntersectionRange(match.range, NSRange(location: self.lastValidCharacterIndex, length: 1)).length == 0 else {
                    continue
                }
                var link = AttributedTextLink(text: String(text[range]), textCheckingResult: match.resultType, url: match.url)

                var rects: [CGRect] = []
                self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
                    // Do nothing if text was truncated while link detection was happening on a background thread.
                    guard textStorage.string == text else {
                        return
                    }
                    rects = self.rects(for: match.range, in: textContainer, with: layoutManager)
                    let attributes = self.textAttributes(for: match.resultType)
                    textStorage.addAttributes(attributes, range: match.range)
                }
                if !rects.isEmpty {
                    link.rects = rects
                    results.append(link)
                }
            }
        }
        return results
    }

    private func rects(for characterRange: NSRange, in textContainer: NSTextContainer, with layoutManager: NSLayoutManager) -> [CGRect] {
        var rects: [CGRect] = []
        var glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        while (true) {
            var glyphRangeOfLine = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &glyphRangeOfLine)
            let lineLastIndex = NSMaxRange(glyphRangeOfLine)
            let rangeLastIndex = NSMaxRange(glyphRange)
            let lastIndex = min(lineLastIndex, rangeLastIndex)
            let partialRange = NSRange(location: glyphRange.location, length: lastIndex - glyphRange.location)
            let rect = layoutManager.boundingRect(forGlyphRange: partialRange, in: textContainer)
            rects.append(rect)
            if rangeLastIndex <= lineLastIndex {
                break
            } else {
                glyphRange.length = glyphRange.length - (lineLastIndex - glyphRange.location)
                glyphRange.location = lineLastIndex
            }
        }
        return rects
    }

    // MARK: Tap handling

    private var trackedLink: AttributedTextLink?

    private var highlightedLink: AttributedTextLink?

    private func link(at point: CGPoint) -> AttributedTextLink? {
        guard self.links != nil else { return nil }
        for link in self.links! {
            for rect in link.rects {
                if rect.contains(point) {
                    return link
                }
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.trackedLink = self.link(at: (touches.first?.location(in: self))!)
        self.highlightedLink = self.trackedLink
        if self.highlightedLink != nil {
            self.setNeedsDisplay()
        } else {
            super.touchesBegan(touches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let link = self.link(at: (touches.first?.location(in: self))!)
        if self.trackedLink != nil && self.trackedLink != link {
            self.trackedLink = nil
            self.highlightedLink = nil
            self.setNeedsDisplay()
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.trackedLink = nil
        self.highlightedLink = nil
        self.setNeedsDisplay()
        super.touchesCancelled(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if self.trackedLink != nil {
            self.delegate?.textLabel(self, didRequestHandle: self.trackedLink!)
            self.trackedLink = nil
        } else {
            super.touchesEnded(touches, with: event)
        }
        self.highlightedLink = nil
        self.setNeedsDisplay()
    }

    // TODO: Add Accessibility support
}
