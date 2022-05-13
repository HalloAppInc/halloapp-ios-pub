//
//  AppDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import BackgroundTasks
import CocoaLumberjackSwift
import Combine
import Contacts
import Core
import CoreCommon
import CoreData
import Reachability
import Sentry
import UIKit
import PushKit

// App in the background can run upto 30 seconds in most cases and 10 seconds should usually be good enough.
fileprivate let backgroundProcessingTimeSec = 25.0
fileprivate let BackgroundFeedRefreshTaskIdentifier = "com.halloapp.hallo.feed.refresh"

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    private let appCrashKey: String = "appCrashKey"

    private let serviceBuilder: ServiceBuilder = {
        return ProtoService(credentials: $0)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        initAppContext(MainAppContext.self, serviceBuilder: serviceBuilder, contactStoreClass: ContactStoreMain.self, appTarget: AppTarget.mainApp)
        
        DDLogInfo("application/didFinishLaunching [\(AppContext.userAgent)] [\(UIDevice.current.getModelName()) (iOS \(UIDevice.current.systemVersion))]")

        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundFeedRefreshTaskIdentifier, using: DispatchQueue.main) { (task) in
            guard let refreshTask = task as? BGAppRefreshTask else {
                DDLogError("bg-feed-refresh/error invalid task \(task)")
                return
            }
            self.handleFeedRefresh(task: refreshTask)
        }

        // This is necessary otherwise application(_:didReceiveRemoteNotification:fetchCompletionHandler:) won't be called.
        UIApplication.shared.registerForRemoteNotifications()

        // This is necessary to keep our voip push token updated.
        registerForVoipNotifications()
        
        UNUserNotificationCenter.current().delegate = self

        setUpReachability()

        // Check and log if crashlytics detects a crash.
        if SentrySDK.crashedLastRun {
            DDLogError("application/didFinishLaunching - crashed - didCrashDuringPreviousExecution")
        }

        if (AppContext.shared.userDefaults.value(forKey: appCrashKey) != nil) {
            DDLogError("application/didFinishLaunching/appCrashKey is not nil - app could have crashed.")
        }
        // Set a value for crashKey that will be cleared if the app terminates cleanly.
        AppContext.shared.userDefaults.set(1, forKey: appCrashKey)
        DDLogInfo("application/didFinishLaunching/update/appCrashKey")

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // remove appCrashKey value to indicate a clean termination (no crash)
        AppContext.shared.userDefaults.removeObject(forKey: appCrashKey)
        DDLogInfo("application/willTerminate/remove/appCrashKey")

        AppContext.shared.stopReportingEvents()
        DDLogInfo("application/willTerminate")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        DDLogInfo("application/didReceiveMemoryWarning")
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

    func checkNotificationsAuthorizationStatus() {
        // Do not allow to ask about access to notifications until user is done with Contacts access prompt.
        guard !ContactStore.contactsAccessRequestNecessary else { return }

        DDLogInfo("appdelegate/notifications/authorization/request")
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert, .badge]) { (granted, error) in
            DDLogInfo("appdelegate/notifications/authorization granted=[\(granted)]")
            if self.needsAPNSToken || !MainAppContext.shared.service.hasValidAPNSPushToken {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.toHexString()
        DDLogInfo("appdelegate/notifications/push-token/success [\(tokenString)]")

        self.needsAPNSToken = false
        MainAppContext.shared.service.sendAPNSTokenIfNecessary(tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DDLogError("appdelegate/notifications/push-token/error [\(error)]")

        self.needsAPNSToken = false
        MainAppContext.shared.service.sendAPNSTokenIfNecessary(nil)
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

        let service = MainAppContext.shared.service
        service.startConnectingIfNecessary()
        service.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            // App was opened while connection attempt was in progress - end task and do nothing else.
            guard application.applicationState == .background else {
                DDLogWarn("application/background-push Connected while in foreground")
                completionHandler(.noData)
                return
            }

            DDLogInfo("application/background-push/connected")

            // Disconnect gracefully after a few seconds, which should be enough to finish processing.
            DispatchQueue.main.asyncAfter(deadline: .now() + backgroundProcessingTimeSec) {
                // Make sure to check if the app is still backgrounded.
                if application.applicationState == .background {
                    DDLogInfo("application/background-push/disconnect")
                    service.disconnect()

                    // Finish bg task once we're disconnected.
                    service.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
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
            DDLogInfo("appdelegate/contacts/access-request Prompting user now")
            let contactStore = CNContactStore()
            contactStore.requestAccess(for: .contacts) { authorized, error in
                DispatchQueue.main.async {
                    AppContext.shared.contactStore.contactsAccessRequestCompleted.send(authorized)
                    completion(true, authorized)
                }
            }
        } else {
            completion(false, ContactStore.contactsAccessAuthorized)
        }
    }

    func requestAccessToContactsAndNotifications() {
        guard !contactsAccessRequestInProgress else {
            DDLogWarn("appdelegate/contacts/access-request Already in progress")
            return
        }
        contactsAccessRequestInProgress = true
        checkContactsAuthorizationStatus { requestPresented, accessAuthorized in
            DDLogInfo("appdelegate/contacts/access-request Granted: [\(accessAuthorized)] Request presented: [\(requestPresented)]")
            self.contactsAccessRequestInProgress = false
            MainAppContext.shared.contactStore.reloadContactsIfNecessary()
            if requestPresented {
                // This is likely the first app launch and now that Contacts access popup is gone,
                // time to request access to notifications.
                self.checkNotificationsAuthorizationStatus()
            }
        }
    }

    // MARK: Reachability

    var reachability: Reachability?

    func setUpReachability() {
        reachability = try? Reachability()
        reachability?.whenReachable = { reachability in
            DDLogInfo("appdelegate/Reachability/reachable/\(reachability.connection)")
            MainAppContext.shared.coreService.reachabilityState = .reachable
            MainAppContext.shared.coreService.reachabilityConnectionType = reachability.connection.description
            MainAppContext.shared.coreService.startConnectingIfNecessary()
            MainAppContext.shared.feedData.resumeMediaDownloads()
        }
        reachability?.whenUnreachable = { reachability in
            DDLogInfo("appdelegate/Reachability/unreachable/\(reachability.connection)")
            MainAppContext.shared.coreService.reachabilityState = .unreachable
            MainAppContext.shared.coreService.reachabilityConnectionType = reachability.connection.description
            MainAppContext.shared.feedData.suspendMediaDownloads()
        }
        do {
            try reachability?.startNotifier()
        } catch {
            DDLogInfo("appdelegate/Reachability/Failed to start notifier/\(reachability?.connection.description ?? "nil")")
        }
    }

    func resumeMediaDownloads() {
        DDLogInfo("appdelegate/resumeMediaDownloads")
        MainAppContext.shared.feedData.resumeMediaDownloads()
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

        task.expirationHandler = { [weak self] in
            guard let self = self else { return }
            DDLogError("application/bg-feed-refresh Expiration handler")
            self.taskFinishCompletionBlock(task: task)
        }
        
        MainAppContext.shared.mergeSharedData()

        let application = UIApplication.shared
        let service = MainAppContext.shared.service
        service.startConnectingIfNecessary()
        service.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            // App was opened while connection attempt was in progress - end task and do nothing else.
            guard application.applicationState == .background else {
                DDLogWarn("application/bg-feed-refresh Connected while in foreground")
                task.setTaskCompleted(success: true)
                return
            }
            DDLogInfo("application/bg-feed-refresh/connected")

            // Disconnect gracefully after a few seconds, which should be enough to finish processing.
            DispatchQueue.main.asyncAfter(deadline: .now() + backgroundProcessingTimeSec) { [self] in
                taskFinishCompletionBlock(task: task)
            }
        }

        // Schedule next bg fetch.
        scheduleFeedRefresh(after: Date.hours(2))
    }

    private func taskFinishCompletionBlock(task: BGAppRefreshTask) {
        let application = UIApplication.shared
        let service = MainAppContext.shared.service
        // Make sure to check if the app is still backgrounded.
        if application.applicationState == .background {
            DDLogInfo("application/bg-feed-refresh/disconnect")
            service.disconnect()

            // Finish bg task once we're disconnected.
            service.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
                DDLogInfo("application/bg-feed-refresh/complete")
                task.setTaskCompleted(success: true)
            }
        } else {
            task.setTaskCompleted(success: true)
        }
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
        timer.schedule(deadline: .now() + 60)
        timer.resume()
        return timer
    }

    // Stay connected in the background for 1 minute and then disconnect.
    // Let iOS trigger an expiration handler for our app and then disconnect and end the task.
    func beginBackgroundConnectionTask() {
        guard backgroundTaskIdentifier == .invalid else {
            DDLogWarn("appdelegate/bg-task Identifier is already set")
            return
        }
        guard disconnectTimer == nil else {
            DDLogWarn("appdelegate/bg-task Timer is not nil")
            return
        }

        let service = MainAppContext.shared.service
        guard !service.isDisconnected else {
            DDLogWarn("appdelegate/bg-task Skipped - not connected to the server")
            return
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "close-connection") {
            DDLogWarn("appdelegate/bg-task Expiration handler. Connection state: [\(service.connectionState)]")
            if self.disconnectTimer != nil {
                self.disconnectTimer?.cancel()
                self.disconnectTimer = nil
            }
            MainAppContext.shared.feedData.suspendMediaDownloads()
            service.disconnectImmediately()
            MainAppContext.shared.stopReportingEvents()
            UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
            self.backgroundTaskIdentifier = .invalid
        }
        guard backgroundTaskIdentifier != .invalid else {
            DDLogError("appdelegate/bg-task Could not start background task")
            return
        }
        DDLogDebug("appdelegate/bg-task Created with identifier:[\(backgroundTaskIdentifier)]")

        disconnectTimer = createDisconnectTimer()
        service.execute(whenConnectionStateIs: .notConnected, onQueue: .main) {
            self.endBackgroundConnectionTask()
        }
    }

    private func disconnectAndEndBackgroundTask() {
        let service = MainAppContext.shared.service

        DDLogInfo("appdelegate/bg-task Disconnect timer fired. Connection state: [\(service.connectionState)]")

        disconnectTimer = nil

        MainAppContext.shared.service.disconnect()
        MainAppContext.shared.stopReportingEvents()
        MainAppContext.shared.feedData.suspendMediaDownloads()
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
            if let metadata = NotificationMetadata.load(from: response) {
                DDLogInfo("appdelegate/notifications/user-response MetaData=\(metadata)")
                metadata.saveToUserDefaults()
                MainAppContext.shared.didTapNotification.send(metadata)
            }
        }

        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
           willPresent notification: UNNotification,
           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.alert)
    }
    
}

// MARK: VOIP

extension AppDelegate: PKPushRegistryDelegate {

    // Register for VoIP notifications
    func registerForVoipNotifications() {
        DDLogInfo("appdelegate/voip-notifications/registerForVoipNotifications")
        let voipRegistry: PKPushRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
    }

    // Register for token
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        if pushCredentials.type == .voIP {
            let tokenString = pushCredentials.token.toHexString()
            DDLogInfo("appdelegate/voip-notifications/didUpdate/voIP-push-token/success [\(tokenString)]")
            MainAppContext.shared.service.sendVOIPTokenIfNecessary(tokenString)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        if type == .voIP {
            DDLogInfo("appdelegate/voip-notifications/didInvalidatePushTokenFor/voIP-push-token: nil")
            MainAppContext.shared.service.sendVOIPTokenIfNecessary(nil)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {

        // Merge any data if necessary.
        MainAppContext.shared.mergeSharedData()

        if type == .voIP {
            DDLogInfo("appdelegate/voip-notifications/didReceiveIncomingPushWith/payload: \(payload.dictionaryPayload)")
            MainAppContext.shared.service.startConnectingIfNecessary()

            guard let noiseKeys = AppContext.shared.userData.noiseKeys,
                  let metadata = payload.dictionaryPayload[NotificationMetadata.userInfoKeyMetadata] as? [String: String],
                  let encryptedContentB64 = metadata[NotificationMetadata.encryptedData],
                  let encryptedMessage = Data(base64Encoded: encryptedContentB64),
                  let pushContent = NoiseStream.decryptPushContent(noiseKeys: noiseKeys, encryptedMessage: encryptedMessage) else {

                      // Check if nse_content is available.
                      // This happens if the incomingCall message was received by the notification extension.
                      // NotificationExtension then invokes the main app wth the base64 encoded version of serialzed server_msg stanza.
                      // We extract the contents from there and then try to report the call to system.
                      guard let metadata = payload.dictionaryPayload[NotificationMetadata.userInfoKeyMetadata] as? [String: String],
                            let serverMsgBase64String = metadata[NotificationMetadata.nseVoipData],
                            let serverMsgPb = Data(base64Encoded: serverMsgBase64String) else {
                          DDLogError("appdelegate/voip-notifications/noise/error unable to find encrypted content")
                          completion()
                          return
                      }

                      // Report call, run completion and return
                      handleVoipMsg(serverMsgPb: serverMsgPb, completion: completion)
                      return
            }

            // Report call, run completion and return
            handleVoipMsg(serverMsgPb: pushContent.content, completion: completion)
            return
        }
        completion()
    }

    private func handleVoipMsg(serverMsgPb: Data, completion: @escaping () -> Void) {
        var service = MainAppContext.shared.service
        do {
            let msg = try Server_Msg(serializedData: serverMsgPb)
            let fromUserID = UserID(msg.fromUid)
            switch msg.payload {
            case .incomingCall(let incomingCall):
                DDLogInfo("appdelegate/voip-notifications/invoking delegate now for call from: \(fromUserID) using incomingCall")
                service.callDelegate?.halloService(service, from: fromUserID, didReceiveIncomingCall: incomingCall) {
                    // send ack for the message.
                    service.sendAck(messageId: msg.id) { _ in }
                }
                service.readyToHandleCallMessages = true
            case .incomingCallPush(let incomingCallPush):
                DDLogInfo("appdelegate/voip-notifications/invoking delegate now for call from: \(fromUserID) using incomingCallPush")
                service.callDelegate?.halloService(service, from: fromUserID, didReceiveIncomingCallPush: incomingCallPush)
                service.readyToHandleCallMessages = true
            default:
                DDLogError("appdelegate/voip-notifications/error invalid payload: \(msg)")
                break
            }
        } catch {
            DDLogError("appdelegate/voip-notifications/error \(error)")
        }
        completion()
    }

}
