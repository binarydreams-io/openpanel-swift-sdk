//
//  AssignGroupPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for an `assign_group` event. Attaches a profile to one or more groups.
public struct AssignGroupPayload: Codable, Sendable, Equatable {
  /// Group IDs to attach the profile to.
  public var groupIds: [String]
  /// Target profile. Required for the server to act on the request.
  public var profileId: ProfileId?

  public init(groupIds: [String], profileId: ProfileId? = nil) {
    self.groupIds = groupIds
    self.profileId = profileId
  }
}
