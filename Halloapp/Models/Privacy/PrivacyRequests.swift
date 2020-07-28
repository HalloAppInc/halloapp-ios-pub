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
    static let activeTypeAttribute = "active_type"
}

class XMPPSendPrivacyListRequest: XMPPRequest {

    private let completion: XMPPRequestCompletion

    init(privacyList: PrivacyList, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild(privacyList.xmppElement)
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPGetPrivacyListsRequest: XMPPRequest {

    typealias XMPPGetPrivacyListsRequestCompletion = (Result<([PrivacyList], PrivacyListType), Error>) -> Void

    private let completion: XMPPGetPrivacyListsRequestCompletion

    init(includeMuted: Bool, completion: @escaping XMPPGetPrivacyListsRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let listsElement = XMPPElement(name: XMPPConstants.listsElement, xmlns: XMPPConstants.xmlns)
            // Omitting list of lists to request results in all lists being returned.
            // To exclude one list from request we must explicitly list all others.
            if !includeMuted {
                listsElement.addChild({
                    let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
                    listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: PrivacyListType.blacklist.rawValue)
                    return listElement
                    }())
                listsElement.addChild({
                    let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
                    listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: PrivacyListType.whitelist.rawValue)
                    return listElement
                    }())
                listsElement.addChild({
                    let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
                    listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: PrivacyListType.blocked.rawValue)
                    return listElement
                    }())
            }
            return listsElement
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        guard let listsElement = response.childElement, listsElement.name == XMPPConstants.listsElement else {
            self.completion(.failure(XMPPError.malformed))
            return
        }
        guard let activeType = PrivacyListType(rawValue: listsElement.attributeStringValue(forName: XMPPConstants.activeTypeAttribute) ?? ""),
              activeType == .all || activeType == .whitelist || activeType == .blacklist else {
            // "active_type" not set or incorrect
            self.completion(.failure(XMPPError.malformed))
            return
        }
        let privacyLists = listsElement.elements(forName: XMPPConstants.listElement).compactMap({ PrivacyList(xmppElement: $0) })
        self.completion(.success((privacyLists, activeType)))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

extension PrivacyList {

    var xmppElement: XMPPElement {
        get {
            let listElement = XMPPElement(name: XMPPConstants.listElement, xmlns: XMPPConstants.xmlns)
            listElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: self.type.rawValue)
            for item in self.items {
                if item.state == .added || item.state == .deleted {
                    let itemElement = XMPPElement(name: XMPPConstants.itemElement, stringValue: item.userId)
                    itemElement.addAttribute(withName: XMPPConstants.typeAttribute, stringValue: item.state.rawValue)
                    listElement.addChild(itemElement)
                }
            }
            return listElement
        }
    }

    convenience init?(xmppElement: XMLElement) {
        assert(xmppElement.name == XMPPConstants.listElement)

        guard let type = PrivacyListType(rawValue: xmppElement.attributeStringValue(forName: XMPPConstants.typeAttribute) ?? "") else {
            DDLogError("privacy/list/xmpp Invalid list type:\n\(xmppElement)")
            return nil
        }
        let items: [PrivacyListItem] = xmppElement.elements(forName: XMPPConstants.itemElement).compactMap { (itemElement) in
            guard let userId = itemElement.stringValue, !userId.isEmpty else {
                DDLogError("privacy/list/xmpp Invalid list entry:\n\(itemElement)")
                return nil
            }
            return PrivacyListItem(userId: userId)
        }
        self.init(type: type, items: items)
    }
}
