//
//  RegistrationService.swift
//  Core
//
//  Created by Garrett on 10/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CryptoKit
import Sodium

public protocol RegistrationService {
    func requestVerificationCode(for phoneNumber: String, byVoice: Bool, groupInviteToken: String?, locale: Locale, completion: @escaping (Result<RegistrationResponse, Error>) -> Void)
    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, groupInviteToken: String?, pushOS: String?, whisperKeys: WhisperKeyBundle, completion: @escaping (Result<Credentials, Error>) -> Void)
    func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void)
}

public struct RegistrationResponse {
    var normalizedPhoneNumber: String
    var retryDelay: TimeInterval
}

public final class DefaultRegistrationService: RegistrationService {
    public init(hostName: String = "api.halloapp.net", userAgent: String = AppContext.userAgent) {
        self.hostName = hostName
        self.userAgent = userAgent
    }

    private let userAgent: String
    private let hostName: String

    // MARK: Verification code requests

    public func requestVerificationCode(for phoneNumber: String, byVoice: Bool, groupInviteToken: String? = nil, locale: Locale, completion: @escaping (Result<RegistrationResponse, Error>) -> Void) {

        var json: [String : String] = [
            "phone": phoneNumber,
            "method": byVoice ? "voice_call" : "sms",
        ]
        if let langID = locale.halloServiceLangID {
            json["lang_id"] = langID
        }
        if let groupToken = groupInviteToken {
            json["group_invite_token"] = groupToken
        }

        guard let url = URL(string: "https://\(hostName)/api/registration/request_otp"),
              let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []) else
        {
            completion(.failure(VerificationCodeRequestError.requestCreationError))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        DDLogInfo("reg/request-sms/begin url=[\(request.url!)]  phone=[\(phoneNumber)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                DDLogError("reg/request-sms/error [\(error)]")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DDLogError("reg/request-sms/error Data is empty.")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeRequestError.malformedResponse))
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeRequestError.malformedResponse))
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DDLogError("reg/request-sms/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeRequestError.malformedResponse))
                }
                return
            }

            DDLogInfo("reg/request-sms/http-response  status=[\(httpResponse.statusCode)]  response=[\(response)]")

            if let errorString = response["error"] as? String {
                let error = VerificationCodeRequestError(rawValue: errorString) ?? .malformedResponse
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let normalizedPhoneNumber = response["phone"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeRequestError.malformedResponse))
                }
                return
            }

            guard let retryDelay = response["retry_after_secs"] as? TimeInterval else {
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeRequestError.malformedResponse))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success(RegistrationResponse(normalizedPhoneNumber: normalizedPhoneNumber, retryDelay: retryDelay)))
            }
        }
        task.resume()
    }

    public func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, groupInviteToken: String?, pushOS: String?, whisperKeys: WhisperKeyBundle, completion: @escaping (Result<Credentials, Error>) -> Void) {

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

        var json: [String : Any] = [
            "name": name,
            "phone": normalizedPhoneNumber,
            "code": verificationCode,
            "s_ed_pub": noiseKeys.publicEdKey.base64EncodedString(),
            "signed_phrase": signedPhrase.base64EncodedString(),
            "identity_key": identityKeyData.base64EncodedString(),
            "signed_key": signedKeyData.base64EncodedString(),
            "one_time_keys": oneTimeKeyData.map { $0.base64EncodedString() },
        ]
        
        // Populate optional values
        if groupInviteToken != nil {
            json["group_invite_token"] = groupInviteToken
        }
        if let pushToken = UserDefaults.standard.string(forKey: "apnsPushToken") {
            json["push_token"] = pushToken
        }
        if pushOS != nil {
            json["push_os"] = groupInviteToken
        }

        let url = URL(string: "https://\(hostName)/api/registration/register2")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: json, options: [])
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        DDLogInfo("reg/validate-code/begin url=[\(request.url!)]  data=[\(json)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                DDLogError("reg/validate-code/error [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            guard let data = data else {
                DDLogError("reg/validate-code/error Data is empty.")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeValidationError.malformedResponse))
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/validate-code/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeValidationError.malformedResponse))
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                DDLogError("reg/validate-code/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeValidationError.malformedResponse))
                }
                return
            }

            DDLogInfo("reg/validate-code/finished  status=[\(httpResponse.statusCode)]  response=[\(response)]")

            if let errorString = response["error"] as? String {
                let error = VerificationCodeValidationError(rawValue: errorString) ?? .malformedResponse
                DDLogInfo("reg/validate-code/invalid [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let userID = response["uid"] as? String else {
                DDLogInfo("reg/validate-code/invalid Missing userId")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeValidationError.malformedResponse))
                }
                return
            }

            if let groupInviteResult = response["group_invite_result"] as? String {
                DDLogInfo("reg/validate-code/groupInviteResult= \(groupInviteResult)")
            }
            DDLogInfo("reg/validate-code/success [noise]")

            DispatchQueue.main.async {
                completion(.success(.v2(userID: userID, noiseKeys: noiseKeys)))
            }

        }
        task.resume()
    }

    public func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void) {
        let json: [String : Any] = [
            "group_invite_token" : groupInviteToken
        ]

        let url = URL(string: "https://\(hostName)/api/registration/get_group_info")!

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
}

public enum VerificationCodeRequestError: String, Error, RawRepresentable {
    case notInvited = "not_invited"
    case smsFailure = "sms_fail"
    case invalidClientVersion = "invalid_client_version"    // client version has expired.
    case requestCreationError
    case malformedResponse // everything else
}

public enum GetGroupNameError: String, Error, RawRepresentable {
    case invalidClientVersion = "invalid_client_version"    // client version has expired.
    case malformedResponse // everything else
}

public enum VerificationCodeValidationError: String, Error, RawRepresentable {
    case incorrectCode = "wrong_sms_code"                   // The sms code provided does not match
    case missingPhone = "missing_phone"                     // Request is missing phone field
    case missingCode = "missing_code"                       // Request is missing code field
    case missingName = "missing_name"                       // Request is missing name field
    case invalidName = "invalid_name"                       // Invalid name in the request
    case badRequest = "bad_request"                         // Could be several reasons, one is UserAgent does not follow the HalloApp.
    case signedPhraseError = "unable_to_open_signed_phrase" // Server unable to read signed phrase
    case invalidClientVersion = "invalid_client_version"    // client version has expired.
    case phraseSigningError                                 // Error signing key phrase
    case keyGenerationError                                 // Unable to generate keys
    case malformedResponse                                  // Everything else
}

public enum NoiseKeyUpdateError: String, Error, RawRepresentable {
    case phraseSigningError
    case requestCreationError
    case invalidKey = "invalid_s_ed_pub"
    case invalidPassword = "invalid_password"
    case signedPhraseError = "unable_to_open_signed_phrase"
    case invalidSignedPhrase = "invalid_signed_phrase"
    case malformedResponse                                  // Everything else
}
