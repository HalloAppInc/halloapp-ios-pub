// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: invite.proto
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

public struct PBinvite {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var phone: String = String()

  public var result: String = String()

  public var reason: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct PBinvites_request {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var invites: [PBinvite] = []

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct PBinvites_response {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var invitesLeft: Int32 = 0

  public var timeUntilRefresh: Int64 = 0

  public var invites: [PBinvite] = []

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension PBinvite: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "invite"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "phone"),
    2: .same(proto: "result"),
    3: .same(proto: "reason"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularStringField(value: &self.phone)
      case 2: try decoder.decodeSingularStringField(value: &self.result)
      case 3: try decoder.decodeSingularStringField(value: &self.reason)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.phone.isEmpty {
      try visitor.visitSingularStringField(value: self.phone, fieldNumber: 1)
    }
    if !self.result.isEmpty {
      try visitor.visitSingularStringField(value: self.result, fieldNumber: 2)
    }
    if !self.reason.isEmpty {
      try visitor.visitSingularStringField(value: self.reason, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBinvite, rhs: PBinvite) -> Bool {
    if lhs.phone != rhs.phone {return false}
    if lhs.result != rhs.result {return false}
    if lhs.reason != rhs.reason {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBinvites_request: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "invites_request"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "invites"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeRepeatedMessageField(value: &self.invites)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.invites.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.invites, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBinvites_request, rhs: PBinvites_request) -> Bool {
    if lhs.invites != rhs.invites {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBinvites_response: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "invites_response"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "invites_left"),
    2: .standard(proto: "time_until_refresh"),
    3: .same(proto: "invites"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularInt32Field(value: &self.invitesLeft)
      case 2: try decoder.decodeSingularInt64Field(value: &self.timeUntilRefresh)
      case 3: try decoder.decodeRepeatedMessageField(value: &self.invites)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.invitesLeft != 0 {
      try visitor.visitSingularInt32Field(value: self.invitesLeft, fieldNumber: 1)
    }
    if self.timeUntilRefresh != 0 {
      try visitor.visitSingularInt64Field(value: self.timeUntilRefresh, fieldNumber: 2)
    }
    if !self.invites.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.invites, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBinvites_response, rhs: PBinvites_response) -> Bool {
    if lhs.invitesLeft != rhs.invitesLeft {return false}
    if lhs.timeUntilRefresh != rhs.timeUntilRefresh {return false}
    if lhs.invites != rhs.invites {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
