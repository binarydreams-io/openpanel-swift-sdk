//
//  GroupPayload.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Payload for a `group` event. Creates or updates a group's metadata.
public struct GroupPayload: Codable, Sendable, Equatable {
  /// Stable group identifier.
  public var id: String
  /// Group kind (e.g. `"company"`, `"organization"`, `"team"`).
  public var type: String
  /// Human-readable group name.
  public var name: String
  /// Custom group traits.
  public var properties: [String: String]?

  public init(id: String, type: String, name: String, properties: [String: String]? = nil) {
    self.id = id
    self.type = type
    self.name = name
    self.properties = properties
  }
}
