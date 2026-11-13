import AppKit
import ApplicationServices

@MainActor
protocol OriginFocusTarget {
    var isCurrentProcess: Bool { get }
    var isTerminated: Bool { get }
    func restoreFocus()
}

@MainActor
final class OriginFocus {
    static let shared = OriginFocus()

    var targetProvider: () -> (any OriginFocusTarget)?
    private(set) var savedTarget: (any OriginFocusTarget)?

    init(
        targetProvider: @escaping () -> (any OriginFocusTarget)? = {
            let currentTarget = SystemOriginFocusTarget.captureCurrent()
            return currentTarget
        }
    ) {
        self.targetProvider = targetProvider
    }

    func capture() {
        guard let currentTarget = targetProvider(), !currentTarget.isTerminated else { return }
        if currentTarget.isCurrentProcess { return }

        savedTarget = currentTarget
    }

    func restore() {
        let targetToRestore = savedTarget
        savedTarget = nil

        guard let targetToRestore, !targetToRestore.isCurrentProcess, !targetToRestore.isTerminated else { return }
        targetToRestore.restoreFocus()
    }

    func clear() {
        savedTarget = nil
    }
}

@MainActor
struct SystemOriginFocusTarget: OriginFocusTarget {
    let application: NSRunningApplication
    let focusedWindow: AXUIElement?
    let focusedElement: AXUIElement?

    var isCurrentProcess: Bool {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let matchesCurrentProcess = application.processIdentifier == currentProcessIdentifier
        return matchesCurrentProcess
    }

    var isTerminated: Bool {
        let applicationTerminated = application.isTerminated
        return applicationTerminated
    }

    static func captureCurrent() -> SystemOriginFocusTarget? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        if frontmostApplication.processIdentifier == currentProcessIdentifier {
            let currentProcessTarget = SystemOriginFocusTarget(
                application: frontmostApplication, focusedWindow: nil, focusedElement: nil)
            return currentProcessTarget
        }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        let focusedWindow = copyAccessibilityElement(
            from: applicationElement, attribute: kAXFocusedWindowAttribute as CFString)
        let focusedElement = copyAccessibilityElement(
            from: applicationElement, attribute: kAXFocusedUIElementAttribute as CFString)

        let capturedTarget = SystemOriginFocusTarget(
            application: frontmostApplication, focusedWindow: focusedWindow, focusedElement: focusedElement)
        return capturedTarget
    }

    func restoreFocus() {
        guard !application.isTerminated else { return }

        application.activate()

        if let focusedWindow {
            AXUIElementSetAttributeValue(focusedWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(focusedWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(focusedWindow, kAXRaiseAction as CFString)
        }

        if let focusedElement {
            AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func copyAccessibilityElement(
        from element: AXUIElement, attribute: CFString
    ) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        var attributeValue: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(element, attribute, &attributeValue)
        guard copyStatus == .success, let attributeValue else { return nil }

        let valueTypeIdentifier = CFGetTypeID(attributeValue)
        let elementTypeIdentifier = AXUIElementGetTypeID()
        guard valueTypeIdentifier == elementTypeIdentifier else { return nil }

        let accessibilityElement = unsafeBitCast(attributeValue, to: AXUIElement.self)
        return accessibilityElement
    }
}
