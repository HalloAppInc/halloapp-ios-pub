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

class ProtoGetInviteAllowanceRequest: ProtoStandardRequest<(Int, Date)> {
    init(completion: @escaping ServiceRequestCompletion<(Int, Date)>) {
        super.init(
            packet: Server_Packet.iqPacket(type: .get, payload: .invitesRequest(Server_InvitesRequest())),
            transform: { response in
                let invites = Int(response.iq.invitesResponse.invitesLeft)
                let timeUntilRefresh = TimeInterval(response.iq.invitesResponse.timeUntilRefresh)
                return .success((invites, Date(timeIntervalSinceNow: timeUntilRefresh))) },
            completion: completion)
    }
}

class ProtoRegisterInvitesRequest: ProtoStandardRequest<InviteResponse> {
    init(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>) {
        var request = Server_InvitesRequest()
        request.invites = phoneNumbers.map {
            var invite = Server_Invite()
            invite.phone = $0
            return invite
        }

        super.init(
            packet: Server_Packet.iqPacket(type: .set, payload: .invitesRequest(request)),
            transform: { response in
                let invitesResponse = response.iq.invitesResponse
                let invitesLeft = Int(invitesResponse.invitesLeft)
                let timeUntilRefresh = TimeInterval(invitesResponse.timeUntilRefresh)
                let results: [String: InviteResult] = Dictionary(uniqueKeysWithValues:
                    invitesResponse.invites.compactMap {
                        switch $0.result {
                        case "ok":
                            return ($0.phone, .success)
                        case "failed":
                            let reason = InviteResult.FailureReason(rawValue: $0.reason) ?? .unknown
                            return ($0.phone, .failure(reason))
                        default:
                            DDLogError("ProtoRegisterInvitesRequest/error unexpected result string [\($0.result)]")
                            return nil
                        }
                    }
                )
                return .success((results: results, count: invitesLeft, refreshDate: Date(timeIntervalSinceNow: timeUntilRefresh))) },
            completion: completion)
    }
}
