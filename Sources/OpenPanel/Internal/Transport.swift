import Foundation

/// Thin HTTP layer mirroring `Api` from the JS SDK:
/// POST JSON, retry transient failures with exponential backoff,
/// treat 401 as a silent drop (no retry, returns nil).
struct Transport {
  let config: OpenPanel.Config
  let session: URLSession

  init(config: OpenPanel.Config, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  func post<Res: Decodable>(path: String, body: some Encodable) async throws -> Res? {
    let url = config.apiURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))

    let encoder = JSONEncoder()
    let data = try encoder.encode(body)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = data
    applyHeaders(&request)

    return try await send(request: request, attempt: 0)
  }

  func get<Res: Decodable>(path: String) async throws -> Res? {
    let url = config.apiURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    applyHeaders(&request)
    return try await send(request: request, attempt: 0)
  }

  // MARK: - Private

  private func applyHeaders(_ request: inout URLRequest) {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.clientId, forHTTPHeaderField: "openpanel-client-id")
    if let secret = config.clientSecret {
      request.setValue(secret, forHTTPHeaderField: "openpanel-client-secret")
    }
    request.setValue(config.sdkName, forHTTPHeaderField: "openpanel-sdk-name")
    request.setValue(config.sdkVersion, forHTTPHeaderField: "openpanel-sdk-version")
  }

  private func send<Res: Decodable>(request: URLRequest, attempt: Int) async throws -> Res? {
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw OpenPanel.Error.invalidResponse }

      switch http.statusCode {
      case 200, 202:
        guard !data.isEmpty else { return nil }
        // Server may return plain text `"Duplicate event"` with 200 — treat as success-with-no-body.
        if let text = String(data: data, encoding: .utf8), !text.hasPrefix("\""), !text.hasPrefix("{"), !text.hasPrefix("[") {
          return nil
        }
        return try JSONDecoder().decode(Res.self, from: data)

      case 401:
        // JS SDK contract: silent drop, no retry.
        return nil

      default:
        let body = String(data: data, encoding: .utf8)
        throw OpenPanel.Error.http(status: http.statusCode, body: body)
      }
    } catch {
      if attempt < config.maxRetries, isRetryable(error) {
        let delay = config.initialRetryDelay * (1 << attempt)
        try await Task.sleep(for: delay)
        return try await send(request: request, attempt: attempt + 1)
      }
      if let openPanelError = error as? OpenPanel.Error { throw openPanelError }
      throw OpenPanel.Error.transport(message: String(describing: error))
    }
  }

  private func isRetryable(_ error: any Error) -> Bool {
    if case let OpenPanel.Error.http(status, _) = error {
      return (500 ..< 600).contains(status) || status == 408 || status == 429
    }
    // Network / URLError — retry.
    return true
  }
}
