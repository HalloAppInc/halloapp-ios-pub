//
//  VerificationCodeService.swift
//  HalloApp
//
//  Created by Garrett on 10/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

protocol VerificationCodeService {
    func requestVerificationCode(for phoneNumber: String, completion: @escaping (Result<String, Error>) -> Void)
    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, completion: @escaping (Result<(String, String), Error>) -> Void)
}

final class VerificationCodeServiceSMS: VerificationCodeService {

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

    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, completion: @escaping (Result<(String, String), Error>) -> Void) {
        let json: [String : String] = [ "name": name, "phone": normalizedPhoneNumber, "code": verificationCode ]
        var request = URLRequest(url: URL(string: "https://\(hostName)/api/registration/register")!)
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

            guard let userID = response["uid"] as? String, let password = response["password"] as? String else {
                DDLogInfo("reg/validate-code/invalid Missing userId or password")
                DispatchQueue.main.async {
                    completion(.failure(VerificationCodeValidationError.malformedResponse))
                }
                return
            }

            DDLogInfo("reg/validate-code/success")

            DispatchQueue.main.async {
                completion(.success((userID, password)))
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
    case incorrectCode = "wrong_sms_code" // The sms code provided does not match
    case missingPhone = "missing_phone"   // Request is missing phone field
    case missingCode = "missing_code"     // Request is missing code field
    case missingName = "missing_name"     // Request is missing name field
    case invalidName = "invalid_name"     // Invalid name in the request
    case badRequest = "bad_request"       // Could be several reasons, one is UserAgent does not follow the HalloApp.
    case malformedResponse                // Everything else
}
