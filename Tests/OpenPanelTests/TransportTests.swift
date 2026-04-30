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
  // MockURLProtocol uses a shared registry; serialization is inherited from MockBackedSuite.
  @Suite("Transport", .tags(.networking, .transport))
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

    /// Convenience: a minimal track envelope used as the request body across most tests.
    private func sampleEnvelope(name: String = "e") -> OpenPanelEvent {
      .track(TrackPayload(name: name))
    }

    // MARK: - Happy path

    @Test
    func `200 OK returns decoded response and caches device-session IDs`() async throws {
      await MockURLProtocol.install { _ in .success(.ok(deviceId: "dev_42", sessionId: "ses_9")) }

      let transport = makeTransport()
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())

      #expect(response?.deviceId == "dev_42")
      #expect(response?.sessionId == "ses_9")
    }

    @Test(arguments: [
      ("openpanel-client-id", "00000000-0000-0000-0000-000000000000"),
      ("openpanel-client-secret", "test-secret"),
      ("Content-Type", "application/json")
    ])
    func `request includes expected static header`(name: String, expected: String) async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }

      let transport = makeTransport()
      let _: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())

      let request = try await firstRequest()
      #expect(request.value(forHTTPHeaderField: name) == expected)
    }

    @Test(arguments: ["openpanel-sdk-name", "openpanel-sdk-version"])
    func `request includes non-empty SDK header`(name: String) async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }

      let transport = makeTransport()
      let _: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())

      let request = try await firstRequest()
      let value = request.value(forHTTPHeaderField: name)
      #expect(value != nil)
      #expect(value?.isEmpty == false)
    }

    @Test
    func `202 returns nil with no body`() async throws {
      await MockURLProtocol.install { _ in .success(.noContent) }

      let transport = makeTransport()
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())
      #expect(response == nil)
    }

    // MARK: - 401 silent drop

    @Test
    func `401 returns nil without throwing and without retrying`() async throws {
      await MockURLProtocol.install { _ in .success(.unauthorized) }

      let transport = makeTransport(maxRetries: 5)
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())
      #expect(response == nil)

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 1) // no retries on 401
    }

    // MARK: - Retries

    @Test
    func `5xx retries up to maxRetries and then throws`() async throws {
      await MockURLProtocol.install { _ in .success(.serverError) }

      let transport = makeTransport(maxRetries: 3)
      let error = await #expect(throws: OpenPanel.Error.self) {
        let _: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())
      }

      // initial + 3 retries = 4 calls
      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 4)

      // The thrown error must surface the upstream HTTP status, not a generic transport error.
      guard case let .http(status, _) = try #require(error) else {
        Issue.record("expected OpenPanel.Error.http, got \(String(describing: error))")
        return
      }
      #expect(status == 500)
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
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())

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
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())
      #expect(response != nil)

      let calls = await MockURLProtocol.registry.requests.count
      #expect(calls == 2)
    }

    // MARK: - Plain-text "Duplicate event"

    @Test
    func `200 with plain-text Duplicate event body returns nil without decoding error`() async throws {
      await MockURLProtocol.install { _ in .success(.duplicate) }

      let transport = makeTransport()
      let response: TrackResponse? = try await transport.post(path: "/track", body: sampleEnvelope())
      #expect(response == nil)
    }

    // MARK: - Request body verification

    @Test
    func `POST body is the encoded envelope`() async throws {
      await MockURLProtocol.install { _ in .success(.ok()) }

      let transport = makeTransport()
      let body = OpenPanelEvent.track(TrackPayload(name: "screen_view", profileId: "u1"))
      let _: TrackResponse? = try await transport.post(path: "/track", body: body)

      let envelope = try await MockURLProtocol.registry.firstEnvelope()
      guard let track = envelope.trackPayload else {
        Issue.record("expected track envelope, got \(envelope.testDescription)")
        return
      }
      #expect(track.name == "screen_view")
      #expect(track.profileId == "u1")
    }

    // MARK: - Helpers

    /// Returns the first captured `URLRequest`, or fails the test with proper source attribution.
    private func firstRequest(sourceLocation: SourceLocation = #_sourceLocation) async throws -> URLRequest {
      let captured = await MockURLProtocol.registry.requests
      return try #require(captured.first, sourceLocation: sourceLocation)
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
