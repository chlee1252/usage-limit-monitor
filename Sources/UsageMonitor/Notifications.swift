import Foundation
import UserNotifications

/// Bridge the completion-handler APIs so older SDKs never send unannotated
/// UserNotifications objects across an actor boundary. Only value types cross.
@MainActor enum Notifications {
  static func authorizationStatus() async -> UNAuthorizationStatus {
    let rawValue: Int = await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        continuation.resume(returning: settings.authorizationStatus.rawValue)
      }
    }
    return UNAuthorizationStatus(rawValue: rawValue) ?? .notDetermined
  }

  static func requestAuthorization() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
        granted, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: granted)
        }
      }
    }
  }

  static func post(identifier: String, title: String, body: String) async throws {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      UNUserNotificationCenter.current().add(request) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
}
