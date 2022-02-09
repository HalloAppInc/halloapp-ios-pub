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
    var rootViewController = RootViewController()

    var callWindow: UIWindow?
    var callViewController: CallViewController?

    private var cancellables = Set<AnyCancellable>()

    private func state(isLoggedIn: Bool? = nil, isAppVersionKnownExpired: Bool? = nil) -> UserInterfaceState
    {
        if isAppVersionKnownExpired ?? MainAppContext.shared.coreService.isAppVersionKnownExpired.value {
            return .expiredVersion
        }

        if isLoggedIn ?? MainAppContext.shared.userData.isLoggedIn {
            let initializationComplete = ContactStore.contactsAccessDenied ||
                (ContactStore.contactsAccessAuthorized && MainAppContext.shared.contactStore.isInitialSyncCompleted)
            return initializationComplete ? .mainInterface : .initializing
        }

        return .registration
    }

    private func transition(to newState: UserInterfaceState) {
        rootViewController.transition(to: newState)
    }

    private func hideCallViewController() {
        guard let window = window, let callWindow = callWindow else {
            return
        }

        UIView.animate(
            withDuration: 0.3,
            animations:  {
                callWindow.alpha = 0
            },
            completion: { _ in
                window.makeKeyAndVisible()
                callWindow.windowScene = nil
                self.callWindow = nil
                self.callViewController = nil
            })
        MainAppContext.shared.coreService.sendPresenceIfPossible(.available)
    }

    private func showCallViewController(for call: Call, completion: (() -> Void)? = nil) {
        guard let window = window else { return }

        let callViewController = CallViewController(peerUserID: call.peerUserID, isOutgoing: call.isOutgoing) { [weak self] in
            self?.hideCallViewController()
        }

        let callWindow = UIWindow(frame: window.frame)
        callWindow.windowScene = window.windowScene
        callWindow.rootViewController = callViewController
        callWindow.alpha = 0
        callWindow.makeKeyAndVisible()

        UIView.animate(
            withDuration: 0.3,
            animations: { callWindow.alpha = 1 },
            completion: { _ in completion?() })

        self.callWindow = callWindow
        self.callViewController = callViewController
        MainAppContext.shared.coreService.sendPresenceIfPossible(.away)
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
            window.rootViewController = rootViewController
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
            MainAppContext.shared.callManager.isAnyCallOngoing.sink { call in
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

                    if call == nil {
                        // Animate call bar out if visible or hide it immediately if root VC is hidden
                        self.rootViewController.updateCallUI(with: call, animated: self.callViewController == nil)
                        self.hideCallViewController()
                    }
                }
        })

        cancellables.insert(
            MainAppContext.shared.callManager.didCallFail.sink {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState != .background else {
                        return
                    }
                    self.presentFailedCallAlertController()
                }
        })

        cancellables.insert(
            MainAppContext.shared.callManager.microphoneAccessDenied.sink {
                DispatchQueue.main.async {
                    guard UIApplication.shared.applicationState != .background else {
                        return
                    }
                    self.presentMicPermissionsAlertController()
                }
        })

        MainAppContext.shared.callManager.callViewDelegate = self
        rootViewController.delegate = self
        
        // explicitly call delegates for group invites for first app start up
        // wait a second or so for app to connect
        if let userActivity = connectionOptions.userActivities.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                self.scene(scene, continue: userActivity)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
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

        // Check pasteboard for group invite link on first launch in the ievent user
        // installed app via group invite link.
        checkPasteboardForGroupInviteLinkIfNecessary()
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
        DDLogInfo("application/scene/continue, type: \(userActivity.activityType)")
        switch userActivity.activityType {
        case NSUserActivityTypeBrowsingWeb:
            guard let incomingURL = userActivity.webpageURL else { return }
            guard let inviteToken = ChatData.parseInviteURL(url: incomingURL) else { return }
            DDLogInfo("application/scene/continue/incomingURL \(incomingURL)")
            processGroupInviteToken(inviteToken)

        // TODO: Do we need to use this intent to pop up people for share-intents? maybe?
        case "INStartAudioCallIntent", "INStartCallIntent":
            // We always try to fetch the contactIdentifier first.
            // Because user could be trying to make the call using siri (or) native-contacts app (or) native-calls app.
            // We lookup the contact and its userID to start call.
            // If that does not work: then we try using the phone number value.
            // If it was a halloapp call - the handle value should be the normalized phone number.
            // So we try to look up the userID using that phone number and then use that to start call.

            let peerUserID: UserID?
            let contactIdentifier = userActivity.contactIdentifier
            let peerNumber = userActivity.phoneNumber

            if let peerNumber = peerNumber,
               let peerContactUserID = MainAppContext.shared.contactStore.userID(for: peerNumber) {
                peerUserID = peerContactUserID
                DDLogInfo("appdelegate/scene/continueUserActivity/using peerNumber: \(peerNumber)/peerUserID: \(String(describing: peerContactUserID))")
            } else if let contactIdentifier = contactIdentifier {
                let peerContact = MainAppContext.shared.contactStore.contact(withIdentifier: contactIdentifier)
                peerUserID = peerContact?.userId
                DDLogInfo("appdelegate/scene/continueUserActivity/using contactIdentifier: \(contactIdentifier)/peerUserID: \(String(describing: peerUserID))")
            } else {
                DDLogError("appdelegate/scene/continueUserActivity/peerNumber is nil - \(String(describing: userActivity.interaction?.intent))")
                peerUserID = nil
            }

            guard let peerUserID = peerUserID else {
                DDLogError("appdelegate/scene/continueUserActivity/empty peerUserID - \(String(describing: userActivity.interaction?.intent))")
                presentFailedCallAlertController()
                return
            }

            DDLogInfo("appdelegate/scene/continueUserActivity/trying to startCall for: \(peerUserID)")
            MainAppContext.shared.callManager.startCall(to: peerUserID) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        DDLogInfo("appdelegate/scene/continueUserActivity/startCall/success")
                    case .failure:
                        DDLogInfo("appdelegate/scene/continueUserActivity/startCall/failure")
                        self.presentFailedCallAlertController()
                    }
                }
            }

        case "INStartVideoCallIntent":
            DDLogInfo("application/scene/continue - unable to handle - type: \(userActivity.activityType)")
            self.presentUnsupportedVideoCallAlertController()

        default:
            DDLogInfo("application/scene/continue - unable to handle - type: \(userActivity.activityType)")
        }

        if let intent = userActivity.interaction?.intent {
            MainAppContext.shared.didTapIntent.send(intent)
        }
    }

    private func displayOngoingCall(call: Call) {
        DispatchQueue.main.async {
            // Always show call view controller for outgoing calls.
            // For incoming calls: show call view controller only after user accepts the call.
            // displayOngoingCall is called specifically in those specific stages of the calls.
            self.showCallViewController(for: call) {
                self.rootViewController.updateCallUI(with: call, animated: false)
            }
        }
    }

    private func presentFailedCallAlertController() {
        DDLogInfo("SceneDelegate/presentFailedCallAlertController")
        let alert = UIAlertController(
            title: Localizations.failedCallTitle,
            message: Localizations.failedCallNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
            DDLogInfo("SceneDelegate/failedCallAlertController/dismiss")
        }))
        var viewController = window?.rootViewController
        while let presentedViewController = viewController?.presentedViewController {
            viewController = presentedViewController
        }
        viewController?.present(alert, animated: true)
    }

    private func presentUnsupportedVideoCallAlertController() {
        DDLogInfo("SceneDelegate/presentUnsupportedVideoCallAlertController")
        let alert = UIAlertController(
            title: Localizations.unsupportedVideoCallTitle,
            message: Localizations.unsupportedVideoCallNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
            DDLogInfo("SceneDelegate/presentUnsupportedVideoCallAlertController/dismiss")
        }))
        var viewController: UIViewController? = self.callViewController
        if viewController == nil {
            viewController = window?.rootViewController
            while let presentedViewController = viewController?.presentedViewController {
                viewController = presentedViewController
            }
        }
        viewController?.present(alert, animated: true)
    }

    private func presentMicPermissionsAlertController() {
        DDLogInfo("SceneDelegate/presentMicPermissionsAlertController")
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle, message: Localizations.micAccessDeniedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default, handler: { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsUrl)
        }))
        var viewController = window?.rootViewController
        while let presentedViewController = viewController?.presentedViewController {
            viewController = presentedViewController
        }
        viewController?.present(alert, animated: true)
    }

    private func checkPasteboardForGroupInviteLinkIfNecessary() {
        let isNotFirstLaunch = AppContext.shared.userDefaults.bool(forKey: "notFirstLaunchKey")
        if !isNotFirstLaunch && UIPasteboard.general.hasURLs {
            DDLogInfo("application/scene/parseURLInPasteBoard")
            guard let url = UIPasteboard.general.urls?.first else { return }
            guard let inviteToken = ChatData.parseInviteURL(url: url) else { return }
            DDLogInfo("application/scene/parseURLInPasteBoard/url \(url)")
            processGroupInviteToken(inviteToken)
        }
        if let groupInviteToken = MainAppContext.shared.userData.groupInviteToken {
            processGroupInviteToken(groupInviteToken)
        }
        AppContext.shared.userDefaults.set(true, forKey: "notFirstLaunchKey")
    }
}

extension SceneDelegate: RootViewControllerDelegate {
    func didTapCallBar() {
        guard let call = MainAppContext.shared.callManager.activeCall else {
            DDLogError("SceneDelegate/didTapCallBar/error [no-call]")
            return
        }
        showCallViewController(for: call)
    }
}

extension SceneDelegate: CallViewDelegate {

    func startedOutgoingCall(call: Call) {
        displayOngoingCall(call: call)
        callViewController?.startedOutgoingCall(call: call)
    }

    func callAccepted(call: Call) {
        displayOngoingCall(call: call)
        callViewController?.callAccepted(call: call)
    }

    func callStarted() {
        callViewController?.callStarted()
    }

    func callRinging() {
        callViewController?.callRinging()
    }

    func callConnected() {
        callViewController?.callConnected()
    }

    func callActive() {
        callViewController?.callActive()
    }

    func callDurationChanged(seconds: Int) {
        callViewController?.callDurationChanged(seconds: seconds)
        rootViewController.updateCallDuration(seconds: seconds)
    }

    func callEnded() {
        callViewController?.callEnded()
    }

    func callReconnecting() {
        callViewController?.callReconnecting()
    }

    func callFailed() {
        callViewController?.callFailed()
    }

    func callHold(_ hold: Bool) {
        callViewController?.callHold(hold)
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

// MARK: Intents: Extend NSUserActivity

protocol SupportedStartCallIntent {
    var contacts: [INPerson]? { get }
}

extension INStartCallIntent: SupportedStartCallIntent {}

// TODO: ios complains that this was deprecated: but this is the intent that ios invokes our app with.
// weird: why they do it - did not find much online for this as of now?
// We anyways made sure to support both for now.
extension INStartAudioCallIntent: SupportedStartCallIntent {}

extension NSUserActivity {

    var phoneNumber: String? {
        guard let startCallIntent = interaction?.intent as? SupportedStartCallIntent else {
            DDLogError("NSUserActivity/handleValue is nil/intent: \(String(describing: interaction?.intent.description))")
            return nil
        }
        DDLogInfo("NSUserActivity/handleValue/intent: \(String(describing: interaction?.intent.description))")
        // Remove occurrences of "+" in the number.
        // We add plus in the handle - since we want iOS to automatically lookup the contact name of the number if available.
        return startCallIntent.contacts?.first?.personHandle?.value?.replacingOccurrences(of: "+", with: "")
    }

    var contactIdentifier: String? {
        guard let startCallIntent = interaction?.intent as? SupportedStartCallIntent else {
            DDLogError("NSUserActivity/contactIdentifier is nil/intent: \(String(describing: interaction?.intent.description))")
            return nil
        }
        DDLogInfo("NSUserActivity/contactIdentifier/intent: \(String(describing: interaction?.intent.description))")
        return startCallIntent.contacts?.first?.contactIdentifier
    }

}
