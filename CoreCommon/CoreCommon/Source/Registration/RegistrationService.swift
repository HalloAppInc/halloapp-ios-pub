//
//  RegistrationService.swift
//  Core
//
//  Created by Garrett on 10/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift

public protocol RegistrationService {
    func requestHashcashChallenge(countryCode: String?, completion: @escaping (Result<String, Error>) -> Void)
    func requestVerificationCode(for phoneNumber: String, byVoice: Bool, hashcash: HashcashSolution?, groupInviteToken: String?, locale: Locale, completion: @escaping (Result<RegistrationResponse, RegistrationErrorResponse>) -> Void)
    func validateVerificationCode(_ verificationCode: String, name: String, normalizedPhoneNumber: String, noiseKeys: NoiseKeys, groupInviteToken: String?, pushOS: String?, pushToken: String?, whisperKeys: WhisperKeyBundle, completion: @escaping (Result<Credentials, Error>) -> Void)
    func getGroupName(groupInviteToken: String, completion: @escaping (Result<String?, Error>) -> Void)
}

public struct RegistrationResponse {
    public var normalizedPhoneNumber: String
    public var retryDelay: TimeInterval
}

public struct RegistrationErrorResponse: Error {
    public var error: Error
    public var retryDelay: TimeInterval?

    public init(error: Error, retryDelay: TimeInterval? = nil) {
        self.error = error
        self.retryDelay = retryDelay
    }
}
public enum VerificationCodeRequestError: Error {
    case invalidPhoneNumber(reason: InvalidPhoneNumberReason?) // phone number provided is invalid
    case notInvited
    case smsFailure
    case invalidClientVersion // client version has expired.
    case requestCreationError
    case retriedTooSoon
    case malformedResponse // everything else
    
    public enum InvalidPhoneNumberReason {
        case invalidCountryCode
        case invalidLength
        case lineTypeVoip
        case lineTypeFixed
        case lineTypeOther
    }
}

public enum GetGroupNameError: String, Error, RawRepresentable {
    case invalidClientVersion = "invalid_client_version"    // client version has expired.
    case malformedResponse // everything else
}

public enum VerificationCodeValidationError: String, Error, RawRepresentable {
    case invalidPhoneNumber = "invalid_phone_number"        // phone number provided is invalid
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
