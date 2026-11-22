import Carbon
import FlutterMacOS
import Foundation

/// Flutter plugin for the dictation push-to-talk shortcut (T2).
///
/// Channel `com.icitranscript/global_shortcut`:
/// - `register` {keyCode, modifiers} (Carbon virtual key code and modifier
///   mask) -> nil; replaces the previous shortcut; FlutterError
///   `SHORTCUT_UNAVAILABLE` when Carbon refuses it.
/// - `unregister` -> nil (also disarms Escape).
/// - `setCancelKeyEnabled` {enabled} -> nil: Escape is a hotkey only while
///   a dictation runs, so it keeps working in other apps the rest of the time.
/// Event channel `com.icitranscript/global_shortcut_events`:
/// {type: pressed | released | cancel}, always on the main thread.
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
/// - HIToolbox Events.h: kVK_Escape.
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
