import AppKit
import NaturalLanguage
import Translation

/// Selected-text capture and language direction shared with the typed-text popup.
@MainActor
enum Translator {
    private static var capturing = false

    static func run() async {
        guard !capturing else { return }
        capturing = true
        defer { capturing = false }
        OriginFocus.shared.capture()
        StatusBar.shared.close(restoreFocus: false, clearOriginFocus: false)
        Popup.close(restoreFocus: false, clearOriginFocus: false)
        guard
            AXIsProcessTrustedWithOptions(
                [
                    "AXTrustedCheckOptionPrompt": true
                ] as CFDictionary)
        else {
            Popup.show(
                .message(
                    "Enable Translator in System Settings → Privacy & Security → Accessibility. Then select text and press ⌥T again."
                ))
            return
        }
        // Read bounds before sending copy; some apps collapse their selection on copy.
        let bounds = PopupPosition.saved == .belowSelection ? SelectionBounds.current() : nil
        let replacement = SelectionReplacement.capture()
        guard let text = await Capture.selection() else {
            Popup.show(.message("No text was copied.\n\n\(Capture.diagnostic)"), selectionBounds: bounds)
            return
        }
        Popup.show(
            content(for: text), selectionBounds: bounds,
            replacement: replacement?.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                == text.trimmingCharacters(in: .whitespacesAndNewlines) ? replacement : nil)
    }

    static func content(for text: String) -> PopupContent {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .message("Enter a sentence to translate.")
        }
        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text) else {
            return .message("Cannot detect the language. Try a longer sentence.")
        }
        let source = Locale.Language(identifier: detected.rawValue)
        let target = Locale.Language(identifier: detected == .english ? "pt" : "en")
        return .request(text: text, source: source, target: target)
    }
}
