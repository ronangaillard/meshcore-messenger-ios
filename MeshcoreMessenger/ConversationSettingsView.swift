// ConversationSettingsView.swift

import SwiftUI

struct ConversationSettingsView: View {
  let contact: Contact
  @EnvironmentObject var messageService: MessageService
  @Environment(\.presentationMode) var presentationMode

  private var isEchoEnabled: Binding<Bool> {
    Binding<Bool>(
      get: {
        self.messageService.echoEnabledContacts[contact.publicKey] ?? false
      },
      set: { _ in
        self.messageService.toggleEcho(for: contact.publicKey)
      }
    )
  }

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Message Settings")) {
          Toggle("Echo Mode", isOn: isEchoEnabled)
            .padding()
        }

        Section(
          footer: Text(
            "When Echo Mode is enabled, any message received from this contact will be automatically sent back to them. Echo mode is handled on the app side, so the app need to be connected to the node for the echo to work."
          )
        ) {
          EmptyView()
        }
      }
      .navigationTitle("Conversation Settings")
      .navigationBarItems(
        trailing:
          Button("Done") {
            presentationMode.wrappedValue.dismiss()
          }
      )
    }
  }
}
