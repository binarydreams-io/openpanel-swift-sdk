//
//  OpenPanelTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
@testable import OpenPanel
import Testing

extension MockBackedSuite {
  @Suite("OpenPanel")
  struct OpenPanelTests {
    /// Re-initialize the shared singleton with a fresh mocked session. `initialize`
    /// resets all cached state so tests don't leak into each other via the singleton.
    private func configure(
      disabled: Bool = false,
      clientSecret: String = "test-secret",
      filter: (@Sendable (OpenPanelEvent) -> Bool)? = nil
    ) async {
      let config = OpenPanel.Config(
        clientId: "00000000-0000-0000-0000-000000000000",
        clientSecret: clientSecret,
        apiURL: URL(string: "https://api.example.test")!,
        initialRetryDelay: .milliseconds(1),
        filter: filter
      )
      await OpenPanel.shared.initialize(config, session: MockURLProtocol.makeSession(), disabled: disabled)
    }

    // MARK: - Queue behaviour

    @Test
    func `disabled=true queues events until ready()`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(disabled: true)

      await OpenPanel.shared.track("a")
      await OpenPanel.shared.track("b")

      #expect(await MockURLProtocol.registry.requests.isEmpty)

      await OpenPanel.shared.ready()

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 2)
    }

    @Test
    func `server deviceId/sessionId are cached on the actor`() async {
      await MockURLProtocol.install { _ in .success(.ok(deviceId: "d_abc", sessionId: "s_xyz")) }
      await configure()

      await OpenPanel.shared.track("e")

      #expect(await OpenPanel.deviceId == "d_abc")
      #expect(await OpenPanel.sessionId == "s_xyz")
    }

    // MARK: - Global properties

    @Test
    func `global properties are merged into every track event`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.setGlobalProperties(["app_version": "1.2.3"])
      await OpenPanel.shared.track("e", properties: ["screen": "Home"])

      let body = try await firstBodyJSON()
      #expect(body.contains("\"app_version\":\"1.2.3\""))
      #expect(body.contains("\"screen\":\"Home\""))
    }

    @Test
    func `event-level properties override global properties on key collision`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.setGlobalProperties(["env": "prod"])
      await OpenPanel.shared.track("e", properties: ["env": "staging"])

      let body = try await firstBodyJSON()
      #expect(body.contains("\"env\":\"staging\""))
      #expect(!body.contains("\"env\":\"prod\""))
    }

    // MARK: - Groups

    @Test
    func `setGroup accumulates groups and attaches them to subsequent events`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      // setGroup requires a profileId to send assign_group events.
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.setGroup("acme")
      await OpenPanel.shared.setGroup("globex")
      await OpenPanel.shared.track("e")

      let bodies = await MockURLProtocol.registry.bodies
      // 2 assign_group + 1 track = 3 requests
      #expect(bodies.count == 3)

      let lastJSON = try String(decoding: #require(bodies.last), as: UTF8.self)
      #expect(lastJSON.contains("\"type\":\"track\""))
      #expect(lastJSON.contains("acme"))
      #expect(lastJSON.contains("globex"))
    }

    @Test
    func `setGroup without profileId is a no-op`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.setGroup("acme")

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 0)
    }

    @Test
    func `setGroups assigns multiple groups at once`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.setGroups(["acme", "globex"])
      await OpenPanel.shared.track("e")

      let bodies = await MockURLProtocol.registry.bodies
      // 1 assign_group + 1 track = 2 requests
      #expect(bodies.count == 2)

      let lastJSON = try String(decoding: #require(bodies.last), as: UTF8.self)
      #expect(lastJSON.contains("acme"))
      #expect(lastJSON.contains("globex"))
    }

    // MARK: - Identify

    @Test
    func `identify with only profileId does NOT hit the server`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 0)
    }

    @Test
    func `identify with extras sends an identify envelope`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))

      let body = try await firstBodyJSON()
      #expect(body.contains("\"type\":\"identify\""))
      #expect(body.contains("\"email\":\"a@b.c\""))
    }

    @Test
    func `identify does not flush while disabled=true`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(disabled: true)

      await OpenPanel.shared.track("queued")

      // identify attempts to drain, but disabled is still true — queue stays.
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      #expect(await MockURLProtocol.registry.requests.isEmpty)

      await OpenPanel.shared.ready()
      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 1)
    }

    @Test
    func `subsequent track events inherit identified profileId`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.track("e")

      let body = try await firstBodyJSON()
      #expect(body.contains("\"profileId\":\"u1\""))
    }

    // MARK: - Revenue

    @Test
    func `revenue encodes __revenue and names the event 'revenue'`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(clientSecret: "s")

      await OpenPanel.shared.revenue(9.99, properties: ["currency": "USD"])

      let body = try await firstBodyJSON()
      #expect(body.contains("\"name\":\"revenue\""))
      #expect(body.contains("\"__revenue\":\"9.99\""))
      #expect(body.contains("\"currency\":\"USD\""))
    }

    // MARK: - Filter

    @Test
    func `filter=false drops the event before network`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(filter: { event in
        if case let .track(p) = event, p.name == "blocked" { return false }
        return true
      })

      await OpenPanel.shared.track("ok")
      await OpenPanel.shared.track("blocked")

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 1)
    }

    // MARK: - Clear

    @Test
    func `clear() resets profile, groups, device/session IDs`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))
      await OpenPanel.shared.track("e")
      #expect(await OpenPanel.deviceId != nil)

      await OpenPanel.shared.clear()

      #expect(await OpenPanel.deviceId == nil)
      #expect(await OpenPanel.sessionId == nil)

      await OpenPanel.shared.track("after")
      let bodies = await MockURLProtocol.registry.bodies
      let lastJSON = try String(decoding: #require(bodies.last), as: UTF8.self)
      #expect(!lastJSON.contains("\"profileId\":\"u1\""))
    }

    // MARK: - Increment / Decrement

    @Test
    func `increment sends increment envelope with profileId`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.increment(property: "login_count", value: 1)

      let body = try await firstBodyJSON()
      #expect(body.contains("\"type\":\"increment\""))
      #expect(body.contains("\"property\":\"login_count\""))
      #expect(body.contains("\"profileId\":\"u1\""))
    }

    @Test
    func `increment without profileId is a no-op`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.increment(property: "x")

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 0)
    }

    @Test
    func `decrement sends decrement envelope with profileId`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u1"))
      await OpenPanel.shared.decrement(property: "credits", value: 5)

      let body = try await firstBodyJSON()
      #expect(body.contains("\"type\":\"decrement\""))
      #expect(body.contains("\"property\":\"credits\""))
    }

    // MARK: - upsertGroup

    @Test
    func `upsertGroup sends group envelope`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.upsertGroup(GroupPayload(id: "g1", type: "company", name: "Acme"))

      let body = try await firstBodyJSON()
      #expect(body.contains("\"type\":\"group\""))
      #expect(body.contains("\"name\":\"Acme\""))
    }

    // MARK: - Flush

    @Test
    func `flush() drains the queue when SDK is enabled`() async {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(disabled: true)

      await OpenPanel.shared.track("a")
      await OpenPanel.shared.track("b")
      #expect(await MockURLProtocol.registry.requests.isEmpty)

      // Enable, then flush explicitly.
      await OpenPanel.shared.ready()

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 2)
    }

    // MARK: - Revenue with deviceId

    @Test
    func `revenue encodes __deviceId when provided`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(clientSecret: "s")

      await OpenPanel.shared.revenue(100, deviceId: "dev_42")

      let body = try await firstBodyJSON()
      #expect(body.contains("\"__deviceId\":\"dev_42\""))
      #expect(body.contains("\"__revenue\":\"100.0\""))
    }

    // MARK: - Queued event timestamp

    @Test
    func `queued track events are stamped with __timestamp`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(disabled: true)

      await OpenPanel.shared.track("queued_event")
      await OpenPanel.shared.ready()

      let body = try await firstBodyJSON()
      #expect(body.contains("\"__timestamp\""))
    }

    // MARK: - Queued events inherit profileId set after queueing

    @Test
    func `track events queued before identify pick up profileId on drain`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure(disabled: true)

      await OpenPanel.shared.track("queued_before_identify")

      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u_late"))
      await OpenPanel.shared.ready()

      let body = try await firstBodyJSON()
      #expect(body.contains("\"profileId\":\"u_late\""))
      #expect(body.contains("\"name\":\"queued_before_identify\""))
    }

    // MARK: - Clear preserves globals

    @Test
    func `clear() does not reset global properties`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }
      await configure()

      await OpenPanel.shared.setGlobalProperties(["env": "prod"])
      await OpenPanel.shared.clear()
      await OpenPanel.shared.track("e")

      let body = try await firstBodyJSON()
      #expect(body.contains("\"env\":\"prod\""))
    }

    // MARK: - Helpers

    private func firstBodyJSON() async throws -> String {
      let bodies = await MockURLProtocol.registry.bodies
      let raw = try #require(bodies.first)
      return String(decoding: raw, as: UTF8.self)
    }
  }
}
