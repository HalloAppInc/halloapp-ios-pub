//
//  TextLabel.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import UIKit

class TextLabel: UILabel {

    let textStorage: NSTextStorage
    let textContainer: NSTextContainer
    let layoutManager: NSLayoutManager

    override init(frame: CGRect) {
        textContainer = NSTextContainer()
        textContainer.lineFragmentPadding = 0

        layoutManager = NSLayoutManager()
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

        layoutManager = NSLayoutManager()
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
            self.textContainer.maximumNumberOfLines = self.numberOfLines
            self.setNeedsDisplay()
            self.invalidateIntrinsicContentSize()
        }
    }

    var hyperlinkDetectionIgnoreRange: Range<String.Index>? {
        didSet {
            self.invalidateTextStorage()
        }
    }


    // MARK: Text Metrics & Drawing

    override var intrinsicContentSize: CGSize {
        get {
            var boundingSize = CGSize(width: self.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude)
            if boundingSize.width == 0 {
                boundingSize.width = CGFloat.greatestFiniteMagnitude
            }
            return self.sizeThatFits(boundingSize)
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

        self.performLayoutBlock { textStorage, textContainer, layoutManager in
            let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
    }

    private var maxTextContainerSize: CGSize = .zero
    private var textRect: CGRect = .zero

    private func textBoundingRect(with size: CGSize) -> CGRect {
        self.prepareTextStorageIfNeeded()

        self.maxTextContainerSize = size
        self.textContainer.size = self.maxTextContainerSize
        self.layoutManager.glyphRange(for: self.textContainer)
        self.textRect = self.layoutManager.usedRect(for: self.textContainer)

        return textRect
    }

    private var textStorageIsValid = false

    private func prepareTextStorageIfNeeded() {
        // FIXME: Access to this variable isn't thread safe.
        guard !textStorageIsValid else { return }

        if let attributedText = self.attributedText {
            let mutableAttributedText: NSMutableAttributedString = attributedText.mutableCopy() as! NSMutableAttributedString
            let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
            paragraphStyle.alignment = self.textAlignment
            paragraphStyle.lineBreakMode = .byWordWrapping
            mutableAttributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: textStorage.length))
            self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
                textStorage.setAttributedString(attributedText)
            }

            self.needsDetectHyperlinks = true
            self.performHyperlinkDetectionIfNeeded()
        }
        self.textStorageIsValid = true
    }

    private func invalidateTextStorage() {
        self.performLayoutBlock { (textStorage, textContainer, layoutManager) in
            textStorage.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
        }
        self.textStorageIsValid = false
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
    struct AttributedTextLink: Equatable {
        let text: String
        let textCheckingResult: NSTextCheckingResult.CheckingType
        let url: URL?
        var rects: [ CGRect ] = []
    }

    private var needsDetectHyperlinks = false
    private var links: [AttributedTextLink]?
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
        var attributedText: NSAttributedString = NSAttributedString()
        var text: String = ""
        self.performLayoutBlock { textStorage, textContainer, layoutManager in
            attributedText = textStorage
            text = textStorage.string
        }
        let links = self.detectSystemDataTypes(in: text, attributedText: attributedText, ignoredRange: self.hyperlinkDetectionIgnoreRange)
        DispatchQueue.main.async {
            self.links = links
            self.setNeedsDisplay()
        }
    }

    private static let linkAttributes: [ NSAttributedString.Key: Any ] =
        [ NSAttributedString.Key.foregroundColor: UIColor.systemBlue ]
    private static let addressAttributes: [ NSAttributedString.Key: Any ] =
        [ NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
          NSAttributedString.Key.underlineColor: UIColor.label.withAlphaComponent(0.5) ]

    private func textAttributes(for textCheckingType: NSTextCheckingResult.CheckingType) -> [ NSAttributedString.Key: Any ] {
        if textCheckingType == .address || textCheckingType == .date {
            return TextLabel.addressAttributes
        } else {
            return TextLabel.linkAttributes
        }
    }

    private func detectSystemDataTypes(in text: String, attributedText: NSAttributedString, ignoredRange: Range<String.Index>? = nil) -> [AttributedTextLink] {
        var results: [AttributedTextLink] = []
        let matches = TextLabel.dataDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        for match in matches {
            if let range = Range(match.range, in: text) {
                if ignoredRange != nil && ignoredRange!.overlaps(range) {
                    continue
                }
                var link = AttributedTextLink(text: String(text[range]), textCheckingResult: match.resultType, url: match.url)

                var rects: [CGRect] = []
                self.performLayoutBlock { textStorage, textContainer, layoutManager in
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
            if let url = self.trackedLink!.url {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
            self.trackedLink = nil
        } else {
            super.touchesEnded(touches, with: event)
        }
        self.highlightedLink = nil
        self.setNeedsDisplay()
    }

    // TODO: Add Accessibility support
}
