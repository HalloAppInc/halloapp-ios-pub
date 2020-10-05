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
    internal var packet: Server_Packet
    private(set) var response: Server_Packet?

    public init(packet: Server_Packet, id: String) {
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

    func process(response: Server_Packet) {
        guard self.state == .sending else { return }
        self.state = .finished
        self.response = response
        DDLogDebug("protorequest/\(self.requestId)/response \(response)")
        self.didFinish(with: response)
    }

    open func didFinish(with response: Server_Packet) { }

    open func didFail(with error: Error) { }
}

open class ProtoStandardRequest<T>: ProtoRequest {

    /// Transform response packet into preferred format
    private let transform: (Server_Packet) -> Result<T, Error>

    /// Handle transformed response
    private let completion: ServiceRequestCompletion<T>

    public init(packet: Server_Packet, transform: @escaping (Server_Packet) -> Result<T, Error>, completion: @escaping ServiceRequestCompletion<T> ) {
        self.transform = transform
        self.completion = completion
        super.init(packet: packet, id: packet.requestID ?? UUID().uuidString)
    }

    public override func didFinish(with response: Server_Packet) {
        switch transform(response) {
        case .success(let output):
            completion(.success(output))
        case .failure(let error):
            completion(.failure(error))
        }
    }

    public override func didFail(with error: Error) {
        completion(.failure(error))
    }
}
