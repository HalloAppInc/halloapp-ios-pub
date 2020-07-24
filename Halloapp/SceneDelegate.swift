//
//  SceneDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import SwiftUI
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        DDLogInfo("application/sceneWillConnect")

        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        // Use a UIHostingController as window root view controller.
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: Landing())
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        DDLogInfo("application/sceneDidDisconnect")

        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        DDLogInfo("application/didBecomeActive")

        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.requestAccessToContactsAndNotifications()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        DDLogInfo("application/willResignActive")

        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        DDLogInfo("application/willEnterForeground")

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        appDelegate.endBackgroundConnectionTask()

        DispatchQueue.main.async {
            appDelegate.checkNotificationsAuthorizationStatus()
        }

        // Need to tell XMPPStream to start connecting every time app is foregrounded
        // because XMPPReconnect won't keep the connection alive unless stream has authenticated
        // at least once since initialization time.
        MainAppContext.shared.xmppController.startConnectingIfNecessary()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        DDLogInfo("application/didEnterBackground")

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        appDelegate.beginBackgroundConnectionTask()

        // Schedule periodic data refresh in the background.
        if MainAppContext.shared.userData.isLoggedIn {
            appDelegate.scheduleFeedRefresh(after: Date.minutes(5))
        }
    }
}
