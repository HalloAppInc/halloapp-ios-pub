//
//  ProtoRequest.swift
//  Core
//
//  Created by Garrett on 8/26/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack

open class ProtoRequest {
    enum State {
        case ready
        case sending
        case cancelled
        case finished
    }

    internal var state: State = .ready
    internal var retriesRemaining = 0
    private(set) var requestId: String
    internal var packet: PBpacket
    private(set) var response: PBpacket?

    public init(packet: PBpacket, id: String) {
        self.packet = packet
        self.requestId = id
    }

    func send(using service: ProtoServiceCore) {
        guard self.state == .ready else {
            DDLogWarn("protorequest/\(self.requestId)/send: not ready [\(self.state)]")
            return
        }
        DDLogInfo("protorequest/\(self.requestId)/sending")
        self.state = .sending

        do {
            service.stream.send(try packet.serializedData())
        } catch {
            DDLogError("protorequest/\(self.requestId)/error: \(error.localizedDescription)")
        }
    }

    func failOnNoConnection() {
        guard self.state == .sending || self.state == .ready else {
            return
        }
        DDLogWarn("protorequest/\(self.requestId)/failed: not-connected")
        self.state = .cancelled
        self.didFail(with: XMPPError.notConnected)
    }

    func cancelAndPrepareFor(retry willRetry: Bool) -> Bool {
        DDLogError("protorequest/\(self.requestId)/failed/rr=\(self.retriesRemaining)")
        switch (self.state) {
        case .finished, .cancelled:
                return false
        case .ready, .sending:
            if !willRetry || self.retriesRemaining <= 0 {
                self.state = .cancelled
                self.didFail(with: XMPPError.aborted)
                return false
            }
        }

        if self.state == .sending {
            self.retriesRemaining -= 1
            self.state = .ready
        }
        return true
    }

    func process(response: PBpacket) {
        guard self.state == .sending else { return }
        self.state = .finished
        self.response = response
        DDLogDebug("protorequest/\(self.requestId)/response \(response)")
        self.didFinish(with: response)
    }

    open func didFinish(with response: PBpacket) { }

    open func didFail(with error: Error) { }
}
