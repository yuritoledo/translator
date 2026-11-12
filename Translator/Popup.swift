import AVFoundation
import AppKit
import SwiftUI
@preconcurrency import Translation

enum PopupContent {
    case message(String)
    case request(text: String, source: Locale.Language, target: Locale.Language)
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

    static func show(_ content: PopupContent, selectionBounds: CGRect? = nil) {
        close()
        let host = NSHostingView(rootView: PopupView(content: content))
        let size = NSSize(width: 380, height: 300)
        let floatingPanel = NSPanel(
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
        floatingPanel.orderFrontRegardless()
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
                TranslationView(text: text, source: source, target: target)
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
    @State private var isSourceDownloading = false
    @State private var isTargetDownloading = false

    private let availabilityChecker: LanguageAvailabilityChecking

    init(
        text: String,
        source: Locale.Language,
        target: Locale.Language,
        cachedTranslation: String? = nil,
        availabilityChecker: LanguageAvailabilityChecking = SystemLanguageAvailabilityChecker()
    ) {
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
                    if isSourceDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("→")
                HStack(spacing: 4) {
                    Text(name(target))
                    if isTargetDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text).foregroundStyle(.secondary).textSelection(.enabled)
                    if busy {
                        ProgressView("Translating…")
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    if !translated.isEmpty { Text(translated).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translated, forType: .string)
                }
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
        }
        .task(id: "\(source.minimalIdentifier)->\(target.minimalIdentifier)") {
            guard translated.isEmpty else { return }
            let isInstalled = await availabilityChecker.isLanguagePairInstalled(source: source, target: target)
            if !isInstalled {
                let sourceInstalled = await availabilityChecker.isLanguageInstalled(source)
                let targetInstalled = await availabilityChecker.isLanguageInstalled(target)
                isSourceDownloading = !sourceInstalled || targetInstalled
                isTargetDownloading = !targetInstalled || sourceInstalled
            }
        }
        .translationTask(configuration) { session in
            do {
                Popup.isPreservingPopup = true
                defer {
                    Popup.isPreservingPopup = false
                    isSourceDownloading = false
                    isTargetDownloading = false
                }
                NSApp.activate(ignoringOtherApps: true)
                try await session.prepareTranslation()
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
