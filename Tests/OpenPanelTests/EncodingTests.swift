import Foundation
@testable import OpenPanel
import Testing

@Suite("Encoding")
struct EncodingTests {
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  // MARK: - Discriminator

  @Test
  func `track envelope uses type: track`() throws {
    let env = TrackEnvelope.track(TrackPayload(name: "screen_view"))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"type\":\"track\""))
    #expect(json.contains("\"name\":\"screen_view\""))
  }

  @Test
  func `assign_group uses snake_case discriminator`() throws {
    let env = TrackEnvelope.assignGroup(AssignGroupPayload(groupIds: ["a"], profileId: "u"))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"type\":\"assign_group\""))
  }

  @Test(
    arguments: [
      (TrackEnvelope.track(TrackPayload(name: "n")), "track"),
      (TrackEnvelope.identify(IdentifyPayload(profileId: "u")), "identify"),
      (TrackEnvelope.group(GroupPayload(id: "g", type: "company", name: "Acme")), "group"),
      (TrackEnvelope.assignGroup(AssignGroupPayload(groupIds: ["g"])), "assign_group"),
      (TrackEnvelope.increment(IncrementPayload(profileId: "u", property: "x")), "increment"),
      (TrackEnvelope.decrement(DecrementPayload(profileId: "u", property: "x")), "decrement")
    ]
  )
  func `all six envelope variants encode with the correct discriminator`(envelope: TrackEnvelope, expectedType: String) throws {
    let json = try String(decoding: encoder.encode(envelope), as: UTF8.self)
    #expect(json.contains("\"type\":\"\(expectedType)\""))
  }

  // MARK: - ProfileId union

  @Test
  func `profileId encodes as string when given a string`() throws {
    let env = TrackEnvelope.identify(IdentifyPayload(profileId: .string("user_123")))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"profileId\":\"user_123\""))
  }

  @Test
  func `profileId encodes as number when given an integer`() throws {
    let env = TrackEnvelope.identify(IdentifyPayload(profileId: .int(42)))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"profileId\":42"))
    #expect(!json.contains("\"profileId\":\"42\""))
  }

  @Test
  func `profileId round-trips through numeric decoding`() throws {
    let original = TrackEnvelope.identify(IdentifyPayload(profileId: .int(42)))
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(TrackEnvelope.self, from: data)
    guard case let .identify(p) = decoded, case let .int(i) = p.profileId else {
      Issue.record("expected .identify(.int)")
      return
    }
    #expect(i == 42)
  }

  @Test
  func `profileId round-trips through string decoding`() throws {
    let original = TrackEnvelope.identify(IdentifyPayload(profileId: .string("u1")))
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(TrackEnvelope.self, from: data)
    guard case let .identify(p) = decoded, case let .string(s) = p.profileId else {
      Issue.record("expected .identify(.string)")
      return
    }
    #expect(s == "u1")
  }

  // MARK: - Optional omission

  @Test
  func `nil groups/properties are omitted, not emitted as null`() throws {
    let env = TrackEnvelope.track(TrackPayload(name: "e"))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(!json.contains("\"groups\""))
    #expect(!json.contains("\"properties\""))
    #expect(!json.contains("\"profileId\""))
  }

  // MARK: - AnyCodable

  @Test
  func `AnyCodable preserves heterogeneous values`() throws {
    let props: Properties = [
      "s": AnyCodable("text"),
      "n": AnyCodable(Int64(7)),
      "d": AnyCodable(1.5),
      "b": AnyCodable(true),
      "null": AnyCodable(nil)
    ]
    let data = try encoder.encode(props)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"s\":\"text\""))
    #expect(json.contains("\"n\":7"))
    #expect(json.contains("\"d\":1.5"))
    #expect(json.contains("\"b\":true"))
    #expect(json.contains("\"null\":null"))
  }
}
