//
//  SettingsView.swift
//  MeshcoreMessenger
//

import SwiftUI

struct SettingsView: View {
  // MARK: - Properties

  @EnvironmentObject var messageService: MessageService
  @EnvironmentObject var bleManager: BLEManager
  @Environment(\.presentationMode) var presentationMode

  // UI State variables are initialized directly from the MessageService once.
  @State private var nodeName: String
  @State private var frequency: String
  @State private var bandwidth: String
  @State private var spreadingFactor: UInt8
  @State private var codingRate: UInt8
  @State private var txPower: String
  @State private var initialSettingsLoaded: Bool

  // Local UI constants and state
  private let sfOptions: [UInt8] = [7, 8, 9, 10, 11, 12]
  private let crOptions: [UInt8] = [5, 6, 7, 8]
  @State private var copyButtonText = "Copy Logs"

  // MARK: - Initializer

  // Custom initializer to set the initial state from the source of truth (MessageService).
  // This runs only once when the view is created, preventing reloads from external updates.
  init(messageService: MessageService) {
    _nodeName = State(initialValue: messageService.settings.name)
    _frequency = State(
      initialValue: String(format: "%.1f", Float(messageService.settings.radioFreq) / 1000.0))
    _bandwidth = State(
      initialValue: String(format: "%.1f", Float(messageService.settings.radioBw) / 1000.0))
    _spreadingFactor = State(initialValue: messageService.settings.radioSf)
    _codingRate = State(initialValue: messageService.settings.radioCr)
    _txPower = State(initialValue: "\(messageService.settings.txPower)")
    initialSettingsLoaded = false
  }

  // MARK: - Body

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Node Connection")) {
          if bleManager.isConnected {
            Button(
              role: .destructive,
              action: {
                bleManager.disconnect()
                presentationMode.wrappedValue.dismiss()
              }
            ) {
              Text("Disconnect from Node")
            }
          } else {
            Text("Not Connected")
              .foregroundColor(.secondary)
          }
        }

        Section(header: Text("Public Info")) {
          HStack {
            Text("Node Name")
            Spacer()
            TextField("Name", text: $nodeName)
              .multilineTextAlignment(.trailing)
          }
        }
        .disabled(!bleManager.isConnected)

        Section(header: Text("Radio Settings")) {
          HStack {
            Text("Frequency (MHz)")
            Spacer()
            TextField("Freq.", text: $frequency)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }
          HStack {
            Text("Bandwidth (kHz)")
            Spacer()
            TextField("BW", text: $bandwidth)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }

          Picker("Spreading Factor (SF)", selection: $spreadingFactor) {
            ForEach(sfOptions, id: \.self) {
              Text("\($0)").tag($0)
            }
          }

          Picker("Coding Rate (CR)", selection: $codingRate) {
            ForEach(crOptions, id: \.self) {
              Text("\($0)").tag($0)
            }
          }

          HStack {
            Text("Transmit Power (dBm)")
            Spacer()
            TextField("TX Power", text: $txPower)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
          }
        }
        .disabled(!bleManager.isConnected)

        Section(header: Text("Debugging")) {
          Button(action: copyLogsToClipboard) {
            HStack {
              Text(copyButtonText)
              Spacer()
              Image(systemName: "doc.on.doc")
            }
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            presentationMode.wrappedValue.dismiss()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            saveSettings()
            presentationMode.wrappedValue.dismiss()
          }
          .disabled(!bleManager.isConnected)
        }
      }
      .onAppear(perform: loadInitialSettings)
    }
  }

  // MARK: - Methods

  private func loadInitialSettings() {
    guard !initialSettingsLoaded else { return }

    self.nodeName = messageService.settings.name
    self.frequency = String(format: "%.1f", Float(messageService.settings.radioFreq) / 1000.0)
    self.bandwidth = String(format: "%.1f", Float(messageService.settings.radioBw) / 1000.0)
    self.spreadingFactor = messageService.settings.radioSf
    self.codingRate = messageService.settings.radioCr
    self.txPower = "\(messageService.settings.txPower)"

    self.initialSettingsLoaded = true
  }

  private func saveSettings() {
    guard bleManager.isConnected else { return }

    if messageService.settings.name != nodeName {
      messageService.saveNodeName(nodeName)
    }

    let freqValue = UInt32((Float(frequency) ?? 0) * 1000)
    let bwValue = UInt32((Float(bandwidth) ?? 0) * 1000)
    let txPowerValue = UInt8(txPower) ?? 14

    let radioSettingsChanged =
      freqValue != messageService.settings.radioFreq || bwValue != messageService.settings.radioBw
      || spreadingFactor != messageService.settings.radioSf
      || codingRate != messageService.settings.radioCr

    if radioSettingsChanged {
      messageService.saveRadioParams(
        freq: freqValue,
        bw: bwValue,
        sf: spreadingFactor,
        cr: codingRate
      )
    }

    if txPowerValue != messageService.settings.txPower {
      messageService.saveTxPower(txPowerValue)
    }
  }

  private func copyLogsToClipboard() {
    let logHistory = Logger.shared.getLogHistory()
    UIPasteboard.general.string = logHistory

    self.copyButtonText = "Copied!"
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      self.copyButtonText = "Copy Logs"
    }
  }
}
