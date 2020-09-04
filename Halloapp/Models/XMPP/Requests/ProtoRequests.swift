//
//  ProtoRequests.swift
//  HalloApp
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

final class ProtoUpdateAvatarRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<String?>

    init(data: Data?, completion: @escaping ServiceRequestCompletion<String?>) {
        self.completion = completion

        var uploadAvatar = PBupload_avatar()
        if let data = data {
            uploadAvatar.data = data
        }

        let packet = PBpacket.iqPacket(type: .set, payload: .uploadAvatar(uploadAvatar))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with packet: PBpacket) {
        let avatarID = packet.iq.payload.avatar.id
        completion(.success(avatarID))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

final class ProtoPushTokenRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Void>

    init(token: String, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var pushToken = PBpush_token()
        pushToken.token = token

        var pushRegister = PBpush_register()
        pushRegister.pushToken = pushToken

        let packet = PBpacket.iqPacket(type: .set, payload: .pushRegister(pushRegister))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

final class ProtoRetractItemRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Void>

    init(feedItem: FeedItemProtocol, feedOwnerId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var pbFeedItem = PBfeed_item()
        pbFeedItem.item = feedItem.protoFeedItem(withData: false)
        pbFeedItem.action = .retract

        let packet = PBpacket.iqPacket(type: .set, payload: .feedItem(pbFeedItem))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

final class ProtoContactSyncRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<[HalloContact]>

    init<T: Sequence>(
        with contacts: T,
        type: ContactSyncRequestType,
        syncID: String,
        batchIndex: Int? = nil,
        isLastBatch: Bool? = nil,
        completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T.Iterator.Element == HalloContact
    {
        self.completion = completion

        var contactList = PBcontact_list()
        contactList.type = {
            switch type {
            case .full:
                return .full
            case .delta:
                return .delta
            }
        }()
        contactList.syncID = syncID
        if let batchIndex = batchIndex {
            contactList.batchIndex = Int32(batchIndex)
        }
        if let isLastBatch = isLastBatch {
            contactList.isLast = isLastBatch
        }
        contactList.contacts = contacts.map { contact in
            var pbContact = PBcontact()
            pbContact.action = contact.isDeletedContact ? .delete : .add
            if let raw = contact.raw { pbContact.raw = raw }
            if let normalized = contact.normalized { pbContact.normalized = normalized }
            if let userID = contact.userid, let numericID = Int64(userID) { pbContact.uid = numericID }
            return pbContact
        }

        let packet = PBpacket.iqPacket(type: .set, payload: .contactList(contactList))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        let contacts = response.iq.payload.contactList.contacts
        self.completion(.success(contacts.compactMap { HalloContact($0) }))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

final class ProtoPresenceSubscribeRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Void>

    init(userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var presence = PBha_presence()
        presence.id = UUID().uuidString
        presence.type = .subscribe
        if let uid = Int64(userID) {
            presence.uid = uid
        }

        var packet = PBpacket()
        packet.presence = presence

        super.init(packet: packet, id: packet.presence.id)
    }

    override func didFinish(with response: PBpacket) {
        completion(.success(()))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

final class ProtoPresenceUpdate: ProtoRequest {
    private let completion: ServiceRequestCompletion<Void>

    init(status: PresenceType, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var presence = PBha_presence()
        presence.id = UUID().uuidString
        presence.type = {
            switch status {
            case .away:
                return .away
            case .available:
                return .available
            }
        }()
        if let uid = Int64(AppContext.shared.userData.userId) {
            presence.uid = uid
        }

        var packet = PBpacket()
        packet.presence = presence

        super.init(packet: packet, id: packet.presence.id)
    }

    override func didFinish(with response: PBpacket) {
        completion(.success(()))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

final class ProtoSendReceipt: ProtoRequest {
    let completion: ServiceRequestCompletion<Void>

    init(
        itemID: String,
        thread: HalloReceipt.Thread,
        type: HalloReceipt.`Type`,
        fromUserID: UserID,
        toUserID: UserID,
        completion: @escaping ServiceRequestCompletion<Void>)
    {
        self.completion = completion

        let payloadContent: PBmsg_payload.OneOf_Content = {
            switch type {
            case .delivery:
                var receipt = PBdelivery_receipt()
                receipt.id = itemID
                if case .group(let threadID) = thread {
                    receipt.threadID = threadID
                }
                return .delivery(receipt)
            case .read:
                var receipt = PBseen_receipt()
                receipt.id = itemID
                if case .group(let threadID) = thread {
                    receipt.threadID = threadID
                }
                return .seen(receipt)
            }
        }()

        var packet = PBpacket()
        packet.msg.payload.content = payloadContent

        super.init(packet: packet, id: packet.msg.id)
    }
}

class ProtoSendNameRequest: ProtoRequest {
    private let completion: ServiceRequestCompletion<Void>

    init(name: String, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion
        var pbName = PBname()
        pbName.name = name

        let packet = PBpacket.iqPacket(type: .set, payload: .name(pbName))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}
