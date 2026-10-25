import Foundation

public struct Preferences: Codable {
  public var enabled: Set<Provider> = Set(Provider.allCases)
  public var threshold = 80
  public var notifications = false
  public var codexExecutable = CodexClient.locateExecutable()
  public var alertMode: AlertMode = .threshold
  public var alertInterval = 10

  public init() {}

  public var alertRule: AlertRule {
    AlertRule(mode: alertMode, threshold: threshold, interval: alertInterval)
  }

  private enum CodingKeys: String, CodingKey {
    case enabled, threshold, notifications, codexExecutable, alertMode, alertInterval
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    enabled =
      try values.decodeIfPresent(Set<Provider>.self, forKey: .enabled) ?? Set(Provider.allCases)
    threshold = min(100, max(10, try values.decodeIfPresent(Int.self, forKey: .threshold) ?? 80))
    notifications = try values.decodeIfPresent(Bool.self, forKey: .notifications) ?? false
    codexExecutable =
      try values.decodeIfPresent(String.self, forKey: .codexExecutable)
      ?? CodexClient.locateExecutable()
    alertMode = try values.decodeIfPresent(AlertMode.self, forKey: .alertMode) ?? .threshold
    let interval = try values.decodeIfPresent(Int.self, forKey: .alertInterval) ?? 10
    alertInterval = [5, 10, 20, 25, 50].contains(interval) ? interval : 10
  }
}
