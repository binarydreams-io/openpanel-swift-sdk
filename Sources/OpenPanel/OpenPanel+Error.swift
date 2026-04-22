import Foundation

extension OpenPanel {
  public enum Error: Swift.Error, Sendable, Equatable {
    /// Thrown by any public API call made before `OpenPanel.initialize(config:)`.
    case notInitialized
    case invalidResponse
    case http(status: Int, body: String?)
    case unauthorized
    case transport(message: String)
  }
}
