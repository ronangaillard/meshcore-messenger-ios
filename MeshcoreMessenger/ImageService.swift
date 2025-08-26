//
//  ImageService.swift
//  MeshcoreMessenger
//

import Foundation
import UIKit

class ImageService: ObservableObject {

  private let messageService: MessageService

  // MARK: - Private State for Image Transfer
  private var imageChunksToSend: [Data] = []
  private var currentChunkIndex = 0
  private var currentImageTransferMessageID: UUID?
  private var currentImageTransferContactKey: Data?

  private var imageReassemblyBuffer: [UInt32: [UInt16: Data]] = [:]
  private var totalChunksForImage: [UInt32: UInt16] = [:]
  private var imageSender: [UInt32: Data] = [:]

  private var imageTimers: [UInt32: Timer] = [:]
  private let imageTimeoutInterval: TimeInterval = 30.0

  init(messageService: MessageService) {
    self.messageService = messageService
    NotificationCenter.default.addObserver(
      self, selector: #selector(onDataReceived), name: .bleDataReceived, object: nil)
  }

  @objc private func onDataReceived(notification: Notification) {
    guard let data = notification.object as? Data else { return }
    let responseCode = data[0]

    // This switch only handles image transfer related codes
    switch responseCode {
    case 0, 1, 0x84:
      handleImagePacket(data)
    default:
      break
    }
  }

  private func handleImagePacket(_ data: Data) {
    let responseCode = data[0]
    switch responseCode {

    case 0:  // RESP_CODE_OK (ACK for an image chunk)
      if !imageChunksToSend.isEmpty {
        Logger.shared.log("   -> OK received. Sending next packet.")
        // The delay gives the radio network time to "breathe"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          self.sendNextChunk()
        }
      }
      break

    case 1:  // RESP_CODE_ERR
      if !imageChunksToSend.isEmpty {
        Logger.shared.log(
          "Error from node (buffer likely full). Waiting 1s and retrying same packet...")
        if currentChunkIndex > 0 {
          currentChunkIndex -= 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          self.sendNextChunk()
        }
      }
      break

    case 0x84:  // PUSH_CODE_RAW_DATA
      Logger.shared.log("Raw data packet received.")
      let payload = data.subdata(in: 4..<data.count)
      handleImageChunkPayload(payload)
      break

    default:
      break
    }
  }

  // MARK: - Image Sending Logic

  func sendImage(imageData: Data, to contact: Contact) {
    Logger.shared.log("Preparing image for sending...")

    guard let preparedData = prepareImageForSending(imageData) else {
      Logger.shared.log("Error: Could not prepare image.")
      return
    }

    Logger.shared.log("   -> Compressed size: \(preparedData.count) bytes")

    guard let selfKey = messageService.getSelfPublicKey() else {
      Logger.shared.log("Error: Cannot send image because local public key is unknown.")
      return
    }

    Logger.shared.log("Sender key is: \(selfKey.hexEncodedString())")

    let chunks = chunk(data: preparedData, from: selfKey, to: contact)

    let newMessage = Message(
      content: .image(
        data: preparedData, progress: .init(sentChunks: 0, totalChunks: chunks.count)),
      isFromCurrentUser: true,
      status: .sending
    )
    DispatchQueue.main.async {
      self.messageService.conversations[contact.publicKey, default: []].append(newMessage)
    }

    self.imageChunksToSend = chunks
    self.currentChunkIndex = 0

    self.currentImageTransferMessageID = newMessage.id
    self.currentImageTransferContactKey = contact.publicKey

    Logger.shared.log("   -> Split into \(chunks.count) packets. Starting send.")
    sendNextChunk()
  }

  private func sendNextChunk() {
    guard let messageID = currentImageTransferMessageID,
      let contactKey = currentImageTransferContactKey
    else { return }

    if currentChunkIndex >= imageChunksToSend.count {
      Logger.shared.log("All packets have been sent to the local node.")
      messageService.updateMessageStatus(for: contactKey, messageID: messageID, newStatus: .sent)
      messageService.updateImageProgress(for: contactKey, messageID: messageID, progress: nil)

      self.imageChunksToSend.removeAll()
      self.currentImageTransferMessageID = nil
      self.currentImageTransferContactKey = nil
      return
    }

    messageService.updateImageProgress(
      for: contactKey,
      messageID: messageID,
      progress: .init(sentChunks: currentChunkIndex, totalChunks: imageChunksToSend.count)
    )

    let chunk = imageChunksToSend[currentChunkIndex]
    Logger.shared.log("   -> Sending packet \(currentChunkIndex + 1)/\(imageChunksToSend.count)...")
    BLEManager.shared.writeData(chunk)

    currentChunkIndex += 1
  }

  private func prepareImageForSending(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let targetSize = CGSize(width: 96, height: 96)
    let scaledImage = image.preparingThumbnail(of: targetSize)

    return scaledImage?.jpegData(compressionQuality: 0.5)
  }

  private func chunk(data: Data, from senderPublicKey: Data, to contact: Contact) -> [Data] {
    // The header contains metadata for reassembly
    let headerSize = 6 + 4 + 2 + 2  // sender(6) + imageID(4) + index(2) + total(2)
    let payloadSize = 150 - headerSize  // Ensure total chunk fits in a packet

    let totalChunks = Int(ceil(Double(data.count) / Double(payloadSize)))
    var chunks: [Data] = []
    let imageID = UInt32.random(in: 0...UInt32.max)

    for i in 0..<totalChunks {
      let startIndex = i * payloadSize
      let endIndex = min(startIndex + payloadSize, data.count)
      let chunkData = data.subdata(in: startIndex..<endIndex)

      var header = Data()
      header.append(senderPublicKey.prefix(6))
      header.append(Data(from: imageID.littleEndian))
      header.append(Data(from: UInt16(i).littleEndian))
      header.append(Data(from: UInt16(totalChunks).littleEndian))

      var finalChunkPayload = Data()
      finalChunkPayload.append(header)
      finalChunkPayload.append(chunkData)

      // Build the final command frame for the node
      var frame = Data()
      frame.append(25)  // CMD_SEND_RAW_DATA
      frame.append(0)  // path_len (0 for simple direct send)
      frame.append(finalChunkPayload)

      chunks.append(frame)
    }
    return chunks
  }

  // MARK: - Image Receiving Logic

  private func handleImageChunkPayload(_ chunk: Data) {
    guard chunk.count >= 14 else {
      Logger.shared.log("Error: Received image packet is too short.")
      return
    }

    let senderPrefix = chunk.subdata(in: 0..<6)
    let imageID = chunk.subdata(in: 6..<10).to(type: UInt32.self).littleEndian
    let chunkIndex = chunk.subdata(in: 10..<12).to(type: UInt16.self).littleEndian
    let totalChunks = chunk.subdata(in: 12..<14).to(type: UInt16.self).littleEndian
    let chunkData = chunk.subdata(in: 14..<chunk.count)

    if imageReassemblyBuffer[imageID] == nil {
      imageReassemblyBuffer[imageID] = [:]
      totalChunksForImage[imageID] = totalChunks
    }

    imageSender[imageID] = senderPrefix

    imageTimers[imageID]?.invalidate()
    imageTimers[imageID] = Timer.scheduledTimer(
      withTimeInterval: imageTimeoutInterval, repeats: false
    ) { [weak self] _ in
      self?.handleImageTimeout(imageID: imageID)
    }

    imageReassemblyBuffer[imageID]?[chunkIndex] = chunkData
    Logger.shared.log(
      "   -> Stored packet \(chunkIndex + 1)/\(totalChunks) for image ID \(imageID)")

    if let buffer = imageReassemblyBuffer[imageID], buffer.count == totalChunks {
      Logger.shared.log("All packets for image \(imageID) have arrived! Reassembling...")
      imageTimers[imageID]?.invalidate()
      imageTimers.removeValue(forKey: imageID)

      var finalImageData = Data()
      for i in 0..<totalChunks {
        if let piece = buffer[i] {
          finalImageData.append(piece)
        }
      }

      if let contact = messageService.contacts.first(where: {
        $0.publicKey.prefix(6) == senderPrefix
      }) {
        let newMessage = Message(
          content: .image(data: finalImageData, progress: nil), isFromCurrentUser: false,
          status: .delivered, isRead: false)

        messageService.showNewMessageNotification(
          title: "New message from \(contact.name)",
          body: "Image",
          userInfo: ["contactPublicKeyHex": contact.publicKey.hexEncodedString()]
        )

        DispatchQueue.main.async {
          self.messageService.conversations[contact.publicKey, default: []].append(newMessage)
        }
      }

      imageReassemblyBuffer.removeValue(forKey: imageID)
      totalChunksForImage.removeValue(forKey: imageID)
    }
  }

  private func handleImageTimeout(imageID: UInt32) {
    guard let totalChunks = totalChunksForImage[imageID],
      let receivedChunks = imageReassemblyBuffer[imageID]?.count
    else {
      // clean if chunk cannot be reassembled
      imageReassemblyBuffer.removeValue(forKey: imageID)
      totalChunksForImage.removeValue(forKey: imageID)
      imageTimers.removeValue(forKey: imageID)
      return
    }

    Logger.shared.log(
      "Image transfer for ID \(imageID) timed out. Received \(receivedChunks) out of \(totalChunks) packets."
    )

    guard let firstChunk = imageReassemblyBuffer[imageID]?.values.first,
      firstChunk.count >= 6
    else {
      imageReassemblyBuffer.removeValue(forKey: imageID)
      totalChunksForImage.removeValue(forKey: imageID)
      imageTimers.removeValue(forKey: imageID)
      return
    }

    let senderPrefix = imageSender[imageID]

    if let contact = messageService.contacts.first(where: { $0.publicKey.prefix(6) == senderPrefix }
    ) {
      let errorMessage =
        "⚠️ Image transfer failed (Received : \(receivedChunks) out of \(totalChunks) packets)."

      let errorContent = MessageContent.text(errorMessage)
      let errorMessageObject = Message(
        content: errorContent, isFromCurrentUser: false, status: .failed)

      DispatchQueue.main.async {
        self.messageService.conversations[contact.publicKey, default: []].append(errorMessageObject)
      }
    }

    imageReassemblyBuffer.removeValue(forKey: imageID)
    totalChunksForImage.removeValue(forKey: imageID)
    imageTimers.removeValue(forKey: imageID)
  }
}
