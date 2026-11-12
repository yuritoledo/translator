import AppKit
import Carbon.HIToolbox
import XCTest

@testable import Translator

struct MockLanguageAvailabilityChecker: LanguageAvailabilityChecking {
    var installedLanguages: Set<String>

    func isLanguageInstalled(_ language: Locale.Language) async -> Bool {
        let identifier = language.minimalIdentifier
        let isInstalled = installedLanguages.contains(identifier)
        return isInstalled
    }

    func isLanguagePairInstalled(source: Locale.Language, target: Locale.Language) async -> Bool {
        let sourceInstalled = await isLanguageInstalled(source)
        let targetInstalled = await isLanguageInstalled(target)
        let bothInstalled = sourceInstalled && targetInstalled
        return bothInstalled
    }
}

final class TranslatorTests: XCTestCase {
    func testSelectionPopupAppearsBelowSelection() {
        let origin = PopupPosition.belowSelection.origin(
            size: CGSize(width: 380, height: 300), pointer: CGPoint(x: 900, y: 800),
            selection: CGRect(x: 100, y: 500, width: 240, height: 24),
            visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        XCTAssertEqual(origin, CGPoint(x: 100, y: 188))
    }

    func testSelectionPositionFallsBackToPointer() {
        let origin = PopupPosition.belowSelection.origin(
            size: CGSize(width: 380, height: 300), pointer: CGPoint(x: 400, y: 700),
            selection: nil, visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        XCTAssertEqual(origin, CGPoint(x: 400, y: 388))
    }

    func testPointerPositionIgnoresSelectionAndClampsToScreen() {
        let origin = PopupPosition.pointer.origin(
            size: CGSize(width: 380, height: 300), pointer: CGPoint(x: 1390, y: 10),
            selection: CGRect(x: 100, y: 500, width: 240, height: 24),
            visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        XCTAssertEqual(origin, CGPoint(x: 1020, y: 0))
    }

    func testPositionSupportsScreenLeftOfMainDisplay() {
        let origin = PopupPosition.belowSelection.origin(
            size: CGSize(width: 380, height: 300), pointer: .zero,
            selection: CGRect(x: -100, y: 700, width: 80, height: 20),
            visibleFrame: CGRect(x: -1400, y: 0, width: 1400, height: 900))
        XCTAssertEqual(origin, CGPoint(x: -380, y: 388))
    }

    func testAccessibilityCoordinatesConvertUsingMainDisplayHeight() {
        let rect = SelectionBounds.appKitRect(
            from: CGRect(x: -500, y: 200, width: 100, height: 20), mainDisplayTop: 900)
        XCTAssertEqual(rect, CGRect(x: -500, y: 680, width: 100, height: 20))
    }

    func testShortcutsAreDistinct() {
        XCTAssertEqual(Hotkey.Shortcut.selection.modifiers, UInt32(optionKey))
        XCTAssertEqual(Hotkey.Shortcut.typed.modifiers, UInt32(optionKey | shiftKey))
        XCTAssertNotEqual(Hotkey.Shortcut.selection.rawValue, Hotkey.Shortcut.typed.rawValue)
    }

    @MainActor func testTypedEnglishUsesPortugueseTarget() {
        guard
            case .request(let text, let source, let target) = Translator.content(for: "This sentence is safe to copy.")
        else {
            return XCTFail("Expected a translation request")
        }
        XCTAssertEqual(text, "This sentence is safe to copy.")
        XCTAssertEqual(source.languageCode?.identifier, "en")
        XCTAssertEqual(target.languageCode?.identifier, "pt")
    }

    @MainActor func testTypedPortugueseUsesEnglishTarget() {
        guard case .request(_, let source, let target) = Translator.content(for: "Esta frase é segura para copiar.")
        else {
            return XCTFail("Expected a translation request")
        }
        XCTAssertEqual(source.languageCode?.identifier, "pt")
        XCTAssertEqual(target.languageCode?.identifier, "en")
    }

    @MainActor func testBlankInputDoesNotStartTranslation() {
        guard case .message = Translator.content(for: " \n\t") else {
            return XCTFail("Blank input must not start translation")
        }
    }

    @MainActor func testTypedPopupOpensWithoutSelectionAndCloses() async throws {
        StatusBar.shared.show()
        defer { StatusBar.shared.close() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(StatusBar.shared.isShown)
        XCTAssertTrue(NSApp.keyWindow?.firstResponder is NSTextView, "The popup must focus its text editor")
        XCTAssertTrue(NSApp.windows.contains { $0.isVisible && $0.frame.width >= 420 })
        StatusBar.shared.close()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(StatusBar.shared.isShown)
    }

    @MainActor func testAvailabilityMockReportsInstalledLanguages() async throws {
        let mockChecker = MockLanguageAvailabilityChecker(installedLanguages: ["en"])
        let german = Locale.Language(identifier: "de")
        let english = Locale.Language(identifier: "en")

        let sourceInstalled = await mockChecker.isLanguageInstalled(german)
        let targetInstalled = await mockChecker.isLanguageInstalled(english)

        XCTAssertFalse(sourceInstalled)
        XCTAssertTrue(targetInstalled)
    }

    @MainActor func testLanguagePairInstallationRequiresBothLanguages() async throws {
        var mockChecker = MockLanguageAvailabilityChecker(installedLanguages: ["en"])
        let german = Locale.Language(identifier: "de")
        let english = Locale.Language(identifier: "en")

        let initiallyInstalled = await mockChecker.isLanguagePairInstalled(source: german, target: english)
        XCTAssertFalse(initiallyInstalled)

        mockChecker.installedLanguages.insert("de")
        let fullyInstalled = await mockChecker.isLanguagePairInstalled(source: german, target: english)
        XCTAssertTrue(fullyInstalled)
    }

    @MainActor func testPopupIgnoresOutsideClicksOnlyWhilePreparingLanguages() throws {
        Popup.show(.message("Preparing languages"))
        defer {
            Popup.isPreservingPopup = false
            Popup.close()
        }
        let outsideWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        outsideWindow.isReleasedWhenClosed = false
        defer { outsideWindow.close() }
        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: outsideWindow.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))

        Popup.isPreservingPopup = true
        NSApp.sendEvent(click)
        XCTAssertTrue(Popup.isShown, "Download dialog clicks must not dismiss the popup")

        Popup.isPreservingPopup = false
        NSApp.sendEvent(click)
        XCTAssertFalse(Popup.isShown, "Outside clicks must dismiss the popup after preparation")
    }

    @MainActor func testSystemLanguageAvailabilityCheckerInstantiates() async throws {
        let systemChecker = SystemLanguageAvailabilityChecker()
        let english = Locale.Language(identifier: "en")
        _ = await systemChecker.isLanguageInstalled(english)
    }

    func testSavedPopupPositionAndUnknownValueFallback() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: PopupPosition.defaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: PopupPosition.defaultsKey)
            } else {
                defaults.removeObject(forKey: PopupPosition.defaultsKey)
            }
        }
        defaults.set(PopupPosition.belowSelection.rawValue, forKey: PopupPosition.defaultsKey)
        XCTAssertEqual(PopupPosition.saved, .belowSelection)
        defaults.set("unknown", forKey: PopupPosition.defaultsKey)
        XCTAssertEqual(PopupPosition.saved, .pointer)
    }
    func testTranslationSymbolExists() {
        XCTAssertNotNil(NSImage(systemSymbolName: "translate", accessibilityDescription: "Translator"))
    }
}
