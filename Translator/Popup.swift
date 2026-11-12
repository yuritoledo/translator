import AVFoundation
import AppKit
import SwiftUI
@preconcurrency import Translation

enum PopupContent {
    case message(String)
    case request(text: String, source: Locale.Language, target: Locale.Language)
}

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Non-activating floating panel at the cursor.
@MainActor
enum Popup {
    private static var panel: NSPanel?
    private static var monitors: [Any] = []
    private static let synth = AVSpeechSynthesizer()
    static var isPreservingPopup = false

    static var isShown: Bool {
        guard let panel else {
            return false
        }
        let panelIsVisible = panel.isVisible
        return panelIsVisible
    }

    static func show(
        _ content: PopupContent, selectionBounds: CGRect? = nil, replacement: SelectionReplacement? = nil
    ) {
        close()
        let host = NSHostingView(rootView: PopupView(content: content, replacement: replacement))
        let size = NSSize(width: 380, height: 300)
        let floatingPanel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        floatingPanel.contentView = host
        floatingPanel.level = .floating
        floatingPanel.isOpaque = false
        floatingPanel.backgroundColor = .clear
        floatingPanel.hasShadow = true
        floatingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingPanel.isReleasedWhenClosed = false
        floatingPanel.hidesOnDeactivate = false
        let mouse = NSEvent.mouseLocation
        let position = PopupPosition.saved
        let anchor =
            position == .belowSelection ? selectionBounds.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse : mouse
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        floatingPanel.setFrameOrigin(
            position.origin(size: size, pointer: mouse, selection: selectionBounds, visibleFrame: bounds))
        floatingPanel.makeKeyAndOrderFront(nil)
        panel = floatingPanel
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { event in
                guard !isPreservingPopup else { return }
                if event.type != .keyDown || event.keyCode == 53 {
                    Task { @MainActor in close() }
                }
            })
        {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { event in
                if event.type == .keyDown && event.keyCode == 53 {
                    close()
                    return nil
                }
                guard !isPreservingPopup else { return event }
                let isCurrentPanel = event.window === panel
                let isSheet = event.window?.sheetParent === panel || panel?.attachedSheet === event.window
                if event.type != .keyDown && !isCurrentPanel && !isSheet {
                    close()
                }
                return event
            })
        {
            monitors.append(monitor)
        }
    }

    static func close() {
        synth.stopSpeaking(at: .immediate)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.close()
        panel = nil
    }

    static func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
    }
    static func speak(_ text: String, _ language: Locale.Language) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.minimalIdentifier)
        synth.speak(utterance)
    }
}

private struct PopupView: View {
    let content: PopupContent
    let replacement: SelectionReplacement?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Translator", systemImage: "translate")
                Spacer()
                Button("Close", systemImage: "xmark") { Popup.close() }
                    .labelStyle(.iconOnly)
            }
            Divider()
            switch content {
            case .message(let text):
                Text(text).foregroundStyle(.secondary)
                Spacer()
            case .request(let text, let source, let target):
                TranslationView(text: text, source: source, target: target, isPopup: true, replacement: replacement)
            }
        }
        .padding(16)
        .frame(width: 380, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TranslationView: View {
    @State private var text: String
    @State private var source: Locale.Language
    @State private var target: Locale.Language
    @State private var configuration: TranslationSession.Configuration?
    @State private var translated = ""
    @State private var error: String?
    @State private var busy = true
    @State private var downloadState = LanguageDownloadState()
    private let isPopup: Bool
    private let replacement: SelectionReplacement?
    private let availabilityChecker: LanguageAvailabilityChecking

    init(
        text: String, source: Locale.Language, target: Locale.Language,
        cachedTranslation: String? = nil, isPopup: Bool = false,
        replacement: SelectionReplacement? = nil,
        availabilityChecker: LanguageAvailabilityChecking = SystemLanguageAvailabilityChecker()
    ) {
        self.isPopup = isPopup
        self.replacement = replacement
        _text = State(initialValue: text)
        _source = State(initialValue: source)
        _target = State(initialValue: target)
        _translated = State(initialValue: cachedTranslation ?? "")
        let hasCache = cachedTranslation != nil
        _busy = State(initialValue: !hasCache)
        _configuration = State(initialValue: hasCache ? nil : .init(source: source, target: target))
        self.availabilityChecker = availabilityChecker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(name(source))
                    if downloadState.isSourceDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("→")
                HStack(spacing: 4) {
                    Text(name(target))
                    if downloadState.isTargetDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !isPopup { Text(text).foregroundStyle(.secondary).textSelection(.enabled) }
                    if busy { ProgressView("Translating…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if !translated.isEmpty { Text(translated).font(isPopup ? .title3 : .body).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Copy ⌘C", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translated, forType: .string)
                }
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy translation (⌘C)")
                Button("Speak", systemImage: "speaker.wave.2") { Popup.speak(translated, target) }
                Spacer()
                Button("Swap", systemImage: "arrow.left.arrow.right") {
                    text = translated
                    let previousSource = source
                    source = target
                    target = previousSource
                    translated = ""
                    busy = true
                    configuration = .init(source: source, target: target)
                }
            }.disabled(busy || translated.isEmpty)

            if isPopup {
                HStack {
                    Spacer()
                    Button("Replace ⌥R", systemImage: "arrow.turn.down.left") {
                        do {
                            guard let replacement else { throw SelectionReplacement.Failure.unavailable }
                            try replacement.replace(with: translated)
                            Popup.close()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .keyboardShortcut("r", modifiers: .option)
                    .help("Replace the original Selection with this translation (⌥R)")
                    .disabled(busy || translated.isEmpty)
                }
            }
        }
        .translationTask(configuration) { session in
            do {
                Popup.isPreservingPopup = true
                defer {
                    Popup.isPreservingPopup = false
                }
                try await downloadState.prepare(source: source, target: target, checker: availabilityChecker) {
                    NSApp.activate(ignoringOtherApps: true)
                    try await session.prepareTranslation()
                }
                Popup.isPreservingPopup = false
                let response = try await session.translate(text)
                guard !Task.isCancelled else { return }
                translated = response.targetText
                error = nil
                TranslationHistory.shared.add(
                    original: text, translation: response.targetText,
                    sourceLanguage: source.minimalIdentifier, targetLanguage: target.minimalIdentifier)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Translation failed: \(error.localizedDescription). Try translating again."
            }
            busy = false
        }
    }

    private func name(_ language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        let localizedName = Locale.current.localizedString(forIdentifier: identifier)
        let resolvedName = localizedName ?? identifier
        return resolvedName
    }
}
