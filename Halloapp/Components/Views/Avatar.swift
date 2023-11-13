//
//  Avatar.swift
//  HalloApp
//
//  Created by Tanveer on 9/14/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import CoreCommon

struct Avatar<MenuContent: View>: View {

    private let store = MainAppContext.shared.avatarStore
    private let userID: UserID
    private let avatar: UserAvatar

    private let content: ((Bool) -> MenuContent)?
    @State private var image: UIImage?

    init(userID: UserID, @ViewBuilder content: @escaping (Bool) -> MenuContent) {
        self.userID = userID
        self.avatar = store.userAvatar(forUserId: userID)
        self.content = content
    }

    var body: some View {
        Menu {
            content?(image != nil)
        } label: {
            Image(uiImage: image ?? UIImage(named: "AvatarUser") ?? .init())
                .resizable()
                .clipShape(Circle())
                .onAppear {
                    avatar.loadThumbnailImage(using: store)
                    image = avatar.image
                }
                .onReceive(avatar.imageDidChange) {
                    image = $0
                }
        }
        .disabled(content == nil)
    }
}

extension Avatar where MenuContent == EmptyView {

    init(userID: UserID) {
        self.userID = userID
        self.avatar = store.userAvatar(forUserId: userID)
        self.content = nil
    }
}
