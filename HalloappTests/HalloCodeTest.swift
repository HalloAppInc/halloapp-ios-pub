//
//  HalloCodeTest.swift
//  HalloAppTests
//
//  Created by Tanveer on 1/26/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import XCTest
@testable import HalloApp

extension HalloCodeTest {
    enum HalloCodeError: Error {
        /// Unable to create a code from the string.
        case couldNotCreate(String)
    }
}


/// For testing the creation and scannability of our custom QR codes.
class HalloCodeTest: XCTestCase {
    /// Tests that our codes scan correctly.
    func testDecoding() throws {
        for url in HalloCodeTest.strings {
            for size in HalloCodeTest.sizes {
                try autoreleasepool {
                    // create the same code at different sizes
                    guard let code = HalloCode(size: size, string: url) else {
                        throw HalloCodeError.couldNotCreate(url)
                    }

                    let decoded = decode(code)
                    XCTAssertEqual(decoded, code.string)
                }
            }
        }
    }

    private func decode(_ code: HalloCode) -> String? {
        let image = code.image
        guard
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
            let ci = CIImage(image: image),
            let features = detector.features(in: ci) as? [CIQRCodeFeature],
            features.count > 0
        else {
            return nil
        }

        return features.first?.messageString
    }
    
    /// Tests the performance of creating a large code.
    func testCodeCreationPerformance() throws {
        let url = HalloCodeTest.strings.last!
        let size = CGSize(width: 300, height: 300)
        
        let options = XCTMeasureOptions()
        options.iterationCount = 40
        
        self.measure(options: options) {
            guard let _ = HalloCode(size: size, string: url)?.image else {
                fatalError()
            }
        }
    }
}


// MARK: - inputs

extension HalloCodeTest {
    private static let strings = [
        "https://halloapp.com/invite/?g=M4jcot1UXWYPoUVCy2jL_e43",
        "https://projects.fivethirtyeight.com/2021-nfl-predictions/games/?ex_cid=rrpromo",
        "https://www.halloapp.com",
        "https://www.newyorker.com/magazine/1962/06/16/silent-spring-part-1",
        "https://www.matchadesign.com/news/blog/qr-code-demystified-part-1/",
        "https://www.rollingstone.com/culture/culture-news/revealed-uk-government-publicity-blitz-to-undermine-privacy-encryption-1285453/",
        "https://www.theverge.com/2021/7/19/22584551/halloapp-private-social-network-by-early-whatsapp-employees",
        "https://klim.co.nz/retail-fonts/epicene-display/",
        "hello",
        "https://raureif.net",
        "https://www.youtube.com/watch?v=26bgYpJOqcw",
        "https://www.newyorker.com/magazine/2021/12/13/on-succession-jeremy-strong-doesnt-get-the-joke",
        "https://www.nytimes.com",
        "https://www.nybooks.com/articles/2022/01/13/apotheosis-now/",
        "https://kottke.org",
        "https://www.theverge.com/2022/1/20/22893059/messenger-new-kids-internet-safety-games-facebook-meta",
    ]
    
    private static let sizes = [
        CGSize(width: 100, height: 100),
        CGSize(width: 200, height: 200),
        CGSize(width: 300, height: 300)
    ]
}
