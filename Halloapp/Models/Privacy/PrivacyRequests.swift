//
//  PrivacyRequests.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import XMPPFramework

fileprivate struct XMPPConstants {
    static let xmlns = "halloapp:user:privacy"

    // Element names
    static let listsElement = "privacy_lists"
    static let listElement = "privacy_list"
    static let itemElement = "uid"

    // Attribute names
    static let typeAttribute = "type"
    static let hashAttribute = "hash"
    static let activeTypeAttribute = "active_type"
}

typealias HalloPrivacyList = XMPPPrivacyList

struct XMPPPrivacyList: PrivacyListProtocol {
    let type: PrivacyListType
    let userIds: [UserID]

    init(type: PrivacyListType, userIds: [UserID]) {
        self.type = type
        self.userIds = userIds
    }
}

class ProtoGetPrivacyListsRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>

    init(listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>) {
        self.completion = completion

        var privacyLists = Server_PrivacyLists()
        privacyLists.lists = listTypes.map { listType in
            var list = Server_PrivacyList()
            list.type = .init(listType)
            return list
        }

        let packet = Server_Packet.iqPacket(type: .get, payload: .privacyLists(privacyLists))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: Server_Packet) {

        let pbPrivacyLists = response.iq.privacyLists
        let lists: [PrivacyListProtocol] = pbPrivacyLists.lists.compactMap { pbList in
            guard let listType = pbList.type.privacyListType else {
                DDLogError("ProtoGetPrivacyListsRequest/didFinish/error unknown list type \(pbList.type)")
                return nil
            }
            return HalloPrivacyList(type: listType, userIds: pbList.uidElements.map { UserID($0.uid) })
        }
        let activeType: PrivacyListType? = {
            switch pbPrivacyLists.activeType {
            case .all:
                return .all
            case .block:
                return .blocked
            case .except:
                return .blacklist
            case .UNRECOGNIZED:
                return nil
            }
        }()

        if let activeType = activeType {
            completion(.success((lists, activeType)))
        } else {
            DDLogError("ProtoGetPrivacyListsRequest/didFinish/error unknown active type")
            completion(.failure(ProtoServiceError.unexpectedResponseFormat))
        }
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

class ProtoUpdatePrivacyListRequest: ProtoStandardRequest<Void> {
    init(update: PrivacyListUpdateProtocol, completion: @escaping ServiceRequestCompletion<Void>) {

        var list = Server_PrivacyList()
        list.type = Server_PrivacyList.TypeEnum(update.type)
        list.uidElements = update.updates.compactMap { (userID, action) in
            guard let uid = Int64(userID) else {
                DDLogError("ProtoUpdatePrivacyListRequest/error invalid userID \(userID)")
                return nil
            }
            var element = Server_UidElement()
            element.uid = uid
            element.action = {
                switch action {
                case .add: return .add
                case .delete: return .delete
                }
            }()
            return element
        }

        super.init(
            packet: Server_Packet.iqPacket(type: .set, payload: .privacyList(list)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

extension Server_UidElement.Action {
    var privacyListItemState: PrivacyListItem.State? {
        switch self {
        case .add: return .added
        case .delete: return .deleted
        case .UNRECOGNIZED: return nil
        }
    }
}

extension Server_PrivacyList.TypeEnum {
    init(_ privacyListType: PrivacyListType) {
        switch privacyListType {
        case .all: self = .all
        case .whitelist: self = .only
        case .blacklist: self = .except
        case .muted: self = .mute
        case .blocked: self = .block
        }
    }

    var privacyListType: PrivacyListType? {
        switch self {
        case .all: return .all
        case .block: return .blocked
        case .except: return .blacklist
        case .only: return .whitelist
        case .mute: return .muted
        case .UNRECOGNIZED: return nil
        }
    }
}
