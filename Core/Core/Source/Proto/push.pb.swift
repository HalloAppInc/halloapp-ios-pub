// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: push.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

public struct PBpush_token {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var os: PBpush_token.Os = .android

  public var token: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Os: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case android // = 0
    case ios // = 1
    case iosDev // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .android
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .android
      case 1: self = .ios
      case 2: self = .iosDev
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .android: return 0
      case .ios: return 1
      case .iosDev: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension PBpush_token.Os: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [PBpush_token.Os] = [
    .android,
    .ios,
    .iosDev,
  ]
}

#endif  // swift(>=4.2)

public struct PBpush_register {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var pushToken: PBpush_token {
    get {return _pushToken ?? PBpush_token()}
    set {_pushToken = newValue}
  }
  /// Returns true if `pushToken` has been explicitly set.
  public var hasPushToken: Bool {return self._pushToken != nil}
  /// Clears the value of `pushToken`. Subsequent reads from it will return its default value.
  public mutating func clearPushToken() {self._pushToken = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _pushToken: PBpush_token? = nil
}

public struct PBpush_pref {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var name: PBpush_pref.Name = .post

  public var value: Bool = false

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Name: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case post // = 0
    case comment // = 1
    case UNRECOGNIZED(Int)

    public init() {
      self = .post
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .post
      case 1: self = .comment
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .post: return 0
      case .comment: return 1
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension PBpush_pref.Name: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [PBpush_pref.Name] = [
    .post,
    .comment,
  ]
}

#endif  // swift(>=4.2)

public struct PBnotification_prefs {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var pushPrefs: [PBpush_pref] = []

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension PBpush_token: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "push_token"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "os"),
    2: .same(proto: "token"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularEnumField(value: &self.os)
      case 2: try decoder.decodeSingularStringField(value: &self.token)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.os != .android {
      try visitor.visitSingularEnumField(value: self.os, fieldNumber: 1)
    }
    if !self.token.isEmpty {
      try visitor.visitSingularStringField(value: self.token, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBpush_token, rhs: PBpush_token) -> Bool {
    if lhs.os != rhs.os {return false}
    if lhs.token != rhs.token {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBpush_token.Os: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "android"),
    1: .same(proto: "ios"),
    2: .same(proto: "ios_dev"),
  ]
}

extension PBpush_register: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "push_register"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "push_token"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularMessageField(value: &self._pushToken)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if let v = self._pushToken {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBpush_register, rhs: PBpush_register) -> Bool {
    if lhs._pushToken != rhs._pushToken {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBpush_pref: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "push_pref"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "name"),
    2: .same(proto: "value"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularEnumField(value: &self.name)
      case 2: try decoder.decodeSingularBoolField(value: &self.value)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.name != .post {
      try visitor.visitSingularEnumField(value: self.name, fieldNumber: 1)
    }
    if self.value != false {
      try visitor.visitSingularBoolField(value: self.value, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBpush_pref, rhs: PBpush_pref) -> Bool {
    if lhs.name != rhs.name {return false}
    if lhs.value != rhs.value {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBpush_pref.Name: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "post"),
    1: .same(proto: "comment"),
  ]
}

extension PBnotification_prefs: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "notification_prefs"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "push_prefs"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeRepeatedMessageField(value: &self.pushPrefs)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.pushPrefs.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.pushPrefs, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBnotification_prefs, rhs: PBnotification_prefs) -> Bool {
    if lhs.pushPrefs != rhs.pushPrefs {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
