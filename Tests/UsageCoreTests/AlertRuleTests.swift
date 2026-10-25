import XCTest

@testable import UsageCore

final class AlertRuleTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let everyTen = AlertRule(mode: .increments, interval: 10)

  func snapshot(
    _ percent: Double, resetOffset: Double = 1000, age: Double = 0,
    provider: Provider = .codex, id: String = "primary"
  ) -> Snapshot {
    Snapshot(
      provider: provider,
      windows: [
        UsageWindow(
          id: id, name: "5시간", usedPercent: percent,
          resetsAt: now.addingTimeInterval(resetOffset))
      ],
      observedAt: now.addingTimeInterval(-age), source: "test")
  }

  func testThresholdRespectsExactBoundaryAndLegacyLedger() {
    var ledger = AlertLedger()
    let rule = AlertRule(threshold: 80)
    XCTAssertTrue(ledger.pending(snapshot(79.99), rule: rule, now: now).isEmpty)
    XCTAssertEqual(ledger.pending(snapshot(80), rule: rule, now: now).first?.milestone, 80)
    ledger.mark(provider: .codex, window: snapshot(80).windows[0], threshold: 80)
    XCTAssertTrue(ledger.pending(snapshot(99), rule: rule, now: now).isEmpty)
  }

  func testEveryTenPercentAndNoRepeatedAlerts() throws {
    var ledger = AlertLedger()
    XCTAssertTrue(ledger.pending(snapshot(9.99), rule: everyTen, now: now).isEmpty)
    for milestone in stride(from: 10, through: 100, by: 10) {
      let alert = try XCTUnwrap(
        ledger.pending(snapshot(Double(milestone)), rule: everyTen, now: now).first)
      XCTAssertEqual(alert.milestone, milestone)
      ledger.mark(provider: .codex, alert: alert, rule: everyTen)
      XCTAssertTrue(ledger.pending(snapshot(Double(milestone)), rule: everyTen, now: now).isEmpty)
      if milestone < 100 {
        XCTAssertTrue(
          ledger.pending(snapshot(Double(milestone) + 9.99), rule: everyTen, now: now).isEmpty)
      }
    }
  }

  func testSkippedMilestonesCoalesceAndDecreasesDoNotReplay() throws {
    var ledger = AlertLedger()
    let first = try XCTUnwrap(ledger.pending(snapshot(21), rule: everyTen, now: now).first)
    XCTAssertEqual(first.milestone, 20)
    ledger.mark(provider: .codex, alert: first, rule: everyTen)
    let jumped = ledger.pending(snapshot(43), rule: everyTen, now: now)
    XCTAssertEqual(jumped.count, 1)
    XCTAssertEqual(jumped.first?.milestone, 40)
    ledger.mark(provider: .codex, alert: try XCTUnwrap(jumped.first), rule: everyTen)
    for value in [10.0, 25, 35, 43, 49.9] {
      XCTAssertTrue(ledger.pending(snapshot(value), rule: everyTen, now: now).isEmpty)
    }
    XCTAssertEqual(ledger.pending(snapshot(50), rule: everyTen, now: now).first?.milestone, 50)
  }

  func testFirstObservationNotifiesHighestReachedMilestoneOnly() {
    let alerts = AlertLedger().pending(snapshot(83), rule: everyTen, now: now)
    XCTAssertEqual(alerts.count, 1)
    XCTAssertEqual(alerts.first?.milestone, 80)
  }

  func testIncrementHistorySurvivesRestartAndResetsPerWindow() throws {
    var ledger = AlertLedger()
    let alert = try XCTUnwrap(ledger.pending(snapshot(83), rule: everyTen, now: now).first)
    ledger.mark(provider: .codex, alert: alert, rule: everyTen)
    let restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
    XCTAssertTrue(restored.pending(snapshot(85), rule: everyTen, now: now).isEmpty)
    XCTAssertEqual(
      restored.pending(snapshot(85, resetOffset: 2000), rule: everyTen, now: now).count, 1)
    XCTAssertEqual(
      restored.pending(snapshot(85, provider: .claude), rule: everyTen, now: now).count, 1)
    XCTAssertEqual(
      restored.pending(snapshot(85, id: "secondary"), rule: everyTen, now: now).count, 1)
  }

  func testModesAndIntervalsHaveIndependentHistory() throws {
    var ledger = AlertLedger()
    let alert = try XCTUnwrap(ledger.pending(snapshot(80), rule: everyTen, now: now).first)
    ledger.mark(provider: .codex, alert: alert, rule: everyTen)
    XCTAssertEqual(ledger.pending(snapshot(80), rule: AlertRule(threshold: 80), now: now).count, 1)
    XCTAssertEqual(
      ledger.pending(snapshot(80), rule: AlertRule(mode: .increments, interval: 25), now: now)
        .first?.milestone, 75)
  }

  func testStaleExpiredFutureAndNonFiniteValuesDoNotNotify() {
    let ledger = AlertLedger()
    for sample in [
      snapshot(90, resetOffset: 0), snapshot(90, age: 901),
      snapshot(90, age: -120), snapshot(.nan),
    ] {
      XCTAssertTrue(ledger.pending(sample, rule: everyTen, now: now).isEmpty)
    }
  }

  func testLegacyPreferencesMigrationKeepsUserSettings() throws {
    let legacy = Data(
      """
      {"enabled":["claude"],"threshold":90,"notifications":true,"codexExecutable":"/custom/codex"}
      """.utf8)
    var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
    XCTAssertEqual(preferences.enabled, [.claude])
    XCTAssertEqual(preferences.threshold, 90)
    XCTAssertTrue(preferences.notifications)
    XCTAssertEqual(preferences.codexExecutable, "/custom/codex")
    XCTAssertEqual(preferences.alertMode, .threshold)
    XCTAssertEqual(preferences.alertInterval, 10)
    preferences.alertMode = .increments
    preferences.alertInterval = 25
    let restored = try JSONDecoder().decode(
      Preferences.self, from: JSONEncoder().encode(preferences))
    XCTAssertEqual(restored.alertRule, preferences.alertRule)
    XCTAssertEqual(restored.threshold, 90)
  }

  func testInvalidIntervalCannotDivideByZero() {
    let rule = AlertRule(mode: .increments, interval: 0)
    XCTAssertEqual(rule.milestones.first, 5)
    XCTAssertEqual(rule.milestones.last, 100)
  }
}
