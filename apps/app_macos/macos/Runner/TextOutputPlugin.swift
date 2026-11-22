import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS

/// Flutter plugin for dictation output (T2): clipboard and synthetic ⌘V.
///
/// Channel `com.icitranscript/text_output`:
/// - `isAccessibilityTrusted` -> Bool, never shows the system prompt.
/// - `requestAccessibility` -> Bool: same check, but asks macOS to show its
///   prompt when not trusted (asynchronous; the value is the current state).
/// - `openAccessibilitySettings` -> Bool: opens System Settings, Privacy &
///   Security > Accessibility.
/// - `copy` {text} -> nil: replaces the general pasteboard with the text.
/// - `saveClipboard` -> nil: in-memory copy of every item and every type of
///   the general pasteboard (images, files, rich text...).
/// - `restoreClipboard` -> nil: writes that copy back; no-op if none.
/// - `paste` -> nil: posts ⌘V key down/up to the HID tap. FlutterError
///   `ACCESSIBILITY_NOT_TRUSTED` or `PASTE_FAILED` when it cannot be posted.
///   Returns once the events are posted, not once the frontmost app has
///   read the pasteboard: the caller must wait before `restoreClipboard`.
///
/// Apple documentation used:
/// - https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted
/// - https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
///   (kAXTrustedCheckOptionPrompt: true shows the prompt, asynchronously)
/// - https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)
///   The `x-apple.systempreferences:` pane URL is not documented by Apple;
///   it is the one AudioCapturePlugin already uses for the other panes.
/// - https://developer.apple.com/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:)
/// - https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)
/// - https://developer.apple.com/documentation/appkit/nspasteboarditem
///   (items go stale when the pasteboard owner changes and cannot be
///   written twice, hence the deep copy to plain Data below)
/// - HIToolbox Events.h (SDK header): kVK_ANSI_V.
class TextOutputPlugin: NSObject, FlutterPlugin {

    /// One entry per pasteboard item: every type with its data.
    private var saved: [[(NSPasteboard.PasteboardType, Data)]]?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/text_output",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(TextOutputPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAccessibilityTrusted":
            result(AXIsProcessTrusted())
        case "requestAccessibility":
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            result(AXIsProcessTrustedWithOptions(options))
        case "openAccessibilitySettings":
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            result(NSWorkspace.shared.open(url))
        case "copy":
            guard let text = (call.arguments as? [String: Any])?["text"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing text", details: nil))
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            result(pasteboard.setString(text, forType: .string)
                ? nil : FlutterError(code: "COPY_FAILED", message: "setString failed", details: nil))
        case "saveClipboard":
            saved = NSPasteboard.general.pasteboardItems?.map { item in
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            } ?? []
            result(nil)
        case "restoreClipboard":
            restore()
            result(nil)
        case "paste":
            result(paste())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func restore() {
        guard let snapshot = saved else { return }
        saved = nil
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func paste() -> FlutterError? {
        // Without Accessibility, CGEvent posting is silently dropped: say so,
        // so the caller falls back to leaving the text on the clipboard.
        guard AXIsProcessTrusted() else {
            return FlutterError(code: "ACCESSIBILITY_NOT_TRUSTED", message: "Accessibility permission missing", details: nil)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return FlutterError(code: "PASTE_FAILED", message: "CGEvent creation failed", details: nil)
        }
        // Explicit flags: modifiers the user still holds (⌥ of ⌥Space) must
        // not turn this into ⌥⌘V.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
