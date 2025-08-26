//
//  ChannelChatView.swift
//  MeshcoreMessenger
//

import SwiftUI

struct ChannelChatView: View {
  let channel: Channel
  @EnvironmentObject var messageService: MessageService
  @State private var messageText: String = ""

  private let characterLimit = 140

  private var messages: [Message] {
    messageService.channelConversations[channel.id] ?? []
  }

  var body: some View {
    VStack {
      ScrollViewReader { scrollViewProxy in
        ScrollView {
          ForEach(messages) { message in
            MessageView(message: message)
          }
        }
        .onChange(of: messages) { _ in
          if let lastMessage = messages.last {
            withAnimation {
              scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
          }
        }
      }

      Spacer()

      HStack {
        VStack(alignment: .trailing) {
          TextField("Message in #\(channel.name)", text: $messageText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.leading)

          Text("\(messageText.count) / \(characterLimit)")
            .font(.caption)
            .foregroundColor(messageText.count > characterLimit ? .red : .gray)
            .padding(.trailing, 5)
        }

        Button(action: sendMessage) {
          Image(systemName: "arrow.up.circle.fill")
            .font(.largeTitle)
        }
        .padding(.trailing)
        .disabled(messageText.isEmpty || messageText.count > characterLimit)
      }
      .padding(.bottom)
    }
    .navigationTitle("#\(channel.name)")
    .onAppear {
      messageService.markChannelAsRead(for: channel.id)
    }
  }

  func sendMessage() {
    guard !messageText.isEmpty else { return }
    messageService.sendChannelMessage(to: channel, message: messageText)
    messageText = ""
  }
}
