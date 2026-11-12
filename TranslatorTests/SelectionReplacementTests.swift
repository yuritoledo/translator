import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import Translator

@MainActor
private final class FakeSelectionTarget: SelectionReplacementTarget {
    var selectedText: String? = "Olá, mundo"
    var selectedRange: NSRange? = NSRange(location: 4, length: 10)
    var canReplaceSelection = true
    var acceptsReplacement = true
    var replacements: [String] = []
    var activated = false

    func replaceSelectedText(with text: String) -> Bool {
        guard acceptsReplacement else { return false }
        replacements.append(text)
        return true
    }

    func activate() {
        activated = true
    }
}

final class SelectionReplacementTests: XCTestCase {
    @MainActor func testReplacesOnlyTheOriginalSelectionAndReturnsToSourceApp() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        try replacement.replace(with: "Hello, world")
        XCTAssertEqual(target.replacements, ["Hello, world"])
        XCTAssertTrue(target.activated)
    }

    @MainActor func testChangedTextDoesNotWriteOrActivate() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        target.selectedText = "Outro texto"
        XCTAssertThrowsError(try replacement.replace(with: "Hello, world"))
        XCTAssertTrue(target.replacements.isEmpty)
        XCTAssertFalse(target.activated)
    }

    @MainActor func testSameTextAtDifferentRangeDoesNotWrite() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        target.selectedRange = NSRange(location: 20, length: 10)
        XCTAssertThrowsError(try replacement.replace(with: "Hello, world"))
        XCTAssertTrue(target.replacements.isEmpty)
    }

    @MainActor func testReadOnlySelectionDoesNotWrite() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        target.canReplaceSelection = false
        XCTAssertThrowsError(try replacement.replace(with: "Hello, world"))
        XCTAssertTrue(target.replacements.isEmpty)
    }

    @MainActor func testRejectedWriteDoesNotActivateSourceApp() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        target.acceptsReplacement = false
        XCTAssertThrowsError(try replacement.replace(with: "Hello, world"))
        XCTAssertFalse(target.activated)
    }

    @MainActor func testEmptyTranslationCannotDeleteSelection() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        XCTAssertThrowsError(try replacement.replace(with: " \n"))
        XCTAssertTrue(target.replacements.isEmpty)
    }

    @MainActor func testMissingSelectionDoesNotCreateReplacement() {
        let target = FakeSelectionTarget()
        target.selectedRange = nil
        XCTAssertNil(SelectionReplacement(target: target))
        target.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertNil(SelectionReplacement(target: target))
    }

    @MainActor func testReplacementCannotRunTwice() throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        try replacement.replace(with: "Hello, world")
        XCTAssertThrowsError(try replacement.replace(with: "Hello again"))
        XCTAssertEqual(target.replacements.count, 1)
    }

    @MainActor func testOptionRReplacesFromTheTranslationView() async throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        let window = replacementWindow(replacement: replacement, cachedTranslation: "Hello, world")
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        let handled = window.performKeyEquivalent(with: try optionR(window: window))
        XCTAssertTrue(handled, "The Popup must handle Option+R")
        XCTAssertEqual(target.replacements, ["Hello, world"])
    }

    @MainActor func testOptionRCannotReplaceWhileTranslationIsMissing() async throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        let window = replacementWindow(replacement: replacement, cachedTranslation: "")
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        _ = window.performKeyEquivalent(with: try optionR(window: window))
        XCTAssertTrue(target.replacements.isEmpty)
    }

    @MainActor func testTypedTranslationDoesNotOfferOptionR() async throws {
        let target = FakeSelectionTarget()
        let replacement = try XCTUnwrap(SelectionReplacement(target: target))
        let window = replacementWindow(replacement: replacement, cachedTranslation: "Hello, world", isPopup: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(window.performKeyEquivalent(with: try optionR(window: window)))
        XCTAssertTrue(target.replacements.isEmpty)
    }

    @MainActor private func replacementWindow(
        replacement: SelectionReplacement, cachedTranslation: String, isPopup: Bool = true
    ) -> NSWindow {
        let view = TranslationView(
            text: replacement.originalText, source: Locale.Language(identifier: "pt"),
            target: Locale.Language(identifier: "en"), cachedTranslation: cachedTranslation,
            isPopup: isPopup, replacement: replacement)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @MainActor private func optionR(window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "®",
                charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
    }
}
