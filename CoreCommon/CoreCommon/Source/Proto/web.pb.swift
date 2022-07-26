// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: web.proto
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

public struct Web_WebContainer {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var payload: Web_WebContainer.OneOf_Payload? = nil

  public var noiseMessage: Web_NoiseMessage {
    get {
      if case .noiseMessage(let v)? = payload {return v}
      return Web_NoiseMessage()
    }
    set {payload = .noiseMessage(newValue)}
  }

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum OneOf_Payload: Equatable {
    case noiseMessage(Web_NoiseMessage)

  #if !swift(>=4.1)
    public static func ==(lhs: Web_WebContainer.OneOf_Payload, rhs: Web_WebContainer.OneOf_Payload) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.noiseMessage, .noiseMessage): return {
        guard case .noiseMessage(let l) = lhs, case .noiseMessage(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      }
    }
  #endif
  }

  public init() {}
}

public struct Web_NoiseMessage {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var messageType: Web_NoiseMessage.MessageType = .ikA

  public var content: Data = Data()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum MessageType: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ikA // = 0
    case ikB // = 1
    case kkA // = 2
    case kkB // = 3
    case UNRECOGNIZED(Int)

    public init() {
      self = .ikA
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ikA
      case 1: self = .ikB
      case 2: self = .kkA
      case 3: self = .kkB
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ikA: return 0
      case .ikB: return 1
      case .kkA: return 2
      case .kkB: return 3
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Web_NoiseMessage.MessageType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Web_NoiseMessage.MessageType] = [
    .ikA,
    .ikB,
    .kkA,
    .kkB,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Web_WebContainer: @unchecked Sendable {}
extension Web_WebContainer.OneOf_Payload: @unchecked Sendable {}
extension Web_NoiseMessage: @unchecked Sendable {}
extension Web_NoiseMessage.MessageType: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "web"

extension Web_WebContainer: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".WebContainer"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "noise_message"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: Web_NoiseMessage?
        var hadOneofValue = false
        if let current = self.payload {
          hadOneofValue = true
          if case .noiseMessage(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.payload = .noiseMessage(v)
        }
      }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if case .noiseMessage(let v)? = self.payload {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Web_WebContainer, rhs: Web_WebContainer) -> Bool {
    if lhs.payload != rhs.payload {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Web_NoiseMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".NoiseMessage"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "message_type"),
    2: .same(proto: "content"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.messageType) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.content) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.messageType != .ikA {
      try visitor.visitSingularEnumField(value: self.messageType, fieldNumber: 1)
    }
    if !self.content.isEmpty {
      try visitor.visitSingularBytesField(value: self.content, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Web_NoiseMessage, rhs: Web_NoiseMessage) -> Bool {
    if lhs.messageType != rhs.messageType {return false}
    if lhs.content != rhs.content {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Web_NoiseMessage.MessageType: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "IK_A"),
    1: .same(proto: "IK_B"),
    2: .same(proto: "KK_A"),
    3: .same(proto: "KK_B"),
  ]
}
