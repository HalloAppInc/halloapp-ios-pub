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
    private var codes = [HalloCode]()
    
    override func setUpWithError() throws {
        for url in HalloCodeTest.strings {
            for size in HalloCodeTest.sizes {
                // create the same code at different sizes
                guard let code = HalloCode(size: size, string: url) else {
                    throw HalloCodeError.couldNotCreate(url)
                }
                
                codes.append(code)
            }
        }
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
        
    /// Tests that our codes scan correctly.
    func testDecoding() throws {
        for code in codes {
            let decoded = decode(code)
            XCTAssertEqual(decoded, code.string)
        }
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

    private func decode(_ code: HalloCode) -> String? {
        let image = code.image
        guard
            let detector = CIDetector(ofType: CIDetectorTypeQRCode,context: nil,
                                     options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
            let ci = CIImage(image: image),
            let features = detector.features(in: ci) as? [CIQRCodeFeature],
            features.count > 0
        else {
            return nil
        }
        
        return features.first?.messageString
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
        "07037 65770 49341 33913 42533 54878 11403 98260 05887 37578 51633 28694",
        "Specifically, Apple’s security concerns relate to language in the bill that the company fears would allow iPhone and iPad users to download apps outside of the App Store. Powderly argued this provision could harm users who could download unscreened and potentially harmful software to their devices. If enacted, the bill would make it difficult for Apple to collect its sometimes 30 percent commissions from developers on App Store purchases."
    ]
    
    private static let sizes = [
        CGSize(width: 100, height: 100),
        CGSize(width: 200, height: 200),
        CGSize(width: 300, height: 300)
    ]
}
