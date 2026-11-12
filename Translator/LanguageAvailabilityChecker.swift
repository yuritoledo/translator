import Foundation
import Translation

protocol LanguageAvailabilityChecking: Sendable {
    func isLanguageInstalled(_ language: Locale.Language) async -> Bool
    func isLanguagePairInstalled(source: Locale.Language, target: Locale.Language) async -> Bool
}

struct SystemLanguageAvailabilityChecker: LanguageAvailabilityChecking {
    func isLanguageInstalled(_ language: Locale.Language) async -> Bool {
        let availability = LanguageAvailability()
        let status = await availability.status(from: language, to: nil)
        let isInstalled = status == .installed
        return isInstalled
    }

    func isLanguagePairInstalled(source: Locale.Language, target: Locale.Language) async -> Bool {
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        let isInstalled = status == .installed
        return isInstalled
    }
}
