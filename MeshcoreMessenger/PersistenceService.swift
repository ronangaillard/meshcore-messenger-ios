//
//  PersistenceService.swift
//  MeshcoreMessenger
//

import Foundation

struct PersistenceService {

  // MARK: - Private File Handling

  private static func getFileURL(forName name: String) -> URL {
    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      .first!
    return documentsDirectory.appendingPathComponent(name)
  }

  private static func save<T: Encodable>(_ object: T, to fileName: String) {
    let fileURL = getFileURL(forName: fileName)
    let encoder = JSONEncoder()
    do {
      let data = try encoder.encode(object)
      try data.write(to: fileURL, options: .atomicWrite)
      Logger.shared.log("Data saved to \(fileName).")
    } catch {
      Logger.shared.log("Error saving to \(fileName): \(error)")
    }
  }

  private static func load<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let fileURL = getFileURL(forName: fileName)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }
    do {
      let data = try Data(contentsOf: fileURL)
      let decoder = JSONDecoder()
      let loadedObject = try decoder.decode(T.self, from: data)
      Logger.shared.log("Data loaded from \(fileName).")
      return loadedObject
    } catch {
      Logger.shared.log("Error loading from \(fileName): \(error).")
      return nil
    }
  }

  // MARK: - Public API

  static func saveConversations(_ conversations: [Data: [Message]]) {
    save(conversations, to: "conversations.json")
  }

  static func loadConversations() -> [Data: [Message]] {
    return load(from: "conversations.json", as: [Data: [Message]].self) ?? [:]
  }

  static func saveChannelConversations(_ conversations: [UInt8: [Message]]) {
    save(conversations, to: "channel_conversations.json")
  }

  static func loadChannelConversations() -> [UInt8: [Message]] {
    return load(from: "channel_conversations.json", as: [UInt8: [Message]].self) ?? [:]
  }

  static func saveChannels(_ channels: [Channel]) {
    save(channels, to: "channels.json")
  }

  static func loadChannels() -> [Channel] {
    return load(from: "channels.json", as: [Channel].self) ?? [Channel(id: 0, name: "Public")]
  }
}
