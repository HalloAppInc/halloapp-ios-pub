//
//  ProfileEditor.swift
//  HalloApp
//
//  Created by Tanveer on 10/23/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import SwiftUI
import Combine
import CoreCommon

struct ProfileEditor: View {

    private enum Field: Hashable {
        case name
        case username
        case link(EditableLink)
    }

    @Environment(\.dismiss) private var dismiss
    @Namespace private var bottomID

    @StateObject private var model = ProfileEditorModel()
    @FocusState private var focused: Field?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 15) {
                        avatar
                            .frame(width: 150, height: 150)
                            .padding(.vertical, 20)
                        nameTextField
                            .focused($focused, equals: .name)
                            .id(Field.name)
                        usernameTextField
                            .focused($focused, equals: .username)
                            .id(Field.username)

                        ForEach(model.links) { link in
                            LinkField(link: link)
                                .focused($focused, equals: .link(link))
                                .id(Field.link(link))
                        }

                        if model.showAddLinkField {
                            addLinkRow
                        }
                    }
                    .padding([.bottom], 15)
                    .animation(.spring(duration: 0.3), value: model.links.count)
                    .animation(.spring(duration: 0.3), value: model.showAddLinkField)
                    .onChange(of: focused) { focused in
                        switch focused {
                        case .link(let link) where link == model.links.last:
                            withAnimation(.easeOut) {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        default:
                            withAnimation(.easeOut) {
                                proxy.scrollTo(focused)
                            }
                        }
                    }
                    .id(bottomID)
                }
                .background {
                    Color.feedBackground
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(Localizations.editProfile)
            .navigationBarTitleDisplayMode(.inline)
            .alert(model.errorMessage ?? "", isPresented: $model.showError) {
                Button(Localizations.buttonOK) { }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Localizations.closeTitle) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.pushedDone()
                    } label: {
                        Text(Localizations.buttonDone)
                            .bold()
                    }
                    .disabled(!model.enableDoneButton)
                }
            }
            .onReceive(model.addedLink) { link in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focused = .link(link)
                }
            }
            .onReceive(model.savedChanges) {
                dismiss()
            }
        }
    }

    private var avatar: some View {
        Avatar(userID: MainAppContext.shared.userData.userId) { hasAvatar in
            if hasAvatar {
                Button(Localizations.viewPhoto) {
                    model.showAvatarViewer = true
                }
            }

            Button(Localizations.takeOrChoosePhoto) {
                model.showAvatarPicker = true
            }

            if hasAvatar {
                Button(Localizations.deletePhoto, role: .destructive) {
                    model.showDeleteAvatarWarning = true
                }
            }
        }
        .fullScreenCover(isPresented: $model.showAvatarViewer) {
            AvatarViewer(userID: MainAppContext.shared.userData.userId)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $model.showAvatarPicker) {
            AvatarPicker { media in
                model.showAvatarPicker = false
                if let media {
                    model.update(avatar: media)
                }
            }
            .ignoresSafeArea()
        }
        .alert(Localizations.deletePhoto, isPresented: $model.showDeleteAvatarWarning) {
            Button(Localizations.deletePhoto, role: .destructive) {
                model.deleteAvatar()
            }
            Button(Localizations.buttonCancel, role: .cancel) { }
        }
    }

    private var nameTextField: some View {
        HStack {
            TextField(Localizations.nameTitle, text: $model.name)
                .textFieldStyle(.plain)
                .accentColor(.primaryBlue)
                .scaledFont(ofSize: 16)

            Spacer()
            Text("\(model.maximumNameLength - model.name.trimmingCharacters(in: .whitespaces).count)")
                .scaledFont(ofSize: 14)
                .foregroundStyle(.secondary)
        }
        .modifier(FieldStyling())
    }

    private var usernameTextField: some View {
        HStack(spacing: 1) {
            Text("@")
            TextField(Localizations.usernameTitle.lowercased(), text: $model.username)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .accentColor(.primaryBlue)

            Spacer()
            Text("\(model.maximumNameLength - model.username.trimmingCharacters(in: .whitespaces).count)")
                .scaledFont(ofSize: 14)
                .foregroundStyle(.secondary)
        }
        .scaledFont(ofSize: 16)
        .modifier(FieldStyling())
    }

    private var addLinkRow: some View {
        Menu {
            Button { model.addLink(type: .instagram) } label: {
                Label(Localizations.instagramName, image: "InstagramOutline")
            }
            Button { model.addLink(type: .tiktok) } label: {
                Label(Localizations.tiktokName, image: "TikTokOutline")
            }
            Button { model.addLink(type: .twitter) } label: {
                Label(Localizations.twitterName, image: "TwitterOutline")
            }
            Button { model.addLink(type: .youtube) } label: {
                Label(Localizations.youtubeName, image: "YouTubeOutline")
            }
            Button { model.addLink(type: .other) } label: {
                Label(Localizations.linkTitle, systemImage: "link")
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .frame(width: 20, height: 20)
                    .tint(.primaryBlue)
                Text(Localizations.addLink)
                    .scaledFont(ofSize: 16)
                    .tint(.secondary)
                Spacer()
            }
            .modifier(FieldStyling())
        }
    }
}

// MARK: - LinkField

fileprivate struct LinkField: View {

    @StateObject private var link: EditableLink

    init(link: EditableLink) {
        _link = StateObject(wrappedValue: link)
    }

    var body: some View {
        let symbol: Image
        switch link.type {
        case .instagram:
            symbol = Image("InstagramOutline")
        case .tiktok:
            symbol = Image("TikTokOutline")
        case .twitter:
            symbol = Image("TwitterOutline")
        case .youtube:
            symbol = Image("YouTubeOutline")
        case .other:
            symbol = Image(systemName: "link")
        }

        return HStack {
            symbol
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primaryBlue)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            LinkTextField(link: link)
                .accentColor(.primaryBlue)
        }
        .modifier(FieldStyling())
    }
}

// MARK: - FieldStyling

fileprivate struct FieldStyling: ViewModifier {

    func body(content: Content) -> some View {
        content
            .padding(15)
            .background {
                fieldBackground
            }
            .padding(.horizontal, 20)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.feedPostBackground)
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Localization

extension Localizations {

    static var editProfile: String {
        NSLocalizedString("edit.profile",
                          value: "Edit Profile",
                          comment: "Title of a screen that allows editing of profile details.")
    }

    static var addLink: String {
        NSLocalizedString("add.link",
                          value: "add link",
                          comment: "Encourages the user to add a link to another social media platform.")
    }

    static var instagramName: String {
        NSLocalizedString("instagram.name",
                          value: "Instagram",
                          comment: "Refers to the social network Instagram.")
    }

    static var tiktokName: String {
        NSLocalizedString("tiktok.name",
                          value: "TikTok",
                          comment: "Refers to the social network TikTok.")
    }

    static var youtubeName: String {
        NSLocalizedString("youtube.name",
                          value: "YouTube",
                          comment: "Refers to the social network YouTube.")
    }

    static var twitterName: String {
        NSLocalizedString("twitter.name",
                          value: "x.com",
                          comment: "Refers to the social network formerly known as Twitter.")
    }

    static var linkTitle: String {
        NSLocalizedString("link.title",
                          value: "Link",
                          comment: "Refers to a URL.")
    }
}
