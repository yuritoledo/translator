import Foundation
import Observation

@MainActor
@Observable
final class LanguageDownloadState {
    private(set) var isSourceDownloading = false
    private(set) var isTargetDownloading = false

    func prepare(
        source: Locale.Language, target: Locale.Language,
        checker: LanguageAvailabilityChecking,
        operation: @MainActor () async throws -> Void
    ) async throws {
        defer {
            isSourceDownloading = false
            isTargetDownloading = false
        }
        let installed = await checker.isLanguagePairInstalled(source: source, target: target)
        try Task.checkCancellation()
        if !installed {
            let sourceInstalled = await checker.isLanguageInstalled(source)
            let targetInstalled = await checker.isLanguageInstalled(target)
            try Task.checkCancellation()
            isSourceDownloading = !sourceInstalled || targetInstalled
            isTargetDownloading = !targetInstalled || sourceInstalled
        }
        try await operation()
    }
}
