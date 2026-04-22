//
//  TransportTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
@testable import OpenPanel
import os
import Testing

extension MockBackedSuite {
  @Suite("Transport") // MockURLProtocol uses shared registry; serialized via parent.
  struct TransportTests {
    private func makeTransport(maxRetries: Int = 3) -> OpenPanel.Transport {
      let config = OpenPanel.Config(
        clientId: "00000000-0000-0000-0000-000000000000",
        clientSecret: "test-secret",
        apiURL: URL(string: "https://api.example.test")!,
        maxRetries: maxRetries,
        initialRetryDelay: .milliseconds(1)
      )
      return OpenPanel.Transport(config: config, session: MockURLProtocol.makeSession())
    }

    // MARK: - Happy path

    @Test
    func `200 OK returns decoded response and caches device/session IDs`() async throws {
      await MockURLProtocol.install { _ in .success(.ok(deviceId: "dev_42", sessionId: "ses_9")) }

      let transport = makeTransport()
      let body = OpenPanelEvent.track(TrackPayload(name: "e"))
      let response: TrackResponse? = try await transport.post(path: "/track", body: body)

      #expect(response?.deviceId == "dev_42")
      #expect(response?.sessionId == "ses_9")
    }

    @Test
    func `request includes auth and SDK headers`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }

      let transport = makeTransport()
      let _: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))

      let captured = await MockURLProtocol.registry.requests
      let request = try #require(captured.first)
      #expect(request.value(forHTTPHeaderField: "openpanel-client-id") == "00000000-0000-0000-0000-000000000000")
      #expect(request.value(forHTTPHeaderField: "openpanel-client-secret") == "test-secret")
      #expect(request.value(forHTTPHeaderField: "openpanel-sdk-name") != nil)
      #expect(request.value(forHTTPHeaderField: "openpanel-sdk-version") != nil)
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func `202 returns nil with no body`() async throws {
      await MockURLProtocol.install { _ in .success(.noContent) }

      let transport = makeTransport()
      let response: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))
      #expect(response == nil)
    }

    // MARK: - 401 silent drop

    @Test
    func `401 returns nil without throwing and without retrying`() async throws {
      await MockURLProtocol.install { _ in .success(.unauthorized) }

      let transport = makeTransport(maxRetries: 5)
      let response: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))
      #expect(response == nil)

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 1) // no retries on 401
    }

    // MARK: - Retries

    @Test
    func `5xx retries up to maxRetries and then throws`() async throws {
      await MockURLProtocol.install { _ in .success(.serverError) }

      let transport = makeTransport(maxRetries: 3)
      await #expect(throws: OpenPanel.Error.self) {
        let _: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))
      }
      // initial + 3 retries = 4 calls
      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 4)
    }

    @Test
    func `transient failure then success on retry`() async throws {
      // First two calls fail with 500, third succeeds.
      let counter = Counter()
      await MockURLProtocol.install { _ in
        let attempt = counter.tick()
        return attempt <= 2 ? .success(.serverError) : .success(.ok(deviceId: "ok", sessionId: "s"))
      }

      let transport = makeTransport(maxRetries: 3)
      let response: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))

      #expect(response?.deviceId == "ok")
      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 3)
    }

    @Test
    func `network error is retried`() async throws {
      let counter = Counter()
      await MockURLProtocol.install { _ in
        let attempt = counter.tick()
        return attempt == 1 ? .failure(URLError(.networkConnectionLost)) : .success(.ok())
      }

      let transport = makeTransport(maxRetries: 2)
      let response: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))
      #expect(response != nil)

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 2)
    }

    // MARK: - Plain-text "Duplicate event"

    @Test
    func `200 with plain-text 'Duplicate event' returns nil, no decoding error`() async throws {
      await MockURLProtocol.install { _ in .success(.duplicate) }

      let transport = makeTransport()
      let response: TrackResponse? = try await transport.post(path: "/track", body: OpenPanelEvent.track(TrackPayload(name: "e")))
      #expect(response == nil)
    }

    // MARK: - Request body verification

    @Test
    func `POST body is the encoded envelope`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }

      let transport = makeTransport()
      let body = OpenPanelEvent.track(TrackPayload(name: "screen_view", profileId: "u1"))
      let _: TrackResponse? = try await transport.post(path: "/track", body: body)

      let bodies = await MockURLProtocol.registry.bodies
      let raw = try #require(bodies.first)
      let json = String(decoding: raw, as: UTF8.self)
      #expect(json.contains("\"type\":\"track\"") || json.contains("\"type\": \"track\""))
      #expect(json.contains("\"name\":\"screen_view\"") || json.contains("\"name\": \"screen_view\""))
    }
  }
}

/// Tiny atomic counter for multi-attempt mock scenarios.
private final class Counter: Sendable {
  private let count = OSAllocatedUnfairLock(initialState: 0)
  func tick() -> Int {
    count.withLock { value in
      value += 1
      return value
    }
  }
}
