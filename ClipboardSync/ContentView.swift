//
//  ContentView.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardManager()
    @StateObject private var pairingManager = DevicePairingManager()
    @StateObject private var networkManager = NetworkManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Clipboard Monitor Tab
            VStack(spacing: 16) {
                // Server Status Card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server Status")
                                .font(.headline)
                            Text(networkManager.isServerRunning ? "Running" : "Stopped")
                                .font(.caption)
                                .foregroundColor(networkManager.isServerRunning ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if networkManager.isServerRunning {
                                networkManager.stopServer()
                            } else {
                                networkManager.startServer()
                            }
                        }) {
                            Text(networkManager.isServerRunning ? "Stop Server" : "Start Server")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(networkManager.isServerRunning ? Color.red : Color.green)
                                .cornerRadius(6)
                        }
                    }
                    
                    if networkManager.isServerRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                                Text("IP Address: \(networkManager.localIPAddress):8765")
                                    .font(.system(.caption, design: .monospaced))
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(networkManager.localIPAddress, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.green)
                                Text("\(networkManager.activeConnections) active connection(s)")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                // Clipboard Monitor Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clipboard Sync")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Auto-syncing to \(pairingManager.pairedDevices.count) device(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                // Status & Control
                HStack(spacing: 12) {
                    Circle()
                        .fill(clipboardManager.isMonitoring ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    
                    Text(clipboardManager.isMonitoring ? "Monitoring Active" : "Not Monitoring")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button(action: {
                        if clipboardManager.isMonitoring {
                            clipboardManager.stopMonitoring()
                        } else {
                            setupIntegration()
                            clipboardManager.startMonitoring()
                        }
                    }) {
                        Text(clipboardManager.isMonitoring ? "Stop" : "Start")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(clipboardManager.isMonitoring ? Color.red : Color.blue)
                            .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                // Current Clipboard
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Content")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    TextEditor(text: .constant(clipboardManager.clipboardContent))
                        .border(Color.gray.opacity(0.3))
                        .cornerRadius(6)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 80)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                // Sync Status
                if !clipboardManager.syncStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Sync")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(clipboardManager.syncStatus)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // History
                VStack(alignment: .leading, spacing: 8) {
                    Text("History (\(clipboardManager.clipboardHistory.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if clipboardManager.clipboardHistory.isEmpty {
                        Text("No clipboard history yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        List(clipboardManager.clipboardHistory) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.content.prefix(100) + (item.content.count > 100 ? "..." : ""))
                                    .font(.caption)
                                    .lineLimit(2)
                                
                                Text(item.displayTime)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .onTapGesture {
                                clipboardManager.copyToClipboard(text: item.content)
                            }
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 150)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .tabItem {
                Label("Monitor", systemImage: "clipboard")
            }
            .tag(0)
            
            // Pairing Tab
            PairingView(pairingManager: pairingManager)
                .tabItem {
                    Label("Pairing", systemImage: "network")
                }
                .tag(1)
        }
        .frame(minWidth: 600, minHeight: 700)
        .onAppear {
            setupIntegration()
        }
    }
    
    private func setupIntegration() {
        // Connect clipboard manager to network manager
        clipboardManager.networkManager = networkManager
        
        // Setup auto-sync on clipboard change
        clipboardManager.onClipboardChange = { item in
            clipboardManager.autoSyncToAllDevices(item, devices: pairingManager.pairedDevices)
        }
        
        // Handle incoming network messages
        networkManager.onMessageReceived = { message, fromDeviceId in
            handleIncomingMessage(message, from: fromDeviceId)
        }
    }
    
    private func handleIncomingMessage(_ message: SyncMessage, from deviceId: String) {
        switch message.type {
        case "handshake":
            print("🤝 Handshake from \(deviceId.prefix(8))")
            // Handshake is auto-handled by NetworkManager
            
        case "clipboard_update":
            // Find paired device
            guard let device = pairingManager.pairedDevices.first(where: { $0.remoteDeviceId == deviceId }) else {
                print("⚠️ Received message from unknown device: \(deviceId.prefix(8))")
                return
            }
            
            do {
                let item = try MessageBuilder.decodeClipboardMessage(message: message, decryptionKey: device.sharedKey)
                
                // Update clipboard
                DispatchQueue.main.async {
                    clipboardManager.copyToClipboard(text: item.content)
                    clipboardManager.clipboardHistory.insert(item, at: 0)
                    if clipboardManager.clipboardHistory.count > 50 {
                        clipboardManager.clipboardHistory.removeLast()
                    }
                }
                
                print("📥 Received clipboard from \(device.name)")
                
            } catch {
                print("❌ Failed to decode clipboard: \(error)")
            }
            
        case "ping":
            // Respond with pong
            let pong = MessageBuilder.createPingMessage(fromDeviceId: pairingManager.currentDeviceId)
            _ = networkManager.sendMessage(pong, to: deviceId)
            
        default:
            print("⚠️ Unknown message type: \(message.type)")
        }
    }
}

#Preview {
    ContentView()
}
