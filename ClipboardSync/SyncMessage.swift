//
//  MessageProtocol.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import Foundation
import CryptoKit

// MARK: - Message Types

struct SyncMessage: Codable {
    let type: String  // "clipboard_update", "handshake", "ping", "pong"
    let fromDeviceId: String
    let toDeviceId: String?  // nil = broadcast
    let timestamp: Int64
    let payload: String  // base64-encoded encrypted data
    
    init(type: String, fromDeviceId: String, toDeviceId: String? = nil, payload: String) {
        self.type = type
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        self.payload = payload
    }
}

// MARK: - Message Builder

class MessageBuilder {
    
    // Create clipboard update message
    static func createClipboardMessage(
        item: ClipboardItem,
        fromDeviceId: String,
        toDeviceId: String,
        encryptionKey: SymmetricKey
    ) throws -> SyncMessage {
        // Encode clipboard item to JSON
        let itemData = try JSONEncoder().encode(item)
        
        // Encrypt with AES-GCM
        let encryptedData = try EncryptionManager.encrypt(data: itemData, key: encryptionKey)
        
        // Base64 encode for transmission
        let payload = encryptedData.base64EncodedString()
        
        return SyncMessage(
            type: "clipboard_update",
            fromDeviceId: fromDeviceId,
            toDeviceId: toDeviceId,
            payload: payload
        )
    }
    
    // Create handshake message
    static func createHandshakeMessage(fromDeviceId: String) -> SyncMessage {
        let handshakeData: [String: String] = [
            "version": "1.0",
            "platform": "macOS"
        ]
        
        let jsonData = try! JSONEncoder().encode(handshakeData)
        let payload = jsonData.base64EncodedString()
        
        return SyncMessage(
            type: "handshake",
            fromDeviceId: fromDeviceId,
            toDeviceId: nil,
            payload: payload
        )
    }
    
    // Create ping message
    static func createPingMessage(fromDeviceId: String) -> SyncMessage {
        return SyncMessage(
            type: "ping",
            fromDeviceId: fromDeviceId,
            toDeviceId: nil,
            payload: ""
        )
    }
    
    // Decode clipboard message
    static func decodeClipboardMessage(
        message: SyncMessage,
        decryptionKey: SymmetricKey
    ) throws -> ClipboardItem {
        // Base64 decode
        guard let encryptedData = Data(base64Encoded: message.payload) else {
            throw NSError(domain: "MessageProtocol", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode base64 payload"
            ])
        }
        
        // Decrypt
        let decryptedData = try EncryptionManager.decrypt(encryptedData: encryptedData, key: decryptionKey)
        
        // Decode clipboard item
        let item = try JSONDecoder().decode(ClipboardItem.self, from: decryptedData)
        
        return item
    }
}
