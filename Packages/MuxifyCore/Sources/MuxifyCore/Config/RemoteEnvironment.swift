import Foundation

/// A hand-configured SSH destination. The selected Environment is UI state,
/// not part of the Config.
public struct RemoteEnvironment: Equatable, Identifiable {
    public let name: String
    public let host: String
    public let username: String
    /// Nil lets SSH config supply the port (OpenSSH otherwise defaults to 22).
    public var port: Int?
    public var identityFile: String?
    public var forwardAgent = true

    public var id: String { name }
}
