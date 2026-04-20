import AVFoundation
import Combine
import CoreMedia
import Foundation

@MainActor
final class CaptureSessionManager: ObservableObject {
    enum Status: Equatable {
        case idle
        case running(deviceID: String)
        case failed(message: String)
    }

    let session = AVCaptureSession()

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentDevice: AVCaptureDevice?
    @Published private(set) var videoDimensions: CGSize?

    private var currentInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let dimensionsReader = DimensionsSampleDelegate()
    private let sessionQueue = DispatchQueue(label: "Mettle.capture", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "Mettle.sampleBuffer", qos: .userInitiated)

    init() {
        session.sessionPreset = .high
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(dimensionsReader, queue: sampleQueue)
        dimensionsReader.onDimensions = { [weak self] size in
            Task { @MainActor in
                guard let self else { return }
                if self.videoDimensions != size {
                    self.videoDimensions = size
                }
            }
        }
    }

    func start(with device: AVCaptureDevice) {
        currentDevice = device
        videoDimensions = nil
        dimensionsReader.reset()
        let session = self.session
        let output = self.videoOutput
        sessionQueue.async { [weak self] in
            do {
                session.beginConfiguration()
                for existing in session.inputs {
                    session.removeInput(existing)
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    Task { @MainActor in
                        self?.resetState(message: "Couldn't add this iPhone as a capture input.")
                    }
                    return
                }
                session.addInput(input)

                if !session.outputs.contains(output) {
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                    }
                }
                session.commitConfiguration()

                if !session.isRunning {
                    session.startRunning()
                }

                Task { @MainActor in
                    self?.currentInput = input
                    self?.status = .running(deviceID: device.uniqueID)
                }
            } catch {
                session.commitConfiguration()
                Task { @MainActor in
                    self?.resetState(
                        message: CaptureError.inputCreationFailed(underlying: error).localizedDescription
                    )
                }
            }
        }
    }

    func stop() {
        videoDimensions = nil
        let session = self.session
        sessionQueue.async { [weak self] in
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()
            Task { @MainActor in
                self?.dimensionsReader.reset()
                self?.currentInput = nil
                self?.currentDevice = nil
                self?.status = .idle
            }
        }
    }

    private func resetState(message: String) {
        currentInput = nil
        videoDimensions = nil
        dimensionsReader.reset()
        status = .failed(message: message)
    }
}

private final class DimensionsSampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onDimensions: ((CGSize) -> Void)?
    private let lock = NSLock()
    private var lastReported: CGSize?

    func reset() {
        lock.lock()
        lastReported = nil
        lock.unlock()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        guard dims.width > 0, dims.height > 0 else { return }
        let size = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))

        lock.lock()
        let changed = lastReported != size
        if changed {
            lastReported = size
        }
        lock.unlock()

        if changed {
            onDimensions?(size)
        }
    }
}
