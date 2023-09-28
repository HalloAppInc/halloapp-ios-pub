//
//  UserData+Updates.swift
//  Core
//
//  Created by Tanveer on 8/8/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreCommon

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
