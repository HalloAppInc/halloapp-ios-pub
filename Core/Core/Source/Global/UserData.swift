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

public enum Credentials {
    case v2(userID: UserID, noiseKeys: NoiseKeys)

    var userID: UserID {
        switch self {
        case .v2(let userID, _): return userID
        }
    }
}

public final class UserData: ObservableObject {
    
    private var isAppClip: Bool

    public let didLogIn = PassthroughSubject<Void, Never>()
    public let didLogOff = PassthroughSubject<Void, Never>()

    public private(set) var userNamePublisher: CurrentValueSubject<String, Never>!

    /**
     Value is derived from presence of saved credentials.
     */
    @Published public var isLoggedIn = false

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

    public var groupInviteToken: String? = nil
    public var groupName: String? = nil

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
    public private(set) var noiseKeys: NoiseKeys?

    public var hostName: String {
        useTestServer ? "s-test.halloapp.net" : "s.halloapp.net"
    }

    public var hostPort: UInt16 {
        5222
    }

    public var credentials: Credentials? {
        guard !userId.isEmpty else { return nil }
        if let noiseKeys = noiseKeys {
            return .v2(userID: userId, noiseKeys: noiseKeys)
        } else {
            return nil
        }
    }

    public func update(credentials: Credentials) {
        switch credentials {
        case .v2(let userID, let noiseKeys):
            DDLogInfo("UserData/credentials/updating [\(userID)] [noise]")
            self.userId = userID
            self.noiseKeys = noiseKeys
        }
        save()
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

    init(storeDirectoryURL: URL, isAppClip: Bool) {
        self.isAppClip = isAppClip
        persistentStoreURL = storeDirectoryURL.appendingPathComponent("UserData.sqlite")
        if let user = fetch() {
            self.countryCode = user.countryCode ?? "1"
            self.phoneInput = user.phoneInput ?? ""
            self.normalizedPhoneNumber = user.phone ?? ""
            self.userId = user.userId ?? ""
            self.name = user.name ?? ""
            
            // If this is the main app and noise keys are present in shared container, load noiseKeys from the container
            if !isAppClip, let storePrivateKey = user.noisePrivateKey, let storePublicKey = user.noisePublicKey {
                DDLogInfo("UserData/init/loading noise keys from persistent store")
                noiseKeys = NoiseKeys(privateEdKey: storePrivateKey, publicEdKey: storePublicKey)
                //Migrate the noise keys from persistent store to keychain
                migrateNoiseKeys()
            } else {
                DDLogInfo("UserData/init/loading noise keys from keychain")
                noiseKeys = Keychain.loadNoiseUserKeypair(for: userId)
            }
        }

        userNamePublisher = CurrentValueSubject(name)
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

    public func logout() {
        didLogOff.send()

        countryCode = "1"
        phoneInput = ""
        normalizedPhoneNumber = ""
        userId = ""
        name = ""
        save()

        isLoggedIn = false
        
        UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsDownload)
    }

    // MARK: Noise

    public func generateNoiseKeysForRegistration() -> NoiseKeys? {
        return NoiseKeys()
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
        } catch {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }
    
    private func migrateNoiseKeys() {
        //Copy noise keys to keychain
        if let noiseKeys = noiseKeys {
            if Keychain.saveNoiseUserKeypair(noiseKeys, for: userId) {
                DDLogInfo("UserData/migrate/noiseKeys/copied from persistent store to keychain")
                removeNoiseKeysFromStore()
            } else {
                DDLogError("UserData/migrate/noiseKeys/error keychain copy from persistent store to keychain")
            }
        }
    }
    
    private func removeNoiseKeysFromStore() {
        let managedObjectContext = persistentContainer.viewContext
        guard let user = fetch() else {
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
