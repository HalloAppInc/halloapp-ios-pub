// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: client_log.proto
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

public struct PBclient_log {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var counts: [PBcount] = []

  public var events: [PBevent] = []

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct PBcount {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var namespace: String = String()

  public var metric: String = String()

  public var count: Int64 = 0

  public var dims: [PBdim] = []

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct PBevent {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var namespace: String = String()

  public var event: Data = SwiftProtobuf.Internal.emptyData

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct PBdim {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var name: String = String()

  public var value: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension PBclient_log: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "client_log"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "counts"),
    2: .same(proto: "events"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeRepeatedMessageField(value: &self.counts)
      case 2: try decoder.decodeRepeatedMessageField(value: &self.events)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.counts.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.counts, fieldNumber: 1)
    }
    if !self.events.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.events, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBclient_log, rhs: PBclient_log) -> Bool {
    if lhs.counts != rhs.counts {return false}
    if lhs.events != rhs.events {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBcount: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "count"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "namespace"),
    2: .same(proto: "metric"),
    3: .same(proto: "count"),
    4: .same(proto: "dims"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularStringField(value: &self.namespace)
      case 2: try decoder.decodeSingularStringField(value: &self.metric)
      case 3: try decoder.decodeSingularInt64Field(value: &self.count)
      case 4: try decoder.decodeRepeatedMessageField(value: &self.dims)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.namespace.isEmpty {
      try visitor.visitSingularStringField(value: self.namespace, fieldNumber: 1)
    }
    if !self.metric.isEmpty {
      try visitor.visitSingularStringField(value: self.metric, fieldNumber: 2)
    }
    if self.count != 0 {
      try visitor.visitSingularInt64Field(value: self.count, fieldNumber: 3)
    }
    if !self.dims.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.dims, fieldNumber: 4)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBcount, rhs: PBcount) -> Bool {
    if lhs.namespace != rhs.namespace {return false}
    if lhs.metric != rhs.metric {return false}
    if lhs.count != rhs.count {return false}
    if lhs.dims != rhs.dims {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBevent: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "event"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "namespace"),
    2: .same(proto: "event"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularStringField(value: &self.namespace)
      case 2: try decoder.decodeSingularBytesField(value: &self.event)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.namespace.isEmpty {
      try visitor.visitSingularStringField(value: self.namespace, fieldNumber: 1)
    }
    if !self.event.isEmpty {
      try visitor.visitSingularBytesField(value: self.event, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBevent, rhs: PBevent) -> Bool {
    if lhs.namespace != rhs.namespace {return false}
    if lhs.event != rhs.event {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension PBdim: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = "dim"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "name"),
    2: .same(proto: "value"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularStringField(value: &self.name)
      case 2: try decoder.decodeSingularStringField(value: &self.value)
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.name.isEmpty {
      try visitor.visitSingularStringField(value: self.name, fieldNumber: 1)
    }
    if !self.value.isEmpty {
      try visitor.visitSingularStringField(value: self.value, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: PBdim, rhs: PBdim) -> Bool {
    if lhs.name != rhs.name {return false}
    if lhs.value != rhs.value {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
