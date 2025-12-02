//
//  DevicePairingManager.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import Foundation
import Combine
import CryptoKit
import AppKit

class DevicePairingManager: ObservableObject {
    @Published var pairedDevices: [PairedDevice] = []
    @Published var currentDeviceId: String = UUID().uuidString
    @Published var currentSharedKey: SymmetricKey?
    @Published var qrCodeImage: NSImage?
    @Published var showPairingCode: String = ""
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadPairedDevices()
        // Generate and save current device ID
        if userDefaults.string(forKey: "currentDeviceId") == nil {
            userDefaults.set(currentDeviceId, forKey: "currentDeviceId")
        } else {
            currentDeviceId = userDefaults.string(forKey: "currentDeviceId") ?? UUID().uuidString
        }
    }
    
    // Generate pairing code and QR code
    func generatePairingCode() -> String {
        let newKey = EncryptionManager.generateSharedKey()
        let keyHex = EncryptionManager.keyToHexString(newKey)
        
        // Create pairing data: device_id|timestamp|key_hex
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let pairingData = "\(currentDeviceId)|\(timestamp)|\(keyHex)"
        
        // Generate QR code
        qrCodeImage = QRCodeGenerator.generateQRCode(from: pairingData)
        showPairingCode = pairingData
        
        // Store current key for this pairing session
        currentSharedKey = SymmetricKey(data: newKey)
        
        print("🔐 Generated pairing code: \(pairingData.prefix(30))...")
        
        return pairingData
    }
    
    // Parse pairing code from QR scan or manual entry
    func addPairedDevice(from pairingCode: String) -> (success: Bool, message: String) {
        let components = pairingCode.split(separator: "|")
        guard components.count == 3 else {
            let message = "❌ Invalid pairing code format"
            print(message)
            return (false, message)
        }
        
        let deviceId = String(components[0])
        let keyHex = String(components[2])
        
        // PREVENT SELF-PAIRING
        if deviceId == currentDeviceId {
            let message = "❌ Cannot pair device with itself"
            print(message)
            return (false, message)
        }
        
        // Check if device already paired
        if pairedDevices.contains(where: { $0.remoteDeviceId == deviceId }) {
            let message = "⚠️ Device already paired"
            print(message)
            return (false, message)
        }
        
        guard let sharedKey = EncryptionManager.hexStringToKey(keyHex) else {
            let message = "❌ Failed to convert hex key"
            print(message)
            return (false, message)
        }
        
        let device = PairedDevice(
            id: UUID().uuidString,
            remoteDeviceId: deviceId,
            sharedKey: sharedKey,
            name: "Android Device",
            dateAdded: Date()
        )
        
        pairedDevices.append(device)
        savePairedDevices()
        
        let message = "✅ Device paired: \(deviceId.prefix(8))..."
        print(message)
        
        return (true, message)
    }
    
    // Save paired devices to UserDefaults
    private func savePairedDevices() {
        if let encoded = try? JSONEncoder().encode(pairedDevices) {
            userDefaults.set(encoded, forKey: "pairedDevices")
            print("💾 Paired devices saved")
        }
    }
    
    // Load paired devices from UserDefaults
    private func loadPairedDevices() {
        if let data = userDefaults.data(forKey: "pairedDevices"),
           let decoded = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            pairedDevices = decoded
            print("📂 Loaded \(pairedDevices.count) paired devices")
        }
    }
    
    // Remove a paired device
    func removePairedDevice(_ device: PairedDevice) {
        pairedDevices.removeAll { $0.id == device.id }
        savePairedDevices()
        print("🗑️ Device removed: \(device.remoteDeviceId.prefix(8))...")
    }
}

// Model for paired devices
struct PairedDevice: Identifiable, Codable {
    let id: String
    let remoteDeviceId: String
    let sharedKey: SymmetricKey
    let name: String
    let dateAdded: Date
    
    enum CodingKeys: String, CodingKey {
        case id, remoteDeviceId, sharedKeyHex, name, dateAdded
    }
    
    init(id: String, remoteDeviceId: String, sharedKey: SymmetricKey, name: String, dateAdded: Date) {
        self.id = id
        self.remoteDeviceId = remoteDeviceId
        self.sharedKey = sharedKey
        self.name = name
        self.dateAdded = dateAdded
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        remoteDeviceId = try container.decode(String.self, forKey: .remoteDeviceId)
        name = try container.decode(String.self, forKey: .name)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        
        let keyHex = try container.decode(String.self, forKey: .sharedKeyHex)
        sharedKey = EncryptionManager.hexStringToKey(keyHex) ?? SymmetricKey(size: .bits256)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(remoteDeviceId, forKey: .remoteDeviceId)
        try container.encode(name, forKey: .name)
        try container.encode(dateAdded, forKey: .dateAdded)
        
        let keyData = sharedKey.withUnsafeBytes { Data($0) }
        let keyHex = EncryptionManager.keyToHexString(keyData)
        try container.encode(keyHex, forKey: .sharedKeyHex)
    }
}
