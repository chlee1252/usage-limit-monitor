import XCTest

@testable import UsageCore

final class MenuBarSelectionTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func snapshot(
    _ provider: Provider, primary: Double, secondary: Double? = nil,
    age: Double = 0, expired: Bool = false
  ) -> Snapshot {
    var windows = [
      UsageWindow(
        id: "primary", name: "5시간", usedPercent: primary,
        resetsAt: now.addingTimeInterval(expired ? -1 : 1000))
    ]
    if let secondary {
      windows.append(
        UsageWindow(
          id: "secondary", name: "7일", usedPercent: secondary,
          resetsAt: now.addingTimeInterval(2000)))
    }
    return Snapshot(
      provider: provider, windows: windows, observedAt: now.addingTimeInterval(-age), source: "test"
    )
  }

  func testAutomaticUsesOnlyEnabledFreshSuccessfulWindows() {
    var preferences = Preferences()
    let snapshots: [Provider: Snapshot] = [
      .codex: snapshot(.codex, primary: 42, secondary: 68),
      .claude: snapshot(.claude, primary: 83),
      .gemini: snapshot(.gemini, primary: 99, age: 1000),
    ]
    XCTAssertEqual(
      MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now)?.provider,
      .claude)
    preferences.enabled.remove(.claude)
    XCTAssertEqual(
      MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now)?.percent, 68)
    XCTAssertNil(
      MenuBarReading.resolve(
        preferences: preferences, snapshots: snapshots,
        failedProviders: [.codex], now: now))
  }

  func testSelectedProviderAndWindowDoNotShowAnotherUsage() {
    var preferences = Preferences()
    preferences.menuBarSource = .codex
    let snapshots: [Provider: Snapshot] = [
      .codex: snapshot(.codex, primary: 42, secondary: 68),
      .claude: snapshot(.claude, primary: 99),
    ]
    XCTAssertEqual(
      MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now)?.percent, 68)
    preferences.menuBarWindowID = "primary"
    XCTAssertEqual(
      MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now)?.percent, 42)
    preferences.menuBarWindowID = "missing"
    XCTAssertNil(MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now))
  }

  func testMissingDisabledStaleFailedAndExpiredSelectionNeverFallsBack() {
    var preferences = Preferences()
    preferences.menuBarSource = .claude
    let codex = snapshot(.codex, primary: 70)
    XCTAssertNil(
      MenuBarReading.resolve(preferences: preferences, snapshots: [.codex: codex], now: now))
    for claude in [
      snapshot(.claude, primary: 83, age: 1000), snapshot(.claude, primary: 83, expired: true),
    ] {
      XCTAssertNil(
        MenuBarReading.resolve(
          preferences: preferences, snapshots: [.codex: codex, .claude: claude], now: now))
    }
    let snapshots: [Provider: Snapshot] = [.codex: codex, .claude: snapshot(.claude, primary: 83)]
    XCTAssertNil(
      MenuBarReading.resolve(
        preferences: preferences, snapshots: snapshots,
        failedProviders: [.claude], now: now))
    preferences.enabled.remove(.claude)
    XCTAssertNil(MenuBarReading.resolve(preferences: preferences, snapshots: snapshots, now: now))
  }

  func testIconOnlyHidesPercentage() {
    var preferences = Preferences()
    preferences.menuBarSource = .iconOnly
    XCTAssertNil(
      MenuBarReading.resolve(
        preferences: preferences,
        snapshots: [.codex: snapshot(.codex, primary: 80)], now: now))
  }

  func testSelectionPersistsAndOlderPreferencesKeepDefaults() throws {
    let old = try JSONDecoder().decode(
      Preferences.self,
      from: Data("{\"threshold\":85,\"alertMode\":\"increments\",\"alertInterval\":25}".utf8))
    XCTAssertEqual(old.menuBarSource, .highest)
    XCTAssertNil(old.menuBarWindowID)
    XCTAssertEqual(old.alertInterval, 25)
    var selected = old
    selected.menuBarSource = .codex
    selected.menuBarWindowID = "secondary"
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(selected))
    XCTAssertEqual(restored.menuBarSource, .codex)
    XCTAssertEqual(restored.menuBarWindowID, "secondary")
    XCTAssertEqual(restored.alertInterval, 25)
    XCTAssertEqual(restored.threshold, 85)
  }
}
