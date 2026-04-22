import Foundation

public struct TrackPayload: Codable, Sendable {
  public var name: String
  public var properties: Properties?
  public var profileId: ProfileId?
  public var groups: [String]?

  public init(name: String, properties: Properties? = nil, profileId: ProfileId? = nil, groups: [String]? = nil) {
    self.name = name
    self.properties = properties
    self.profileId = profileId
    self.groups = groups
  }
}
