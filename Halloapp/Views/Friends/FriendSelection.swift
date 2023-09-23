//
//  FriendSelection.swift
//  HalloApp
//
//  Created by Tanveer on 9/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Core
import CoreCommon

protocol DisplayableFriend: Hashable, Identifiable {
    var id: UserID { get }
    var name: String { get }
    var username: String { get }
}

protocol DisplayableFriendSection: Identifiable {
    associatedtype Friend: DisplayableFriend

    var title: String? { get }
    var friends: [Friend] { get }
}

protocol SelectionModel: ObservableObject {
    associatedtype Section: DisplayableFriendSection
    typealias Friend = Section.Friend

    var title: String { get }
    var selected: [Friend] { get }
    var candidates: [Section] { get }

    func update(selection: Set<UserID>)
}

// MARK: - FriendSelectionList

struct FriendSelection<Model: SelectionModel>: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject var model: Model

    @State private var editMode = EditMode.inactive
    @State private var selection = Set<UserID>()
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            List(selection: $selection) {
                let selected = filter(friends: model.selected)
                Section {
                    ForEach(selected) { friend in
                        row(for: friend)
                    }
                } header: {
                    if !selected.isEmpty {
                        Text(model.title)
                    }
                }

                ForEach(model.candidates) { section in
                    let friends = filter(friends: section.friends)
                    let shouldShow = editMode.isEditing && !friends.isEmpty

                    Section {
                        if shouldShow {
                            ForEach(friends) { friend in
                                row(for: friend)
                            }
                        }
                    } header: {
                        if shouldShow, let title = section.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .removeListBackground()
            .background {
                Color.feedBackground
                    .ignoresSafeArea(.all)
            }
            .transaction {
                $0.animation = nil
            }
            .searchable(text: $searchText)
            .navigationTitle(Text(model.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Localizations.closeTitle) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { editMode in
                if editMode.isEditing {
                    selection = Set(model.selected.map { $0.id })
                } else {
                    model.update(selection: selection)
                }
            }
            .onAppear {
                if model.selected.isEmpty {
                    // setting the edit mode without the dispatch causes a table view crash on iOS 15
                    DispatchQueue.main.async { editMode = .active }
                }
            }
        }
        .tint(.primaryBlue)
    }

    private func row(for friend: Model.Friend) -> some View {
        HStack {
            Avatar(userID: friend.id, store: MainAppContext.shared.avatarStore)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .scaledFont(ofSize: 17)
                if !friend.username.isEmpty {
                    Text("@\(friend.username)")
                        .scaledFont(ofSize: 12)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Color.feedPostBackground)
        .listRowInsets(.init(top: 8, leading: 11, bottom: 8, trailing: 11))
    }

    private func filter(friends: [Model.Friend]) -> [Model.Friend] {
        guard !searchText.isEmpty, searchText.count > 1 else {
            return friends
        }

        return friends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(searchText) ||
            friend.username.localizedCaseInsensitiveContains(searchText)
        }
    }
}

fileprivate extension View {

    func removeListBackground() -> some View {
        if #available(iOS 16, *) {
            return self.scrollContentBackground(.hidden)
        } else {
            return self
        }
    }
}

// MARK: - FriendSelectionViewController

class FriendSelectionViewController<Model: SelectionModel>: UIHostingController<FriendSelection<Model>> {

    init(model: @autoclosure @escaping () -> Model) {
        if #unavailable(iOS 16) {
            // lists in iOS 15 are backed by UITableView
            UITableView.appearance(whenContainedInInstancesOf: [FriendSelectionViewController.self]).backgroundColor = .clear
        }

        super.init(rootView: FriendSelection(model: model()))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}

// MARK: - Localization

extension Localizations {

    static var closeTitle: String {
        NSLocalizedString("close.title",
                          value: "Close",
                          comment: "Title of a button to close a screen.")
    }
}
