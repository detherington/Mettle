import Foundation

@MainActor
final class TeleprompterState: ObservableObject {
    @Published var script: String = ""
    @Published var fontSize: CGFloat = 56
    @Published var scrollSpeed: Double = 45   // points per second
    @Published var isPlaying: Bool = false
    @Published var isMirrored: Bool = false
}
