import AppKit
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
      Task { @MainActor in
        guard let self else { return }
        self.item.button?.title = self.store.highestUsage.map { " \($0)%" } ?? ""
      }
    }
  }
  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else if let button = item.button {
      // Bound the entire panel before presenting it. Intrinsic ScrollView sizing can
      // otherwise grow the hosting view past the screen and push its header offscreen.
      let screen = button.window?.screen ?? NSScreen.main
      let height = min(620, (screen?.visibleFrame.height ?? 700) - 32)
      let controller = NSHostingController(
        rootView: DashboardView(
          store: store, openSettings: { [weak self] in self?.showSettings() },
          panelHeight: height))
      controller.sizingOptions = []
      popover.contentViewController = controller
      popover.contentSize = NSSize(width: 370, height: height)
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
