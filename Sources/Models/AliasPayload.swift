//
//  AliasPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for an `alias` event. Merges an anonymous profile (`alias`) into a
/// canonical one (`profileId`) server-side — typical use is anon → logged-in.
public struct AliasPayload: Codable, Sendable, Equatable {
  /// Canonical profile to keep.
  public var profileId: String
  /// Profile (or alias key) to merge into `profileId`.
  public var alias: String

  public init(profileId: String, alias: String) {
    self.profileId = profileId
    self.alias = alias
  }
}
