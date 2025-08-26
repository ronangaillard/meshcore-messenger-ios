//
//  WelcomePopupView.swift
//  MeshcoreMessenger
//

import SwiftUI

struct WelcomePopupView: View {
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        Image(systemName: "hand.wave.fill")
          .font(.system(size: 60))
          .foregroundColor(.blue)

        Text("Welcome!")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text(
          "This is an open-source app to use the Meshcore network. It's in a very early stage, so feel free to report any bugs. By the way, in the settings, you have a button to copy the logs; don't hesitate to use it and send them to me (r_o_n_a_n on Discord)."
        )
        .multilineTextAlignment(.center)
        .padding(.horizontal)

        Text(
          "You will need to remove MeshCore app so that it does not fetch messages from node, you may also need to restart iPhone to finish clearing BLE cache on iPhone."
        )
        .multilineTextAlignment(.center)
        .padding(.horizontal)

        Text(
          "You can send images with this app, but be really careful not to monopolize the bandwidth."
        )
        .font(.caption)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

        Button(action: {
          presentationMode.wrappedValue.dismiss()
        }) {
          Text("Got it!")
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(10)
        }
        .padding(.horizontal)
      }
      .padding()
      .navigationTitle("Welcome")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

struct WelcomePopupView_Previews: PreviewProvider {
  static var previews: some View {
    WelcomePopupView()
  }
}
