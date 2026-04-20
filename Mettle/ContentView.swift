import AVFoundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.darrelletherington.Mettle", category: "permissions")

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @StateObject private var discovery = DeviceDiscovery()
    @StateObject private var capture = CaptureSessionManager()

    @State private var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var selectedDeviceID: String?
    @State private var hasFinishedInitialScan: Bool = false

    private var activeDevice: AVCaptureDevice? {
        guard let id = selectedDeviceID else { return nil }
        return discovery.devices.first(where: { $0.uniqueID == id })
    }

    var body: some View {
        ZStack {
            content
                .background(Color.black)

            WindowConfigurator(
                isAlwaysOnTop: appState.isAlwaysOnTop,
                isChromeHidden: appState.isChromeHidden,
                videoDimensions: capture.videoDimensions
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            EscapeMonitor {
                if appState.isChromeHidden {
                    appState.isChromeHidden = false
                }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .toolbar { toolbarContent }
        .navigationTitle("Mettle")
        .task { await bootstrap() }
        .onReceive(discovery.$devices) { devices in
            handleDeviceListChange(devices)
        }
        .onChange(of: selectedDeviceID) { newValue in
            if let id = newValue, let device = discovery.devices.first(where: { $0.uniqueID == id }) {
                capture.start(with: device)
            } else {
                capture.stop()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch authorizationStatus {
        case .denied, .restricted:
            PermissionDeniedView(
                statusCode: Int(authorizationStatus.rawValue),
                onRequestAccess: { Task { await requestCameraAccess() } }
            )
        case .notDetermined:
            EmptyStateView(isSearching: true)
        case .authorized:
            if activeDevice != nil {
                PreviewView(session: capture.session, isMirrored: appState.isMirrored)
            } else {
                EmptyStateView(isSearching: !hasFinishedInitialScan)
            }
        @unknown default:
            EmptyStateView(isSearching: false)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DevicePicker(devices: discovery.devices, selectedDeviceID: $selectedDeviceID)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.isMirrored.toggle()
            } label: {
                Label(
                    "Mirror",
                    systemImage: appState.isMirrored
                        ? "rectangle.righthalf.inset.filled.arrow.right"
                        : "arrow.left.and.right.righttriangle.left.righttriangle.right"
                )
            }
            .help("Mirror horizontally (⌘M)")

            Button {
                appState.isAlwaysOnTop.toggle()
            } label: {
                Label("Always on Top", systemImage: appState.isAlwaysOnTop ? "pin.fill" : "pin")
            }
            .help("Keep window on top (⌘T)")

            Button {
                appState.isChromeHidden.toggle()
            } label: {
                Label(
                    "Hide Chrome",
                    systemImage: appState.isChromeHidden ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
            }
            .help("Hide window chrome (⌘⇧F)")
        }
    }

    private func bootstrap() async {
        let initial = AVCaptureDevice.authorizationStatus(for: .video)
        log.notice("Launch — initial camera authorization status rawValue=\(initial.rawValue, privacy: .public)")

        switch initial {
        case .notDetermined:
            await requestCameraAccess()
        case let status:
            authorizationStatus = status
        }

        // Give the iPhone 4 seconds to appear after launch (first-connect latency).
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        hasFinishedInitialScan = true
    }

    private func requestCameraAccess() async {
        let before = AVCaptureDevice.authorizationStatus(for: .video)
        log.notice("requestCameraAccess — before rawValue=\(before.rawValue, privacy: .public)")
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        let after = AVCaptureDevice.authorizationStatus(for: .video)
        log.notice("requestCameraAccess — granted=\(granted, privacy: .public) after rawValue=\(after.rawValue, privacy: .public)")
        authorizationStatus = after
    }

    private func handleDeviceListChange(_ devices: [AVCaptureDevice]) {
        if let id = selectedDeviceID, devices.contains(where: { $0.uniqueID == id }) {
            return
        }
        if devices.count == 1 {
            selectedDeviceID = devices.first?.uniqueID
        } else if devices.isEmpty {
            selectedDeviceID = nil
        } else if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.uniqueID
        }
    }
}
