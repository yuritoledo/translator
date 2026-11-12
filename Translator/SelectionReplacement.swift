import AppKit
import ApplicationServices

@MainActor
protocol SelectionReplacementTarget {
    var selectedText: String? { get }
    var selectedRange: NSRange? { get }
    var canReplaceSelection: Bool { get }
    func replaceSelectedText(with text: String) -> Bool
    func activate()
}

@MainActor
final class SelectionReplacement {
    enum Failure: LocalizedError {
        case unavailable
        case changed
        case emptyTranslation

        var errorDescription: String? {
            switch self {
            case .unavailable: "This app does not support safe replacement. Use Copy and paste the translation instead."
            case .changed: "The original Selection changed. Select the text and translate it again."
            case .emptyTranslation: "There is no translation to replace the Selection with."
            }
        }
    }

    let originalText: String
    private let range: NSRange
    private let target: any SelectionReplacementTarget
    private var replaced = false

    init?(target: any SelectionReplacementTarget) {
        guard let text = target.selectedText, let range = target.selectedRange,
            !text.isEmpty, range.length > 0
        else { return nil }
        originalText = text
        self.range = range
        self.target = target
    }

    static func capture() -> SelectionReplacement? {
        guard let target = AccessibilitySelectionTarget.focused() else { return nil }
        return SelectionReplacement(target: target)
    }

    func replace(with translation: String) throws {
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.emptyTranslation
        }
        guard !replaced, target.selectedText == originalText, target.selectedRange == range else {
            throw Failure.changed
        }
        guard target.canReplaceSelection, target.replaceSelectedText(with: translation) else {
            throw Failure.unavailable
        }
        replaced = true
        target.activate()
    }
}

/// Uses only the selected-text attribute. Never writes the whole text-field value or sends paste.
@MainActor
private struct AccessibilitySelectionTarget: SelectionReplacementTarget {
    let element: AXUIElement
    let app: NSRunningApplication

    static func focused() -> AccessibilitySelectionTarget? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
            pid != ProcessInfo.processInfo.processIdentifier,
            let app = NSRunningApplication(processIdentifier: pid)
        else { return nil }
        return AccessibilitySelectionTarget(element: element, app: app)
    }

    var selectedText: String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    var selectedRange: NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
            range.location >= 0, range.length > 0
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    var canReplaceSelection: Bool {
        var settable: DarwinBoolean = false
        return !app.isTerminated
            && AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    func replaceSelectedText(with text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    func activate() {
        app.activate(options: [])
    }
}
