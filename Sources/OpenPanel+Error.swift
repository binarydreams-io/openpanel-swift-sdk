//
//  OpenPanel+Error.swift
//  OpenPanel
//
//  Created by Leonid Frolov on 30.04.2026.
//

import Foundation

public extension OpenPanel {
  /// Errors surfaced by the transport layer.
  /// Public SDK methods never throw — they catch and log internally.
  enum Error: Swift.Error, Sendable, Equatable {
    /// The server returned a response that wasn't an `HTTPURLResponse`.
    case invalidResponse
    /// The server returned a non-2xx, non-401 status after retries were exhausted.
    case http(status: Int, body: String?)
    /// A networking failure (DNS, TLS, lost connection) after retries were exhausted.
    case transport(message: String)
  }
}
