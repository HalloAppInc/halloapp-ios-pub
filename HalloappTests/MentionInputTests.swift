//
//  MentionInputTests.swift
//  HalloAppTests
//
//  Created by Garrett on 8/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import XCTest
@testable import HalloApp

class MentionInputTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func makeInput(text: String = "", mentions: [NSRange: UserID] = [:], selectedRange: NSRange? = nil) -> MentionInput {
        return MentionInput(
            text: text,
            mentions: mentions,
            selectedRange: selectedRange ?? NSRange(location: text.count, length: 0))
    }

    func testAddMentionToEmptyInput() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        XCTAssert(input.text == "@Alice ")
        XCTAssert(input.mentions[NSRange(location: 0, length: 6)] == "AA")
        XCTAssert(input.selectedRange == NSRange(location: 7, length: 0))
    }

    func testAddMentionDoesNotChangeEarlierMentions() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        input.addMention(name: "Bob", userID: "BBB", in: NSRange(location: 7, length: 0))
        XCTAssert(input.text == "@Alice @Bob ")
        XCTAssert(input.mentions[NSRange(location: 0, length: 6)] == "AA")
        XCTAssert(input.mentions[NSRange(location: 7, length: 4)] == "BBB")
        XCTAssert(input.selectedRange == NSRange(location: 12, length: 0))
    }

    func testAddMentionShiftsLaterMentions() throws {
        var input = makeInput()
        input.addMention(name: "Bob", userID: "BBB", in: NSRange(location: 0, length: 0))
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        XCTAssert(input.text == "@Alice @Bob ")
        XCTAssert(input.mentions[NSRange(location: 0, length: 6)] == "AA")
        XCTAssert(input.mentions[NSRange(location: 7, length: 4)] == "BBB")
        XCTAssert(input.selectedRange == NSRange(location: 7, length: 0))
    }

    func testAddMentionRange() throws {
        var input = makeInput(text: "Some @ text")
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 5, length: 1))
        // NB: We always insert an extra space after the mention
        XCTAssert(input.text == "Some @Alice  text")
        XCTAssert(input.mentions[NSRange(location: 5, length: 6)] == "AA")
        XCTAssert(input.selectedRange == NSRange(location: 12, length: 0))
    }

    func testChangeTextShiftsLaterMentions() throws {
        var input = makeInput()
        input.addMention(name: "Alice", userID: "AA", in: NSRange(location: 0, length: 0))
        input.changeText(in: NSRange(location: 0, length: 0), to: "Hello ")
        XCTAssert(input.text == "Hello @Alice ")
        XCTAssert(input.mentions[NSRange(location: 6, length: 6)] == "AA")
        XCTAssert(input.selectedRange == NSRange(location: 6, length: 0))
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
        XCTAssert(input.impactedMentionRanges(in: aliceRange) == [aliceRange])
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 4, length: 0)) == [aliceRange])
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 1, length: 2)) == [aliceRange])
        XCTAssert(input.impactedMentionRanges(in: bobRange) == [bobRange])
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 6, length: 3)) == [bobRange])

        // Multiple intersections
        XCTAssert(input.impactedMentionRanges(in: input.text.fullExtent).sorted { $0.location < $1.location } == [aliceRange, bobRange])
        XCTAssert(input.impactedMentionRanges(in: NSRange(location: 3, length: 8)).sorted { $0.location < $1.location } == [aliceRange, bobRange])
    }
}
