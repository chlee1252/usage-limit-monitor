import AppKit
import SwiftUI
import UsageCore

extension Provider {
  var tint: Color {
    switch self {
    case .codex: return Color(red: 0.12, green: 0.48, blue: 0.42)
    case .claude: return Color(red: 0.68, green: 0.38, blue: 0.23)
    case .gemini: return Color(red: 0.26, green: 0.43, blue: 0.79)
    }
  }
  var symbol: String {
    switch self {
    case .codex: return "terminal"
    case .claude: return "asterisk"
    case .gemini: return "sparkle"
    }
  }
}

struct DashboardView: View {
  @ObservedObject var store: MonitorStore
  var openSettings: () -> Void
  var isPreview = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Usage Monitor").font(.system(size: 20, weight: .semibold, design: .rounded))
          Text("다음 작업 전에, 남은 여유를 확인하세요.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await store.refresh(force: true) }
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 14))
        }
        .buttonStyle(.plain).disabled(store.refreshing).help("사용량 새로고침")
        .accessibilityLabel("사용량 새로고침")
      }
      .padding(22)
      Divider()
      if isPreview {
        providerRows(now: Date())
      } else {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          ScrollView {
            providerRows(now: context.date)
          }
          .frame(maxHeight: 500)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      Divider()
      HStack(spacing: 7) {
        Image(systemName: store.preferences.notifications ? "bell.badge" : "bell.slash")
        Text(store.preferences.notifications ? "\(store.preferences.threshold)%에서 알림" : "알림 꺼짐")
        Spacer()
        if isPreview {
          Text("예시 데이터").foregroundStyle(.secondary)
        } else if store.refreshing {
          ProgressView().controlSize(.mini)
        }
        Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }
          .buttonStyle(.plain).help("설정").accessibilityLabel("설정 열기")
        if !isPreview {
          Menu {
            Button("설정…", action: openSettings)
            Divider()
            Button("종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
          } label: {
            Image(systemName: "ellipsis")
          }
          .menuStyle(.borderlessButton).frame(width: 20)
        }
      }
      .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(
        .vertical, 15)
    }
    .frame(width: 370)
    .background(Color(nsColor: .windowBackgroundColor))
  }
  private func providerRows(now: Date) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if store.visibleProviders.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("확인할 AI를 선택해 주세요").font(.headline)
          Text("설정에서 Codex, Claude Code, Gemini를 켤 수 있습니다.")
            .font(.callout).foregroundStyle(.secondary)
          Button("서비스 설정", action: openSettings)
        }.padding(24)
      }
      ForEach(store.visibleProviders) { provider in
        ProviderRow(
          provider: provider, snapshot: store.snapshots[provider],
          error: store.errors[provider], threshold: store.preferences.threshold,
          now: now, openSettings: openSettings)
        if provider != store.visibleProviders.last { Divider().padding(.horizontal, 22) }
      }
    }
  }
}

private struct ProviderRow: View {
  let provider: Provider
  let snapshot: Snapshot?
  let error: String?
  let threshold: Int
  let now: Date
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(spacing: 9) {
        Image(systemName: provider.symbol).font(.system(size: 17, weight: .medium))
          .foregroundStyle(provider.tint).frame(width: 23)
        Text(provider.name).font(.system(size: 14, weight: .semibold))
        Spacer()
        Text(status).font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
      }
      if let snapshot, !snapshot.windows.isEmpty {
        ForEach(snapshot.windows) { window in
          VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
              Text(window.name).font(.system(size: 11)).foregroundStyle(.secondary)
              Spacer()
              Text(window.expired(at: now) ? "—" : "\(Int(window.usedPercent.rounded()))%")
                .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
              Text("사용").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            UsageBar(
              percent: window.expired(at: now) ? 0 : window.usedPercent,
              threshold: threshold, tint: provider.tint,
              muted: window.expired(at: now) || !snapshot.isFresh(at: now) || error != nil)
            HStack {
              Text(window.expired(at: now) ? "리셋 지남 · 새 데이터 대기" : resetLabel(window.resetsAt))
              Spacer()
              if !window.expired(at: now), window.usedPercent >= Double(threshold) {
                Text("알림 기준 도달").foregroundStyle(.orange)
              }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }
        Text("마지막 확인 · \(ageLabel(snapshot.observedAt))")
          .font(.system(size: 10)).foregroundStyle(.secondary)
      } else {
        Text(
          provider == .gemini
            ? "직접 입력한 사용량을 표시합니다.\nGemini의 /stats model에서 확인해 주세요."
            : provider == .claude
              ? "상태 표시줄을 연결하면\nClaude Code의 한도가 여기에 표시됩니다." : "Codex CLI 로그인 후 사용량을 조회합니다."
        )
        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        Button(provider == .gemini ? "사용량 입력" : "연결 설정", action: openSettings)
          .font(.system(size: 11))
      }
      if let error {
        Text(error).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(
          horizontal: false, vertical: true)
      }
    }.padding(.horizontal, 22).padding(.vertical, 18)
  }
  var status: String {
    guard let snapshot, !snapshot.windows.isEmpty else { return "연결 대기" }
    if error != nil { return "조회 실패 · 이전 값" }
    if !snapshot.isFresh(at: now) { return "오래된 값" }
    return snapshot.source
  }
  func resetLabel(_ date: Date?) -> String {
    guard let date else { return "리셋 시간 미제공" }
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    if seconds >= 86400 { return "\(seconds / 86400)일 \((seconds % 86400) / 3600)시간 후 리셋" }
    if seconds >= 3600 { return "\(seconds / 3600)시간 \((seconds % 3600) / 60)분 후 리셋" }
    return "\(max(1, seconds / 60))분 후 리셋"
  }
  func ageLabel(_ date: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes == 0 { return "방금" }
    if minutes < 60 { return "\(minutes)분 전" }
    if minutes < 1440 { return "\(minutes / 60)시간 전" }
    return "\(minutes / 1440)일 전"
  }
}

struct UsageBar: View {
  let percent: Double
  let threshold: Int
  let tint: Color
  var muted = false
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.07))
        Capsule().fill(
          muted ? Color.secondary.opacity(0.35) : percent >= Double(threshold) ? Color.orange : tint
        )
        .frame(width: geometry.size.width * min(100, max(0, percent)) / 100)
        Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 1, height: 12)
          .offset(x: geometry.size.width * Double(threshold) / 100)
      }.frame(height: 6)
    }.frame(height: 8)
      .accessibilityLabel("사용률 \(Int(percent))퍼센트, 알림 기준 \(threshold)퍼센트")
  }
}

struct SettingsView: View {
  @ObservedObject var store: MonitorStore
  @State private var geminiPercent = 0.0
  @State private var geminiReset = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("설정").font(.system(size: 24, weight: .semibold, design: .rounded)).padding(24)
      Form {
        Section("표시할 AI") {
          ForEach(Provider.allCases) { provider in
            Toggle(
              provider.name,
              isOn: Binding(
                get: { store.preferences.enabled.contains(provider) },
                set: { enabled in
                  if enabled {
                    store.preferences.enabled.insert(provider)
                  } else {
                    store.preferences.enabled.remove(provider)
                  }
                  Task { await store.refresh(force: true) }
                }))
          }
        }
        Section("사용량 알림") {
          Toggle(
            "한도에 가까워지면 알림",
            isOn: Binding(
              get: { store.preferences.notifications },
              set: { value in
                Task { await store.enableNotifications(value) }
              }))
          HStack {
            Slider(
              value: Binding(
                get: { Double(store.preferences.threshold) },
                set: { store.preferences.threshold = Int($0) }), in: 10...100, step: 5)
            Text("\(store.preferences.threshold)%").monospacedDigit().frame(width: 44)
          }
          Text("각 한도 구간마다 한 번 알립니다. 15분 이상 지난 값은 알림에서 제외합니다.")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Text(store.permission).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("테스트 알림") { Task { await store.testNotification() } }.disabled(
              !store.preferences.notifications)
          }
        }
        Section("Codex · 자동 조회") {
          HStack {
            TextField("Codex CLI 실행 파일 경로", text: $store.preferences.codexExecutable)
            Button("선택…") {
              let panel = NSOpenPanel()
              panel.canChooseDirectories = false
              if panel.runModal() == .OK, let url = panel.url {
                store.preferences.codexExecutable = url.path
              }
            }
          }
          Text("ChatGPT 계정으로 로그인한 Codex CLI가 필요합니다. 5분마다 조회합니다.")
            .font(.caption).foregroundStyle(.secondary)
          Button("지금 조회") { Task { await store.refresh(force: true) } }.disabled(store.refreshing)
        }
        Section("Claude Code · 상태 표시줄 연결") {
          Text("Claude 설정에 연결 스크립트를 추가합니다. 기존 상태 표시줄은 유지하며, 연결 해제 시 복원합니다.")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("Claude 연결", action: store.installClaude)
            Button("연결 해제", action: store.uninstallClaude)
          }
          Text("한도 데이터가 제공되는 계정·CLI 버전에서 동작합니다. 응답이 끝난 뒤 갱신되며, 앱은 30초마다 확인합니다.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("Gemini · 직접 입력") {
          Text(
            "Gemini CLI의 /stats model에서 확인한 사용률을 입력하세요. 자동 조회는 아직 지원하지 않습니다. 여러 모델은 각각 한도가 다를 수 있습니다."
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Slider(value: $geminiPercent, in: 0...100, step: 1)
            Text("\(Int(geminiPercent))%").monospacedDigit().frame(width: 44)
          }
          DatePicker("리셋 시간", selection: $geminiReset, in: Date()...)
          Button("사용량 저장") { store.saveGemini(percent: geminiPercent, reset: geminiReset) }
        }
      }.formStyle(.grouped)
      if let notice = store.notice {
        HStack {
          Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
          Spacer()
          Button {
            store.notice = nil
          } label: {
            Image(systemName: "xmark")
          }.buttonStyle(.plain)
        }.padding(16).background(Color.accentColor.opacity(0.08))
      }
      HStack {
        Text("Usage Monitor 0.1.0").foregroundStyle(.secondary)
        Spacer()
        Link(
          "연결 및 설치 안내",
          destination: URL(string: "https://github.com/chlee1252/usage-limit-monitor#readme")!)
      }.font(.caption).padding(16)
    }.frame(width: 540, height: 780)
      .onAppear {
        if let window = store.snapshots[.gemini]?.windows.first {
          geminiPercent = window.usedPercent
          if let reset = window.resetsAt, reset > Date() { geminiReset = reset }
        }
        Task { await store.updatePermission() }
      }
  }
}
