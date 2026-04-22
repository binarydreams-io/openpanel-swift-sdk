import Foundation

public struct AssignGroupPayload: Codable, Sendable {
  public var groupIds: [String]
  public var profileId: ProfileId?

  public init(groupIds: [String], profileId: ProfileId? = nil) {
    self.groupIds = groupIds
    self.profileId = profileId
  }
}
