import SwiftUI
import AppKit

struct PermissionDeniedView: View {
    let statusCode: Int
    var onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("Camera access required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Mettle needs camera permission to display your iPhone's screen. iOS devices appear to macOS under the camera privacy umbrella.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 10) {
                Button("Request Camera Access") {
                    onRequestAccess()
                }
                .buttonStyle(.borderedProminent)

                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 6)

            Text("Diagnostic: AVAuthorizationStatus rawValue = \(statusCode) (0=notDetermined 1=restricted 2=denied 3=authorized)")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.top, 14)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
