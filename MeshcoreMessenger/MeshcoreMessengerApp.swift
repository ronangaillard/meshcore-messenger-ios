//
//  MeshcoreMessengerApp.swift
//  MeshcoreMessenger
//

import SwiftUI

@main
struct MeshcoreMessengerApp: App {
  @StateObject private var bleManager = BLEManager.shared
  @StateObject private var messageService = MessageService()
  @StateObject private var imageService: ImageService

  init() {
    let msgService = MessageService()
    _messageService = StateObject(wrappedValue: msgService)
    _imageService = StateObject(wrappedValue: ImageService(messageService: msgService))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(bleManager)
        .environmentObject(messageService)
        .environmentObject(imageService)
    }
  }
}
