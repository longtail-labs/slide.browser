import Foundation

/// Unix domain socket server for Slide CLI communication.
/// Listens on `~/.slide/slide.sock`, accepts newline-delimited JSON-RPC 2.0 messages.
public final class CommandServer: @unchecked Sendable {
    public static let socketDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".slide")
    public static let socketPath = socketDir.appendingPathComponent("slide.sock").path

    public static let maxMessageSize = 1_048_576 // 1MB safety limit
    public static let slideVersion = "0.1.0"

    private var serverSocket: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.slide.commandserver", qos: .userInitiated)
    private var handler: (@Sendable (JSONRPCRequest) async -> JSONRPCResponse)?
    private var isRunning = false

    public init() {}

    /// Start listening on the Unix socket.
    /// - Parameter handler: Async callback invoked for each incoming JSON-RPC request.
    public func start(handler: @escaping @Sendable (JSONRPCRequest) async -> JSONRPCResponse) throws {
        self.handler = handler

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: Self.socketDir,
            withIntermediateDirectories: true
        )

        // Remove stale socket
        unlink(Self.socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw CommandServerError.socketCreationFailed(errno)
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(serverSocket)
            throw CommandServerError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverSocket)
            throw CommandServerError.bindFailed(errno)
        }

        // Set permissions: owner-only (0o600)
        chmod(Self.socketPath, 0o600)

        // Listen
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            throw CommandServerError.listenFailed(errno)
        }

        // Accept connections via GCD
        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
            }
            unlink(Self.socketPath)
        }
        self.dispatchSource = source
        isRunning = true
        source.resume()

        print("[CommandServer] Listening on \(Self.socketPath)")
    }

    /// Stop the server and clean up the socket file.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        dispatchSource?.cancel()
        dispatchSource = nil
        print("[CommandServer] Stopped")
    }

    // MARK: - Private

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverSocket, sockPtr, &clientLen)
            }
        }
        guard clientFd >= 0 else { return }

        // Handle client on a background task
        let handler = self.handler
        Task.detached { [weak self] in
            await self?.handleClient(fd: clientFd, handler: handler)
        }
    }

    private func handleClient(fd: Int32, handler: (@Sendable (JSONRPCRequest) async -> JSONRPCResponse)?) async {
        defer { close(fd) }

        guard let handler else { return }

        // Read until newline
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        while true {
            let bytesRead = read(fd, &chunk, chunkSize)
            if bytesRead <= 0 { break }
            buffer.append(contentsOf: chunk[0..<bytesRead])

            guard buffer.count <= Self.maxMessageSize else {
                let errorResponse = JSONRPCResponse.error(-32600, "Message too large", id: nil)
                writeResponse(errorResponse, to: fd)
                return
            }

            // Process all complete messages (newline-delimited)
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let messageData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])

                guard !messageData.isEmpty else { continue }

                let response: JSONRPCResponse
                do {
                    let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(messageData))
                    response = await handler(request)
                } catch {
                    response = JSONRPCResponse.error(-32700, "Parse error: \(error.localizedDescription)", id: nil)
                }

                writeResponse(response, to: fd)
            }

            // If we got data ending in newline, we're done
            if buffer.isEmpty { break }
        }

        // Handle remaining data without newline (single message without trailing newline)
        if !buffer.isEmpty {
            let response: JSONRPCResponse
            do {
                let request = try JSONDecoder().decode(JSONRPCRequest.self, from: buffer)
                response = await handler(request)
            } catch {
                response = JSONRPCResponse.error(-32700, "Parse error: \(error.localizedDescription)", id: nil)
            }
            writeResponse(response, to: fd)
        }
    }

    private func writeResponse(_ response: JSONRPCResponse, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(UInt8(ascii: "\n"))
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = write(fd, base, ptr.count)
        }
    }
}

// MARK: - Socket Client (for CLI mode)

/// Minimal client that connects to the Slide socket, sends a JSON-RPC request, and reads the response.
public struct SocketClient {
    public let socketPath: String

    public init(socketPath: String = CommandServer.socketPath) {
        self.socketPath = socketPath
    }

    /// Send a JSON-RPC request and return the response.
    public func send(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CommandServerError.socketCreationFailed(errno)
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw CommandServerError.connectFailed(errno)
        }

        // Write request + newline
        var data = try JSONEncoder().encode(request)
        data.append(UInt8(ascii: "\n"))
        let written = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return write(fd, base, ptr.count)
        }
        guard written > 0 else {
            throw CommandServerError.writeFailed(errno)
        }

        // Shutdown write side so server knows we're done
        shutdown(fd, SHUT_WR)

        // Read response
        var responseData = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &chunk, 4096)
            if bytesRead <= 0 { break }
            responseData.append(contentsOf: chunk[0..<bytesRead])
        }

        // Trim trailing newline
        if responseData.last == UInt8(ascii: "\n") {
            responseData.removeLast()
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
    }

    /// Convenience: send a method with typed params and return typed result.
    public func call<P: Encodable, R: Decodable>(
        method: SlideMethod,
        params: P,
        as resultType: R.Type
    ) throws -> R {
        let request = JSONRPCRequest(
            method: method.rawValue,
            params: AnyCodable(params),
            id: .int(1)
        )
        let response = try send(request)
        if let error = response.error {
            throw CommandServerError.rpcError(error.code, error.message)
        }
        guard let result = response.result else {
            throw CommandServerError.noResult
        }
        return try result.decode(resultType)
    }
}

// MARK: - Errors

public enum CommandServerError: LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
    case pathTooLong
    case rpcError(Int, String)
    case noResult
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let e): return "Failed to create socket: \(String(cString: strerror(e)))"
        case .bindFailed(let e): return "Failed to bind socket: \(String(cString: strerror(e)))"
        case .listenFailed(let e): return "Failed to listen: \(String(cString: strerror(e)))"
        case .connectFailed(let e): return "Cannot connect to Slide (is it running?): \(String(cString: strerror(e)))"
        case .writeFailed(let e): return "Failed to write: \(String(cString: strerror(e)))"
        case .pathTooLong: return "Socket path too long"
        case .rpcError(let code, let msg): return "RPC error \(code): \(msg)"
        case .noResult: return "No result in response"
        case .notRunning: return "Slide is not running"
        }
    }
}
