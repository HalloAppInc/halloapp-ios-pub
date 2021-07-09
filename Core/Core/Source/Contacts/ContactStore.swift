//
//  ContactStore.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

/**
 Responsible for synchronization between device's address book and app's contact cache.
 */

import CocoaLumberjackSwift
import Combine
import Contacts
import CoreData

// MARK: Types

public typealias UserID = String

open class ContactStore {

    public let userData: UserData

    required public init(userData: UserData) {
        self.userData = userData
    }

    // MARK: Access to Contacts

    public var contactsAccessRequestCompleted = PassthroughSubject<Bool, Never>()

    public class var contactsAccessAuthorized: Bool {
        get {
            return ContactStore.contactsAccessStatus == .authorized
        }
    }

    /// True if permissions have been explicitly denied. False does not imply contacts are available (e.g., may be undetermined or unavailable due to parental controls).
    public class var contactsAccessDenied: Bool {
        get {
            return ContactStore.contactsAccessStatus == .denied
        }
    }

    public class var contactsAccessRequestNecessary: Bool {
        get {
            return ContactStore.contactsAccessStatus == .notDetermined
        }
    }

    private class var contactsAccessStatus: CNAuthorizationStatus {
        get {
            return CNContactStore.authorizationStatus(for: .contacts)
        }
    }

    // MARK: CoreData stack

    public class var persistentStoreURL: URL {
        get {
            return AppContext.contactStoreURL
        }
    }

    public private(set) lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: ContactStore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: ContactStore.self).url(forResource: "Contacts", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "Contacts", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        let managedObjectContext = self.persistentContainer.newBackgroundContext()
        managedObjectContext.performAndWait {
            block(managedObjectContext)
        }
    }

    public var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }

    // MARK: Metadata
    /**
     - returns:
     Metadata associated with contact's store.
     */
    public var databaseMetadata: [String: Any]? {
        get {
            var result: [String: Any] = [:]
            self.persistentContainer.persistentStoreCoordinator.performAndWait {
                do {
                    try result = NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL)
                }
                catch {
                    DDLogError("contacts/metadata/read error=[\(error)]")
                }
            }
            return result
        }
    }

    // MARK: Fetching contacts

    public func allRegisteredContactIDs() -> [UserID] {
        let fetchRequst = NSFetchRequest<NSDictionary>(entityName: "ABContact")
        fetchRequst.predicate = NSPredicate(format: "userId != nil")
        fetchRequst.propertiesToFetch = [ "userId" ]
        fetchRequst.resultType = .dictionaryResultType
        do {
            let allContacts = try self.persistentContainer.viewContext.fetch(fetchRequst)
            return allContacts.compactMap { $0["userId"] as? UserID }
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func allRegisteredContacts(sorted: Bool) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId != nil")
        fetchRequest.returnsObjectsAsFaults = false
        if sorted {
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        }
        do {
            let contacts = try self.persistentContainer.viewContext.fetch(fetchRequest)
            return contacts
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    // MARK: Push names

    public private(set) lazy var pushNames: [UserID: String] = {
        var pushNames: [UserID: String] = [:]
        performOnBackgroundContextAndWait { (managedObjectContext) in
            pushNames = self.fetchAllPushNames(using: managedObjectContext)
        }
        return pushNames
    }()

    private func fetchAllPushNames(using managedObjectContext: NSManagedObjectContext) -> [UserID: String] {
        let fetchRequest: NSFetchRequest<PushName> = PushName.fetchRequest()
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            let names: [UserID: String] = results.reduce(into: [:]) {
                guard let userID = $1.userId else {
                    DDLogError("contacts/push-name/fetch/error push name missing userID [\($1.name ?? "")]")
                    return
                }
                $0[userID] = $1.name
            }
            DDLogDebug("contacts/push-name/fetched  count=[\(names.count)]")
            return names
        }
        catch {
            fatalError("Failed to fetch push names  [\(error)]")
        }
    }

    private var pushNameUpdateQueue = DispatchQueue(label: "com.halloapp.contacts.push-name")

    private func savePushNames(_ names: [UserID: String]) {
        performOnBackgroundContextAndWait { (managedObjectContext) in
            var existingNames: [UserID : PushName] = [:]

            // Fetch existing names.
            let fetchRequest: NSFetchRequest<PushName> = PushName.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userId in %@", Set(names.keys))
            do {
                let results = try managedObjectContext.fetch(fetchRequest)
                existingNames = results.reduce(into: [:]) { $0[$1.userId!] = $1 }
            }
            catch {
                fatalError("Failed to fetch push names  [\(error)]")
            }

            // Insert new names / update existing
            names.forEach { (userId, contactName) in
                if let existingName = existingNames[userId] {
                    if existingName.name != contactName {
                        DDLogDebug("contacts/push-name/update  userId=[\(userId)] from=[\(existingName.name ?? "")] to=[\(contactName)]")
                        existingName.name = contactName
                    }
                } else {
                    DDLogDebug("contacts/push-name/new  userId=[\(userId)] name=[\(contactName)]")
                    let newPushName = NSEntityDescription.insertNewObject(forEntityName: "PushName", into: managedObjectContext) as! PushName
                    newPushName.userId = userId
                    newPushName.name = contactName
                }
            }

            // Save
            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                }
                catch {
                    fatalError("Failed to save managed object context [\(error)]")
                }
            }
        }
    }

    open func addPushNames(_ names: [UserID: String]) {
        pushNameUpdateQueue.async { [self] in
            savePushNames(names)
        }

        pushNames.merge(names) { (existingName, newName) -> String in
            return newName
        }
    }

    // MARK: Push numbers

    public private(set) lazy var pushNumbers: [UserID: String] = {
        var pushNumbers: [UserID: String] = [:]
        performOnBackgroundContextAndWait { (managedObjectContext) in
            pushNumbers = self.fetchAllPushNumbers(using: managedObjectContext)
        }
        return pushNumbers
    }()

    private func fetchAllPushNumbers(using managedObjectContext: NSManagedObjectContext) -> [UserID: String] {
        let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            let numbers: [UserID: String] = results.reduce(into: [:]) {
                guard let userID = $1.userID else {
                    DDLogError("contactStore/fetchAllPushNumbers/fetch/error push number missing userID [\($1.normalizedPhoneNumber ?? "")]")
                    return
                }
                $0[userID] = $1.normalizedPhoneNumber
            }
            DDLogVerbose("contactStore/fetchAllPushNumbers/fetched count=[\(numbers.count)]")
            return numbers
        }
        catch {
            fatalError("contactStore/fetchAllPushNumbers/error [\(error)]")
        }
    }

    private var pushNumberUpdateQueue = DispatchQueue(label: "com.halloapp.contacts.pushNumber")

    private func savePushNumbers(_ numbers: [UserID: String]) {
        performOnBackgroundContextAndWait { (managedObjectContext) in
            var existingNumbers: [UserID : PushNumber] = [:]

            // Fetch existing numbers
            let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userID in %@", Set(numbers.keys))
            do {
                let results = try managedObjectContext.fetch(fetchRequest)
                existingNumbers = results.reduce(into: [:]) { $0[$1.userID!] = $1 }
            }
            catch {
                fatalError("contactStore/savePushNumbers/error  [\(error)]")
            }

            // Insert new numbers / update existing
            numbers.forEach { (userID, number) in
                if let existingNumber = existingNumbers[userID] {
                    if existingNumber.normalizedPhoneNumber != number {
                        DDLogDebug("contactStore/savePushNumbers/update  userId=[\(userID)] from=[\(existingNumber.normalizedPhoneNumber ?? "")] to=[\(number)]")
                        existingNumber.normalizedPhoneNumber = number
                    }
                } else {
                    DDLogDebug("contactStore/savePushNumbers/new  userId=[\(userID)] name=[\(number)]")
                    let newPushNumber = NSEntityDescription.insertNewObject(forEntityName: "PushNumber", into: managedObjectContext) as! PushNumber
                    newPushNumber.userID = userID
                    newPushNumber.normalizedPhoneNumber = number
                }
            }

            if managedObjectContext.hasChanges {
                do {
                    try managedObjectContext.save()
                }
                catch {
                    fatalError("Failed to save managed object context [\(error)]")
                }
            }
        }
    }

    open func addPushNumbers(_ numbers: [UserID: String]) {
        pushNumberUpdateQueue.async { [self] in
            savePushNumbers(numbers)
        }

        pushNumbers.merge(numbers) { (existingNumber, newNumber) -> String in
            return newNumber
        }
    }

    // MARK: UI Support

    public func contact(withUserId userId: UserID) -> ABContact? {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        do {
            let contacts = try persistentContainer.viewContext.fetch(fetchRequest)
            return contacts.first
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func contact(withNormalizedPhone normalizedPhoneNumber: String) -> ABContact? {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", normalizedPhoneNumber)
        do {
            let contacts = try persistentContainer.viewContext.fetch(fetchRequest)
            return contacts.first
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    /// Returns display name for a user given their user ID. Returns `ownName` if `userID` matches active user ID.
    /// - Parameters:
    ///   - userId: `UserID` to look up
    ///   - ownName: `String?` to return if `userID` matches the active user ID (e.g., "Me" or the user's chosen name)
    public func fullNameIfAvailable(for userId: UserID, ownName: String?) -> String? {
        if userId == self.userData.userId {
            return ownName
        }

        // Fetch from the address book, only if contacts permission is granted
        if ContactStore.contactsAccessAuthorized {
            if let contact = contact(withUserId: userId),
               let fullName = contact.fullName {
                return fullName
            }
        }

        // Try push name as necessary.
        if let pushName = pushNames[userId] {
            return "~\(pushName)"
        }

        return nil
    }

    public func fullNameIfAvailable(forNormalizedPhone normalizedPhoneNumber: String, ownName: String?) -> String? {
        if normalizedPhoneNumber == self.userData.normalizedPhoneNumber {
            return ownName
        }

        // Fetch from the address book.
        if let contact = contact(withNormalizedPhone: normalizedPhoneNumber),
           let fullName = contact.fullName {
            return fullName
        }

        return nil
    }

    public func fullNames(forUserIds userIds: Set<UserID>) -> [UserID : String] {
        guard !userIds.isEmpty else { return [:] }

        var results: [UserID : String] = [:]

        // 1. Try finding address book names.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId in %@", userIds)
        fetchRequest.returnsObjectsAsFaults = false
        let managedObjectContext = self.persistentContainer.newBackgroundContext()
        managedObjectContext.performAndWait {
            do {
                let contacts = try managedObjectContext.fetch(fetchRequest)
                results = contacts.reduce(into: [:]) { (names, contact) in
                    names[contact.userId!] = contact.fullName
                }
            }
            catch {
                fatalError("Unable to fetch contacts: \(error)")
            }
        }

        // 2. Get push names for everyone else.
        let pushNames = self.pushNames // TODO: probably need a lock here
        userIds.forEach { (userId) in
            if results[userId] == nil {
                results[userId] = pushNames[userId]
            }
        }

        return results
    }

    /// Name appropriate for use in mention. Does not contain "@" prefix.
    public func mentionNameIfAvailable(for userID: UserID, pushName: String?) -> String? {
        if let fullName = fullNameIfAvailable(for: userID, ownName: userData.name) {
            return fullName
        }
        if let pushName = pushName, !pushName.isEmpty {
            return pushName
        }
        return nil
    }

}
