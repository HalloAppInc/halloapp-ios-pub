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
    /// For when the text view doesn't display all of its text. `glyphs` is the range for
    /// the last visible line of glyphs, and `rect` is the bounding rect for said glyphs.
    private typealias TruncationPosition = (glyphs: NSRange, rect: CGRect)
    private var truncationPosition: TruncationPosition?
    /// - note: For correctly positioning `moreButton`.
    private var baselineOffsetFromBottom: CGFloat?
    
    private var trackedMention: AttributedTextLink?
    
    private lazy var moreButton: UILabel = {
        let button = UILabel()
        button.text = Localizations.textViewMore
        button.sizeToFit()
        button.textColor = .systemBlue
        button.isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(pushedMore))
        button.addGestureRecognizer(tap)
        
        return button
    }()
    
    override var text: String! {
        didSet { invalidateState() }
    }
    
    override var attributedText: NSAttributedString! {
        didSet {
            invalidateState()
            if let attributedText = attributedText, attributedText.length > 0, let font = attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                updateMoreButtonFont(with: font)
            }
        }
    }
    
    override var font: UIFont? {
        didSet {
            invalidateState()
            if let font = font {
                updateMoreButtonFont(with: font)
            }
        }
    }
    
    var numberOfLines: Int {
        set {
            textContainer.maximumNumberOfLines = newValue
            invalidateState()
        }
        
        get { return textContainer.maximumNumberOfLines }
    }
    
    override var intrinsicContentSize: CGSize {
        get {
            // - TODO: move truncation + exclusion logic to another place
            let size = super.intrinsicContentSize
            textContainer.size = size
            findTruncationPosition()
            placeExclusionPathIfNeeded()
            return size
        }
    }
    
    init() {
        super.init(frame: .zero, textContainer: nil)
        
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
        moreButton.isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("ExpandableTextView coder init not implemented.")
    }
    
    @objc private func pushedMore(_ button: UIButton) {
        (self.delegate as? ExpandableTextViewDelegate)?.textViewDidRequestToExpand(self)
    }
    
    private func placeExclusionPathIfNeeded() {
        guard let (_, lastLineRect) = truncationPosition else {
            textContainer.exclusionPaths = []
            truncationPosition = nil
            moreButton.isHidden = true
            return
        }
        
        let threshold = self.bounds.maxX - moreButton.bounds.width
        if lastLineRect != .zero && lastLineRect.maxX > threshold {
            let offset = lastLineRect.maxX - threshold
            let exclusionRect = CGRect(x: lastLineRect.maxX - offset,
                                       y: lastLineRect.minY,
                                   width: self.bounds.maxX - lastLineRect.maxX,
                                  height: lastLineRect.height * 0.5)
            
            textContainer.exclusionPaths = [UIBezierPath(rect: exclusionRect)]
        }

        moreButton.isHidden = false
    }
    
    /**
     Finds the truncation point in the text view, if it exists. Updates `truncationPosition`.
     - note: Can cause layout generation.
     */
    private func findTruncationPosition() {
        guard numberOfLines != 0 else {
            truncationPosition = nil
            return
        }

        let glyphCount = layoutManager.numberOfGlyphs
        var glyphIndex = 0
        var lineIndex = 0
        var lastRect: CGRect?
        var lastLineGlyphs = NSMakeRange(0, 0)
        
        while glyphIndex < layoutManager.numberOfGlyphs && lineIndex < numberOfLines {
            lastRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lastLineGlyphs)
            glyphIndex = NSMaxRange(lastLineGlyphs)
            lineIndex += 1
        }
        
        let truncatedGlyphRange = layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lastLineGlyphs.location)
        guard glyphIndex != glyphCount || truncatedGlyphRange.location != NSNotFound else {
            truncationPosition = nil
            return
        }
        
        self.truncationPosition = (lastLineGlyphs, lastRect ?? .zero)
    }
    
    private func invalidateState() {
        trackedMention = nil
        textContainer.exclusionPaths = []
        invalidateIntrinsicContentSize()
    }
    
    private func updateMoreButtonFont(with font: UIFont) {
        let mediumFont = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
        moreButton.font = mediumFont
        moreButton.sizeToFit()
        setNeedsLayout()
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

// MARK: - layout manager delegate methods

extension ExpandableTextView: NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, textContainer: NSTextContainer, didChangeGeometryFrom oldSize: CGSize) {
        placeExclusionPathIfNeeded()
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>, lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        
        baselineOffsetFromBottom = lineFragmentRect.pointee.height - baselineOffset.pointee
        return false
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        guard let _ = truncationPosition else {
            return
        }
        
        let screenScale = UIScreen.main.scale
        if let baselineOffset = baselineOffsetFromBottom {
            let labelBaselineY = moreButton.font.ascender
            moreButton.frame.origin.y = floor((self.textContainer.size.height  - baselineOffset - labelBaselineY) * screenScale) / screenScale
        }
        
        moreButton.frame.origin.x = self.bounds.maxX - moreButton.bounds.width
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
    
    static var textViewMore = NSLocalizedString("textview.more", value: "...more", comment: "Link to expand truncated text.")
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
