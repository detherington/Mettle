import SwiftUI
import CoreMediaIO
import Sparkle

@main
struct MettleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var teleprompterState = TeleprompterState()
    private let updaterController: SPUStandardUpdaterController

    init() {
        Self.enableScreenCaptureDevices()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 360, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandMenu("View") {
                Toggle("Mirror Horizontally", isOn: $appState.isMirrored)
                    .keyboardShortcut("m", modifiers: .command)
                Toggle("Always on Top", isOn: $appState.isAlwaysOnTop)
                    .keyboardShortcut("t", modifiers: .command)
                Divider()
                Toggle("Hide Window Chrome", isOn: $appState.isChromeHidden)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowList) {
                Divider()
                OpenTeleprompterCommand()
            }
        }

        Window("Teleprompter", id: "teleprompter") {
            TeleprompterView()
                .environmentObject(teleprompterState)
        }
    }

    /// Required for iOS devices to appear in the AVCaptureDevice list.
    private static func enableScreenCaptureDevices() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
    }
}

private struct OpenTeleprompterCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Teleprompter") {
            openWindow(id: "teleprompter")
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
    }
}
