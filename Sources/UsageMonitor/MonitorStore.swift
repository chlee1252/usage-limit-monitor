import AppKit
import SwiftUI
import UsageCore
import UserNotifications

struct Preferences: Codable {
  var enabled: Set<Provider> = Set(Provider.allCases)
  var threshold = 80
  var notifications = false
  var codexExecutable = CodexClient.locateExecutable()
}

@MainActor final class MonitorStore: ObservableObject {
  @Published var preferences: Preferences { didSet { persistPreferences() } }
  @Published var snapshots: [Provider: Snapshot] = [:]
  @Published var errors: [Provider: String] = [:]
  @Published var refreshing = false
  @Published var notice: String?
  @Published var permission = "꺼짐"
  private var ledger: AlertLedger
  private var timer: Timer?
  private var lastCodexAttempt = Date.distantPast
  private var evaluating = false
  private let preview: Bool
  private var preferencesURL: URL { Storage.directory.appendingPathComponent("preferences.json") }
  private var ledgerURL: URL { Storage.directory.appendingPathComponent("alerts.json") }

  init(preview: Bool = false) {
    self.preview = preview
    preferences =
      (try? Storage.read(
        Preferences.self, from: Storage.directory.appendingPathComponent("preferences.json")))
      ?? Preferences()
    ledger =
      (try? Storage.read(
        AlertLedger.self, from: Storage.directory.appendingPathComponent("alerts.json")))
      ?? AlertLedger()
    if preview {
      preferences = Preferences()
      preferences.notifications = true
      snapshots = [
        .codex: Snapshot(
          provider: .codex,
          windows: [
            UsageWindow(
              id: "primary", name: "5시간", usedPercent: 42, resetsAt: Date().addingTimeInterval(7200)
            ),
            UsageWindow(
              id: "secondary", name: "7일", usedPercent: 68,
              resetsAt: Date().addingTimeInterval(250000)),
          ], source: "미리보기"),
        .claude: Snapshot(
          provider: .claude,
          windows: [
            UsageWindow(
              id: "five_hour", name: "5시간", usedPercent: 83,
              resetsAt: Date().addingTimeInterval(4100)),
            UsageWindow(
              id: "seven_day", name: "7일", usedPercent: 56,
              resetsAt: Date().addingTimeInterval(160000)),
          ], source: "미리보기"),
        .gemini: Snapshot(
          provider: .gemini,
          windows: [
            UsageWindow(
              id: "manual", name: "일일 한도", usedPercent: 24,
              resetsAt: Date().addingTimeInterval(32000))
          ], source: "미리보기"),
      ]
      return
    }
    for provider in Provider.allCases {
      snapshots[provider] = try? Storage.read(Snapshot.self, from: cacheURL(provider))
    }
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    Task {
      await refresh(force: true)
      await updatePermission()
    }
  }
  var visibleProviders: [Provider] { Provider.allCases.filter { preferences.enabled.contains($0) } }
  var highestUsage: Int? {
    let now = Date()
    return visibleProviders.compactMap { provider -> Double? in
      guard errors[provider] == nil, let snapshot = snapshots[provider], snapshot.isFresh(at: now)
      else { return nil }
      return snapshot.windows.filter { !$0.expired(at: now) }.map(\.usedPercent).max()
    }.max().map { Int($0.rounded()) }
  }
  func cacheURL(_ provider: Provider) -> URL {
    Storage.directory.appendingPathComponent("\(provider.rawValue).json")
  }
  func persistPreferences() {
    guard !preview else { return }
    do { try Storage.save(preferences, to: preferencesURL) } catch {
      notice = "설정 저장 실패: \(error.localizedDescription)"
    }
  }
  func refresh(force: Bool = false) async {
    guard !preview, !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    for provider in [Provider.claude, .gemini] where preferences.enabled.contains(provider) {
      if let snapshot = try? Storage.read(Snapshot.self, from: cacheURL(provider)),
        snapshot.provider == provider
      {
        snapshots[provider] = snapshot
      }
    }
    if preferences.enabled.contains(.codex),
      force || Date().timeIntervalSince(lastCodexAttempt) >= 300
    {
      lastCodexAttempt = Date()
      let executable = preferences.codexExecutable
      do {
        let snapshot = try await Task.detached(priority: .utility) {
          try CodexClient.read(executable: executable)
        }.value
        snapshots[.codex] = snapshot
        errors[.codex] = nil
        try Storage.save(snapshot, to: cacheURL(.codex))
      } catch { errors[.codex] = error.localizedDescription }
    }
    await evaluateAlerts()
  }
  func updatePermission() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional: permission = "허용됨"
    case .denied: permission = "시스템 설정에서 알림을 허용해 주세요"
    default: permission = "권한 요청 전"
    }
  }
  func enableNotifications(_ enabled: Bool) async {
    guard !preview else { return }
    if enabled {
      do {
        preferences.notifications = try await UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .sound])
      } catch { notice = "알림 설정 실패: \(error.localizedDescription)" }
    } else {
      preferences.notifications = false
    }
    await updatePermission()
    await evaluateAlerts()
  }
  func testNotification() async {
    do {
      let content = UNMutableNotificationContent()
      content.title = "Usage Monitor"
      content.body = "설정한 사용률에 도달하면 이렇게 알려드려요."
      content.sound = .default
      try await UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: "test", content: content, trigger: nil))
    } catch { notice = "테스트 알림 실패: \(error.localizedDescription)" }
  }
  private func evaluateAlerts() async {
    guard !preview, preferences.notifications, !evaluating else { return }
    evaluating = true
    defer { evaluating = false }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    else { return }
    let threshold = preferences.threshold
    for provider in visibleProviders {
      guard errors[provider] == nil, let snapshot = snapshots[provider] else { continue }
      for window in ledger.eligible(snapshot, threshold: threshold) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider.name) 사용량 \(Int(window.usedPercent.rounded()))%"
        content.body = "\(window.name) 한도가 알림 기준 \(threshold)%에 도달했습니다."
        content.sound = .default
        do {
          try await center.add(
            UNNotificationRequest(
              identifier: ledger.key(provider: provider, window: window, threshold: threshold),
              content: content, trigger: nil))
          ledger.mark(provider: provider, window: window, threshold: threshold)
          try Storage.save(ledger, to: ledgerURL)
        } catch { notice = "알림 처리 실패: \(error.localizedDescription)" }
      }
    }
  }
  func saveGemini(percent: Double, reset: Date) {
    guard percent.isFinite, (0...100).contains(percent), reset > Date() else {
      notice = "0~100%와 미래의 리셋 시간을 입력해 주세요."
      return
    }
    let snapshot = Snapshot(
      provider: .gemini,
      windows: [
        UsageWindow(id: "manual", name: "직접 입력한 한도", usedPercent: percent, resetsAt: reset)
      ], source: "직접 입력")
    do {
      try Storage.save(snapshot, to: cacheURL(.gemini))
      snapshots[.gemini] = snapshot
      notice = "Gemini 사용량을 저장했습니다. 자동으로 갱신되지 않습니다."
      Task { await evaluateAlerts() }
    } catch { notice = error.localizedDescription }
  }
  func installClaude() {
    do {
      guard let executable = Bundle.main.executablePath else { return }
      try ClaudeBridge.install(executable: executable)
      notice = "Claude 연결을 설정했습니다. Claude Code에서 다음 응답을 받으면 사용량이 표시됩니다."
    } catch { notice = error.localizedDescription }
  }
  func uninstallClaude() {
    do {
      try ClaudeBridge.uninstall()
      notice = "기존 Claude 상태 표시줄을 복원했습니다."
    } catch { notice = error.localizedDescription }
  }
}
