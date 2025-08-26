//
//  BLEManager.swift
//  MeshcoreMessenger
//

import CoreBluetooth
import Foundation

extension Notification.Name {
  static let bleDataReceived = Notification.Name("bleDataReceived")
  static let bleReady = Notification.Name("bleReady")
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

  static let shared = BLEManager()

  @Published var isConnected = false

  private var centralManager: CBCentralManager!
  private var meshcorePeripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?

  let meshcoreServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
  let writeCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
  let notifyCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

  private override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: nil)
  }

  func writeData(_ data: Data) {
    guard let peripheral = self.meshcorePeripheral,
      let characteristic = self.writeCharacteristic
    else {
      Logger.shared.log("BLEManager: Not ready to send data.")
      return
    }
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
  }

  // MARK: - Delegate Methods
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      Logger.shared.log("BLEManager: Bluetooth is On. Scanning...")
      centralManager.scanForPeripherals(withServices: [meshcoreServiceUUID], options: nil)
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    Logger.shared.log("BLEManager: Found Node: \(peripheral.name ?? "Unknown")")

    self.meshcorePeripheral = peripheral

    centralManager.stopScan()

    centralManager.connect(peripheral, options: nil)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Logger.shared.log("BLEManager: Connected to Node.")
    DispatchQueue.main.async { self.isConnected = true }
    peripheral.delegate = self
    peripheral.discoverServices([meshcoreServiceUUID])
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    Logger.shared.log("BLEManager: Disconnected from Node.")
    self.meshcorePeripheral = nil
    self.writeCharacteristic = nil
    DispatchQueue.main.async { self.isConnected = false }

    centralManager.scanForPeripherals(withServices: [meshcoreServiceUUID], options: nil)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }
    for service in services where service.uuid == meshcoreServiceUUID {
      peripheral.discoverCharacteristics(
        [writeCharacteristicUUID, notifyCharacteristicUUID], for: service)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard let characteristics = service.characteristics else { return }
    var foundWrite = false
    var foundNotify = false

    for characteristic in characteristics {
      if characteristic.uuid == writeCharacteristicUUID {
        self.writeCharacteristic = characteristic
        foundWrite = true
      } else if characteristic.uuid == notifyCharacteristicUUID {
        peripheral.setNotifyValue(true, for: characteristic)
        foundNotify = true
      }
    }

    if foundWrite && foundNotify {
      Logger.shared.log("BLEManager: Ready to communicate. Posting notification.")
      NotificationCenter.default.post(name: .bleReady, object: nil)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard let data = characteristic.value else { return }
    NotificationCenter.default.post(name: .bleDataReceived, object: data)
  }
}
