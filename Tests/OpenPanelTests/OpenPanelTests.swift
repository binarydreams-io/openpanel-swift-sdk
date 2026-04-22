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
    clientSecret: String? = nil,
    filter: (@Sendable (OpenPanelEvent) -> Bool)? = nil
  ) async {
    let config = OpenPanel.Config(
      clientId: "00000000-0000-0000-0000-000000000000",
      clientSecret: clientSecret,
      apiURL: URL(string: "https://api.example.test")!,
      initialRetryDelay: .milliseconds(1),
      disabled: disabled,
      filter: filter
    )
    await OpenPanel.initialize(config: config, session: MockURLProtocol.makeSession())
  }

  // MARK: - Not initialized

  @Test
  func `track throws notInitialized before initialize()`() async throws {
    await OpenPanel.shared.resetForTesting()
    await #expect(throws: OpenPanel.Error.notInitialized) {
      try await OpenPanel.track("e")
    }
  }

  @Test
  func `identify throws notInitialized before initialize()`() async throws {
    await OpenPanel.shared.resetForTesting()
    await #expect(throws: OpenPanel.Error.notInitialized) {
      try await OpenPanel.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))
    }
  }

  @Test
  func `setGlobalProperties throws notInitialized before initialize()`() async throws {
    await OpenPanel.shared.resetForTesting()
    await #expect(throws: OpenPanel.Error.notInitialized) {
      try await OpenPanel.setGlobalProperties(["k": AnyCodable("v")])
    }
  }

  @Test
  func `ready throws notInitialized before initialize()`() async throws {
    await OpenPanel.shared.resetForTesting()
    await #expect(throws: OpenPanel.Error.notInitialized) {
      try await OpenPanel.ready()
    }
  }

  @Test
  func `clear throws notInitialized before initialize()`() async throws {
    await OpenPanel.shared.resetForTesting()
    await #expect(throws: OpenPanel.Error.notInitialized) {
      try await OpenPanel.clear()
    }
  }

  // MARK: - Queue behaviour

  @Test
  func `disabled=true queues events until ready()`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure(disabled: true)

    try await OpenPanel.track("a")
    try await OpenPanel.track("b")

    #expect(await MockURLProtocol.registry.requests.isEmpty)

    try await OpenPanel.ready()

    let calls = await MockURLProtocol.registry.requests.count
    #expect(calls == 2)
  }

  @Test
  func `server deviceId/sessionId are cached on the actor`() async throws {
    await MockURLProtocol.install { _ in .success(.ok(deviceId: "d_abc", sessionId: "s_xyz")) }
    await configure()

    try await OpenPanel.track("e")

    #expect(await OpenPanel.deviceId == "d_abc")
    #expect(await OpenPanel.sessionId == "s_xyz")
  }

  // MARK: - Global properties

  @Test
  func `global properties are merged into every track event`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.setGlobalProperties(["app_version": AnyCodable("1.2.3")])
    try await OpenPanel.track("e", properties: ["screen": AnyCodable("Home")])

    let body = try await firstBodyJSON()
    #expect(body.contains("\"app_version\":\"1.2.3\""))
    #expect(body.contains("\"screen\":\"Home\""))
  }

  @Test
  func `event-level properties override global properties on key collision`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.setGlobalProperties(["env": AnyCodable("prod")])
    try await OpenPanel.track("e", properties: ["env": AnyCodable("staging")])

    let body = try await firstBodyJSON()
    #expect(body.contains("\"env\":\"staging\""))
    #expect(!body.contains("\"env\":\"prod\""))
  }

  // MARK: - Groups

  @Test
  func `setGroup accumulates groups and attaches them to subsequent events`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.setGroup("acme")
    try await OpenPanel.setGroup("globex")
    try await OpenPanel.track("e")

    let bodies = await MockURLProtocol.registry.bodies
    #expect(bodies.count == 3)

    let lastJSON = try String(decoding: #require(bodies.last), as: UTF8.self)
    #expect(lastJSON.contains("\"type\":\"track\""))
    #expect(lastJSON.contains("acme"))
    #expect(lastJSON.contains("globex"))
  }

  // MARK: - Identify

  @Test
  func `identify with only profileId does NOT hit the server`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.identify(IdentifyPayload(profileId: "u1"))

    let calls = await MockURLProtocol.registry.requests.count
    #expect(calls == 0)
  }

  @Test
  func `identify with extras sends an identify envelope`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))

    let body = try await firstBodyJSON()
    #expect(body.contains("\"type\":\"identify\""))
    #expect(body.contains("\"email\":\"a@b.c\""))
  }

  @Test
  func `identify flushes queued events with disabled=true`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure(disabled: true)

    try await OpenPanel.track("queued")

    // identify triggers flush — but only useful if SDK is enabled.
    // Here disabled is still true, so queue stays.
    try await OpenPanel.identify(IdentifyPayload(profileId: "u1"))
    #expect(await MockURLProtocol.registry.requests.isEmpty)

    try await OpenPanel.ready()
    let calls = await MockURLProtocol.registry.requests.count
    #expect(calls == 1)
  }

  @Test
  func `subsequent track events inherit identified profileId`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.identify(IdentifyPayload(profileId: "u1"))
    try await OpenPanel.track("e")

    let body = try await firstBodyJSON()
    #expect(body.contains("\"profileId\":\"u1\""))
  }

  // MARK: - Revenue

  @Test
  func `revenue encodes __revenue as an integer and names the event 'revenue'`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure(clientSecret: "s")

    try await OpenPanel.revenue(999, properties: ["currency": AnyCodable("USD")])

    let body = try await firstBodyJSON()
    #expect(body.contains("\"name\":\"revenue\""))
    #expect(body.contains("\"__revenue\":999"))
    #expect(!body.contains("\"__revenue\":\"999\""))
    #expect(!body.contains("\"__revenue\":999.0"))
    #expect(body.contains("\"currency\":\"USD\""))
  }

  // MARK: - Filter

  @Test
  func `filter=false drops the event before network`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure(filter: { event in
      if case let .track(p) = event, p.name == "blocked" { return false }
      return true
    })

    try await OpenPanel.track("ok")
    try await OpenPanel.track("blocked")

    let calls = await MockURLProtocol.registry.requests.count
    #expect(calls == 1)
  }

  // MARK: - Clear

  @Test
  func `clear() resets profile, groups, device/session IDs`() async throws {
    await MockURLProtocol.install { _ in .success(.ok()) }
    await configure()

    try await OpenPanel.identify(IdentifyPayload(profileId: "u1", email: "a@b.c"))
    try await OpenPanel.track("e")
    #expect(await OpenPanel.deviceId != nil)

    try await OpenPanel.clear()

    #expect(await OpenPanel.deviceId == nil)
    #expect(await OpenPanel.sessionId == nil)

    try await OpenPanel.track("after")
    let bodies = await MockURLProtocol.registry.bodies
    let lastJSON = try String(decoding: #require(bodies.last), as: UTF8.self)
    #expect(!lastJSON.contains("\"profileId\":\"u1\""))
  }

  // MARK: - Helpers

  private func firstBodyJSON() async throws -> String {
    let bodies = await MockURLProtocol.registry.bodies
    let raw = try #require(bodies.first)
    return String(decoding: raw, as: UTF8.self)
  }
}
}
