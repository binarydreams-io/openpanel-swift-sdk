import Testing

/// Parent suite for tests that share `MockURLProtocol.registry`.
/// `.serialized` on the parent serializes all nested suites, preventing
/// cross-suite handler clobbering that plain `@Suite(.serialized)` — which
/// only serializes within a single suite — does not catch.
@Suite(.serialized)
enum MockBackedSuite {}
