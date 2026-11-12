import Foundation
import XCTest

@testable import Translator

private struct DelayedAvailabilityChecker: LanguageAvailabilityChecking {
    func isLanguagePairInstalled(source: Locale.Language, target: Locale.Language) async -> Bool {
        try? await Task.sleep(for: .milliseconds(50))
        return false
    }

    func isLanguageInstalled(_ language: Locale.Language) async -> Bool {
        language.minimalIdentifier == "en"
    }
}

final class LanguageDownloadStateTests: XCTestCase {
    @MainActor func testSlowAvailabilityFinishesBeforePreparationAndCannotRestoreSpinners() async throws {
        let state = LanguageDownloadState()
        var prepared = false
        try await state.prepare(
            source: Locale.Language(identifier: "de"), target: Locale.Language(identifier: "en"),
            checker: DelayedAvailabilityChecker()
        ) {
            XCTAssertTrue(state.isSourceDownloading)
            XCTAssertFalse(state.isTargetDownloading)
            prepared = true
        }
        XCTAssertTrue(prepared)
        XCTAssertFalse(state.isSourceDownloading)
        XCTAssertFalse(state.isTargetDownloading)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(state.isSourceDownloading, "A late availability result must not restore the spinner")
        XCTAssertFalse(state.isTargetDownloading)
    }

    @MainActor func testPreparationFailureClearsSpinners() async {
        let state = LanguageDownloadState()
        do {
            try await state.prepare(
                source: Locale.Language(identifier: "de"), target: Locale.Language(identifier: "en"),
                checker: MockLanguageAvailabilityChecker(installedLanguages: ["en"])
            ) {
                XCTAssertTrue(state.isSourceDownloading)
                throw CancellationError()
            }
            XCTFail("Expected preparation to throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(state.isSourceDownloading)
        XCTAssertFalse(state.isTargetDownloading)
    }

    @MainActor func testInstalledPairDoesNotShowSpinners() async throws {
        let state = LanguageDownloadState()
        try await state.prepare(
            source: Locale.Language(identifier: "de"), target: Locale.Language(identifier: "en"),
            checker: MockLanguageAvailabilityChecker(installedLanguages: ["de", "en"])
        ) {
            XCTAssertFalse(state.isSourceDownloading)
            XCTAssertFalse(state.isTargetDownloading)
        }
    }
}
