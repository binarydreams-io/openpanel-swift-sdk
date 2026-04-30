//
//  OpenPanelTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
@testable import OpenPanel
import Testing

// MARK: - Track

extension MockBackedSuite {
  @Suite("Track", .tags(.networking))
  struct TrackTests {
    @Test(.configured)
    func `server deviceId/sessionId are cached on the actor`() async throws {
      await MockURLProtocol.install { _ in .success(.ok(deviceId: "d_abc", sessionId: "s_xyz")) }

      await OpenPanel.shared.track("e")

      #expect(await OpenPanel.deviceId == "d_abc")
      #expect(await OpenPanel.sessionId == "s_xyz")
    }

    @Test(.configured)
    func `subsequent track events inherit identified profileId`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.track("e")

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      #expect(payload.name == "e")
      #expect(payload.profileId == .string("u1"))
    }
  }
}

// MARK: - Identify

extension MockBackedSuite {
  @Suite("Identify", .tags(.networking, .identify))
  struct IdentifyTests {
    @Test(.configured)
    func `identify with only profileId does NOT hit the server`() async {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))

      let count = await MockURLProtocol.registry.requests.count
      #expect(count == 0)
    }

    @Test(.configured)
    func `identify with extras sends an identify envelope`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.identifyPayload)
      #expect(payload.profileId == .string("u1"))
      #expect(payload.email == "a@b.c")
    }

    @Test(.configured(disabled: true))
    func `identify does not flush while disabled=true`() async {
      await OpenPanel.shared.track("queued")

      // identify attempts to drain, but disabled is still true — queue stays.
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      let beforeReady = await MockURLProtocol.registry.requests.count
      #expect(beforeReady == 0)

      await OpenPanel.shared.ready()
      let afterReady = await MockURLProtocol.registry.requests.count
      #expect(afterReady == 1)
    }
  }
}

// MARK: - Groups

extension MockBackedSuite {
  @Suite("Groups", .tags(.networking, .groups))
  struct GroupTests {
    @Test(.configured)
    func `setGroup accumulates groups and attaches them to subsequent events`() async throws {
      // setGroup requires a profileId to send assign_group events.
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.setGroup("acme")
      await OpenPanel.shared.setGroup("globex")
      await OpenPanel.shared.track("e")

      let envelopes = try await MockURLProtocol.registry.envelopes()
      // 2 assign_group + 1 track = 3 requests
      #expect(envelopes.count == 3)

      let lastEnvelope = try #require(envelopes.last)
      let trackPayload = try #require(lastEnvelope.trackPayload)
      let groups = try #require(trackPayload.groups)
      #expect(Set(groups) == ["acme", "globex"])
    }

    @Test(.configured)
    func `setGroups assigns multiple groups at once`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.setGroups(["acme", "globex"])
      await OpenPanel.shared.track("e")

      let envelopes = try await MockURLProtocol.registry.envelopes()
      // 1 assign_group + 1 track = 2 requests
      #expect(envelopes.count == 2)

      let assign = try #require(envelopes.first?.assignGroupPayload)
      #expect(Set(assign.groupIds) == ["acme", "globex"])
      #expect(assign.profileId == .string("u1"))

      let trackPayload = try #require(envelopes.last?.trackPayload)
      let groups = try #require(trackPayload.groups)
      #expect(Set(groups) == ["acme", "globex"])
    }

    @Test(.configured)
    func `upsertGroup sends group envelope`() async throws {
      await OpenPanel.shared.upsertGroup(GroupPayload(id: "g1", type: "company", name: "Acme"))

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.groupPayload)
      #expect(payload.id == "g1")
      #expect(payload.type == "company")
      #expect(payload.name == "Acme")
    }
  }
}

// MARK: - Queue

extension MockBackedSuite {
  @Suite("Queue", .tags(.networking, .queue))
  struct QueueTests {
    @Test(.configured(disabled: true))
    func `disabled=true queues events until ready()`() async {
      await OpenPanel.shared.track("a")
      await OpenPanel.shared.track("b")

      let beforeReady = await MockURLProtocol.registry.requests.count
      #expect(beforeReady == 0)

      await OpenPanel.shared.ready()

      let afterReady = await MockURLProtocol.registry.requests.count
      #expect(afterReady == 2)
    }

    @Test(.configured(disabled: true))
    func `flush() drains the queue when SDK is enabled`() async {
      await OpenPanel.shared.track("a")
      await OpenPanel.shared.track("b")
      let beforeReady = await MockURLProtocol.registry.requests.count
      #expect(beforeReady == 0)

      // Enable, then flush is implicitly invoked by ready().
      await OpenPanel.shared.ready()

      let afterReady = await MockURLProtocol.registry.requests.count
      #expect(afterReady == 2)
    }

    @Test(.configured(disabled: true))
    func `queued track events are stamped with __timestamp`() async throws {
      await OpenPanel.shared.track("queued_event")
      await OpenPanel.shared.ready()

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      let properties = try #require(payload.properties)
      #expect(properties["__timestamp"] != nil)
    }

    @Test(.configured(disabled: true))
    func `track events queued before identify pick up profileId on drain`() async throws {
      await OpenPanel.shared.track("queued_before_identify")

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u_late"))
      await OpenPanel.shared.ready()

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      #expect(payload.name == "queued_before_identify")
      #expect(payload.profileId == .string("u_late"))
    }
  }
}

// MARK: - Revenue

extension MockBackedSuite {
  @Suite("Revenue", .tags(.networking))
  struct RevenueTests {
    @Test(.configured(clientSecret: "s"))
    func `revenue encodes __revenue and names the event 'revenue'`() async throws {
      await OpenPanel.shared.revenue(9.99, properties: ["currency": "USD"])

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      #expect(payload.name == "revenue")
      let properties = try #require(payload.properties)
      #expect(properties["__revenue"] == "9.99")
      #expect(properties["currency"] == "USD")
    }

    @Test(.configured(clientSecret: "s"))
    func `revenue encodes __deviceId when provided`() async throws {
      await OpenPanel.shared.revenue(100, deviceId: "dev_42")

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      let properties = try #require(payload.properties)
      #expect(properties["__deviceId"] == "dev_42")
      #expect(properties["__revenue"] == "100.0")
    }
  }
}

// MARK: - Counters (increment / decrement)

extension MockBackedSuite {
  @Suite("Counters", .tags(.networking))
  struct CounterTests {
    @Test(.configured)
    func `increment sends increment envelope with profileId`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.increment(property: "login_count", value: 1)

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.incrementPayload)
      #expect(payload.property == "login_count")
      #expect(payload.profileId == .string("u1"))
      #expect(payload.value == 1)
    }

    @Test(.configured)
    func `decrement sends decrement envelope with profileId`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.decrement(property: "credits", value: 5)

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.decrementPayload)
      #expect(payload.property == "credits")
      #expect(payload.profileId == .string("u1"))
      #expect(payload.value == 5)
    }
  }
}

// MARK: - Methods that require a profileId

extension MockBackedSuite {
  @Suite("RequiresProfileId", .tags(.networking))
  struct RequiresProfileIdTests {
    @Test(.configured, arguments: [
      "setGroup",
      "setGroups",
      "increment",
      "decrement"
    ])
    func `methods that require profileId are no-ops without one`(method: String) async {
      switch method {
      case "setGroup": await OpenPanel.shared.setGroup("g")
      case "setGroups": await OpenPanel.shared.setGroups(["g"])
      case "increment": await OpenPanel.shared.increment(property: "p")
      case "decrement": await OpenPanel.shared.decrement(property: "p")
      default:
        Issue.record("unknown method '\(method)'")
        return
      }
      let count = await MockURLProtocol.registry.requests.count
      #expect(count == 0, "\(method) must not hit the network without profileId")
    }
  }
}

// MARK: - Global properties

extension MockBackedSuite {
  @Suite("GlobalProperties", .tags(.networking))
  struct GlobalPropertiesTests {
    @Test(.configured)
    func `global properties are merged into every track event`() async throws {
      await OpenPanel.shared.setGlobalProperties(["app_version": "1.2.3"])
      await OpenPanel.shared.track("e", properties: ["screen": "Home"])

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      let properties = try #require(payload.properties)
      #expect(properties["app_version"] == "1.2.3")
      #expect(properties["screen"] == "Home")
    }

    @Test(.configured)
    func `event-level properties override global properties on key collision`() async throws {
      await OpenPanel.shared.setGlobalProperties(["env": "prod"])
      await OpenPanel.shared.track("e", properties: ["env": "staging"])

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      let properties = try #require(payload.properties)
      #expect(properties["env"] == "staging")
    }
  }
}

// MARK: - Clear

extension MockBackedSuite {
  @Suite("Clear", .tags(.networking))
  struct ClearTests {
    @Test(.configured)
    func `clear() resets profile, groups, device/session IDs`() async throws {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))
      await OpenPanel.shared.track("e")
      #expect(await OpenPanel.deviceId != nil)

      await OpenPanel.shared.clear()

      #expect(await OpenPanel.deviceId == nil)
      #expect(await OpenPanel.sessionId == nil)

      await OpenPanel.shared.track("after")
      let envelope = try await MockURLProtocol.registry.lastEnvelope()
      let payload = try #require(envelope.trackPayload)
      #expect(payload.profileId == nil)
    }

    @Test(.configured)
    func `clear() does not reset global properties`() async throws {
      await OpenPanel.shared.setGlobalProperties(["env": "prod"])
      await OpenPanel.shared.clear()
      await OpenPanel.shared.track("e")

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      let payload = try #require(envelope.trackPayload)
      let properties = try #require(payload.properties)
      #expect(properties["env"] == "prod")
    }
  }
}

// MARK: - Filter

extension MockBackedSuite {
  @Suite("Filter", .tags(.networking))
  struct FilterTests {
    @Test(.configured(filter: { event in
      if case let .track(p) = event, p.name == "blocked" { return false }
      return true
    }))
    func `filter=false drops the event before network`() async throws {
      await OpenPanel.shared.track("ok")
      await OpenPanel.shared.track("blocked")

      let envelopes = try await MockURLProtocol.registry.envelopes()
      #expect(envelopes.count == 1)
      let payload = try #require(envelopes.first?.trackPayload)
      #expect(payload.name == "ok")
    }
  }
}
