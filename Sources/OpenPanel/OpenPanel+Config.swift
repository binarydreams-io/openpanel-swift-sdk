import Foundation

extension OpenPanel {
  public struct Config: Sendable {
    public var clientId: String
    public var clientSecret: String?
    public var apiURL: URL
    public var sdkName: String
    public var sdkVersion: String
    public var maxRetries: Int
    public var initialRetryDelay: Duration
    public var disabled: Bool
    public var debug: Bool
    /// Optional filter: return false to drop an event before it goes out.
    public var filter: (@Sendable (OpenPanelEvent) -> Bool)?

    public init(
      clientId: String,
      clientSecret: String? = nil,
      apiURL: URL = URL(string: "https://api.openpanel.dev")!,
      sdkName: String = "swift",
      sdkVersion: String = OpenPanel.SDK.version,
      maxRetries: Int = 3,
      initialRetryDelay: Duration = .milliseconds(500),
      disabled: Bool = false,
      debug: Bool = false,
      filter: (@Sendable (OpenPanelEvent) -> Bool)? = nil
    ) {
      self.clientId = clientId
      self.clientSecret = clientSecret
      self.apiURL = apiURL
      self.sdkName = sdkName
      self.sdkVersion = sdkVersion
      self.maxRetries = maxRetries
      self.initialRetryDelay = initialRetryDelay
      self.disabled = disabled
      self.debug = debug
      self.filter = filter
    }
  }
}
