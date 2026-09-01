import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.RecordScreen"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let signaling = Logger(subsystem: subsystem, category: "signaling")
    static let webRTC = Logger(subsystem: subsystem, category: "webrtc")
    static let recording = Logger(subsystem: subsystem, category: "recording")
}
