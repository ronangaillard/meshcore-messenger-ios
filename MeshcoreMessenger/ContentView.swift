//
//  ContentView.swift
//  MeshcoreMessenger
//

import SwiftUI

struct ContentView: View {
  @EnvironmentObject var bleManager: BLEManager
  @EnvironmentObject var messageService: MessageService
  @EnvironmentObject var imageService: ImageService

  @State private var showSettingsSheet = false

  @State private var contactNavigationTarget: Contact? = nil
  @State private var isContactNavigationActive = false
  @State private var channelNavigationTarget: Channel? = nil
  @State private var isChannelNavigationActive = false
  @State private var showWelcomePopup = false

  var body: some View {
    TabView {
      // Tab 1: Contacts
      NavigationView {
        VStack {
          contactsList
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarItems
          }
          ToolbarItem(placement: .navigationBarTrailing) {
            trailingToolbarItems
          }
        }
      }
      .tabItem {
        Label("Contacts", systemImage: "person.2.fill")
      }

      // Tab 2: Channels
      NavigationView {
        VStack {
          channelsList
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarItems
          }
          ToolbarItem(placement: .navigationBarTrailing) {
            trailingToolbarItems
          }
        }
      }
      .tabItem {
        Label("Channels", systemImage: "antenna.radiowaves.left.and.right")
      }
    }
    .background(.bar)  // Ajoute l'arrière-plan natif de la barre
    .sheet(isPresented: $showSettingsSheet) {
      SettingsView(messageService: messageService)
        .environmentObject(messageService)
    }
    .onReceive(messageService.$contactToNavigateTo, perform: processContactNavigation)
    .onReceive(messageService.$channelToNavigateTo, perform: processChannelNavigation)
    .sheet(isPresented: $showWelcomePopup) {
      WelcomePopupView()
    }
    .onAppear {
      checkFirstLaunch()
    }
    .background(
      VStack {
        NavigationLink(
          destination: contactNavigationTarget.map { ChatView(contact: $0) },
          isActive: $isContactNavigationActive
        ) { EmptyView() }

        NavigationLink(
          destination: channelNavigationTarget.map { ChannelChatView(channel: $0) },
          isActive: $isChannelNavigationActive
        ) { EmptyView() }
      }
    )
  }

  // MARK: - Subviews

  private var leadingToolbarItems: some View {
    VStack(alignment: .leading) {
      Text(messageService.settings.name)
        .font(.headline)

      if bleManager.isConnected {
        HStack(spacing: 4) {
          if messageService.batteryMilliVolts != nil {
            Text(batteryPercentageString(millivolts: messageService.batteryMilliVolts))
          }
          Text(" - Connected")
        }
        .font(.caption)
        .foregroundColor(.green)
      } else {
        Text("Disconnected")
          .font(.caption)
          .foregroundColor(.red)
      }
    }
  }

  private var trailingToolbarItems: some View {
    HStack(spacing: 15) {
      Button(action: { showSettingsSheet = true }) {
        Image(systemName: "gearshape")
      }
      .disabled(!bleManager.isConnected)

      Button(action: {
        messageService.sendSelfAdvertisement(isFlooded: false)
      }) {
        Image(systemName: "antenna.radiowaves.left.and.right")
      }
      .disabled(!bleManager.isConnected)

      Button(action: {
        messageService.getContacts()
        messageService.getBatteryAndStorage()
      }) {
        Image(systemName: "arrow.clockwise")
      }
      .disabled(!bleManager.isConnected)
    }
  }

  private var contactsList: some View {
    List(messageService.contacts) { contact in
      NavigationLink(destination: ChatView(contact: contact)) {
        HStack {
          VStack(alignment: .leading) {
            Text(contact.name)
              .font(.headline)
            Text("Key: \(contact.publicKey.hexEncodedString().prefix(12))...")
              .font(.caption)
              .foregroundColor(.gray)
          }
          Spacer()
          if let unreadCount = messageService.unreadMessageCounts[contact.publicKey],
            unreadCount > 0
          {
            Text("\(unreadCount)")
              .font(.caption)
              .fontWeight(.bold)
              .foregroundColor(.white)
              .padding(5)
              .background(Color.red)
              .clipShape(Circle())
          }
        }
      }
    }
  }

  private var channelsList: some View {
    List(messageService.channels) { channel in
      NavigationLink(destination: ChannelChatView(channel: channel)) {
        HStack {
          Text(channel.name)
          Spacer()
          if let unreadCount = messageService.channelConversations[channel.id]?.filter({
            !$0.isFromCurrentUser && !$0.isRead
          }).count, unreadCount > 0 {
            Text("\(unreadCount)")
              .font(.caption)
              .fontWeight(.bold)
              .foregroundColor(.white)
              .padding(5)
              .background(Color.red)
              .clipShape(Circle())
          }
        }
      }
    }
  }

  // MARK: - Helper Methods

  private func batteryPercentageString(millivolts: Int?) -> String {
    guard let mV = millivolts else { return "" }
    // Based on a standard LiPo battery voltage range
    let minVoltage: Float = 3000.0  // Empty
    let maxVoltage: Float = 4200.0  // Full

    let clampedVoltage = max(minVoltage, min(Float(mV), maxVoltage))
    let percentage = ((clampedVoltage - minVoltage) / (maxVoltage - minVoltage)) * 100

    return String(format: "⚡️%.0f%%", percentage)
  }

  private func processContactNavigation(to contact: Contact?) {
    guard let contact = contact else { return }
    Logger.shared.log("Processing navigation to contact \(contact.name)...")

    self.contactNavigationTarget = contact

    // Switch to the Contacts tab if not already there.
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootViewController = windowScene.windows.first?.rootViewController,
      let tabBarController = rootViewController as? UITabBarController
    {
      tabBarController.selectedIndex = 0  // Assuming Contacts is the first tab
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.isContactNavigationActive = true
    }

    self.messageService.contactToNavigateTo = nil
  }

  private func processChannelNavigation(to channel: Channel?) {
    guard let channel = channel else { return }
    Logger.shared.log("Processing navigation to channel \(channel.name)...")

    self.channelNavigationTarget = channel

    // Switch to the Channels tab if not already there.
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootViewController = windowScene.windows.first?.rootViewController,
      let tabBarController = rootViewController as? UITabBarController
    {
      tabBarController.selectedIndex = 1  // Assuming Channels is the second tab
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.isChannelNavigationActive = true
    }

    self.messageService.channelToNavigateTo = nil
  }

  private func checkFirstLaunch() {
    let launchedBefore = UserDefaults.standard.bool(forKey: "launchedBefore")
    if !launchedBefore {
      showWelcomePopup = true
      UserDefaults.standard.set(true, forKey: "launchedBefore")
    }
  }
}
