import Foundation

actor API {
  private var baseUrl: String
  private var headers: [String: String]
  private var maxRetries: Int
  private var initialRetryDelay: TimeInterval

  struct Config {
    let baseUrl: String
    var defaultHeaders: [String: String]?
    var maxRetries: Int?
    var initialRetryDelay: TimeInterval?
  }

  init(config: Config) {
    self.baseUrl = config.baseUrl
    self.headers = config.defaultHeaders ?? [:]
    headers["Content-Type"] = "application/json"
    self.maxRetries = config.maxRetries ?? 3
    self.initialRetryDelay = config.initialRetryDelay ?? 0.5
  }

  func updateConfig(_ config: Config) {
    baseUrl = config.baseUrl
    headers = config.defaultHeaders ?? [:]
    headers["Content-Type"] = "application/json"
    maxRetries = config.maxRetries ?? 3
    initialRetryDelay = config.initialRetryDelay ?? 0.5
  }

  private func post(url: URL, data: some Codable, options: [String: String] = [:], attempt: Int = 0) async -> Result<Data, Error> {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers

    do {
      request.httpBody = try JSONEncoder().encode(data)
    } catch {
      return .failure(error)
    }

    for (key, value) in options {
      request.setValue(value, forHTTPHeaderField: key)
    }

    do {
      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(NSError(domain: "HTTPError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
      }

      guard (200 ... 299).contains(httpResponse.statusCode) else {
        return .failure(NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"]))
      }

      return .success(data)
    } catch {
      if attempt < maxRetries {
        let delay = initialRetryDelay * pow(2.0, Double(attempt))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return await post(url: url, data: data, options: options, attempt: attempt + 1)
      }
      return .failure(error)
    }
  }

  func fetch(path: String, data: some Codable, options: [String: String] = [:]) async -> Result<Data, Error> {
    guard let url = URL(string: baseUrl + path) else {
      return .failure(NSError(domain: "URLError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
    }
    return await post(url: url, data: data, options: options)
  }
}
