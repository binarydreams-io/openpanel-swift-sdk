//
//  IncrementPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for an `increment` event. Atomically increments a numeric profile property.
public struct IncrementPayload: Codable, Sendable, Equatable {
  /// Profile whose property is being incremented.
  public var profileId: ProfileId
  /// Property key.
  public var property: String
  /// Amount to add. Server defaults to `1` when `nil`.
  public var value: Double?

  public init(profileId: ProfileId, property: String, value: Double? = nil) {
    self.profileId = profileId
    self.property = property
    self.value = value
  }
}
