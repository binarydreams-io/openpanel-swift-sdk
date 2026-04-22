import Foundation

/// Discriminated union on `type` matching the server's event envelope schema.
enum TrackEnvelope {
  case track(TrackPayload)
  case identify(IdentifyPayload)
  case group(GroupPayload)
  case assignGroup(AssignGroupPayload)
  case increment(IncrementPayload)
  case decrement(DecrementPayload)
}

extension TrackEnvelope: Codable {
  private enum Keys: String, CodingKey { case type, payload }
  private enum Kind: String, Codable {
    case track, identify, group, assign_group, increment, decrement
  }

  init(from decoder: Decoder) throws {
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

  func encode(to encoder: Encoder) throws {
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
