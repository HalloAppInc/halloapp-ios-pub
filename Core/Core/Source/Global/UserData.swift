//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Combine
import SwiftUI
import XMPPFramework

public final class UserData: ObservableObject {

    public let didLogIn = PassthroughSubject<Void, Never>()
    public let didLogOff = PassthroughSubject<Void, Never>()

    public private(set) var userNamePublisher: CurrentValueSubject<String, Never>!

    /**
     Value is derived from presence of saved userId/password pair.
     */
    @Published public var isLoggedIn = false

    public var useProtobuf: Bool {
        // NB: We use the static user defaults since this is accessed during AppContext initialization
        get {
            if AppContext.userDefaultsForAppGroup.value(forKey: "UseProtobuf") == nil {
                return true
            }
            return AppContext.userDefaultsForAppGroup.bool(forKey: "UseProtobuf")
        }
        set {
            AppContext.userDefaultsForAppGroup.set(newValue, forKey: "UseProtobuf")
        }
    }

    public var useTestServer: Bool {
        get {
            #if DEBUG
            if UserDefaults.shared.value(forKey: "UseTestServer") == nil {
                // Debug builds should default to test server
                return true
            }
            #endif
            return UserDefaults.shared.bool(forKey: "UseTestServer")
        }
        set {
            UserDefaults.shared.set(newValue, forKey: "UseTestServer")
        }
    }
    
    public static var compressionQuality: Float = 0.4

    // Entered by user.
    public var countryCode = "1"
    public var phoneInput = ""
    public var name = "" {
        didSet {
            userNamePublisher.send(name)
        }
    }

    // Provided by the server.
    public var normalizedPhoneNumber: String = ""
    public var userId: UserID = ""
    public var password = ""

    public var userJID: XMPPJID? {
        guard !userId.isEmpty && !password.isEmpty else { return nil }
        return XMPPJID(user: userId, domain: "s.halloapp.net", resource: "iphone")
    }

    public var hostName: String {
        useTestServer ? "s-test.halloapp.net" : "s.halloapp.net"
    }

    public var hostPort: UInt16 {
        useProtobuf ? 5210 : 5222
    }

    public var formattedPhoneNumber: String {
        var phoneNumberStr = normalizedPhoneNumber
        if phoneNumberStr.isEmpty {
            phoneNumberStr = countryCode.appending(phoneInput)
        }
        phoneNumberStr = "+\(phoneNumberStr)"
        if let phoneNumber = try? AppContext.shared.phoneNumberFormatter.parse(phoneNumberStr) {
            phoneNumberStr = AppContext.shared.phoneNumberFormatter.format(phoneNumber, toType: .international)
        }
        return phoneNumberStr
    }

    init(storeDirectoryURL: URL) {
        persistentStoreURL = storeDirectoryURL.appendingPathComponent("UserData.sqlite")
        if let user = fetch() {
            self.countryCode = user.countryCode ?? "1"
            self.phoneInput = user.phoneInput ?? ""
            self.normalizedPhoneNumber = user.phone ?? ""
            self.userId = user.userId ?? ""
            self.password = user.password ?? ""
            self.name = user.name ?? ""
        }

        self.needsKeychainMigration = !password.isEmpty

        if let keychainPassword = Self.loadPasswordFromKeychain(userID: userId) {
            DDLogInfo("UserData/init/password loaded from keychain")
            password = keychainPassword
        } else {
            DDLogInfo("UserData/init/password not found on keychain")
        }

        userNamePublisher = CurrentValueSubject(name)
        if !self.userId.isEmpty && !self.password.isEmpty {
            self.isLoggedIn = true
        }
    }
    
    public func tryLogIn() {
        if !userId.isEmpty && !password.isEmpty {
            self.isLoggedIn = true
            self.didLogIn.send()
        }
    }

    public func migratePasswordToKeychain() {
        guard needsKeychainMigration else {
            DDLogInfo("UserData/migratePassword skipping")
            return
        }

        // NB: Log event through service (not EventMonitor) so we can wait for it to be received before we migrate
        AppContext.shared.coreService.log(events: [.passwordMigrationBegan()]) { result in
            guard case .success = result else { return }
            self.save()
        }
    }
    
    public func logout() {
        didLogOff.send()

        if Self.removePasswordFromKeychain(userID: userId) {
            DDLogInfo("UserData/logout cleared password")
        } else {
            DDLogError("UserData/logout/error unable to clear password")
        }

        countryCode = "1"
        phoneInput = ""
        normalizedPhoneNumber = ""
        userId = ""
        password = ""
        name = ""
        save()

        isLoggedIn = false
        
        UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsDownload)
    }

    // MARK: Keychain

    private var needsKeychainMigration = false

    @discardableResult
    private static func savePasswordToKeychain(userID: UserID, password: String) -> Bool {

        guard loadPasswordFromKeychain(userID: userID) != password else {
            // Existing entry is up to date
            return true
        }

        guard let passwordData = password.data(using: .utf8), let kFalse = kCFBooleanFalse, !password.isEmpty else {
            return false
        }

        if loadKeychainItem(userID: userID) == nil {
            // Add new entry
            let keychainItem = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: "hallo",
                kSecAttrSynchronizable: kFalse,
                kSecValueData: passwordData,
            ] as CFDictionary
            let status = SecItemAdd(keychainItem, nil)
            return status == errSecSuccess
        } else {
            // Update existing entry
            let query = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: "hallo",
            ] as CFDictionary

            let update = [
                kSecValueData: passwordData,
                kSecAttrSynchronizable: kFalse,
            ] as CFDictionary

            let status = SecItemUpdate(query, update)
            return status == errSecSuccess
        }
    }

    @discardableResult
    private static func removePasswordFromKeychain(userID: UserID) -> Bool {
        let keychainItem = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: "hallo",
        ] as CFDictionary
        let status = SecItemDelete(keychainItem)
        return status == errSecSuccess
    }

    private static func loadPasswordFromKeychain(userID: UserID) -> String? {
        guard let item = loadKeychainItem(userID: userID) as? NSDictionary,
              let data = item[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8) else
        {
            return nil
        }

        return password.isEmpty ? nil : password
    }

    private static func loadKeychainItem(userID: UserID) -> AnyObject? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: "hallo",
            kSecReturnAttributes: true,
            kSecReturnData: true,
        ] as CFDictionary

        var result: AnyObject?
        SecItemCopyMatching(query, &result)

        return result
    }

    // MARK: CoreData Stack

    private let persistentStoreURL: URL

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: UserData.self).url(forResource: "UserData", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "Halloapp", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [ storeDescription ]
        container.loadPersistentStores(completionHandler: { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        })
        return container
    }()

    private func fetch() -> User? {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let result = try managedObjectContext.fetch(fetchRequest)
            return result.first
        } catch  {
            DDLogError("UserData/fetch/error [\(error)]")
            fatalError()
        }
    }

    public func save() {
        let managedObjectContext = persistentContainer.viewContext
        var user: User! = fetch()
        if user == nil {
            user = NSEntityDescription.insertNewObject(forEntityName: User.entity().name!, into: managedObjectContext) as? User
        }
        user.countryCode = countryCode
        user.phoneInput = phoneInput
        user.phone = normalizedPhoneNumber
        user.userId = userId
        user.name = name

        let passwordSaveSuccess = Self.savePasswordToKeychain(userID: userId, password: password)

        // Clear password from DB if it was saved to keychain
        user.password = passwordSaveSuccess ? "" : password

        do {
            try managedObjectContext.save()
            if needsKeychainMigration && passwordSaveSuccess {
                DDLogInfo("UserData/save/keychain migrated")
                AppContext.shared.coreService.log(events: [.passwordMigrationSucceeded()]) { _ in }
                needsKeychainMigration = false
            }
        } catch {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }
}
