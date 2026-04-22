import Foundation

public struct DecrementPayload: Codable, Sendable {
  public var profileId: ProfileId
  public var property: String
  public var value: Double?

  public init(profileId: ProfileId, property: String, value: Double? = nil) {
    self.profileId = profileId
    self.property = property
    self.value = value
  }
}
