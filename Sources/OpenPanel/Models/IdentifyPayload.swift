import Foundation

public struct IdentifyPayload: Codable, Sendable {
  public var profileId: ProfileId
  public var firstName: String?
  public var lastName: String?
  public var email: String?
  public var avatar: String?
  public var properties: Properties?

  public init(
    profileId: ProfileId,
    firstName: String? = nil,
    lastName: String? = nil,
    email: String? = nil,
    avatar: String? = nil,
    properties: Properties? = nil
  ) {
    self.profileId = profileId
    self.firstName = firstName
    self.lastName = lastName
    self.email = email
    self.avatar = avatar
    self.properties = properties
  }
}
