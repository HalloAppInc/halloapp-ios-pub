//
//  XMPPStreamProtoBuf.swift
//  Core
//
//  Created by Alan Luo on 8/3/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

public final class ProtoStream: XMPPStream {

    override init() {
        super.init()
        isProtoBufProtocol = true
    }

    /**
     This is a temporary solution. I can't get access to multicastDelegate in XMPPStream,
     so I use protoService here to get access to the delegate.
     */
    public weak var protoService: ProtoServiceCore?

    /// Send ProtoBuf serialized data
    /// This method overrides the parent method and adds 4 bytes to the front of the data.
    /// The first byte is always 0, and the next 3 bytes are the size of the payload.
    /// More details here: https://github.com/HalloAppInc/server/blob/master/doc/update_protocol.md#note
    ///
    /// - Parameter data: ProtoBuf serialized data
    public override func send(_ data: Data) {
        let length = Int32(data.count)
        var finalData = Data()

        // The first byte should always be 0, and the next 3 bytes are the size of the payload.
        // Since it is almost impossible to have a payload larger than 16777215 (the maximum unsigned 3 bytes number),
        // I just use the 4 bytes of a Int32 number.
        withUnsafeBytes(of: length.bigEndian) { finalData.append(contentsOf: $0) }
        finalData.append(data)

        super.send(finalData)
    }

    /// Originally, XMPPStream should start to read data when it is negotiating with the server.
    /// The new protocol skipped the negotiation procedure, so I have to tell the socket to start to read data
    /// as soon as a secured connection has been established.
    public override func socketDidSecure(_ sock: GCDAsyncSocket) {
        super.socketDidSecure(sock)

        state = XMPPStreamState.STATE_XMPP_STARTTLS_2

        asyncSocket.readData(withTimeout: -1, tag: 100)
    }


    /// Originally, XMPPStream will receive the data and use an XMPPParser to parse the data.
    /// I tried to write an XMPPParser to deserialize the data to ProtoBuf, but I encountered two issues:
    /// 1.  XMPPStream expects XMPPParser to return NSXMLElement, which is different from ProtoBuf.
    /// 2. The ProtoBuf library in Objective-C is difficult to use. It has some issues with ARC.
    /// In the end, I decided to override this method and handle all the deserialization in Swift.
    /// This method will take the received data,
    /// remove the first four bytes (like the data we send out, the 1st byte is always 0, and the next 3 bytes are the size of the payload),
    /// and let handleAuth or handlePacket to process them.
    public override func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {

        var offset = 0
        while offset < data.count {

            // The socket may have read multiple proto packets. Split them up using 4-byte length headers.
            let lengthData = Data(bytes: Array(data.bytes[offset..<data.count]), count: 4)
            let length = Int(UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self)}))
            let packetMax = min(data.count, offset+length+4)
            let packetData = data.subdata(in: (offset+4)..<packetMax)
            offset += length + 4

            if (state == XMPPStreamState.STATE_XMPP_AUTH) {
                handleAuth(data: packetData)
            } else {
                handlePacket(data: packetData)
            }
        }

        asyncSocket.readData(withTimeout: -1, tag: 101)
    }

    /// XMPPStream supports authentication mechanisms that confront to XMPPSASLAuthentication.
    /// Again, XMPPSASLAuthentication only supports NSXMLElement.
    /// I added this method to send auth request directly.
    /// Similiar to `authenticateWithPassword:error:`, this method sends out an authentication request using AuthRequest.
    /// - Parameter password: the password
    public func sendAuthRequestWithPassword(password: String) {
        var authRequest = PBauth_request()

        if let myJID = myJID, let uid = Int64(myJID.user ?? ""), let resource = myJID.resource {
            authRequest.uid = uid
            authRequest.resource = resource
        }

        authRequest.pwd = password
        authRequest.cm.mode = passiveMode ? .passive : .active
        authRequest.cv.version = clientVersion as String

        let data = try! authRequest.serializedData()
        send(data)

        state = XMPPStreamState.STATE_XMPP_AUTH
    }


    /// Handle the authentication result.
    /// - Parameter data: A serialized data of the ProtoBuf AuthResult
    func handleAuth(data: Data) {
        do {
            let authResult = try PBauth_result(serializedData: data)

            if authResult.result == "success" {
                isAuthenticated = true
                state = XMPPStreamState.STATE_XMPP_CONNECTED

                DispatchQueue.main.async {
                    self.protoService?.xmppStreamDidAuthenticate(self)
                }
            } else {
                state = XMPPStreamState.STATE_XMPP_DISCONNECTED
                protoService?.authenticationFailed()
            }
        } catch {
            DDLogError("ProtoStream/handleAuth/error could not deserialize packet")
        }
    }

    /// Handle all packets except AuthResult, which will be handled by handleAuth.
    /// - Parameter data: A serialized data of the ProtoBuf Packet
    func handlePacket(data: Data) {
        do {
            let packet = try PBpacket(serializedData: data)

            if let requestID = packet.requestID {
                protoService?.didReceive(packet: packet, requestID: requestID)
            }
        } catch {
            DDLogError("ProtoStream/handlePacket/error could not deserialize packet")
        }
    }


    /// Block the old way to send request.
    /// A wrong request will cause the server to disconnect.
    public override func send(_ element: DDXMLElement) {
        DDLogError("ProtoStream/send/error attempted to send xml: \(element.compactXMLString())")
    }
}

public extension PBpacket {
    static func iqPacketWithID() -> PBpacket {
        var packet = PBpacket()
        packet.iq.id = XMPPIQ.generateUniqueIdentifier()
        return packet
    }

    static func iqPacket(type: PBha_iq.TypeEnum, payload: PBiq_payload.OneOf_Content) -> PBpacket {
        var packet = PBpacket.iqPacketWithID()
        packet.iq.type = type
        packet.iq.payload.content = payload
        return packet
    }

    static func msgPacket(
        from: UserID,
        to: UserID,
        id: String = UUID().uuidString,
        type: PBha_message.TypeEnum = .normal,
        payload: PBmsg_payload.OneOf_Content) -> PBpacket
    {
        var msg = PBha_message()

        if let fromUID = Int64(from) {
            msg.fromUid = fromUID
        } else {
            DDLogError("PBpacket/\(id)/error invalid from user ID \(from)")
        }

        if let toUID = Int64(to) {
            msg.toUid = toUID
        } else {
            DDLogError("PBpacket/\(id)/error invalid to user ID \(to)")
        }

        msg.type = type
        msg.id = id
        msg.payload.content = payload

        var packet = PBpacket()
        packet.msg = msg

        return packet
    }
    
    var requestID: String? {
        guard let stanza = stanza else {
            return nil
        }
        switch stanza {
        case .msg(let msg):
            return msg.id
        case .iq(let iq):
            return iq.id
        case .ack(let ack):
            return ack.id
        case .presence(let presence):
            return presence.id
        case .chatState:
            // TODO: do we need an ID here for anything?
            return nil
        case .error:
            return nil
        }
    }
}
