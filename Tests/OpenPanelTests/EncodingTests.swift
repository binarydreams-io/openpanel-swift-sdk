//
//  EncodingTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

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

  @Test(
    arguments: [
      (OpenPanelEvent.track(TrackPayload(name: "n")), "track"),
      (OpenPanelEvent.identify(IdentifyPayload(profileId: "u")), "identify"),
      (OpenPanelEvent.group(GroupPayload(id: "g", type: "company", name: "Acme")), "group"),
      (OpenPanelEvent.assignGroup(AssignGroupPayload(groupIds: ["g"])), "assign_group"),
      (OpenPanelEvent.increment(IncrementPayload(profileId: "u", property: "x")), "increment"),
      (OpenPanelEvent.decrement(DecrementPayload(profileId: "u", property: "x")), "decrement")
    ]
  )
  func `all six envelope variants encode with the correct discriminator`(envelope: OpenPanelEvent, expectedType: String) throws {
    let json = try String(decoding: encoder.encode(envelope), as: UTF8.self)
    #expect(json.contains("\"type\":\"\(expectedType)\""))
  }

  // MARK: - ProfileId union

  @Test
  func `profileId encodes as string when given a string`() throws {
    let env = OpenPanelEvent.identify(IdentifyPayload(profileId: .string("user_123")))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"profileId\":\"user_123\""))
  }

  @Test
  func `profileId encodes as number when given an integer`() throws {
    let env = OpenPanelEvent.identify(IdentifyPayload(profileId: .int(42)))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(json.contains("\"profileId\":42"))
    #expect(!json.contains("\"profileId\":\"42\""))
  }

  @Test
  func `profileId round-trips through numeric decoding`() throws {
    let original = OpenPanelEvent.identify(IdentifyPayload(profileId: .int(42)))
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(OpenPanelEvent.self, from: data)
    guard case let .identify(p) = decoded, case let .int(i) = p.profileId else {
      Issue.record("expected .identify(.int)")
      return
    }
    #expect(i == 42)
  }

  @Test
  func `profileId round-trips through string decoding`() throws {
    let original = OpenPanelEvent.identify(IdentifyPayload(profileId: .string("u1")))
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(OpenPanelEvent.self, from: data)
    guard case let .identify(p) = decoded, case let .string(s) = p.profileId else {
      Issue.record("expected .identify(.string)")
      return
    }
    #expect(s == "u1")
  }

  // MARK: - Optional omission

  @Test
  func `nil groups/properties are omitted, not emitted as null`() throws {
    let env = OpenPanelEvent.track(TrackPayload(name: "e"))
    let json = try String(decoding: encoder.encode(env), as: UTF8.self)
    #expect(!json.contains("\"groups\""))
    #expect(!json.contains("\"properties\""))
    #expect(!json.contains("\"profileId\""))
  }
}
