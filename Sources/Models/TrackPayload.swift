//
//  TrackPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for a `track` event.
public struct TrackPayload: Codable, Sendable, Equatable {
  /// Event name. Reserved names (`screen_view`, `revenue`, …) carry server-side semantics.
  public var name: String
  /// Arbitrary string properties attached to the event. Reserved keys start with `__`.
  public var properties: [String: String]?
  /// Profile this event belongs to. Inherited from the last `identify` call when `nil`.
  public var profileId: ProfileId?
  /// Group IDs this event is associated with. Merged with groups attached via ``OpenPanel/setGroup(_:)``.
  public var groups: [String]?

  public init(name: String, properties: [String: String]? = nil, profileId: ProfileId? = nil, groups: [String]? = nil) {
    self.name = name
    self.properties = properties
    self.profileId = profileId
    self.groups = groups
  }
}
