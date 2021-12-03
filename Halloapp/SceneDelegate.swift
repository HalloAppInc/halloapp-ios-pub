//
//  SceneDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import Intents
import UIKit

class SceneDelegate: UIResponder {

    var window: UIWindow?

    private var cancellables = Set<AnyCancellable>()

    enum UserInterfaceState {
        case expiredVersion
        case initializing
        case registration
        case mainInterface
        case call
    }

    private var userInterfaceState: UserInterfaceState?

    private func viewController(forUserInterfaceState state: UserInterfaceState) -> UIViewController? {
        switch state {
        case .initializing:
            return InitializingViewController()

        case .registration:
            guard let registrationManager = makeRegistrationManager() else {
                DDLogError("SceneDelegate/viewController/registration/error [no-registration-manager]")
                return nil
            }
            return VerificationViewController(registrationManager: registrationManager)

        case .mainInterface:
            return HomeViewController()

        case .expiredVersion:
            return ExpiredVersionViewController()

        case .call:
            return makeCallViewController()
        }
    }

    private func state(isLoggedIn: Bool? = nil, isAppVersionKnownExpired: Bool? = nil) -> UserInterfaceState
    {
        if isAppVersionKnownExpired ?? MainAppContext.shared.coreService.isAppVersionKnownExpired.value {
            return .expiredVersion
        }

        if isInCallUI {
            return .call
        }

        if isLoggedIn ?? MainAppContext.shared.userData.isLoggedIn {
            let initializationComplete = ContactStore.contactsAccessDenied ||
                (ContactStore.contactsAccessAuthorized && MainAppContext.shared.contactStore.isInitialSyncCompleted)
            return initializationComplete ? .mainInterface : .initializing
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

    private func makeRegistrationManager() -> RegistrationManager? {
        guard let noiseKeys = MainAppContext.shared.userData.loggedOutNoiseKeys else {
            DDLogError("SceneDelegate/makeRegistrationManager/error [no-noise-keys]")
            return nil
        }
        let noiseService = NoiseRegistrationService(noiseKeys: noiseKeys)
        return DefaultRegistrationManager(registrationService: noiseService)
    }

    private var isInCallUI = false {
        didSet {
            if isInCallUI != oldValue {
                transition(to: state())
            }
        }
    }
    private func makeCallViewController() -> CallViewController {
        // TODO: SceneDelegate shouldn't worry about these details.
        let peerUserID = MainAppContext.shared.callManager.peerUserID ?? ""
        let isOutgoing = MainAppContext.shared.callManager.isOutgoing ?? false
        return CallViewController(peerUserID: peerUserID, isOutgoing: isOutgoing)
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
                self.transition(to: self.state(isLoggedIn: isLoggedIn))
        })

        cancellables.insert(
            MainAppContext.shared.coreService.isAppVersionKnownExpired.sink { [weak self] isExpired in
                guard let self = self else { return }
                self.transition(to: self.state(isAppVersionKnownExpired: isExpired))
        })

        cancellables.insert(
            MainAppContext.shared.syncManager.$isSyncInProgress.sink { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.transition(to: self.state())
                }
        })

        cancellables.insert(
            MainAppContext.shared.contactStore.contactsAccessRequestCompleted.sink { [weak self] isContactAccessAuthorized in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.transition(to: self.state())
                }
        })

        cancellables.insert(
            MainAppContext.shared.coreService.isAppVersionCloseToExpiry.sink { [weak self] isCloseToExpiry in
                guard let self = self else { return }
                if isCloseToExpiry {
                    self.presentAppUpdateWarning()
                }
        })

        cancellables.insert(
            MainAppContext.shared.callManager.isAnyCallActive.sink { call in
                DispatchQueue.main.async {
                    if UIApplication.shared.applicationState == .background {
                        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
                        if call == nil {
                            appDelegate.beginBackgroundConnectionTask()
                        } else {
                            appDelegate.endBackgroundConnectionTask()
                            appDelegate.resumeMediaDownloads()
                        }
                    }

                    self.isInCallUI = call != nil
                }
        })
        
        // explicitly call delegates for group invites for first app start up
        // wait a second or so for app to connect
        if let userActivity = connectionOptions.userActivities.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.scene(scene, continue: userActivity)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.scene(scene, openURLContexts: connectionOptions.urlContexts)
            }
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

        // Clear icon badges (currently used to track only chat messages)
        // Set to -1 instead of 0
        // If set to 0 from X, iOS will delete all local notifications including feed, comments, messages, etc.
        MainAppContext.shared.applicationIconBadgeNumber = -1

        // Load pushnames and pushnumbers from core data when app comes into the foreground,
        // needed in the case when app is in the background and notification share extension (NSE) adds a new pushname/number,
        // could be made more efficient by only loading when we know there are new additions from NSE
        MainAppContext.shared.contactStore.loadPushNamesAndNumbers()

        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        MainAppContext.shared.contactStore.reloadContactsIfNecessary()
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
        appDelegate.resumeMediaDownloads()

        DispatchQueue.main.async {
            appDelegate.checkNotificationsAuthorizationStatus()
        }

        guard MainAppContext.shared.userData.isLoggedIn else { return }

        MainAppContext.shared.mergeSharedData()

        // Need to tell XMPPStream to start connecting every time app is foregrounded
        // because XMPPReconnect won't keep the connection alive unless stream has authenticated
        // at least once since initialization time.
        MainAppContext.shared.service.startConnectingIfNecessary()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        DDLogInfo("application/didEnterBackground")

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        if MainAppContext.shared.callManager.activeCall == nil {
            appDelegate.beginBackgroundConnectionTask()
        }

        // Schedule periodic data refresh in the background.
        if MainAppContext.shared.userData.isLoggedIn {
            appDelegate.scheduleFeedRefresh(after: Date.hours(2))
        }
    }

    // handles halloapp:// custom schema while app is either in foreground or background
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        DDLogInfo("application/scene/openURLContexts")
        guard let url = URLContexts.first?.url else { return }
        guard let inviteToken = ChatData.parseInviteURL(url: url) else { return }
        DDLogInfo("application/scene/openURLContexts/url \(url)")
        processGroupInviteToken(inviteToken)
    }

    // handles invite url while app is either in foreground or background
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        DDLogInfo("application/scene/continue")
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            guard let incomingURL = userActivity.webpageURL else { return }
            guard let inviteToken = ChatData.parseInviteURL(url: incomingURL) else { return }
            DDLogInfo("application/scene/continue/incomingURL \(incomingURL)")
            processGroupInviteToken(inviteToken)
        }
        
        if let intent = userActivity.interaction?.intent {
            MainAppContext.shared.didTapIntent.send(intent)
        }
    }
}

// App expiration

private extension SceneDelegate {
    private func presentAppUpdateWarning() {
        let alert = UIAlertController(title: Localizations.appUpdateNoticeTitle, message: Localizations.appUpdateNoticeText, preferredStyle: UIAlertController.Style.alert)
        let updateAction = UIAlertAction(title: Localizations.buttonUpdate, style: .default, handler: { action in
            DDLogInfo("SceneDelegate/updateNotice/update clicked")
            guard let customAppURL = AppContext.appStoreURL,
                  UIApplication.shared.canOpenURL(customAppURL) else
            {
                DDLogError("SceneDelegate/updateNotice/error unable to open [\(AppContext.appStoreURL?.absoluteString ?? "nil")]")
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
    
    private func processGroupInviteToken(_ inviteToken: String) {
        MainAppContext.shared.userData.groupInviteToken = inviteToken
        MainAppContext.shared.didGetGroupInviteToken.send()
    }
}
