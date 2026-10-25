import CoreFoundation
import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
  case codex, claude, gemini
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .codex: return "Codex"
    case .claude: return "Claude Code"
    case .gemini: return "Gemini"
    }
  }
}

public struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let usedPercent: Double
  public let resetsAt: Date?
  public init(id: String, name: String, usedPercent: Double, resetsAt: Date?) {
    self.id = id
    self.name = name
    self.usedPercent = usedPercent
    self.resetsAt = resetsAt
  }
  public func expired(at date: Date) -> Bool { resetsAt.map { $0 <= date } ?? false }
}

public struct Snapshot: Codable, Equatable, Sendable {
  public let provider: Provider
  public let windows: [UsageWindow]
  public let observedAt: Date
  public let source: String
  public init(provider: Provider, windows: [UsageWindow], observedAt: Date = Date(), source: String)
  {
    self.provider = provider
    self.windows = windows
    self.observedAt = observedAt
    self.source = source
  }
  public func isFresh(at date: Date) -> Bool {
    date.timeIntervalSince(observedAt) >= -60 && date.timeIntervalSince(observedAt) < 900
  }
}

public enum UsageError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

public enum UsageParser {
  public static func codex(_ data: Data, now: Date = Date()) throws -> Snapshot {
    let root = try object(data)
    let result = root["result"] as? [String: Any] ?? root
    var windows: [UsageWindow] = []
    let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
    if let buckets, !buckets.isEmpty {
      for key in buckets.keys.sorted() {
        windows += codexWindows(buckets[key]!, prefix: key, multiple: buckets.count > 1)
      }
    } else if let bucket = result["rateLimits"] as? [String: Any] {
      windows = codexWindows(
        bucket, prefix: bucket["limitId"] as? String ?? "codex", multiple: false)
    }
    guard !windows.isEmpty else {
      throw UsageError.message("한도 정보가 없습니다. Codex에 ChatGPT 계정으로 로그인해 주세요.")
    }
    return Snapshot(provider: .codex, windows: windows, observedAt: now, source: "자동 조회")
  }
  private static func codexWindows(_ bucket: [String: Any], prefix: String, multiple: Bool)
    -> [UsageWindow]
  {
    ["primary", "secondary"].compactMap { slot in
      guard let value = bucket[slot] as? [String: Any],
        let percent = percentage(value["usedPercent"])
      else { return nil }
      let minutes = value["windowDurationMins"] as? Int
      let label: String
      if let minutes, minutes > 0 {
        if minutes % 1440 == 0 {
          label = "\(minutes / 1440)일"
        } else if minutes % 60 == 0 {
          label = "\(minutes / 60)시간"
        } else {
          label = "\(minutes)분"
        }
      } else {
        label = slot == "primary" ? "기본 한도" : "추가 한도"
      }
      return UsageWindow(
        id: "\(prefix).\(slot)",
        name: multiple ? "\(bucket["limitName"] as? String ?? prefix) · \(label)" : label,
        usedPercent: percent, resetsAt: epoch(value["resetsAt"]))
    }
  }
  public static func claude(_ data: Data, now: Date = Date()) throws -> Snapshot {
    let root = try object(data)
    let limits = root["rate_limits"] as? [String: Any] ?? [:]
    let windows = [("five_hour", "5시간"), ("seven_day", "7일"), ("spend_limit", "지출 한도")].compactMap {
      key, name -> UsageWindow? in
      guard let value = limits[key] as? [String: Any],
        let percent = percentage(value["used_percentage"])
      else { return nil }
      return UsageWindow(
        id: key, name: name, usedPercent: percent, resetsAt: epoch(value["resets_at"]))
    }
    // An empty update intentionally clears old quota data (e.g. after an account change).
    return Snapshot(provider: .claude, windows: windows, observedAt: now, source: "Claude 상태 표시줄")
  }
  private static func object(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw UsageError.message("올바른 JSON 데이터가 아닙니다.")
    }
    return object
  }
  private static func percentage(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let percent = number.doubleValue
    return percent.isFinite && percent >= 0 && percent <= 100 ? percent : nil
  }
  private static func epoch(_ value: Any?) -> Date? {
    guard let value = value as? Double, value.isFinite, value > 0 else { return nil }
    return Date(timeIntervalSince1970: value)
  }
}

public struct AlertLedger: Codable {
  public var sent: Set<String> = []
  public init() {}
  public func key(provider: Provider, window: UsageWindow, threshold: Int) -> String {
    "\(provider.rawValue)|\(window.id)|\(window.resetsAt?.timeIntervalSince1970 ?? 0)|\(threshold)"
  }
  public func eligible(_ snapshot: Snapshot, threshold: Int, now: Date = Date()) -> [UsageWindow] {
    guard snapshot.isFresh(at: now) else { return [] }
    return snapshot.windows.filter {
      !$0.expired(at: now) && $0.usedPercent >= Double(threshold)
        && !sent.contains(key(provider: snapshot.provider, window: $0, threshold: threshold))
    }
  }
  public mutating func mark(provider: Provider, window: UsageWindow, threshold: Int) {
    sent.insert(key(provider: provider, window: window, threshold: threshold))
  }
}
