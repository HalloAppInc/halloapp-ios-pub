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

import Contacts
import CoreData
import Foundation

// Values are persisted as ABContact.status. Do not change.
enum ABContactStatus: Int16 {
    case unknown = 0
    case `in` = 1
    case `out` = 2
    case invalid = 3
}

// MARK: Constants
fileprivate let ContactStoreMetadataCollationLocale = "CollationLocale"
fileprivate let ContactStoreMetadataContactsLoaded = "ContactsLoaded"
fileprivate let ContactStoreMetadataContactsSynced = "ContactsSynced"

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
        print("CNContact/process id=[\(contact.identifier)]")

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
            print("CNContact/\(contact.identifier): fullName is empty")
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
    private var xmppController: XMPPController

    private let contactSerialQueue = DispatchQueue(label: "com.halloapp.hallo.contacts")

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

    private class func persistentStoreURL() -> URL {
        return AppContext.contactStoreURL()
    }

    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: ContactStore.persistentStoreURL())
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

    init(xmppController: XMPPController) {
        self.xmppController = xmppController
    }


    // MARK: Metadata
    /**
     - returns:
     Metadata associated with contact's store.
     */
    func databaseMetadata() -> [String: Any]? {
        var result: [String: Any] = [:]
        self.persistentContainer.persistentStoreCoordinator.performAndWait {
            do {
                try result = NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL())
            }
            catch {
                print("contacts/metadata/read error=[\(error)]")
            }
        }
        return result
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
                try metadata = NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL())
                mutator(&metadata)
                do {
                    try NSPersistentStoreCoordinator.setMetadata(metadata, forPersistentStoreOfType: NSSQLiteStoreType, at: ContactStore.persistentStoreURL())
                }
                catch {
                    print("contacts/metadata/write error=[\(error)]")
                }
            }
            catch {
                print("contacts/metadata/read error=[\(error)]")
            }

        }
    }


    // MARK: Loading contacts
    /**
     Whether or not contacts have been loaded from device Address Book into app's contact store.
     */
    lazy var contactsAvailable: Bool = {
        guard let metadata = self.databaseMetadata() else {
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
    public func reloadContactsIfNecessary() {
    }

    /**
     Synchronize device's Address Book and app's contact store.

     - parameters:
        - context: Managed object context to use.
        - completion: Code to execute on method completion.
     */
    private func reloadContacts(using context: NSManagedObjectContext, completion: (_ deletedIDs: Set<String>?, _ error: Error?) -> Void) {
        context.retainsRegisteredObjects = true

        let startTime = Date()
        let contactsAvailable = self.contactsAvailable

        let allContactsRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
        allContactsRequest.returnsObjectsAsFaults = false

        // Harvest all the WAAddressBookContact objects from the store in one fetch.
        // As we process device contacts, from this set we'll subtract contacts
        // that are still present on device.
        var contactsToDelete: [ABContact]
        do {
            try contactsToDelete = context.fetch(allContactsRequest)
            print("contacts/reload/fetch-existing count=[\(contactsToDelete.count)]")
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
            print("contacts/reload/fetch-identifiers count=[\(allContactIdentifiers.count)]")
        } catch {
            print("contacts/reload/fetch-identifiers/failed error=[\(error)]")
            completion(nil, error)
            return
        }
        var identifiersToContactsMap: [String: [ABContact]] = [:]
        if contactsAvailable && !allContactIdentifiers.isEmpty {
            let allIdentifiers = Set(allContactIdentifiers)
            let allContactsWithIdentifiers = contactsToDelete.filter { allIdentifiers.contains($0.identifier!)}
            identifiersToContactsMap = Dictionary(grouping: allContactsWithIdentifiers) { $0.identifier! }
        }

        print("contacts/reload/all-fetches-done time=[\(Date().timeIntervalSince(startTime))]")

        // This will contain the up-to-date set of all address book contacts.
        var allContacts: [ABContact] = []
        // Track which userIDs were really deleted.
        var deletedUserIDs: Set<String> = Set(), existingUserIDs: Set<String> = Set()
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
                existingUserIDs.formUnion(contacts.compactMap{ $0.userId })
            }
        } catch {
            print("Failed to fetch device contacts: \(error)")
            completion(nil, error)
            return
        }
        print("contacts/reload/finished time=[\(Date().timeIntervalSince(startTime))]")

        ///TODO: re-sort contacts

        autoreleasepool {
            print("contacts/reload/will-delete count=[\(contactsToDelete.count)]")
            // We do not need to worry about recently added contacts because contactsToDelete was
            // derived from a snapshot of all the WAAddressBookContact objects in our db prior to fetching all the
            // address book records.
            for contactToDelete in contactsToDelete {
                print("contacts/reload/will-delete id=[\(String(describing: contactToDelete.identifier))] phone=[\(String(describing: contactToDelete.phoneNumber))] userid=[\(String(describing: contactToDelete.userId))]")
                if let userId = contactToDelete.userId {
                    deletedUserIDs.insert(userId)
                }
                context.delete(contactToDelete)
            }
        }

        // If phone number was deleted in one contact, but is still present in another, we should not report it as deleted to the server.
        deletedUserIDs.subtract(existingUserIDs)

        print("contacts/reload/will-save time=[\(Date().timeIntervalSince(startTime))]")
        do {
            try context.save()
            print("contacts/reload/did-save time=[\(Date().timeIntervalSince(startTime))]")
        } catch {
            print("contacts/reload/save-error error=[\(error)]")
        }

        print("contacts/reload/finish time=[\(Date().timeIntervalSince(startTime))]")

        DispatchQueue.main.async {
            if (!self.contactsAvailable) {
                self.contactsAvailable = true
                self.mutateDatabaseMetadata{ metadata in
                    metadata[ContactStoreMetadataContactsLoaded] = true
                }
            }
            ///TODO: send to server
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
        print("contacts/reload/create-new id=[%@]", contactProxy.identifier)
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
                print("skip-duplicate [no phone]")
            } else {
                if !contactKey.isEmpty {
                    uniqueContactKeys.insert(contactKey)
                }
                if existingContacts.isEmpty || !phoneToContactMap.isEmpty {
                    // existingContacts.isEmpty: New contact without phone numbers.
                    // !phoneToContactMap.isEmpty: All phone numbers from contact got deleted.
                    let contact = self.addNewContact(from: contactProxy, into: context)
                    contact.status = ABContactStatus.invalid.rawValue
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
                print("skip-duplicate [\(phoneProxy.phoneNumber):\(contactProxy.fullName.prefix(3))]")
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
}
