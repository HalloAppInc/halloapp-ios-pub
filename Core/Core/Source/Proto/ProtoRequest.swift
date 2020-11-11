//
//  ProtoRequest.swift
//  Core
//
//  Created by Garrett on 8/26/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack

open class ProtoRequestBase {

    enum State {
        case ready
        case sending
        case cancelled
        case finished
    }

    internal var state: State = .ready
    internal var retriesRemaining = 0

    public let requestId: String
    private let request: Server_Packet

    fileprivate init(request: Server_Packet) {
        self.requestId = request.requestID ?? UUID().uuidString
        self.request = request
    }

    func send(using service: ProtoServiceCore) {
        guard state == .ready else {
            DDLogWarn("request/\(Self.self)/\(requestId)/send: not ready [\(state)]")
            return
        }
        DDLogDebug("request/\(Self.self)/\(requestId)/sending \(request)")
        state = .sending

        do {
            service.stream.send(try request.serializedData())
        } catch {
            DDLogError("request/\(Self.self)/\(requestId)/send/error: \(error)")
        }
    }

    func failOnNoConnection() {
        guard state == .sending || state == .ready else {
            return
        }
        DDLogWarn("protorequest/\(requestId)/failed: not-connected")
        state = .cancelled
        DispatchQueue.main.async {
            self.fail(withError: XMPPError.notConnected)
        }
    }

    func cancelAndPrepareFor(retry willRetry: Bool) -> Bool {
        DDLogError("protorequest/\(requestId)/failed/rr=\(retriesRemaining)")
        switch state {
        case .finished, .cancelled:
            return false
        case .ready, .sending:
            if !willRetry || retriesRemaining <= 0 {
                state = .cancelled
                DispatchQueue.main.async {
                    self.fail(withError: XMPPError.aborted)
                }
                return false
            }
        }

        if state == .sending {
            retriesRemaining -= 1
            state = .ready
        }
        return true
    }

    func process(response: Server_Packet) {
        guard state == .sending else { return }
        state = .finished
        DDLogDebug("request/\(Self.self)/\(requestId)/response \(response)")
        DispatchQueue.main.async {
            self.finish(withResponse: response)
        }
    }

    fileprivate func finish(withResponse response: Server_Packet) { }

    fileprivate func fail(withError error: Error) { }
}

open class ProtoRequest<T>: ProtoRequestBase {

    public typealias Completion = ServiceRequestCompletion<T>

    /// Transform response packet into preferred format
    private let transform: (Server_Iq) -> Result<T, Error>

    /// Handle transformed response
    private let completion: Completion

    public init(iqPacket: Server_Packet, transform: @escaping (Server_Iq) -> Result<T, Error>, completion: @escaping Completion) {
        self.transform = transform
        self.completion = completion
        super.init(request: iqPacket)
    }

    fileprivate override func finish(withResponse response: Server_Packet) {
        guard case let .iq(serverIQ) = response.stanza else {
            fail(withError: XMPPError.malformed)
            return
        }
        if case .error = serverIQ.type {
            fail(withError: XMPPError.serverError(serverIQ.errorStanza.reason))
            return
        }

        switch transform(serverIQ) {
        case .success(let output):
            completion(.success(output))
        case .failure(let error):
            fail(withError: error)
        }
    }

    fileprivate override func fail(withError error: Error) {
        DDLogDebug("request/\(Self.self)/\(requestId)/failed \(error)")
        completion(.failure(error))
    }
}
