//
//  EncodingTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
@testable import OpenPanel
import Testing

@Suite("Encoding", .tags(.encoding))
struct EncodingTests {
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private let decoder = JSONDecoder()

  // MARK: - Discriminator round-trips

  @Test(arguments: [
    OpenPanelEvent.track(TrackPayload(name: "n")),
    OpenPanelEvent.identify(IdentifyPayload(profileId: "u")),
    OpenPanelEvent.group(GroupPayload(id: "g", type: "company", name: "Acme")),
    OpenPanelEvent.assignGroup(AssignGroupPayload(groupIds: ["g"])),
    OpenPanelEvent.increment(IncrementPayload(profileId: "u", property: "x")),
    OpenPanelEvent.decrement(DecrementPayload(profileId: "u", property: "x"))
  ])
  func `every envelope variant round-trips losslessly`(envelope: OpenPanelEvent) throws {
    let data = try encoder.encode(envelope)
    let decoded = try decoder.decode(OpenPanelEvent.self, from: data)
    #expect(decoded == envelope)
  }

  // MARK: - ProfileId union

  @Test(arguments: [
    (ProfileId.string("user_123"), "\"profileId\":\"user_123\""),
    (ProfileId.int(42), "\"profileId\":42"),
    (ProfileId.double(3.14), "\"profileId\":3.14")
  ])
  func `profileId encodes per its variant`(profileId: ProfileId, expectedFragment: String) throws {
    let envelope = OpenPanelEvent.identify(IdentifyPayload(profileId: profileId))
    let json = try String(decoding: encoder.encode(envelope), as: UTF8.self)
    #expect(json.contains(expectedFragment))
  }

  @Test
  func `numeric profileId is not quoted as a string`() throws {
    let envelope = OpenPanelEvent.identify(IdentifyPayload(profileId: .int(42)))
    let json = try String(decoding: encoder.encode(envelope), as: UTF8.self)
    #expect(json.contains("\"profileId\":\"42\"") == false)
  }

  // MARK: - Optional omission

  @Test
  func `nil track fields are omitted, never emitted as null`() throws {
    let envelope = OpenPanelEvent.track(TrackPayload(name: "e"))
    let json = try String(decoding: encoder.encode(envelope), as: UTF8.self)
    #expect(json.contains("\"groups\"") == false)
    #expect(json.contains("\"properties\"") == false)
    #expect(json.contains("\"profileId\"") == false)
    #expect(json.contains("null") == false)
  }
}
