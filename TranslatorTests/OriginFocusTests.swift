import AppKit
import XCTest

@testable import Translator

@MainActor
private final class FakeOriginFocusTarget: OriginFocusTarget {
    let identifier: String
    var isCurrentProcess: Bool
    var isTerminated: Bool
    private(set) var restoreCount = 0

    init(identifier: String, isCurrentProcess: Bool = false, isTerminated: Bool = false) {
        self.identifier = identifier
        self.isCurrentProcess = isCurrentProcess
        self.isTerminated = isTerminated
    }

    func restoreFocus() {
        restoreCount += 1
    }
}

final class OriginFocusTests: XCTestCase {
    @MainActor private func resetOriginFocus() {
        OriginFocus.shared.targetProvider = {
            let currentTarget = SystemOriginFocusTarget.captureCurrent()
            return currentTarget
        }
        OriginFocus.shared.clear()
        Popup.close(restoreFocus: false, clearOriginFocus: true)
        StatusBar.shared.close(restoreFocus: false, clearOriginFocus: true)
    }

    @MainActor func testCapturesAndRestoresExternalApplicationFocus() {
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Safari")
        let focus = OriginFocus(targetProvider: { return externalTarget })

        focus.capture()
        focus.restore()

        XCTAssertEqual(externalTarget.restoreCount, 1)
        XCTAssertNil(focus.savedTarget)
    }

    @MainActor func testDoesNotOverwriteExternalFocusWithTranslatorProcess() {
        let externalTarget = FakeOriginFocusTarget(identifier: "com.microsoft.VSCode")
        let translatorTarget = FakeOriginFocusTarget(identifier: "co.yuritoledo.translator", isCurrentProcess: true)
        var currentTarget: any OriginFocusTarget = externalTarget
        let focus = OriginFocus(targetProvider: { return currentTarget })

        focus.capture()
        currentTarget = translatorTarget
        focus.capture()
        focus.restore()

        XCTAssertEqual(externalTarget.restoreCount, 1)
        XCTAssertEqual(translatorTarget.restoreCount, 0)
    }

    @MainActor func testTerminatedTargetIsNotRestored() {
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Notes")
        let focus = OriginFocus(targetProvider: { return externalTarget })

        focus.capture()
        externalTarget.isTerminated = true
        focus.restore()

        XCTAssertEqual(externalTarget.restoreCount, 0)
    }

    @MainActor func testPopupRestoresOriginFocusOnExplicitClose() {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Safari")
        OriginFocus.shared.targetProvider = { return externalTarget }

        Popup.show(.message("Translated text"))
        Popup.close()

        XCTAssertEqual(externalTarget.restoreCount, 1)
        XCTAssertNil(OriginFocus.shared.savedTarget)
    }

    @MainActor func testPopupRestoresOriginFocusOnEscapeKey() throws {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Safari")
        OriginFocus.shared.targetProvider = { return externalTarget }

        Popup.show(.message("Translated text"))
        let escapeEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escapeEvent)

        XCTAssertFalse(Popup.isShown)
        XCTAssertEqual(externalTarget.restoreCount, 1)
    }

    @MainActor func testPopupOutsideClickDoesNotRestoreOriginFocus() throws {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Safari")
        OriginFocus.shared.targetProvider = { return externalTarget }

        Popup.show(.message("Translated text"))
        let outsideWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        outsideWindow.isReleasedWhenClosed = false
        defer { outsideWindow.close() }
        let outsideClick = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: outsideWindow.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))

        NSApp.sendEvent(outsideClick)
        Popup.close()

        XCTAssertFalse(Popup.isShown)
        XCTAssertEqual(externalTarget.restoreCount, 0)
        XCTAssertNil(OriginFocus.shared.savedTarget)
    }

    @MainActor func testTypedPopupRestoresOriginFocusOnExplicitClose() {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Terminal")
        OriginFocus.shared.targetProvider = { return externalTarget }

        StatusBar.shared.show()
        XCTAssertTrue(StatusBar.shared.isShown)

        StatusBar.shared.close()

        XCTAssertFalse(StatusBar.shared.isShown)
        XCTAssertEqual(externalTarget.restoreCount, 1)
    }

    @MainActor func testTypedPopupImplicitDismissalClearsWithoutRestoringOriginFocus() {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.apple.Terminal")
        OriginFocus.shared.targetProvider = { return externalTarget }

        StatusBar.shared.show()
        StatusBar.shared.close(restoreFocus: false, clearOriginFocus: true)

        XCTAssertFalse(StatusBar.shared.isShown)
        XCTAssertEqual(externalTarget.restoreCount, 0)
        XCTAssertNil(OriginFocus.shared.savedTarget)
    }

    @MainActor func testTransitionBetweenSelectionPopupAndTypedPopupPreservesOriginFocus() {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.microsoft.VSCode")
        let translatorTarget = FakeOriginFocusTarget(identifier: "co.yuritoledo.translator", isCurrentProcess: true)
        var currentTarget: any OriginFocusTarget = externalTarget
        OriginFocus.shared.targetProvider = { return currentTarget }

        Popup.show(.message("Selection translation"))
        currentTarget = translatorTarget

        StatusBar.shared.show()
        XCTAssertFalse(Popup.isShown)
        XCTAssertTrue(StatusBar.shared.isShown)
        XCTAssertEqual(externalTarget.restoreCount, 0)

        StatusBar.shared.close()
        XCTAssertEqual(externalTarget.restoreCount, 1)
    }

    @MainActor func testTransitionBetweenTypedPopupAndSelectionPopupPreservesOriginFocus() {
        defer { resetOriginFocus() }
        let externalTarget = FakeOriginFocusTarget(identifier: "com.microsoft.VSCode")
        let translatorTarget = FakeOriginFocusTarget(identifier: "co.yuritoledo.translator", isCurrentProcess: true)
        var currentTarget: any OriginFocusTarget = externalTarget
        OriginFocus.shared.targetProvider = { return currentTarget }

        StatusBar.shared.show()
        currentTarget = translatorTarget

        OriginFocus.shared.capture()
        StatusBar.shared.close(restoreFocus: false, clearOriginFocus: false)
        Popup.close(restoreFocus: false, clearOriginFocus: false)
        Popup.show(.message("Selection translation"))

        XCTAssertEqual(externalTarget.restoreCount, 0)

        Popup.close()
        XCTAssertEqual(externalTarget.restoreCount, 1)
    }
}
