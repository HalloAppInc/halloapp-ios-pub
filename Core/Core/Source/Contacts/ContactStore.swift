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

import CocoaLumberjack
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

    public class var contactsAccessAuthorized: Bool {
        get {
            return ContactStore.contactsAccessStatus == .authorized
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

    public func allInNetworkContactIDs() -> [UserID] {
        let fetchRequst = NSFetchRequest<NSDictionary>(entityName: "ABContact")
        fetchRequst.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.in.rawValue)
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

    public func allInNetworkContacts(sorted: Bool) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.in.rawValue)
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

    public lazy var pushNames: [UserID : String] = {
        return fetchAllPushNames()
    }()

    private func fetchAllPushNames() -> [UserID : String] {
        let fetchRequest: NSFetchRequest<PushName> = PushName.fetchRequest()
        do {
            let results = try self.persistentContainer.viewContext.fetch(fetchRequest)
            let names = results.reduce(into: [:]) { $0[$1.userId!] = $1.name }
            DDLogDebug("contacts/push-name/fetched  count=[\(names.count)]")
            return names
        }
        catch {
            fatalError("Failed to fetch push names  [\(error)]")
        }
    }

    // MARK: UI Support

    public func fullName(for userID: UserID) -> String {
        // Fallback to a static string.
        return fullNameIfAvailable(for: userID) ?? "Unknown Contact"
    }

    public func fullNameIfAvailable(for userID: UserID) -> String? {
        if userID == self.userData.userId {
            // TODO: return correct pronoun.
            return "Me"
        }

        var fullName: String? = nil

        // Fetch from the address book.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
        do {
            let contacts = try self.persistentContainer.viewContext.fetch(fetchRequest)
            if let name = contacts.first?.fullName {
                fullName = name
            }
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Try push name as necessary.
        if fullName == nil {
            if let pushName = self.pushNames[userID] {
                fullName = "~\(pushName)"
            }
        }

        return fullName
    }

    public func firstName(for userID: UserID) -> String {
        if userID == self.userData.userId {
            // TODO: return correct pronoun.
            return "I"
        }
        var firstName: String? = nil

        // Fetch from the address book.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
        do {
            let contacts = try self.persistentContainer.viewContext.fetch(fetchRequest)
            if let name = contacts.first?.givenName {
                firstName = name
            }
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Try push name as necessary.
        if firstName == nil {
            if let pushName = self.pushNames[userID] {
                firstName = "~\(pushName)"
            }
        }

        // Fallback to a static string.
        return firstName ?? "Unknown Contact"
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

    /// Returns an attributed string where mention placeholders have been replaced with contact names. User IDs are retrievable via the .userMention attribute.
    public func textWithMentions(_ collapsedText: String?, orderedMentions: [FeedMentionProtocol]) -> NSAttributedString? {
        guard let collapsedText = collapsedText else { return nil }

        let mentionText = MentionText(
            collapsedText: collapsedText,
            mentions: Dictionary(uniqueKeysWithValues: orderedMentions.map { ($0.index, $0.userID) }))

        return mentionText.expandedText { userID in
            self.mentionName(
                for: userID,
                pushedName: orderedMentions.first(where: { userID == $0.userID })?.name)
        }
    }

    /// Name appropriate for use in mention. Does not contain "@" prefix.
    public func mentionName(for userID: UserID, pushedName: String?) -> String {
        if userID == userData.userId {
            return userData.name
        }
        if let fullName = fullNameIfAvailable(for: userID) {
            return fullName
        }
        if let pushedName = pushedName, !pushedName.isEmpty {
            return pushedName
        }
        return "Unknown Contact"
    }
}
