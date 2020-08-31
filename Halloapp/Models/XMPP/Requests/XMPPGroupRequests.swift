//
//  XMPPGroupRequests.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

class XMPPGroupCreateRequest : XMPPRequest {
    typealias XMPPGroupRequestCompletion = (XMLElement?, Error?) -> Void
    let completion: XMPPGroupRequestCompletion

    init(name: String, members: [UserID], completion: @escaping XMPPGroupRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "s.halloapp.net"))
                
        iq.addChild({
            let group = XMLElement(name: "group", xmlns: "halloapp:groups")
            group.addAttribute(withName: "action", stringValue: "create")
            group.addAttribute(withName: "name", stringValue: name)
            
            for memberId in members {
                let memberEl = XMLElement(name: "member")
                memberEl.addAttribute(withName: "uid", stringValue: memberId)
                group.addChild(memberEl)
            }
            
            return group
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}


class XMPPGroupGetInfoRequest : XMPPRequest {
    typealias XMPPGroupRequestCompletion = (XMLElement?, Error?) -> Void
    let completion: XMPPGroupRequestCompletion

    init(groupId: GroupID, completion: @escaping XMPPGroupRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: "s.halloapp.net"))
                
        iq.addChild({
            let group = XMLElement(name: "group", xmlns: "halloapp:groups")
            group.addAttribute(withName: "gid", stringValue: groupId)
            group.addAttribute(withName: "action", stringValue: "get")
            return group
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}

class XMPPGroupLeaveRequest : XMPPRequest {
    typealias XMPPGroupRequestCompletion = (XMLElement?, Error?) -> Void
    let completion: XMPPGroupRequestCompletion

    init(groupId: GroupID, completion: @escaping XMPPGroupRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "s.halloapp.net"))
                
        iq.addChild({
            let group = XMLElement(name: "group", xmlns: "halloapp:groups")
            group.addAttribute(withName: "gid", stringValue: groupId)
            group.addAttribute(withName: "action", stringValue: "leave")
            return group
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}


class XMPPGroupModifyMembersRequest : XMPPRequest {
    typealias XMPPGroupRequestCompletion = (XMLElement?, Error?) -> Void
    let completion: XMPPGroupRequestCompletion

    init(groupId: GroupID, members: [UserID], action: ChatGroupMemberAction, completion: @escaping XMPPGroupRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "s.halloapp.net"))
                
        iq.addChild({
            let group = XMLElement(name: "group", xmlns: "halloapp:groups")
            group.addAttribute(withName: "gid", stringValue: groupId)
            group.addAttribute(withName: "action", stringValue: "modify_members")

            for memberId in members {
                let memberEl = XMLElement(name: "member")
                memberEl.addAttribute(withName: "uid", stringValue: memberId)
                memberEl.addAttribute(withName: "action", stringValue: action.rawValue)
                group.addChild(memberEl)
            }
            
            return group
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}
