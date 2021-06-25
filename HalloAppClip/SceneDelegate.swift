//
//  SceneDelegate.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import UIKit

class SceneDelegate: UIResponder {

    var window: UIWindow?

    private var cancellables = Set<AnyCancellable>()

    enum UserInterfaceState {
        case registration
        case mainInterface
    }

    private var userInterfaceState: UserInterfaceState?

    private func viewController(forUserInterfaceState state: UserInterfaceState) -> UIViewController? {
        switch state {
        case .registration:
            return VerificationViewController()

        case .mainInterface:
            return AppClipHomeViewController()
        }
    }

    private func state(isLoggedIn: Bool) -> UserInterfaceState {
        if isLoggedIn {
            return .mainInterface
        }
        return .registration
    }

    private func transition(to newState: UserInterfaceState) {
        guard newState != userInterfaceState else { return }
        DDLogInfo("SceneDelegate/transition [\(newState)]")
        userInterfaceState = newState
        if let viewController = viewController(forUserInterfaceState: newState) {
            window?.rootViewController = viewController
        }
    }

}

extension SceneDelegate: UIWindowSceneDelegate {

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            if let tintColor = UIColor(named: "Tint") {
                window.tintColor = tintColor
            }
            self.window = window
            window.makeKeyAndVisible()
        }

        cancellables.insert(
            AppClipContext.shared.userData.$isLoggedIn.sink { [weak self] isLoggedIn in
                guard let self = self else { return }
                self.transition(to: self.state(isLoggedIn: isLoggedIn))
        })
        
        // Parse incoming app clip URL for groupInviteToken
        if let userActivity = connectionOptions.userActivities.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.scene(scene, continue: userActivity)
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        // Save changes in the application's managed object context when the application transitions to the background.
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        DDLogInfo("application/scene/continue")
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        guard let incomingURL = userActivity.webpageURL else { return }
        DDLogInfo("application/scene/continue/incomingURL \(incomingURL)")
        guard let inviteToken = parseInviteURL(url: incomingURL) else { return }
        processGroupInviteToken(inviteToken)
    }

    func parseInviteURL(url: URL?) -> String? {
        guard let url = url else { return nil }
        guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }

        guard let scheme = components.scheme?.lowercased() else { return nil }
        guard let host = components.host?.lowercased() else { return nil }
        guard let path = components.path?.lowercased() else { return nil }

        if scheme == "https" {
            guard host == "halloapp.com" || host == "www.halloapp.com" else { return nil }
            guard path == "/invite/" else { return nil }
        } else if scheme == "halloapp" {
            guard host == "invite" else { return nil }
            guard path == "/" else { return nil }
        } else {
            return nil
        }

        guard let params = components.queryItems else { return nil }
        guard let inviteToken = params.first(where: { $0.name == "g" })?.value else { return nil }

        return inviteToken
    }

    private func processGroupInviteToken(_ inviteToken: String) {
        AppClipContext.shared.userData.groupInviteToken = inviteToken
    }
}

