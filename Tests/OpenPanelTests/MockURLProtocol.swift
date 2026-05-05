//
//  MockURLProtocol.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation
import os

/// URLProtocol subclass that lets tests stub `URLSession` responses.
///
/// Usage:
/// ```swift
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// let session = URLSession(configuration: config)
/// let recorder = await MockURLProtocol.install { req in .ok(deviceId: "d", sessionId: "s") }
/// ```
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  // MARK: - Handler registry

  struct Response {
    var statusCode: Int
    var body: Data
    var headers: [String: String]

    static func ok(deviceId: String = "dev_1", sessionId: String = "ses_1") -> Response {
      let bodyJSON = #"{"deviceId":"\#(deviceId)","sessionId":"\#(sessionId)"}"#
      return .init(
        statusCode: 200,
        body: Data(bodyJSON.utf8),
        headers: ["Content-Type": "application/json"]
      )
    }

    static let noContent = Response(statusCode: 202, body: Data(), headers: [:])
    static let unauthorized = Response(statusCode: 401, body: Data("unauthorized".utf8), headers: [:])
    static let serverError = Response(statusCode: 500, body: Data("boom".utf8), headers: [:])
    static let duplicate = Response(
      statusCode: 200,
      body: Data("Duplicate event".utf8),
      headers: ["Content-Type": "text/plain"]
    )
  }

  /// Thread-safe handler storage. Handlers are closures that receive the request
  /// and decide what to return — this lets us script multi-attempt scenarios.
  actor Registry {
    private var handler: (@Sendable (URLRequest) -> Result<Response, Error>)?
    private var capturedRequests: [URLRequest] = []
    private var capturedBodies: [Data] = []

    func install(_ handler: @Sendable @escaping (URLRequest) -> Result<Response, Error>) {
      self.handler = handler
      capturedRequests = []
      capturedBodies = []
    }

    func handle(_ request: URLRequest, body: Data?) -> Result<Response, Error> {
      capturedRequests.append(request)
      if let body { capturedBodies.append(body) }
      return handler?(request) ?? .failure(URLError(.badURL))
    }

    var requests: [URLRequest] {
      capturedRequests
    }

    var bodies: [Data] {
      capturedBodies
    }
  }

  static let registry = Registry()

  static func install(_ handler: @Sendable @escaping (URLRequest) -> Result<Response, Error>) async {
    await registry.install(handler)
  }

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  // MARK: - URLProtocol

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  private let loadTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

  override func startLoading() {
    let request = request
    // URLSession puts uploaded body into httpBodyStream, not httpBody.
    let requestBody = Self.readBody(from: request)

    let loadingTask = Task {
      let handlerResult = await Self.registry.handle(request, body: requestBody)
      guard !Task.isCancelled else { return }
      switch handlerResult {
      case let .success(response):
        let httpResponse = HTTPURLResponse(
          url: request.url!,
          statusCode: response.statusCode,
          httpVersion: "HTTP/1.1",
          headerFields: response.headers
        )!
        self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: response.body)
        self.client?.urlProtocolDidFinishLoading(self)
      case let .failure(error):
        self.client?.urlProtocol(self, didFailWithError: error)
      }
    }
    loadTask.withLock { storedTask in storedTask = loadingTask }
  }

  override func stopLoading() {
    loadTask.withLock { storedTask in storedTask?.cancel() }
  }

  /// URLSession surfaces the request body via `httpBodyStream`.
  private static func readBody(from request: URLRequest) -> Data? {
    if let bodyData = request.httpBody { return bodyData }
    guard let bodyStream = request.httpBodyStream else { return nil }
    bodyStream.open()
    defer { bodyStream.close() }
    var collectedData = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while bodyStream.hasBytesAvailable {
      let bytesRead = bodyStream.read(&buffer, maxLength: bufferSize)
      if bytesRead <= 0 { break }
      collectedData.append(buffer, count: bytesRead)
    }
    return collectedData
  }
}
