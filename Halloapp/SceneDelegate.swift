//
//  SceneDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import UIKit

class SceneDelegate: UIResponder {

    var window: UIWindow?

    private var cancellables = Set<AnyCancellable>()

    enum UserInterfaceState {
        case expiredVersion
        case registration
        case mainInterface
    }

    private var userInterfaceState: UserInterfaceState?

    private func viewController(forUserInterfaceState state: UserInterfaceState) -> UIViewController? {
        switch state {
        case .registration:
            return VerificationViewController()

        case .mainInterface:
            return HomeViewController()

        case .expiredVersion:
            return ExpiredVersionViewController()
        }
    }

    private func state(isLoggedIn: Bool, isAppVersionKnownExpired: Bool) -> UserInterfaceState {
        if isAppVersionKnownExpired {
            return .expiredVersion
        }
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
        DDLogInfo("application/sceneWillConnect")

        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            if let tintColor = UIColor(named: "Tint") {
                window.tintColor = tintColor
            }
            self.window = window
            window.makeKeyAndVisible()
        }

        cancellables.insert(
            MainAppContext.shared.userData.$isLoggedIn.sink { [weak self] isLoggedIn in
                guard let self = self else { return }
                self.transition(to: self.state(isLoggedIn: isLoggedIn, isAppVersionKnownExpired: MainAppContext.shared.coreService.isAppVersionKnownExpired.value))
        })

        cancellables.insert(
            MainAppContext.shared.coreService.didConnect.sink { [weak self] in
                self?.checkClientVersionExpiration()
        })

        cancellables.insert(
            MainAppContext.shared.coreService.isAppVersionKnownExpired.sink { [weak self] isExpired in
                guard let self = self else { return }
                self.transition(to: self.state(isLoggedIn: MainAppContext.shared.userData.isLoggedIn, isAppVersionKnownExpired: isExpired))
        })
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

        // Clear icon badges (currently used to track only chat messages)
        // Set to -1 instead of 0
        // If set to 0 from X, iOS will delete all local notifications including feed, comments, messages, etc.
        MainAppContext.shared.applicationIconBadgeNumber = -1

        // Initial permissions request initiated by RegistrationManager. Request here only if we're already logged in when the app starts.
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate, MainAppContext.shared.userData.isLoggedIn && scene.activationState == .foregroundActive {
            appDelegate.requestAccessToContactsAndNotifications()
        }

        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
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
        
        MainAppContext.shared.mergeSharedData()

        // Need to tell XMPPStream to start connecting every time app is foregrounded
        // because XMPPReconnect won't keep the connection alive unless stream has authenticated
        // at least once since initialization time.
        MainAppContext.shared.service.startConnectingIfNecessary()
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

// App expiration

private extension SceneDelegate {
    private func presentAppUpdateWarning() {
        let alert = UIAlertController(title: Localizations.appUpdateNoticeTitle, message: Localizations.appUpdateNoticeText, preferredStyle: UIAlertController.Style.alert)
        let updateAction = UIAlertAction(title: Localizations.buttonUpdate, style: .default, handler: { action in
            DDLogInfo("SceneDelegate/updateNotice/update clicked")
            let urlString = "itms-apps://apple.com/app/1501583052"
            guard let customAppURL = URL(string: urlString),
                  UIApplication.shared.canOpenURL(customAppURL) else
            {
                DDLogError("SceneDelegate/updateNotice/error unable to open \(urlString)")
                return
            }
            UIApplication.shared.open(customAppURL, options: [:], completionHandler: nil)
        })
        let dismissAction = UIAlertAction(title: Localizations.buttonDismiss, style: .default, handler: { action in
            DDLogInfo("SceneDelegate/updateNotice/dismiss clicked")
        })
        alert.addAction(updateAction)
        alert.addAction(dismissAction)
        window?.rootViewController?.present(alert, animated: true, completion: nil)
    }

    private func checkClientVersionExpiration() {
        MainAppContext.shared.service.checkVersionExpiration { result in
            guard case .success(let numSecondsLeft) = result else {
                DDLogError("Client version check did not return expiration")
                return
            }

            let numDaysLeft = numSecondsLeft/86400
            if numDaysLeft < 10 {
                DDLogInfo("SceneDelegate/updateNotice/days left: \(numDaysLeft)")
                self.presentAppUpdateWarning()
            }
        }
    }
}

extension Localizations {

    static var appUpdateNoticeTitle: String {
        NSLocalizedString("home.update.notice.title", value: "This version is out of date", comment: "Title of update notice shown to users who have old versions of the app")
    }

    static var appUpdateNoticeText: String {
        NSLocalizedString("home.update.notice.text", value: "Please update to the latest version of HalloApp", comment: "Text shown to users who have old versions of the app")
    }

    static var appUpdateNoticeButtonExit: String {
        NSLocalizedString("home.update.notice.button.exit", value: "Exit", comment: "Title for exit button that closes the app")
    }
}
