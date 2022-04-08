//
//  URLRouterTests.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import XCTest
@testable import HalloApp

class URLRouterTests: XCTestCase {

    func testAppLinks() {
        let expectation = expectation(description: "Should handle route")
        let router = URLRouter(hosts: [
            URLRouter.Host(domains: [URLRouter.applinkHost], routes: [
                URLRouter.Route(path: "/foo/bar", handler: { _ in
                    expectation.fulfill()
                    return true
                })
            ])
        ])
        router.handle(url: URL(string: "halloapp://foo/bar")!)
        waitForExpectations(timeout: 1)
    }

    func testUniversalLinks() {
        let expectation = expectation(description: "Should handle route")
        expectation.expectedFulfillmentCount = 4
        let router = URLRouter(hosts: [
            URLRouter.Host(domains: ["www.halloapp.com", "halloapp.com"], routes: [
                URLRouter.Route(path: "/foo/bar", handler: { _ in
                    expectation.fulfill()
                    return true
                })
            ])
        ])
        for scheme in ["http", "https"] {
            for domain in ["www.halloapp.com", "halloapp.com"] {
                router.handle(url: URL(string: "\(scheme)://\(domain)/foo/bar")!)
            }
        }
        waitForExpectations(timeout: 1)
    }

    func testRouteParameters() {
        let expectation = expectation(description: "Should handle route")
        expectation.expectedFulfillmentCount = 2

        let router = URLRouter(hosts: [
            URLRouter.Host(domains: [URLRouter.applinkHost, "halloapp.com"], routes: [
                URLRouter.Route(path: "/:foo/bar/:baz", handler: { params in
                    XCTAssertEqual(params["foo"], "value1")
                    XCTAssertEqual(params["baz"], "value2")
                    XCTAssertEqual(params.count, 2)
                    expectation.fulfill()
                    return true
                })
            ])
        ])

        router.handle(url: URL(string: "halloapp://value1/bar/value2")!)
        router.handle(url: URL(string: "https://halloapp.com/value1/bar/value2")!)
        waitForExpectations(timeout: 1)
    }

    func testUrlParameters() {
        let expectation = expectation(description: "Should handle route")
        expectation.expectedFulfillmentCount = 2

        let router = URLRouter(hosts: [
            URLRouter.Host(domains: [URLRouter.applinkHost, "halloapp.com"], routes: [
                URLRouter.Route(path: "/foo", handler: { params in
                    XCTAssertEqual(params["bar"], "value1")
                    XCTAssertEqual(params["baz"], "value2")
                    XCTAssertEqual(params.count, 2)
                    expectation.fulfill()
                    return true
                })
            ])
        ])

        router.handle(url: URL(string: "halloapp://foo?bar=value1&baz=value2")!)
        router.handle(url: URL(string: "https://halloapp.com/foo?bar=value1&baz=value2")!)
        waitForExpectations(timeout: 1)
    }

    func testFragment() {
        let expectation = expectation(description: "Should handle route")

        let router = URLRouter(hosts: [
            URLRouter.Host(domains: ["halloapp.com"], routes: [
                URLRouter.Route(path: "/test", handler: { params in
                    XCTAssertEqual(params[URLRouter.fragmentParameter], "fragment")
                    XCTAssertEqual(params.count, 1)
                    expectation.fulfill()
                    return true
                })
            ])
        ])

        router.handle(url: URL(string: "https://halloapp.com/test#fragment")!)
        waitForExpectations(timeout: 1)
    }

    func testParameterOverrides() {
        let expectation = expectation(description: "Should handle route")

        let router = URLRouter(hosts: [
            URLRouter.Host(domains: ["halloapp.com"], routes: [
                URLRouter.Route(path: "/test/:bar", handler: { params in
                    XCTAssertEqual(params["bar"], "url")
                    XCTAssertEqual(params.count, 1)
                    expectation.fulfill()
                    return true
                })
            ])
        ])

        router.handle(url: URL(string: "https://halloapp.com/test/url?bar=query")!)
        waitForExpectations(timeout: 1)
    }
}
