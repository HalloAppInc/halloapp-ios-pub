//
//  URLRouter.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/24/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreCommon
import Foundation

class URLRouter {

    static let shared: URLRouter = {
        var routes: [Route] = []
        routes.append(Route(path: "/invite") { params in
            guard let inviteToken = params["g"] else {
                return
            }
            MainAppContext.shared.userData.groupInviteToken = inviteToken
            MainAppContext.shared.didGetGroupInviteToken.send()
        })
        routes.append(Route(path: "/appclip") { params in
            guard let inviteToken = params["g"] else {
                return
            }
            MainAppContext.shared.userData.groupInviteToken = inviteToken
            MainAppContext.shared.didGetGroupInviteToken.send()
        })

        var shareRoutes: [Route] = []
        shareRoutes.append(Route(path: "/:blobID") { params in
            guard let blobID = params["blobID"],
                  let key = params[URLRouter.fragmentParameter].flatMap({ fragment -> Data? in
                      var key = fragment
                      if key.hasPrefix("k") {
                          key = String(fragment.dropFirst())
                      }
                      return Data(base64urlEncoded: key)
                  }) else {
                return
            }
            MainAppContext.shared.feedData.externalSharePost(with: blobID, key: key) { result in
                guard let currentViewController = UIViewController.currentViewController else {
                    DDLogError("URLRouter/Unable to find currentViewController")
                    return
                }

                switch result {
                case .success(let post):
                    currentViewController.present(PostViewController(post: post), animated: true)
                case .failure(let error):
                    DDLogError("URLRouter/Failed to decrypt external share post: \(error)")
                    let alertController = UIAlertController(title: Localizations.failedToLoadExternalSharePost, message: nil, preferredStyle: .alert)
                    alertController.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
                    currentViewController.present(alertController, animated: true)
                }
            }
        })

        return URLRouter(hosts: [
            Host(domains: ["share.halloapp.com"], routes: shareRoutes),
            Host(domains: [
                URLRouter.applinkHost,
                "halloapp.com",
                "www.halloapp.com",
                "invite.halloapp.com"
            ], routes: routes)
        ])
    }()

    typealias Params = [String: String]

    struct Host {
        let domains: Set<String>
        let routes: [Route]

        init(domains: [String], routes: [Route]) {
            self.domains = Set(domains)
            self.routes = routes
        }
    }

    static let applinkHost = "applink"
    static let fragmentParameter = "urlFragment"

    struct Route {
        enum PathComponent {
            case path(path: String), parameter(name: String)
        }

        let pathComponents: [PathComponent]
        let handler: ([String: String]) -> Void

        init(path: String, handler: @escaping (Params) -> Void) {
            self.pathComponents = path.split(separator: "/").map { component in
                if component.hasPrefix(":") {
                    return .parameter(name: String(component.dropFirst()))
                } else {
                    return .path(path: String(component))
                }
            }
            self.handler = handler
        }
    }

    private var hosts: [Host]

    init(hosts: [Host]) {
        self.hosts = hosts
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let (route, params) = route(for: url) else {
            DDLogInfo("URLRouter/No matching route found for \(url)")
            return false
        }
        DDLogInfo("URLRouter/Found matching route and will handle \(url)")
        route.handler(params)
        return true
    }

    func handleOrOpen(url: URL) {
        if !handle(url: url) {
            UIApplication.shared.open(url)
        }
    }
}

extension URLRouter {

    private func route(for url: URL) -> (Route, Params)? {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard let scheme = urlComponents.scheme?.lowercased(),
              var host = urlComponents.host?.lowercased() else {
            return nil
        }

        var urlPathComponents = Array(urlComponents.path.split(separator: "/").map { String($0) })

        switch scheme {
        case "http", "https":
            break
        case "halloapp":
            // For halloapp:// urls, the host will be the first part of the path
            urlPathComponents.insert(host, at: 0)
            host = Self.applinkHost
        default:
            return nil
        }

        guard let routes = hosts.first(where: { $0.domains.contains(host) })?.routes else {
            return nil
        }

        var params: Params = [:]
        let route = routes.first { route in
            guard route.pathComponents.count == urlPathComponents.count else {
                return false
            }
            params = [:]
            return zip(route.pathComponents, urlPathComponents).allSatisfy { (routePathComponent, urlPathComponent) in
                switch routePathComponent {
                case .parameter(let name):
                    params[name] = urlPathComponent
                    return true
                case .path(let path):
                    return path == urlPathComponent
                }
            }
        }

        guard let route = route else {
            return nil
        }

        // Route parameters trump query parameters
        if let queryParams = urlComponents.queryItems?.reduce(into: [:], { $0[$1.name] = $1.value }) {
            params.merge(queryParams) { (current, _) in current }
        }

        // Add in fragment
        params[Self.fragmentParameter] = urlComponents.fragment

        return (route, params)
    }
}

extension Localizations {

    static var failedToLoadExternalSharePost: String {
        NSLocalizedString("urlrouter.externalShare.failed",
                          value: "Failed to load post",
                          comment: "Alert appearing after clicking an external share link that failed to load")
    }
}
