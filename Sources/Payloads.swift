import Foundation

public typealias TrackProperties = [String: String]

public enum TrackHandlerPayload: Codable, Sendable {
  case track(TrackPayload)
  case increment(IncrementPayload)
  case decrement(DecrementPayload)
  case alias(AliasPayload)
  case identify(IdentifyPayload)

  private enum CodingKeys: String, CodingKey {
    case type, payload
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .track(payload):
      try container.encode("track", forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .increment(payload):
      try container.encode("increment", forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .decrement(payload):
      try container.encode("decrement", forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .alias(payload):
      try container.encode("alias", forKey: .type)
      try container.encode(payload, forKey: .payload)
    case let .identify(payload):
      try container.encode("identify", forKey: .type)
      try container.encode(payload, forKey: .payload)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "track":
      self = try .track(container.decode(TrackPayload.self, forKey: .payload))
    case "increment":
      self = try .increment(container.decode(IncrementPayload.self, forKey: .payload))
    case "decrement":
      self = try .decrement(container.decode(DecrementPayload.self, forKey: .payload))
    case "alias":
      self = try .alias(container.decode(AliasPayload.self, forKey: .payload))
    case "identify":
      self = try .identify(container.decode(IdentifyPayload.self, forKey: .payload))
    default:
      throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
    }
  }
}

public struct TrackPayload: Codable, Sendable {
  public let name: String
  public var properties: [String: String]?
  public var profileId: String?

  public init(name: String, properties: [String: String]? = nil, profileId: String? = nil) {
    self.name = name
    self.properties = properties
    self.profileId = profileId
  }
}

public struct IdentifyPayload: Codable, Sendable {
  public let profileId: String
  public var firstName: String?
  public var lastName: String?
  public var email: String?
  public var avatar: String?
  public var properties: [String: String]?

  public init(profileId: String, firstName: String? = nil, lastName: String? = nil, email: String? = nil, avatar: String? = nil, properties: [String: String]? = nil) {
    self.profileId = profileId
    self.firstName = firstName
    self.lastName = lastName
    self.email = email
    self.avatar = avatar
    self.properties = properties
  }
}

public struct AliasPayload: Codable, Sendable {
  public let profileId: String
  public let alias: String

  public init(profileId: String, alias: String) {
    self.profileId = profileId
    self.alias = alias
  }
}

public struct IncrementPayload: Codable, Sendable {
  public let profileId: String
  public let property: String
  public var value: Int?

  public init(profileId: String, property: String, value: Int? = nil) {
    self.profileId = profileId
    self.property = property
    self.value = value
  }
}

public struct DecrementPayload: Codable, Sendable {
  public let profileId: String
  public let property: String
  public var value: Int?

  public init(profileId: String, property: String, value: Int? = nil) {
    self.profileId = profileId
    self.property = property
    self.value = value
  }
}
