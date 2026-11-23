import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS
import Foundation

/// Flutter plugin for the dictation push-to-talk shortcut (T2).
///
/// Channel `com.icitranscript/global_shortcut`:
/// - `register` {keyCode, modifiers} (Carbon virtual key code and modifier
///   mask) -> nil; replaces the previous shortcut; FlutterError
///   `SHORTCUT_UNAVAILABLE` when Carbon refuses it.
/// - `registerModifiers` {modifiers} (Carbon mask, at least two modifiers)
///   -> nil: a modifier-only shortcut (⌥⌘), which Carbon cannot register.
///   Watched with NSEvent global + local monitors, which only see key events
///   when the app is trusted for Accessibility: FlutterError
///   `ACCESSIBILITY_REQUIRED` otherwise (never a silently dead shortcut).
///   Replaces the previous shortcut, keyed or not.
/// - `unregister` -> nil (also disarms Escape and removes the monitors).
/// - `keyLabel` {keyCode} -> String?: characters the key types in the
///   current keyboard layout, without modifiers (AZERTY: 13 -> "Z"); nil when
///   it cannot be translated.
/// - `setCancelKeyEnabled` {enabled} -> nil: Escape is a hotkey only while
///   a dictation runs, so it keeps working in other apps the rest of the time.
/// Event channel `com.icitranscript/global_shortcut_events`:
/// {type: pressed | released | cancel | aborted}, always on the main thread.
/// Modifier-only: `pressed` when exactly the chosen modifiers become held
/// (caps lock, fn and numeric pad flags ignored); `released` when one of
/// them goes up; `aborted` (and no `released`) when a key or a mouse button
/// goes down, or another modifier joins, while they are held: that was
/// another app's shortcut (⌘⌥Esc, ⌘⌥-drag in Finder).
/// NSEvent monitors (Apple documentation):
/// - https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
///   (events of other apps only; key events require Accessibility)
/// - https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)
///   (this app's own events; returning the event leaves it unchanged)
/// - https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.struct/deviceindependentflagsmask
///
/// Carbon hotkeys fire while another app is frontmost and need no
/// Accessibility permission. Apple's Carbon reference pages are no longer
/// online (developer.apple.com/documentation/carbon/... returns 404), so the
/// signatures and semantics below come from the SDK headers:
/// - HIToolbox CarbonEvents.h: RegisterEventHotKey, UnregisterEventHotKey,
///   kEventHotKeyExclusive, kEventHotKeyPressed / kEventHotKeyReleased
///   (direct object = typeEventHotKeyID), GetApplicationEventTarget.
/// - HIToolbox CarbonEventsCore.h: InstallEventHandler, RemoveEventHandler,
///   GetEventParameter, eventHotKeyExistsErr.
/// - HIToolbox Events.h: kVK_Escape, LMGetKbdType.
/// - HIToolbox TextInputSources.h: TISCopyCurrentKeyboardLayoutInputSource
///   (layout used even under an input method), kTISPropertyUnicodeKeyLayoutData
///   ('uchr' CFData, NULL for KCHR-only layouts).
/// - https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate
///
/// Limit: Carbon only reports a conflict (eventHotKeyExistsErr) against
/// another process that also registered the same combination with
/// kEventHotKeyExclusive. A non-exclusive registrant or a system shortcut
/// is NOT detected: registration then succeeds and both may fire.
class GlobalShortcutPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let signature: OSType = 0x4F41_5453 // 'OATS'
    private static let mainId: UInt32 = 1
    private static let cancelId: UInt32 = 2

    private var mainRef: EventHotKeyRef?
    /// Escape with every subset of the shortcut's modifiers (alone included):
    /// Carbon matches the mask exactly, and the user may still hold all or
    /// part of ⌃⌥ of ⌃⌥Space when cancelling (at most 16 hotkeys).
    private var cancelRefs: [EventHotKeyRef] = []
    private var mainModifiers: UInt32 = 0

    // Modifier-only shortcut (NSEvent monitors).
    private var chordMask: NSEvent.ModifierFlags?
    private var monitors: [Any] = []
    private var chordDown = false
    private var chordAborted = false
    // A key went down while modifiers were held: no `pressed` until every
    // modifier is up (releasing ⇧ of ⌘⌥⇧4 must not start a dictation).
    private var chordTainted = false
    private var lastFlags: NSEvent.ModifierFlags = []
    private static let chordFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private var handlerRef: EventHandlerRef?
    private var sink: FlutterEventSink?
    /// Pressed seen without its release yet (guards against repeats).
    private var isDown = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = GlobalShortcutPlugin()
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/global_shortcut",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        FlutterEventChannel(
            name: "com.icitranscript/global_shortcut_events",
            binaryMessenger: registrar.messenger
        ).setStreamHandler(instance)
        instance.installHandler()
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "register":
            guard let keyCode = args?["keyCode"] as? Int,
                  let modifiers = args?["modifiers"] as? Int else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing keyCode or modifiers", details: nil))
                return
            }
            unregisterMain()
            let status = registerHotKey(
                keyCode: UInt32(keyCode), modifiers: UInt32(modifiers),
                id: Self.mainId, options: OptionBits(kEventHotKeyExclusive), ref: &mainRef
            )
            if status == noErr { mainModifiers = UInt32(modifiers) }
            result(status == noErr ? nil : FlutterError(
                code: "SHORTCUT_UNAVAILABLE",
                message: "RegisterEventHotKey failed",
                details: Int(status)
            ))
        case "registerModifiers":
            guard let modifiers = args?["modifiers"] as? Int else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing modifiers", details: nil))
                return
            }
            unregisterMain()
            guard AXIsProcessTrusted() else {
                result(FlutterError(
                    code: "ACCESSIBILITY_REQUIRED",
                    message: "Modifier-only shortcuts need Accessibility",
                    details: nil
                ))
                return
            }
            installChord(Self.flags(fromCarbon: UInt32(modifiers)))
            result(nil)
        case "keyLabel":
            guard let keyCode = args?["keyCode"] as? Int else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing keyCode", details: nil))
                return
            }
            result(Self.keyLabel(UInt16(truncatingIfNeeded: keyCode)))
        case "unregister":
            unregisterMain()
            setCancelKey(false)
            result(nil)
        case "setCancelKeyEnabled":
            guard let enabled = args?["enabled"] as? Bool else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing enabled", details: nil))
                return
            }
            let status = setCancelKey(enabled)
            result(status == noErr ? nil : FlutterError(
                code: "CANCEL_KEY_UNAVAILABLE",
                message: "RegisterEventHotKey failed for Escape",
                details: Int(status)
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        setCancelKey(false)
        return nil
    }

    // MARK: Key label

    /// Characters typed by [keyCode] alone in the current layout, uppercased
    /// like menu shortcuts; nil if not translatable or not printable.
    static func keyLabel(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return label.isEmpty ? nil : label.uppercased()
    }

    // MARK: Carbon

    private func installHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        // Non-capturing closure (C function pointer): self travels in userData.
        // The plugin lives as long as the app (the registrar keeps it).
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let plugin = Unmanaged<GlobalShortcutPlugin>.fromOpaque(userData).takeUnretainedValue()
                return plugin.handleHotKey(event)
            },
            types.count,
            &types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            NSLog("GlobalShortcutPlugin: InstallEventHandler failed (%d)", status)
        }
    }

    private func handleHotKey(_ event: EventRef) -> OSStatus {
        var hotKeyId = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyId
        )
        guard status == noErr, hotKeyId.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        switch (hotKeyId.id, pressed) {
        case (Self.mainId, true):
            guard !isDown else { break }
            isDown = true
            emit("pressed")
        case (Self.mainId, false):
            guard isDown else { break }
            isDown = false
            emit("released")
        case (Self.cancelId, true):
            emit("cancel")
        default:
            break
        }
        return noErr
    }

    private func registerHotKey(
        keyCode: UInt32, modifiers: UInt32, id: UInt32, options: OptionBits, ref: inout EventHotKeyRef?
    ) -> OSStatus {
        RegisterEventHotKey(
            keyCode, modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), options, &ref
        )
    }

    private func unregisterMain() {
        if let ref = mainRef { UnregisterEventHotKey(ref) }
        mainRef = nil
        isDown = false
        // Escape is then armed without modifiers only: ⌘⌥Esc stays a key
        // down seen by the monitors (aborted), never a cancel hotkey.
        mainModifiers = 0
        removeChord()
    }

    // MARK: Modifier-only shortcut

    private static func flags(fromCarbon mask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mask & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if mask & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if mask & UInt32(optionKey) != 0 { flags.insert(.option) }
        if mask & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    private func installChord(_ mask: NSEvent.ModifierFlags) {
        chordMask = mask
        chordDown = false
        chordAborted = false
        chordTainted = false
        lastFlags = NSEvent.modifierFlags.intersection(Self.chordFlags)
        let events: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.onChordEvent(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.onChordEvent(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeChord() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        chordMask = nil
        chordDown = false
        chordAborted = false
        chordTainted = false
    }

    private func onChordEvent(_ event: NSEvent) {
        guard let mask = chordMask else { return }
        let flags = event.modifierFlags.intersection(Self.chordFlags)
        if event.type != .flagsChanged {
            // Key or mouse button down with modifiers held: another app's
            // shortcut or gesture.
            if !flags.isEmpty { chordTainted = true }
            if chordDown && !chordAborted {
                chordAborted = true
                emit("aborted")
            }
            return
        }
        let previous = lastFlags
        lastFlags = flags
        if flags.isEmpty { chordTainted = false }
        if !chordDown {
            // Exactly the chosen modifiers, reached by adding a key (never by
            // releasing an extra one).
            if flags == mask && previous.isStrictSubset(of: mask) && !chordTainted {
                chordDown = true
                chordAborted = false
                emit("pressed")
            }
            return
        }
        if !flags.isSuperset(of: mask) {
            // One of them went up.
            chordDown = false
            if !chordAborted { emit("released") }
            chordAborted = false
            chordTainted = !flags.isEmpty && chordTainted
        } else if flags != mask && !chordAborted {
            // Another modifier joined (⌘⌥⇧…): not our shortcut.
            chordAborted = true
            chordTainted = true
            emit("aborted")
        }
    }

    @discardableResult
    private func setCancelKey(_ enabled: Bool) -> OSStatus {
        if enabled {
            guard cancelRefs.isEmpty else { return noErr }
            // Non-exclusive: Escape is only borrowed for the length of a dictation.
            for modifiers in Self.subsets(of: mainModifiers) {
                var ref: EventHotKeyRef?
                let status = registerHotKey(
                    keyCode: UInt32(kVK_Escape), modifiers: modifiers, id: Self.cancelId, options: 0, ref: &ref
                )
                guard status == noErr, let ref else {
                    setCancelKey(false)
                    return status
                }
                cancelRefs.append(ref)
            }
            return noErr
        }
        cancelRefs.forEach { UnregisterEventHotKey($0) }
        cancelRefs = []
        return noErr
    }

    /// Every subset of the bits of [mask], 0 and [mask] included.
    private static func subsets(of mask: UInt32) -> [UInt32] {
        var result: [UInt32] = [0]
        var sub = mask
        while sub != 0 {
            result.append(sub)
            sub = (sub - 1) & mask
        }
        return result
    }

    private func emit(_ type: String) {
        let send: () -> Void = { [weak self] in self?.sink?(["type": type]) }
        if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
    }

    @objc private func applicationWillTerminate() {
        unregisterMain()
        setCancelKey(false)
        if let ref = handlerRef { RemoveEventHandler(ref) }
        handlerRef = nil
    }
}
