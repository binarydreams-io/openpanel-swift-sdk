//
//  OpenPanel+API.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

// MARK: - Public instance API

public extension OpenPanel {
  /// Configure the singleton. Must be called before any other public API.
  /// Calling a second time replaces the config/transport and resets all cached state.
  /// Pass `disabled: true` to queue events until ``ready()`` is called.
  func initialize(_ config: Config, disabled: Bool = false) {
    self.config = config
    transport = Transport(config: config)
    profileId = nil
    groups.removeAll()
    global.removeAll()
    queue.removeAll()
    deviceId = nil
    sessionId = nil
    self.disabled = disabled
  }

  /// Unblock queued events. Pair with `initialize(_:, disabled: true)` for deferred startup.
  func ready() async {
    ensureInitialized()
    disabled = false
    await drainQueue()
  }

  /// Reset cached identity (profile, groups, device, session).
  func clear() {
    ensureInitialized()
    profileId = nil
    groups.removeAll()
    deviceId = nil
    sessionId = nil
  }

  func setGlobalProperties(_ properties: [String: String]) {
    ensureInitialized()
    global.merge(properties) { _, new in new }
  }

  func track(
    _ name: String,
    properties: [String: String]? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) async {
    ensureInitialized()

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

  func identify(_ payload: IdentifyPayload) async {
    ensureInitialized()

    profileId = payload.profileId

    // Attempt to flush queued events. No-op while `disabled` is still `true`.
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

  func upsertGroup(_ payload: GroupPayload) async {
    ensureInitialized()
    await send(.group(payload))
  }

  func setGroup(_ groupId: String) async {
    ensureInitialized()
    guard !groups.contains(groupId) else { return }
    groups.insert(groupId)
    guard let pid = profileId else {
      log("Ignored setGroup('\(groupId)') — no profileId set")
      return
    }
    await send(.assignGroup(AssignGroupPayload(groupIds: [groupId], profileId: pid)))
  }

  func setGroups(_ groupIds: [String]) async {
    ensureInitialized()
    let newGroups = groupIds.filter { !groups.contains($0) }
    guard !newGroups.isEmpty else { return }
    groups.formUnion(newGroups)
    guard let pid = profileId else {
      log("Ignored setGroups(\(newGroups)) — no profileId set")
      return
    }
    await send(.assignGroup(AssignGroupPayload(groupIds: newGroups, profileId: pid)))
  }

  func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) async {
    ensureInitialized()
    guard let pid = profileId ?? self.profileId else {
      log("Ignored increment('\(property)') — no profileId set")
      return
    }
    await send(.increment(IncrementPayload(profileId: pid, property: property, value: value)))
  }

  func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) async {
    ensureInitialized()
    guard let pid = profileId ?? self.profileId else {
      log("Ignored decrement('\(property)') — no profileId set")
      return
    }
    await send(.decrement(DecrementPayload(profileId: pid, property: property, value: value)))
  }

  /// Revenue is a regular `track` event named `"revenue"` with a reserved `__revenue` property.
  /// The server requires a client secret for revenue unless the project allows unsafe revenue.
  func revenue(_ amount: Double, properties: [String: String]? = nil, deviceId: String? = nil) async {
    var props = properties ?? [:]
    props["__revenue"] = String(amount)
    if let deviceId {
      props["__deviceId"] = deviceId
    }
    await track("revenue", properties: props)
  }

  func flush() async {
    ensureInitialized()
    await drainQueue()
  }
}

// MARK: - Static facade (fire-and-forget)

public extension OpenPanel {
  /// Configure the singleton. Hops onto the actor asynchronously;
  /// the call returns immediately.
  static func initialize(_ config: Config, disabled: Bool = false) {
    Task { await shared.initialize(config, disabled: disabled) }
  }

  static func ready() {
    Task { await shared.ready() }
  }

  static func clear() {
    Task { await shared.clear() }
  }

  static func setGlobalProperties(_ properties: [String: String]) {
    Task { await shared.setGlobalProperties(properties) }
  }

  static func track(
    _ name: String,
    properties: [String: String]? = nil,
    profileId: ProfileId? = nil,
    groups: [String]? = nil
  ) {
    Task { await shared.track(name, properties: properties, profileId: profileId, groups: groups) }
  }

  static func identify(_ payload: IdentifyPayload) {
    Task { await shared.identify(payload) }
  }

  static func upsertGroup(_ payload: GroupPayload) {
    Task { await shared.upsertGroup(payload) }
  }

  static func setGroup(_ groupId: String) {
    Task { await shared.setGroup(groupId) }
  }

  static func setGroups(_ groupIds: [String]) {
    Task { await shared.setGroups(groupIds) }
  }

  static func increment(property: String, value: Double? = nil, profileId: ProfileId? = nil) {
    Task { await shared.increment(property: property, value: value, profileId: profileId) }
  }

  static func decrement(property: String, value: Double? = nil, profileId: ProfileId? = nil) {
    Task { await shared.decrement(property: property, value: value, profileId: profileId) }
  }

  static func revenue(_ amount: Double, properties: [String: String]? = nil, deviceId: String? = nil) {
    Task { await shared.revenue(amount, properties: properties, deviceId: deviceId) }
  }

  static func flush() {
    Task { await shared.flush() }
  }

  static var deviceId: String? {
    get async { await shared.deviceId }
  }

  static var sessionId: String? {
    get async { await shared.sessionId }
  }
}
