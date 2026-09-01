import Foundation

enum LocalNetworkProtocol {
    static let bonjourType = "_recordscreen._tcp"
}

struct PeerHandshake: Codable, Sendable {
    enum Role: String, Codable, Sendable {
        case publisher
        case receiver
    }

    let role: Role
    let deviceName: String
}
