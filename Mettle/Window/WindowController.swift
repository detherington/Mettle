import AppKit
import SwiftUI

/// Bridges SwiftUI state to NSWindow behaviors SwiftUI doesn't expose:
/// always-on-top, chrome hiding, and locked aspect-ratio resizing.
struct WindowConfigurator: NSViewRepresentable {
    let isAlwaysOnTop: Bool
    let isChromeHidden: Bool
    let videoDimensions: CGSize?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onWindowAvailable = { [coord = context.coordinator, s = self] window in
            coord.apply(
                window: window,
                alwaysOnTop: s.isAlwaysOnTop,
                chromeHidden: s.isChromeHidden,
                videoDimensions: s.videoDimensions
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else {
            (nsView as? AccessorView)?.onWindowAvailable = { [coord = context.coordinator, s = self] window in
                coord.apply(
                    window: window,
                    alwaysOnTop: s.isAlwaysOnTop,
                    chromeHidden: s.isChromeHidden,
                    videoDimensions: s.videoDimensions
                )
            }
            return
        }
        context.coordinator.apply(
            window: window,
            alwaysOnTop: isAlwaysOnTop,
            chromeHidden: isChromeHidden,
            videoDimensions: videoDimensions
        )
    }

    final class Coordinator {
        private var appliedRestorable = false
        private var appliedAlwaysOnTop: Bool?
        private var appliedChromeHidden: Bool?
        private var appliedAspect: CGSize = .zero
        private var needsInitialSize = true

        func apply(
            window: NSWindow,
            alwaysOnTop: Bool,
            chromeHidden: Bool,
            videoDimensions: CGSize?
        ) {
            if !appliedRestorable {
                window.isRestorable = false
                appliedRestorable = true
            }

            if appliedAlwaysOnTop != alwaysOnTop {
                window.level = alwaysOnTop ? .floating : .normal
                appliedAlwaysOnTop = alwaysOnTop
            }

            if appliedChromeHidden != chromeHidden {
                applyChrome(window: window, hidden: chromeHidden)
                appliedChromeHidden = chromeHidden
            }

            let targetAspect = videoDimensions.flatMap { dims in
                (dims.width > 0 && dims.height > 0) ? dims : nil
            } ?? .zero

            if !nsSizeEqual(appliedAspect, targetAspect) {
                let hadPreviousAspect = appliedAspect != .zero
                window.contentAspectRatio = targetAspect
                appliedAspect = targetAspect
                if targetAspect == .zero {
                    needsInitialSize = true
                } else if needsInitialSize {
                    needsInitialSize = false
                    resizeToFit(window: window, aspect: targetAspect)
                } else if hadPreviousAspect {
                    animateToNewAspect(window: window, aspect: targetAspect)
                }
            }
        }

        private func applyChrome(window: NSWindow, hidden: Bool) {
            if hidden {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.toolbar?.isVisible = false
            } else {
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.styleMask.remove(.fullSizeContentView)
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
                window.toolbar?.isVisible = true
            }
        }

        private func resizeToFit(window: NSWindow, aspect: CGSize) {
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let maxW = visible.width * 0.5
            let maxH = visible.height * 0.85
            let ratio = aspect.width / aspect.height

            var targetH: CGFloat = 720
            var targetW = targetH * ratio
            if targetW > maxW {
                targetW = maxW
                targetH = targetW / ratio
            }
            if targetH > maxH {
                targetH = maxH
                targetW = targetH * ratio
            }

            let oldCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
            window.setContentSize(NSSize(width: targetW, height: targetH))
            let newFrame = window.frame
            window.setFrameOrigin(NSPoint(
                x: oldCenter.x - newFrame.width / 2,
                y: oldCenter.y - newFrame.height / 2
            ))
        }

        private func animateToNewAspect(window: NSWindow, aspect: CGSize) {
            guard !window.inLiveResize else { return }

            let currentContent = window.contentRect(forFrameRect: window.frame).size
            let currentArea = currentContent.width * currentContent.height
            guard currentArea > 0 else { return }

            let ratio = aspect.width / aspect.height
            var newWidth = sqrt(currentArea * ratio)
            var newHeight = newWidth / ratio

            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let maxW = visible.width * 0.9
            let maxH = visible.height * 0.9
            if newWidth > maxW {
                newWidth = maxW
                newHeight = newWidth / ratio
            }
            if newHeight > maxH {
                newHeight = maxH
                newWidth = newHeight * ratio
            }

            let newContent = NSSize(width: newWidth, height: newHeight)
            let newFrameSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: newContent)
            ).size
            let oldCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
            let newFrame = NSRect(
                x: oldCenter.x - newFrameSize.width / 2,
                y: oldCenter.y - newFrameSize.height / 2,
                width: newFrameSize.width,
                height: newFrameSize.height
            )

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        }

        private func nsSizeEqual(_ a: CGSize, _ b: CGSize) -> Bool {
            abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
        }
    }
}

private final class AccessorView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowAvailable?(window)
        }
    }
}
