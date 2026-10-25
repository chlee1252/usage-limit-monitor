import Foundation

public enum Storage {
  public static var directory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/UsageMonitor", isDirectory: true)
  }
  public static func save<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
}

public enum ClaudeBridge {
  public static var settingsURL: URL {
    let config =
      ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
    return URL(fileURLWithPath: config).appendingPathComponent("settings.json")
  }
  public static func install(
    executable: String, settings: URL = settingsURL, directory: URL = Storage.directory
  ) throws {
    let manager = FileManager.default
    let script = directory.appendingPathComponent("claude-statusline.sh")
    let backup = directory.appendingPathComponent("claude-statusline-backup.json")
    var root: [String: Any] = [:]
    if manager.fileExists(atPath: settings.path) {
      guard
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings))
          as? [String: Any]
      else {
        throw UsageError.message("Claude 설정 파일을 읽을 수 없습니다. 기존 설정은 변경하지 않았습니다.")
      }
      root = object
    }
    let installedCommand = quote(script.path)
    if (root["statusLine"] as? [String: Any])?["command"] as? String == installedCommand { return }
    // Save the exact previous statusLine, keeping unrelated settings untouched.
    let previous = root["statusLine"]
    let oldCommand = (previous as? [String: Any])?["command"] as? String
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let backupData = try JSONSerialization.data(
      withJSONObject: ["previous": previous ?? NSNull()], options: [.prettyPrinted])
    try backupData.write(to: backup, options: .atomic)
    let continuation =
      oldCommand.map { "printf '%s' \"$payload\" | /bin/sh -c \(quote($0))" }
      ?? "printf 'Usage Monitor 연결됨'"
    let body = """
      #!/bin/sh
      payload=$(cat)
      printf '%s' "$payload" | \(quote(executable)) --capture-claude >/dev/null 2>&1
      \(continuation)

      """
    try body.write(to: script, atomically: true, encoding: .utf8)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    var status = previous as? [String: Any] ?? [:]
    status["type"] = "command"
    status["command"] = installedCommand
    root["statusLine"] = status
    try manager.createDirectory(
      at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(
      to: settings, options: .atomic)
  }
  public static func uninstall(settings: URL = settingsURL, directory: URL = Storage.directory)
    throws
  {
    let script = directory.appendingPathComponent("claude-statusline.sh")
    let backup = directory.appendingPathComponent("claude-statusline-backup.json")
    guard
      var root = try JSONSerialization.jsonObject(with: Data(contentsOf: settings))
        as? [String: Any],
      (root["statusLine"] as? [String: Any])?["command"] as? String == quote(script.path)
    else {
      throw UsageError.message("현재 상태 표시줄은 Usage Monitor가 관리하고 있지 않습니다.")
    }
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any]
    if let previous = saved?["previous"], !(previous is NSNull) {
      root["statusLine"] = previous
    } else {
      root.removeValue(forKey: "statusLine")
    }
    try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(
      to: settings, options: .atomic)
  }
  private static func quote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
