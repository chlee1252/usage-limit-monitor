import Foundation

public enum MenuBarSource: String, Codable, CaseIterable, Sendable {
  case highest, codex, claude, gemini, iconOnly

  public var provider: Provider? { Provider(rawValue: rawValue) }

  public var name: String {
    switch self {
    case .highest: return "전체 중 가장 높은 사용률"
    case .iconOnly: return "아이콘만 표시"
    default: return provider?.name ?? ""
    }
  }
}

public struct MenuBarReading: Equatable, Sendable {
  public let provider: Provider
  public let window: UsageWindow
  public var percent: Int { Int(window.usedPercent.rounded()) }

  public static func resolve(
    preferences: Preferences, snapshots: [Provider: Snapshot],
    failedProviders: Set<Provider> = [], now: Date = Date()
  ) -> MenuBarReading? {
    guard preferences.menuBarSource != .iconOnly else { return nil }
    let selected = preferences.menuBarSource.provider
    let candidates = Provider.allCases.flatMap { provider -> [MenuBarReading] in
      guard preferences.enabled.contains(provider), !failedProviders.contains(provider),
        selected == nil || selected == provider,
        let snapshot = snapshots[provider], snapshot.isFresh(at: now)
      else { return [] }
      return snapshot.windows.compactMap { window in
        guard !window.expired(at: now), window.usedPercent.isFinite,
          (0...100).contains(window.usedPercent),
          selected == nil || preferences.menuBarWindowID == nil
            || preferences.menuBarWindowID == window.id
        else { return nil }
        return MenuBarReading(provider: provider, window: window)
      }
    }
    return candidates.max { $0.window.usedPercent < $1.window.usedPercent }
  }
}
