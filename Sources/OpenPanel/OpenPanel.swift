import Foundation

/// OpenPanel analytics client.
///
/// Usage is via the shared singleton: call `OpenPanel.initialize(config:)` once at
/// app start, then use the static API (`OpenPanel.track`, `OpenPanel.identify`, …).
/// Any call made before `initialize` throws `OpenPanel.Error.notInitialized`.
///
/// Behaviour (mirrors the JS SDK):
/// - Events are sent immediately to `POST /track`.
/// - When `disabled` is true, events are queued in memory until `ready()` is called.
/// - The server returns `{ deviceId, sessionId }` which the client caches and reuses.
/// - Global properties are merged into every `track` event.
/// - A `filter` closure can drop events before they leave the process.
///
/// Queue is in-memory only: it does NOT persist across app restarts.
public actor OpenPanel {
  // MARK: - Singleton

  public static let shared = OpenPanel()

  // MARK: - State

  private var config: Config?
  private var transport: Transport?

  private var profileId: ProfileId?
  private var groups: Set<String> = []
  private var global: Properties = [:]
  private var queue: [TrackEnvelope] = []

  /// Server-issued identifiers. Populated after the first successful request.
  public private(set) var deviceId: String?
  public private(set) var sessionId: String?

  // MARK: - Init

  private init() {}

  // MARK: - Initialize

  /// Configure the singleton. Must be called before any other public API.
  /// Calling a second time replaces the config/transport and resets all cached state.
  public func initialize(config: Config, session: URLSession = .shared) {
    self.config = config
    self.transport = Transport(config: config, session: session)
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
  }

  public static func initialize(config: Config, session: URLSession = .shared) async {
    await shared.initialize(config: config, session: session)
  }

  // MARK: - Lifecycle

  /// Unblock queued events. Use together with `config.disabled = true` for deferred startup.
  public func ready() async throws {
    try requireInitialized()
    config?.disabled = false
    await drainQueue()
  }

  /// Reset cached identity (profile, groups, device, session).
  public func clear() throws {
    try requireInitialized()
    profileId = nil
    groups.removeAll()
    deviceId = nil
    sessionId = nil
  }

  // MARK: - Global properties

  public func setGlobalProperties(_ properties: Properties) throws {
    try requireInitialized()
    global.merge(properties) { _, new in new }
  }

  // MARK: - Public API

  public func track(
    _ name: String,
    properties: Properties? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) async throws {
    try requireInitialized()

    var merged = global
    if let properties { merged.merge(properties) { _, new in new } }

    let eventGroups = Array(self.groups.union(groups ?? []))
    let payload = TrackPayload(
      name: name,
      properties: merged.isEmpty ? nil : merged,
      profileId: profileId ?? self.profileId,
      groups: eventGroups.isEmpty ? nil : eventGroups
    )
    await send(.track(payload))
  }

  public func identify(_ payload: IdentifyPayload) async throws {
    try requireInitialized()

    profileId = payload.profileId

    // Flush anything we were holding for a profile.
    await drainQueue()

    // Only hit the API if caller supplied more than just the ID.
    let hasExtras = payload.firstName != nil || payload.lastName != nil
      || payload.email != nil || payload.avatar != nil
      || (payload.properties?.isEmpty == false)

    guard hasExtras else { return }

    var merged = payload
    if let props = payload.properties {
      var combined = global
      combined.merge(props) { _, new in new }
      merged.properties = combined
    } else if !global.isEmpty {
      merged.properties = global
    }

    await send(.identify(merged))
  }

  public func upsertGroup(_ payload: GroupPayload) async throws {
    try requireInitialized()
    await send(.group(payload))
  }

  public func setGroup(_ groupId: String) async throws {
    try requireInitialized()
    groups.insert(groupId)
    await send(.assignGroup(AssignGroupPayload(groupIds: [groupId], profileId: profileId)))
  }

  public func setGroups(_ groupIds: [String]) async throws {
    try requireInitialized()
    groups.formUnion(groupIds)
    await send(.assignGroup(AssignGroupPayload(groupIds: groupIds, profileId: profileId)))
  }

  public func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) async throws {
    try requireInitialized()
    guard let pid = profileId ?? self.profileId else { return }
    await send(.increment(IncrementPayload(profileId: pid, property: property, value: value)))
  }

  public func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) async throws {
    try requireInitialized()
    guard let pid = profileId ?? self.profileId else { return }
    await send(.decrement(DecrementPayload(profileId: pid, property: property, value: value)))
  }

  /// Revenue is a regular `track` event named `"revenue"` with a reserved `__revenue` property.
  /// The server requires a client secret for revenue unless the project allows unsafe revenue.
  public func revenue(_ amount: Int, properties: Properties? = nil, deviceId: String? = nil) async throws {
    var props = properties ?? [:]
    props["__revenue"] = AnyCodable(Int64(amount))
    if let deviceId {
      props["__deviceId"] = AnyCodable(deviceId)
    }
    try await track("revenue", properties: props)
  }

  public func flush() async throws {
    try requireInitialized()
    await drainQueue()
  }

  // MARK: - Static facade

  public static func ready() async throws {
    try await shared.ready()
  }

  public static func clear() async throws {
    try await shared.clear()
  }

  public static func setGlobalProperties(_ properties: Properties) async throws {
    try await shared.setGlobalProperties(properties)
  }

  public static func track(
    _ name: String,
    properties: Properties? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) async throws {
    try await shared.track(name, properties: properties, profileId: profileId, groups: groups)
  }

  public static func identify(_ payload: IdentifyPayload) async throws {
    try await shared.identify(payload)
  }

  public static func upsertGroup(_ payload: GroupPayload) async throws {
    try await shared.upsertGroup(payload)
  }

  public static func setGroup(_ groupId: String) async throws {
    try await shared.setGroup(groupId)
  }

  public static func setGroups(_ groupIds: [String]) async throws {
    try await shared.setGroups(groupIds)
  }

  public static func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) async throws {
    try await shared.increment(property: property, value: value, profileId: profileId)
  }

  public static func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) async throws {
    try await shared.decrement(property: property, value: value, profileId: profileId)
  }

  public static func revenue(_ amount: Int, properties: Properties? = nil, deviceId: String? = nil) async throws {
    try await shared.revenue(amount, properties: properties, deviceId: deviceId)
  }

  public static func flush() async throws {
    try await shared.flush()
  }

  public static var deviceId: String? {
    get async { await shared.deviceId }
  }

  public static var sessionId: String? {
    get async { await shared.sessionId }
  }

  // MARK: - Internal (testing)

  /// Fully un-configures the singleton. Only for tests — `@testable import OpenPanel`
  /// is required to reach it. Not part of the public API.
  internal func resetForTesting() {
    config = nil
    transport = nil
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
  }

  // MARK: - Private

  private func requireInitialized() throws {
    guard config != nil, transport != nil else {
      throw Error.notInitialized
    }
  }

  private func send(_ envelope: TrackEnvelope) async {
    guard let config, let transport else { return }

    if let filter = config.filter, !filter(OpenPanelEvent(envelope)) {
      return
    }

    if config.disabled {
      queue.append(stamped(envelope))
      log("queued", envelope)
      return
    }

    log("send", envelope)
    do {
      let response: TrackResponse? = try await transport.post(path: "/track", body: envelope)
      if let response {
        deviceId = response.deviceId
        sessionId = response.sessionId
      }
    } catch {
      log("send error", error)
    }
  }

  /// JS SDK stamps queued `track` events with `__timestamp` so the server knows when
  /// the event actually happened (not when it was flushed).
  private func stamped(_ envelope: TrackEnvelope) -> TrackEnvelope {
    guard case var .track(payload) = envelope else { return envelope }
    var props = payload.properties ?? [:]
    if props["__timestamp"] == nil {
      props["__timestamp"] = AnyCodable(ISO8601DateFormatter.openPanel.string(from: Date()))
    }
    payload.properties = props
    return .track(payload)
  }

  private func drainQueue() async {
    guard let config, !config.disabled else { return }
    let pending = queue
    queue.removeAll()
    for envelope in pending {
      await send(envelope)
    }
  }

  private func log(_ label: String, _ value: Any) {
    if config?.debug == true {
      print("[OpenPanel] \(label):", value)
    }
  }
}

// MARK: - Helpers

private extension ISO8601DateFormatter {
  nonisolated(unsafe) static let openPanel: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
