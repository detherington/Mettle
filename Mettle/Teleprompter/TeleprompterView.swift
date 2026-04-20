import AppKit
import SwiftUI

struct TeleprompterView: View {
    @EnvironmentObject private var state: TeleprompterState

    var body: some View {
        VStack(spacing: 0) {
            TeleprompterTextView(
                text: $state.script,
                fontSize: state.fontSize,
                isPlaying: state.isPlaying,
                scrollSpeed: state.scrollSpeed,
                isMirrored: state.isMirrored
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay(alignment: .center) {
                if state.script.isEmpty {
                    Text("Paste or type your script")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }

            controlBar
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Color.black)
    }

    private var controlBar: some View {
        HStack(spacing: 18) {
            Button {
                state.isPlaying.toggle()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 24)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .help(state.isPlaying ? "Pause (Space)" : "Play (Space)")

            Button {
                state.isPlaying = false
                NotificationCenter.default.post(name: .teleprompterRewind, object: nil)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Rewind to top")

            Divider().frame(height: 18)

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: $state.fontSize, in: 24...140)
                    .frame(width: 120)
            }

            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)
                Slider(value: $state.scrollSpeed, in: 10...200)
                    .frame(width: 120)
            }

            Toggle(isOn: $state.isMirrored) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .toggleStyle(.button)
            .help("Mirror text horizontally")

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

extension Notification.Name {
    static let teleprompterRewind = Notification.Name("Mettle.teleprompterRewind")
}

// MARK: - Text view + auto-scroll

private struct TeleprompterTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var isPlaying: Bool
    var scrollSpeed: Double
    var isMirrored: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .black
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 48, height: 80)
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        textView.string = text
        textView.delegate = context.coordinator
        textView.wantsLayer = true

        context.coordinator.attach(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selectedRange.location, length), length: 0))
        }

        let desiredFont = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        if textView.font != desiredFont {
            textView.font = desiredFont
        }

        textView.isEditable = !isPlaying
        textView.isSelectable = true

        if isMirrored {
            textView.layer?.transform = CATransform3DMakeScale(-1, 1, 1)
        } else {
            textView.layer?.transform = CATransform3DIdentity
        }

        context.coordinator.setPlayback(isPlaying: isPlaying, speed: scrollSpeed)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var displayLink: CVDisplayLink?
        private var lastTickHostTime: UInt64 = 0
        private var currentSpeed: Double = 0
        private var isRunning = false
        private var rewindToken: NSObjectProtocol?

        init(text: Binding<String>) {
            self._text = text
            super.init()
            rewindToken = NotificationCenter.default.addObserver(
                forName: .teleprompterRewind,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scrollToTop()
            }
        }

        func attach(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }

        func setPlayback(isPlaying: Bool, speed: Double) {
            currentSpeed = speed
            if isPlaying {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }

        func invalidate() {
            stopDisplayLink()
            if let rewindToken {
                NotificationCenter.default.removeObserver(rewindToken)
                self.rewindToken = nil
            }
        }

        private func scrollToTop() {
            guard let scrollView, let clip = scrollView.contentView as NSClipView? else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
            scrollView.reflectScrolledClipView(clip)
        }

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            var link: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&link)
            guard let link else { return }
            let unmanaged = Unmanaged.passUnretained(self).toOpaque()
            CVDisplayLinkSetOutputCallback(link, { _, nowTs, outputTs, _, _, ctx in
                guard let ctx else { return kCVReturnSuccess }
                let coord = Unmanaged<Coordinator>.fromOpaque(ctx).takeUnretainedValue()
                coord.onDisplayLink(nowHostTime: nowTs.pointee.hostTime)
                return kCVReturnSuccess
            }, unmanaged)
            displayLink = link
            lastTickHostTime = 0
            isRunning = true
            CVDisplayLinkStart(link)
        }

        private func stopDisplayLink() {
            isRunning = false
            if let link = displayLink {
                CVDisplayLinkStop(link)
                displayLink = nil
            }
        }

        private nonisolated func onDisplayLink(nowHostTime: UInt64) {
            DispatchQueue.main.async { [weak self] in
                self?.advance(nowHostTime: nowHostTime)
            }
        }

        private func advance(nowHostTime: UInt64) {
            guard isRunning,
                  let scrollView,
                  let clip = scrollView.contentView as NSClipView?,
                  let doc = scrollView.documentView else { return }

            let delta: Double
            if lastTickHostTime == 0 {
                delta = 1.0 / 60.0
            } else {
                let hostSeconds = Double(nowHostTime - lastTickHostTime) / 1_000_000_000.0
                delta = min(max(hostSeconds, 0), 0.1)
            }
            lastTickHostTime = nowHostTime

            let increment = CGFloat(currentSpeed * delta)
            let maxY = max(0, doc.frame.height - clip.bounds.height)
            let newY = min(clip.bounds.origin.y + increment, maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: newY))
            scrollView.reflectScrolledClipView(clip)

            if newY >= maxY {
                stopDisplayLink()
            }
        }
    }
}
