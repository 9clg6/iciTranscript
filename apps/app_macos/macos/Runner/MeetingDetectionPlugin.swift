import CoreAudio
import FlutterMacOS
import Foundation

// Apple documentation (read 2026-11-22):
// - https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist
// - https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertybundleid
// - https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput
// - https://developer.apple.com/documentation/coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)
// These pages state no minimum OS version; the SDK header (CoreAudio/AudioHardware.h) gives the
// semantics: the process list is "an array of AudioObjectIDs that represent the Process objects for
// all client processes currently connected to the system", BundleID is a CFString the caller
// releases, IsRunningInput is a UInt32 (1 = running IO with at least one active input stream).
// The process objects shipped with macOS 14 (Sonoma); older systems get `start` -> false.

/// Flutter plugin telling Dart which other apps are capturing the microphone.
///
/// Channel `com.icitranscript/meeting_detection`:
/// - `start` -> Bool (false below macOS 14: nothing is watched)
/// - `stop` -> nil
/// Swift -> Dart: `micUsers` {bundleIds: [String]} after each change, this app excluded.
/// Reads process bundle ids only (no audio, no window titles, no foreground app).
class MeetingDetectionPlugin: NSObject, FlutterPlugin {

    private let channel: FlutterMethodChannel
    private var monitor: AnyObject?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/meeting_detection",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(MeetingDetectionPlugin(channel: channel), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            guard #available(macOS 14.0, *) else { return result(false) }
            if monitor == nil {
                let m = MicUsersMonitor { [weak self] ids in
                    self?.channel.invokeMethod("micUsers", arguments: ["bundleIds": ids])
                }
                m.start()
                monitor = m
            }
            result(true)
        case "stop":
            if #available(macOS 14.0, *) { (monitor as? MicUsersMonitor)?.stop() }
            monitor = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Watches the HAL process list and each process's IsRunningInput; reports the set of bundle ids
/// currently capturing input, on the main queue, only when it changes.
@available(macOS 14.0, *)
private final class MicUsersMonitor {

    private let onChange: ([String]) -> Void
    private let ownBundleId = Bundle.main.bundleIdentifier ?? ""
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listListener: AudioObjectPropertyListenerBlock?
    private var inputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var last: Set<String>?

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr {
            listListener = block
        }
        refresh()
    }

    func stop() {
        if let block = listListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, block)
        }
        listListener = nil
        for id in Array(inputListeners.keys) { unlisten(id) }
        last = nil
    }

    private func refresh() {
        let processes = processObjects()
        // Follow IsRunningInput on every process; drop the ones that left.
        for id in Array(inputListeners.keys) where !processes.contains(id) { unlisten(id) }
        for id in processes where inputListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                inputListeners[id] = block
            }
        }
        var users = Set<String>()
        for id in processes where isRunningInput(id) {
            if let bundleId = bundleId(id), !bundleId.isEmpty, bundleId != ownBundleId {
                users.insert(bundleId)
            }
        }
        guard users != last else { return }
        last = users
        onChange(users.sorted())
    }

    private func unlisten(_ id: AudioObjectID) {
        guard let block = inputListeners.removeValue(forKey: id) else { return }
        var address = Self.address(kAudioProcessPropertyIsRunningInput)
        AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
    }

    private func processObjects() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private func isRunningInput(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioProcessPropertyIsRunningInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private func bundleId(_ id: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
