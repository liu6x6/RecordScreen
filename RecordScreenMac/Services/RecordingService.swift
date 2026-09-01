@preconcurrency import AVFoundation
import Foundation

enum RecordingState {
    case idle
    case preparing
    case recording
    case finishing
    case finished(URL)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparing, .recording:
            true
        case .idle, .finishing, .finished, .failed:
            false
        }
    }

    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .finishing:
            true
        case .idle, .finished, .failed:
            false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            "Ready to record"
        case .preparing:
            "Waiting for the first video frame…"
        case .recording:
            "Recording video"
        case .finishing:
            "Finalizing recording…"
        case let .finished(url):
            "Saved to \(url.path.abbreviatingHomeDirectory)"
        case let .failed(message):
            "Recording failed: \(message)"
        }
    }
}

@MainActor
final class RecordingService: ObservableObject {
    @Published private(set) var state: RecordingState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    var onStateChanged: ((RecordingState) -> Void)?

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var temporaryURL: URL?
    private var finalURL: URL?
    private var frameSize: CGSize?
    private var lastPresentationTime: CMTime?
    private var droppedFrameCount = 0

    func beginRecording() async -> Bool {
        guard !state.isBusy else {
            reportFailure("A recording is already active.")
            return false
        }

        clearWriterState()
        state = .preparing

        do {
            let destination = try await Task.detached(priority: .utility) {
                try Self.makeDestination()
            }.value
            guard case .preparing = state else {
                return false
            }
            temporaryURL = destination.temporaryURL
            finalURL = destination.finalURL
            AppLog.recording.info(
                "Prepared video-only recording destination: \(destination.finalURL.path.abbreviatingHomeDirectory, privacy: .public)."
            )
            return true
        } catch {
            reportFailure(error.localizedDescription)
            return false
        }
    }

    func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard state.isActive else { return }
        guard presentationTime.isValid else {
            registerDroppedFrame(reason: "invalid presentation timestamp")
            return
        }

        if writer == nil {
            createWriter(for: pixelBuffer, at: presentationTime)
        }

        guard let writer, let writerInput, let pixelBufferAdaptor else { return }
        guard writer.status == .writing else {
            reportFailure(writerFailureDescription(writer))
            return
        }

        let currentSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        guard currentSize == frameSize else {
            AppLog.recording.notice(
                "Stopping recording because video dimensions changed from \(self.frameDescription, privacy: .public) to \(Int(currentSize.width), privacy: .public)x\(Int(currentSize.height), privacy: .public)."
            )
            Task { [weak self] in
                await self?.finishRecording()
            }
            return
        }

        if let lastPresentationTime, CMTimeCompare(presentationTime, lastPresentationTime) <= 0 {
            registerDroppedFrame(reason: "non-monotonic presentation timestamp")
            return
        }

        guard writerInput.isReadyForMoreMediaData else {
            registerDroppedFrame(reason: "writer input is not ready")
            return
        }

        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            switch writer.status {
            case .failed:
                reportFailure(writerFailureDescription(writer))
            case .writing:
                registerDroppedFrame(reason: "pixel buffer adaptor rejected the frame")
            case .unknown, .completed, .cancelled:
                reportFailure(writerFailureDescription(writer))
            @unknown default:
                reportFailure(writerFailureDescription(writer))
            }
            return
        }

        lastPresentationTime = presentationTime
        if case .preparing = state {
            state = .recording
        }
    }

    func finishRecording() async {
        guard case .preparing = state else {
            guard case .recording = state else { return }
            await finishActiveWriter()
            return
        }

        let temporaryURL = temporaryURL
        clearWriterState()
        state = .failed("Recording stopped before a video frame arrived.")
        if let temporaryURL {
            await Self.removeTemporaryOutput(at: temporaryURL)
        }
    }

    func reportFailure(_ message: String) {
        let temporaryURL = temporaryURL
        let writerBox = writer.map(WriterBox.init)
        clearWriterState()
        state = .failed(message)
        AppLog.recording.error("Recording failed: \(message, privacy: .public)")

        Task.detached(priority: .utility) {
            writerBox?.writer.cancelWriting()
            if let temporaryURL {
                await Self.removeTemporaryOutput(at: temporaryURL)
            }
        }
    }

    private func createWriter(for pixelBuffer: CVPixelBuffer, at presentationTime: CMTime) {
        guard let temporaryURL, let finalURL else {
            reportFailure("The recording destination was not prepared.")
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            reportFailure("The first video frame has invalid dimensions.")
            return
        }

        do {
            let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mov)
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            writerInput.expectsMediaDataInRealTime = true

            let sourceAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(pixelBuffer),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: sourceAttributes
            )

            guard writer.canAdd(writerInput) else {
                throw RecordingError.cannotAddVideoInput
            }
            writer.add(writerInput)
            guard writer.startWriting() else {
                throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "AVAssetWriter could not start.")
            }

            writer.startSession(atSourceTime: presentationTime)
            self.writer = writer
            self.writerInput = writerInput
            self.pixelBufferAdaptor = adaptor
            frameSize = CGSize(width: width, height: height)
            lastPresentationTime = nil
            AppLog.recording.info(
                "Created H.264 MOV writer for \(finalURL.path.abbreviatingHomeDirectory, privacy: .public) at \(width, privacy: .public)x\(height, privacy: .public)."
            )
        } catch {
            reportFailure(error.localizedDescription)
        }
    }

    private func finishActiveWriter() async {
        guard let writer, let writerInput, let temporaryURL, let finalURL else {
            reportFailure("The active video writer is unavailable.")
            return
        }

        state = .finishing
        self.writer = nil
        self.writerInput = nil
        pixelBufferAdaptor = nil
        self.temporaryURL = nil
        self.finalURL = nil
        frameSize = nil
        lastPresentationTime = nil
        writerInput.markAsFinished()

        let writerBox = WriterBox(writer)
        let result = await Task.detached(priority: .utility) {
            await Self.finish(
                writerBox: writerBox,
                temporaryURL: temporaryURL,
                finalURL: finalURL
            )
        }.value

        switch result {
        case let .success(url):
            state = .finished(url)
            AppLog.recording.info(
                "Finalized video recording: \(url.path.abbreviatingHomeDirectory, privacy: .public); dropped \(self.droppedFrameCount, privacy: .public) frame(s)."
            )
        case let .failure(message):
            state = .failed(message)
            AppLog.recording.error("Recording finalization failed: \(message, privacy: .public)")
        }
    }

    private func registerDroppedFrame(reason: String) {
        droppedFrameCount += 1
        if droppedFrameCount == 1 || droppedFrameCount.isMultiple(of: 60) {
            AppLog.recording.notice(
                "Dropped \(self.droppedFrameCount, privacy: .public) recording frame(s); latest reason: \(reason, privacy: .public)."
            )
        }
    }

    private func writerFailureDescription(_ writer: AVAssetWriter) -> String {
        writer.error?.localizedDescription ?? "AVAssetWriter entered \(String(describing: writer.status))."
    }

    private var frameDescription: String {
        guard let frameSize else { return "unknown dimensions" }
        return "\(Int(frameSize.width))x\(Int(frameSize.height))"
    }

    private func clearWriterState() {
        writer = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        temporaryURL = nil
        finalURL = nil
        frameSize = nil
        lastPresentationTime = nil
        droppedFrameCount = 0
    }

    private nonisolated static func makeDestination() throws -> RecordingDestination {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecordingError.documentsDirectoryUnavailable
        }

        let directory = documentsURL.appendingPathComponent("RecordScreen", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let values = try directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let availableCapacity: Int64
        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            availableCapacity = Int64(importantCapacity)
        } else if let standardCapacity = values.volumeAvailableCapacity {
            availableCapacity = Int64(standardCapacity)
        } else {
            availableCapacity = 0
        }
        let minimumFreeSpace: Int64 = 500 * 1024 * 1024
        guard availableCapacity >= minimumFreeSpace else {
            throw RecordingError.insufficientDiskSpace(
                available: availableCapacity,
                required: minimumFreeSpace
            )
        }

        let stem = "RecordScreen-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
        let finalURL = directory.appendingPathComponent("\(stem).mov", isDirectory: false)
        let temporaryURL = directory.appendingPathComponent("\(stem).partial", isDirectory: false)
        guard !fileManager.fileExists(atPath: finalURL.path),
              !fileManager.fileExists(atPath: temporaryURL.path) else {
            throw RecordingError.destinationAlreadyExists
        }
        return RecordingDestination(temporaryURL: temporaryURL, finalURL: finalURL)
    }

    private nonisolated static func finish(
        writerBox: WriterBox,
        temporaryURL: URL,
        finalURL: URL
    ) async -> RecordingFinishResult {
        await withCheckedContinuation { continuation in
            writerBox.writer.finishWriting {
                let writer = writerBox.writer
                guard writer.status == .completed else {
                    let message = writer.error?.localizedDescription
                        ?? "AVAssetWriter finished with status \(String(describing: writer.status))."
                    Task.detached(priority: .utility) {
                        await Self.removeTemporaryOutput(at: temporaryURL)
                        continuation.resume(returning: .failure(message))
                    }
                    return
                }

                do {
                    let fileManager = FileManager.default
                    guard !fileManager.fileExists(atPath: finalURL.path) else {
                        throw RecordingError.destinationAlreadyExists
                    }
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                    continuation.resume(returning: .success(finalURL))
                } catch {
                    Task.detached(priority: .utility) {
                        await Self.removeTemporaryOutput(at: temporaryURL)
                        continuation.resume(returning: .failure(error.localizedDescription))
                    }
                }
            }
        }
    }

    private nonisolated static func removeTemporaryOutput(at url: URL) async {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.removeItem(at: url)
                AppLog.recording.info("Removed failed temporary recording output: \(url.path.abbreviatingHomeDirectory, privacy: .public).")
            } catch {
                AppLog.recording.error(
                    "Could not remove temporary recording output \(url.path.abbreviatingHomeDirectory, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }.value
    }
}

private struct RecordingDestination: Sendable {
    let temporaryURL: URL
    let finalURL: URL
}

private final class WriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

private enum RecordingFinishResult: Sendable {
    case success(URL)
    case failure(String)
}

private enum RecordingError: LocalizedError {
    case documentsDirectoryUnavailable
    case insufficientDiskSpace(available: Int64, required: Int64)
    case destinationAlreadyExists
    case cannotAddVideoInput
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            "The Documents directory is unavailable."
        case let .insufficientDiskSpace(available, required):
            "At least \(required / 1_048_576) MB of free disk space is required; only \(available / 1_048_576) MB is available."
        case .destinationAlreadyExists:
            "A recording with the generated name already exists."
        case .cannotAddVideoInput:
            "The H.264 video input could not be added to AVAssetWriter."
        case let .writerFailed(message):
            message
        }

    }
}

private extension String {
    var abbreviatingHomeDirectory: String {
        replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
