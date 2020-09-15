//
//  TextLabel.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Contacts
import Core
import Foundation
import SafariServices
import UIKit

fileprivate class LayoutManager: NSLayoutManager {

    override func usedRect(for container: NSTextContainer) -> CGRect {
        self.glyphRange(for: container)
        return super.usedRect(for: container)
    }
}

class AttributedTextLink: Equatable, Identifiable {
    let id: String
    let text: String
    let linkType: NSTextCheckingResult.CheckingType
    let range: NSRange
    let result: NSTextCheckingResult?
    var rects = [CGRect]()

    /// Mentioned user ID
    let userID: UserID?

    init(text: String, textCheckingResult: NSTextCheckingResult) {
        self.id = UUID().uuidString
        self.text = text
        self.linkType = textCheckingResult.resultType
        self.range = textCheckingResult.range
        self.result = textCheckingResult
        self.userID = nil
    }

    init(text: String, resultType: NSTextCheckingResult.CheckingType, range: NSRange, userID: UserID? = nil) {
        self.id = UUID().uuidString
        self.text = text
        self.linkType = resultType
        self.range = range
        self.result = nil
        self.userID = userID
    }

    static func == (lhs: AttributedTextLink, rhs: AttributedTextLink) -> Bool {
        return lhs.id == rhs.id
    }
}

extension NSTextCheckingResult.CheckingType {
    static let userMention = NSTextCheckingResult.CheckingType(rawValue: 1 << 35)
}

protocol TextLabelDelegate: AnyObject {
    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink)
    func textLabelDidRequestToExpand(_ label: TextLabel)
}

class TextLabel: UILabel {

    weak var delegate: TextLabelDelegate?

    private let textStorage: NSTextStorage
    private let textContainer: NSTextContainer
    private let layoutManager: NSLayoutManager

    private var readMoreButton: UILabel!
    private var maskLayer: CAShapeLayer!
    private var readMoreGradientLayer: CAGradientLayer!

    override init(frame: CGRect) {
        textContainer = NSTextContainer()
        textContainer.lineFragmentPadding = 0

        layoutManager = LayoutManager()
        layoutManager.usesFontLeading = false
        layoutManager.addTextContainer(textContainer)

        textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        super.init(frame: .zero)

        commonInit()
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

        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = true
        addInteraction(UIContextMenuInteraction(delegate: self))

        readMoreButton = UILabel()
        readMoreButton.text = "...more"
        readMoreButton.textColor = .systemGray
        readMoreButton.font = .preferredFont(forTextStyle: .body)
        readMoreButton.backgroundColor = backgroundColor
        readMoreButton.isHidden = true
        readMoreButton.isUserInteractionEnabled = true
        readMoreButton.sizeToFit()
        addSubview(readMoreButton)

        maskLayer = CAShapeLayer()
        maskLayer.fillRule = .evenOdd

        readMoreGradientLayer = CAGradientLayer()
        readMoreGradientLayer.colors = [ UIColor.white.withAlphaComponent(1).cgColor,
                                         UIColor.white.withAlphaComponent(0.5).cgColor,
                                         UIColor.white.withAlphaComponent(0).cgColor,
                                         UIColor.white.withAlphaComponent(0).cgColor ]
        readMoreGradientLayer.locations = [ 0, 0.3, 0.6, 1 ]
        readMoreGradientLayer.startPoint = CGPoint(x: 0, y: 1)
        readMoreGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        maskLayer.addSublayer(readMoreGradientLayer)

        readMoreButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(readMoreTapped)))
    }

    // MARK: UILabel

    override var text: String? {
        didSet {
            invalidateTextStorage()
        }
    }

    override var attributedText: NSAttributedString? {
        didSet {
            invalidateTextStorage()
            if let readMoreButton = readMoreButton, let font = attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                readMoreButton.font = font
                readMoreButton.sizeToFit()
                setNeedsLayout()
            }
        }
    }

    override var font: UIFont! {
        didSet {
            invalidateTextStorage()
            if let readMoreButton = readMoreButton {
                readMoreButton.font = font
                readMoreButton.sizeToFit()
                setNeedsLayout()
            }
        }
    }

    override var numberOfLines: Int {
        didSet {
            invalidateTextStorage()
        }
    }

    override var backgroundColor: UIColor? {
        didSet {
            if let readMoreButton = readMoreButton {
                readMoreButton.backgroundColor = backgroundColor
            }
        }
    }

    // MARK: Text Metrics & Drawing

    private var textStorageIsValid = false

    private var textRect: CGRect = .zero

    override var intrinsicContentSize: CGSize {
        get {
            var maxLayoutWidth = preferredMaxLayoutWidth
            if maxLayoutWidth == 0 {
                maxLayoutWidth = bounds.width
            }
            if maxLayoutWidth == 0 {
                maxLayoutWidth = CGFloat.greatestFiniteMagnitude
            }
            return sizeThatFits(CGSize(width: maxLayoutWidth, height: CGFloat.greatestFiniteMagnitude))
        }
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        textContainer.size = .zero
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let maxSize = CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        var textSize = textBoundingRect(with: maxSize).size
        textSize.width = ceil(textSize.width)
        textSize.height = ceil(textSize.height)
        return textSize
    }

    private func textBoundingRect(with size: CGSize) -> CGRect {
        prepareTextStorageIfNeeded()

        if textContainer.size != size {
            performLayoutBlock { (textStorage, textContainer, layoutManager) in
                textContainer.size = size
            }
            truncateTextIfNeeded()
            performLayoutBlock { (textStorage, textContainer, layoutManager) in
                self.textRect = layoutManager.usedRect(for: textContainer)
            }
            performHyperlinkDetectionIfNeeded()
        }
        return textRect
    }

    override func draw(_ rect: CGRect) {
        prepareTextStorageIfNeeded()

        links.forEach { link in
            guard link.rects.isEmpty else { return }
            link.rects = Self.textRects(forCharacterRange: link.range, inTextContainer: textContainer, withLayoutManager: layoutManager)
        }

        performLayoutBlock { (textStorage, textContainer, layoutManager) in
            let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let screenScale = UIScreen.main.scale
        readMoreButton.frame.origin.x = bounds.maxX - readMoreButton.frame.width
        readMoreButton.frame.origin.y = floor(textRect.maxY * screenScale) / screenScale - readMoreButton.frame.height

        if readMoreButton.isHidden {
            layer.mask = nil
        } else {
            let maskRect = bounds
            maskLayer.frame = maskRect

            let gradientWidth: CGFloat = 30
            var gradientRect = readMoreButton.frame
            gradientRect.origin.x = gradientRect.minX - gradientWidth
            gradientRect.size.width = gradientWidth
            readMoreGradientLayer.frame = gradientRect

            let path = UIBezierPath(rect: gradientRect)
            path.append(UIBezierPath(rect: maskRect))
            maskLayer.path = path.cgPath

            layer.mask = maskLayer
        }
    }

    // MARK: Text Storage

    private var lastValidCharacterIndex: Int = NSNotFound // NSNotFound == full range is valid

    private func prepareTextStorageIfNeeded() {
        // FIXME: Access to this variable isn't thread safe.
        guard !textStorageIsValid else { return }

        if let attributedText = attributedText {
            let mutableAttributedText: NSMutableAttributedString = attributedText.mutableCopy() as! NSMutableAttributedString
            mutableAttributedText.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: mutableAttributedText.length))
            mutableAttributedText.removeAttribute(.shadow, range: NSRange(location: 0, length: mutableAttributedText.length))
            performLayoutBlock { (textStorage, textContainer, layoutManager) in
                textStorage.setAttributedString(mutableAttributedText)
            }
            needsDetectHyperlinks = true
        }
        textStorageIsValid = true
    }

    private func invalidateTextStorage() {
        performLayoutBlock { (textStorage, textContainer, layoutManager) in
            textStorage.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
            textContainer.maximumNumberOfLines = 0
            textContainer.exclusionPaths = []
            self.links = []
        }
        invalidateIntrinsicContentSize()
        textStorageIsValid = false
    }

    private func truncate(textStorage: NSTextStorage, layoutManager: NSLayoutManager, textContainer: NSTextContainer, toLineCount maxLineCount: Int) -> NSRange {
        textContainer.maximumNumberOfLines = 0
        let glyphCount = layoutManager.numberOfGlyphs
        var lastLineGlyphRange = NSRange(location: 0, length: 0)
        var lineCount = 0
        var startGlyphIndex = 0
        while startGlyphIndex < glyphCount && lineCount < maxLineCount {
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
        if truncatedGlyphRange.location == NSNotFound {
            // The last line may not be truncated if it is shown in full. In this case, we need to back
            // up the character index by 1 to remove the trailing newline character.
            let index = NSMaxRange(lastLineGlyphRange)
            truncatedGlyphRange = NSRange(location: index, length: glyphCount - index)
            var truncatedCharacterRange = layoutManager.characterRange(forGlyphRange: truncatedGlyphRange, actualGlyphRange: nil)
            if truncatedCharacterRange.location > 0 {
                truncatedCharacterRange.location -= 1
                truncatedCharacterRange.length += 1
            }
            return truncatedCharacterRange
        } else {
            needsDetectHyperlinks = true

            truncatedGlyphRange.length = glyphCount - truncatedGlyphRange.location
            let truncatedCharacterRange = layoutManager.characterRange(forGlyphRange: truncatedGlyphRange, actualGlyphRange:nil)
            return truncatedCharacterRange
        }
    }

    private func truncateTextIfNeeded() {
        readMoreButton.isHidden = true
        lastValidCharacterIndex = NSNotFound

        guard numberOfLines != 0 && layoutManager.numberOfGlyphs > 10 else {
            return
        }

        var truncatedRange = NSRange(location: NSNotFound, length: 0)
        performLayoutBlock { (textStorage, textContainer, layoutManager) in
            truncatedRange = self.truncate(textStorage: textStorage, layoutManager: layoutManager, textContainer: textContainer, toLineCount: self.numberOfLines)

            if truncatedRange.location != NSNotFound {
                let textRect = layoutManager.usedRect(for: textContainer)
                // 1. Just half the height to ensure that only the bottom line of text is truncated.
                // 2. Do not add exclusion path if text and "...more" do not overlap (eg. short lines).
                var exclusionRectSize = CGSize(width: readMoreButton.frame.width, height: 0.5 * readMoreButton.frame.height)
                exclusionRectSize.width -= textContainer.size.width - textRect.width
                if exclusionRectSize.width > 0 {
                    let exclusionRect = CGRect(x: textRect.maxX - exclusionRectSize.width, y: textRect.maxY - exclusionRectSize.height, width: exclusionRectSize.width, height: exclusionRectSize.height)
                    textContainer.exclusionPaths  = [ UIBezierPath(rect: exclusionRect) ]
                }
            }
        }

        if truncatedRange.location > 0 {
            lastValidCharacterIndex = truncatedRange.location - 1
        }

        readMoreButton.isHidden = truncatedRange.location == NSNotFound
    }

    @objc private func readMoreTapped() {
        if let delegate = delegate {
            delegate.textLabelDidRequestToExpand(self)
        }
    }

    // MARK: Thread safety

    /**
     * This setup is to allow updating the text objects off the main thread.
     */
    private let textObjectsLock = NSLock()

    private func performLayoutBlock(block: (NSTextStorage, NSTextContainer, NSLayoutManager) -> ()) {
        textObjectsLock.lock()
        block(textStorage, textContainer, layoutManager)
        textObjectsLock.unlock()
    }

    // MARK: Hyperlinks

    private var needsDetectHyperlinks = false

    private var links = [AttributedTextLink]()

    private static let linkAttributes: [ NSAttributedString.Key: Any ] =
        [ .foregroundColor: UIColor.systemBlue ]

    private static let addressAttributes: [ NSAttributedString.Key: Any ] =
        [ .underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: UIColor.label.withAlphaComponent(0.5) ]

    private static func mentionAttributes(baseFont: UIFont) -> [ NSAttributedString.Key: Any] {
        guard let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return [:]
        }
        return [.font: UIFont(descriptor: boldDescriptor, size: baseFont.pointSize)]
    }

    static private let detectionQueue = DispatchQueue(label: "hyperlink-detection")

    static private let dataDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)

    private func performHyperlinkDetectionIfNeeded() {
        guard needsDetectHyperlinks else { return }
        needsDetectHyperlinks = false
        TextLabel.detectionQueue.async {
            self.reallyDetectHyperlinks()
        }
    }

    private func reallyDetectHyperlinks() {
        var text: String = ""
        var links = [AttributedTextLink]()
        performLayoutBlock { (textStorage, textContainer, layoutManager) in
            text = textStorage.string
            links += self.userMentions(in: textStorage)
        }
        let rangesOfExistingLinks = links.compactMap { Range($0.range, in: text) }
        links += detectSystemDataTypes(in: text, ignoredRanges: rangesOfExistingLinks)

        performLayoutBlock { (textStorage, textContainer, layoutManager) in
            // String may have been changed or truncated while link detection was happening on a background thread.
            let possiblyTruncatedRange = text.commonPrefix(with: textStorage.string).utf16Extent
            let linksFullyContainedInRange = links.filter { possiblyTruncatedRange.contains($0.range) }

            for link in linksFullyContainedInRange {
                if let linkBaseFont = textStorage.attribute(.font, at: link.range.location, effectiveRange: nil) as? UIFont {
                    textStorage.addAttributes(Self.textAttributes(for: link.linkType, baseFont: linkBaseFont), range: link.range)
                }
            }
        }

        DispatchQueue.main.async {
            self.links = links
            self.setNeedsDisplay()
        }
    }

    private class func textAttributes(for textCheckingType: NSTextCheckingResult.CheckingType, baseFont: UIFont) -> [ NSAttributedString.Key: Any ] {
        switch textCheckingType {
        case .address, .date:
            return TextLabel.addressAttributes
        case .userMention:
            return TextLabel.mentionAttributes(baseFont: baseFont)
        default:
            return TextLabel.linkAttributes
        }
    }

    private func userMentions(in attributedString: NSAttributedString?) -> [AttributedTextLink] {
        guard let attributedString = attributedString else { return [] }
        var links = [AttributedTextLink]()
        attributedString.enumerateAttribute(.userMention, in: attributedString.utf16Extent, options: .init()) { value, mentionRange, _ in
            guard let userID = value as? UserID else {
                return
            }
            links.append(AttributedTextLink(
                text: attributedString.attributedSubstring(from: mentionRange).string,
                resultType: .userMention,
                range: mentionRange,
                userID: userID))
        }
        return links
    }

    private func detectSystemDataTypes(in text: String, ignoredRanges: [Range<String.Index>]) -> [AttributedTextLink] {
        var results: [AttributedTextLink] = []
        let matches = TextLabel.dataDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
        for match in matches {
            if let range = Range(match.range, in: text) {
                if ignoredRanges.contains(where: { $0.overlaps(range) }) {
                    continue
                }
                // Don't linkify if up against truncation boundary, as the extracted data could be based on
                // a partial string and could therefore be invalid.
                guard NSIntersectionRange(match.range, NSRange(location: self.lastValidCharacterIndex, length: 1)).length == 0 else {
                    continue
                }

                let link = AttributedTextLink(text: String(text[range]), textCheckingResult: match)
                results.append(link)
            }
        }
        return results
    }

    private class func textRects(forCharacterRange characterRange: NSRange, inTextContainer textContainer: NSTextContainer, withLayoutManager layoutManager: NSLayoutManager) -> [CGRect] {
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

    private func link(at point: CGPoint) -> AttributedTextLink? {
        return links.first(where: { (link) in
            return link.rects.contains(where: { $0.contains(point) })
        })
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            trackedLink = link(at: touch.location(in: self))
        }
        if trackedLink == nil {
            super.touchesBegan(touches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, trackedLink != nil {
            let linkAtCurrentLocation = link(at: touch.location(in: self))
            if trackedLink != linkAtCurrentLocation {
                trackedLink = nil
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedLink = nil
        super.touchesCancelled(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let link = trackedLink {
            self.delegate?.textLabel(self, didRequestHandle: link)
            trackedLink = nil
        } else {
            super.touchesEnded(touches, with: event)
        }
    }

    // TODO: Add Accessibility support
}

extension TextLabel: UIContextMenuInteractionDelegate {

    private func contextMenuItems(forWebLink link: AttributedTextLink) -> [UIMenuElement]? {
        guard let url  = link.result?.url else { return nil }

        var items = [UIMenuElement]()

        // Open Link
        items.append(UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { (_) in
            UIApplication.shared.open(url)
        })

        // Add to Reading List
        items.append(UIAction(title: "Add to Reading list", image: UIImage(systemName: "eyeglasses")) { (_) in
            try? SSReadingList.default()?.addItem(with: url, title: nil, previewText: nil)
        })

        // Copy Link
        items.append(UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { (_) in
            UIPasteboard.general.string = link.text
            UIPasteboard.general.url = url
        })

        // Share
        items.append(UIAction(title: "Share...", image: UIImage(systemName: "square.and.arrow.up")) { (_) in
            MainAppContext.shared.activityViewControllerPresentRequest.send([url])
        })

        return items
    }

    private func contextMenuItems(forTelLink link: AttributedTextLink) -> [UIMenuElement] {
        var items = [UIMenuElement]()

        // Call <phone number>
        if let url = URL(string: "tel:\(link.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"), UIApplication.shared.canOpenURL(url) {
            items.append(UIAction(title: "Call \(link.text)", image: UIImage(systemName: "phone")) { (_) in
                UIApplication.shared.open(url)
            })
        }

        /// TODO: "Add to Contacts"

        // Copy Phone Number
        items.append(UIAction(title: "Copy Phone Number", image: UIImage(systemName: "doc.on.doc")) { (_) in
            UIPasteboard.general.string = link.text
        })

        return items
    }

    private func contextMenuItems(forAddressLink link: AttributedTextLink) -> [UIMenuElement] {
        var items = [UIMenuElement]()

        // Get Directions
        if let directionsURL = URL(string: "https://maps.apple.com/?daddr=\(link.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"),
            UIApplication.shared.canOpenURL(directionsURL) {
            items.append(UIAction(title: "Get Directions", image: UIImage(systemName: "arrow.up.right.diamond")) { (_) in
                UIApplication.shared.open(directionsURL)
            })
        }

        // Open in Maps
        if let mapsURL = URL(string: "https://maps.apple.com/?address=\(link.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"),
           UIApplication.shared.canOpenURL(mapsURL){
            items.append(UIAction(title: "Open in Maps", image: UIImage(systemName: "map")) { (_) in
                UIApplication.shared.open(mapsURL)
            })
        }

        /// TODO: "Add to Contacts"

        // Copy Address
        items.append(UIAction(title: "Copy Address", image: UIImage(systemName: "doc.on.doc")) { (_) in
            UIPasteboard.general.string = link.text
        })

        return items
    }

    private func contextMenuItems(forLink link: AttributedTextLink) -> [UIMenuElement]? {
        switch link.linkType {
        case .link:
            return contextMenuItems(forWebLink: link)

        case .phoneNumber:
            return contextMenuItems(forTelLink: link)

        case .address:
            return contextMenuItems(forAddressLink: link)

        default:
            break
        }
        return nil
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let link = link(at: location), let menuItems = contextMenuItems(forLink: link) else { return nil }

        return UIContextMenuConfiguration(identifier: link.id as NSString, previewProvider: nil) { (suggestedActions) in
            return UIMenu(title: link.text, children: menuItems)
        }
    }

    private func link(forMenuConfiguration configuration: UIContextMenuConfiguration) -> AttributedTextLink? {
        guard let configurationIdentifier = configuration.identifier as? String else { return nil }
        return links.first(where: { $0.id == configurationIdentifier })
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let link = link(forMenuConfiguration: configuration) else { return nil }

        let previewParameters = UIPreviewParameters(textLineRects: link.rects.map({ NSValue(cgRect: $0.insetBy(dx: 4, dy: 4)) }))
        previewParameters.backgroundColor = .secondarySystemGroupedBackground
        return UITargetedPreview(view: self, parameters: previewParameters)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let link = link(forMenuConfiguration: configuration) else { return nil }

        let previewParameters = UIPreviewParameters(textLineRects: link.rects.map({ NSValue(cgRect: $0.insetBy(dx: 4, dy: 4)) }))
        previewParameters.backgroundColor = .clear
        return UITargetedPreview(view: self, parameters: previewParameters)
    }

}
