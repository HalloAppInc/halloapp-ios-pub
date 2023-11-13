//
//  UserData+Updates.swift
//  Core
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift

extension UserData {

    public enum UsernameAvailability {
        case available
        case unavailable(reason: ChangeUsernameError)
    }

    public func checkUsernameAvailability(username: String) async throws -> UsernameAvailability {
        do {
            try validate(username: username)
        } catch {
            let error = error as? ChangeUsernameError ?? .other
            return .unavailable(reason: error)
        }

        return try await withCheckedThrowingContinuation { continuation in
            AppContext.shared.coreService.checkUsernameAvailability(username: username) { result in
                switch result {
                case .success(let response):
                    switch response.result {
                    case .ok:
                        continuation.resume(returning: .available)
                    case .fail:
                        continuation.resume(returning: .unavailable(reason: .init(serverReason: response.reason)))
                    case .UNRECOGNIZED:
                        continuation.resume(throwing: NSError(domain: "Invalid response", code: 1))
                    }

                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func set(username: String) async throws {
        try validate(username: username)

        try await withCheckedThrowingContinuation { continuation in
            AppContext.shared.coreService.updateUsername(username: username) { result in
                switch result {
                case .success(let response):
                    switch response.result {
                    case .ok:
                        continuation.resume()
                    case .fail:
                        continuation.resume(throwing: ChangeUsernameError(serverReason: response.reason))
                    case .UNRECOGNIZED:
                        continuation.resume(throwing: NSError(domain: "Could not set username", code: 1))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        await MainActor.run {
            let userData = AppContext.shared.userData
            userData.username = username
            userData.save(using: userData.viewContext)
        }
    }

    private func validate(username: String) throws {
        if let first = username.first?.unicodeScalars.first, !CharacterSet.usernameLowercaseLetters.contains(first) {
            throw ChangeUsernameError.invalidStartingCharacter
        }

        if username.rangeOfCharacter(from: .username.inverted) != nil {
            throw ChangeUsernameError.invalidCharacters
        }
    }

    // MARK: Links

    public func add(link: ProfileLink) async throws {
        try await withCheckedThrowingContinuation { continuation in
            AppContext.shared.coreService.addProfileLink(type: link.serverLink.type, text: link.string) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        await MainActor.run {
            let userData = AppContext.shared.userData
            userData.links += [link]
            userData.save(using: userData.viewContext)
        }
    }

    public func remove(link: ProfileLink) async throws {
        try await withCheckedThrowingContinuation { continuation in
            AppContext.shared.coreService.removeProfileLink(type: link.serverLink.type, text: link.string) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        await MainActor.run {
            let userData = AppContext.shared.userData
            userData.links = userData.links.filter { $0 != link }
            userData.save(using: userData.viewContext)
        }
    }

    public func update(links: [ProfileLink]) async throws {
        let pendingLinks = Set(links)
        let existingLinks = await MainActor.run { Set(AppContext.shared.userData.links) }
        let forRemoval = existingLinks.subtracting(pendingLinks)
        let forAdd = pendingLinks.subtracting(existingLinks)
        DDLogInfo("UserData/update-links/removing [\(forRemoval.count)] adding [\(forAdd.count)]")

        let removed = await withTaskGroup(of: ProfileLink?.self) { group in
            for link in forRemoval {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        AppContext.shared.coreService.removeProfileLink(type: link.serverLink.type, text: link.string) { result in
                            continuation.resume(returning: (try? result.get()).flatMap { _ in link })
                        }
                    }
                }
            }
            return await group
                .compactMap { $0 }
                .reduce(into: []) { $0.append($1) }
        }

        let added = await withTaskGroup(of: ProfileLink?.self) { group in
            for link in forAdd {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        AppContext.shared.coreService.addProfileLink(type: link.serverLink.type, text: link.string) { result in
                            continuation.resume(returning: (try? result.get()).flatMap { _ in link })
                        }
                    }
                }
            }
            return await group
                .compactMap { $0 }
                .reduce(into: []) { $0.append($1) }
        }

        DDLogInfo("UserData/update-links/removed [\(removed.count)] added [\(added.count)]")
        await MainActor.run {
            let removedSet = Set(removed)
            let updatedLinks = existingLinks.filter { !removedSet.contains($0) } + added
            let userData = AppContext.shared.userData

            userData.links = updatedLinks
            userData.save(using: userData.viewContext)
        }

        if added.count != forAdd.count || removed.count != forRemoval.count {
            throw NSError(domain: "Batch link update error", code: 1)
        }
    }
}

// MARK: - ChangeUsernameError

public enum ChangeUsernameError: LocalizedError {

    case tooShort
    case tooLong
    case invalidCharacters
    case invalidStartingCharacter
    case alreadyTaken
    case other

    public init(serverReason: Server_UsernameResponse.Reason) {
        switch serverReason {
        case .tooshort:
            self = .tooShort
        case .toolong:
            self = .tooLong
        case .badexpr:
            self = .invalidCharacters
        case .notuniq:
            self = .alreadyTaken
        case .UNRECOGNIZED(_):
            self = .other
        }
    }

    public var errorDescription: String? {
        switch self {
        case .tooShort:
            return NSLocalizedString("username.too.short.error",
                                     value: "Username Too Short",
                                     comment: "Displayed when trying to set a username with too few characters.")
        case .tooLong:
            return NSLocalizedString("username.too.long.error",
                                     value: "Username Too Long",
                                     comment: "Displayed when trying to set a username with too many characters.")
        case .invalidCharacters:
            return NSLocalizedString("username.invalid.characters.error",
                                     value: "Username has Invalid Characters",
                                     comment: "Displayed when trying to set a username with invalid characters.")
        case .invalidStartingCharacter:
            return NSLocalizedString("username.invalid.starting.character.error",
                                     value: "Invalid Starting Character",
                                     comment: "Displayed when trying to set a username with an invalid starting character.")
        case .alreadyTaken:
            return NSLocalizedString("username.taken.error",
                                     value: "Sorry, @%@ is Taken 🥲",
                                     comment: "Displayed when the user tries to claim a username that is already taken.")
        case .other:
            return NSLocalizedString("username.unknown.error",
                                     value: "An Error Occurred",
                                     comment: "Displayed when an unknown error occurred while setting a username.")
        }
    }
}

// MARK: - CharacterSet extension

fileprivate extension CharacterSet {

    static var username: Self {
        CharacterSet(charactersIn: "_.")
            .union(usernameLowercaseLetters)
            .union(usernameDigits)
    }

    static var usernameLowercaseLetters: Self {
        CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
    }

    static var usernameDigits: Self {
        CharacterSet(charactersIn: "0123456789")
    }
}
