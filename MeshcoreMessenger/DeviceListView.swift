//
//  DeviceListView.swift
//  MeshcoreMessenger
//

import CoreBluetooth
import SwiftUI

struct DeviceListView: View {
  @EnvironmentObject var bleManager: BLEManager
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    NavigationView {
      VStack {
        if bleManager.discoveredPeripherals.isEmpty {
          Text("Scanning for nodes...")
            .foregroundColor(.secondary)
        } else {
          List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
            Button(action: {
              bleManager.connect(to: peripheral)
            }) {
              HStack {
                Text(peripheral.name ?? "Unknown Device")
                Spacer()
                Image(systemName: "chevron.right")
                  .foregroundColor(.secondary)
              }
            }
            .foregroundColor(.primary)
          }
        }
      }
      .navigationTitle("Available Nodes")
      .navigationBarItems(
        trailing: Button("Cancel") {
          presentationMode.wrappedValue.dismiss()
        })
    }
    .onAppear(perform: bleManager.startScan)
    .onDisappear(perform: bleManager.stopScan)
    .onReceive(bleManager.$isConnected) { isConnected in
      // Dismiss the sheet automatically once connection is established
      if isConnected {
        presentationMode.wrappedValue.dismiss()
      }
    }
  }
}
