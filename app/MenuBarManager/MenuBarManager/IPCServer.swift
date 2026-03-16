import Foundation

/// JSON-based IPC server over a Unix domain socket.
/// Handles requests from the CLI tool.
class IPCServer {
    private let controller: MenuBarController
    private var listener: FileHandle?
    private var socketFD: Int32 = -1
    private let socketPath: String

    init(controller: MenuBarController) {
        self.controller = controller

        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/filippo")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.socketPath = appSupport.appendingPathComponent("filippo.sock").path
    }

    func start() {
        // Clean up stale socket
        unlink(socketPath)

        // Create socket
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            print("Failed to create socket")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        pathBytes.withUnsafeBufferPointer { buf in
            withUnsafeMutableBytes(of: &addr.sun_path) { rawSunPath in
                let count = min(buf.count, rawSunPath.count - 1)
                rawSunPath.copyBytes(from: UnsafeRawBufferPointer(buf).prefix(count))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("Failed to bind socket: \(String(cString: strerror(errno)))")
            return
        }

        // Listen
        guard listen(socketFD, 5) == 0 else {
            print("Failed to listen on socket")
            return
        }

        print("IPC server listening on \(socketPath)")

        // Accept connections on a background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while socketFD >= 0 {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(socketFD, sockPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else { continue }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Read request
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])
        guard let request = try? JSONDecoder().decode(IPCRequest.self, from: data) else {
            sendResponse(fd: fd, response: IPCResponse(success: false, error: "invalid request"))
            return
        }

        let response = processRequest(request)
        sendResponse(fd: fd, response: response)
    }

    private func processRequest(_ request: IPCRequest) -> IPCResponse {
        switch request.type {
        case "list_items":
            return listItems()
        case "apply_config", "reload_config":
            controller.reloadConfig()
            return IPCResponse(success: true)
        case "show_all":
            DispatchQueue.main.async { self.controller.showAll() }
            return IPCResponse(success: true)
        case "get_status":
            return listItems()
        default:
            return IPCResponse(success: false, error: "unknown message type: \(request.type)")
        }
    }

    private func listItems() -> IPCResponse {
        var items: [[String: Any]] = []

        // Include discovered items
        for item in controller.discoveredItems {
            let name = MenuBarItemDiscovery.displayName(for: item)
            let status = controller.knownItems[name] ?? "visible"
            items.append([
                "name": name,
                "owner": item.ownerName,
                "status": status,
                "active": true,
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: items) else {
            return IPCResponse(success: false, error: "failed to serialize items")
        }

        return IPCResponse(success: true, data: data)
    }

    private func sendResponse(fd: Int32, response: IPCResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        let newline = Data([0x0A]) // JSON line delimiter
        let payload = data + newline
        payload.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, payload.count)
        }
    }
}

struct IPCRequest: Codable {
    let type: String
    let payload: Data?

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        payload = try container.decodeIfPresent(Data.self, forKey: .payload)
    }
}

struct IPCResponse: Codable {
    let success: Bool
    var error: String?
    var data: Data?
}
