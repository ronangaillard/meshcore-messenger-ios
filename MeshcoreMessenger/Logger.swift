//
//  Logger.swift
//  MeshcoreMessenger
//

import Foundation

class Logger {
  static let shared = Logger()

  private var logEntries: [String] = []
  private let logLimit = 500

  private init() {}

  /// Logs a message to the console and stores it in memory.
  func log(_ message: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    let timestamp = dateFormatter.string(from: Date())
    let fullLogEntry = "[\(timestamp)] - \(message)"

    print(fullLogEntry)

    // Add to our in-memory store on the main thread to ensure thread safety
    DispatchQueue.main.async {
      self.logEntries.append(fullLogEntry)

      if self.logEntries.count > self.logLimit {
        self.logEntries.removeFirst()
      }
    }
  }

  /// Returns all stored log entries as a single string.
  func getLogHistory() -> String {
    return logEntries.joined(separator: "\n")
  }
}
