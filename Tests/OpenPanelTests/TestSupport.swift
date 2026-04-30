//
//  TestSupport.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
@testable import OpenPanel
import Testing

// MARK: - Configured-OpenPanel scope trait

/// Test scope that resets the `OpenPanel.shared` singleton with a mock-backed session
/// before each test/case and installs a default `200 OK` response. Removes the
/// `await configure()` boilerplate that every legacy test used to repeat.
struct ConfiguredOpenPanel: TestTrait, TestScoping, Sendable {
  let disabled: Bool
  let clientSecret: String
  let filter: (@Sendable (OpenPanelEvent) -> Bool)?
  let response: MockURLProtocol.Response?

  func provideScope(
    for _: Test,
    testCase _: Test.Case?,
    performing function: () async throws -> Void
  ) async throws {
    if let response {
      await MockURLProtocol.install { _ in .success(response) }
    }
    let config = OpenPanel.Config(
      clientId: "00000000-0000-0000-0000-000000000000",
      clientSecret: clientSecret,
      apiURL: URL(string: "https://api.example.test")!,
      initialRetryDelay: .milliseconds(1),
      filter: filter
    )
    await OpenPanel.shared.initialize(config, session: MockURLProtocol.makeSession(), disabled: disabled)
    try await function()
  }
}

extension Trait where Self == ConfiguredOpenPanel {
  /// Reset SDK with default `200 OK` mock response.
  static var configured: Self {
    ConfiguredOpenPanel(disabled: false, clientSecret: "test-secret", filter: nil, response: .ok())
  }

  static func configured(
    disabled: Bool = false,
    clientSecret: String = "test-secret",
    filter: (@Sendable (OpenPanelEvent) -> Bool)? = nil,
    response: MockURLProtocol.Response? = .ok()
  ) -> Self {
    ConfiguredOpenPanel(disabled: disabled, clientSecret: clientSecret, filter: filter, response: response)
  }
}

// MARK: - Envelope decoding helpers

extension MockURLProtocol.Registry {
  /// Decode all captured request bodies into `OpenPanelEvent` envelopes.
  func envelopes(sourceLocation: SourceLocation = #_sourceLocation) throws -> [OpenPanelEvent] {
    let captured = bodies
    let decoder = JSONDecoder()
    return try captured.map { raw in
      do {
        return try decoder.decode(OpenPanelEvent.self, from: raw)
      } catch {
        Issue.record("Could not decode envelope: \(error). Raw: \(String(decoding: raw, as: UTF8.self))", sourceLocation: sourceLocation)
        throw error
      }
    }
  }

  func firstEnvelope(sourceLocation: SourceLocation = #_sourceLocation) throws -> OpenPanelEvent {
    let captured = bodies
    let raw = try #require(captured.first, sourceLocation: sourceLocation)
    return try JSONDecoder().decode(OpenPanelEvent.self, from: raw)
  }

  func lastEnvelope(sourceLocation: SourceLocation = #_sourceLocation) throws -> OpenPanelEvent {
    let captured = bodies
    let raw = try #require(captured.last, sourceLocation: sourceLocation)
    return try JSONDecoder().decode(OpenPanelEvent.self, from: raw)
  }
}

// MARK: - OpenPanelEvent payload extractors (test-only convenience)

extension OpenPanelEvent {
  var trackPayload: TrackPayload? {
    if case let .track(p) = self { p } else { nil }
  }

  var identifyPayload: IdentifyPayload? {
    if case let .identify(p) = self { p } else { nil }
  }

  var groupPayload: GroupPayload? {
    if case let .group(p) = self { p } else { nil }
  }

  var assignGroupPayload: AssignGroupPayload? {
    if case let .assignGroup(p) = self { p } else { nil }
  }

  var incrementPayload: IncrementPayload? {
    if case let .increment(p) = self { p } else { nil }
  }

  var decrementPayload: DecrementPayload? {
    if case let .decrement(p) = self { p } else { nil }
  }
}

// MARK: - CustomTestStringConvertible (test target only)

extension OpenPanelEvent: CustomTestStringConvertible {
  public var testDescription: String {
    switch self {
    case let .track(p): "track(\"\(p.name)\")"
    case let .identify(p): "identify(\(p.profileId.testDescription))"
    case let .group(p): "group(\"\(p.id)\", type: \(p.type))"
    case let .assignGroup(p): "assignGroup(\(p.groupIds))"
    case let .increment(p): "increment(\(p.property))"
    case let .decrement(p): "decrement(\(p.property))"
    }
  }
}

extension ProfileId: CustomTestStringConvertible {
  public var testDescription: String {
    switch self {
    case let .string(s): "\"\(s)\""
    case let .int(i): "\(i)"
    case let .double(d): "\(d)"
    }
  }
}
