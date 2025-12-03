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
    private var connections: [String: ConnectionInfo] = [:]
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "com.slateoss.clipboardsync.network")
    
    var onMessageReceived: ((SyncMessage, String) -> Void)?
    
    // Connection info with buffer for partial messages
    private class ConnectionInfo {
        let connection: NWConnection
        var receiveBuffer = Data()
        let deviceId: String?
        
        init(connection: NWConnection, deviceId: String? = nil) {
            self.connection = connection
            self.deviceId = deviceId
        }
    }
    
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
            parameters.includePeerToPeer = true
            
            // Keep connection alive
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 30
            tcpOptions.keepaliveInterval = 10
            tcpOptions.keepaliveCount = 3
            parameters.defaultProtocolStack.transportProtocol = tcpOptions
            
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
            print("📍 Connect Android to: \(localIPAddress):\(port)")
            
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
        
        for (deviceId, connInfo) in connections {
            connInfo.connection.cancel()
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
        
        let connInfo = ConnectionInfo(connection: connection)
        
        connection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionStateUpdate(connection, connInfo: connInfo, state: newState)
        }
        
        receiveMessage(on: connInfo)
        connection.start(queue: queue)
    }
    
    private func handleConnectionStateUpdate(_ connection: NWConnection, connInfo: ConnectionInfo, state: NWConnection.State) {
        queue.async { [weak self] in
            switch state {
            case .ready:
                print("✅ Connection ready: \(connection.endpoint)")
            case .failed(let error):
                print("❌ Connection failed: \(error)")
                self?.removeConnection(connInfo)
            case .cancelled:
                print("🔌 Connection cancelled")
                self?.removeConnection(connInfo)
            default:
                break
            }
        }
    }
    
    private func receiveMessage(on connInfo: ConnectionInfo) {
        // Read with length-prefix framing
        connInfo.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Receive error: \(error)")
                self.removeConnection(connInfo)
                return
            }
            
            if let data = data, !data.isEmpty {
                connInfo.receiveBuffer.append(data)
                self.processReceivedData(connInfo: connInfo)
            }
            
            if !isComplete {
                self.receiveMessage(on: connInfo)
            } else {
                self.removeConnection(connInfo)
            }
        }
    }
    
    private func processReceivedData(connInfo: ConnectionInfo) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Process all complete messages in buffer
            while connInfo.receiveBuffer.count >= 4 {
                // Read 4-byte length prefix (big-endian) - SAFE way
                let lengthBytes = connInfo.receiveBuffer.prefix(4)
                let length = lengthBytes.withUnsafeBytes { buffer -> UInt32 in
                    // Create aligned copy
                    var value: UInt32 = 0
                    withUnsafeMutableBytes(of: &value) { dest in
                        dest.copyBytes(from: buffer)
                    }
                    return UInt32(bigEndian: value)
                }
                
                // Sanity check
                guard length > 0 && length < 1_000_000 else {
                    print("❌ Invalid message length: \(length)")
                    self.removeConnection(connInfo)
                    return
                }
                
                let totalNeeded = 4 + Int(length)
                
                // Wait for complete message
                guard connInfo.receiveBuffer.count >= totalNeeded else {
                    break
                }
                
                // Extract message
                let messageData = connInfo.receiveBuffer.subdata(in: 4..<totalNeeded)
                connInfo.receiveBuffer.removeFirst(totalNeeded)
                
                // Decode and handle
                self.handleReceivedMessage(messageData, connInfo: connInfo)
            }
        }
    }
    
    private func handleReceivedMessage(_ data: Data, connInfo: ConnectionInfo) {
        do {
            let message = try JSONDecoder().decode(SyncMessage.self, from: data)
            print("📨 Received: \(message.type) from \(message.fromDeviceId.prefix(8))")
            
            // Register on handshake
            if message.type == "handshake" {
                registerConnection(connInfo, deviceId: message.fromDeviceId)
            }
            
            DispatchQueue.main.async {
                self.onMessageReceived?(message, message.fromDeviceId)
            }
            
        } catch {
            print("❌ Invalid message data (\(data.count) bytes): \(error)")
        }
    }
    
    private func registerConnection(_ connInfo: ConnectionInfo, deviceId: String) {
        // Store connection with device ID
        connections[deviceId] = connInfo
        
        DispatchQueue.main.async { [weak self] in
            self?.activeConnections = self?.connections.count ?? 0
            self?.connectionStatus[deviceId] = .connected
        }
        
        print("✅ Registered device: \(deviceId.prefix(8))")
    }
    
    private func removeConnection(_ connInfo: ConnectionInfo) {
        if let deviceId = connections.first(where: { $0.value === connInfo })?.key {
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
        guard let connInfo = connections[deviceId] else {
            print("❌ No connection for \(deviceId.prefix(8))")
            return false
        }
        
        do {
            let messageData = try JSONEncoder().encode(message)
            
            // Create length-prefixed data
            var length = UInt32(messageData.count).bigEndian
            var packetData = Data()
            withUnsafeBytes(of: &length) { bytes in
                packetData.append(contentsOf: bytes)
            }
            packetData.append(messageData)
            
            connInfo.connection.send(
                content: packetData,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        print("❌ Send failed to \(deviceId.prefix(8)): \(error)")
                    } else {
                        print("✅ Sent \(message.type) to \(deviceId.prefix(8)) (\(messageData.count) bytes)")
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
