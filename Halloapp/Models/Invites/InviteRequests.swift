//
//  XMPPInviteRequests.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import XMPPFramework

fileprivate struct XMPPConstants {
    static let xmlns = "halloapp:invites"

    struct Elements {
        static let invites = "invites"
        static let invite = "invite"
    }

    struct Attributes {
        static let invitesLeft = "invites_left"
        static let timeUntilRefresh = "time_until_refresh"

        static let phone = "phone"
        static let result = "result"
        static let reason = "reason"
    }
}

typealias InviteResponse = (results: [String: InviteResult], count: Int, refreshDate: Date)

enum InviteResult {
    enum FailureReason: String {
        case invalidNumber = "invalid_number"
        case noInvitesLeft = "no_invites_left"
        case existingUser = "existing_user"
        case unknown
    }

    case success
    case failure(FailureReason)
}

class XMPPGetInviteAllowanceRequest: XMPPRequest {

    typealias XMPPGetInviteAllowanceRequestCompletion = (Result<(Int, Date), Error>) -> Void

    private let completion: XMPPGetInviteAllowanceRequestCompletion

    init(completion: @escaping XMPPGetInviteAllowanceRequestCompletion) {
        self.completion = completion
        let invitesElement = XMPPElement(name: XMPPConstants.Elements.invites, xmlns: XMPPConstants.xmlns)
        super.init(iq: XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo), child: invitesElement))
    }

    override func didFinish(with response: XMPPIQ) {
        guard let invitesElement = response.childElement, invitesElement.name == XMPPConstants.Elements.invites else {
            completion(.failure(XMPPError.malformed))
            return
        }
        let invitesLeft = invitesElement.attributeIntegerValue(forName: XMPPConstants.Attributes.invitesLeft)
        let timeUntilRefresh = invitesElement.attributeDoubleValue(forName: XMPPConstants.Attributes.timeUntilRefresh)
        completion(.success((invitesLeft, Date(timeIntervalSinceNow: timeUntilRefresh))))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
}

class XMPPRegisterInvitesRequest: XMPPRequest {

    typealias XMPPRegisterInvitesRequestCompletion = (Result<InviteResponse, Error>) -> Void

    private let completion: XMPPRegisterInvitesRequestCompletion

    init(phoneNumbers: [String], completion: @escaping XMPPRegisterInvitesRequestCompletion) {
        self.completion = completion
        let invitesElement = XMPPElement(name: XMPPConstants.Elements.invites, xmlns: XMPPConstants.xmlns)
        for phoneNumber in phoneNumbers {
            invitesElement.addChild({
                let invite = XMPPElement(name: XMPPConstants.Elements.invite)
                invite.addAttribute(withName: XMPPConstants.Attributes.phone, stringValue: phoneNumber)
                return invite
                }())
        }
        super.init(iq: XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo), child: invitesElement))
    }

    override func didFinish(with response: XMPPIQ) {
        guard let invitesElement = response.childElement, invitesElement.name == XMPPConstants.Elements.invites else {
            completion(.failure(XMPPError.malformed))
            return
        }
        let invitesLeft = invitesElement.attributeIntegerValue(forName: XMPPConstants.Attributes.invitesLeft)
        let timeUntilRefresh = invitesElement.attributeDoubleValue(forName: XMPPConstants.Attributes.timeUntilRefresh)
        var results = [String: InviteResult]()
        for inviteElement in invitesElement.elements(forName: XMPPConstants.Elements.invite) {
            guard let phoneNumber = inviteElement.attributeStringValue(forName: XMPPConstants.Attributes.phone),
                let resultStr = inviteElement.attributeStringValue(forName: XMPPConstants.Attributes.result) else {
                    continue
            }
            switch resultStr {
            case "ok":
                results[phoneNumber] = .success
            case "failed":
                let failureReason = inviteElement.attributeStringValue(forName: XMPPConstants.Attributes.reason) ?? ""
                results[phoneNumber] = .failure(InviteResult.FailureReason(rawValue: failureReason) ?? InviteResult.FailureReason.unknown)
            default:
                break
            }
        }
        completion(.success((results, invitesLeft, Date(timeIntervalSinceNow: timeUntilRefresh))))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }

}

class ProtoGetInviteAllowanceRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<(Int, Date)>

    init(completion: @escaping ServiceRequestCompletion<(Int, Date)>) {
        self.completion = completion

        // TODO (waiting for schema)
        let packet = PBpacket.iqPacketWithID()

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        completion(.failure(ProtoServiceError.unimplemented))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }
    
}


class ProtoRegisterInvitesRequest: ProtoRequest {

    private let completion: ServiceRequestCompletion<InviteResponse>

    init(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>) {
        self.completion = completion

        // TODO (waiting for schema)
        let packet = PBpacket.iqPacketWithID()

        super.init(packet: packet, id: packet.iq.id)
    }

    override func didFinish(with response: PBpacket) {
        completion(.failure(ProtoServiceError.unimplemented))
    }

    override func didFail(with error: Error) {
        completion(.failure(error))
    }

}
