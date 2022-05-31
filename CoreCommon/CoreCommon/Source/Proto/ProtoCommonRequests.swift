//
//  ProtoCommonRequests.swift
//  Core
//
//  Created by Garrett on 8/28/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Foundation

public final class ProtoGetServerPropertiesRequest: ProtoRequest<ServerPropertiesResponse> {

    public init(completion: @escaping Completion) {
        super.init(
            iqPacket: .iqPacket(type: .get, payload: .props(Server_Props())),
            transform: { (iq) in
                let version = iq.props.hash.toHexString()
                let properties: [String: String] = Dictionary(
                    uniqueKeysWithValues: iq.props.props.map { ($0.name, $0.value) }
                )
                return .success((version: version, properties: properties))
            },
            completion: completion)
    }
}

public final class ProtoLoggingRequest: ProtoRequest<Void> {

    public init(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping Completion) {
        var clientLog = Server_ClientLog()
        clientLog.counts = countableEvents.map { event in
            var count = Server_Count()
            count.namespace = event.namespace
            count.metric = event.metric
            count.count = Int64(event.count)
            count.dims = event.dimensions.map { (name, value) in
                var dim = Server_Dim()
                dim.name = name
                dim.value = value
                return dim
            }
            return count
        }
        clientLog.events = discreteEvents.map { $0.eventData }

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .clientLog(clientLog)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoSendNameRequest: ProtoRequest<Void> {

    public init(name: String, completion: @escaping Completion) {
        var serverName = Server_Name()
        serverName.name = name

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .name(serverName)),
            transform: { _ in .success(()) },
            completion: completion)
    }
}

public final class ProtoGroupPreviewWithLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    public init(inviteLink: String, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.action = .preview
        groupInviteLink.link = inviteLink

        super.init(
            iqPacket: .iqPacket(type: .get, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}

public final class ProtoJoinGroupWithLinkRequest: ProtoRequest<Server_GroupInviteLink> {

    public init(inviteLink: String, completion: @escaping Completion) {
        var groupInviteLink = Server_GroupInviteLink()
        groupInviteLink.action = .join
        groupInviteLink.link = inviteLink

        super.init(
            iqPacket: .iqPacket(type: .set, payload: .groupInviteLink(groupInviteLink)),
            transform: { (iq) in
                return .success(iq.groupInviteLink) },
            completion: completion)
    }
}

private extension DiscreteEvent {
    var eventData: Server_EventData {
        var eventData = Server_EventData()
        eventData.edata = eData
        eventData.platform = .ios
        eventData.version = AppContextCommon.appVersionForService
        return eventData
    }

    private var eData: Server_EventData.OneOf_Edata {
        switch self {
        case .mediaUpload(let postID, let duration, let numPhotos, let numVideos, let totalSize, let status):
            var upload = Server_MediaUpload()
            upload.id = postID
            upload.durationMs = UInt32(duration * 1000)
            upload.numPhotos = UInt32(numPhotos)
            upload.numVideos = UInt32(numVideos)
            upload.totalSize = UInt32(totalSize)
            upload.status = status == .ok ? .ok : .fail
            return .mediaUpload(upload)

        case .mediaDownload(let postID, let duration, let numPhotos, let numVideos, let totalSize):
            var download = Server_MediaDownload()
            download.id = postID
            download.durationMs = UInt32(duration * 1000)
            download.numPhotos = UInt32(numPhotos)
            download.numVideos = UInt32(numVideos)
            download.totalSize = UInt32(totalSize)
            return .mediaDownload(download)

        case .pushReceived(let id, let timestamp):
            var push = Server_PushReceived()
            push.id = id
            push.clientTimestamp = UInt64(timestamp.timeIntervalSince1970)
            return .pushReceived(push)

        case .decryptionReport(let id, let contentType, let result, let clientVersion, let sender, let rerequestCount, let timeTaken, let isSilent):
            var report = Server_DecryptionReport()
            report.msgID = id
            if result == "success" {
                report.result = .ok
            } else {
                report.result = .fail
                report.reason = result
            }
            report.originalVersion = clientVersion
            report.senderVersion = sender.version
            report.senderPlatform = sender.platform.serverPlatform
            report.rerequestCount = UInt32(rerequestCount)
            report.timeTakenS = UInt32(timeTaken)
            report.isSilent = isSilent
            switch contentType {
            case .chat:
                report.contentType = .chat
            case .groupHistory:
                report.contentType = .groupHistory
            }
            return .decryptionReport(report)

        case .groupDecryptionReport(let id, let gid, let contentType, let error, let clientVersion, let sender, let rerequestCount, let timeTaken):
            var report = Server_GroupDecryptionReport()
            // This is contentID
            report.contentID = id
            report.gid = gid
            switch contentType {
            case .post:
                report.itemType = .post
            case .comment:
                report.itemType = .comment
            case .historyResend:
                report.itemType = .historyResend
            }
            if error.isEmpty {
                report.result = .ok
            } else {
                report.result = .fail
                report.reason = error
            }
            report.senderVersion = sender?.version ?? ""
            report.senderPlatform = sender?.platform.serverPlatform ?? Server_Platform.unknown
            report.originalVersion = clientVersion
            report.rerequestCount = UInt32(rerequestCount)
            report.timeTakenS = UInt32(timeTaken)
            // deadline is 1day = 86400seconds, so if timeTaken is beyond that.
            // schedule is result_based.
            if report.timeTakenS > 86400 {
                report.schedule = .resultBased
            } else {
                report.schedule = .daily
            }
            return .groupDecryptionReport(report)

        case .groupHistoryReport(let gid, let numExpected, let numDecrypted, let clientVersion, let rerequestCount, let timeTaken):
            var report = Server_GroupHistoryReport()
            report.gid = gid
            report.numDecrypted = UInt32(numDecrypted)
            report.numExpected = UInt32(numExpected)
            report.originalVersion = clientVersion
            report.rerequestCount = UInt32(rerequestCount)
            report.timeTakenS = UInt32(timeTaken)
            // deadline is 1day = 86400seconds, so if timeTaken is beyond that.
            // schedule is result_based.
            if report.timeTakenS > 86400 {
                report.schedule = .resultBased
            } else {
                report.schedule = .daily
            }
            return .groupHistoryReport(report)

        case .callReport(let id, let peerUserID, let type, let direction, let networkType, let answered, let connected, let duration_ms, let endCallReason, let localEndCall, let webrtcStats):
            var callReport = Server_Call()
            callReport.callID = id
            callReport.peerUid = UInt64(peerUserID) ?? 0
            if type == "audio" {
                callReport.type = .audio
            } else if type == "video" {
                callReport.type = .video
            }
            callReport.direction = direction == "outgoing" ? .outgoing : .incoming
            if networkType == "wifi" {
                callReport.networkType = .wifi
            } else if networkType == "cellular" {
                callReport.networkType = .cellular
            }
            callReport.answered = answered
            callReport.connected = connected
            callReport.durationMs = UInt64(duration_ms)
            callReport.endCallReason = endCallReason
            callReport.localEndCall = localEndCall
            callReport.webrtcStats = webrtcStats
            return .call(callReport)

        case .fabAction(let type):
            var fabAction = Server_FabAction()
            switch type {
            case .gallery:
                fabAction.type = .gallery
            case .audio:
                fabAction.type = .audio
            case .text:
                fabAction.type = .text
            case .camera:
                fabAction.type = .camera
            }
            return .fabAction(fabAction)
        }
    }
}

extension UserAgent.Platform {
    var serverPlatform: Server_Platform {
        switch self {
        case .android: return .android
        case .ios: return .ios
        }
    }
}
