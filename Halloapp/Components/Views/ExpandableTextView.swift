//
//  ExpandableTextView.swift
//  HalloApp
//
//  Created by Tanveer on 2/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

protocol ExpandableTextViewDelegate: UITextViewDelegate {
    func textView(_ textView: ExpandableTextView, didRequestHandleMention userID: UserID)
    func textViewDidRequestToExpand(_ textView: ExpandableTextView)
    func textView(_ textView: ExpandableTextView, didSelectAction action: UserMenuAction)
}

/// An expandable text view that provides contextual menus for links, phone numbers,
/// and @ mentions.
class ExpandableTextView: UITextView {
    /// - note: For correctly positioning `moreButton`.
    private var baselineOffsetFromBottom: CGFloat?
    
    private var trackedMention: AttributedTextLink?
    
    private lazy var moreButton: UILabel = {
        let button = UILabel()
        button.isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(pushedMore))
        button.addGestureRecognizer(tap)
        
        button.text = Localizations.textViewMore
        
        return button
    }()
    
    private lazy var ellipsisLabel: UILabel = {
        let label = UILabel()
        label.text = "... "
        
        return label
    }()
    
    override var text: String! {
        didSet {
            invalidateState()
        }
    }
    
    override var attributedText: NSAttributedString! {
        didSet {
            invalidateState()
        }
    }
    
    override var font: UIFont? {
        didSet {
            invalidateState()
            if let font = font {
                updateExpanderViews(with: font)
                setNeedsLayout()
            }
        }
    }
    
    override var textAlignment: NSTextAlignment {
        didSet {
            invalidateState()
            setNeedsLayout()
        }
    }
    
    var numberOfLines: Int {
        set {
            textContainer.maximumNumberOfLines = newValue
            invalidateState()
        }
        
        get { return textContainer.maximumNumberOfLines }
    }
    
    private var textDirection: UIUserInterfaceLayoutDirection {
        switch textAlignment {
        case .left:
            return .leftToRight
        case .right:
            return .rightToLeft
        default:
            return effectiveUserInterfaceLayoutDirection
        }
    }
    
    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = nil
        contentInset = .zero
        insetsLayoutMarginsFromSafeArea = false
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        tintColor = .systemBlue

        layoutManager.usesFontLeading = false
        layoutManager.delegate = self
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainerInset = .zero
        textContainer.heightTracksTextView = true
        textContainer.widthTracksTextView = true
        
        dataDetectorTypes.insert(.link)
        dataDetectorTypes.insert(.phoneNumber)
        linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        
        // for mentions
        addInteraction(UIContextMenuInteraction(delegate: self))

        addSubview(moreButton)
        addSubview(ellipsisLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("ExpandableTextView coder init not implemented.")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let font = font {
            updateExpanderViews(with: font)
        }
        
        handleTruncation()
    }
    
    @objc
    private func pushedMore(_ button: UIButton) {
        (self.delegate as? ExpandableTextViewDelegate)?.textViewDidRequestToExpand(self)
    }
    
    private func invalidateState() {
        trackedMention = nil
        invalidateTruncation()
        invalidateIntrinsicContentSize()
    }
    
    private func invalidateTruncation() {
        textContainer.exclusionPaths = []
        ellipsisLabel.isHidden = true
        moreButton.isHidden = true
    }
    
    /**
     Updates the styling of `ellipsisLabel` and `moreButton`.
     */
    private func updateExpanderViews(with font: UIFont) {
        let mediumFont = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
        
        ellipsisLabel.font = font
        moreButton.font = mediumFont
        ellipsisLabel.textColor = .label
        moreButton.textColor = .systemBlue
        
        if case .rightToLeft = textDirection {
            ellipsisLabel.text = " ..."
        } else {
            ellipsisLabel.text = "... "
        }
        
        moreButton.sizeToFit()
        ellipsisLabel.sizeToFit()
    }
    
    private func mention(at point: CGPoint) -> AttributedTextLink? {
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let entireRange = NSMakeRange(0, textStorage.length)
        var nameRange = NSMakeRange(0, 0)
        
        let attributes = textStorage.attributes(at: charIndex, longestEffectiveRange: &nameRange, in: entireRange)
        if let userID = attributes[.userMention] as? UserID {
            let text = textStorage.attributedSubstring(from: nameRange).string
            
            return AttributedTextLink(text: text,
                                resultType: .userMention,
                                     range: nameRange,
                                    userID: userID)
        }
        
        return nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            trackedMention = mention(at: touch.location(in: self))
        }
        
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let tracked = trackedMention {
            let linkAtCurrentLocation = mention(at: touch.location(in: self))
            if tracked != linkAtCurrentLocation {
                trackedMention = nil
            }
        }

        super.touchesMoved(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedMention = nil
        super.touchesCancelled(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let link = trackedMention, let id = link.userID {
            (self.delegate as? ExpandableTextViewDelegate)?.textView(self, didRequestHandleMention: id)
            trackedMention = nil
        }
        
        super.touchesEnded(touches, with: event)
    }
}

// MARK: - truncation flow

extension ExpandableTextView {
    /// For when the text view doesn't display all of its text. `glyphs` is the range for
    /// the last visible line of glyphs, and `rect` is the bounding rect for said glyphs.
    private typealias TruncationPosition = (glyphs: NSRange, rect: CGRect)

    private func handleTruncation() {
        if let position = truncationPosition() {
            placeExclusionPathIfNeeded(position)

            ellipsisLabel.isHidden = false
            moreButton.isHidden = false
        } else {
            invalidateTruncation()
        }
    }
    
    /**
     Finds the truncation point in the text view, if it exists.
     */
    private func truncationPosition() -> TruncationPosition? {
        guard numberOfLines != 0 else {
            return nil
        }

        let glyphCount = layoutManager.numberOfGlyphs
        var glyphIndex = 0
        var lineIndex = 0
        var lastRect: CGRect?
        var lastLineGlyphs = NSMakeRange(0, 0)
        
        while glyphIndex < layoutManager.numberOfGlyphs, lineIndex < numberOfLines {
            lastRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lastLineGlyphs, withoutAdditionalLayout: true)
            glyphIndex = NSMaxRange(lastLineGlyphs)
            lineIndex += 1
        }
        
        let truncatedGlyphRange = layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lastLineGlyphs.location)
        guard glyphIndex != glyphCount || truncatedGlyphRange.location != NSNotFound else {
            return nil
        }
        
        return (lastLineGlyphs, lastRect ?? .zero)
    }
    
    /**
     Applies an exclusion path if there is not enough space for the expander views.
     
     - Returns: An updated truncation position that takes into account the exclusion path. If no exclusion path was applied,
                the same values that were passed in are returned.
     */
    @discardableResult
    private func placeExclusionPathIfNeeded(_ position: TruncationPosition) -> TruncationPosition {
        var (lastLineGlyphs, lastLineRect) = position
        
        if let exclusionRect = exclusionRect(for: lastLineRect) {
            textContainer.exclusionPaths = [UIBezierPath(rect: exclusionRect)]
            // get the updated bounding rect after the exlusion path has been applied
            var updatedGlyphs = NSMakeRange(0, 0)
            lastLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: lastLineGlyphs.location, effectiveRange: &updatedGlyphs)
            lastLineGlyphs = updatedGlyphs
        }
        
        positionExpanderViews((lastLineGlyphs, lastLineRect))
        return (lastLineGlyphs, lastLineRect)
    }
    
    /**
     - Parameter linRect: The bounding rect for the last visible line in the text view.
     - Returns: The rect to be used for the exclusion path. `nil` if no exclusion is necessary.
     */
    private func exclusionRect(for lineRect: CGRect) -> CGRect? {
        guard lineRect != .zero else {
            return nil
        }
        
        let expanderViewsWidth = ellipsisLabel.bounds.width + moreButton.bounds.width
        
        if case .rightToLeft = textDirection {
            let limit = self.bounds.minX + expanderViewsWidth
            if lineRect.minX < limit {
                
                return CGRect(x: 0,
                              y: lineRect.minY,
                          width: expanderViewsWidth,
                         height: lineRect.height * 0.5)
            }
        } else {
            let limit = self.bounds.maxX - expanderViewsWidth
            if lineRect.maxX > limit {
                let widthToExclude = lineRect.maxX - limit
                
                return CGRect(x: lineRect.maxX - widthToExclude,
                              y: lineRect.minY,
                          width: self.bounds.maxX - expanderViewsWidth,
                         height: lineRect.height * 0.5)
            }
        }
        
        return nil
    }
    
    private func positionExpanderViews(_ position: TruncationPosition) {
        let rect = adjustedTruncationViewsPosition(position) ?? position.rect
        if case .rightToLeft = textDirection {
            ellipsisLabel.frame.origin.x = rect.minX - ellipsisLabel.bounds.width
            moreButton.frame.origin.x = ellipsisLabel.frame.origin.x - moreButton.bounds.width
        } else {
            ellipsisLabel.frame.origin.x = rect.maxX
            moreButton.frame.origin.x = ellipsisLabel.frame.origin.x + ellipsisLabel.bounds.width
        }
        
        let screenScale = UIScreen.main.scale
        let baselineOffset = baselineOffsetFromBottom ?? .zero
        let labelBaselineY = self.ellipsisLabel.font?.ascender ?? .zero
        
        ellipsisLabel.frame.origin.y = ((position.rect.maxY - baselineOffset - labelBaselineY) * screenScale) / screenScale
        if ellipsisLabel.frame.maxY > bounds.maxY {
            // there are edge cases w/ right-to-left languages that can cause the label to be cut-off
            ellipsisLabel.frame.origin.y = bounds.maxY - ellipsisLabel.frame.height
        }

        moreButton.frame.origin.y = ellipsisLabel.frame.origin.y + (ellipsisLabel.font.ascender - moreButton.font.ascender)
    }
    
    private func adjustedTruncationViewsPosition(_ position: TruncationPosition) -> CGRect? {
        let characterRange = layoutManager.characterRange(forGlyphRange: position.glyphs, actualGlyphRange: nil)
        // it's a bit tricky w/ right-to-left languages as the ranges seem to be flipped
        // hence the other conditional assignment inside of the loop
        let lastChar = textDirection == .leftToRight ? NSMaxRange(characterRange) - 1 : characterRange.location
        var adjusted = lastChar
        var i = 0
        
        while let range = Range(NSMakeRange(adjusted, 1), in: textStorage.string),
              textStorage.string[range] == " ",
              i < 2,
              characterRange.contains(lastChar)
        {
            // for now let's just move backwards up to two spaces
            // we can adjust this method later on if we want to skip other characters
            adjusted += textDirection == .leftToRight ? -1 : 1
            i += 1
        }
        
        if adjusted != lastChar {
            let adjustedGlyphRange = layoutManager.glyphRange(forCharacterRange: NSMakeRange(adjusted, 1), actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: adjustedGlyphRange, in: textContainer)
        }
        
        return nil
    }
}

// MARK: - layout manager delegate methods

extension ExpandableTextView: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>, lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        
        baselineOffsetFromBottom = lineFragmentRect.pointee.height - baselineOffset.pointee
        return false
    }
}

// MARK: - context menu delegate methods

extension ExpandableTextView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard
            let mention = mention(at: location),
            let id = mention.userID
        else {
            return nil
        }
        
        let config = UIContextMenuConfiguration(identifier: id as NSString, previewProvider: {
            return UserFeedViewController(userId: id)
        }) { [weak self] _ in
            return UIMenu.menu(for: id) { [weak self] action in
                guard let self = self else { return }
                (self.delegate as? ExpandableTextViewDelegate)?.textView(self, didSelectAction: action)
            }
        }
        
        return config
    }
    
    private func contextMenuPreview(for interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let link = mention(at: interaction.location(in: self)) else {
            return nil
        }
        
        let rects = TextLabel.textRects(forCharacterRange: link.range, inTextContainer: textContainer, withLayoutManager: layoutManager)
        let center = CGRect.center(of: rects) ?? interaction.location(in: self)
        
        let parmeters = UIPreviewParameters(textLineRects: rects.map { NSValue(cgRect: $0.insetBy(dx: 6, dy: 6)) })
        parmeters.backgroundColor = self.backgroundColor
            
        let target = UIPreviewTarget(container: self, center: center)
        let snapshot = self.resizableSnapshotView(from: self.bounds, afterScreenUpdates: true, withCapInsets: .zero)
        return UITargetedPreview(view: snapshot ?? self, parameters: parmeters, target: target)
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return contextMenuPreview(for: interaction, configuration: configuration)
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return contextMenuPreview(for: interaction, configuration: configuration)
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard
            let mention = mention(at: interaction.location(in: self)),
            let id = mention.userID
        else {
            return
        }
        
        animator.addCompletion { [id] in
            (self.delegate as? ExpandableTextViewDelegate)?.textView(self, didRequestHandleMention: id)
        }
    }
}

// MARK: - localization

extension Localizations {
    // ideally we'd use the values defined in `ProfileHeaderViewController`, but since using those would
    // cause inconsistent casing when compared to the system's context menus, we define new ones here
    static var contextMenuMessageUser = NSLocalizedString("textview.context.menu.message.user",
                                                   value: "Message",
                                                 comment: "Same as profile.header.message.user, but capitalized")
    
    static var contextMenuAudioCall = NSLocalizedString("textview.context.menu.audio.call.user",
                                                 value: "Voice call",
                                               comment: "Same as profile.header.call.user, but capitalized")
    
    static var contextMenuVideoCall = NSLocalizedString("textview.context.menu.video.call.user",
                                                 value: "Video call",
                                               comment: "Same as profile.header.call.user, but capitalized")
    
    static var textViewMore = NSLocalizedString("textview.more",
                                         value: "more",
                                       comment: "Link to expand truncated text.")
}

fileprivate extension CGRect {
    static func center(of rects: [CGRect]) -> CGPoint? {
        guard !rects.isEmpty else {
            return nil
        }
        
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        for rect in rects {
            minX = minX > rect.minX ? rect.minX : minX
            maxX = maxX < rect.maxX ? rect.maxX : maxX
            minY = minY > rect.minY ? rect.minY : minY
            maxY = maxY < rect.maxY ? rect.maxY : maxY
        }
        
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}
