import Foundation

// MARK: - JSON-RPC 2.0 Models

/// JSON-RPC 2.0 request envelope.
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: AnyCodable?
    public let id: JSONRPCId?

    public init(method: String, params: AnyCodable? = nil, id: JSONRPCId? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
        self.id = id
    }
}

/// JSON-RPC 2.0 response envelope.
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let result: AnyCodable?
    public let error: JSONRPCError?
    public let id: JSONRPCId?

    public init(result: AnyCodable?, id: JSONRPCId?) {
        self.jsonrpc = "2.0"
        self.result = result
        self.error = nil
        self.id = id
    }

    public init(error: JSONRPCError, id: JSONRPCId?) {
        self.jsonrpc = "2.0"
        self.result = nil
        self.error = error
        self.id = id
    }

    public static func success<T: Encodable>(_ value: T, id: JSONRPCId?) -> JSONRPCResponse {
        JSONRPCResponse(result: AnyCodable(value), id: id)
    }

    public static func error(_ code: Int, _ message: String, id: JSONRPCId?) -> JSONRPCResponse {
        JSONRPCResponse(error: JSONRPCError(code: code, message: message), id: id)
    }
}

/// JSON-RPC 2.0 error object.
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public var data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    public static let parseError      = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest  = JSONRPCError(code: -32600, message: "Invalid request")
    public static let methodNotFound  = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams   = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError   = JSONRPCError(code: -32603, message: "Internal error")
}

/// JSON-RPC id — can be string or integer.
public enum JSONRPCId: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string or int"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

// MARK: - Type-erased Codable wrapper

/// Minimal type-erased Codable wrapper for JSON-RPC params/results.
public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable

    public init<T: Encodable & Sendable>(_ value: T) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try common types
        if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict
        } else if let arr = try? container.decode([AnyCodable].self) {
            self.value = arr
        } else if let str = try? container.decode(String.self) {
            self.value = str
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let dbl = try? container.decode(Double.self) {
            self.value = dbl
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if container.decodeNil() {
            // Represent null as empty string for simplicity
            self.value = Optional<String>.none as Any
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        default:
            // For typed Encodable results, encode via JSONEncoder round-trip
            if let encodable = value as? any Encodable {
                let data = try JSONEncoder().encode(AnyEncodableBox(encodable))
                let json = try JSONDecoder().decode(AnyCodable.self, from: data)
                try json.encode(to: encoder)
            } else {
                try container.encodeNil()
            }
        }
    }

    /// Decode the params as a typed struct.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// Helper to encode any Encodable through a box
private struct AnyEncodableBox: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: Encoder) throws { try base.encode(to: encoder) }
}
