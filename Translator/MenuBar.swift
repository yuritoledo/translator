import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBar.shared.start()
    }
}

/// A real status item gives the global shortcut a stable popover anchor.
@MainActor
final class StatusBar: NSObject, NSPopoverDelegate {
    static let shared = StatusBar()
    private var item: NSStatusItem?
    private let popover = NSPopover()

    var isShown: Bool { popover.isShown }
    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translator")?
                .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Translator — Type: ⌥⇧T · Selection: ⌥T"
            button.setAccessibilityLabel("Translator")
            button.target = self
            button.action = #selector(toggle)
        }
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 510)
        Hotkey.register(selection: { Task { await Translator.run() } }, typed: { self.toggle() })
    }

    @objc private func toggle() {
        if popover.isShown { close() } else { show() }
    }

    func show() {
        guard let button = item?.button else { return }
        Popup.close()
        if !popover.isShown {
            popover.contentViewController = NSHostingController(rootView: TypedPopupView())
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        Popup.stopSpeaking()
        // Release the editor and task. Successful results remain in local history.
        popover.contentViewController = nil
    }
}

private struct TypedRequest: Identifiable {
    let id = UUID()
    let content: PopupContent
    var cachedTranslation: String? = nil
}

private struct TypedPopupView: View {
    @State private var text = ""
    @State private var request: TypedRequest?
    @State private var history = TranslationHistory.shared
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Translator", systemImage: "translate").font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") { StatusBar.shared.close() }
                    .labelStyle(.iconOnly)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused($editorFocused)
                    .accessibilityLabel("Text to translate")
                if text.isEmpty {
                    Text("Type or paste text…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 96)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
            HStack {
                Text("⌘↩ to translate").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Translate") {
                    request = TypedRequest(content: Translator.content(for: text))
                    editorFocused = false
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Divider()
            if let request {
                HStack {
                    Button("Recent translations", systemImage: "chevron.left") {
                        self.request = nil
                        Popup.stopSpeaking()
                    }.buttonStyle(.link)
                    Spacer()
                }
                switch request.content {
                case .message(let message):
                    Text(message).foregroundStyle(.secondary)
                    Spacer()
                case .request(let text, let source, let target):
                    TranslationView(
                        text: text, source: source, target: target,
                        cachedTranslation: request.cachedTranslation
                    ).id(request.id)
                }
            } else {
                RecentTranslationsView(
                    entries: history.entries,
                    onSelect: { entry in
                        text = entry.original
                        request = TypedRequest(
                            content: .request(
                                text: entry.original,
                                source: Locale.Language(identifier: entry.sourceLanguage),
                                target: Locale.Language(identifier: entry.targetLanguage)),
                            cachedTranslation: entry.translation)
                        editorFocused = false
                    }, onClear: { history.clear() })
            }
            Divider()
            HStack {
                Text("Select text anywhere: ⌥T").font(.caption).foregroundStyle(.secondary)
                Spacer()
                SettingsMenu()
            }
        }
        .padding(16)
        .frame(width: 420, height: 510)
        .task {
            await Task.yield()
            editorFocused = true
        }
        .onExitCommand { StatusBar.shared.close() }
    }
}

private struct SettingsMenu: View {
    @AppStorage(PopupPosition.defaultsKey) private var position: PopupPosition = .pointer
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Menu {
            Picker("Selection popup position", selection: $position) {
                ForEach(PopupPosition.allCases, id: \.self) { position in
                    Text(position.label).tag(position)
                }
            }
            Text("Selection bounds unavailable? Uses pointer.")
            Divider()
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError =
                            SMAppService.mainApp.status == .requiresApproval
                            ? "Approve Translator in System Settings → General → Login Items." : nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                }
            if let loginError { Text(loginError) }
            Button("Accessibility settings…") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            ForEach(Hotkey.Shortcut.allCases, id: \.self) { shortcut in
                if let status = Hotkey.failures[shortcut] {
                    Text(
                        "Cannot register \(shortcut.label) (error \(status)). Quit other apps that use it, then reopen Translator."
                    )
                }
            }
            Divider()
            Button("Quit Translator") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}
