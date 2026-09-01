import Foundation

enum StreamConnectionState: Equatable, Sendable {
    case idle
    case preparing
    case connecting
    case connected
    case reconnecting
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .connecting: "Connecting"
        case .connected: "Live"
        case .reconnecting: "Reconnecting"
        case .failed: "Connection Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .preparing, .connecting, .connected, .reconnecting: true
        case .idle, .failed: false
        }
    }
}

struct StreamConfiguration: Equatable, Sendable {
    var resolution: Resolution = .fullHD
    var frameRate: Int = 30
    var videoBitRate: Int = 6_000_000

    enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case hd = "1280 × 720"
        case fullHD = "1920 × 1080"

        var id: Self { self }
    }
}

@MainActor
protocol StreamPublisher: AnyObject {
    var state: StreamConnectionState { get }
    func startPublishing(configuration: StreamConfiguration) async throws
    func stopPublishing()
}

@MainActor
protocol StreamReceiver: AnyObject {
    var state: StreamConnectionState { get }
    func startReceiving() async throws
    func stopReceiving()
}
