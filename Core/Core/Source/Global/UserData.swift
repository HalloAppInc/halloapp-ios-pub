//
//  UserData.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Combine
import Foundation
import SwiftUI
import XMPPFramework

public final class UserData: ObservableObject {
    private let userCore = UserCore()

    public let didLogIn = PassthroughSubject<Void, Never>()
    public let didLogOff = PassthroughSubject<Void, Never>()

    /**
     Value is derived from presence of saved userId/password pair.
     */
    @Published public var isLoggedIn = false

    public var useTestServer: Bool {
        get {
            UserDefaults.shared.bool(forKey: "UseTestServer")
        }
        set {
            UserDefaults.shared.set(newValue, forKey: "UseTestServer")
        }
    }
    
    public var compressionQuality: Float = 0.4

    // Entered by user.
    public var countryCode = "1"
    public var phoneInput = ""
    public var name = ""

    // Provided by the server.
    public var normalizedPhoneNumber: String = ""
    public var userId: UserID = ""
    public var password = "11111111"

    public var userJID: XMPPJID? {
        get {
            guard !userId.isEmpty && !password.isEmpty else { return nil }
            return XMPPJID(user: userId, domain: "s.halloapp.net", resource: "iphone")
        }
    }

    public var hostName: String {
        get {
            self.useTestServer ? "s-test.halloapp.net" : "s.halloapp.net"
        }
    }

    public var formattedPhoneNumber: String {
        get {
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
    }

    init() {
        if let user = userCore.fetch() {
            self.countryCode = user.countryCode ?? "1"
            self.phoneInput = user.phoneInput ?? ""
            self.normalizedPhoneNumber = user.phone ?? ""
            self.userId = user.userId ?? ""
            self.password = user.password ?? ""
            self.name = user.name ?? ""
        }
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
    
    public func logout() {
        self.didLogOff.send()

        self.countryCode = "1"
        self.phoneInput = ""
        self.normalizedPhoneNumber = ""
        self.userId = ""
        self.password = ""
        self.name = ""
        self.save()

        self.isLoggedIn = false
    }
        
    public func save() {
        userCore.save(countryCode: self.countryCode, phoneInput: self.phoneInput, normalizedPhoneNumber: self.normalizedPhoneNumber,
                      userId: self.userId, password: self.password, name: self.name)
    }

}


fileprivate class UserCore {

    private class var persistentStoreURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("UserData.sqlite")
        }
    }

    let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: UserCore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: UserCore.self).url(forResource: "UserData", withExtension: "momd")!
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

    func fetch() -> User? {
        return fetch(using: self.persistentContainer.viewContext)
    }

    private func fetch(using managedObjectContext: NSManagedObjectContext) -> User? {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let result = try managedObjectContext.fetch(fetchRequest)
            return result.first
        } catch  {
            DDLogError("usercore/fetch/error [\(error)]")
            fatalError()
        }
    }

    func save(countryCode: String, phoneInput: String, normalizedPhoneNumber: String, userId: String, password: String, name: String) {
        let managedObjectContext = self.persistentContainer.viewContext
        var user = self.fetch(using: managedObjectContext)
        if user == nil {
            user = NSEntityDescription.insertNewObject(forEntityName: User.entity().name!, into: managedObjectContext) as? User
        }
        user?.countryCode = countryCode
        user?.phoneInput = phoneInput
        user?.phone = normalizedPhoneNumber
        user?.userId = userId
        user?.password = password
        user?.name = name
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("usercore/save/error [\(error)]")
            fatalError()
        }
    }

}

