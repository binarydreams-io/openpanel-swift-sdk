import Foundation

/// Minimal type-erased Codable for free-form `properties` dictionaries.
/// Supports: null, Bool, Int64, Double, String, [AnyCodable], [String: AnyCodable].
public struct AnyCodable: Sendable, Codable {
  public let value: (any Sendable)?

  public init(_ value: (any Sendable)?) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self.value = nil
      return
    }
    if let bool = try? container.decode(Bool.self) {
      self.value = bool
      return
    }
    if let int = try? container.decode(Int64.self) {
      self.value = int
      return
    }
    if let double = try? container.decode(Double.self) {
      self.value = double
      return
    }
    if let string = try? container.decode(String.self) {
      self.value = string
      return
    }
    if let array = try? container.decode([AnyCodable].self) {
      self.value = array
      return
    }
    if let object = try? container.decode([String: AnyCodable].self) {
      self.value = object
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case nil: try container.encodeNil()
    case let bool as Bool: try container.encode(bool)
    case let int as Int: try container.encode(Int64(int))
    case let int as Int64: try container.encode(int)
    case let double as Double: try container.encode(double)
    case let float as Float: try container.encode(Double(float))
    case let string as String: try container.encode(string)
    case let array as [AnyCodable]: try container.encode(array)
    case let array as [Any]: try container.encode(array.map(AnyCodable.init(coercing:)))
    case let object as [String: AnyCodable]: try container.encode(object)
    case let object as [String: Any]: try container.encode(object.mapValues(AnyCodable.init(coercing:)))
    default:
      throw EncodingError.invalidValue(
        value as Any,
        .init(codingPath: encoder.codingPath, debugDescription: "Unsupported value")
      )
    }
  }

  /// Re-wraps elements extracted from an `[Any]` / `[String: Any]` container whose
  /// originating value was Sendable-constrained at construction. `Sendable` is a
  /// marker protocol, so it can't be conditionally cast at runtime — dispatch by
  /// concrete type instead. Unsupported types collapse to `nil`.
  private init(coercing value: Any?) {
    switch value {
    case nil: self.value = nil
    case let wrapped as AnyCodable: self.value = wrapped.value
    case let bool as Bool: self.value = bool
    case let int as Int: self.value = Int64(int)
    case let int as Int64: self.value = int
    case let double as Double: self.value = double
    case let float as Float: self.value = Double(float)
    case let string as String: self.value = string
    case let array as [AnyCodable]: self.value = array
    case let object as [String: AnyCodable]: self.value = object
    case let array as [Any]: self.value = array.map { AnyCodable(coercing: $0) }
    case let object as [String: Any]: self.value = object.mapValues { AnyCodable(coercing: $0) }
    default: self.value = nil
    }
  }
}

public typealias Properties = [String: AnyCodable]
