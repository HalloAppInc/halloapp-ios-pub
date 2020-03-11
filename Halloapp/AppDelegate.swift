//
//  AppDelegate.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import UIKit
import CoreData
import Contacts

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        AppContext.initContext()

        return true
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
        guard !ContactStore.contactsAccessRequestNecessary else {
            return
        }
        guard self.needsAPNSToken || !AppContext.shared.xmppController.hasValidAPNSPushToken else {
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            return
        }
        print("appdelegate/notifications/access-request")
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert, .badge]) { (granted, error) in
            print("appdelegate/notifications/access-request [\(granted)]")
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        self.needsAPNSToken = false
        let tokenString = deviceToken.hexString
        print("appdelegate/notifications/push-token/success [\(tokenString)]")
        AppContext.shared.xmppController.apnsToken = tokenString
        AppContext.shared.xmppController.sendCurrentAPNSTokenIfPossible()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        self.needsAPNSToken = false
        AppContext.shared.xmppController.apnsToken = nil
        print("appdelegate/notifications/push-token/error [\(error)]")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print ("appdelegate/notifications/received-remote \(userInfo)")
        // Handle the silent remote notification when received.
        completionHandler(UIBackgroundFetchResult.newData)
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
            print("appdelegate/contacts/access-request")
            let contactStore = CNContactStore()
            contactStore.requestAccess(for: .contacts) { authorized, error in
                print("appdelegate/contacts/access-request granted=[\(authorized)]")
                DispatchQueue.main.async {
                    completion(true, authorized)
                }
            }
        } else {
            completion(false, ContactStore.contactsAccessAuthorized)
        }
    }

    public func requestAccessToContactsAndNotifications() {
        guard !self.contactsAccessRequestInProgress else {
            print("appdelegate/contacts/access-request/in-progress")
            return
        }
        guard UIApplication.shared.applicationState != .background else {
            print("appdelegate/contacts/access-request/app-inactive")
            return
        }
        self.contactsAccessRequestInProgress = true
        self.checkContactsAuthorizationStatus{ requestPresented, accessAuthorized in
            self.contactsAccessRequestInProgress = false
            AppContext.shared.contactStore.reloadContactsIfNecessary()
            if requestPresented {
                // This is likely the first app launch and now that Contacts access popup is gone,
                // time to request access to notifications.
                self.checkNotificationsAuthorizationStatus()
            }
        }
    }
}

