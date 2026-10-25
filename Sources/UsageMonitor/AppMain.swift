import AppKit
import Combine
import SwiftUI
import UsageCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var item: NSStatusItem!
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var store: MonitorStore!
  private var timer: Timer?
  private var observations = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    UNUserNotificationCenter.current().delegate = self
    store = MonitorStore()
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    item.button?.image = NSImage(
      systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "AI 사용량")
    item.button?.imagePosition = .imageLeading
    item.button?.toolTip = "Usage Monitor · AI 사용 한도"
    popover.behavior = .transient
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.updateMenuBar() }
    }
    // Published values notify before assignment; deliver on the next main-loop turn.
    store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.updateMenuBar()
      self?.resizePopover()
    }.store(in: &observations)
    updateMenuBar()
  }
  private func updateMenuBar() {
    let source = store.preferences.menuBarSource
    let reading = store.menuBarReading
    item.button?.title = source == .iconOnly ? "" : reading.map { " \($0.percent)%" } ?? " —"
    item.button?.image = NSImage(
      systemSymbolName: source.provider?.symbol ?? "chart.bar.xaxis",
      accessibilityDescription: "AI 사용량")
    item.button?.toolTip =
      reading.map { "\($0.provider.name) · \($0.window.name) · \($0.percent)% 사용" }
      ?? (source == .iconOnly ? "Usage Monitor" : "\(source.name) · 최신 사용량 없음")
  }
  private func makeDashboard(panelHeight: CGFloat? = nil) -> DashboardView {
    DashboardView(
      store: store, openSettings: { [weak self] in self?.showSettings() },
      panelHeight: panelHeight)
  }
  private func panelSize() -> NSSize {
    // Measure the non-scrolling content, then cap it to the status item's display.
    let measurement = NSHostingView(rootView: makeDashboard())
    let available = (item.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 700
    return NSSize(
      width: DashboardView.width,
      height: min(ceil(measurement.fittingSize.height), 480, available - 32))
  }
  private func resizePopover() {
    guard popover.isShown,
      let controller = popover.contentViewController as? NSHostingController<DashboardView>
    else { return }
    let size = panelSize()
    guard abs(popover.contentSize.height - size.height) > 1 else { return }
    controller.rootView = makeDashboard(panelHeight: size.height)
    popover.contentSize = size
  }
  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else if let button = item.button {
      let size = panelSize()
      let controller = NSHostingController(rootView: makeDashboard(panelHeight: size.height))
      controller.sizingOptions = []
      popover.contentViewController = controller
      popover.contentSize = size
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      Task { await store.refresh() }
    }
  }
  func showSettings() {
    popover.performClose(nil)
    let screen = item.button?.window?.screen ?? NSScreen.main
    let height = min(780, (screen?.visibleFrame.height ?? 840) - 60)
    if settingsWindow == nil {
      let controller = NSHostingController(
        rootView: SettingsView(store: store, panelHeight: height))
      let window = NSWindow(contentViewController: controller)
      window.title = "Usage Monitor 설정"
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.isReleasedWhenClosed = false
      settingsWindow = window
    }
    if let window = settingsWindow {
      if let controller = window.contentViewController as? NSHostingController<SettingsView> {
        controller.rootView = SettingsView(store: store, panelHeight: height)
      }
      window.setContentSize(NSSize(width: 540, height: height))
      if let frame = screen?.visibleFrame {
        window.setFrameOrigin(
          NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2))
      }
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

@main struct UsageMonitorMain {
  @MainActor static func main() throws {
    if CommandLine.arguments.contains("--capture-claude") {
      do {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let snapshot = try UsageParser.claude(data)
        try Storage.save(snapshot, to: Storage.directory.appendingPathComponent("claude.json"))
      } catch { exit(1) }
    } else if CommandLine.arguments.contains("--check-codex") {
      do {
        let snapshot = try CodexClient.read(executable: CodexClient.locateExecutable())
        let data = try JSONEncoder().encode(snapshot)
        FileHandle.standardOutput.write(data)
      } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
      }
    } else if CommandLine.arguments.contains("--check-layout") {
      let app = NSApplication.shared
      app.setActivationPolicy(.prohibited)
      let store = MonitorStore(preview: true)
      for providers: Set<Provider> in [Set(Provider.allCases), [.codex], []] {
        store.preferences.enabled = providers
        let host = NSHostingView(rootView: DashboardView(store: store, openSettings: {}))
        let size = host.fittingSize
        precondition(size.width == DashboardView.width && size.height > 60 && size.height < 360)
        print("providers=\(providers.count) panel=\(Int(size.width))×\(Int(ceil(size.height)))")
      }
    } else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
      CommandLine.arguments.count > index + 1
    {
      let app = NSApplication.shared
      app.setActivationPolicy(.prohibited)
      let store = MonitorStore(preview: true)
      let view = DashboardView(store: store, openSettings: {}, isPreview: true).environment(
        \.colorScheme, .light)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      {
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
      } else {
        exit(1)
      }
    } else {
      let application = NSApplication.shared
      let delegate = AppDelegate()
      application.delegate = delegate
      withExtendedLifetime(delegate) { application.run() }
    }
  }
}
