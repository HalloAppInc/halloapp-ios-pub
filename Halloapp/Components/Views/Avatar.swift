//
//  Avatar.swift
//  HalloApp
//
//  Created by Tanveer on 9/14/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import CoreCommon

struct Avatar: View {

    private let userID: UserID
    private let store: AvatarStore
    private let avatar: UserAvatar

    @State private var image: UIImage?

    init(userID: UserID, store: AvatarStore) {
        self.userID = userID
        self.store = store
        self.avatar = store.userAvatar(forUserId: userID)
    }

    var body: some View {
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
}
