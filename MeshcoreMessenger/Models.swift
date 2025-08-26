//
//  Models.swift
//  MeshcoreMessenger
//

import Foundation

// MARK: - Data Models

enum MessageStatus: String, Hashable, Codable {
  case sending, sent, delivered, failed
}

struct ImageUploadProgress: Hashable, Codable {
  let sentChunks: Int
  let totalChunks: Int
}

struct Channel: Identifiable, Hashable, Codable {
  let id: UInt8
  var name: String
}

enum MessageContent: Hashable, Codable {
  case text(String)
  case image(data: Data, progress: ImageUploadProgress?)

  enum CodingKeys: String, CodingKey {
    case text, imageData, imageProgress
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let text = try container.decodeIfPresent(String.self, forKey: .text) {
      self = .text(text)
    } else {
      let data = try container.decode(Data.self, forKey: .imageData)
      let progress = try container.decodeIfPresent(ImageUploadProgress.self, forKey: .imageProgress)
      self = .image(data: data, progress: progress)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode(text, forKey: .text)
    case .image(let data, let progress):
      try container.encode(data, forKey: .imageData)
      try container.encodeIfPresent(progress, forKey: .imageProgress)
    }
  }
}

struct Message: Identifiable, Hashable, Codable {
  let id: UUID
  var content: MessageContent
  let isFromCurrentUser: Bool
  var status: MessageStatus
  var isRead: Bool

  init(content: MessageContent, isFromCurrentUser: Bool, status: MessageStatus, isRead: Bool = true)
  {
    self.id = UUID()
    self.content = content
    self.isFromCurrentUser = isFromCurrentUser
    self.status = status
    self.isRead = isRead
  }
}

struct Contact: Identifiable, Hashable, Codable {
  let id: UUID
  let publicKey: Data
  let name: String

  init(id: UUID = UUID(), publicKey: Data, name: String) {
    self.id = id
    self.publicKey = publicKey
    self.name = name
  }
}

struct NodeSettings: Equatable {
  var name: String = "Loading..."
  var radioFreq: UInt32 = 0
  var radioBw: UInt32 = 0
  var radioSf: UInt8 = 0
  var radioCr: UInt8 = 0
  var txPower: UInt8 = 0
}

// MARK: - Extensions

extension Data {
  func hexEncodedString() -> String {
    return map { String(format: "%02hhx", $0) }.joined()
  }

  init<T>(from value: T) {
    var value = value
    self.init(buffer: UnsafeBufferPointer(start: &value, count: 1))
  }

  func to<T>(type: T.Type) -> T {
    return self.withUnsafeBytes { $0.load(as: T.self) }
  }
}
