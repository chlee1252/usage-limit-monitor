import XCTest

@testable import UsageCore

final class UsageCoreTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func data(_ json: String) -> Data { Data(json.utf8) }
  func testCodexMultipleBucketsAndWindowDurations() throws {
    let snapshot = try UsageParser.codex(
      data(
        """
        {"result":{"rateLimitsByLimitId":{
          "codex":{"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1800100000},"secondary":null},
          "review":{"primary":{"usedPercent":92,"windowDurationMins":300},"secondary":{"usedPercent":45,"windowDurationMins":60}}
        }}}
        """), now: now)
    XCTAssertEqual(snapshot.windows.count, 3)
    XCTAssertEqual(snapshot.windows.first?.usedPercent, 0)
    XCTAssertTrue(snapshot.windows.first!.name.contains("7일"))
    XCTAssertTrue(snapshot.windows[1].name.contains("5시간"))
    XCTAssertEqual(Set(snapshot.windows.map(\.id)).count, 3)
  }
  func testCodexLegacyBucket() throws {
    let snapshot = try UsageParser.codex(
      data(
        """
        {"rateLimits":{"primary":{"usedPercent":65.5,"windowDurationMins":15}}}
        """))
    XCTAssertEqual(snapshot.windows.first?.name, "15분")
    XCTAssertEqual(snapshot.windows.first?.usedPercent, 65.5)
    XCTAssertNil(snapshot.windows.first?.resetsAt)
  }
  func testMissingAndInvalidPercentNeverBecomeZero() {
    for value in ["null", "true", "-1", "101", "\"30\""] {
      XCTAssertThrowsError(
        try UsageParser.codex(data("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(value)}}}")))
    }
    XCTAssertThrowsError(try UsageParser.codex(data("{}")))
  }
  func testClaudeDoesNotConfuseContextWithQuota() throws {
    let snapshot = try UsageParser.claude(
      data(
        """
        {"context_window":{"used_percentage":90},"rate_limits":{"five_hour":{"used_percentage":38.5,"resets_at":1800100000}}}
        """), now: now)
    XCTAssertEqual(snapshot.windows.count, 1)
    XCTAssertEqual(snapshot.windows[0].usedPercent, 38.5)
    XCTAssertTrue(
      try UsageParser.claude(data("{\"context_window\":{\"used_percentage\":90}}")).windows.isEmpty)
  }
  func testAlertsAtThresholdOncePerResetAndThreshold() {
    var ledger = AlertLedger()
    let window = UsageWindow(
      id: "5h", name: "5시간", usedPercent: 80, resetsAt: now.addingTimeInterval(100))
    let snapshot = Snapshot(provider: .codex, windows: [window], observedAt: now, source: "test")
    XCTAssertEqual(ledger.eligible(snapshot, threshold: 80, now: now).count, 1)
    ledger.mark(provider: .codex, window: window, threshold: 80)
    XCTAssertTrue(ledger.eligible(snapshot, threshold: 80, now: now).isEmpty)
    XCTAssertEqual(ledger.eligible(snapshot, threshold: 75, now: now).count, 1)
    XCTAssertTrue(ledger.eligible(snapshot, threshold: 85, now: now).isEmpty)
    let next = UsageWindow(
      id: "5h", name: "5시간", usedPercent: 82, resetsAt: now.addingTimeInterval(200))
    XCTAssertEqual(
      ledger.eligible(
        Snapshot(provider: .codex, windows: [next], observedAt: now, source: "test"), threshold: 80,
        now: now
      ).count, 1)
  }
  func testNoAlertsForStaleExpiredOrFutureData() {
    let window = UsageWindow(
      id: "5h", name: "5시간", usedPercent: 99, resetsAt: now.addingTimeInterval(10000))
    for observed in [now.addingTimeInterval(-901), now.addingTimeInterval(120)] {
      XCTAssertTrue(
        AlertLedger().eligible(
          Snapshot(provider: .claude, windows: [window], observedAt: observed, source: "test"),
          threshold: 80, now: now
        ).isEmpty)
    }
    let expired = UsageWindow(id: "5h", name: "5시간", usedPercent: 100, resetsAt: now)
    XCTAssertTrue(
      AlertLedger().eligible(
        Snapshot(provider: .claude, windows: [expired], observedAt: now, source: "test"),
        threshold: 80, now: now
      ).isEmpty)
  }
  func testLedgerPersistsAcrossLaunches() throws {
    var ledger = AlertLedger()
    let window = UsageWindow(
      id: "test", name: "test", usedPercent: 99, resetsAt: now.addingTimeInterval(100))
    ledger.mark(provider: .gemini, window: window, threshold: 80)
    let restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
    XCTAssertTrue(
      restored.eligible(
        Snapshot(provider: .gemini, windows: [window], observedAt: now, source: "test"),
        threshold: 80, now: now
      ).isEmpty)
  }
  func testClaudeInstallPreservesSettingsAndRestoresOriginal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = directory.appendingPathComponent("settings.json")
    let original: [String: Any] = [
      "theme": "dark", "statusLine": ["type": "command", "command": "cat | wc -c", "padding": 2],
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: settings)
    try ClaudeBridge.install(
      executable: "/some path/UsageMonitor", settings: settings, directory: directory)
    try ClaudeBridge.install(
      executable: "/some path/UsageMonitor", settings: settings, directory: directory)
    let installed =
      try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    XCTAssertEqual(installed["theme"] as? String, "dark")
    XCTAssertEqual((installed["statusLine"] as? [String: Any])?["padding"] as? Int, 2)
    try ClaudeBridge.uninstall(settings: settings, directory: directory)
    let restored =
      try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! NSDictionary
    XCTAssertEqual(restored, original as NSDictionary)
  }
  func testClaudeInvalidConfigIsUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = directory.appendingPathComponent("settings.json")
    try data("not json").write(to: settings)
    XCTAssertThrowsError(
      try ClaudeBridge.install(executable: "/bin/false", settings: settings, directory: directory))
    XCTAssertEqual(try Data(contentsOf: settings), data("not json"))
  }
  func testCodexRPCWithMockAndTimeout() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("codex")
    try """
    #!/bin/sh
    read -r init
    echo '{"id":1,"result":{}}'
    read -r initialized
    read -r request
    echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":33,"windowDurationMins":300}}}}'
    read -r end
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    XCTAssertEqual(try CodexClient.read(executable: script.path).windows.first?.usedPercent, 33)
    try "#!/bin/sh\nread -r init\nread -r never\n".write(
      to: script, atomically: true, encoding: .utf8)
    let start = Date()
    XCTAssertThrowsError(try CodexClient.read(executable: script.path, timeout: 0.3))
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }
}
