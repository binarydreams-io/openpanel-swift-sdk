//
//  IdentifyPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for an `identify` event. Maps a device to a profile and updates profile traits.
public struct IdentifyPayload: Codable, Sendable, Equatable {
  /// Stable user identifier in your system.
  public var profileId: ProfileId
  public var firstName: String?
  public var lastName: String?
  public var email: String?
  /// Avatar URL.
  public var avatar: String?
  /// Custom profile traits. Merged with global properties before being sent.
  public var properties: [String: String]?

  public init(
    profileId: ProfileId,
    firstName: String? = nil,
    lastName: String? = nil,
    email: String? = nil,
    avatar: String? = nil,
    properties: [String: String]? = nil
  ) {
    self.profileId = profileId
    self.firstName = firstName
    self.lastName = lastName
    self.email = email
    self.avatar = avatar
    self.properties = properties
  }
}
