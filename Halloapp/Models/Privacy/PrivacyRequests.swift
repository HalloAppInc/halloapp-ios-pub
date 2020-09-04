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

    init?(xmppElement: XMLElement) {
        assert(xmppElement.name == XMPPConstants.listElement)

        guard let type = PrivacyListType(rawValue: xmppElement.attributeStringValue(forName: XMPPConstants.typeAttribute) ?? "") else {
            DDLogError("privacy/list/xmpp Invalid list type:\n\(xmppElement)")
            return nil
        }
        let userIds: [UserID] = xmppElement.elements(forName: XMPPConstants.itemElement).compactMap { (itemElement) in
            guard let userId = itemElement.stringValue, !userId.isEmpty else {
                DDLogError("privacy/list/xmpp Invalid list entry:\n\(itemElement)")
                return nil
            }
            return userId
        }
        self.init(type: type, userIds: userIds)
    }

}

class XMPPSendPrivacyListRequest: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init<T>(privacyList: T, completion: @escaping XMPPRequestCompletion) where T: PrivacyListProtocol, T: XMPPElementRepresentable {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(privacyList.xmppElement)
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        completion(.success(()))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

class XMPPGetPrivacyListsRequest: XMPPRequest {

    typealias XMPPGetPrivacyListsRequestCompletion = (Result<([PrivacyListProtocol], PrivacyListType), Error>) -> Void

    private let completion: XMPPGetPrivacyListsRequestCompletion

    init(_ listTypes: [PrivacyListType], completion: @escaping XMPPGetPrivacyListsRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let listsElement = XMPPElement(name: XMPPConstants.listsElement, xmlns: XMPPConstants.xmlns)
            for listType in listTypes {
                listsElement.addChild({
                    let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
                    listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: listType.rawValue)
                    return listElement
                    }())
            }
            return listsElement
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        guard let listsElement = response.childElement, listsElement.name == XMPPConstants.listsElement else {
            completion(.failure(XMPPError.malformed))
            return
        }
        guard let activeType = PrivacyListType(rawValue: listsElement.attributeStringValue(forName: XMPPConstants.activeTypeAttribute) ?? ""),
              activeType == .all || activeType == .whitelist || activeType == .blacklist else {
            // "active_type" not set or incorrect
            completion(.failure(XMPPError.malformed))
            return
        }
        let privacyLists = listsElement.elements(forName: XMPPConstants.listElement).compactMap({ XMPPPrivacyList(xmppElement: $0) })
        completion(.success((privacyLists, activeType)))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

extension PrivacyList: XMPPElementRepresentable {

    public var xmppElement: XMPPElement {
        get {
            let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
            listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: type.rawValue)
            listElement.addAttribute(withName: XMPPConstants.hashAttribute, stringValue: hash)
            for item in items {
                if item.state == .added || item.state == .deleted {
                    let itemElement = XMPPElement(name: XMPPConstants.itemElement, stringValue: item.userId)
                    itemElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: item.state.rawValue)
                    listElement.addChild(itemElement)
                }
            }
            return listElement
        }
    }
}

extension PrivacyListAllContacts: XMPPElementRepresentable {

    var xmppElement: XMPPElement {
        get {
            let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
            listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: type.rawValue)
            return listElement
        }
    }
}

class ProtoGetPrivacyListsRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>

    init(listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>) {
        self.completion = completion

        var privacyLists = PBprivacy_lists()
        privacyLists.lists = listTypes.map { listType in
            var list = PBprivacy_list()
            list.type = .init(listType)
            return list
        }

        let packet = PBpacket.iqPacket(type: .get, payload: .privacyLists(privacyLists))

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {

        let pbPrivacyLists = response.iq.payload.privacyLists
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

class ProtoSendPrivacyListRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<Void>

    init(privacyList: PrivacyList, completion: @escaping ServiceRequestCompletion<Void>) {
        self.completion = completion

        var list = PBprivacy_list()
        list.type = PBprivacy_list.TypeEnum(privacyList.type)
        list.uidElements = privacyList.items.compactMap { item in
            guard let uid = Int64(item.userId) else {
                DDLogError("ProtoSendPrivacyListRequest/error invalid userID \(item.userId)")
                return nil
            }
            var element = PBuid_element()
            element.uid = uid
            switch item.state {
            case .added:
                element.action = .add
            case .deleted:
                element.action = .delete
            default:
                return nil
            }
            return element
        }

        let packet = PBpacket.iqPacket(type: .set, payload: .privacyList(list))
        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        completion(.success(()))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

extension PBuid_element.Action {
    var privacyListItemState: PrivacyListItem.State? {
        switch self {
        case .add: return .added
        case .delete: return .deleted
        case .UNRECOGNIZED: return nil
        }
    }
}

extension PBprivacy_list.TypeEnum {
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
