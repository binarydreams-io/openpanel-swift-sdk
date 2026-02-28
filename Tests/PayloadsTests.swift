import Foundation
@testable import OpenPanel
import Testing

@Suite("Payloads")
struct PayloadsTests {
  // MARK: - TrackPayload

  @Test("TrackPayload encodes and decodes")
  func trackPayloadRoundTrip() throws {
    let payload = TrackPayload(
      name: "button_click",
      properties: ["page": "home"],
      profileId: "user-123"
    )
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackPayload.self, from: data)
    #expect(decoded.name == "button_click")
    #expect(decoded.profileId == "user-123")
    #expect(decoded.properties?["page"] == "home")
  }

  @Test("TrackPayload encodes with nil optional fields")
  func trackPayloadNilOptionals() throws {
    let payload = TrackPayload(name: "page_view")
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackPayload.self, from: data)
    #expect(decoded.name == "page_view")
    #expect(decoded.profileId == nil)
    #expect(decoded.properties == nil)
  }

  // MARK: - IdentifyPayload

  @Test("IdentifyPayload encodes and decodes with all fields")
  func identifyPayloadFullRoundTrip() throws {
    let payload = IdentifyPayload(
      profileId: "user-456",
      firstName: "John",
      lastName: "Doe",
      email: "john@example.com",
      avatar: "https://example.com/avatar.png",
      properties: ["plan": "pro"]
    )
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(IdentifyPayload.self, from: data)
    #expect(decoded.profileId == "user-456")
    #expect(decoded.firstName == "John")
    #expect(decoded.lastName == "Doe")
    #expect(decoded.email == "john@example.com")
    #expect(decoded.avatar == "https://example.com/avatar.png")
    #expect(decoded.properties?["plan"] == "pro")
  }

  @Test("IdentifyPayload encodes with only required fields")
  func identifyPayloadMinimal() throws {
    let payload = IdentifyPayload(profileId: "user-789")
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(IdentifyPayload.self, from: data)
    #expect(decoded.profileId == "user-789")
    #expect(decoded.firstName == nil)
    #expect(decoded.lastName == nil)
    #expect(decoded.email == nil)
    #expect(decoded.avatar == nil)
    #expect(decoded.properties == nil)
  }

  // MARK: - AliasPayload

  @Test("AliasPayload encodes and decodes")
  func aliasPayloadRoundTrip() throws {
    let payload = AliasPayload(profileId: "user-123", alias: "anon-456")
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(AliasPayload.self, from: data)
    #expect(decoded.profileId == "user-123")
    #expect(decoded.alias == "anon-456")
  }

  // MARK: - IncrementPayload

  @Test("IncrementPayload encodes and decodes with value")
  func incrementPayloadWithValue() throws {
    let payload = IncrementPayload(profileId: "user-1", property: "login_count", value: 5)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(IncrementPayload.self, from: data)
    #expect(decoded.profileId == "user-1")
    #expect(decoded.property == "login_count")
    #expect(decoded.value == 5)
  }

  @Test("IncrementPayload encodes and decodes without value")
  func incrementPayloadWithoutValue() throws {
    let payload = IncrementPayload(profileId: "user-1", property: "login_count")
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(IncrementPayload.self, from: data)
    #expect(decoded.profileId == "user-1")
    #expect(decoded.property == "login_count")
    #expect(decoded.value == nil)
  }

  // MARK: - DecrementPayload

  @Test("DecrementPayload encodes and decodes with value")
  func decrementPayloadWithValue() throws {
    let payload = DecrementPayload(profileId: "user-2", property: "credits", value: 10)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(DecrementPayload.self, from: data)
    #expect(decoded.profileId == "user-2")
    #expect(decoded.property == "credits")
    #expect(decoded.value == 10)
  }

  @Test("DecrementPayload encodes and decodes without value")
  func decrementPayloadWithoutValue() throws {
    let payload = DecrementPayload(profileId: "user-2", property: "credits")
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(DecrementPayload.self, from: data)
    #expect(decoded.value == nil)
  }

  // MARK: - TrackHandlerPayload

  @Test("TrackHandlerPayload wraps track payload")
  func trackHandlerTrack() throws {
    let inner = TrackPayload(name: "event", profileId: "u1")
    let payload = TrackHandlerPayload.track(inner)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    if case let .track(decodedInner) = decoded {
      #expect(decodedInner.name == "event")
      #expect(decodedInner.profileId == "u1")
    } else {
      Issue.record("Expected .track case")
    }
  }

  @Test("TrackHandlerPayload wraps identify payload")
  func trackHandlerIdentify() throws {
    let inner = IdentifyPayload(profileId: "u2", email: "a@b.com")
    let payload = TrackHandlerPayload.identify(inner)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    if case let .identify(decodedInner) = decoded {
      #expect(decodedInner.profileId == "u2")
      #expect(decodedInner.email == "a@b.com")
    } else {
      Issue.record("Expected .identify case")
    }
  }

  @Test("TrackHandlerPayload wraps alias payload")
  func trackHandlerAlias() throws {
    let inner = AliasPayload(profileId: "u3", alias: "a3")
    let payload = TrackHandlerPayload.alias(inner)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    if case let .alias(decodedInner) = decoded {
      #expect(decodedInner.profileId == "u3")
      #expect(decodedInner.alias == "a3")
    } else {
      Issue.record("Expected .alias case")
    }
  }

  @Test("TrackHandlerPayload wraps increment payload")
  func trackHandlerIncrement() throws {
    let inner = IncrementPayload(profileId: "u4", property: "visits", value: 1)
    let payload = TrackHandlerPayload.increment(inner)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    if case let .increment(decodedInner) = decoded {
      #expect(decodedInner.profileId == "u4")
      #expect(decodedInner.property == "visits")
      #expect(decodedInner.value == 1)
    } else {
      Issue.record("Expected .increment case")
    }
  }

  @Test("TrackHandlerPayload wraps decrement payload")
  func trackHandlerDecrement() throws {
    let inner = DecrementPayload(profileId: "u5", property: "tokens", value: 3)
    let payload = TrackHandlerPayload.decrement(inner)
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    if case let .decrement(decodedInner) = decoded {
      #expect(decodedInner.profileId == "u5")
      #expect(decodedInner.property == "tokens")
      #expect(decodedInner.value == 3)
    } else {
      Issue.record("Expected .decrement case")
    }
  }

  @Test("TrackHandlerPayload decoding unknown type throws")
  func trackHandlerUnknownType() {
    let json = """
    {"type":"unknown","payload":{}}
    """
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(TrackHandlerPayload.self, from: data)
    }
  }

  @Test("TrackHandlerPayload JSON contains correct type field")
  func trackHandlerTypeField() throws {
    let cases: [(TrackHandlerPayload, String)] = [
      (.track(TrackPayload(name: "e")), "track"),
      (.identify(IdentifyPayload(profileId: "p")), "identify"),
      (.alias(AliasPayload(profileId: "p", alias: "a")), "alias"),
      (.increment(IncrementPayload(profileId: "p", property: "x")), "increment"),
      (.decrement(DecrementPayload(profileId: "p", property: "x")), "decrement")
    ]

    for (payload, expectedType) in cases {
      let data = try JSONEncoder().encode(payload)
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      #expect(json?["type"] as? String == expectedType)
    }
  }
}
