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
  static let width: CGFloat = 300
  @ObservedObject var store: MonitorStore
  var openSettings: () -> Void
  var isPreview = false
  // A nil height uses the natural content size for measurement and README rendering.
  var panelHeight: CGFloat?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Usage Monitor").font(.system(size: 12, weight: .semibold))
        Spacer()
        if isPreview { Text("예시").font(.system(size: 10)).foregroundStyle(.secondary) }
        Button {
          Task { await store.refresh(force: true) }
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 11))
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain).disabled(store.refreshing)
        .help("사용량 새로고침").accessibilityLabel("사용량 새로고침")
      }
      .padding(.horizontal, 14).frame(height: 34)
      Divider()
      if panelHeight == nil {
        providerRows(now: Date())
      } else {
        TimelineView(.periodic(from: .now, by: 30)) { context in
          ScrollView { providerRows(now: context.date) }
            .frame(maxHeight: .infinity)
        }
      }
      Divider()
      HStack(spacing: 6) {
        Image(systemName: store.preferences.notifications ? "bell" : "bell.slash")
        Text(store.preferences.notifications ? store.preferences.alertRule.summary : "알림 꺼짐")
        Spacer()
        if store.refreshing { ProgressView().controlSize(.mini) }
        Button(action: openSettings) {
          Image(systemName: "gearshape").frame(width: 22, height: 22)
        }.buttonStyle(.plain).help("설정").accessibilityLabel("설정 열기")
        if isPreview {
          Image(systemName: "ellipsis").frame(width: 18)
        } else {
          Menu {
            Button("설정…", action: openSettings)
            Divider()
            Button("종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
          } label: {
            Image(systemName: "ellipsis")
          }
          .menuStyle(.borderlessButton).frame(width: 18)
          .accessibilityLabel("더 보기")
        }
      }
      .font(.system(size: 10)).foregroundStyle(.secondary)
      .padding(.horizontal, 14).frame(height: 32)
    }
    .frame(width: Self.width, height: panelHeight)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func providerRows(now: Date) -> some View {
    VStack(spacing: 0) {
      if store.visibleProviders.isEmpty {
        HStack {
          Text("표시할 AI를 선택하세요").font(.system(size: 11)).foregroundStyle(.secondary)
          Spacer()
          Button("설정", action: openSettings).controlSize(.small)
        }.padding(14)
      }
      ForEach(store.visibleProviders) { provider in
        ProviderRow(
          provider: provider, snapshot: store.snapshots[provider],
          error: store.errors[provider], rule: store.preferences.alertRule,
          now: now, openSettings: openSettings)
        if provider != store.visibleProviders.last { Divider().padding(.horizontal, 14) }
      }
    }
  }
}

private struct ProviderRow: View {
  let provider: Provider
  let snapshot: Snapshot?
  let error: String?
  let rule: AlertRule
  let now: Date
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: provider.symbol).foregroundStyle(provider.tint).frame(width: 14)
        Text(provider.name).fontWeight(.semibold)
        Spacer()
        Text(status).font(.system(size: 9)).foregroundStyle(
          error == nil ? Color.secondary : Color.orange)
      }.font(.system(size: 11)).frame(height: 16).help(details)
      if let snapshot, !snapshot.windows.isEmpty {
        ForEach(snapshot.windows) { window in
          HStack(spacing: 6) {
            Text(window.name).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.tail).frame(width: 47, alignment: .leading)
            UsageBar(
              percent: window.expired(at: now) ? 0 : window.usedPercent,
              rule: rule, tint: provider.tint,
              muted: window.expired(at: now) || !snapshot.isFresh(at: now) || error != nil)
            Text(window.expired(at: now) ? "—" : "\(Int(window.usedPercent.rounded()))%")
              .fontWeight(.medium).monospacedDigit().frame(width: 33, alignment: .trailing)
            Text(resetLabel(window.resetsAt)).font(.system(size: 9))
              .foregroundStyle(.secondary).lineLimit(1).frame(width: 44, alignment: .trailing)
          }
          .font(.system(size: 11)).frame(height: 22)
          .help(
            "\(window.name) · \(window.resetsAt.map { "리셋: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "리셋 시간 미제공")\n\(details)"
          )
          .accessibilityElement(children: .combine)
        }
      } else {
        HStack {
          Text(provider == .gemini ? "사용량 직접 입력" : error == nil ? "연결이 필요합니다" : "조회하지 못했습니다")
            .foregroundStyle(.secondary)
          Spacer()
          Button(provider == .gemini ? "입력" : "연결", action: openSettings)
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }.font(.system(size: 10)).frame(height: 22).help(details)
      }
    }.padding(.horizontal, 14).padding(.vertical, 9)
  }

  var status: String {
    if error != nil { return "조회 실패" }
    guard let snapshot, !snapshot.windows.isEmpty else { return "" }
    if !snapshot.isFresh(at: now) { return "오래된 값" }
    return provider == .gemini ? "직접 입력" : ""
  }
  var details: String {
    if let error { return error }
    guard let snapshot else {
      return provider == .gemini ? "Gemini CLI의 /stats model에서 확인한 값을 설정에서 입력하세요." : "설정에서 연결하세요."
    }
    return
      "\(snapshot.source) · 마지막 확인: \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))"
  }
  func resetLabel(_ date: Date?) -> String {
    guard let date else { return "시간 없음" }
    let seconds = Int(date.timeIntervalSince(now))
    if seconds <= 0 { return "갱신 대기" }
    if seconds >= 86400 { return "\(seconds / 86400)일 후" }
    if seconds >= 3600 { return "\(seconds / 3600)시간 후" }
    return "\(max(1, seconds / 60))분 후"
  }
}

struct UsageBar: View {
  let percent: Double
  let rule: AlertRule
  let tint: Color
  var muted = false
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.07))
        Capsule().fill(
          muted
            ? Color.secondary.opacity(0.35)
            : rule.mode == .threshold && percent >= Double(rule.threshold) ? Color.orange : tint
        )
        .frame(width: geometry.size.width * min(100, max(0, percent)) / 100)
        ForEach(rule.milestones, id: \.self) { milestone in
          Rectangle().fill(Color.primary.opacity(0.25)).frame(width: 1)
            .offset(x: min(geometry.size.width - 1, geometry.size.width * Double(milestone) / 100))
        }
      }
    }.frame(height: 4)
      .accessibilityLabel("사용률 \(Int(percent))퍼센트, \(rule.summary)")
  }
}

struct SettingsView: View {
  @ObservedObject var store: MonitorStore
  var panelHeight: CGFloat = 720
  @State private var geminiPercent = 0.0
  @State private var geminiReset = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("설정").font(.system(size: 24, weight: .semibold, design: .rounded)).padding(24)
      Form {
        Section("메뉴 막대") {
          Picker(
            "대표 사용량",
            selection: Binding(
              get: { store.preferences.menuBarSource },
              set: { source in
                store.preferences.menuBarSource = source
                store.preferences.menuBarWindowID = nil
                if let provider = source.provider { store.preferences.enabled.insert(provider) }
                Task { await store.refresh() }
              })
          ) {
            ForEach(MenuBarSource.allCases, id: \.self) { source in
              Text(source.name).tag(source)
            }
          }
          if store.preferences.menuBarSource.provider != nil {
            Picker("한도 구간", selection: $store.preferences.menuBarWindowID) {
              Text("이 AI에서 가장 높은 사용률").tag(nil as String?)
              ForEach(store.menuBarWindows) { window in
                Text(window.name).tag(Optional(window.id))
              }
              if let selected = store.preferences.menuBarWindowID,
                !store.menuBarWindows.contains(where: { $0.id == selected })
              {
                Text("이전 선택 구간 · 데이터 없음").tag(Optional(selected))
              }
            }
          }
          Text("선택한 사용량이 없거나 오래되면 —로 표시합니다. 아이콘에 마우스를 올리면 어떤 한도인지 확인할 수 있습니다.")
            .font(.caption).foregroundStyle(.secondary)
        }
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
            "사용량 알림 받기",
            isOn: Binding(
              get: { store.preferences.notifications },
              set: { value in
                Task { await store.enableNotifications(value) }
              }))
          Picker("알림 방식", selection: $store.preferences.alertMode) {
            Text("지정 비율 도달 시").tag(AlertMode.threshold)
            Text("일정 비율마다").tag(AlertMode.increments)
          }.pickerStyle(.segmented)
          if store.preferences.alertMode == .threshold {
            HStack {
              Text("알림 기준")
              Slider(
                value: Binding(
                  get: { Double(store.preferences.threshold) },
                  set: { store.preferences.threshold = Int($0) }), in: 10...100, step: 5)
              Text("\(store.preferences.threshold)%").monospacedDigit().frame(width: 44)
            }
            Text("사용률이 \(store.preferences.threshold)%에 도달하면 한 번 알립니다. 한도가 리셋되면 다시 알립니다.")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Picker("알림 간격", selection: $store.preferences.alertInterval) {
              ForEach([5, 10, 20, 25, 50], id: \.self) { interval in
                Text("\(interval)%마다").tag(interval)
              }
            }
            Text("예: 10% 간격이면 10%, 20%, 30%…에서 알립니다. 여러 구간을 한 번에 넘으면 가장 높은 구간만 알립니다.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Text("15분 이상 지난 값은 알림에서 제외합니다. 새 설정은 다음 사용량 확인부터 적용됩니다.")
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
    }.frame(width: 540, height: panelHeight)
      .onAppear {
        if let window = store.snapshots[.gemini]?.windows.first {
          geminiPercent = window.usedPercent
          if let reset = window.resetsAt, reset > Date() { geminiReset = reset }
        }
        Task { await store.updatePermission() }
      }
  }
}
