//
//  EditableLink.swift
//  HalloApp
//
//  Created by Tanveer on 10/24/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import CoreCommon

class EditableLink: ObservableObject, Identifiable, Hashable {

    typealias `Type` = ProfileLink.`Type`

    let id = UUID()
    @Published private(set) var type: `Type`
    @Published private(set) var text: String
    @Published private(set) var usernameRange: NSRange?
    @Published var isDeleted = false

    var username: String? {
        guard let usernameRange, let range = Range(usernameRange, in: text) else {
            return nil
        }
        return String(text[range])
    }

    var isEmpty: Bool {
        if type != .other, username?.isEmpty ?? true {
            return true
        }
        return text.isEmpty
    }

    init(type: `Type`) {
        self.type = type
        self.text = type.base ?? ""

        usernameRange = Self.patterns.first(where: { $0.0 == type })
            .flatMap { _, expression in
                usernameRange(using: expression)
            }
    }

    init(profileLink: ProfileLink) {
        self.type = profileLink.type
        self.text = (profileLink.type.base ?? "") + profileLink.string

        usernameRange = Self.patterns.first(where: { $0.0 == type })
            .flatMap { _, expression in
                usernameRange(using: expression)
            }
    }

    func update(with string: String) {
        text = string
        let range = NSMakeRange(0, string.utf16.count)
        let match: (`Type`, NSRange)? = Self.patterns
            .lazy
            .compactMap { type, expression in
                self.usernameRange(using: expression, range: range).flatMap { range in
                    (type, range)
                }
            }
            .first

        if let match {
            type = match.0
            usernameRange = match.1
        } else {
            type = .other
            usernameRange = nil
        }
    }

    private func usernameRange(using expression: NSRegularExpression, range: NSRange? = nil) -> NSRange? {
        let range = range ?? NSMakeRange(0, text.utf16.count)
        let match = expression.firstMatch(in: text, range: range)?.range(withName: "username")

        if let match, match.location != NSNotFound {
            return match
        }

        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func ==(lhs: EditableLink, rhs: EditableLink) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Expressions

extension EditableLink {

    private static let patterns: [(`Type`, NSRegularExpression)] = {
        let allCases: [`Type`] = [.instagram, .tiktok, .youtube, .twitter]
        return allCases.lazy
            .compactMap { type in
                type.base.flatMap { (type, $0) }
            }
            .compactMap { type, base in
                let regex = (try? NSRegularExpression(pattern: "\\A(?:https?://)?(?:www.)?(\(base))(?<username>[^/]*)/?\\z"))
                return regex.flatMap { (type, $0) }
            }
    }()
}

extension ProfileLink {

    init(editableLink: EditableLink) {
        let text = editableLink.username ?? editableLink.text
        self.init(type: editableLink.type, string: text)
    }
}
