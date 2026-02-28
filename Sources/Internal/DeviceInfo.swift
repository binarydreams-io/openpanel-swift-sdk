import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(iOS)
import WebKit
#elseif os(macOS)
import AppKit
import WebKit
#endif

class DeviceInfo {
  struct Info {
    var brand: String = "Apple"
    var os: String // tvOS
    var osVersion: String // 18.4
    var device: String // smarttv
    var model: String // AppleTV6,2

    var osVersionUnderscored: String {
      osVersion.replacingOccurrences(of: ".", with: "_")
    }
  }

  static func getInfo() async -> Info {
    #if os(iOS)
    return await getiOSInfo()
    #elseif os(macOS)
    return getMacOSInfo()
    #elseif os(tvOS)
    return await getTvOSInfo()
    #endif
  }

  static func getUserAgent() async -> String {
    #if os(iOS)
    return await getiOSUserAgent()
    #elseif os(macOS)
    return getMacOSUserAgent(getMacOSInfo())
    #elseif os(tvOS)
    return getTvOSUserAgent(await getTvOSInfo())
    #endif
  }

  #if os(iOS)
  @MainActor
  static func getiOSInfo() -> Info {
    let device = UIDevice.current
    // TODO: Get specific iPhone model
    return Info(
      os: "iOS",
      osVersion: device.systemVersion,
      device: "mobile",
      model: "iPhone"
    )
  }

  @MainActor
  private static func getiOSUserAgent() async -> String {
    if !isRunningInExtension() {
      let webView = WKWebView(frame: .zero)
      let userAgent = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
        webView.evaluateJavaScript("navigator.userAgent") { result, _ in
          continuation.resume(returning: result as? String ?? "")
        }
      }
      let agent = userAgent.isEmpty ? "Mozilla/5.0 (iPhone; U)" : userAgent
      return agent + " OpenPanel/\(OpenPanel.sdkVersion)"
    } else {
      return getBasicUserAgent()
    }
  }

  private static func isRunningInExtension() -> Bool {
    Bundle.main.bundleURL.pathExtension == "appex"
  }
  #endif

  #if canImport(UIKit)
  @MainActor
  private static func getBasicUserAgent() -> String {
    let device = UIDevice.current
    let systemVersion = device.systemVersion
    let model = device.model
    let systemName = device.systemName

    var userAgent = "Mozilla/5.0 (\(model); \(systemName) \(systemVersion.replacingOccurrences(of: ".", with: "_")); like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/\(systemVersion)"
    userAgent += " OpenPanel/\(OpenPanel.sdkVersion)"
    return userAgent
  }
  #endif

  #if os(macOS)
  static func getMacOSInfo() -> Info {
    let processInfo = ProcessInfo.processInfo
    let osVersion = processInfo.operatingSystemVersionString
    let versionParts = osVersion.components(separatedBy: " ")
    let version = versionParts.count > 1 ? versionParts[1] : "Unknown"

    return Info(
      os: "Mac OS",
      osVersion: version,
      device: "desktop",
      model: getMacModelIdentifier() ?? "Unknown"
    )
  }

  private static func getMacOSUserAgent(_ info: Info) -> String {
    let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X \(info.osVersionUnderscored); \(info.model)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15"
    return userAgent + " OpenPanel/\(OpenPanel.sdkVersion)"
  }

  static func getMacModelIdentifier() -> String? {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: Int(size))
    if sysctlbyname("hw.model", &machine, &size, nil, 0) != 0 {
      return nil
    }
    let data = machine.prefix(while: { $0 != 0 }).map { UInt8($0) }
    return String(decoding: data, as: UTF8.self)
  }
  #endif

  #if os(tvOS)
  static func getAppleTVModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let mirror = Mirror(reflecting: systemInfo.machine)
    return mirror.children.reduce(into: "") { id, child in
      guard let byte = child.value as? Int8, byte != 0 else { return }
      id.append(String(UnicodeScalar(UInt8(byte))))
    }
  }

  @MainActor
  static func getTvOSInfo() -> Info {
    let device = UIDevice.current
    return Info(
      os: "tvOS",
      osVersion: device.systemVersion,
      device: "smarttv",
      model: getAppleTVModelIdentifier()
    )
  }

  private static func getTvOSUserAgent(_ info: Info) -> String {
    var userAgent = "Mozilla/5.0 (Apple TV; \(info.model); \(info.os) \(info.osVersionUnderscored)) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/\(info.osVersion)"
    userAgent += " OpenPanel/\(OpenPanel.sdkVersion)"
    return userAgent
  }
  #endif
}
