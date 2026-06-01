import Foundation

/// Error codes shared across all Voxa SDKs. Keep identical in concept everywhere.
public enum VoxaErrorCode: String, Sendable {
    case auth, capability, connection, device, media, server
}

/// Typed error surfaced by the SDK. Never contains PHI (transcript/message content).
public struct VoxaError: Error, CustomStringConvertible, Sendable {
    public let code: VoxaErrorCode
    public let message: String
    public let status: Int?

    public init(_ code: VoxaErrorCode, _ message: String, status: Int? = nil) {
        self.code = code
        self.message = message
        self.status = status
    }

    public var description: String {
        "VoxaError(\(code.rawValue)): \(message)" + (status.map { " [HTTP \($0)]" } ?? "")
    }
}
