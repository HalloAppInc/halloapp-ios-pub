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
import Combine
import Contacts
import CoreData
import Foundation
import UIKit

// MARK: Constants
fileprivate let ContactStoreMetadataCollationLocale = "CollationLocale"
fileprivate let ContactStoreMetadataContactsLoaded = "ContactsLoaded"
let ContactStoreMetadataNextFullSyncDate = "NextFullSyncDate"

/**
 Intermediate object encapsulating information about  AddressBook contact's phone number.

 Contains logic for converting `CNLabeledValue<CNPhoneNumber>` into a format convenient to populate `ABContact`.

 Recent iOS versions allow storing phone numbers in non-Lating numerals (e.g. Devanagari, Arabic). Those are converted to Latin numerals that server understands.
 */
fileprivate struct PhoneProxy {
    private(set) var phoneNumber: String, localizedPhoneNumber: String?

    init?(_ phoneNumberValue: CNLabeledValue<CNPhoneNumber>) {
        if phoneNumberValue.value.stringValue.isEmpty {
            // It looks like the phone number might be an empty string in some cases (iOS bug?). Ignore those.
            return nil
        }
        self.phoneNumber = phoneNumberValue.value.stringValue;
        ///TODO: convert non-latin digits and populate `localizedPhoneNumber`
    }
}

/**
 Intermediate object encapsulating intormation about AddressBook's contact.

 Contains logic that consumes a `CNContact` object and loads all information that our app needs into format convenient for  populating `ABContact` instances.
 */
fileprivate struct ContactProxy {
    private(set) var identifier: String
    private(set) var fullName = "", givenName = "", searchTokenList = ""
    private(set) var phones: [PhoneProxy]

    init(_ contact: CNContact) {
        self.identifier = contact.identifier

        // Note: If contact doesn't have a property set, CNContact will return an empty string, not nil.
        self.givenName = contact.givenName

        // Try to get a composite name for the contact using AddressBook API.
        // If API returns an empty string, try using: Company name, Nickname, Emails, Phone Numbers.
        if self.givenName.lengthOfBytes(using: .utf8) + contact.familyName.lengthOfBytes(using: .utf8) < 1000 {
            // Filter out contacts with unreasonably long names.
            self.fullName = CNContactFormatter.string(from:contact, style:.fullName) ?? ""
        } else if !self.givenName.isEmpty {
            self.fullName = self.givenName
        } else {
            self.fullName = contact.familyName
        }
        if self.fullName.isEmpty {
            DDLogWarn("CNContact/\(contact.identifier): fullName is empty")
            self.fullName = {
                if !contact.organizationName.isEmpty {
                    return contact.organizationName
                }
                if !contact.nickname.isEmpty {
                    return contact.nickname
                }
                return ""
            } ()

            // Fallback to phone number.
            if self.fullName.isEmpty {
                if let phone = contact.phoneNumbers.first {
                    self.fullName = phone.value.stringValue
                }
            }
            // Fallback to email address.
            if self.fullName.isEmpty {
                if let email = contact.emailAddresses.first {
                    self.fullName = email.value as String
                }
            }
        }

        // Search tokens: all names, company and nickname.
        // Note: Tokenization is fairly expensive. Unfortunately, since we have no way
        // of determining if the contact's company name has changed, we have to retokenize every single
        // time we update ABContact with its respective CNContact.
        let contactFields = [ contact.givenName, contact.middleName, contact.familyName, contact.phoneticGivenName,
                              contact.phoneticFamilyName, contact.organizationName, contact.nickname]
        var searchTokens: Set<String> = Set(contactFields.flatMap { $0.searchTokens() })
        // Add transliterated tokens to be able to search by typing contact name in English (Apple's apps do that).
        searchTokens.formUnion(searchTokens.compactMap{ $0.applyingTransform(.toLatin, reverse: false) })
        self.searchTokenList = searchTokens.sorted(by: { $0 < $1}).joined(separator: " ")

        ///TODO: load section data

        // Phones
        self.phones = contact.phoneNumbers.compactMap{ PhoneProxy($0) }
    }
}


class ContactStore {
    private var userData: UserData
    private var xmppController: XMPPController
    private var needReloadContacts = true
    private var isReloadingContacts = false

    private let contactSerialQueue = DispatchQueue(label: "com.halloapp.contacts")
    private var cancellableSet: Set<AnyCancellable> = []

    // MARK: Access to Contacts

    class var contactsAccessAuthorized: Bool {
        get {
            return ContactStore.contactsAccessStatus == .authorized
        }
    }

    class var contactsAccessRequestNecessary: Bool {
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

    private class var persistentStoreURL: URL {
        get {
            return AppContext.contactStoreURL
        }
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: ContactStore.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Contacts")
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        let managedObjectContext = self.persistentContainer.newBackgroundContext()
        managedObjectContext.performAndWait {
            block(managedObjectContext)
        }
    }

    var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }


    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData

        NotificationCenter.default.addObserver(forName: NSNotification.Name.CNContactStoreDidChange, object: nil, queue: nil) { _ in
            DDLogDebug("CNContactStoreDidChange")
            self.needReloadContacts = true
            self.reloadContactsIfNecessary()
        }

        self.cancellableSet.insert(userData.didLogOff.sink { _ in
            self.contactSerialQueue.async {
                AppContext.shared.syncManager.queue.sync {
                    self.resetStatusForAllContacts()
                }
            }
        })
    }


    // MARK: Metadata
    /**
     - returns:
     Metadata associated with contact's store.
     */
    var databaseMetadata: [String: Any]? {
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

    /**
     Update metadata associated with contact's store.

     - parameters:
        - mutator: Code that mutates store's metadata.

     */
    func mutateDatabaseMetadata(mutator: (inout [String: Any]) -> Void) {
        self.persistentContainer.persistentStoreCoordinator.performAndWait {
            var metadata: [String: Any] = [:]
            do {
                try metadata = NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL)
                mutator(&metadata)
                do {
                    try NSPersistentStoreCoordinator.setMetadata(metadata, forPersistentStoreOfType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL)
                }
                catch {
                    DDLogError("contacts/metadata/write error=[\(error)]")
                }
            }
            catch {
                DDLogError("contacts/metadata/read error=[\(error)]")
            }

        }
    }


    // MARK: Loading contacts
    /**
     Whether or not contacts have been loaded from device Address Book into app's contact store.
     */
    lazy var contactsAvailable: Bool = {
        guard let metadata = self.databaseMetadata else {
            return false
        }
        guard let result = metadata[ContactStoreMetadataContactsLoaded] as? Bool else {
            return false
        }
        return result
    }()

    /**
     Synchronize all device contacts with app's internal contacts store.

     Syncronization is performed on persistent store's  background queue.
     */
    func reloadContactsIfNecessary() {
        guard self.needReloadContacts else {
            return
        }

        guard UIApplication.shared.applicationState != .background else {
            DDLogDebug("contacts/reload/app-backgrounded")
            return
        }

        let syncManager = AppContext.shared.syncManager

        if (ContactStore.contactsAccessAuthorized) {
            DDLogInfo("contacts/reload/required")
            guard !self.isReloadingContacts else {
                DDLogInfo("contacts/reload/already-in-progress")
                return
            }
            self.needReloadContacts = false
            self.isReloadingContacts = true

            DispatchQueue.main.async {
                self.contactSerialQueue.async {
                    syncManager.queue.sync {
                        self.performOnBackgroundContextAndWait { managedObjectContext in
                            self.reloadContacts(using: managedObjectContext) { deletedIds, error in
                                if error == nil {
                                    if deletedIds != nil {
                                        syncManager.add(deleted: deletedIds!)
                                    }

                                    if syncManager.isSyncEnabled {
                                        syncManager.requestDeltaSync()
                                    } else if self.userData.isLoggedIn {
                                        DispatchQueue.main.async {
                                            self.enableContactSync()
                                        }
                                    }
                                }

                                DispatchQueue.main.async {
                                    // Wait 2 seconds to allow incoming needReloadContacts requests to coalesce, and then
                                    // check again to see if we need to reload the address book.
                                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2.0) {
                                        self.isReloadingContacts = false
                                        self.reloadContactsIfNecessary()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else if !syncManager.isSyncEnabled {
            if self.userData.isLoggedIn {
                DispatchQueue.main.async {
                    self.enableContactSync()
                }
            }
        }
    }

    private var syncWillBeEnabled = false
    func enableContactSync() {
        if self.xmppController.isConnectedToServer {
            AppContext.shared.syncManager.enableSync()
        } else if (!self.syncWillBeEnabled) {
            self.syncWillBeEnabled = true
            self.cancellableSet.insert(
                self.xmppController.didConnect.sink { _ in
                    AppContext.shared.syncManager.enableSync()
                    self.syncWillBeEnabled = false
                }
            )
        }
    }

    /**
     Synchronize device's Address Book and app's contact store.

     - parameters:
        - context: Managed object context to use.
        - completion: Code to execute on method completion.
     */
    private func reloadContacts(using context: NSManagedObjectContext, completion: (_ deletedIDs: Set<ABContact.NormalizedPhoneNumber>?, _ error: Error?) -> Void) {
        context.retainsRegisteredObjects = true

        let startTime = Date()
        let contactsAvailable = self.contactsAvailable

        let allContactsRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
        allContactsRequest.returnsObjectsAsFaults = false

        var numberOfContactsBeingUpdated = 0
        do {
            try numberOfContactsBeingUpdated = context.count(for: allContactsRequest)
        }
        catch {
            ///TODO: delete contacts store
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Harvest all the WAAddressBookContact objects from the store in one fetch.
        // As we process device contacts, from this set we'll subtract contacts
        // that are still present on device.
        var contactsToDelete: [ABContact]
        do {
            try contactsToDelete = context.fetch(allContactsRequest)
            DDLogInfo("contacts/reload/fetch-existing count=[\(contactsToDelete.count)]")
        }
        catch {
            ///TODO: delete contacts store
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Fetch identifiers for all contacts on the device with the required sort order.
        // Then, if contacts were loaded before, map all existing contacts by their address book identifiers.
        let cnContactStore = CNContactStore()
        var allContactIdentifiers: [String] = []
        do {
            try allContactIdentifiers = self.identifiers(from: cnContactStore)
            DDLogInfo("contacts/reload/fetch-identifiers count=[\(allContactIdentifiers.count)]")
        } catch {
            DDLogError("contacts/reload/fetch-identifiers/failed error=[\(error)]")
            completion(nil, error)
            return
        }
        var identifiersToContactsMap: [String: [ABContact]] = [:]
        if contactsAvailable && !allContactIdentifiers.isEmpty {
            let allIdentifiers = Set(allContactIdentifiers)
            let allContactsWithIdentifiers = contactsToDelete.filter { allIdentifiers.contains($0.identifier!)}
            identifiersToContactsMap = Dictionary(grouping: allContactsWithIdentifiers) { $0.identifier! }
        }

        DDLogInfo("contacts/reload/all-fetches-done time=[\(Date().timeIntervalSince(startTime))]")

        // This will contain the up-to-date set of all address book contacts.
        var allContacts: [ABContact] = []
        // Track which userIDs were really deleted.
        var deletedUserIDs: Set<ABContact.NormalizedPhoneNumber> = Set(), existingUserIDs: Set<ABContact.NormalizedPhoneNumber> = Set()
        var uniqueContactKeys: Set<String> = Set()

        // Create/update ABContact entries from device contacts.
        let keysToFetch = [ CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                            CNContactGivenNameKey as CNKeyDescriptor, CNContactPhoneticGivenNameKey as CNKeyDescriptor,
                            CNContactFamilyNameKey as CNKeyDescriptor, CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
                            CNContactMiddleNameKey as CNKeyDescriptor, CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
                            CNContactOrganizationNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor,
                            CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor ]
        let cnContactFetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
        ///TODO: check memory usage for larger address books on older devices
        cnContactFetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: allContactIdentifiers)
        cnContactFetchRequest.sortOrder = .userDefault
        do {
            try cnContactStore.enumerateContacts(with: cnContactFetchRequest) { (cnContact, stop) in
                let existingContacts = identifiersToContactsMap[cnContact.identifier]
                let (contacts, newContacts) = self.reloadContactData(from: cnContact, using: context,
                                                                     existingContacts: existingContacts ?? [],
                                                                     uniqueContactKeys: &uniqueContactKeys)
                allContacts.append(contentsOf: contacts)
                if newContacts.count != contacts.count {
                    // Check above is a optimization for initial address book sync:
                    // if all contacts are new contacts then it's guaranteed that
                    // they will not be in "contactsToDelete".
                    contactsToDelete.removeAll(where: { contacts.contains($0) })
                }
                existingUserIDs.formUnion(contacts.compactMap{ $0.normalizedPhoneNumber })
            }
        } catch {
            DDLogError("Failed to fetch device contacts: \(error)")
            completion(nil, error)
            return
        }
        DDLogInfo("contacts/reload/finished time=[\(Date().timeIntervalSince(startTime))]")

        // Re-sort contacts
        var resortAllContacts = !self.contactsAvailable || numberOfContactsBeingUpdated == 0
        let currentLocale = Locale.current.languageCode
        if let lastLocale = self.databaseMetadata?[ContactStoreMetadataCollationLocale] as? String {
            if lastLocale != currentLocale {
                DDLogInfo("contacts/reload/locale-changed/from/\(lastLocale)/to/\(currentLocale ?? "")")
                resortAllContacts = true
            }
        }
        // re-sort contacts
        autoreleasepool {
            var lastSort: Int32 = 0
            let totalContactsCount = allContacts.count
            for (index, contact) in allContacts.enumerated() {
                // Simple algorithm for initial contacts processing and when the locale has changed,
                // where a lot of contacts have to be reassigned to new sections.
                if resortAllContacts {
                    lastSort += 1000
                    contact.sort = lastSort
                }
                    // Complex algorithm when reloading contacts. Note that this is very slow if a lot of
                    // contacts have been assigned different sections (e.g. after changing the phone's locale).
                    // We skip this step if this is a child contact (i.e. not shown on the contacts list).
                else {
                    let currentSort: Int32 = contact.sort
                    if currentSort <= lastSort || currentSort-lastSort > 1000 {
                        var nextSort: Int32 = 0

                        var nItems: Int32 = 0
                        var j = index + 1
                        while j < totalContactsCount-1 {
                            let nextContact = allContacts[j]
                            if nextContact.sort > lastSort + nItems {
                                nextSort = nextContact.sort
                                break
                            }
                            nItems += 1
                            j += 1
                        }
                        if currentSort > lastSort && currentSort < nextSort {
                            lastSort = currentSort
                        } else {
                            var proposedSort: Int32
                            if nextSort > 0 {
                                proposedSort = lastSort + (nextSort - lastSort) / (nItems + 2)
                            } else {
                                proposedSort = lastSort + 1000
                            }
                            contact.sort = proposedSort
                            lastSort = proposedSort
                            DDLogDebug("contacts/reload/contact/update-sort [\(contact.fullName ?? "<<NO NAME>>")]:[\(currentSort)]->[\(proposedSort)]")
                        }
                    } else {
                        lastSort = currentSort
                    }
                }
            }
        }
        DDLogInfo("contacts/reload/re-sorted time=[\(Date().timeIntervalSince(startTime))]")

        autoreleasepool {
            DDLogInfo("contacts/reload/will-delete count=[\(contactsToDelete.count)]")
            // We do not need to worry about recently added contacts because contactsToDelete was
            // derived from a snapshot of all the WAAddressBookContact objects in our db prior to fetching all the
            // address book records.
            for contactToDelete in contactsToDelete {
                DDLogInfo("contacts/reload/will-delete id=[\(contactToDelete.identifier ?? ""))] phone=[\(contactToDelete.phoneNumber ?? ""))] userid=[\(contactToDelete.normalizedPhoneNumber ?? ""))]")
                if let normalizedPhoneNumber = contactToDelete.normalizedPhoneNumber {
                    deletedUserIDs.insert(normalizedPhoneNumber)
                }
                context.delete(contactToDelete)
            }
        }

        // If phone number was deleted in one contact, but is still present in another, we should not report it as deleted to the server.
        deletedUserIDs.subtract(existingUserIDs)

        DDLogInfo("contacts/reload/will-save time=[\(Date().timeIntervalSince(startTime))]")
        do {
            try context.save()
            DDLogInfo("contacts/reload/did-save time=[\(Date().timeIntervalSince(startTime))]")
        } catch {
            DDLogError("contacts/reload/save-error error=[\(error)]")
        }

        self.mutateDatabaseMetadata { metadata in
            metadata[ContactStoreMetadataCollationLocale] = currentLocale
        }

        DDLogInfo("contacts/reload/finish time=[\(Date().timeIntervalSince(startTime))]")

        DispatchQueue.main.async {
            if (!self.contactsAvailable) {
                self.contactsAvailable = true
                self.mutateDatabaseMetadata{ metadata in
                    metadata[ContactStoreMetadataContactsLoaded] = true
                }
            }
        }

        completion(deletedUserIDs, nil);
    }

    /**
     Returns identifiers (`CNContact.identifier`) for all contacts on device.
     */
    private func identifiers(from cnContactStore: CNContactStore) throws -> [String] {
        let contactsFetchRequest = CNContactFetchRequest(keysToFetch: [])
        contactsFetchRequest.sortOrder = .userDefault
        var allContactIdentifiers: [String] = []
        try cnContactStore.enumerateContacts(with: contactsFetchRequest) { (contact, _) in
            allContactIdentifiers.append(contact.identifier)
        }
        return allContactIdentifiers
    }

    /**
     Add a new empty ABContact to the provided managed object context and populate contact's identifier.
     */
    private func addNewContact(from contactProxy: ContactProxy, into context: NSManagedObjectContext) -> ABContact {
        DDLogInfo("contacts/reload/create-new id=[\(contactProxy.identifier)]")
        let contact = NSEntityDescription.insertNewObject(forEntityName: "ABContact", into: context) as! ABContact
        contact.identifier = contactProxy.identifier
        return contact
    }

    /**
     Reload all relevant data from a `CNContact` instance.

     - returns:
     Two ABContact sets: first would hold all contacts associated with a given address book entry. Second would be contacts that were just added.

     - parameters:
        - cnContact: Contact fetched from iOS Address Book.
        - context: Managed object context to add new `ABContact` instances to.
        - existingContacts: Existing (created during previous sync sessions) contacts with the same identifier as `cnContact`.
        - uniqueContactKeys: An external object used to track and remove contact duplicates.
     */
    private func reloadContactData(from cnContact: CNContact, using context: NSManagedObjectContext,
                                   existingContacts: [ABContact], uniqueContactKeys: inout Set<String>) -> ([ABContact], [ABContact]) {

        let contactProxy = ContactProxy(cnContact)

        var contacts: [ABContact] = [], inserted: [ABContact] = []

        // Map all contacts by phone number.
        var phoneToContactMap: [String: ABContact] = [:]
        for contact in existingContacts {
            if let phoneNumber = contact.phoneNumber {
                phoneToContactMap[phoneNumber.unformattedPhoneNumber()] = contact
            }
        }

        // Special case when contact has zero phone numbers.
        if contactProxy.phones.isEmpty {
            let contactKey = contactProxy.fullName
            if !contactKey.isEmpty && uniqueContactKeys.contains(contactKey) {
                DDLogWarn("skip-duplicate [no phone]")
            } else {
                if !contactKey.isEmpty {
                    uniqueContactKeys.insert(contactKey)
                }
                if existingContacts.isEmpty || !phoneToContactMap.isEmpty {
                    // existingContacts.isEmpty: New contact without phone numbers.
                    // !phoneToContactMap.isEmpty: All phone numbers from contact got deleted.
                    let contact = self.addNewContact(from: contactProxy, into: context)
                    contact.status = .invalid
                    inserted.append(contact)
                    contacts.append(contact)
                } else if existingContacts.count == 1 && phoneToContactMap.isEmpty {
                    // If contact still has no phone numbers associated - mark it as current.
                    // Otherwise do nothing and let code below create ABContact entries for
                    // each phone number and entry without phone number will be deleted.
                    contacts.append(existingContacts.first!)
                }
            }
        }

        // Sync ABContact with address book data.
        for phoneProxy in contactProxy.phones {
            let contactKey = contactProxy.fullName.isEmpty ? phoneProxy.phoneNumber : (contactProxy.fullName + "_" + phoneProxy.phoneNumber)
            if uniqueContactKeys.contains(contactKey) {
                DDLogInfo("skip-duplicate [\(phoneProxy.phoneNumber):\(contactProxy.fullName.prefix(3))]")
                continue
            }
            uniqueContactKeys.insert(contactKey)
            var contact = phoneToContactMap[phoneProxy.phoneNumber.unformattedPhoneNumber()]
            if contact == nil {
                let newContact = self.addNewContact(from: contactProxy, into: context)
                newContact.phoneNumber = phoneProxy.phoneNumber
                phoneToContactMap[phoneProxy.phoneNumber] = newContact
                inserted.append(newContact)
                contact = newContact
            }
            contacts.append(contact!)
        }

        // Update all contacts with the same name.
        for contact in contacts {
            if contact.fullName != contactProxy.fullName {
                contact.fullName = contactProxy.fullName
            }
            if contact.givenName != contactProxy.givenName {
                contact.givenName = contactProxy.givenName
            }
            if contact.searchTokenList != contactProxy.searchTokenList {
                contact.searchTokenList = contactProxy.searchTokenList
            }
        }

        return (contacts, inserted)
    }

    // MARK: Server Sync

    func contactsFor(fullSync: Bool) -> [ABContact] {
        let fetchRequst = NSFetchRequest<ABContact>(entityName: "ABContact")
        if fullSync {
            fetchRequst.predicate = NSPredicate(format: "phoneNumber != nil")
        } else {
            fetchRequst.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.unknown.rawValue)
        }
        var allContacts: [ABContact] = []
        do {
            ///TODO: should use a private context here likely
            allContacts = try self.persistentContainer.viewContext.fetch(fetchRequst)
        }
        catch {
            fatalError()
        }
        return allContacts
    }

    private func contactsMatching(phoneNumbers: [String], in managedObjectContext: NSManagedObjectContext) -> [String: [ABContact]] {
        let fetchRequst = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequst.predicate = NSPredicate(format: "phoneNumber IN %@", phoneNumbers)
        fetchRequst.returnsObjectsAsFaults = false
        var contacts: [ABContact] = []
        do {
            try contacts = managedObjectContext.fetch(fetchRequst)
        }
        catch {
            fatalError()
        }
        return Dictionary(grouping: contacts, by: { $0.phoneNumber! })
    }

    private func contactsMatching(normalizedPhoneNumbers: [ABContact.NormalizedPhoneNumber], in managedObjectContext: NSManagedObjectContext) -> [String: [ABContact]] {
        let fetchRequst = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequst.predicate = NSPredicate(format: "normalizedPhoneNumber IN %@", normalizedPhoneNumbers)
        fetchRequst.returnsObjectsAsFaults = false
        var contacts: [ABContact] = []
        do {
            try contacts = managedObjectContext.fetch(fetchRequst)
        }
        catch {
            fatalError()
        }
        return Dictionary(grouping: contacts, by: { $0.normalizedPhoneNumber! })
    }

    private func update(contacts: [ABContact], with xmppContact: XMPPContact, updating newUsersSet: inout Set<ABContact.NormalizedPhoneNumber>) {
        let newStatus: ABContact.Status = xmppContact.registered ? .in : (xmppContact.normalized == nil ? .invalid : .out)
        if newStatus == .invalid {
            DDLogInfo("contacts/sync/process-results/invalid [\(xmppContact.raw!)]")
        }
        for abContact in contacts {
            // Update status.
            let previousStatus = abContact.status
            if newStatus != previousStatus {
                abContact.status = newStatus

                if newStatus == .in {
                    DDLogInfo("contacts/sync/process-results/new-user [\(xmppContact.normalized!)]:[\(abContact.fullName ?? "<<NO NAME>>")]")
                    newUsersSet.insert(xmppContact.normalized!)
                } else if previousStatus == .in && newStatus == .out {
                    DDLogInfo("contacts/sync/process-results/delete-user [\(xmppContact.normalized!)]:[\(abContact.fullName ?? "<<NO NAME>>")]")
                }
            }

            // Store normalized phone number.
            if xmppContact.normalized != abContact.normalizedPhoneNumber {
                abContact.normalizedPhoneNumber = xmppContact.normalized
            }

            // Update userId
            if xmppContact.userid != abContact.userId {
                DDLogInfo("contacts/sync/process-results/userid-update [\(abContact.fullName ?? "<<NO NAME>>")]: [\(abContact.userId ?? "")] -> [\(xmppContact.userid ?? "")]")
                abContact.userId = xmppContact.userid
            }
        }
    }

    func processSync(results: [XMPPContact], isFullSync: Bool, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("contacts/sync/process-results/start")
        let startTime = Date()

        let allPhoneNumbers = results.map{ $0.raw! } // none must not be empty

        let phoneNumberToContactsMap = self.contactsMatching(phoneNumbers: allPhoneNumbers, in: managedObjectContext)
        var newUsers: Set<ABContact.NormalizedPhoneNumber> = []
        for xmppContact in results {
            if let contacts = phoneNumberToContactsMap[xmppContact.raw!] {
                self.update(contacts: contacts, with: xmppContact, updating: &newUsers)
            }
        }

        DDLogInfo("contacts/sync/process-results/will-save time=[\(Date().timeIntervalSince(startTime))]")
        do {
            try managedObjectContext.save()
            DDLogInfo("contacts/sync/process-results/did-save time=[\(Date().timeIntervalSince(startTime))]")
        } catch {
            DDLogError("contacts/sync/process-results/save-error error=[\(error)]")
        }


        DDLogInfo("contacts/sync/process-results/finish time=[\(Date().timeIntervalSince(startTime))]")
    }

    func processNotification(contacts xmppContacts: [XMPPContact], using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("contacts/notification/process")
        let selfPhoneNumber = self.userData.phone
        // Server can send a "new friend" notification for user's own phone number too (on first sync) - filter that one out.
        let allNormalizedPhoneNumbers = xmppContacts.map{ $0.normalized! }.filter{ $0 != selfPhoneNumber }
        guard !allNormalizedPhoneNumbers.isEmpty else {
            DDLogInfo("contacts/notification/process/empty")
            return
        }
        let phoneNumberToContactsMap = self.contactsMatching(normalizedPhoneNumbers: allNormalizedPhoneNumbers, in: managedObjectContext)
        var newUsers: Set<ABContact.NormalizedPhoneNumber> = []
        for xmppContact in xmppContacts {
            if let contacts = phoneNumberToContactsMap[xmppContact.normalized!] {
                self.update(contacts: contacts, with: xmppContact, updating: &newUsers)
            }
        }
        DDLogInfo("contacts/notification/process/will-save")
        do {
            try managedObjectContext.save()
            DDLogInfo("contacts/notification/process/did-save")
        } catch {
            DDLogError("contacts/snotification/process/save-error error=[\(error)]")
        }
    }

    private func resetStatusForAllContacts() {
        DDLogWarn("contacts/reset-status")
        self.performOnBackgroundContextAndWait { managedObjectContext in
            let request = NSBatchUpdateRequest(entity: ABContact.entity())
            request.predicate = NSPredicate(format: "statusValue != %d", ABContact.Status.invalid.rawValue)
            request.propertiesToUpdate = [ "statusValue": ABContact.Status.unknown.rawValue ]
            do {
                let result = try managedObjectContext.execute(request) as? NSBatchUpdateResult
                DDLogInfo("contacts/reset-status/complete result=[\(String(describing: result))]")
            }
            catch {
                DDLogError("contacts/reset-status/error \(error)")
                fatalError("Failed to execute request: \(error)")
            }

            do {
                try managedObjectContext.save()
                DDLogInfo("contacts/reset-status/save-complete")
            }
            catch {
                DDLogError("contacts/reset-status/error \(error)")
            }
        }
    }

    // MARK: Fetching contacts

    func allRegisteredContactIDs() -> [ABContact.UserID] {
        let fetchRequst = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequst.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.in.rawValue)
        do {
            let allContacts = try self.persistentContainer.viewContext.fetch(fetchRequst)
            return allContacts.compactMap { $0.normalizedPhoneNumber }
        }
        catch {
            fatalError()
        }
    }

    // MARK: SwiftUI Support

    func fullName(for phoneNumber: ABContact.NormalizedPhoneNumber) -> String {
        if phoneNumber == self.userData.phone {
            // TODO: return correct pronoun.
            return "Me"
        }

        var fullName = phoneNumber
        let fetchRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", phoneNumber)
        do {
            let contacts = try self.persistentContainer.viewContext.fetch(fetchRequest)
            if let name = contacts.first?.fullName {
                fullName = name
            }
        }
        catch {
            fatalError()
        }
        return fullName
    }

    func firstName(for phoneNumber: ABContact.NormalizedPhoneNumber) -> String {
        if phoneNumber == self.userData.phone {
            // TODO: return correct pronoun.
            return "I"
        }

        var firstName = phoneNumber
        let fetchRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber == %@", phoneNumber)
        do {
            let contacts = try self.persistentContainer.viewContext.fetch(fetchRequest)
            if let name = contacts.first?.givenName {
                firstName = name
            }
        }
        catch {
            fatalError()
        }
        return firstName
    }
}
