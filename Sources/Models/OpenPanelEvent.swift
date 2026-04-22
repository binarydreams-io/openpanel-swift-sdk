//
//  OpenPanelEvent.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Discriminated union on `type` matching the server's event envelope schema.
/// Every public action on the SDK encodes to one of these variants and is sent
/// as the body of a single `POST /track` request.
public enum OpenPanelEvent: Sendable, Equatable {
  /// A behavioural event (page view, click, custom name, …).
  case track(TrackPayload)
  /// Associate a profile with the current device and (optionally) update profile traits.
  case identify(IdentifyPayload)
  /// Create or update a group's metadata.
  case group(GroupPayload)
  /// Attach a profile to one or more groups.
  case assignGroup(AssignGroupPayload)
  /// Increment a numeric profile property atomically server-side.
  case increment(IncrementPayload)
  /// Decrement a numeric profile property atomically server-side.
  case decrement(DecrementPayload)
}

extension OpenPanelEvent: Codable {
  private enum Keys: String, CodingKey { case type, payload }
  private enum Kind: String, Codable {
    case track, identify, group, assign_group, increment, decrement
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .track: self = try .track(container.decode(TrackPayload.self, forKey: .payload))
    case .identify: self = try .identify(container.decode(IdentifyPayload.self, forKey: .payload))
    case .group: self = try .group(container.decode(GroupPayload.self, forKey: .payload))
    case .assign_group: self = try .assignGroup(container.decode(AssignGroupPayload.self, forKey: .payload))
    case .increment: self = try .increment(container.decode(IncrementPayload.self, forKey: .payload))
    case .decrement: self = try .decrement(container.decode(DecrementPayload.self, forKey: .payload))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    switch self {
    case let .track(payload):
      try container.encode(Kind.track, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .identify(payload):
      try container.encode(Kind.identify, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .group(payload):
      try container.encode(Kind.group, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .assignGroup(payload):
      try container.encode(Kind.assign_group, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .increment(payload):
      try container.encode(Kind.increment, forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .decrement(payload):
      try container.encode(Kind.decrement, forKey: .type)
      try container.encode(payload, forKey: .payload)
    }
  }
}
