import Foundation

enum CaptureError: LocalizedError {
    case cameraPermissionDenied
    case cameraPermissionRestricted
    case inputCreationFailed(underlying: Error)
    case sessionConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is denied. Enable it in System Settings > Privacy & Security > Camera."
        case .cameraPermissionRestricted:
            return "Camera access is restricted on this device."
        case .inputCreationFailed(let underlying):
            return "Couldn't start the iPhone stream: \(underlying.localizedDescription)"
        case .sessionConfigurationFailed:
            return "Couldn't configure the capture session."
        }
    }
}
