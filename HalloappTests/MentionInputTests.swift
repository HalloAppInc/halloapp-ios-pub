//
//  MentionInputTests.swift
//  HalloAppTests
//
//  Created by Garrett on 8/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import XCTest
@testable import HalloApp

fileprivate extension MentionInput {
    func mentionedUser(for range: NSRange) -> UserID! {
        guard let mention = self.mentions[range] else {
            XCTFail("Mentioned user was nil")
            return nil
        }
        return mention.userID
    }
}

class MentionInputTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func makeInput(text: String = "", mentions: MentionRangeMap = [:], selectedRange: NSRange? = nil) -> MentionInput {
        return MentionInput(
            text: text,
            mentions: mentions,
            selectedRange: selectedRange ?? NSRange(location: (text as NSString).length, length: 0))
    }

    func testAddMentionToEmptyInput() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        XCTAssertEqual(input.text, "@Alice ")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 0, length: 6)), "AA")
        XCTAssertEqual(input.selectedRange, NSRange(location: 7, length: 0))
    }

    func testAddMentionDoesNotChangeEarlierMentions() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        input.addMention(name: "Bob", userID: "BBB", in: NSRange(location: 7, length: 0))
        XCTAssertEqual(input.text, "@Alice @Bob ")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 0, length: 6)), "AA")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 7, length: 4)), "BBB")
        XCTAssertEqual(input.selectedRange, NSRange(location: 12, length: 0))
    }

    func testAddMentionShiftsLaterMentions() throws {
        var input = makeInput()
        input.addMention(name: "Bob", userID: "BBB", in: NSRange(location: 0, length: 0))
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        XCTAssertEqual(input.text, "@Alice @Bob ")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 0, length: 6)), "AA")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 7, length: 4)), "BBB")
        XCTAssertEqual(input.selectedRange, NSRange(location: 7, length: 0))
    }
    
    func testAddMentionRange() throws {
        var input = makeInput(text: "Some @ text")
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 5, length: 1))
        // NB: We always insert an extra space after the mention
        XCTAssertEqual(input.text, "Some @Alice  text")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 5, length: 6)), "AA")
        XCTAssertEqual(input.selectedRange, NSRange(location: 12, length: 0))
    }

    func testChangeTextShiftsLaterMentions() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        input.changeText(in: NSRange(location: 0, length: 0), to: "Hello ")
        XCTAssertEqual(input.text, "Hello @Alice ")
        XCTAssertEqual(input.mentionedUser(for: NSRange(location: 6, length: 6)), "AA")
        XCTAssertEqual(input.selectedRange, NSRange(location: 6, length: 0))
    }

    func testImpactedMentionRanges() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        input.addMention(name: "Bob", userID: "BBB", in: NSRange(location: 7, length: 0))

        let aliceRange = NSRange(location: 0, length: 6)
        let bobRange = NSRange(location: 7, length: 4)

        // Adjacent cursor positions do not impact mentions
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 0, length: 0)).isEmpty)
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 6, length: 0)).isEmpty)
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 6, length: 1)).isEmpty)
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 11, length: 0)).isEmpty)
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 12, length: 0)).isEmpty)

        // Single intersections
        XCTAssertEqual(input.impactedMentionRanges(in: aliceRange), [aliceRange])
        XCTAssertEqual(input.impactedMentionRanges(in: NSRange(location: 4, length: 0)), [aliceRange])
        XCTAssertEqual(input.impactedMentionRanges(in: NSRange(location: 1, length: 2)), [aliceRange])
        XCTAssertEqual(input.impactedMentionRanges(in: bobRange), [bobRange])
        XCTAssertEqual(input.impactedMentionRanges(in: NSRange(location: 6, length: 3)), [bobRange])

        // Multiple intersections
        XCTAssertEqual(input.impactedMentionRanges(in: input.text.utf16Extent).sorted { $0.location < $1.location }, [aliceRange, bobRange])
        XCTAssertEqual(input.impactedMentionRanges(in: NSRange(location: 3, length: 8)).sorted { $0.location < $1.location }, [aliceRange, bobRange])
    }
    
    func testRangeOfMentionCandidate() throws {
        var input = makeInput(text: "@@Alice@🇺🇸🤞🏻@Bob \n日本語＠ガーレト　فرسی @Carol", mentions: [:], selectedRange: nil)

        let firstIndex = input.text.startIndex
        let secondIndex = input.text.index(after: firstIndex)
        let thirdIndex = input.text.index(after: secondIndex)

        // Returns nil if cursor is at start of text
        input.selectedRange = NSRange(location: 0, length: 0)
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == nil)

        // "@|@": Only includes characters before the cursor
        input.selectedRange = NSRange(location: 1, length: 0)
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == firstIndex..<secondIndex)

        // "@[@]": Returns nil if selection has non-zero length
        input.selectedRange = NSRange(location: 1, length: 1)
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == nil)

        // "@@|": Only includes most recent "@"
        input.selectedRange = NSRange(location: 2, length: 0)
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == secondIndex..<thirdIndex)

        // Helper to update selectedRange (UTF-16) so we can test conversion to String.Index (encoding agnostic)
        let moveCursorToEndOfSubstring: (String) -> Void = { substring in
            let utf16range = (input.text as NSString).range(of: substring)
            input.selectedRange = NSRange(location: NSMaxRange(utf16range), length: 0)
        }

        // Range is returned if no mentions overlap
        moveCursorToEndOfSubstring("@Alic")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == input.text.range(of: "@Alic"))

        // Returns nil if there is an overlapping mention
        input.mentions[(input.text as NSString).range(of: "@Ali")] = MentionedUser(userID: "AA", pushName: "Alice")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == nil)

        // Returns nil if the cursor is contained in an existing mention
        moveCursorToEndOfSubstring("@Al")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == nil)

        // Range is correct following complex emoji
        moveCursorToEndOfSubstring("@Bob")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == input.text.range(of: "@Bob"))

        // Range is correct following CJK characters
        moveCursorToEndOfSubstring("@ガー")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == input.text.range(of: "@ガー"))

        // Range is correct following RTL characters
        moveCursorToEndOfSubstring("@Carol")
        XCTAssert(input.rangeOfMentionCandidateAtCurrentPosition() == input.text.range(of: "@Carol"))

    }
}
