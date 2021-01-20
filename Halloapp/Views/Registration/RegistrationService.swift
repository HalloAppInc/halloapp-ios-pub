//
//  RegistrationService.swift
//  HalloApp
//
//  Created by Garrett on 10/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CryptoKit
import Sodium

protocol RegistrationService {
    func requestVerificationCode(for phoneNumber: String, completion: @escaping (Result<String, Error>) -> Void)
    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, completion: @escaping (Result<Credentials, Error>) -> Void)

    // Temporary (used for Noise migration)
    func updateNoiseKeys(_ noiseKeys: NoiseKeys, userID: UserID, password: String, completion: @escaping (Result<Credentials, Error>) -> Void)
}

final class DefaultRegistrationService: RegistrationService {
    init(hostName: String = "api.halloapp.net", userAgent: String = MainAppContext.userAgent) {
        self.hostName = hostName
        self.userAgent = userAgent
    }

    private let userAgent: String
    private let hostName: String

    // MARK: Verification code requests

    func requestVerificationCode(for phoneNumber: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://\(hostName)/api/registration/request_sms")!)
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["phone": phoneNumber])
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

            DispatchQueue.main.async {
                completion(.success(normalizedPhoneNumber))
            }
        }
        task.resume()
    }

    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, completion: @escaping (Result<Credentials, Error>) -> Void) {

        guard let phraseData = "HALLO".data(using: .utf8), let signedPhrase = noiseKeys.sign(phraseData) else {
            completion(.failure(VerificationCodeValidationError.phraseSigningError))
            return
        }

        let json: [String : String] = [
            "name": name,
            "phone": normalizedPhoneNumber,
            "code": verificationCode,
            "s_ed_pub": noiseKeys.publicEdKey.base64EncodedString(),
            "signed_phrase": signedPhrase.base64EncodedString(),
        ]
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

            DDLogInfo("reg/validate-code/success [noise]")

            DispatchQueue.main.async {
                completion(.success(.v2(userID: userID, noiseKeys: noiseKeys)))
            }

        }
        task.resume()
    }

    // Support migration to Noise protocol

    func updateNoiseKeys(_ noiseKeys: NoiseKeys, userID: UserID, password: String, completion: @escaping (Result<Credentials, Error>) -> Void) {
        guard let phraseData = "HALLO".data(using: .utf8), let signedPhrase = noiseKeys.sign(phraseData) else {
            completion(.failure(NoiseKeyUpdateError.phraseSigningError))
            return
        }
        let json: [String : String] = [
            "uid": userID,
            "password": password,
            "s_ed_pub": noiseKeys.publicEdKey.base64EncodedString(),
            "signed_phrase": signedPhrase.base64EncodedString(),
        ]
        guard let url = URL(string: "https://\(hostName)/api/registration/update_key"),
              let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []) else
        {
            completion(.failure(NoiseKeyUpdateError.requestCreationError))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        DDLogInfo("reg/update-noise-keys/begin url=[\(url.absoluteString)] [\(userID)]")
        let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                DDLogError("reg/update-noise-keys/error [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            guard let data = data else {
                DDLogError("reg/update-noise-keys/error Data is empty.")
                DispatchQueue.main.async {
                    completion(.failure(NoiseKeyUpdateError.malformedResponse))
                }
                return
            }
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                DDLogError("reg/update-noise-keys/error Invalid response. [\(String(describing: urlResponse))]")
                DispatchQueue.main.async {
                    completion(.failure(NoiseKeyUpdateError.malformedResponse))
                }
                return
            }
            guard let response = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                DDLogError("reg/update-noise-keys/error Invalid response. [\(String(bytes: data, encoding: .utf8) ?? "")]")
                DispatchQueue.main.async {
                    completion(.failure(NoiseKeyUpdateError.malformedResponse))
                }
                return
            }

            DDLogInfo("reg/update-noise-keys/finished  status=[\(httpResponse.statusCode)]  response=[\(response)]")

            if let errorString = response["error"] as? String {
                let error = NoiseKeyUpdateError(rawValue: errorString) ?? .malformedResponse
                DDLogInfo("reg/update-noise-keys/invalid [\(error)]")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let result = response["result"] as? String else {
                DDLogInfo("reg/update-noise-keys/invalid Missing result")
                DispatchQueue.main.async {
                    completion(.failure(NoiseKeyUpdateError.malformedResponse))
                }
                return
            }

            guard result == "ok" else {
                DDLogInfo("reg/update-noise-keys/invalid result [\(result)]")
                let error = NoiseKeyUpdateError(rawValue: result) ?? .malformedResponse
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            DDLogInfo("reg/update-noise-keys/success [noise]")

            DispatchQueue.main.async {
                completion(.success(.v2(userID: userID, noiseKeys: noiseKeys)))
            }
        }
        task.resume()
    }

}

enum VerificationCodeRequestError: String, Error, RawRepresentable {
    case notInvited = "not_invited"
    case smsFailure = "sms_fail"
    case malformedResponse // everything else
}

enum VerificationCodeValidationError: String, Error, RawRepresentable {
    case incorrectCode = "wrong_sms_code"                   // The sms code provided does not match
    case missingPhone = "missing_phone"                     // Request is missing phone field
    case missingCode = "missing_code"                       // Request is missing code field
    case missingName = "missing_name"                       // Request is missing name field
    case invalidName = "invalid_name"                       // Invalid name in the request
    case badRequest = "bad_request"                         // Could be several reasons, one is UserAgent does not follow the HalloApp.
    case signedPhraseError = "unable_to_open_signed_phrase" // Server unable to read signed phrase
    case phraseSigningError                                 // Error signing key phrase
    case keyGenerationError                                 // Unable to generate keys
    case malformedResponse                                  // Everything else
}

enum NoiseKeyUpdateError: String, Error, RawRepresentable {
    case phraseSigningError
    case requestCreationError
    case invalidKey = "invalid_s_ed_pub"
    case invalidPassword = "invalid_password"
    case signedPhraseError = "unable_to_open_signed_phrase"
    case invalidSignedPhrase = "invalid_signed_phrase"
    case malformedResponse                                  // Everything else
}
