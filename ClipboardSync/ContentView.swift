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
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Clipboard Monitor Tab
            VStack(spacing: 16) {
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
                            clipboardManager.startMonitoring()
                            setupAutoSync()
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
    }
    
    private func setupAutoSync() {
        clipboardManager.onClipboardChange = { item in
            // Auto-sync to all paired devices
            clipboardManager.autoSyncToAllDevices(item, devices: pairingManager.pairedDevices)
        }
    }
}

#Preview {
    ContentView()
}
