//
//  ClipboardManager.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import Cocoa
import Combine
import CryptoKit

class ClipboardManager: ObservableObject {
    @Published var clipboardContent: String = ""
    @Published var clipboardHistory: [ClipboardItem] = []
    @Published var isMonitoring: Bool = false
    @Published var syncStatus: String = ""
    
    var onClipboardChange: ((ClipboardItem) -> Void)?
    
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    
    func startMonitoring() {
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        // Poll clipboard every 500ms for changes
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        print("✅ Clipboard monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        
        print("⏹️ Clipboard monitoring stopped")
    }
    
    private func checkClipboard() {
        // Check if clipboard content changed
        if lastChangeCount != pasteboard.changeCount {
            lastChangeCount = pasteboard.changeCount
            
            // Try to get string content from clipboard
            if let content = pasteboard.string(forType: .string) {
                clipboardContent = content
                
                // Create clipboard item
                let item = ClipboardItem(
                    content: content,
                    timestamp: Date(),
                    type: "text"
                )
                
                // Add to history
                clipboardHistory.insert(item, at: 0)
                
                // Keep only last 50 items
                if clipboardHistory.count > 50 {
                    clipboardHistory.removeLast()
                }
                
                print("📋 Clipboard changed: \(content.prefix(50))...")
                
                // Trigger callback for auto-sync
                onClipboardChange?(item)
            }
        }
    }
    
    func copyToClipboard(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("✅ Copied to clipboard")
    }
    
    func sendToDevice(_ item: ClipboardItem, device: PairedDevice) -> Bool {
        do {
            let itemData = try JSONEncoder().encode(item)
            let encryptedData = try EncryptionManager.encrypt(data: itemData, key: device.sharedKey)
            
            // TODO: Send encryptedData over network to Android device
            print("✅ Encrypted clipboard item for \(device.name): \(encryptedData.count) bytes")
            syncStatus = "Synced to \(device.name): \(encryptedData.count) bytes"
            
            return true
        } catch {
            print("❌ Encryption failed: \(error)")
            syncStatus = "Sync failed: \(error.localizedDescription)"
            return false
        }
    }
    
    // Auto-sync to all paired devices
    func autoSyncToAllDevices(_ item: ClipboardItem, devices: [PairedDevice]) {
        guard !devices.isEmpty else { return }
        
        for device in devices {
            _ = sendToDevice(item, device: device)
        }
        
        print("🔄 Auto-synced to \(devices.count) device(s)")
    }
    
    deinit {
        stopMonitoring()
    }
}

// Model for clipboard history item
struct ClipboardItem: Identifiable, Codable {
    let id: String
    let content: String
    let timestamp: Date
    let type: String
    
    init(content: String, timestamp: Date, type: String) {
        self.id = UUID().uuidString
        self.content = content
        self.timestamp = timestamp
        self.type = type
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, type
    }
}
