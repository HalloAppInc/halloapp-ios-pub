//
//  AppDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import BackgroundTasks
import CocoaLumberjack
import Contacts
import Core
import CoreData
import UIKit

fileprivate let BackgroundFeedRefreshTaskIdentifier = "com.halloapp.hallo.feed.refresh"

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        initAppContext(MainAppContext.self, xmppControllerClass: XMPPControllerMain.self, contactStoreClass: ContactStoreMain.self)

        DDLogInfo("application/didFinishLaunching")

        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundFeedRefreshTaskIdentifier, using: DispatchQueue.main) { (task) in
            self.handleFeedRefresh(task: task as! BGAppRefreshTask)
        }

        // This is necessary otherwise application(_:didReceiveRemoteNotification:fetchCompletionHandler:) won't be called.
        UIApplication.shared.registerForRemoteNotifications()
        
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        DDLogInfo("application/willTermimate")
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: Remote notifications

    private var needsAPNSToken = true

    public func checkNotificationsAuthorizationStatus() {
        // Do not allow to ask about access to notifications until user is done with Contacts access prompt.
        guard !ContactStore.contactsAccessRequestNecessary else { return }
        guard self.needsAPNSToken || !MainAppContext.shared.xmppController.hasValidAPNSPushToken else { return }
        guard UIApplication.shared.applicationState != .background else { return }

        DDLogInfo("appdelegate/notifications/authorization/request")
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert, .badge]) { (granted, error) in
            DDLogInfo("appdelegate/notifications/authorization granted=[\(granted)]")
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.toHexString()
        DDLogInfo("appdelegate/notifications/push-token/success [\(tokenString)]")

        self.needsAPNSToken = false
        MainAppContext.shared.xmppController.apnsToken = tokenString
        MainAppContext.shared.xmppController.sendCurrentAPNSTokenIfPossible()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DDLogError("appdelegate/notifications/push-token/error [\(error)]")

        self.needsAPNSToken = false
        MainAppContext.shared.xmppController.apnsToken = nil
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        DDLogInfo("appdelegate/background-push \(userInfo)")

        // Ignore notifications received when the app is in foreground.
        guard application.applicationState == .background else {
            DDLogWarn("appdelegate/background-push Application is not backgrounded")
            completionHandler(.noData)
            return
        }
        
        MainAppContext.shared.mergeSharedData()

        let xmppController = MainAppContext.shared.xmppController
        xmppController.startConnectingIfNecessary()
        xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            // App was opened while connection attempt was in progress - end task and do nothing else.
            guard application.applicationState == .background else {
                DDLogWarn("application/background-push Connected while in foreground")
                completionHandler(.noData)
                return
            }

            DDLogInfo("application/background-push/connected")

            // Disconnect gracefully after 3 seconds, which should be enough to finish processing.
            // TODO: disconnect immediately after receiving "offline marker".
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Make sure to check if the app is still backgrounded.
                if application.applicationState == .background {
                    DDLogInfo("application/background-push/disconnect")
                    xmppController.disconnect()

                    // Finish bg task once we're disconnected.
                    xmppController.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
                        DDLogInfo("application/background-push/complete")
                        completionHandler(.newData)
                    }
                }
            }
        }
    }

    // MARK: Privacy Access Requests

    /**
     This variable is necessary because presenting Contacts access request popup makes the app to go into "inactive" state
     and then back to "active" when popup is closed (by either approving or rejecting access request).
     */
    private var contactsAccessRequestInProgress = false

    private func checkContactsAuthorizationStatus(completion: @escaping (Bool, Bool) -> Void) {
        // Authorization status will be unknown on first launch or after privacy settings reset.
        // We need to excplicitly request access in this case.
        if ContactStore.contactsAccessRequestNecessary {
            DDLogInfo("appdelegate/contacts/access-request")
            let contactStore = CNContactStore()
            contactStore.requestAccess(for: .contacts) { authorized, error in
                DDLogInfo("appdelegate/contacts/access-request granted=[\(authorized)]")
                DispatchQueue.main.async {
                    completion(true, authorized)
                }
            }
        } else {
            completion(false, ContactStore.contactsAccessAuthorized)
        }
    }

    func requestAccessToContactsAndNotifications() {
        guard !self.contactsAccessRequestInProgress else {
            DDLogWarn("appdelegate/contacts/access-request/in-progress")
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            DDLogInfo("appdelegate/contacts/access-request/app-inactive")
            return
        }
        self.contactsAccessRequestInProgress = true
        self.checkContactsAuthorizationStatus{ requestPresented, accessAuthorized in
            self.contactsAccessRequestInProgress = false
            MainAppContext.shared.contactStore.reloadContactsIfNecessary()
            if requestPresented {
                // This is likely the first app launch and now that Contacts access popup is gone,
                // time to request access to notifications.
                self.checkNotificationsAuthorizationStatus()
            }
        }
    }

    // MARK: Background App Refresh

    func scheduleFeedRefresh(after timeInterval: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundFeedRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: timeInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            DDLogInfo("application/bg-feed-refresh/scheduled after=[\(timeInterval)]")
        } catch {
            DDLogError("application/bg-feed-refresh  Could not schedule refresh: \(error)")
        }
    }

    private func handleFeedRefresh(task: BGAppRefreshTask) {
        DDLogInfo("application/bg-feed-refresh/begin")

        // Nothing to fetch if user isn't yet registered.
        guard MainAppContext.shared.userData.isLoggedIn else {
            DDLogWarn("application/bg-feed-refresh Not logged in")
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = {
            DDLogError("application/bg-feed-refresh Expiration handler")
        }
        
        MainAppContext.shared.mergeSharedData()

        let application = UIApplication.shared
        let xmppController = MainAppContext.shared.xmppController
        xmppController.startConnectingIfNecessary()
        xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            // App was opened while connection attempt was in progress - end task and do nothing else.
            guard application.applicationState == .background else {
                DDLogWarn("application/bg-feed-refresh Connected while in foreground")
                task.setTaskCompleted(success: true)
                return
            }

            DDLogInfo("application/bg-feed-refresh/connected")

            // Disconnect gracefully after 3 seconds, which should be enough to finish processing.
            // TODO: disconnect immediately after receiving "offline marker".
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Make sure to check if the app is still backgrounded.
                if application.applicationState == .background {
                    DDLogInfo("application/bg-feed-refresh/disconnect")
                    xmppController.disconnect()

                    // Finish bg task once we're disconnected.
                    xmppController.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
                        DDLogInfo("application/bg-feed-refresh/complete")
                        task.setTaskCompleted(success: true)
                    }
                } else {
                    task.setTaskCompleted(success: true)
                }
            }
        }

        // Schedule next bg fetch.
        scheduleFeedRefresh(after: Date.minutes(5))
    }

    // MARK: Background Connection Task

    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var disconnectTimer: DispatchSourceTimer?
    private func createDisconnectTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            self.disconnectAndEndBackgroundTask()
        })
        timer.schedule(deadline: .now() + 10)
        timer.resume()
        return timer
    }

    /**
     Stay connected in the background for 10 seconds, then gracefully disconnect and let iOS suspend the app.
     */
    func beginBackgroundConnectionTask() {
        guard backgroundTaskIdentifier == .invalid else {
            DDLogError("appdelegate/bg-task Identifier is not set")
            fatalError("Background task identifier is not set")
        }
        guard disconnectTimer == nil else {
            DDLogError("appdelegate/bg-task Timer is not nil")
            fatalError("Disconnect timer is not nil")
        }

        let xmppController = AppContext.shared.xmppController
        guard !xmppController.isDisconnected else {
            DDLogWarn("appdelegate/bg-task Skipped - not connected to the server")
            return
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "close-connection") {
            DDLogWarn("appdelegate/bg-task Expiration handler. Connection state: [\(xmppController.connectionState)]")
            if self.disconnectTimer != nil {
                self.disconnectTimer?.cancel()
                self.disconnectTimer = nil
            }
            xmppController.disconnectImmediately()
            self.backgroundTaskIdentifier = .invalid
        }
        guard backgroundTaskIdentifier != .invalid else {
            DDLogError("appdelegate/bg-task Could not start background task")
            return
        }
        DDLogDebug("appdelegate/bg-task Created with identifier:[\(backgroundTaskIdentifier)]")

        disconnectTimer = createDisconnectTimer()
        xmppController.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
            self.endBackgroundConnectionTask()
        }
    }

    private func disconnectAndEndBackgroundTask() {
        let xmppController = MainAppContext.shared.xmppController

        DDLogInfo("appdelegate/bg-task Disconnect timer fired. Connection state: [\(xmppController.connectionState)]")

        disconnectTimer = nil
        AppContext.shared.xmppController.disconnect()
    }

    func endBackgroundConnectionTask() {
        guard backgroundTaskIdentifier != .invalid else {
            DDLogWarn("appdelegate/bg-task No background task to end")
            return
        }
        DDLogDebug("appdelegate/bg-task Finished")

        if disconnectTimer != nil {
            disconnectTimer?.cancel()
            disconnectTimer = nil
        }

        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DDLogInfo("appdelegate/notifications/user-response/\(response.actionIdentifier) UserInfo=\(response.notification.request.content.userInfo)")

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let metadata = NotificationMetadata(notificationResponse: response) {
                DDLogInfo("appdelegate/notifications/user-response MetaData=\(metadata)")
                metadata.saveToUserDefaults()
                MainAppContext.shared.didTapNotification.send(metadata)
            }
        }

        completionHandler()
    }
}
