//
//  OpenPanel+Transport.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

/// Thin HTTP transport layer.
/// Sends JSON via POST, retries transient failures with exponential backoff,
/// and treats 401 as a silent drop (no retry, returns `nil`).
extension OpenPanel {
  struct Transport {
    let config: Config
    let session: URLSession

    private static let encoder: JSONEncoder = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return encoder
    }()

    private static let decoder = JSONDecoder()

    init(config: Config, session: URLSession = .shared) {
      self.config = config
      self.session = session
    }

    func post<Response: Decodable>(path: String, body: some Encodable) async throws -> Response? {
      let requestURL = makeURL(path: path)
      let encodedBody = try Self.encoder.encode(body)

      var request = URLRequest(url: requestURL)
      request.httpMethod = "POST"
      request.httpBody = encodedBody
      applyHeaders(&request)

      return try await send(request: request, attempt: 0)
    }

    // MARK: - Private

    /// Joins `apiURL` with `path` regardless of whether either side has leading/trailing
    /// slashes. Preserves any base-path prefix in `apiURL` (e.g. proxy mounted at `/openpanel`).
    private func makeURL(path: String) -> URL {
      var urlComponents = URLComponents(url: config.apiURL, resolvingAgainstBaseURL: true) ?? URLComponents()
      let pathSegments = [urlComponents.path, path]
        .flatMap { $0.split(separator: "/") }
        .map(String.init)
      urlComponents.path = "/" + pathSegments.joined(separator: "/")
      return urlComponents.url ?? config.apiURL
    }

    private func applyHeaders(_ request: inout URLRequest) {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(config.clientId, forHTTPHeaderField: "openpanel-client-id")
      request.setValue(config.clientSecret, forHTTPHeaderField: "openpanel-client-secret")
      request.setValue(config.sdkName, forHTTPHeaderField: "openpanel-sdk-name")
      request.setValue(config.sdkVersion, forHTTPHeaderField: "openpanel-sdk-version")
    }

    private func send<Response: Decodable>(request: URLRequest, attempt: Int) async throws -> Response? {
      do {
        let (responseData, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else { throw OpenPanel.Error.invalidResponse }

        switch httpResponse.statusCode {
        case 200, 202:
          guard !responseData.isEmpty else { return nil }
          // Server may return plain text `"Duplicate event"` with 200 — treat as success-with-no-body.
          if let responseText = String(data: responseData, encoding: .utf8),
             !responseText.hasPrefix("\""),
             !responseText.hasPrefix("{"),
             !responseText.hasPrefix("[")
          {
            return nil
          }
          return try Self.decoder.decode(Response.self, from: responseData)

        case 401:
          // Unauthorized — silent drop, no retry.
          log("Unauthorized (401) for \(request.url?.absoluteString ?? "unknown")")
          return nil

        default:
          let responseBody = String(data: responseData, encoding: .utf8)
          throw OpenPanel.Error.http(status: httpResponse.statusCode, body: responseBody)
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        if attempt < config.maxRetries, isRetryable(error) {
          // Cap the shift to avoid overflow if a caller passes an unreasonable maxRetries.
          let backoffMultiplier = 1 << min(attempt, 16)
          let backoffDelay = config.initialRetryDelay * backoffMultiplier
          try await Task.sleep(for: backoffDelay)
          return try await send(request: request, attempt: attempt + 1)
        }
        if let openPanelError = error as? OpenPanel.Error { throw openPanelError }
        throw OpenPanel.Error.transport(message: String(describing: error))
      }
    }

    private func log(_ message: @autoclosure () -> String) {
      guard config.debug else { return }
      let formattedMessage = message()
      OpenPanel.transportLog.debug("\(formattedMessage)")
    }

    /// Retries 5xx, 408, 429, and recoverable network conditions. DNS failures, refused
    /// connections to a known host, malformed responses, and similar terminal errors are
    /// surfaced immediately rather than burning the retry budget.
    private func isRetryable(_ error: any Swift.Error) -> Bool {
      if case let OpenPanel.Error.http(status, _) = error {
        return (500 ..< 600).contains(status) || status == 408 || status == 429
      }
      if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotConnectToHost, .cannotFindHost,
             .resourceUnavailable, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed, .secureConnectionFailed:
          return true
        default:
          return false
        }
      }
      return false
    }
  }
}
