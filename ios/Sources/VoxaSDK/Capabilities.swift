import Foundation

/// Granular capabilities the SDK gates on (derived from the JWT role today; the server is
/// the real enforcement point). See the cross-platform spec.
public enum Capability: String, Sendable, CaseIterable {
    case joinCall, joinVideo, chat, consent
    case callControl, video, copilot, transcript, entities, suggestions, forms
    case presence, queue, transfer, escalate, botHandoff
    case monitor, whisper, barge, analytics
}

/// The role + capability set derived from a token.
public struct TokenProfile: Sendable {
    public let role: String
    public let capabilities: Set<Capability>
    public let tenantId: String?
    public let userId: String?

    public func can(_ c: Capability) -> Bool { capabilities.contains(c) }

    func requireCapability(_ c: Capability) throws {
        if !can(c) {
            throw VoxaError(.capability, "This token (\(role)) is not permitted to use \"\(c.rawValue)\".")
        }
    }

    private static let client: Set<Capability> = [.joinCall, .joinVideo, .chat, .consent]
    private static let agent: Set<Capability> = client.union([
        .callControl, .video, .copilot, .transcript, .entities, .suggestions,
        .forms, .presence, .queue, .transfer, .escalate, .botHandoff,
    ])
    private static let supervisor: Set<Capability> = agent.union([.monitor, .whisper, .barge, .analytics])

    /// Decode a Voxa access token (JWT) for client-side gating. Does NOT verify the signature
    /// (the server does). A non-JWT / guest token yields the CLIENT profile.
    public static func from(token: String) -> TokenProfile {
        let claims = decodeJWT(token)
        let role = (claims?["role"] as? String)?.uppercased()
        let caps: Set<Capability>
        switch role {
        case "SUPERVISOR", "ADMIN", "SUPER_ADMIN": caps = supervisor
        case "AGENT": caps = agent
        default: caps = client
        }
        return TokenProfile(
            role: role ?? "CLIENT",
            capabilities: caps,
            tenantId: claims?["tenantId"] as? String,
            userId: claims?["userId"] as? String
        )
    }
}

private func decodeJWT(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return json
}
