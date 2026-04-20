import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isMirrored: Bool = false
    @Published var isAlwaysOnTop: Bool = false
    @Published var isChromeHidden: Bool = false
}
