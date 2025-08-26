# Meshcore Messenger iOS

An experimental iOS companion app for Meshcore BLE nodes, built with SwiftUI. This application allows users to interact with the mesh network to send text messages, share images, and manage node settings directly from their iPhone.

## Features

* **Direct Messaging**: Engage in one-on-one conversations with other nodes on the network.  
* **Group Channels**: Participate in public group conversations.  
* **Image Sharing**: Send and receive compressed images over the low-bandwidth network.  
* **Node Configuration**: Adjust radio parameters (frequency, bandwidth, SF, etc.) and other node settings on the fly.  
* **Persistent Chat History**: All conversations are saved locally on your device.  
* **Local Notifications**: Get notified of new messages even when the app is in the background.  

## Architecture

The application is built using modern SwiftUI and follows a service-oriented architecture to separate concerns, making the codebase clean and maintainable.

* **BLEManager.swift**: The low-level Bluetooth layer. Its sole responsibility is to establish and maintain a connection with the Meshcore node, and to send/receive raw data packets. It uses NotificationCenter to broadcast events (like received data) to other services.  
* **MessageService.swift**: The primary logic layer for user-facing features. It handles contacts, channels, text messages, and node settings. It listens to data broadcasts from BLEManager and parses packets relevant to its domain.  
* **ImageService.swift**: A specialized service dedicated entirely to the complex logic of image transfer. It manages the chunking, sending, and reassembly of image packets.  
* **PersistenceService.swift**: A simple, static service that handles the saving and loading of all Codable data models (conversations, channels) to and from the device's local storage.  
* **SwiftUI Views**: The entire UI is built with SwiftUI, with views like ChatView, ChannelChatView, and SettingsView reacting to state changes published by the services.

## Technical Deep Dive: Image Transfer Protocol

Sending images over a low-bandwidth mesh network presents a significant challenge due to the very small packet size limit (**184 bytes** of payload). It's impossible to send an image in a single packet.  
This app implements a custom protocol on top of the existing `CMD_SEND_RAW_DATA` command to manage this.

### 1\. The Challenge: Packet Size Limitation

A single raw data packet can only carry a tiny amount of data. Even a heavily compressed thumbnail image is several kilobytes in size. Therefore, the image must be fragmented into many small pieces ("chunks").

### 2\. The Solution: Chunking & Reassembly

The process is as follows:

1. **Preparation**: The selected image is first scaled down (e.g., to 96x96 pixels) and aggressively compressed into a JPEG format to minimize its total size.  
2. **Chunking**: The resulting Data is split into small chunks, each sized to fit within the packet limit while leaving room for a custom header.  
3. **Custom Header**: Each chunk is prepended with a custom 14-byte header to facilitate reassembly on the receiving end.

The structure of the payload sent with `CMD_SEND_RAW_DATA` is:

| Field | Size (bytes) | Description |
| :---- | :---- | :---- |
| **Sender Prefix** | 6 | The first 6 bytes of the sender's public key. |
| **Image ID** | 4 | A random UInt32 to uniquely identify this image transfer. |
| **Chunk Index** | 2 | The sequence number of this chunk (e.g., 0, 1, 2...). |
| **Total Chunks** | 2 | The total number of chunks for this image. |
| **Image Data** | Up to 136 | The actual bytes of the compressed image. |

### 3\. Flow Control and Reliability

To prevent overwhelming the node's limited memory buffer, the app implements a robust flow control mechanism:

* After sending a chunk, the app **waits** for a `RESP_CODE_OK` (value `0`) acknowledgement from the node.  
* Only after receiving this ACK does it proceed to send the next chunk.  
* If the node's buffer is full, it responds with a `RESP_CODE_ERR` (value `1`) with an error code `ERR_CODE_TABLE_FULL` (value `3`).  
* When the app receives this error, it waits for 1 second and **retries sending the same chunk**, assuming the node has had time to clear its buffer.

This ACK-based flow control ensures that the image transfer is as fast as the node can handle without losing packets due to buffer overflow.

## How to Build

1. Clone the repository.  
2. Open `MeshcoreMessenger.xcodeproj` in Xcode.  
3. Select your iPhone as the build target (Bluetooth is not available on the simulator).  
4. Ensure you have a developer account set up in Xcode for code signing.  
5. Build and run the application.

## Dependencies

This project is built with pure SwiftUI and CoreBluetooth and has **no external dependencies**.

