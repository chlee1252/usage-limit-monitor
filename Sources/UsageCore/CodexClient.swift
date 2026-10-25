import Darwin
import Foundation

public enum CodexClient {
  public static func locateExecutable() -> String {
    let candidates = [
      "/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
  }
  /// Runs only account metadata RPCs; no model invocation or credential extraction.
  public static func read(executable: String, timeout: TimeInterval = 15) throws -> Snapshot {
    guard FileManager.default.isExecutableFile(atPath: executable) else {
      throw UsageError.message("Codex CLI를 찾지 못했습니다. 설정에서 실행 파일을 선택해 주세요.")
    }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server", "--listen", "stdio://"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] =
      URL(fileURLWithPath: executable).deletingLastPathComponent().path
      + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
    process.environment = environment
    try process.run()
    defer {
      try? input.fileHandleForWriting.close()
      if process.isRunning { process.terminate() }
      // Bounded cleanup, including an unresponsive CLI.
      let deadline = Date().addingTimeInterval(0.5)
      while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      try? output.fileHandleForReading.close()
    }
    func send(_ object: [String: Any]) throws {
      var data = try JSONSerialization.data(withJSONObject: object)
      data.append(10)
      try input.fileHandleForWriting.write(contentsOf: data)
    }
    try send([
      "id": 1, "method": "initialize",
      "params": ["clientInfo": ["name": "usage_monitor", "version": "0.1.0"]],
    ])
    var buffer = Data()
    var initialized = false
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      var descriptor = pollfd(
        fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
      let available = poll(&descriptor, 1, 200)
      guard available >= 0 else { throw UsageError.message("Codex 연결을 읽지 못했습니다.") }
      if available == 0 { continue }
      var bytes = [UInt8](repeating: 0, count: 8192)
      let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
      guard count > 0 else { throw UsageError.message("Codex 연결이 종료됐습니다. CLI 로그인 상태를 확인해 주세요.") }
      buffer.append(contentsOf: bytes.prefix(count))
      guard buffer.count < 4_000_000 else { throw UsageError.message("Codex 응답이 너무 큽니다.") }
      while let end = buffer.firstIndex(of: 10) {
        let line = buffer[..<end]
        buffer.removeSubrange(...end)
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let id = root["id"] as? Int
        else { continue }
        if root["error"] != nil {
          throw UsageError.message("Codex 조회에 실패했습니다. CLI에서 로그인한 뒤 다시 시도해 주세요.")
        }
        if id == 1 && !initialized {
          initialized = true
          try send(["method": "initialized"])
          try send(["id": 2, "method": "account/rateLimits/read"])
        } else if id == 2 {
          return try UsageParser.codex(Data(line))
        }
      }
    }
    throw UsageError.message("Codex 응답 시간이 초과됐습니다. 네트워크 상태를 확인해 주세요.")
  }
}
