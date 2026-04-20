import AVFoundation
import Combine
import Foundation

@MainActor
final class DeviceDiscovery: ObservableObject {
    @Published private(set) var devices: [AVCaptureDevice] = []

    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var observers: [NSObjectProtocol] = []
    private var kvoToken: NSKeyValueObservation?

    init() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = Self.supportedDeviceTypes()
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .muxed,
            position: .unspecified
        )
        self.discoverySession = session

        // KVO on the discovery session picks up hot-plug changes reliably.
        kvoToken = session.observe(\.devices, options: [.initial, .new]) { [weak self] session, _ in
            let snapshot = session.devices
            Task { @MainActor in
                self?.refresh(from: snapshot)
            }
        }

        // Belt-and-suspenders notification subscriptions for older macOS.
        let center = NotificationCenter.default
        let connectToken = center.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let disconnectToken = center.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers = [connectToken, disconnectToken]

        refresh()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        kvoToken?.invalidate()
    }

    func refresh() {
        guard let session = discoverySession else { return }
        refresh(from: session.devices)
    }

    private func refresh(from discovered: [AVCaptureDevice]) {
        let filtered = discovered.filter(Self.isLikelyiPhone)
        if filtered.map(\.uniqueID) != devices.map(\.uniqueID) {
            devices = filtered
        }
    }

    private static func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = []
        if #available(macOS 14.0, *) {
            types.append(.external)
        } else {
            types.append(.externalUnknown)
        }
        return types
    }

    private static func isLikelyiPhone(_ device: AVCaptureDevice) -> Bool {
        // External video devices on macOS include webcams and capture cards.
        // Trusted iPhones report manufacturer "Apple Inc." and expose muxed media.
        let manufacturer = device.manufacturer
        let looksApple = manufacturer.localizedCaseInsensitiveContains("Apple")
        let hasMuxed = device.hasMediaType(.muxed)
        return looksApple && hasMuxed
    }
}
