import Foundation

public enum AlertMode: String, Codable, CaseIterable, Sendable {
  case threshold, increments
}

public struct AlertRule: Equatable, Sendable {
  public let mode: AlertMode
  public let threshold: Int
  public let interval: Int

  public init(mode: AlertMode = .threshold, threshold: Int = 80, interval: Int = 10) {
    self.mode = mode
    self.threshold = min(100, max(10, threshold))
    self.interval = min(50, max(5, interval))
  }

  public var milestones: [Int] {
    mode == .threshold ? [threshold] : (1...100).filter { $0 % interval == 0 || $0 == 100 }
  }

  public var summary: String {
    mode == .threshold ? "\(threshold)%에서 알림" : "\(interval)%마다 알림"
  }
}

public struct UsageAlert: Sendable {
  public let window: UsageWindow
  public let milestone: Int
}

extension AlertLedger {
  public func key(provider: Provider, alert: UsageAlert, rule: AlertRule) -> String {
    if rule.mode == .threshold {
      return key(provider: provider, window: alert.window, threshold: rule.threshold)
    }
    return
      "interval|\(key(provider: provider, window: alert.window, threshold: rule.interval))|\(alert.milestone)"
  }

  /// Coalesce skipped milestones into one notification at the highest reached milestone.
  /// The ledger is only advanced after the notification has been accepted by the OS.
  public func pending(_ snapshot: Snapshot, rule: AlertRule, now: Date = Date()) -> [UsageAlert] {
    guard snapshot.isFresh(at: now) else { return [] }
    return snapshot.windows.compactMap { window in
      guard !window.expired(at: now), window.usedPercent.isFinite,
        let milestone = rule.milestones.last(where: { Double($0) <= window.usedPercent })
      else { return nil }
      let alert = UsageAlert(window: window, milestone: milestone)
      return sent.contains(key(provider: snapshot.provider, alert: alert, rule: rule)) ? nil : alert
    }
  }

  public mutating func mark(provider: Provider, alert: UsageAlert, rule: AlertRule) {
    // Record lower milestones too: a later decrease must not replay old alerts.
    for milestone in rule.milestones where milestone <= alert.milestone {
      sent.insert(
        key(
          provider: provider,
          alert: UsageAlert(window: alert.window, milestone: milestone), rule: rule))
    }
  }
}
