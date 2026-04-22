import Foundation

/// Type-erased view of a queued event (for `filter`).
public enum OpenPanelEvent: Sendable {
  case track(TrackPayload)
  case identify(IdentifyPayload)
  case group(GroupPayload)
  case assignGroup(AssignGroupPayload)
  case increment(IncrementPayload)
  case decrement(DecrementPayload)

  init(_ envelope: TrackEnvelope) {
    switch envelope {
    case let .track(payload): self = .track(payload)
    case let .identify(payload): self = .identify(payload)
    case let .group(payload): self = .group(payload)
    case let .assignGroup(payload): self = .assignGroup(payload)
    case let .increment(payload): self = .increment(payload)
    case let .decrement(payload): self = .decrement(payload)
    }
  }
}
