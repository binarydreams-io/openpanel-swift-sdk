//
//  PreconditionTests.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

@testable import OpenPanel
import Testing

@Suite("Preconditions")
struct PreconditionTests {
  /// The README and `ensureInitialized()` doc-comment promise a hard crash when any
  /// public API is used before `initialize`. An exit test guards that contract: if it
  /// ever silently degrades to a no-op, this suite fails.
  @Test
  func `calling track before initialize crashes the process`() async {
    await #expect(processExitsWith: ExitTest.Condition.failure) {
      // Fresh subprocess → singleton is uninitialized → ensureInitialized() traps.
      await OpenPanel.shared.track("event")
    }
  }

  @Test
  func `calling identify before initialize crashes the process`() async {
    await #expect(processExitsWith: ExitTest.Condition.failure) {
      await OpenPanel.shared.identify(IdentifyPayload(profileId: "u"))
    }
  }
}
