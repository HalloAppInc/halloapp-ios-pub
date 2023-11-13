//
//  ProfileEditorModel.swift
//  HalloApp
//
//  Created by Tanveer on 10/24/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Foundation
import Combine
import Core
import CoreCommon
import CocoaLumberjackSwift

@MainActor
class ProfileEditorModel: ObservableObject {

    private var cancellables: Set<AnyCancellable> = []
    private var updateTask: Task<Void, Never>?

    // MARK: Bindings

    @Published var name = MainAppContext.shared.userData.name
    @Published var username = MainAppContext.shared.userData.username
    @Published var showError = false
    @Published var showAvatarPicker = false
    @Published var showAvatarViewer = false
    @Published var showDeleteAvatarWarning = false

    // MARK: State

    @Published private(set) var links: [EditableLink] = []
    @Published private(set) var showAddLinkField = true
    @Published private(set) var enableDoneButton = true
    @Published private(set) var errorMessage: String?

    // MARK: Publishers

    private let _addedLink = PassthroughSubject<EditableLink, Never>()
    private let _savedChanges = PassthroughSubject<Void, Never>()

    var addedLink: AnyPublisher<EditableLink, Never> {
        _addedLink.eraseToAnyPublisher()
    }

    var savedChanges: AnyPublisher<Void, Never> {
        _savedChanges.eraseToAnyPublisher()
    }

    let maximumNameLength = 20

    init() {
        links = MainAppContext.shared.userData.links
            .sorted()
            .map { EditableLink(profileLink: $0) }
        links.forEach { subscribe(to: $0) }

        Publishers.CombineLatest3($name, $username, $links)
            .dropFirst()
            .sink { [weak self] in self?.handleEdits(name: $0, username: $1, links: $2) }
            .store(in: &cancellables)

        $links
            .map { $0.count }
            .sink { [weak self] in self?.showAddLinkField = $0 < 4 }
            .store(in: &cancellables)
    }

    // MARK: Actions

    func pushedDone() {
        enableDoneButton = false
        updateTask = Task {
            await update()
        }
    }

    func addLink(type: EditableLink.`Type`) {
        let link = EditableLink(type: type)
        subscribe(to: link)

        links.append(link)
        _addedLink.send(link)
    }

    func update(avatar: PendingMedia) {
        avatar.ready
            .first { $0 }
            .sink { _ in
                guard let image = avatar.image else {
                    return
                }

                let context = MainAppContext.shared
                context.avatarStore.uploadAvatar(image: image,
                                                 for: context.userData.userId,
                                                 using: context.service)
            }
            .store(in: &cancellables)
    }

    func deleteAvatar() {
        DDLogInfo("ProfileEditorModel/deleteAvatar")
        let context = MainAppContext.shared
        let userID = context.userData.userId

        context.avatarStore.removeAvatar(for: userID, using: context.service)
    }

    private func handleEdits(name: String, username: String, links: [EditableLink]) {
        let name = name.trimmingCharacters(in: .whitespaces)
        let username = username.trimmingCharacters(in: .whitespaces)
        let isNameValid = name.count > 2 && name.count <= maximumNameLength
        let isUsernameValid = username.count > 2 && username.count <= maximumNameLength

        if isNameValid, isUsernameValid {
            enableDoneButton = true
        } else {
            enableDoneButton = false
        }
    }

    private func update() async {
        let links = transformAndRemoveDuplicateLinks()
        let userData = MainAppContext.shared.userData
        let updateName = name.trimmingCharacters(in: .whitespaces) != userData.name
        let updateUsername = username.trimmingCharacters(in: .whitespaces) != userData.username
        let updateLinks = links != userData.links

        await withThrowingTaskGroup(of: Void.self) { [name, username, links] group in
            if updateName {
                MainAppContext.shared.service.updateUsername(name)
            }
            if updateUsername {
                group.addTask(priority: .userInitiated) {
                    try await userData.set(username: username)
                }
            }
            if updateLinks {
                group.addTask(priority: .userInitiated) {
                    try await userData.update(links: links)
                }
            }

            do {
                try await group.waitForAll()
                DDLogInfo("ProfileEditorModel/update/success")
                if !Task.isCancelled {
                    _savedChanges.send()
                }
            } catch ChangeUsernameError.alreadyTaken {
                errorMessage = String(format: ChangeUsernameError.alreadyTaken.localizedDescription, username)
                showError = true
            } catch {
                DDLogError("ProfileEditorModel/update/failed with error \(String(describing: error))")
                errorMessage = Localizations.genericError
                showError = true
            }
        }
    }

    // MARK: Helpers

    private func subscribe(to link: EditableLink) {
        link.$isDeleted
            .filter { $0 }
            .sink { [weak self] _ in
                if let self {
                    self.links = self.links.filter { $0 != link }
                }
            }
            .store(in: &cancellables)
    }

    private func transformAndRemoveDuplicateLinks() -> [ProfileLink] {
        var seen = Set<ProfileLink>()
        var updated = [EditableLink]()

        for link in links where !link.isEmpty {
            let profileLink = ProfileLink(editableLink: link)
            if seen.insert(profileLink).inserted {
                updated.append(link)
            }
        }

        links = updated
        return Array(seen)
    }
}
