//
//  NetworkManager.swift
//  ClipboardSync
//
//  Created by Atharva on 02/12/25.
//

import Foundation
import Network
import Combine

class NetworkManager: ObservableObject {
    @Published var isServerRunning: Bool = false
    @Published var localIPAddress: String = "Unknown"
    @Published var activeConnections: Int = 0
    @Published var connectionStatus: [String: ConnectionState] = [:]
    
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "com.slateoss.clipboardsync.network")
    
    var onMessageReceived: ((SyncMessage, String) -> Void)?
    
    init() {
        detectLocalIPAddress()
    }
    
    // MARK: - Server Lifecycle
    
    func startServer() {
        guard listener == nil else {
            print("⚠️ Server already running")
            return
        }
        
        do {
            // Use plain TCP (no WebSocket) to bypass sandbox restrictions
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] newState in
                self?.handleListenerStateUpdate(newState)
            }
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewConnection(newConnection)
            }
            
            listener?.start(queue: queue)
            
            DispatchQueue.main.async {
                self.isServerRunning = true
            }
            
            print("🚀 TCP Server started on port \(port)")
            print("📍 Connect Android to: ws://\(localIPAddress):\(port)")
            
        } catch {
            print("❌ Failed to start server: \(error)")
            DispatchQueue.main.async {
                self.isServerRunning = false
            }
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        
        for (deviceId, connection) in connections {
            connection.cancel()
            print("🔌 Closed connection to \(deviceId.prefix(8))")
        }
        connections.removeAll()
        
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.activeConnections = 0
            self.connectionStatus.removeAll()
        }
        
        print("⏹️ Server stopped")
    }
    
    // MARK: - Connection Handling
    
    private func handleListenerStateUpdate(_ state: NWListener.State) {
        queue.async { [weak self] in
            switch state {
            case .ready:
                print("✅ TCP Listener ready on port \(self?.port ?? 0)")
            case .failed(let error):
                print("❌ Listener failed: \(error)")
                DispatchQueue.main.async {
                    self?.isServerRunning = false
                }
            case .cancelled:
                print("🛑 Listener cancelled")
            default:
                break
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("🔗 New TCP connection from \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionStateUpdate(connection, state: newState)
        }
        
        receiveMessage(on: connection)
        connection.start(queue: queue)
    }
    
    private func handleConnectionStateUpdate(_ connection: NWConnection, state: NWConnection.State) {
        queue.async { [weak self] in
            switch state {
            case .ready:
                print("✅ Connection ready: \(connection.endpoint)")
            case .failed(let error):
                print("❌ Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                print("🔌 Connection cancelled")
                self?.removeConnection(connection)
            default:
                break
            }
        }
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Receive error: \(error)")
                self.removeConnection(connection)
                return
            }
            
            if let data = data, !data.isEmpty {
                self.handleReceivedData(data, from: connection)
            }
            
            if isComplete {
                self.receiveMessage(on: connection)
            }
        }
    }
    
    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Try to decode as JSON message
                let message = try JSONDecoder().decode(SyncMessage.self, from: data)
                print("📨 Received: \(message.type) from \(message.fromDeviceId.prefix(8))")
                
                // Register on handshake
                if message.type == "handshake" {
                    self.registerConnection(connection, deviceId: message.fromDeviceId)
                }
                
                DispatchQueue.main.async {
                    self.onMessageReceived?(message, message.fromDeviceId)
                }
                
            } catch {
                print("❌ Invalid message data (\(data.count) bytes): \(error)")
                // Ignore invalid messages
            }
        }
    }
    
    private func registerConnection(_ connection: NWConnection, deviceId: String) {
        connections[deviceId] = connection
        
        DispatchQueue.main.async { [weak self] in
            self?.activeConnections = self?.connections.count ?? 0
            self?.connectionStatus[deviceId] = .connected
        }
        
        print("✅ Registered device: \(deviceId.prefix(8))")
    }
    
    private func removeConnection(_ connection: NWConnection) {
        if let deviceId = connections.first(where: { $0.value === connection })?.key {
            connections.removeValue(forKey: deviceId)
            
            DispatchQueue.main.async { [weak self] in
                self?.activeConnections = self?.connections.count ?? 0
                self?.connectionStatus[deviceId] = .disconnected
            }
            
            print("🔌 Removed device: \(deviceId.prefix(8))")
        }
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ message: SyncMessage, to deviceId: String) -> Bool {
        guard let connection = connections[deviceId] else {
            print("❌ No connection for \(deviceId.prefix(8))")
            return false
        }
        
        do {
            let data = try JSONEncoder().encode(message)
            
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        print("❌ Send failed to \(deviceId.prefix(8)): \(error)")
                    } else {
                        print("✅ Sent \(message.type) to \(deviceId.prefix(8))")
                    }
                }
            )
            
            return true
            
        } catch {
            print("❌ Encode failed: \(error)")
            return false
        }
    }
    
    func broadcastMessage(_ message: SyncMessage, except excludeDeviceId: String? = nil) {
        for (deviceId, _) in connections {
            if deviceId != excludeDeviceId {
                _ = sendMessage(message, to: deviceId)
            }
        }
    }
    
    // MARK: - IP Detection
    
    private func detectLocalIPAddress() {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let interface = ptr?.pointee {
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        address = String(cString: hostname)
                        break
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        DispatchQueue.main.async {
            self.localIPAddress = address ?? "Unknown"
        }
        print("🌐 Local IP: \(address ?? "Unknown")")
    }

}

enum ConnectionState {
    case disconnected, connecting, connected, error(String)
    
    var displayString: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
