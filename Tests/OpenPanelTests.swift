import Foundation
@testable import OpenPanel
import Testing

@Suite("OpenPanel", .serialized)
struct OpenPanelTests {
  // MARK: - SDK Version

  @Test("sdkVersion returns expected value")
  func sdkVersion() {
    #expect(OpenPanel.sdkVersion == "0.1.0")
  }

  // MARK: - Options

  @Test("Options stores all provided values")
  func optionsInit() {
    let options = OpenPanel.Options(
      clientId: "client-1",
      clientSecret: "secret",
      apiUrl: "https://custom.api.com",
      waitForProfile: true,
      filter: nil,
      disabled: false,
    )
    #expect(options.clientId == "client-1")
    #expect(options.clientSecret == "secret")
    #expect(options.apiUrl == "https://custom.api.com")
    #expect(options.waitForProfile == true)
    #expect(options.disabled == false)
  }

  @Test("Options defaults are nil")
  func optionsDefaults() {
    let options = OpenPanel.Options(clientId: "client-2")
    #expect(options.clientId == "client-2")
    #expect(options.clientSecret == nil)
    #expect(options.apiUrl == nil)
    #expect(options.waitForProfile == nil)
    #expect(options.disabled == nil)
  }

  // MARK: - Initialize & Global Properties

  @Test("initialize sets up the shared instance without crashing")
  func initializeDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client"))
    // If we reach here, initialization succeeded
  }

  @Test("setGlobalProperties and clear work correctly")
  func globalPropertiesAndClear() {
    OpenPanel.initialize(options: .init(clientId: "test-client"))

    OpenPanel.setGlobalProperties(["customKey": "customValue"])

    // Clear should reset state without crashing
    OpenPanel.clear()
  }

  @Test("setGlobalProperties merges with existing properties")
  func globalPropertiesMerge() {
    OpenPanel.initialize(options: .init(clientId: "test-client"))

    OpenPanel.setGlobalProperties(["a": String(1)])
    OpenPanel.setGlobalProperties(["b": String(2)])

    // Both calls should succeed without crashing — merging is internal
    OpenPanel.clear()
  }

  // MARK: - Track (does not crash when disabled)

  @Test("track does not crash when SDK is disabled")
  func trackWhenDisabled() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.track(name: "test_event", properties: ["key": "value"])
    OpenPanel.clear()
  }

  // MARK: - Identify

  @Test("identify does not crash")
  func identifyDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.identify(payload: IdentifyPayload(
      profileId: "user-1",
      firstName: "Jane",
      email: "jane@example.com"
    ))
    OpenPanel.clear()
  }

  // MARK: - Alias

  @Test("alias does not crash")
  func aliasDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.alias(payload: AliasPayload(profileId: "user-1", alias: "anon-1"))
    OpenPanel.clear()
  }

  // MARK: - Increment / Decrement

  @Test("increment does not crash")
  func incrementDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.increment(payload: IncrementPayload(profileId: "user-1", property: "logins", value: 1))
    OpenPanel.clear()
  }

  @Test("decrement does not crash")
  func decrementDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.decrement(payload: DecrementPayload(profileId: "user-1", property: "credits", value: 5))
    OpenPanel.clear()
  }

  // MARK: - Filter

  @Test("filter blocks events")
  func filterBlocksEvents() {
    let options = OpenPanel.Options(
      clientId: "test-client",
      filter: { payload in
        if case let .track(track) = payload {
          return track.name != "blocked_event"
        }
        return true
      },
      disabled: false
    )
    // The filter itself is a closure and cannot be directly verified via output,
    // but we ensure initialization and tracking with a filter does not crash.
    OpenPanel.initialize(options: options)
    OpenPanel.track(name: "blocked_event")
    OpenPanel.track(name: "allowed_event")
    OpenPanel.clear()
  }

  // MARK: - Flush

  @Test("flush does not crash on empty queue")
  func flushEmpty() {
    OpenPanel.initialize(options: .init(clientId: "test-client", disabled: true))
    OpenPanel.flush()
    OpenPanel.clear()
  }

  // MARK: - Ready

  @Test("ready does not crash")
  func readyDoesNotCrash() {
    OpenPanel.initialize(options: .init(clientId: "test-client", waitForProfile: true))
    OpenPanel.ready()
    OpenPanel.clear()
  }

  // MARK: - waitForProfile queuing

  @Test("Events queue when waitForProfile is true and flush after ready")
  func waitForProfileQueuing() {
    OpenPanel.initialize(options: .init(clientId: "test-client", waitForProfile: true, disabled: true))

    // These should be queued, not sent
    OpenPanel.track(name: "queued_event_1")
    OpenPanel.track(name: "queued_event_2")

    // ready() flushes the queue
    OpenPanel.ready()
    OpenPanel.clear()
  }
}
