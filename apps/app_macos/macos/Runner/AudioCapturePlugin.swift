import Cocoa
import FlutterMacOS
import AVFoundation
import ScreenCaptureKit
import AudioToolbox
import CoreAudio
import CoreGraphics

// MARK: - AudioCapturePlugin

/// Flutter plugin that captures audio from microphone (AUHAL Audio Unit) and
/// system audio output (ScreenCaptureKit, macOS 13+). Both streams are
/// delivered as PCM Int16 16 kHz mono chunked events.
class AudioCapturePlugin: NSObject, FlutterPlugin {

    // MARK: Channels

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel

    fileprivate let streamHandler = AudioStreamHandler()

    // MARK: Audio engines

    private var auHAL: AudioUnit?

    @available(macOS 13.0, *)
    private var scStream: SCStream? {
        get { _scStream as? SCStream }
        set { _scStream = newValue }
    }
    private var _scStream: Any?

    @available(macOS 13.0, *)
    private var scStreamOutput: SystemAudioOutputHandler? {
        get { _scStreamOutput as? SystemAudioOutputHandler }
        set { _scStreamOutput = newValue }
    }
    private var _scStreamOutput: Any?

    private var isCapturing = false

    // Track screen capture permission state without triggering a dialog.
    // Set to true when SCStream starts successfully, false when it fails with
    // a permission error. nil = unknown (never attempted).
    private var screenCapturePermissionGranted: Bool? = nil

    // Target format: 16 kHz, mono, PCM Int16
    private static let targetSampleRate: Double = 16000
    private static let targetChannels: AVAudioChannelCount = 1
    private static let chunkDurationMs: Int = 100
    fileprivate static let samplesPerChunk: Int = 1600 // 16000 * 0.1

    // AUHAL converter and render buffer
    private var auhalConverter: AVAudioConverter?
    private var auhalDeviceFormat: AVAudioFormat?
    private var auhalRenderBuffer: AVAudioPCMBuffer?
    // Accumulation buffer for Int16 bytes
    private var auhalAccumulatedData = Data()
    private let auhalLock = NSLock()

    // A capture generation identifies every chunk produced by one start/stop
    // cycle. Main-queue events keep the generation they were created in so a
    // delayed event cannot leak into the next transcription session.
    private let captureTelemetryLock = NSLock()
    private var captureGeneration: UInt64 = 0
    private var captureGenerationIsActive = false
    private var captureStartedAtUptime: TimeInterval = 0
    private var captureInputFrames: UInt64 = 0
    private var captureOutputFrames: UInt64 = 0
    private var captureChunkCount: UInt64 = 0

    // MARK: Plugin registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/audio_control",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.icitranscript/audio_stream",
            binaryMessenger: registrar.messenger
        )
        let instance = AudioCapturePlugin(
            methodChannel: channel,
            eventChannel: eventChannel
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance.streamHandler)
    }

    private init(methodChannel: FlutterMethodChannel, eventChannel: FlutterEventChannel) {
        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        super.init()
    }

    // MARK: Capture generation and telemetry

    @discardableResult
    private func beginCaptureGeneration() -> UInt64 {
        captureTelemetryLock.lock()
        captureGeneration &+= 1
        captureGenerationIsActive = true
        captureStartedAtUptime = ProcessInfo.processInfo.systemUptime
        captureInputFrames = 0
        captureOutputFrames = 0
        captureChunkCount = 0
        let generation = captureGeneration
        captureTelemetryLock.unlock()

        NSLog("[AudioCapturePlugin] Capture generation \(generation) started")
        return generation
    }

    private func activeCaptureGeneration() -> UInt64? {
        captureTelemetryLock.lock()
        defer { captureTelemetryLock.unlock() }
        return captureGenerationIsActive ? captureGeneration : nil
    }

    private func isCaptureGenerationActive(_ generation: UInt64) -> Bool {
        captureTelemetryLock.lock()
        defer { captureTelemetryLock.unlock() }
        return captureGenerationIsActive && captureGeneration == generation
    }

    private func recordAUHALFrames(
        generation: UInt64,
        inputFrames: UInt32,
        outputFrames: Int
    ) {
        captureTelemetryLock.lock()
        defer { captureTelemetryLock.unlock() }
        guard captureGenerationIsActive, captureGeneration == generation else { return }
        captureInputFrames &+= UInt64(inputFrames)
        captureOutputFrames &+= UInt64(outputFrames)
    }

    private func recordAUHALChunk(generation: UInt64) {
        captureTelemetryLock.lock()
        defer { captureTelemetryLock.unlock() }
        guard captureGenerationIsActive, captureGeneration == generation else { return }
        captureChunkCount &+= 1
    }

    private func finishCaptureGeneration(expectedGeneration: UInt64? = nil) {
        captureTelemetryLock.lock()
        guard captureGenerationIsActive,
              expectedGeneration == nil || expectedGeneration == captureGeneration else {
            captureTelemetryLock.unlock()
            return
        }

        let generation = captureGeneration
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - captureStartedAtUptime)
        let inputFrames = captureInputFrames
        let outputFrames = captureOutputFrames
        let chunks = captureChunkCount
        captureGenerationIsActive = false
        captureTelemetryLock.unlock()

        let inputRate = elapsed > 0 ? Double(inputFrames) / elapsed : 0
        let outputRate = elapsed > 0 ? Double(outputFrames) / elapsed : 0
        let elapsedText = String(format: "%.3f", elapsed)
        let inputRateText = String(format: "%.1f", inputRate)
        let outputRateText = String(format: "%.1f", outputRate)
        NSLog(
            "[AudioCapturePlugin] Capture generation \(generation) telemetry: " +
            "elapsed=\(elapsedText)s " +
            "inputFrames=\(inputFrames) (\(inputRateText)/s) " +
            "outputFrames=\(outputFrames) (\(outputRateText)/s) " +
            "chunks=\(chunks) chunkFrames=\(chunks * UInt64(Self.samplesPerChunk))"
        )
    }

    // MARK: FlutterPlugin – method call handling

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCapture":
            let args = call.arguments as? [String: Any] ?? [:]
            let inputDeviceId = args["inputDeviceId"] as? String
            let outputEnabled = args["outputEnabled"] as? Bool ?? false
            startCapture(inputDeviceId: inputDeviceId, outputEnabled: outputEnabled, result: result)

        case "stopCapture":
            stopCapture(result: result)

        case "listDevices":
            listDevices(result: result)

        case "isSystemAudioAvailable":
            if #available(macOS 13.0, *) {
                result(true)
            } else {
                result(false)
            }

        case "requestMicPermission":
            requestMicPermission(result: result)

        case "checkPermissions":
            checkPermissions(result: result)

        case "openSystemSettings":
            let args = call.arguments as? [String: Any] ?? [:]
            let pane = args["pane"] as? String ?? "screenRecording"
            openSystemSettings(pane: pane, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Request Mic Permission

    private func requestMicPermission(result: @escaping FlutterResult) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioCapturePlugin] requestMicPermission: current status = \(status.rawValue)")

        switch status {
        case .authorized:
            NSLog("[AudioCapturePlugin] Mic already authorized")
            result("authorized")
        case .notDetermined:
            NSLog("[AudioCapturePlugin] Requesting mic access...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    NSLog("[AudioCapturePlugin] Mic access granted: \(granted)")
                    result(granted ? "authorized" : "denied")
                }
            }
        case .denied:
            NSLog("[AudioCapturePlugin] Mic denied")
            result("denied")
        case .restricted:
            NSLog("[AudioCapturePlugin] Mic restricted")
            result("restricted")
        @unknown default:
            result("unknown")
        }
    }

    // MARK: - Check Permissions (non-intrusive)

    private func checkPermissions(result: @escaping FlutterResult) {
        let micStatus: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = "authorized"
        case .denied: micStatus = "denied"
        case .restricted: micStatus = "restricted"
        case .notDetermined: micStatus = "notDetermined"
        @unknown default: micStatus = "unknown"
        }

        // Do NOT call CGPreflightScreenCaptureAccess() here: in macOS 15 (Sequoia)
        // it triggers the TCC consent dialog when status is "notDetermined".
        // Instead, use the cached result from the last SCStream attempt.
        let screenStatus: String
        if let granted = screenCapturePermissionGranted {
            screenStatus = granted ? "authorized" : "denied"
        } else {
            // Never attempted a capture yet — report as notDetermined without prompting
            screenStatus = "notDetermined"
        }

        NSLog("[AudioCapturePlugin] checkPermissions: mic=\(micStatus) screen=\(screenStatus)")
        result(["mic": micStatus, "screenRecording": screenStatus])
    }

    // MARK: - Screen Capture Permission Detection

    /// Returns true if the error is caused by missing Screen Recording / System Audio permission.
    /// ScreenCaptureKit errors are in the SCStreamErrorDomain.
    /// Error code -3801 = SCStreamErrorNotEntitled (user hasn't granted permission).
    @available(macOS 13.0, *)
    private func isScreenCapturePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // SCStreamErrorDomain, code -3801 = SCStreamErrorNotEntitled (no permission)
        // code -3800 = SCStreamErrorAttemptToStartStreamState (already running)
        if nsError.domain == "com.apple.screencapturekit.error" {
            return nsError.code == -3801 || nsError.code == -3814
        }
        // Fallback: check the error description for permission-related keywords
        let desc = error.localizedDescription.lowercased()
        return desc.contains("permission") || desc.contains("not entitled") || desc.contains("access denied")
    }

    // MARK: - Open System Settings

    private func openSystemSettings(pane: String, result: @escaping FlutterResult) {
        let urlString: String
        switch pane {
        case "microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        result(nil)
    }

    // MARK: - Start Capture

    private func startCapture(inputDeviceId: String?, outputEnabled: Bool, result: @escaping FlutterResult) {
        guard !isCapturing else {
            result(FlutterError(code: "ALREADY_CAPTURING", message: "Audio capture is already active", details: nil))
            return
        }

        // Pre-flight: vérifier et demander la permission micro
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioCapturePlugin] Mic permission status: \(micStatus.rawValue)")

        switch micStatus {
        case .authorized:
            startCaptureWithPermissions(inputDeviceId: inputDeviceId, outputEnabled: outputEnabled, result: result)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startCaptureWithPermissions(inputDeviceId: inputDeviceId, outputEnabled: outputEnabled, result: result)
                    } else {
                        result(FlutterError(
                            code: "MIC_PERMISSION_DENIED",
                            message: "Accès au microphone refusé. Ouvrez Réglages Système > Confidentialité et sécurité > Microphone.",
                            details: nil
                        ))
                    }
                }
            }
        default:
            result(FlutterError(
                code: "MIC_PERMISSION_DENIED",
                message: "Accès au microphone refusé. Ouvrez Réglages Système > Confidentialité et sécurité > Microphone.",
                details: nil
            ))
        }
    }

    private func startCaptureWithPermissions(inputDeviceId: String?, outputEnabled: Bool, result: @escaping FlutterResult) {
        isCapturing = true
        let generation = beginCaptureGeneration()

        do {
            try startMicrophoneCapture(inputDeviceId: inputDeviceId)
        } catch {
            finishCaptureGeneration(expectedGeneration: generation)
            isCapturing = false
            result(FlutterError(code: "MIC_ERROR", message: "Impossible de démarrer le microphone: \(error.localizedDescription)", details: nil))
            return
        }

        if outputEnabled {
            if #available(macOS 13.0, *) {
                startSystemAudioCapture(captureGeneration: generation) { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        NSLog("[AudioCapturePlugin] System audio capture failed: \(error.localizedDescription)")
                        // Detect permission errors by their error code/domain
                        let isPermissionError = self.isScreenCapturePermissionError(error)
                        self.screenCapturePermissionGranted = false
                        if isPermissionError {
                            NSLog("[AudioCapturePlugin] Screen Recording denied — falling back to mic only")
                            DispatchQueue.main.async {
                                // Notifier Dart que l'audio bureau est indisponible (informatif, pas bloquant)
                                self.streamHandler.send(event: [
                                    "type": "outputUnavailable",
                                    "reason": "SCREEN_RECORDING_DENIED",
                                ])
                                result(nil) // Succès — le micro tourne déjà
                            }
                            return
                        }
                        // Autre erreur non-permission : continuer avec le micro seulement
                        NSLog("[AudioCapturePlugin] Erreur audio système non-critique, micro seul actif")
                    } else {
                        self.screenCapturePermissionGranted = true
                    }
                    DispatchQueue.main.async { result(nil) }
                }
                return
            } else {
                NSLog("[AudioCapturePlugin] System audio capture requires macOS 13+")
            }
        }

        result(nil)
    }

    // MARK: - Microphone Capture (AUHAL Audio Unit)

    private func startMicrophoneCapture(inputDeviceId: String?) throws {
        // 1. Find the HAL output component
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw NSError(domain: "AudioCapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not find HAL output audio component"])
        }

        // 2. Create an AudioUnit instance
        var audioUnit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let au = audioUnit else {
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not create AudioUnit instance (status \(status))"])
        }

        // 3. Enable input on element 1
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // element 1 = input
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not enable input IO (status \(status))"])
        }

        // 4. Disable output on element 0
        var disableIO: UInt32 = 0
        status = AudioUnitSetProperty(au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // element 0 = output
            &disableIO,
            UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not disable output IO (status \(status))"])
        }

        // 5. Set the input device
        var deviceID: AudioDeviceID
        if let inputDeviceId = inputDeviceId,
           let id = AudioDeviceID(inputDeviceId),
           getDeviceName(deviceID: id) != nil {
            // Device explicitement sélectionné par l'utilisateur
            deviceID = id
        } else {
            // Fallback : device par défaut du système (respecte le choix macOS de l'utilisateur)
            // Si le device par défaut ressemble à BlackHole/Soundflower, on tente le mic intégré.
            var defaultDevice = AudioDeviceID(0)
            var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            var propAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propAddr, 0, nil, &propSize, &defaultDevice)
            let defaultName = (getDeviceName(deviceID: defaultDevice) ?? "").lowercased()
            let isVirtual = defaultName.contains("blackhole") || defaultName.contains("soundflower")
                || defaultName.contains("loopback") || defaultName.contains("aggregate")
            if defaultDevice != 0 && !isVirtual {
                deviceID = defaultDevice
            } else if let builtIn = AudioCapturePlugin.findBuiltInMicrophone() {
                deviceID = builtIn
            } else {
                deviceID = defaultDevice
            }
        }

        status = AudioUnitSetProperty(au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not set input device (status \(status))"])
        }

        // 6. Query the device's native input format from element 1 input scope
        var deviceASBD = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1, // element 1 input scope = device native format
            &deviceASBD,
            &asbdSize)
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not get device format (status \(status))"])
        }

        // Log the device name for debugging
        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &deviceName)
        NSLog("[AudioCapturePlugin] AUHAL input device: \(deviceName) (id=\(deviceID), \(deviceASBD.mSampleRate)Hz, \(deviceASBD.mChannelsPerFrame)ch, \(deviceASBD.mBitsPerChannel)bit)")

        // 6b. Downmix to mono if device has multiple channels.
        // Setting the AUHAL output scope to 1 channel causes AudioUnitRender to deliver
        // only channel 0, avoiding AVAudioConverter 2ch→1ch failures.
        let originalChannelCount = deviceASBD.mChannelsPerFrame
        if originalChannelCount > 1 {
            NSLog("[AudioCapturePlugin] Multi-channel device (\(originalChannelCount)ch) — downmixing to mono")
            deviceASBD.mChannelsPerFrame = 1
            // For interleaved formats, update the per-frame byte count.
            // Non-interleaved formats keep mBytesPerFrame as per-channel size (unchanged).
            if deviceASBD.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 {
                deviceASBD.mBytesPerFrame = deviceASBD.mBytesPerFrame / originalChannelCount
                deviceASBD.mBytesPerPacket = deviceASBD.mBytesPerPacket / originalChannelCount
            }
        }

        // 7. Mirror the format on element 1 output scope
        status = AudioUnitSetProperty(au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1, // element 1 output scope = what we read from render callback
            &deviceASBD,
            asbdSize)
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not set output format on element 1 (status \(status))"])
        }

        // Re-read the format actually negotiated by AUHAL. Continuity/Bluetooth
        // devices may negotiate a different client format than the requested
        // ASBD; building the converter from the stale request produces the
        // wrong number of output samples and an ever-growing transcription lag.
        var negotiatedASBD = AudioStreamBasicDescription()
        var negotiatedSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &negotiatedASBD,
            &negotiatedSize)
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not get negotiated input format (status \(status))"])
        }

        // Create AVAudioFormat from the negotiated AUHAL client ASBD.
        guard let deviceFormat = AVAudioFormat(streamDescription: &negotiatedASBD) else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create AVAudioFormat from negotiated ASBD"])
        }

        // Create output format: PCM Int16, 16kHz, mono
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.targetSampleRate, channels: 1, interleaved: true) else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create target AVAudioFormat"])
        }

        // Create converter
        guard let converter = AVAudioConverter(from: deviceFormat, to: outputFormat) else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create AVAudioConverter"])
        }
        converter.primeMethod = .none

        self.auhalConverter = converter
        self.auhalDeviceFormat = deviceFormat

        // Core Audio may change the maximum slice size after route/sleep events.
        // Query the unit instead of rendering `inNumberFrames` into a fixed
        // 4096-frame buffer.
        var maximumFramesPerSlice: UInt32 = 0
        var maximumFramesSize = UInt32(MemoryLayout<UInt32>.size)
        let maximumFramesStatus = AudioUnitGetProperty(au,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFramesPerSlice,
            &maximumFramesSize)
        if maximumFramesStatus != noErr || maximumFramesPerSlice == 0 {
            maximumFramesPerSlice = 4096
        }
        let renderFrameCount = AVAudioFrameCount(Swift.max(maximumFramesPerSlice, 4096))
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: deviceFormat, frameCapacity: renderFrameCount) else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create render buffer"])
        }
        self.auhalRenderBuffer = renderBuffer

        // 8. Register input callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: auhalInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(au,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not set input callback (status \(status))"])
        }

        // Initialize and start
        status = AudioUnitInitialize(au)
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not initialize AudioUnit (status \(status))"])
        }

        status = AudioOutputUnitStart(au)
        guard status == noErr else {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            throw NSError(domain: "AudioCapturePlugin", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not start AudioUnit (status \(status))"])
        }

        self.auHAL = au
        NSLog("[AudioCapturePlugin] AUHAL microphone capture started (negotiated: \(negotiatedASBD.mSampleRate) Hz, maxSlice=\(maximumFramesPerSlice))")
    }

    // MARK: - AUHAL Render Callback

    /// Called by Core Audio when input data is available.
    fileprivate func handleAUHALInput(
        inRefCon: UnsafeMutableRawPointer,
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) {
        guard let generation = activeCaptureGeneration(),
              let au = auHAL,
              let renderBuffer = auhalRenderBuffer,
              let converter = auhalConverter,
              let deviceFormat = auhalDeviceFormat else { return }

        // Never ask AudioUnitRender to fill more frames than the AudioBufferList
        // can describe. The previous min()+render(larger count) was unsafe.
        guard inNumberFrames <= renderBuffer.frameCapacity else {
            NSLog("[AudioCapturePlugin] Dropping oversized AUHAL slice: \(inNumberFrames) > \(renderBuffer.frameCapacity)")
            return
        }
        renderBuffer.frameLength = AVAudioFrameCount(inNumberFrames)

        // Render audio from the device
        let status = AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, renderBuffer.mutableAudioBufferList)
        guard status == noErr else { return }

        // Convert to PCM Int16 16kHz mono
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(inNumberFrames) * Self.targetSampleRate / deviceFormat.sampleRate)
        ) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outputFrameCapacity) else { return }

        var error: NSError?
        // Feed the rendered buffer EXACTLY ONCE. AVAudioConverter calls the
        // input block repeatedly while doing sample-rate conversion; returning
        // the same buffer with .haveData every time makes it reprocess the same
        // audio (producing ~3x duplicated/overlapping output at 48k->16k),
        // which garbles the transcription. Signal .noDataNow after one feed.
        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return renderBuffer
        }

        let conversionStatus = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        guard conversionStatus != .error else { return }

        // Extract Int16 bytes from the output buffer
        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0 else { return }

        let audioBufferList = outputBuffer.audioBufferList
        let bufferPointer = audioBufferList.pointee.mBuffers
        let availableByteCount = Int(bufferPointer.mDataByteSize)
        let bytesPerFrame = Int(converter.outputFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = frameCount * bytesPerFrame
        guard let dataPtr = bufferPointer.mData,
              byteCount > 0,
              byteCount <= availableByteCount else { return }

        recordAUHALFrames(
            generation: generation,
            inputFrames: inNumberFrames,
            outputFrames: frameCount
        )

        let int16Data = Data(bytes: dataPtr, count: byteCount)

        // Accumulate and send in chunks of 3200 bytes (1600 samples * 2 bytes per Int16)
        let chunkByteSize = Self.samplesPerChunk * 2
        auhalLock.lock()
        auhalAccumulatedData.append(int16Data)

        while auhalAccumulatedData.count >= chunkByteSize {
            let chunkData = auhalAccumulatedData.prefix(chunkByteSize)
            auhalAccumulatedData.removeFirst(chunkByteSize)
            auhalLock.unlock()

            recordAUHALChunk(generation: generation)
            sendAudioChunk(
                source: "input",
                data: Data(chunkData),
                captureGeneration: generation
            )

            auhalLock.lock()
        }
        auhalLock.unlock()
    }

    // MARK: - System Audio Capture (ScreenCaptureKit)

    @available(macOS 13.0, *)
    private func startSystemAudioCapture(
        captureGeneration: UInt64,
        completion: @escaping (Error?) -> Void
    ) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else { return }
            guard self.isCaptureGenerationActive(captureGeneration) else {
                completion(NSError(
                    domain: "AudioCapturePlugin",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Capture stopped before system audio startup completed"]
                ))
                return
            }

            if let error = error {
                completion(error)
                return
            }

            guard let content = content else {
                completion(NSError(domain: "AudioCapturePlugin", code: -2,
                                   userInfo: [NSLocalizedDescriptionKey: "No shareable content available"]))
                return
            }

            // We need at least one display to create a filter
            guard let display = content.displays.first else {
                completion(NSError(domain: "AudioCapturePlugin", code: -3,
                                   userInfo: [NSLocalizedDescriptionKey: "No display found"]))
                return
            }

            // Filter: capture the display but we only care about audio
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Int(Self.targetSampleRate)
            config.channelCount = Int(Self.targetChannels)

            // Minimize video overhead – we only want audio
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

            let outputHandler = SystemAudioOutputHandler(
                plugin: self,
                captureGeneration: captureGeneration
            )
            self._scStreamOutput = outputHandler

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            do {
                try stream.addStreamOutput(outputHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

                stream.startCapture { captureError in
                    if let captureError = captureError {
                        completion(captureError)
                    } else {
                        NSLog("[AudioCapturePlugin] System audio capture started")
                        completion(nil)
                    }
                }

                self._scStream = stream
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - Stop Capture

    private func stopCapture(result: @escaping FlutterResult) {
        stopAllCapture()
        result(nil)
    }

    private func stopAllCapture() {
        // Invalidate queued main-thread events before stopping native capture.
        // The summary is emitted once for the generation, never per callback.
        finishCaptureGeneration()

        // Stop AUHAL microphone
        if let au = auHAL {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            self.auHAL = nil
            NSLog("[AudioCapturePlugin] AUHAL microphone capture stopped")
        }
        auhalConverter = nil
        auhalDeviceFormat = nil
        auhalRenderBuffer = nil
        auhalLock.lock()
        auhalAccumulatedData.removeAll()
        auhalLock.unlock()

        // Stop system audio
        if #available(macOS 13.0, *) {
            if let stream = scStream {
                stream.stopCapture { error in
                    if let error = error {
                        NSLog("[AudioCapturePlugin] Error stopping system audio: \(error)")
                    } else {
                        NSLog("[AudioCapturePlugin] System audio capture stopped")
                    }
                }
                _scStream = nil
                _scStreamOutput = nil
            }
        }

        isCapturing = false
    }

    // MARK: - List Devices

    private func listDevices(result: @escaping FlutterResult) {
        var devices: [[String: Any]] = []

        // Use Core Audio to enumerate devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else {
            result(devices)
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            result(devices)
            return
        }

        for deviceID in deviceIDs {
            let name = getDeviceName(deviceID: deviceID) ?? "Unknown"
            let inputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)

            if inputChannels > 0 {
                devices.append([
                    "id": String(deviceID),
                    "name": name,
                    "isInput": true,
                ])
            }
            if outputChannels > 0 {
                devices.append([
                    "id": String(deviceID),
                    "name": name,
                    "isInput": false,
                ])
            }
        }

        result(devices)
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        return status == noErr ? name as String : nil
    }

    private func getChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard getStatus == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var channels = 0
        for buffer in bufferList {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    // MARK: - Find Built-In Microphone

    /// Finds the built-in microphone device, avoiding BlackHole and other virtual devices.
    private static func findBuiltInMicrophone() -> AudioDeviceID? {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr, 0, nil, &dataSize
        ) == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr, 0, nil, &dataSize, &devices
        ) == noErr else { return nil }

        for device in devices {
            // Check if device has input streams
            var inputStreamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &inputStreamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            // Get device name
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(device, &nameAddr, 0, nil, &nameSize, &name)
            let deviceName = name as String

            NSLog("[AudioCapturePlugin] Found input device: \(deviceName) (id=\(device))")

            // Skip BlackHole and other virtual devices
            let lowerName = deviceName.lowercased()
            if lowerName.contains("blackhole") || lowerName.contains("soundflower") || lowerName.contains("loopback") {
                continue
            }

            // Prefer "MacBook Pro" mic specifically (not external/Continuity mics)
            if lowerName.contains("macbook") || lowerName.contains("built-in") {
                NSLog("[AudioCapturePlugin] Selected built-in microphone: \(deviceName) (id=\(device))")
                return device
            }
        }

        // If no built-in mic found, return first non-virtual input device
        for device in devices {
            var inputStreamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &inputStreamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(device, &nameAddr, 0, nil, &nameSize, &name)
            let deviceName = (name as String).lowercased()

            if !deviceName.contains("blackhole") && !deviceName.contains("soundflower") {
                NSLog("[AudioCapturePlugin] Selected fallback input device: \(name) (id=\(device))")
                return device
            }
        }

        return nil
    }

    // MARK: - Send Audio Chunk (PCM Int16 Data)

    fileprivate static var logCount = 0

    fileprivate func sendAudioChunk(
        source: String,
        data: Data,
        captureGeneration suppliedGeneration: UInt64? = nil
    ) {
        guard let generation = suppliedGeneration ?? activeCaptureGeneration(),
              isCaptureGenerationActive(generation) else { return }

        // Debug: log max sample amplitude
        AudioCapturePlugin.logCount += 1
        if AudioCapturePlugin.logCount <= 5 || AudioCapturePlugin.logCount % 200 == 0 {
            // Read Int16 samples to find max amplitude
            var maxAbs: Int16 = 0
            data.withUnsafeBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for sample in int16Buffer {
                    let abs = sample == Int16.min ? Int16.max : Swift.abs(sample)
                    if abs > maxAbs { maxAbs = abs }
                }
            }
            NSLog("[AudioCapturePlugin] sendChunk #\(AudioCapturePlugin.logCount) source=\(source) bytes=\(data.count) maxAbs=\(maxAbs)")
        }

        let event: [String: Any] = [
            "source": source,
            "data": FlutterStandardTypedData(bytes: data),
            "timestampMs": Int64(Date().timeIntervalSince1970 * 1000),
        ]

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isCaptureGenerationActive(generation) else { return }
            self.streamHandler.send(event: event)
        }
    }
}

// MARK: - AUHAL C Callback

private func auhalInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let plugin = Unmanaged<AudioCapturePlugin>.fromOpaque(inRefCon).takeUnretainedValue()
    plugin.handleAUHALInput(
        inRefCon: inRefCon,
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inBusNumber: inBusNumber,
        inNumberFrames: inNumberFrames
    )
    return noErr
}

// MARK: - SystemAudioOutputHandler (ScreenCaptureKit delegate)

@available(macOS 13.0, *)
private class SystemAudioOutputHandler: NSObject, SCStreamOutput {

    private weak var plugin: AudioCapturePlugin?
    private let captureGeneration: UInt64

    private var accumulatedData = Data()
    private let lock = NSLock()

    init(plugin: AudioCapturePlugin, captureGeneration: UInt64) {
        self.plugin = plugin
        self.captureGeneration = captureGeneration
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }

        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc!)

        // System audio from ScreenCaptureKit is Float32 — convert to Int16
        let floatCount: Int
        if let asbd = asbd, asbd.pointee.mBitsPerChannel > 0 {
            floatCount = totalLength / Int(asbd.pointee.mBitsPerChannel / 8)
        } else {
            floatCount = totalLength / MemoryLayout<Float>.size
        }

        let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
        let samples = UnsafeBufferPointer(start: floatPointer, count: floatCount)

        // Convert Float32 samples to Int16 Data
        var int16Data = Data(count: floatCount * 2)
        int16Data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<floatCount {
                let clamped = max(-1.0, min(1.0, samples[i]))
                int16Buffer[i] = Int16(clamped * 32767.0)
            }
        }

        // Accumulate and send in chunks of 3200 bytes (1600 samples * 2 bytes)
        let chunkByteSize = AudioCapturePlugin.samplesPerChunk * 2
        lock.lock()
        accumulatedData.append(int16Data)

        while accumulatedData.count >= chunkByteSize {
            let chunkData = accumulatedData.prefix(chunkByteSize)
            accumulatedData.removeFirst(chunkByteSize)
            lock.unlock()

            plugin?.sendAudioChunk(
                source: "output",
                data: Data(chunkData),
                captureGeneration: captureGeneration
            )

            lock.lock()
        }
        lock.unlock()
    }
}

// MARK: - AudioStreamHandler (EventChannel)

private class AudioStreamHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    func send(event: [String: Any]) {
        eventSink?(event)
    }
}
