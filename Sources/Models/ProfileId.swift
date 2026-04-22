//
//  ProfileId.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Server accepts profileId as either a string or a number.
/// We encode as-is and preserve the shape the caller provided.
public enum ProfileId: Sendable, Hashable {
  case string(String)
  case int(Int64)
  case double(Double)

  public init(_ value: String) {
    self = .string(value)
  }

  public init(_ value: Int) {
    self = .int(Int64(value))
  }

  public init(_ value: Int64) {
    self = .int(value)
  }

  public init(_ value: Double) {
    self = .double(value)
  }
}

extension ProfileId: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
      return
    }
    if let int = try? container.decode(Int64.self) {
      self = .int(int)
      return
    }
    if let double = try? container.decode(Double.self) {
      self = .double(double)
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "ProfileId must be string or number")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .string(string): try container.encode(string)
    case let .int(int): try container.encode(int)
    case let .double(double): try container.encode(double)
    }
  }
}

extension ProfileId: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .string(value)
  }
}

extension ProfileId: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .int(Int64(value))
  }
}
