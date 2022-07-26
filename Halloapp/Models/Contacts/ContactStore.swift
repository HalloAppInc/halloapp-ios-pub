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
import ContactsUI
import Core
import CoreCommon
import CoreData

// MARK: Constants

private let ContactStoreMetadataCollationLocale = "CollationLocale"
private let ContactStoreMetadataContactsLoaded = "ContactsLoaded"
private let ContactsStoreMetadataContactsSynced = "ContactsSynced"
let ContactStoreMetadataNextFullSyncDate = "NextFullSyncDate"

/**
 Intermediate object encapsulating information about  AddressBook contact's phone number.

 Contains logic for converting `CNLabeledValue<CNPhoneNumber>` into a format convenient to populate `ABContact`.

 Recent iOS versions allow storing phone numbers in non-Latin numerals (e.g. Devanagari, Arabic). Those are converted to Latin numerals that server understands.
 */
private struct PhoneProxy {
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
 Intermediate object encapsulating information about AddressBook's contact.

 Contains logic that consumes a `CNContact` object and loads all information that our app needs into format convenient for  populating `ABContact` instances.
 */
private struct ContactProxy {
    private(set) var identifier: String
    private(set) var fullName = "", givenName = "", indexName = "", searchTokenList = ""
    private(set) var phones: [PhoneProxy]

    init(_ contact: CNContact) {
        identifier = contact.identifier

        // Note: If contact doesn't have a property set, CNContact will return an empty string, not nil.
        givenName = contact.givenName

        // Try to get a composite name for the contact using AddressBook API.
        // If API returns an empty string, try using: Company name, Nickname, Emails, Phone Numbers.
        if givenName.lengthOfBytes(using: .utf8) + contact.familyName.lengthOfBytes(using: .utf8) < 1000 {
            // Filter out contacts with unreasonably long names.
            fullName = CNContactFormatter.string(from:contact, style:.fullName) ?? ""
        } else if !givenName.isEmpty {
            fullName = givenName
        } else {
            fullName = contact.familyName
        }
        if fullName.isEmpty {
            DDLogWarn("CNContact/\(contact.identifier): fullName is empty")
            fullName = {
                if !contact.organizationName.isEmpty {
                    return contact.organizationName
                }
                if !contact.nickname.isEmpty {
                    return contact.nickname
                }
                return ""
            } ()

            // Fallback to email address.
            if fullName.isEmpty {
                if let email = contact.emailAddresses.first {
                    fullName = email.value as String
                }
            }

            // Fallback to phone number.
            if fullName.isEmpty {
                if let phone = contact.phoneNumbers.first {
                    fullName = phone.value.stringValue
                }
            }
        }

        // Name used to split contacts in sections.
        if (CNContactsUserDefaults.shared().sortOrder == .givenName) {
            indexName = contact.phoneticGivenName
            if indexName.isEmpty {
                indexName = contact.givenName
            }
            if indexName.isEmpty {
                indexName = contact.familyName
            }
        } else {
            indexName = contact.phoneticFamilyName
            if indexName.isEmpty {
                indexName = contact.familyName
            }
            if indexName.isEmpty {
                indexName = contact.givenName
            }
        }
        if indexName.isEmpty && contact.contactType == .organization {
            indexName = contact.organizationName
        }
        if indexName.isEmpty {
            indexName = contact.nickname
        }
        if indexName.isEmpty {
            indexName = fullName
        }

        // iOS ignores non-alphanumeric characters in names - so should we.
        indexName = indexName.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        // Search tokens: all names, company and nickname.
        // Note: Tokenization is fairly expensive. Unfortunately, since we have no way
        // of determining if the contact's company name has changed, we have to retokenize every single
        // time we update ABContact with its respective CNContact.
        let contactFields = [ contact.givenName, contact.middleName, contact.familyName, contact.phoneticGivenName,
                              contact.phoneticFamilyName, contact.organizationName, contact.nickname]
        var searchTokens: Set<String> = Set(contactFields.flatMap { $0.searchTokens() })
        // Add transliterated tokens to be able to search by typing contact name in English (Apple's apps do that).
        searchTokens.formUnion(searchTokens.compactMap{ $0.applyingTransform(.toLatin, reverse: false) })
        searchTokenList = searchTokens.sorted(by: { $0 < $1}).joined(separator: " ")

        // Phones
        phones = contact.phoneNumbers.compactMap{ PhoneProxy($0) }
    }
}

class ContactStoreMain: ContactStore {

    private let contactSerialQueue = DispatchQueue(label: "com.halloapp.contacts")
    private var cancellableSet: Set<AnyCancellable> = []

    let didCompleteInitialSync = PassthroughSubject<Void, Never>()
    let didAddressBookChange = PassthroughSubject<Void, Never>()
    let didDiscoverNewUsers = PassthroughSubject<[UserID], Never>()

    // MARK: Init

    required init(userData: UserData) {
        super.init(userData: userData)

        NotificationCenter.default.addObserver(forName: NSNotification.Name.CNContactStoreDidChange, object: nil, queue: nil) { _ in
            DDLogDebug("CNContactStoreDidChange")
            self.needReloadContacts = true
            self.reloadContactsIfNecessary()
        }

        self.cancellableSet.insert(userData.didLogIn.sink {
            MainAppContext.shared.syncManager.disableSync() // resets next full sync date
            
            self.enableContactSync()
        })

        self.cancellableSet.insert(userData.didLogOff.sink { _ in
            // Reset server-provided data for all contacts.
            self.contactSerialQueue.async {
                MainAppContext.shared.syncManager.queue.sync {
                    self.resetStatusForAllContacts()
                }
            }

            // Remove previous sync flag.
            self.mutateDatabaseMetadata { (metadata) in
                metadata[ContactsStoreMetadataContactsSynced] = nil
            }
        })
    }

    // MARK: Database Metadata
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
    private var needReloadContacts = true
    private var isReloadingContacts = false

    /**
     Whether or not contacts have been loaded from device Address Book into app's contact store.
     */
    private lazy var isContactsAvailable: Bool = {
        guard let metadata = self.databaseMetadata else {
            return false
        }
        guard let result = metadata[ContactStoreMetadataContactsLoaded] as? Bool else {
            return false
        }
        return result
    }()

    var isInitialSyncCompleted: Bool {
        get {
            guard let result = databaseMetadata?[ContactsStoreMetadataContactsSynced] as? Bool else {
                return false
            }
            return result
        }
        set {
            mutateDatabaseMetadata { metadata in
                metadata[ContactsStoreMetadataContactsSynced] = newValue
            }
        }
    }

    /**
     Synchronize all device contacts with app's internal contacts store.

     Synchronization is performed on persistent store's  background queue.
     */
    func reloadContactsIfNecessary() {
        guard needReloadContacts else {
            return
        }

        let syncManager = MainAppContext.shared.syncManager!
        
        guard ContactStore.contactsAccessAuthorized else {
            // TODO: delete local contact cache
            self.deleteAllContacts()
            
            if !syncManager.isSyncEnabled {
                if userData.isLoggedIn {
                    DispatchQueue.main.async {
                        self.enableContactSync()
                    }
                }
            }
            return
        }

        DDLogInfo("contacts/reload/required")
        guard !isReloadingContacts else {
            DDLogInfo("contacts/reload/already-in-progress")
            return
        }
        needReloadContacts = false
        isReloadingContacts = true

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
                                    syncManager.requestSync()
                                } else if self.userData.isLoggedIn {
                                    DispatchQueue.main.async {
                                        self.enableContactSync()
                                    }
                                }
                                
                                self.didAddressBookChange.send()
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
    }

    func enableContactSync() {
        MainAppContext.shared.syncManager?.enableSync()
    }

    /**
     Synchronize device's Address Book and app's contact store.

     - parameters:
        - context: Managed object context to use.
        - completion: Code to execute on method completion.
     */
    private func reloadContacts(using context: NSManagedObjectContext, completion: (_ deletedPhoneNumbers: Set<ABContact.NormalizedPhoneNumber>?, _ error: Error?) -> Void) {
        let startTime = Date()
        let contactsAvailable = self.isContactsAvailable

        let allContactsRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
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
        // Track which phone numbers were really deleted.
        var deletedPhoneNumbers: Set<ABContact.NormalizedPhoneNumber> = Set(), existingPhoneNumbers: Set<ABContact.NormalizedPhoneNumber> = Set()
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
        if !allContactIdentifiers.isEmpty {
            cnContactFetchRequest.predicate = CNContact.predicateForContacts(withIdentifiers: allContactIdentifiers)
        }
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
                existingPhoneNumbers.formUnion(contacts.compactMap{ $0.normalizedPhoneNumber })
            }
        } catch {
            DDLogError("Failed to fetch device contacts: \(error)")
            completion(nil, error)
            return
        }
        DDLogInfo("contacts/reload/finished time=[\(Date().timeIntervalSince(startTime))]")

        // Re-sort contacts
        var resortAllContacts = !contactsAvailable || numberOfContactsBeingUpdated == 0
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
                DDLogInfo("contacts/reload/will-delete id=[\(contactToDelete.identifier ?? ""))] phone=[\(contactToDelete.phoneNumber ?? ""))] userid=[\(contactToDelete.userId ?? ""))]")
                if let normalizedPhoneNumber = contactToDelete.normalizedPhoneNumber {
                    deletedPhoneNumbers.insert(normalizedPhoneNumber)
                }
                context.delete(contactToDelete)
            }
        }

        // If phone number was deleted in one contact, but is still present in another, we should not report it as deleted to the server.
        deletedPhoneNumbers.subtract(existingPhoneNumbers)

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
            if !self.isContactsAvailable {
                self.isContactsAvailable = true
                self.mutateDatabaseMetadata{ metadata in
                    metadata[ContactStoreMetadataContactsLoaded] = true
                }
            }
        }

        completion(deletedPhoneNumbers, nil);
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
                } else if let firstContact = existingContacts.first, existingContacts.count == 1 && phoneToContactMap.isEmpty {
                    // If contact still has no phone numbers associated - mark it as current.
                    // Otherwise do nothing and let code below create ABContact entries for
                    // each phone number and entry without phone number will be deleted.
                    contacts.append(firstContact)
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
            if let contact = phoneToContactMap[phoneProxy.phoneNumber.unformattedPhoneNumber()] {
                contacts.append(contact)
            } else {
                let newContact = self.addNewContact(from: contactProxy, into: context)
                newContact.phoneNumber = phoneProxy.phoneNumber
                phoneToContactMap[phoneProxy.phoneNumber] = newContact
                inserted.append(newContact)
                contacts.append(newContact)
            }
        }

        // Update all contacts with the same name.
        for contact in contacts {
            if contact.fullName != contactProxy.fullName {
                contact.fullName = contactProxy.fullName
            }
            if contact.givenName != contactProxy.givenName {
                contact.givenName = contactProxy.givenName
            }
            if contact.indexName != contactProxy.indexName {
                contact.indexName = contactProxy.indexName
            }
            if contact.searchTokenList != contactProxy.searchTokenList {
                contact.searchTokenList = contactProxy.searchTokenList
            }
        }

        return (contacts, inserted)
    }

    // MARK: Fetching

    func contacts(withUserIds userIds: [UserID], in managedObjectContext: NSManagedObjectContext) -> [ABContact] {
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

    func sortedContacts(withUserIds userIds: [UserID], in managedObjectContext: NSManagedObjectContext) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId in %@", userIds)
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]

        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            return contacts
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }
    }

    func addUserToAddressBook(userID: UserID, presentingVC: UIViewController) {
        guard !isContactInAddressBook(userId: userID, in: viewContext) else { return }
        guard let name = pushNames[userID] else { return }
        guard let pushNumber = pushNumber(userID) else { return }

        let store = CNContactStore()

        let newContact = CNMutableContact()
        let phone = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: pushNumber.formattedPhoneNumber))

        let nameComponents = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if nameComponents.count > 1 {
            newContact.givenName = String(nameComponents[0])
            newContact.familyName = String(nameComponents[1])
        } else {
            newContact.givenName = name
        }
        newContact.phoneNumbers = [phone]

        let vc = CNContactViewController(forNewContact : newContact)
        vc.contactStore = store
        vc.delegate = presentingVC as? CNContactViewControllerDelegate

        presentingVC.navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: Server Sync

    func contactsFor(fullSync: Bool, in managedObjectContext: NSManagedObjectContext) -> [ABContact] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        if fullSync {
            fetchRequest.predicate = NSPredicate(format: "phoneNumber != nil")
        } else {
            fetchRequest.predicate = NSPredicate(format: "statusValue == %d", ABContact.Status.unknown.rawValue)
        }
        var allContacts: [ABContact] = []
        do {
            allContacts = try managedObjectContext.fetch(fetchRequest)
        }
        catch {
            fatalError()
        }
        return allContacts
    }

    private func contactsMatching(phoneNumbers: [String], in managedObjectContext: NSManagedObjectContext) -> [String: [ABContact]] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "phoneNumber IN %@", phoneNumbers)
        fetchRequest.returnsObjectsAsFaults = false
        var contacts: [ABContact] = []
        do {
            try contacts = managedObjectContext.fetch(fetchRequest)
        }
        catch {
            fatalError()
        }
        return Dictionary(grouping: contacts, by: { $0.phoneNumber! })
    }

    private func contactsMatching(normalizedPhoneNumbers: [ABContact.NormalizedPhoneNumber], in managedObjectContext: NSManagedObjectContext) -> [String: [ABContact]] {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "normalizedPhoneNumber IN %@", normalizedPhoneNumbers)
        fetchRequest.returnsObjectsAsFaults = false
        var contacts: [ABContact] = []
        do {
            try contacts = managedObjectContext.fetch(fetchRequest)
        }
        catch {
            fatalError()
        }
        return Dictionary(grouping: contacts, by: { $0.normalizedPhoneNumber! })
    }

    /**
     - returns: Contacts whose status has been changed to "in".
     */
    private func update(contacts: [ABContact], with xmppContact: XMPPContact) -> [ABContact] {
        var newUsers: [ABContact] = []
        if xmppContact.normalized == nil {
            DDLogInfo("contacts/sync/process-results/invalid [\(xmppContact.raw ?? "<missing raw>")]")
        }
        for abContact in contacts {
            // status field is not modified in the sync anymore.
            abContact.status = .processed

            // Store normalized phone number.
            if xmppContact.normalized != abContact.normalizedPhoneNumber {
                abContact.normalizedPhoneNumber = xmppContact.normalized
            }

            // Save/update hash
            if let normalizedPhoneNumber = xmppContact.normalized {
                if abContact.phoneNumberHash == nil {
                    let hashData: Data? = normalizedPhoneNumber.sha256()
                    abContact.phoneNumberHash = hashData?.prefix(8).toHexString()
                    DDLogInfo("contacts/sync/process-results/hash-update [\(xmppContact.normalized ?? "<missing normalized number>")]:[\(abContact.phoneNumberHash ?? "<missing hash>")]")
                }
            } else if abContact.phoneNumberHash != nil {
                abContact.phoneNumberHash = nil
            }

            // Update userId
            if xmppContact.userid != abContact.userId {
                DDLogInfo("contacts/sync/process-results/userid-update [\(abContact.fullName ?? "<<NO NAME>>")|\(xmppContact.normalized ?? "<missing phone number>")]: [\(abContact.userId ?? "")] -> [\(xmppContact.userid ?? "")]")
                abContact.userId = xmppContact.userid
                if (xmppContact.userid != nil) {
                    DDLogInfo("contacts/sync/process-results/new-uid [\(xmppContact.userid ?? "<missing uid>")]")
                    newUsers.append(abContact)
                }
            }

            // Update friend count
            if xmppContact.numPotentialContacts != abContact.numPotentialContacts {
                DDLogInfo("contacts/sync/process-results/friend-count-update [\(xmppContact.normalized ?? "normalized-number-missing")]:[\(xmppContact.numPotentialContacts)]")
                abContact.numPotentialContacts = Int64(xmppContact.numPotentialContacts)
            }
        }
        return newUsers
    }

    private func notifyAboutNewUsers(_ userIds: [UserID]) {
        self.didDiscoverNewUsers.send(userIds)
    }

    func processSync(results: [XMPPContact], using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("contacts/sync/process-results/start")

        let startTime = Date()
        var discoveredUsers: [ABContact] = []
        let phoneNumberToContactsMap = contactsMatching(phoneNumbers: results.compactMap { $0.raw }, in: managedObjectContext)
        for xmppContact in results {
            if let raw = xmppContact.raw, let matchingContacts = phoneNumberToContactsMap[raw], !matchingContacts.isEmpty {
                let contacts = update(contacts: matchingContacts, with: xmppContact)
                discoveredUsers.append(contentsOf: contacts)
            }
        }

        DDLogInfo("contacts/sync/process-results/will-save time=[\(Date().timeIntervalSince(startTime))]")
        do {
            try managedObjectContext.save()
            DDLogInfo("contacts/sync/process-results/did-save time=[\(Date().timeIntervalSince(startTime))]")
        } catch {
            DDLogError("contacts/sync/process-results/save-error error=[\(error)]")
        }

        if isInitialSyncCompleted {
            let userIdsToSharePostsWith = discoveredUsers.compactMap({ $0.userId })
            if !userIdsToSharePostsWith.isEmpty {
                DispatchQueue.main.async {
                    self.notifyAboutNewUsers(userIdsToSharePostsWith)
                }
            }
        }

        DDLogInfo("contacts/sync/process-results/finish time=[\(Date().timeIntervalSince(startTime))]")
    }

    func processNotification(contacts xmppContacts: [XMPPContact], using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("contacts/notification/process userIds=[\(xmppContacts.map({ $0.userid ?? "<no userId>" }))]")
        let selfPhoneNumber = self.userData.normalizedPhoneNumber
        // Server can send a "new friend" notification for user's own phone number too (on first sync) - filter that one out.
        let allNormalizedPhoneNumbers = xmppContacts.compactMap { $0.normalized }.filter { $0 != selfPhoneNumber }
        guard !allNormalizedPhoneNumbers.isEmpty else {
            DDLogInfo("contacts/notification/process/empty")
            return
        }
        var discoveredUsers: [ABContact] = []
        let phoneNumberToContactsMap = self.contactsMatching(normalizedPhoneNumbers: allNormalizedPhoneNumbers, in: managedObjectContext)
        for xmppContact in xmppContacts {
            if let normalized = xmppContact.normalized, let matchingContacts = phoneNumberToContactsMap[normalized], !matchingContacts.isEmpty {
                let contacts = update(contacts: matchingContacts, with: xmppContact)
                discoveredUsers.append(contentsOf: contacts)
            }
        }
        DDLogInfo("contacts/notification/process/will-save")
        do {
            try managedObjectContext.save()
            DDLogInfo("contacts/notification/process/did-save")
        } catch {
            DDLogError("contacts/snotification/process/save-error error=[\(error)]")
        }

        let userIdsToSharePostsWith = discoveredUsers.compactMap({ $0.userId })
        if !userIdsToSharePostsWith.isEmpty {
            DispatchQueue.main.async {
                self.notifyAboutNewUsers(userIdsToSharePostsWith)
            }
        }
    }

    func processNotification(contactHashes: [Data], using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("contacts/notification/process hashes=[\(contactHashes.map({ $0.toHexString() }))]")

        var matchingContacts = Set<ABContact>()

        for hash in contactHashes.map({ $0.toHexString() }) {
            let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "phoneNumberHash BEGINSWITH %@", hash)
            fetchRequest.returnsObjectsAsFaults = false
            do {
                let contacts = try managedObjectContext.fetch(fetchRequest)
                matchingContacts.formUnion(contacts)
            }
            catch {
                fatalError()
            }
        }

        guard !matchingContacts.isEmpty else {
            DDLogWarn("contacts/notification/ No matching contacts")
            return
        }

        for contact in matchingContacts {
            DDLogDebug("contacts/notification/reset-status phone=[\(contact.normalizedPhoneNumber ?? "<invalid>")]")
            contact.status = .unknown
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
            request.propertiesToUpdate = [ "statusValue": ABContact.Status.unknown.rawValue,
                                           "normalizedPhoneNumber": NSExpression(forConstantValue: nil),
                                           "userId": NSExpression(forConstantValue: nil)]
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

    // MARK: Contact Names

    func fullName(for userID: UserID, showPushNumber: Bool = false, in managedObjectContext: NSManagedObjectContext) -> String {
        // Fallback to a static string.
        return fullNameIfAvailable(for: userID, ownName: Localizations.meCapitalized, showPushNumber: showPushNumber, in: managedObjectContext) ?? Localizations.unknownContact
    }

    func firstName(for userID: UserID, in managedObjectContext: NSManagedObjectContext) -> String {
        if userID == self.userData.userId {
            // TODO: return correct pronoun.
            return "I"
        }
        var firstName: String? = nil
        var fullName: String? = nil

        // Fetch from the address book.
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
        do {
            let contacts = try managedObjectContext.fetch(fetchRequest)
            if let name = contacts.first?.givenName {
                firstName = name
            }
            fullName = contacts.first?.fullName
        }
        catch {
            fatalError("Unable to fetch contacts: \(error)")
        }

        // Try full name if first name is empty
        if firstName?.isEmpty ?? true {
            firstName = fullName
        }

        // Try push name as necessary.
        if firstName == nil {
            if let pushName = self.pushNames[userID] {
                firstName = "~\(pushName)"
            }
        }

        // Fallback to a static string.
        return firstName ?? Localizations.unknownContact
    }


    // MARK: Push names

    override func addPushNames(_ names: [UserID : String]) {
        guard !names.isEmpty else { return }

        super.addPushNames(names)
    }
    
    // MARK: Push numbers

    override func addPushNumbers(_ numbers: [UserID : String]) {
        guard !numbers.isEmpty else { return }

        super.addPushNumbers(numbers)
    }

    // MARK: Mentions

    /// Name appropriate for use in mention. Does not contain "@" prefix.
    func mentionName(for userID: UserID, pushName: String?, in managedObjectContext: NSManagedObjectContext) -> String {
        if let name = mentionNameIfAvailable(for: userID, pushName: pushName, in: managedObjectContext) {
            return name
        }
        return Localizations.unknownContact
    }

    /// Returns an attributed string where mention placeholders have been replaced with contact names. User IDs are retrievable via the .userMention attribute.
    func textWithMentions(_ collapsedText: String?, mentions: [FeedMentionProtocol], in managedObjectContext: NSManagedObjectContext) -> NSAttributedString? {
        guard let collapsedText = collapsedText else { return nil }

        let mentionText = MentionText(collapsedText: collapsedText, mentionArray: mentions)

        return mentionText.expandedText { userID in
            self.mentionName(for: userID, pushName: mentions.first(where: { userID == $0.userID })?.name, in: managedObjectContext)
        }
    }
}
