//
//  MessageService.swift
//  MeshcoreMessenger
//

import Foundation
import UserNotifications

class MessageService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

  // MARK: - Published Properties
  @Published var contacts: [Contact] = []
  @Published var channels: [Channel] { didSet { PersistenceService.saveChannels(channels) } }
  @Published var conversations: [Data: [Message]] {
    didSet { PersistenceService.saveConversations(conversations) }
  }
  @Published var channelConversations: [UInt8: [Message]] {
    didSet { PersistenceService.saveChannelConversations(channelConversations) }
  }
  @Published var settings = NodeSettings()
  @Published var contactToNavigateTo: Contact?
  @Published var channelToNavigateTo: Channel?

  // MARK: - Private State
  private var selfPublicKey: Data?
  private var pendingContacts: [Contact] = []
  private var ackCodeToContext: [UInt32: (messageID: UUID, contactKey: Data)] = [:]
  private var lastSentTextMessageID: UUID?
  private var lastSentTextMessageContactKey: Data?

  // MARK: - Initialization
  override init() {
    self.conversations = [:]
    self.channelConversations = [:]
    self.channels = []
    super.init()

    self.conversations = PersistenceService.loadConversations()
    self.channelConversations = PersistenceService.loadChannelConversations()
    self.channels = PersistenceService.loadChannels()

    NotificationCenter.default.addObserver(
      self, selector: #selector(onDataReceived), name: .bleDataReceived, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(onBleReady), name: .bleReady, object: nil)

    UNUserNotificationCenter.current().delegate = self
    requestNotificationPermission()
  }

  @objc private func onBleReady() {
    Logger.shared.log("MessageService: Received BLE Ready signal. Initializing session...")
    sendAppStart()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.getContacts()
    }
  }

  // MARK: - Data Handling
  @objc private func onDataReceived(notification: Notification) {
    guard let data = notification.object as? Data else { return }
    let responseCode = data[0]

    // This switch only handles message/contact/channel related codes
    switch responseCode {
    case 2...8, 16, 17, 0x10, 0x82, 0x83, 0x88:
      handleProtocolPacket(data)
    default:
      break  // Ignore codes not related to this service
    }
  }

  private func handleProtocolPacket(_ data: Data) {
    let responseCode = data[0]
    switch responseCode {

    case 6:  // RESP_CODE_SENT
      let ackCode = data.subdata(in: 2..<6).to(type: UInt32.self).littleEndian
      if let context = ackCodeToContext[ackCode] {
        Logger.shared.log("Message \(context.messageID) marked as 'Sent'.")
        updateMessageStatus(for: context.contactKey, messageID: context.messageID, newStatus: .sent)
      } else if let messageID = lastSentTextMessageID,
        let contactKey = lastSentTextMessageContactKey
      {
        // TODO: this is a hot fix, we should get messageID from context
        updateMessageStatus(for: contactKey, messageID: messageID, newStatus: .sent)
        self.lastSentTextMessageID = nil
        self.lastSentTextMessageContactKey = nil
      }
      break

    case 7, 16:  // RESP_CODE_CONTACT_MSG_RECV & V3
      Logger.shared.log("Direct message content received.")
      parseReceivedMessage(from: data)
      Logger.shared.log("   -> Checking for next message in queue...")
      syncNextMessage()
      break

    case 8, 17:  // RESP_CODE_CHANNEL_MSG_RECV & V3
      Logger.shared.log("Channel message received.")
      parseChannelMessage(from: data)
      break

    case 0x82:  // PUSH_CODE_SEND_CONFIRMED
      let ackCode = data.subdata(in: 1..<5).to(type: UInt32.self)
      if let context = ackCodeToContext[ackCode] {
        Logger.shared.log("Message \(context.messageID) marked as 'Delivered'.")
        updateMessageStatus(
          for: context.contactKey, messageID: context.messageID, newStatus: .delivered)
        ackCodeToContext.removeValue(forKey: ackCode)
      }
      break

    case 2:
      Logger.shared.log("Receiving contact list...")
      pendingContacts.removeAll()
      break
    case 3:
      parseContact(from: data)
      break
    case 4:
      Logger.shared.log("Contact list finished.")
      DispatchQueue.main.async { self.contacts = self.pendingContacts }
      break
    case 5:  // RESP_CODE_SELF_INFO
      Logger.shared.log("Receiving local node info.")
      guard data.count > 58 else {
        Logger.shared.log("   -> Error: SELF_INFO packet too short.")
        return
      }
      self.selfPublicKey = data.subdata(in: 4..<36)
      var newSettings = NodeSettings()
      newSettings.txPower = data[2]
      newSettings.radioFreq = data.subdata(in: 48..<52).to(type: UInt32.self).littleEndian
      newSettings.radioBw = data.subdata(in: 52..<56).to(type: UInt32.self).littleEndian
      newSettings.radioSf = data[56]
      newSettings.radioCr = data[57]
      newSettings.name =
        String(data: data.subdata(in: 58..<data.count), encoding: .utf8)?.replacingOccurrences(
          of: "\0", with: "") ?? "Unknown"

      DispatchQueue.main.async {
        self.settings = newSettings
        Logger.shared.log("   -> Node settings updated. TX Power: \(newSettings.txPower) dBm")
      }
      break
    case 0x10:
      Logger.shared.log("Node message queue is empty.")
      break
    case 0x83:
      Logger.shared.log("Notification received: a message is waiting. Requesting it now.")
      syncNextMessage()
    default:
      // This case is handled by another service or is truly unhandled.
      break
    }
  }

  // MARK: - Command Sending

  func getContacts() {
    Logger.shared.log("Sending CMD_GET_CONTACTS...")
    BLEManager.shared.writeData(Data([4]))
  }

  func sendAppStart() {
    Logger.shared.log("Sending CMD_APP_START to the node...")
    var frame = Data()
    frame.append(1)
    frame.append(1)  // App version
    frame.append(Data(count: 6))  // Reserved bytes
    frame.append("Meshcore iOS".data(using: .utf8)!)
    BLEManager.shared.writeData(frame)
  }

  func sendMessage(to contact: Contact, message: String) {
    guard !message.isEmpty else { return }
    let newMessage = Message(
      content: .text(message), isFromCurrentUser: true, status: .sending, isRead: true)

    Logger.shared.log("Sending CMD_SEND_TXT_MSG to \(contact.name)...")
    var frame = Data()
    frame.append(2)
    frame.append(0)
    frame.append(0)
    let timestamp = UInt32(Date().timeIntervalSince1970)
    var timestampLE = timestamp.littleEndian
    frame.append(Data(bytes: &timestampLE, count: 4))
    frame.append(contact.publicKey.prefix(6))
    frame.append(message.data(using: .utf8)!)

    ackCodeToContext[timestamp] = (newMessage.id, contact.publicKey)
    self.lastSentTextMessageID = newMessage.id
    self.lastSentTextMessageContactKey = contact.publicKey

    DispatchQueue.main.async {
      self.conversations[contact.publicKey, default: []].append(newMessage)
    }
    BLEManager.shared.writeData(frame)
  }

  func sendChannelMessage(to channel: Channel, message: String) {
    guard !message.isEmpty else { return }
    let newMessage = Message(content: .text(message), isFromCurrentUser: true, status: .sending)
    DispatchQueue.main.async {
      self.channelConversations[channel.id, default: []].append(newMessage)
    }

    Logger.shared.log("Sending CMD_SEND_CHANNEL_TXT_MSG to #\(channel.name)...")
    var frame = Data()
    frame.append(3)
    frame.append(0)
    frame.append(channel.id)
    let timestamp = UInt32(Date().timeIntervalSince1970)
    var timestampLE = timestamp.littleEndian
    frame.append(Data(bytes: &timestampLE, count: 4))

    let messageWithSender = "\(settings.name): \(message)"
    frame.append(messageWithSender.data(using: .utf8)!)
    BLEManager.shared.writeData(frame)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      if let index = self.channelConversations[channel.id]?.firstIndex(where: {
        $0.id == newMessage.id
      }) {
        self.channelConversations[channel.id]?[index].status = .sent
      }
    }
  }

  func syncNextMessage() {
    Logger.shared.log("Requesting next message from queue...")
    BLEManager.shared.writeData(Data([0x0A]))
  }

  func saveNodeName(_ newName: String) {
    Logger.shared.log("Sending CMD_SET_ADVERT_NAME...")
    var frame = Data()
    frame.append(8)
    frame.append(newName.data(using: .utf8)!)
    BLEManager.shared.writeData(frame)
  }

  func saveRadioParams(freq: UInt32, bw: UInt32, sf: UInt8, cr: UInt8) {
    Logger.shared.log("Sending CMD_SET_RADIO_PARAMS...")
    var frame = Data()
    frame.append(11)
    var freqLE = freq.littleEndian
    var bwLE = bw.littleEndian
    frame.append(Data(bytes: &freqLE, count: 4))
    frame.append(Data(bytes: &bwLE, count: 4))
    frame.append(sf)
    frame.append(cr)
    BLEManager.shared.writeData(frame)
  }

  func saveTxPower(_ newPower: UInt8) {
    Logger.shared.log("Sending CMD_SET_RADIO_TX_POWER...")
    var frame = Data()
    frame.append(12)
    frame.append(newPower)
    BLEManager.shared.writeData(frame)
  }

  func sendSelfAdvertisement(isFlooded: Bool) {
    Logger.shared.log("Sending CMD_SEND_SELF_ADVERT...")
    var frame = Data()
    frame.append(7)
    frame.append(isFlooded ? 1 : 0)
    BLEManager.shared.writeData(frame)
  }

  // MARK: - Data Parsing
  private func parseContact(from data: Data) {
    Logger.shared.log("Parsing contacts")
    guard data.count >= 132 else { return }
    let publicKey = data.subdata(in: 1..<33)
    let nameData = data.subdata(in: 100..<132)
    let name =
      String(bytes: nameData, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
    let newContact = Contact(publicKey: publicKey, name: name)

    Logger.shared.log("New contact name found : \(newContact.name)")

    if !pendingContacts.contains(where: { $0.publicKey == newContact.publicKey }) {
      pendingContacts.append(newContact)
      Logger.shared.log(
        "Parsed contact: \(newContact.name) with public key \(newContact.publicKey.hexEncodedString())"
      )
    }
  }

  private func parseReceivedMessage(from data: Data) {
    let textOffset = 13
    guard data.count > textOffset else { return }

    let pubkeyPrefix = data.subdata(in: 1..<7)
    let messageText =
      String(data: data.subdata(in: textOffset..<data.count), encoding: .utf8)
      ?? "Unreadable message"

    if let contact = contacts.first(where: { $0.publicKey.prefix(6) == pubkeyPrefix }) {
      let newMessage = Message(
        content: .text(messageText), isFromCurrentUser: false, status: .delivered, isRead: false)
      Logger.shared.log("Successfully parsed message '\(messageText)' from \(contact.name)")

      showNewMessageNotification(
        title: "New message from \(contact.name)",
        body: messageText,
        userInfo: ["contactPublicKeyHex": contact.publicKey.hexEncodedString()]
      )

      DispatchQueue.main.async {
        self.conversations[contact.publicKey, default: []].append(newMessage)
      }
    } else {
      Logger.shared.log(
        "Warning: Received message but could not find a matching contact for prefix \(pubkeyPrefix.hexEncodedString())"
      )
    }
  }

  private func parseChannelMessage(from data: Data) {
    let isV3 = (data[0] == 17)
    let textOffset = isV3 ? 11 : 8
    guard data.count > textOffset else { return }

    let channelID = data[isV3 ? 4 : 1]
    let messageText =
      String(data: data.subdata(in: textOffset..<data.count), encoding: .utf8)
      ?? "Unreadable message"

    guard let channel = self.channels.first(where: { $0.id == channelID }) else {
      Logger.shared.log("Warning: Received message for unknown channel ID \(channelID)")
      return
    }

    let isFromMe = messageText.hasPrefix(self.settings.name)
    let newMessage = Message(
      content: .text(messageText), isFromCurrentUser: isFromMe, status: .delivered,
      isRead: isFromMe ? true : false)

    DispatchQueue.main.async {
      self.channelConversations[channelID, default: []].append(newMessage)
    }

    if !isFromMe {
      let senderName = String(messageText.split(separator: ":").first ?? "Someone")
      showNewMessageNotification(
        title: "#\(channel.name)",
        body: messageText,
        userInfo: ["channelID": channel.id]
      )
    }
  }

  // MARK: - State Update Helpers
  func updateMessageStatus(for contactKey: Data, messageID: UUID, newStatus: MessageStatus) {
    guard var conversation = conversations[contactKey],
      let index = conversation.firstIndex(where: { $0.id == messageID })
    else {
      return
    }
    conversation[index].status = newStatus
    DispatchQueue.main.async {
      self.conversations[contactKey] = conversation
    }
  }

  func updateImageProgress(for contactKey: Data, messageID: UUID, progress: ImageUploadProgress?) {
    guard var conversation = conversations[contactKey],
      let index = conversation.firstIndex(where: { $0.id == messageID })
    else {
      return
    }
    guard case .image(let data, _) = conversation[index].content else { return }

    conversation[index].content = .image(data: data, progress: progress)
    DispatchQueue.main.async {
      self.conversations[contactKey] = conversation
    }
  }

  func markConversationAsRead(for contactKey: Data) {
    guard var conversation = conversations[contactKey] else { return }
    var wasModified = false
    for i in 0..<conversation.count {
      if !conversation[i].isFromCurrentUser && !conversation[i].isRead {
        conversation[i].isRead = true
        wasModified = true
      }
    }
    if wasModified {
      DispatchQueue.main.async {
        self.conversations[contactKey] = conversation
      }
      Logger.shared.log("Conversation with \(contactKey.hexEncodedString()) marked as read.")
    }
  }

  func markChannelAsRead(for channelID: UInt8) {
    guard var conversation = channelConversations[channelID] else { return }
    var wasModified = false
    for i in 0..<conversation.count {
      if !conversation[i].isFromCurrentUser && !conversation[i].isRead {
        conversation[i].isRead = true
        wasModified = true
      }
    }
    if wasModified {
      DispatchQueue.main.async {
        self.channelConversations[channelID] = conversation
      }
      Logger.shared.log("Channel #\(channelID) marked as read.")
    }
  }

  func hasUnreadMessages(in contactKey: Data) -> Bool {
    return conversations[contactKey]?.contains(where: { !$0.isFromCurrentUser && !$0.isRead })
      ?? false
  }

  func hasUnreadMessages(in channelID: UInt8) -> Bool {
    return channelConversations[channelID]?.contains(where: { !$0.isFromCurrentUser && !$0.isRead })
      ?? false
  }

  func getSelfPublicKey() -> Data? {
    return self.selfPublicKey
  }

  // MARK: - Notification Methods
  func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        Logger.shared.log("Notification permission granted.")
      } else if let error = error {
        Logger.shared.log("Error requesting notification permission: \(error.localizedDescription)")
      }
    }
  }

  func showNewMessageNotification(title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default
    content.userInfo = userInfo

    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {

    let userInfo = response.notification.request.content.userInfo

    if let publicKeyHex = userInfo["contactPublicKeyHex"] as? String {
      Logger.shared.log("Notification tapped for contact key: \(publicKeyHex)")
      if let targetContact = self.contacts.first(where: {
        $0.publicKey.hexEncodedString() == publicKeyHex
      }) {
        DispatchQueue.main.async {
          self.contactToNavigateTo = targetContact
        }
      }
    } else if let channelID = userInfo["channelID"] as? UInt8 {
      Logger.shared.log("Notification tapped for channel ID: \(channelID)")
      if let targetChannel = self.channels.first(where: { $0.id == channelID }) {
        DispatchQueue.main.async {
          self.channelToNavigateTo = targetChannel
        }
      }
    }

    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {

    Logger.shared.log("Notification received while app is in foreground.")

    completionHandler([.banner, .sound, .badge])
  }

}
