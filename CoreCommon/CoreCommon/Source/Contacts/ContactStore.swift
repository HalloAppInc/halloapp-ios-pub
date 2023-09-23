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

private struct PushNumberData {
    public var normalizedPhoneNumber: String
    public var isMessagingAccepted: Bool

    public init(normalizedPhoneNumber: String, isMessagingAccepted: Bool = false) {
        self.normalizedPhoneNumber = normalizedPhoneNumber
        self.isMessagingAccepted = isMessagingAccepted
    }
}

open class ContactStore {

    public let userData: UserData
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.contactStore")

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
            return AppContextCommon.contactStoreURL
        }
    }

    public private(set) var persistentContainer: NSPersistentContainer = {
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

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    public private(set) var pushNames: [UserID: String] = [:]
    private var pushNumbersData: [UserID: PushNumberData] = [:]
    private var userDefaults: UserDefaults

    required public init(userData: UserData, userDefaults: UserDefaults) {
        self.userData = userData
        self.userDefaults = userDefaults
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true

        viewContext.performAndWait {
            loadPushNamesAndNumbers()
        }
    }

    public func loadPushNamesAndNumbers() {
        pushNames = ContactStore.fetchAllPushNames(using: viewContext)
        pushNumbersData = ContactStore.fetchAllPushNumbersData(using: viewContext)
    }

    private func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return context
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let enqueuedTime = Date()
        if userDefaults.bool(forKey: "disableQueueSerialization") {
            let context = self.newBackgroundContext()
            context.perform {
                if -enqueuedTime.timeIntervalSinceNow > AppContextCommon.queueStallTimeout {
                    AppContextCommon.shared.errorLogger?.logError(NSError(domain: "stalledContactStoreQueue", code: 1408))
                }
                block(context)
            }
        } else {
            backgroundProcessingQueue.async { [weak self] in
                guard let self = self else { return }

                let context = self.newBackgroundContext()
                context.performAndWait {
                    if -enqueuedTime.timeIntervalSinceNow > AppContextCommon.queueStallTimeout {
                        AppContextCommon.shared.errorLogger?.logError(NSError(domain: "stalledContactStoreQueue", code: 1408))
                    }
                    block(context)
                }
            }
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        let enqueuedTime = Date()
        if userDefaults.bool(forKey: "disableQueueSerialization") {
            let context = self.newBackgroundContext()
            context.performAndWait {
                if -enqueuedTime.timeIntervalSinceNow > AppContextCommon.queueStallTimeout {
                    AppContextCommon.shared.errorLogger?.logError(NSError(domain: "stalledContactStoreQueue", code: 1409))
                }
                block(context)
            }
        } else {
            backgroundProcessingQueue.sync {
                let context = self.newBackgroundContext()
                context.performAndWait {
                    if -enqueuedTime.timeIntervalSinceNow > AppContextCommon.queueStallTimeout {
                        AppContextCommon.shared.errorLogger?.logError(NSError(domain: "stalledContactStoreQueue", code: 1408))
                    }
                    block(context)
                }
            }
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

    public func contacts(withUserIds userIds: [UserID], in managedObjectContext: NSManagedObjectContext) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId in %@", userIds)
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func allRegisteredContactIDs(in managedObjectContext: NSManagedObjectContext) -> [UserID] {
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "ABContact")
        fetchRequest.predicate = NSPredicate(format: "userId != nil")
        fetchRequest.propertiesToFetch = [ "userId" ]
        fetchRequest.resultType = .dictionaryResultType
        do {
            let allContacts = try managedObjectContext.fetch(fetchRequest)
            return allContacts.compactMap { $0["userId"] as? UserID }
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func allRegisteredContacts(sorted: Bool, in managedObjectContext: NSManagedObjectContext) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId != nil")
        fetchRequest.returnsObjectsAsFaults = false
        if sorted {
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        }
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func normalizedPhoneNumber(for userID: UserID, using managedObjectContext: NSManagedObjectContext) -> String? {
        if userID == self.userData.userId {
            return userData.normalizedPhoneNumber
        }
        var normalizedPhoneNumber: String? = nil

        // Fetch from the address book.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            if let number = contacts.first?.normalizedPhoneNumber {
                normalizedPhoneNumber = number
            }
        } catch {
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Try push number as necessary.
        if normalizedPhoneNumber == nil {
            if let pushNumber = self.pushNumber(userID) {
                normalizedPhoneNumber = pushNumber
            }
        }

        return normalizedPhoneNumber
    }

    public func userID(for normalizedPhoneNumber: String, using managedObjectContext: NSManagedObjectContext) -> UserID? {
        if normalizedPhoneNumber == self.userData.normalizedPhoneNumber {
            return userData.userId
        }
        var userID: UserID? = nil

        // Fetch from the address book.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", normalizedPhoneNumber)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            if let contactID = contacts.first?.userId {
                userID = contactID
            }
        } catch {
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Try looking up push db as necessary.
        if userID == nil {
            if let pushUserID = self.userID(forPushNumber: normalizedPhoneNumber, in: managedObjectContext) {
                userID = pushUserID
            }
        }

        return userID
    }

    // MARK: Push names

    private static func fetchAllPushNames(using managedObjectContext: NSManagedObjectContext) -> [UserID: String] {
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
        performSeriallyOnBackgroundContext { (managedObjectContext) in
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

    open func pushNumber(_ userID: UserID) -> String? {
        guard let pushNumberData = pushNumbersData[userID] else { return nil }
        return pushNumberData.normalizedPhoneNumber
    }

    private func userID(forPushNumber normalizedPushNumber: String, in managedObjectContext: NSManagedObjectContext) -> UserID? {
        let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", normalizedPushNumber)
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            if results.count >= 2 {
                DDLogError("contactStore/fetchUserID/fetched count=[\(results.count)]")
            }
            return results.first?.userID
        }
        catch {
            fatalError("contactStore/fetchUserID/error [\(error)]")
        }
    }

    private static func fetchAllPushNumbersData(using managedObjectContext: NSManagedObjectContext) -> [UserID: PushNumberData] {
        let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            let pushNumbersData: [UserID: PushNumberData] = results.reduce(into: [:]) {
                // auto generated managedobjects string attributes from coredata are optional even if marked as not
                guard let userID = $1.userID, let normalizedPhoneNumber = $1.normalizedPhoneNumber else {
                    DDLogError("contactStore/fetchAllPushNumbers/fetch/error push number missing userID [\($1.userID ?? "")]")
                    return
                }
                $0[userID] = PushNumberData(normalizedPhoneNumber: normalizedPhoneNumber, isMessagingAccepted: $1.isMessagingAccepted)
            }
            DDLogVerbose("contactStore/fetchAllPushNumbers/fetched count=[\(pushNumbersData.count)]")
            return pushNumbersData
        }
        catch {
            fatalError("contactStore/fetchAllPushNumbers/error [\(error)]")
        }
    }

    private var pushNumberUpdateQueue = DispatchQueue(label: "com.halloapp.contacts.pushNumber")

    private func savePushNumbersData(_ pushNumbersData: [UserID: PushNumberData]) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in

            var existingPushNumbers: [UserID : PushNumber] = [:]

            // Fetch existing numbers
            let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userID in %@", Set(pushNumbersData.keys))
            do {
                let results = try managedObjectContext.fetch(fetchRequest)
                existingPushNumbers = results.reduce(into: [:]) {
                    guard let userID = $1.userID else { return }
                    $0[userID] = $1
                }
            }
            catch {
                fatalError("contactStore/savePushNumbersData/error  [\(error)]")
            }

            // Insert new numbers / update existing
            pushNumbersData.forEach { (userID, pushNumberData) in
                if let existingPushNumber = existingPushNumbers[userID] {
                    if existingPushNumber.normalizedPhoneNumber != pushNumberData.normalizedPhoneNumber {
                        DDLogDebug("contactStore/savePushNumbers/update  userId=[\(userID)] from=[\(existingPushNumber.normalizedPhoneNumber ?? "")] to=[\(pushNumberData.normalizedPhoneNumber)]")
                        existingPushNumber.normalizedPhoneNumber = pushNumberData.normalizedPhoneNumber
                    }
                } else {
                    DDLogDebug("contactStore/savePushNumbers/new  userId=[\(userID)] number=[\(pushNumberData.normalizedPhoneNumber)]")
                    let newPushNumber = PushNumber(context: managedObjectContext)
                    newPushNumber.userID = userID
                    newPushNumber.normalizedPhoneNumber = pushNumberData.normalizedPhoneNumber
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
        var numbersData: [UserID: PushNumberData] = [:]
        numbers.forEach { (userID, number) in
            numbersData[userID] = PushNumberData(normalizedPhoneNumber: number)
        }
        addPushNumbersData(numbersData)
    }

    private func addPushNumbersData(_ newPushNumbersData: [UserID: PushNumberData]) {
        pushNumberUpdateQueue.async { [self] in
            savePushNumbersData(newPushNumbersData)
        }

        newPushNumbersData.forEach { (userID, newPushNumberData) in
            if let existingPushNumberData = pushNumbersData[userID] {
                if existingPushNumberData.normalizedPhoneNumber != newPushNumberData.normalizedPhoneNumber {
                    pushNumbersData[userID]?.normalizedPhoneNumber = newPushNumberData.normalizedPhoneNumber
                }
            } else {
                pushNumbersData[userID] = PushNumberData(normalizedPhoneNumber: newPushNumberData.normalizedPhoneNumber)
            }
        }
    }

    open func isPushNumberMessagingAccepted(userID: UserID) -> Bool {
        if let existingPushNumberData = pushNumbersData[userID] {
            return existingPushNumberData.isMessagingAccepted
        }
        return false
    }

    open func setIsMessagingAccepted(userID: UserID, isMessagingAccepted: Bool) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            let fetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "userID = %@", userID)
            do {
                let results = try managedObjectContext.fetch(fetchRequest)
                results.first?.isMessagingAccepted = isMessagingAccepted
            }
            catch {
                fatalError("contactStore/setIsMessagingAccepted/error  [\(error)]")
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

        pushNumbersData[userID]?.isMessagingAccepted = isMessagingAccepted
    }

    open func deleteAllPushNamesAndNumbers() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in

            let pushNameFetchRequest: NSFetchRequest<PushName> = PushName.fetchRequest()
            do {
                let results = try managedObjectContext.fetch(pushNameFetchRequest)
                results.forEach { managedObjectContext.delete($0) }
            }
            catch { fatalError("contactStore/deletePushNames/error  [\(error)]") }
                
            let pushNumberFetchRequest: NSFetchRequest<PushNumber> = PushNumber.fetchRequest()
            do {
                let results = try managedObjectContext.fetch(pushNumberFetchRequest)
                results.forEach { managedObjectContext.delete($0) }
            }
            catch { fatalError("contactStore/deletePushNumbers/error  [\(error)]") }

            do {
                try managedObjectContext.save()
            }
            catch { fatalError("Failed to delete managed object context [\(error)]") }
        }
    }

    open func deleteAllContacts() {
        performSeriallyOnBackgroundContext { (managedObjectContext) in

            let allContactsFetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
            do {
                let results = try managedObjectContext.fetch(allContactsFetchRequest)
                results.forEach { managedObjectContext.delete($0) }
            }
            catch { fatalError("contactStore/deleteAllContacts/error  [\(error)]") }
            do {
                try managedObjectContext.save()
            }
            catch { fatalError("Failed to delete all contacts [\(error)]") }
        }
    }

    // MARK: UI Support

    public func contact(withUserId userId: UserID, in managedObjectContext: NSManagedObjectContext) -> ABContact? {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts.first
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func isContactInAddressBook(userId: UserID, in managedObjectContext: NSManagedObjectContext) -> Bool {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        do {
            let count = try managedObjectContext.count(for: fetchRequest)
            return count > 0
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func contact(withNormalizedPhone normalizedPhoneNumber: String, in managedObjectContext: NSManagedObjectContext) -> ABContact? {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", normalizedPhoneNumber)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts.first
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func contact(withIdentifier identifier: String, in managedObjectContext: NSManagedObjectContext) -> ABContact? {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts.first
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    public func fullName(for userID: UserID, showPushNumber: Bool = false, in managedObjectContext: NSManagedObjectContext) -> String {
        // Fallback to a static string.
        return fullNameIfAvailable(for: userID, ownName: Localizations.meCapitalized, showPushNumber: showPushNumber, in: managedObjectContext) ?? Localizations.unknownContact
    }

    /// Returns display name for a user given their user ID. Returns `ownName` if `userID` matches active user ID.
    /// - Parameters:
    ///   - userId: `UserID` to look up
    ///   - ownName: `String?` to return if `userID` matches the active user ID (e.g., "Me" or the user's chosen name)
    ///   - showPushNumber: `Bool` returns user's push number  if user is not in contact book, mainly used in Chats
    public func fullNameIfAvailable(for userId: UserID, ownName: String?, showPushNumber: Bool = false, in managedObjectContext: NSManagedObjectContext) -> String? {
        if userId == self.userData.userId {
            return ownName
        }

        // Fetch from the address book, only if contacts permission is granted
        if ContactStore.contactsAccessAuthorized {
            if let contact = contact(withUserId: userId, in: managedObjectContext),
               let fullName = contact.fullName {
                return fullName
            }
        }

        // show push number if one exists
        if showPushNumber {
            if let pushNumber = pushNumber(userId) {
                return pushNumber.formattedPhoneNumber
            }
        }

        // Try push name as necessary.
        if let pushName = pushNames[userId] {
            return "~\(pushName)"
        }

        return nil
    }

    public func fullNameIfAvailable(forNormalizedPhone normalizedPhoneNumber: String, ownName: String?, in managedObjectContext: NSManagedObjectContext) -> String? {
        if normalizedPhoneNumber == self.userData.normalizedPhoneNumber {
            return ownName
        }

        // Fetch from the address book.
        if let contact = contact(withNormalizedPhone: normalizedPhoneNumber, in: managedObjectContext),
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

        performOnBackgroundContextAndWait { managedObjectContext in
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
    public func mentionNameIfAvailable(for userID: UserID, pushName: String?, in managedObjectContext: NSManagedObjectContext) -> String? {
        if let fullName = fullNameIfAvailable(for: userID, ownName: userData.name, in: managedObjectContext) {
            return fullName
        }
        if let pushName = pushName, !pushName.isEmpty {
            return pushName
        }
        return nil
    }

    // MARK: - Suggested Contacts hiding

    public func hideContactFromSuggestedInvites(identifier: String) {
        performSeriallyOnBackgroundContext { context in
            let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)
            do {
                let contacts = try context.fetch(fetchRequest)
                guard !contacts.isEmpty else {
                    DDLogError("ContactStore/hideContactFromSuggestedInvites/Could not find contact to hide")
                    return
                }
                contacts.forEach { $0.hideInSuggestedInvites = true }
                try context.save()
            }
            catch {
                fatalError("Unable to set hideInSuggestedInvites: \(error)")
            }
        }
    }

    public func resetHiddenSuggestedContacts() {
        performSeriallyOnBackgroundContext { context in
            let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "hideInSuggestedInvites == true")
            do {
                let contacts = try context.fetch(fetchRequest)
                contacts.forEach { $0.hideInSuggestedInvites = false }
                try context.save()
            }
            catch {
                fatalError("Unable to reset hideInSuggestedInvites: \(error)")
            }
        }
    }
}

// MARK: - Migration

extension ContactStore {

    public func nameInfoForMigration() -> [UserID: String] {
        var result = [UserID: String]()
        viewContext.performAndWait {
            for contact in allRegisteredContacts(sorted: false, in: viewContext) {
                guard let userID = contact.userId else {
                    continue
                }
                result[userID] = contact.fullName ?? ""
            }

            for pushName in allPushNames(in: viewContext) {
                guard let userID = pushName.userId, result[userID] == nil else {
                    continue
                }
                result[userID] = pushName.name ?? ""
            }
        }

        return result
    }

    private func allPushNames(in context: NSManagedObjectContext) -> [PushName] {
        let request = PushName.fetchRequest()

        do {
            let pushNames = try context.fetch(request)
            return pushNames
        } catch {
            DDLogError("ContactStore/allPushNames/fetch failed with error \(String(describing: error))")
        }

        return []
    }
}

public extension Localizations {
    static var userYouCapitalized: String {
        NSLocalizedString("user.you.capitalized", value: "You", comment: "Capitalized reference to the user, second person pronoun")
    }

    static var userYou: String {
        NSLocalizedString("user.you", value: "you", comment: "Reference to the user, second person pronoun")
    }

    static var meCapitalized: String {
        NSLocalizedString("meCapitalized", value: "Me", comment: "Displayed in place of own name (e.g., next to own comments)")
    }
}
