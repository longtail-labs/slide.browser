import Foundation

/// Routes incoming JSON-RPC requests to typed handlers using two-pass decoding.
/// First decodes the envelope (method + raw params), then decodes typed params by method.
public final class CommandRouter: @unchecked Sendable {
    public typealias Handler = @Sendable (SlideMethod, JSONRPCRequest) async -> JSONRPCResponse

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Process a raw JSON-RPC request: validate method, delegate to handler.
    public func route(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        // Pass 1: validate method
        guard let method = SlideMethod(rawValue: request.method) else {
            return .error(-32601, "Method not found: \(request.method)", id: request.id)
        }

        // Pass 2: delegate to handler with typed method
        return await handler(method, request)
    }
}

// MARK: - Param Decoding Helpers

extension JSONRPCRequest {
    /// Decode params as a typed struct. Returns nil if params is nil.
    public func decodeParams<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let params else { return nil }
        return try params.decode(type)
    }

    /// Decode params as a typed struct, throwing invalidParams if missing.
    public func requireParams<T: Decodable>(_ type: T.Type) throws -> T {
        guard let params else {
            throw CommandRouterError.missingParams
        }
        do {
            return try params.decode(type)
        } catch {
            throw CommandRouterError.invalidParams(error.localizedDescription)
        }
    }
}

public enum CommandRouterError: LocalizedError {
    case missingParams
    case invalidParams(String)

    public var errorDescription: String? {
        switch self {
        case .missingParams: return "Missing required params"
        case .invalidParams(let detail): return "Invalid params: \(detail)"
        }
    }
}
