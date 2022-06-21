//
//  NoiseRegistrationService.swift
//  Core
//
//  Created by Garrett on 8/23/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

typealias RegisterResponseHandler = (Result<Server_RegisterResponse, Error>) -> Void

enum NoiseRegistrationError: Error {
    case requestError
    case responseError
    case timeout
}

public final class NoiseRegistrationService: RegistrationService {
    public init(
        noiseKeys: NoiseKeys,
        userAgent: String = AppContextCommon.userAgent,
        hostName: String = "s.halloapp.net",
        port: UInt16 = 5208,
        httpHostName: String = "api.halloapp.net")
    {
        self.noiseKeys = noiseKeys
        self.userAgent = userAgent
        self.hostName = hostName
        self.port = port
        self.httpHostName = httpHostName
    }

    public func requestHashcashChallenge(countryCode: String?, completion: @escaping (Result<String, Error>) -> Void) {
        var hashcash = Server_HashcashRequest()
        if let countryCode = countryCode {
            hashcash.countryCode = countryCode
        }

        var request = Server_RegisterRequest()
        request.hashcashRequest = hashcash

        enqueue(request) { result in
            switch result {
            case .success(let response):
                let challenge = response.hashcashResponse.hashcashChallenge
                DispatchQueue.main.async {
                    completion(.success(challenge))
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    public func requestVerificationCode(for phoneNumber: String, byVoice: Bool, hashcash: HashcashSolution?, groupInviteToken: String?, locale: Locale, completion: @escaping (Result<RegistrationResponse, RegistrationErrorResponse>) -> Void)
    {
        var otpRequest = Server_OtpRequest()
        otpRequest.phone = phoneNumber
        otpRequest.method = byVoice ? .voiceCall : .sms
        otpRequest.userAgent = userAgent
        if let hashcash = hashcash {
            otpRequest.hashcashSolution = hashcash.solution
            otpRequest.hashcashSolutionTimeTakenMs = Int64(hashcash.timeTaken * 1000)
        }
        if let groupInviteToken = groupInviteToken {
            otpRequest.groupInviteToken = groupInviteToken
        }
        if let langID = locale.halloServiceLangID {
            otpRequest.langID = langID
        }

        var request = Server_RegisterRequest()
        request.request = .otpRequest(otpRequest)

        enqueue(request) { result in
            switch result {
            case .success(let response):
                switch response.response {
                case .otpResponse(let otpResponse):
                    switch otpResponse.result {
                    case .success:
                        let registrationResponse = RegistrationResponse(
                            normalizedPhoneNumber: otpResponse.phone,
                            retryDelay: TimeInterval(otpResponse.retryAfterSecs))
                        DispatchQueue.main.async {
                            completion(.success(registrationResponse))
                        }
                    case .failure, .unknownResult, .UNRECOGNIZED:
                        let error = VerificationCodeRequestError.error(with: otpResponse.reason)

                        if otpResponse.retryAfterSecs > 0 {
                            let retryDelay = TimeInterval(otpResponse.retryAfterSecs)
                            completion(.failure(RegistrationErrorResponse(error: VerificationCodeRequestError.retriedTooSoon, retryDelay: retryDelay)))
                        } else {
                            DispatchQueue.main.async {
                                completion(.failure(RegistrationErrorResponse(error: error)))
                            }
                        }
                    }
                case .hashcashResponse, .verifyResponse, .none:
                    DispatchQueue.main.async {
                        completion(.failure(RegistrationErrorResponse(error: VerificationCodeRequestError.malformedResponse)))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(RegistrationErrorResponse(error: error)))
                }
            }
        }
    }

    public func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, groupInviteToken: String?, pushOS: String?, pushToken: String?, whisperKeys: WhisperKeyBundle, completion: @escaping (Result<Credentials, Error>) -> Void)
    {
        guard let phraseData = "HALLO".data(using: .utf8),
              let signedPhrase = noiseKeys.sign(phraseData) else
        {
            completion(.failure(VerificationCodeValidationError.phraseSigningError))
            return
        }
        guard let identityKeyData = try? whisperKeys.protoIdentityKey.serializedData(),
              let signedKeyData = try? whisperKeys.protoSignedPreKey.serializedData() else
        {
            completion(.failure(VerificationCodeValidationError.keyGenerationError))
            return
        }
        let oneTimeKeyData = whisperKeys.oneTime.compactMap { try? $0.protoOneTimePreKey.serializedData() }

        var verifyRequest = Server_VerifyOtpRequest()
        verifyRequest.code = verificationCode
        verifyRequest.name = name
        verifyRequest.phone = normalizedPhoneNumber
        verifyRequest.signedPhrase = signedPhrase
        verifyRequest.signedKey = signedKeyData
        verifyRequest.identityKey = identityKeyData
        verifyRequest.oneTimeKeys = oneTimeKeyData
        verifyRequest.staticKey = noiseKeys.publicEdKey
        verifyRequest.userAgent = userAgent

        if let groupInviteToken = groupInviteToken {
            verifyRequest.groupInviteToken = groupInviteToken
        }

        if let pushToken = pushToken {
            var token = Server_PushToken()
            token.token = pushToken
            #if DEBUG
            token.tokenType = .iosDev
            #else
            token.tokenType = pushOS == "ios_appclip" ? .iosAppclip : .ios
            #endif

            var register = Server_PushRegister()
            register.pushToken = token
            if let langID = Locale.current.halloServiceLangID {
                register.langID = langID
            }
            verifyRequest.pushRegister = register
        }

        var request = Server_RegisterRequest()
        request.request = .verifyRequest(verifyRequest)

        enqueue(request) { result in
            switch result {
            case .success(let response):
                switch response.response {
                case .verifyResponse(let verifyResponse):
                    switch verifyResponse.result {
                    case .success:
                        let credentials = Credentials.v2(
                            userID: String(verifyResponse.uid),
                            noiseKeys: noiseKeys)
                        DispatchQueue.main.async {
                            completion(.success(credentials))
                        }
                    case .failure, .unknownResult, .UNRECOGNIZED:
                        let error = VerificationCodeValidationError.error(with: verifyResponse.reason)
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                case .hashcashResponse, .otpResponse, .none:
                    DispatchQueue.main.async {
                        completion(.failure(VerificationCodeRequestError.malformedResponse))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    public func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void) {
        let json: [String : Any] = [
            "group_invite_token" : groupInviteToken
        ]

        let url = URL(string: "https://\(httpHostName)/api/registration/get_group_info")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: json, options: [])
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        DDLogInfo("reg/get-group-info/begin url=[\(request.url!)]  data=[\(json)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                DDLogError("reg/get-group-info/error [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            guard let data = data else {
                DDLogError("reg/get-group-info/error Data is empty.")
                DispatchQueue.main.async {
                    completion(.failure(GetGroupNameError.malformedResponse))
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/get-group-info/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    completion(.failure(GetGroupNameError.malformedResponse))
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                DDLogError("reg/get-group-info/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    completion(.failure(GetGroupNameError.malformedResponse))
                }
                return
            }

            DDLogInfo("reg/get-group-info/finished  status=[\(httpResponse.statusCode)]  response=[\(response)]")

            if let errorString = response["error"] as? String {
                let error = GetGroupNameError(rawValue: errorString) ?? .malformedResponse
                DDLogInfo("reg/get-group-info/error [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            if let groupName = response["name"] as? String {
                DDLogInfo("reg/get-group-info/Name= \(groupName)")
                DispatchQueue.main.async {
                    completion(.success(groupName))
                }
            } else {
                //Group not found
                completion(.success(nil))
            }
        }
        task.resume()
    }

    // MARK: Private

    private let userAgent: String
    private let noiseKeys: NoiseKeys
    private let hostName: String
    private let port: UInt16
    private let httpHostName: String

    private var requestQueue = [(Server_RegisterRequest, RegisterResponseHandler?)]()
    private var activeResponseHandler: RegisterResponseHandler?
    private var timeoutHandlerTask: DispatchWorkItem?

    private var connectionState = ConnectionState.notConnected

    private func enqueue(_ request: Server_RegisterRequest, completion: RegisterResponseHandler?) {
        requestQueue.append((request, completion))
        sendNextRequestWhenReady()
    }

    private func sendNextRequestWhenReady() {
        guard let (request, completion) = requestQueue.first else {
            DDLogInfo("NoiseRegistration/sendNext/aborting [nothing to send]")
            return
        }
        switch connectionState {
        case .connected:
            guard activeResponseHandler == nil else {
                DDLogInfo("NoiseRegistration/sendNext/aborting [waiting for response]")
                return
            }
            requestQueue.removeFirst()
            send(request, completion: completion)
        case .connecting:
            // Just wait (next request will be executed once connected)
            break
        case .disconnecting, .notConnected:
            // Leave request in queue, it will be included with handshake
            noiseStream.connect(host: hostName, port: port)
        }
    }

    /// Actually send request. Assumes stream is connected and ready (i.e., not waiting for a response)
    private func send(_ request: Server_RegisterRequest, completion: RegisterResponseHandler?) {
        guard let requestData = try? request.serializedData() else {
            completion?(.failure(NoiseRegistrationError.requestError))
            return
        }

        activeResponseHandler = completion
        noiseStream.send(requestData)
        let timeoutHandler = DispatchWorkItem { [weak self] in
            self?.activeResponseHandler?(.failure(NoiseRegistrationError.timeout))
            self?.activeResponseHandler = nil
            self?.noiseStream.disconnect()
            self?.sendNextRequestWhenReady()
        }

        let ttl: TimeInterval = 10
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl, execute: timeoutHandler)
        timeoutHandlerTask = timeoutHandler
    }

    private lazy var noiseStream: NoiseStream = {
        return NoiseStream(
            noiseKeys: noiseKeys,
            serverStaticKey: nil,
            delegate: self)
    }()
}

extension NoiseRegistrationService: NoiseDelegate {
    public func receivedPacketData(_ packetData: Data) {
        guard let response = try? Server_RegisterResponse(serializedData: packetData) else {
            DDLogError("proto/received/error could not deserialize packet [\(packetData.base64EncodedString())]")
            return
        }
        timeoutHandlerTask?.cancel()
        activeResponseHandler?(.success(response))
        activeResponseHandler = nil
        sendNextRequestWhenReady()
    }

    public func connectionPayload() -> Data? {
        guard let (request, _) = requestQueue.first else {
            return nil
        }
        return try? request.serializedData()
    }

    public func receivedConnectionResponse(_ responseData: Data) -> Bool {
        guard let (_, completion) = requestQueue.first else {
            DDLogError("NoiseRegistration/receivedConnectionResponse/error [no-handler]")
            return false
        }

        guard let response = try? Server_RegisterResponse(serializedData: responseData) else {
            completion?(.failure(NoiseRegistrationError.responseError))
            return false
        }
        requestQueue.removeFirst()
        timeoutHandlerTask?.cancel()

        completion?(.success(response))
        return true
    }

    public func updateConnectionState(_ connectionState: ConnectionState) {
        self.connectionState = connectionState
        if connectionState == .connected {
            sendNextRequestWhenReady()
        }
    }

    public func receivedServerStaticKey(_ key: Data) {
        // no-op
    }
}

private extension VerificationCodeRequestError {
    static func error(with reason: Server_OtpResponse.Reason) -> VerificationCodeRequestError {
        switch reason {
        case .invalidPhoneNumber:
            return .invalidPhoneNumber
        case .invalidClientVersion:
            return .invalidClientVersion
        case .otpFail:
            return .smsFailure
        case .notInvited:
            return .notInvited
        case .retriedTooSoon:
            return .retriedTooSoon
        case .invalidGroupInviteToken, .badRequest, .badMethod:
            return .requestCreationError
        case .internalServerError, .unknownReason, .UNRECOGNIZED:
            return .malformedResponse
        case .invalidHashcashNonce:
            return .requestCreationError
        case .wrongHashcashSolution:
            return .requestCreationError
        case .invalidCountryCode, .invalidLength, .lineTypeVoip, .lineTypeFixed, .lineTypeOther:
            // TODO: show better error responses to the user.
            return .invalidPhoneNumber
        }
    }
}

private extension VerificationCodeValidationError {
    static func error(with reason: Server_VerifyOtpResponse.Reason) -> VerificationCodeValidationError {
        switch reason {
        case .invalidPhoneNumber:
            return .invalidPhoneNumber
        case .invalidClientVersion:
            return .invalidClientVersion
        case .wrongSmsCode:
            return .incorrectCode
        case .missingPhone:
            return .missingPhone
        case .missingCode:
            return .missingCode
        case .missingName:
            return .missingName
        case .invalidName:
            return .invalidName
        case .unableToOpenSignedPhrase:
            return .signedPhraseError
        case .missingIdentityKey,
             .missingSignedKey,
             .missingOneTimeKeys,
             .badBase64Key,
             .invalidOneTimeKeys,
             .tooFewOneTimeKeys,
             .tooManyOneTimeKeys,
             .tooBigIdentityKey,
             .tooBigSignedKey,
             .tooBigOneTimeKeys,
             .invalidSEdPub,
             .invalidSignedPhrase,
             .badRequest:
            return .badRequest
        case .internalServerError, .unknownReason, .UNRECOGNIZED:
            return .malformedResponse
        case .invalidCountryCode, .invalidLength, .lineTypeVoip, .lineTypeFixed, .lineTypeOther:
            // TODO: show better error responses to the user.
            return .invalidPhoneNumber
        }
    }
}
