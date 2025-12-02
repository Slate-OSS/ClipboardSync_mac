//
//  PairingView.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import SwiftUI

struct PairingView: View {
    @ObservedObject var pairingManager: DevicePairingManager
    @State private var showingPairingCode = false
    @State private var manualPairingCode = ""
    @State private var pairingMessage = ""
    @State private var messageType: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Device Pairing")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Current Device ID: \(pairingManager.currentDeviceId.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // Generate new pairing code
            Button(action: {
                pairingManager.generatePairingCode()
                showingPairingCode = true
                pairingMessage = ""
            }) {
                HStack {
                    Image(systemName: "qrcode")
                    Text("Generate Pairing Code")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .fontWeight(.semibold)
            }
            
            // Show QR code if generated
            if showingPairingCode, let qrImage = pairingManager.qrCodeImage {
                VStack(spacing: 12) {
                    Text("Scan with your Android device")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Image(nsImage: qrImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .border(Color.gray.opacity(0.3))
                        .cornerRadius(4)
                    
                    // Manual code entry as fallback
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or enter manually:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text(pairingManager.showPairingCode)
                            .font(.caption2)
                            .monospaced()
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("This code is unique to this pairing session")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Manual pairing code entry
            VStack(spacing: 12) {
                Text("Enter Pairing Code from Device")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("Pairing code (device_id|timestamp|key)", text: $manualPairingCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
                
                Button(action: {
                    let result = pairingManager.addPairedDevice(from: manualPairingCode)
                    pairingMessage = result.message
                    messageType = result.success ? "success" : "error"
                    
                    if result.success {
                        manualPairingCode = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            pairingMessage = ""
                        }
                    }
                }) {
                    Text("Add Device")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .fontWeight(.semibold)
                }
                
                if !pairingMessage.isEmpty {
                    Text(pairingMessage)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(messageType == "success" ? .green : .red)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(messageType == "success" ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            // Paired devices list
            VStack(alignment: .leading, spacing: 12) {
                Text("Paired Devices (\(pairingManager.pairedDevices.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if pairingManager.pairedDevices.isEmpty {
                    VStack {
                        Image(systemName: "iphone")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        
                        Text("No devices paired yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Pair an Android device to start auto-syncing clipboard")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 8) {
                        ForEach(pairingManager.pairedDevices) { device in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    
                                    Text("ID: " + device.remoteDeviceId.prefix(12) + "...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .monospaced()
                                    
                                    Text("Added: " + device.dateAdded.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    pairingManager.removePairedDevice(device)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 18))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    PairingView(pairingManager: DevicePairingManager())
}
