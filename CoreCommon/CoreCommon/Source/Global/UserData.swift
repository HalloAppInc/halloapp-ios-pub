//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreData
import SwiftUI

public struct Credentials {
    public let userID: UserID
    public let name: String
    public let username: String
    public let noiseKeys: NoiseKeys
}

public enum OldCredentials {
    case v2(userID: UserID, noiseKeys: NoiseKeys)

    public var userID: UserID {
        switch self {
        case .v2(let userID, _): return userID
        }
    }

    public var noiseKeys: NoiseKeys {
        switch self {
        case .v2(_, let noiseKeys): return noiseKeys
        }
    }
}

private struct UserDefaultsKey {
    static let loggedOutNoiseKeys = "LoggedOutNoiseKeys"
}

public final class UserData: ObservableObject {
    
    private var isAppClip: Bool

    public let didLogIn = PassthroughSubject<Void, Never>()
    public let didLogOff = PassthroughSubject<Void, Never>()

    public private(set) var userNamePublisher: CurrentValueSubject<String, Never>!
    public private(set) var userIDPublisher: CurrentValueSubject<String, Never>!

    /**
     Value is derived from presence of saved credentials.
     */
    @Published public var isLoggedIn = false

    public static var compressionQuality: Float = 0.4

    public var groupInviteToken: String? = nil
    public var groupName: String? = nil

    // Entered by user.
    public var countryCode = "1"
    public var phoneInput = ""
    public var name = "" {
        didSet {
            userNamePublisher?.send(name)
        }
    }
    public var username = ""
    public var links: [ProfileLink] = []

    // Provided by the server.
    public var normalizedPhoneNumber: String = ""
    public var userId: UserID = ""
    public private(set) var noiseKeys: NoiseKeys?

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    private lazy var bgContext: NSManagedObjectContext = {
        persistentContainer.newBackgroundContext()
    }()

    public var credentials: Credentials? {
        guard !userId.isEmpty, let noiseKeys else {
            return nil
        }

        return Credentials(userID: userId, name: name, username: "", noiseKeys: noiseKeys)
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        bgContext.perform { [weak self] in
            guard let self = self else { return }
            block(self.bgContext)
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        bgContext.performAndWait {
            block(self.bgContext)
        }
    }

    public func update(credentials: Credentials, in managedObjectContext: NSManagedObjectContext) {
        userId = credentials.userID
        name = credentials.name
        username = credentials.username
        noiseKeys = credentials.noiseKeys

        save(using: managedObjectContext)
    }

    public var formattedPhoneNumber: String {
        var phoneNumberStr = normalizedPhoneNumber
        if phoneNumberStr.isEmpty {
            phoneNumberStr = countryCode.appending(phoneInput)
        }
        phoneNumberStr = "+\(phoneNumberStr)"
        if let phoneNumber = try? AppContextCommon.shared.phoneNumberFormatter.parse(phoneNumberStr) {
            phoneNumberStr = AppContextCommon.shared.phoneNumberFormatter.format(phoneNumber, toType: .international)
        }
        return phoneNumberStr
    }

    init(storeDirectoryURL: URL, isAppClip: Bool) {
        self.isAppClip = isAppClip
        persistentStoreURL = storeDirectoryURL.appendingPathComponent("UserData.sqlite")
        viewContext.performAndWait {
            if let user = fetch(using: viewContext) {
                self.countryCode = user.countryCode ?? "1"
                self.phoneInput = user.phoneInput ?? ""
                self.normalizedPhoneNumber = user.phone ?? ""
                self.userId = user.userId ?? ""
                self.name = user.name ?? ""
                self.username = user.username ?? ""
                self.links = user.links as? [ProfileLink] ?? []

                // If this is the main app and noise keys are present in shared container, load noiseKeys from the container
                if !isAppClip, let storePrivateKey = user.noisePrivateKey, let storePublicKey = user.noisePublicKey {
                    DDLogInfo("UserData/init/loading noise keys from persistent store")
                    noiseKeys = NoiseKeys(privateEdKey: storePrivateKey, publicEdKey: storePublicKey)
                    //Migrate the noise keys from persistent store to keychain
                    migrateNoiseKeys(using: viewContext)
                } else {
                    DDLogInfo("UserData/init/loading noise keys from keychain [\(userId)]")
                    noiseKeys = Keychain.loadNoiseUserKeypair(for: userId)
                    if noiseKeys == nil {
                        DDLogInfo("UserData/init/noise keys not found")
                    } else {
                        DDLogInfo("UserData/init/loaded noise keys")
                    }
                }
            }
        }

        userNamePublisher = CurrentValueSubject(name)
        userIDPublisher = CurrentValueSubject(userId)
        if credentials != nil {
            self.isLoggedIn = true
        }
    }
    
    public func tryLogIn() {
        if credentials != nil {
            self.isLoggedIn = true
            self.didLogIn.send()
        }
    }

    public func logout(using managedObjectContext: NSManagedObjectContext) {
        didLogOff.send()

        countryCode = "1"
        phoneInput = ""
        normalizedPhoneNumber = ""
        userId = ""
        name = ""
        username = ""
        save(using: managedObjectContext)

        isLoggedIn = false
        
        // TODO DINI
        // UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsDownload)
    }

    // MARK: Noise

    public var loggedOutNoiseKeys: NoiseKeys? {
        let savedKeys = try? UserDefaults.shared.codable(forKey: UserDefaultsKey.loggedOutNoiseKeys) as NoiseKeys?
        if let savedKeys = savedKeys {
            return savedKeys
        } else {
            guard let newKeys = NoiseKeys() else { return nil }
            try? UserDefaults.shared.setCodable(newKeys, forKey: UserDefaultsKey.loggedOutNoiseKeys)
            return newKeys
        }
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

    private func fetch(using managedObjectContext: NSManagedObjectContext) -> User? {
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

    public func save(using managedObjectContext: NSManagedObjectContext) {
        var user: User! = fetch(using: managedObjectContext)
        if user == nil {
            user = NSEntityDescription.insertNewObject(forEntityName: User.entity().name!, into: managedObjectContext) as? User
        }
        user.countryCode = countryCode
        user.phoneInput = phoneInput
        user.phone = normalizedPhoneNumber
        user.userId = userId
        user.name = name
        user.username = username
        user.links = links

        // Clear password (no longer supported)
        user.password = ""

        if let noiseKeys = noiseKeys {
            if Keychain.saveNoiseUserKeypair(noiseKeys, for: userId) {
                DDLogInfo("UserData/save/noiseKeys/saved")
            } else {
                DDLogError("UserData/save/noiseKeys/error keychain save failed")
            }
            // If this is the AppClip, save noise keys to share with main app via persistent container
            if (isAppClip) {
                DDLogInfo("UserData/save/noiseKeys/saving noise keys to persistent store ")
                user.noisePublicKey = noiseKeys.publicEdKey
                user.noisePrivateKey = noiseKeys.privateEdKey
            }
        }

        do {
            try managedObjectContext.save()
            NotificationCenter.default.post(name: Self.userDataDidSave, object: nil)
        } catch {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }
    
    private func migrateNoiseKeys(using managedObjectContext: NSManagedObjectContext) {
        //Copy noise keys to keychain
        if let noiseKeys = noiseKeys {
            if Keychain.saveNoiseUserKeypair(noiseKeys, for: userId) {
                DDLogInfo("UserData/migrate/noiseKeys/copied from persistent store to keychain")
                removeNoiseKeysFromStore(using: managedObjectContext)
            } else {
                DDLogError("UserData/migrate/noiseKeys/error keychain copy from persistent store to keychain")
            }
        }
    }
    
    private func removeNoiseKeysFromStore(using managedObjectContext: NSManagedObjectContext) {
        guard let user = fetch(using: managedObjectContext) else {
            return
        }
        
        user.noisePrivateKey = nil
        user.noisePublicKey = nil

        do {
            try managedObjectContext.save()
            DDLogError("UserData/migrate/noiseKeys/removed from persistent store")
        } catch {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }
}

// MARK: - Save notification

extension UserData {

    public static let userDataDidSave = Notification.Name("userDataDidSave")
}
