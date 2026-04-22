import Foundation

public struct GroupPayload: Codable, Sendable {
  public var id: String
  public var type: String
  public var name: String
  public var properties: Properties?

  public init(id: String, type: String, name: String, properties: Properties? = nil) {
    self.id = id
    self.type = type
    self.name = name
    self.properties = properties
  }
}
