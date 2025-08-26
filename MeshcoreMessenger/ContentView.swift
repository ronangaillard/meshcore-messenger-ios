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

  enum ActiveView {
    case contacts, channels
  }
  @State private var activeView: ActiveView = .contacts

  var body: some View {
    NavigationView {
      VStack {
        Text(bleManager.isConnected ? "Connected" : "Disconnected")
          .foregroundColor(bleManager.isConnected ? .green : .red)
          .padding(.bottom, 5)

        Picker("View", selection: $activeView) {
          Text("Contacts").tag(ActiveView.contacts)
          Text("Channels").tag(ActiveView.channels)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)

        if activeView == .contacts {
          contactsList
        } else {
          channelsList
        }
      }
      .navigationTitle(activeView == .contacts ? "Contacts" : "Channels")
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: { showSettingsSheet = true }) {
            Image(systemName: "gearshape")
          }
          .disabled(!bleManager.isConnected)
        }
        ToolbarItem(placement: .principal) {
          Button(action: {
            messageService.sendSelfAdvertisement(isFlooded: false)
          }) {
            Image(systemName: "antenna.radiowaves.left.and.right")
          }
          .disabled(!bleManager.isConnected)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            messageService.getContacts()
          }) {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(!bleManager.isConnected)
        }
      }
      .sheet(isPresented: $showSettingsSheet) {
        SettingsView(messageService: messageService)
          .environmentObject(messageService)
      }
      .onReceive(messageService.$contactToNavigateTo, perform: processContactNavigation)
      .onReceive(messageService.$channelToNavigateTo, perform: processChannelNavigation)

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
      .sheet(isPresented: $showWelcomePopup) {
        WelcomePopupView()
      }
      .onAppear {
        checkFirstLaunch()
      }
    }
    .navigationViewStyle(.stack)
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
          if messageService.hasUnreadMessages(in: contact.publicKey) {
            Circle()
              .fill(Color.blue)
              .frame(width: 10, height: 10)
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
          if messageService.hasUnreadMessages(in: channel.id) {
            Circle()
              .fill(Color.blue)
              .frame(width: 10, height: 10)
          }
        }
      }
    }
  }

  private func processContactNavigation(to contact: Contact?) {
    guard let contact = contact else { return }
    Logger.shared.log("Processing navigation to contact \(contact.name)...")

    self.contactNavigationTarget = contact

    self.activeView = .contacts

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.isContactNavigationActive = true
    }

    self.messageService.contactToNavigateTo = nil
  }

  private func processChannelNavigation(to channel: Channel?) {
    guard let channel = channel else { return }
    Logger.shared.log("Processing navigation to channel \(channel.name)...")

    self.channelNavigationTarget = channel

    self.activeView = .channels

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
