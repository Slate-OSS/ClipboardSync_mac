//
//  EncryptionManager.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import Foundation
import CryptoKit

class EncryptionManager {
    // Generate a random shared key (32 bytes for AES-256)
    static func generateSharedKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }
    
    // Encrypt data using AES-GCM
    static func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        // Combine nonce + ciphertext + tag for transmission
        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)
        
        return encryptedData
    }
    
    // Decrypt data using AES-GCM
    static func decrypt(encryptedData: Data, key: SymmetricKey) throws -> Data {
        let nonceSize = 12 // AES-GCM nonce size
        let tagSize = 16   // GCM tag size
        
        guard encryptedData.count >= nonceSize + tagSize else {
            throw NSError(domain: "DecryptionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data too short"])
        }
        
        let nonce = try AES.GCM.Nonce(data: encryptedData.prefix(nonceSize))
        let ciphertext = encryptedData.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedData.suffix(tagSize)
        
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        return decryptedData
    }
    
    // Convert key to hex string for QR code/display
    static func keyToHexString(_ key: Data) -> String {
        return key.map { String(format: "%02x", $0) }.joined()
    }
    
    // Convert hex string back to key
    static func hexStringToKey(_ hexString: String) -> SymmetricKey? {
        let cleaned = hexString.lowercased()
        var bytes = [UInt8]()
        
        for i in stride(from: 0, to: cleaned.count, by: 2) {
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: 2)
            let byteString = String(cleaned[start..<end])
            
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
        }
        
        let data = Data(bytes)
        return SymmetricKey(data: data)
    }
}
