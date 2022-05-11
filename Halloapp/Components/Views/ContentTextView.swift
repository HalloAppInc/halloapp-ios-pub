//
//  ContentTextView.swift
//  HalloApp
//
//  Created by Tanveer on 3/16/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import LinkPresentation
import CoreCommon
import Core
import Combine

protocol ContentTextViewDelegate: UITextViewDelegate {
    func textView(_ textView: ContentTextView, didPaste image: UIImage)
}

class ContentTextView: UITextView {
    enum LinkPreviewFetchState {
        case fetching
        case fetched((preview: UIImage?, data: LinkPreviewData)?)
    }
    
    private(set) var maxHeight: CGFloat = 144
    
    private var linkPreviewTimer = Timer()
    private(set) var linkPreviewURL: URL?
    private var invalidLinkPreviewURL: URL?
    private(set) var linkPreviewData: LinkPreviewData?
    let linkPreviewMetadata = CurrentValueSubject<LinkPreviewFetchState, Never>(.fetched(nil))
    
    var mentions = MentionRangeMap()
    var mentionInput: MentionInput {
        MentionInput(text: text, mentions: mentions, selectedRange: selectedRange)
    }
    
    var mentionText: MentionText {
        get { return MentionText(expandedText: text, mentionRanges: mentions) }
        set {
            let textAndMentions = newValue.expandedTextAndMentions {
                MainAppContext.shared.contactStore.fullName(for: $0)
            }
            
            text = textAndMentions.text.string
            mentions = textAndMentions.mentions
        }
    }
    
    override var font: UIFont? {
        didSet {
            guard let font = self.font else {
                maxHeight = 144
                return
            }
            
            let usingLines = font.lineHeight * 5 + textContainerInset.top + textContainerInset.bottom
            maxHeight = min(usingLines.rounded(.up), 144)
        }
    }
    
    override var intrinsicContentSize: CGSize {
        get {
            // without this we'd get layout issues when pasting and deleting
            // larger amounts of text
            let size = sizeThatFits(CGSize(width: self.bounds.width,
                                          height: .greatestFiniteMagnitude))
            return size
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), let _ = UIPasteboard.general.image, let _ = delegate {
            return true
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }
    
    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image, let delegate = delegate as? ContentTextViewDelegate {
            delegate.textView(self, didPaste: image)
        } else {
            super.paste(sender)
        }
    }
    
    func checkLinkPreview() {
        guard text != "" else {
            resetLinkDetection()
            return linkPreviewMetadata.send(.fetched(nil))
        }
        
        if !linkPreviewTimer.isValid {
            if let link = detectLink() {
                startLinkDetectionTimer(with: link)
            }
        }
    }
    
    private func detectLink() -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = linkDetector.matches(in: text,
                                      options: [],
                                        range: NSRange(location: 0, length: text.utf16.count))
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
    
    private func startLinkDetectionTimer(with link: URL?) {
        linkPreviewURL = link
        linkPreviewTimer = Timer.scheduledTimer(timeInterval: 1,
                                                      target: self,
                                                    selector: #selector(updateLinkDetectionTimer),
                                                    userInfo: nil,
                                                     repeats: true)
    }
    
    @objc
    private func updateLinkDetectionTimer() {
        linkPreviewTimer.invalidate()
        // After waiting for 1 second, if the url did not change, fetch link preview info
        if let url = detectLink() {
            if url == linkPreviewURL {
                // Have we already fetched the link? then do not fetch again
                // have we previously fetched the link and it was invalid? then do not fetch again
                if self.linkPreviewData?.url == linkPreviewURL || linkPreviewURL == invalidLinkPreviewURL {
                    return
                }
                fetchURLPreview()
            } else {
                // link has changed... reset link fetch cycle
                startLinkDetectionTimer(with: url)
            }
        }
    }

    private func fetchURLPreview() {
        guard let link = linkPreviewURL else { return }
        
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = 10

        LinkPreviewMetadataProvider.startFetchingMetadata(for: link) { [weak self] (metadata, preview ,error) in
            guard let data = metadata, error == nil else {
                // Error fetching link preview; remove link preview loading state
                self?.invalidLinkPreviewURL = link
                DispatchQueue.main.async {
                    self?.resetLinkDetection()
                }
              return
            }
            
            DispatchQueue.main.async {
                self?.linkPreviewData = data
                self?.linkPreviewMetadata.send(.fetched((preview, data)))
            }
        }
        
        linkPreviewMetadata.send(.fetching)
    }
    
    func resetLinkDetection() {
        linkPreviewTimer.invalidate()
        linkPreviewURL = nil
        invalidLinkPreviewURL = nil
        linkPreviewData = nil
        linkPreviewMetadata.send(.fetched(nil))
    }
}

// MARK: - mentions

extension ContentTextView {
    func update(from input: MentionInput) {
        text = input.text
        mentions = input.mentions
        selectedRange = input.selectedRange
        
        delegate?.textViewDidChange?(self)
    }
    
    /**
     Accepts a mention that was selected from the mention picker.
     */
    func accept(mention: MentionableUser) {
        guard let candidateRange = mentionInput.rangeOfMentionCandidateAtCurrentPosition() else {
            return
        }
        
        let ns = NSRange(candidateRange, in: text)
        addMention(name: mention.fullName, userID: mention.userID, in: ns)
    }
    
    func addMention(name: String, userID: UserID, in range: NSRange) {
        var input = mentionInput
        input.addMention(name: name, userID: userID, in: range)
        update(from: input)
    }
    
    func shouldChangeMentionText(in range: NSRange, text: String) -> Bool {
        var input = MentionInput(text: self.text, mentions: mentions, selectedRange: self.selectedRange)
        let rangeIncludingImpactedMentions = input.impactedMentionRanges(in: range)
                                                  .reduce(range) { range, mention in NSUnionRange(range, mention) }
        
        input.changeText(in: rangeIncludingImpactedMentions, to: text)
        if range == rangeIncludingImpactedMentions {
            mentions = input.mentions
            return true
        } else {
            update(from: input)
            return false
        }
    }
    
    func resetMentions() {
        mentions.removeAll()
    }
}
