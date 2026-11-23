import AppKit
import FlutterMacOS
import Foundation

// Apple documentation (read 2026-11-23):
// - https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:)
//   (the status bar does not retain the item: keep a strong reference)
// - https://developer.apple.com/documentation/appkit/nsstatusitem/button (macOS 10.10+)
// - https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
//   ("a panel ... that does not activate the owning app"; SDK header NSWindow.h: NSPanel only)
// - https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate
//   (default true for NSPanel: set to false, Oats is usually inactive when the panel opens)
// - https://developer.apple.com/documentation/appkit/nswindow/canbecomekey
//   (false without `titled`: overridden so the panel gets Escape)
// - https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
//   (mouse-down monitoring needs no accessibility trust; never called for our own events)
// - https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)
// - https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:)
// - https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)
// - https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:)
//   (after terminateLater, the app must reply)
// - https://developer.apple.com/documentation/appkit/nsworkspace/willpoweroffnotification
// - https://developer.apple.com/documentation/foundation/processinfo/beginactivity(options:reason:)
// - https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:)
//   ("not called when a user quits an application")
// SF Symbols need macOS 11: below, plain drawn shapes.

/// Menu bar item and its panel: see that a note records, start or stop it,
/// the last lines, the live question and the meeting suggestion, without
/// bringing the main window forward. AppKit views only; everything shown
/// comes from the last `update` snapshot sent by Dart.
///
/// Channel `com.icitranscript/status_panel` (contract: top of
/// test/features/status_panel/status_panel_snapshot_test.dart):
/// - Dart -> Swift: `update` {snapshot}, `showWindow`, `terminate`
/// - Swift -> Dart: `ready`, `start`, `stop`, `pauseResume`, `skipFinalising`,
///   `acceptSuggestion`, `dismissSuggestion`, `answerNow` {questionId}, `openWindow`, `quit`
/// Nothing is logged: titles, lines and answers stay on this Mac.
class StatusPanelPlugin: NSObject, FlutterPlugin, NSWindowDelegate {

    /// Button labels and fixed texts, French, in one place.
    private enum L {
        static let start = "Démarrer la note"
        static let stop = "Arrêter"
        static let pause = "Pause"
        static let resume = "Reprendre"
        static let skip = "Passer"
        static let idle = "Aucune note en cours"
        static let untitled = "Note sans titre"
        static let paused = "En pause"
        static let finalising = "Finalisation… %d s"
        static let dictating = "Dictée en cours"
        static let answer = "Répondre"
        static let ignore = "Ignorer"
        static let open = "Ouvrir Oats"
        static let quit = "Quitter"
        static let truncated = "Réponse raccourcie"
        static let sources = "Sources : "
        static let questionStates: [String: String] = [
            "detected": "Question détectée",
            "answering": "Réponse en cours…",
            "answered": "Réponse proposée",
            "declined": "Pas de réponse utile",
            "failed": "La réponse a échoué",
            "needsModel": "Aucun modèle prêt",
        ]
    }

    private static let width: CGFloat = 340
    private static let padding: CGFloat = 14

    /// Green of the app, reserved for "live": the recording dot only.
    fileprivate static let live = PanelColor.accent

    private let channel: FlutterMethodChannel
    private let statusItem: NSStatusItem
    private lazy var panel: StatusPanelWindow = makePanel()
    private var snapshot: [String: Any] = [:]
    private var clickMonitor: Any?
    private var closedAt = Date.distantPast

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
        }
        refreshStatusItem()
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.poweringOff = true }
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/status_panel",
            binaryMessenger: registrar.messenger
        )
        let instance = StatusPanelPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        shared = instance
        // Dart may not listen yet: it also sends a first snapshot itself.
        channel.invokeMethod("ready", arguments: nil)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "update":
            snapshot = call.arguments as? [String: Any] ?? [:]
            refreshStatusItem()
            holdActivityWhileRecording()
            if panel.isVisible { rebuildPanel() }
            result(nil)
        case "suggest":
            showSuggestion(call.arguments as? [String: Any] ?? [:])
            result(nil)
        case "showWindow":
            closePanel()
            StatusPanelPlugin.showMainWindow()
            result(nil)
        case "terminate":
            result(nil)
            finishQuit()
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// The live plugin, for AppDelegate's quit routing; nil before the
    /// Flutter view registers it.
    private(set) static weak var shared: StatusPanelPlugin?

    /// Native safety bound, a little above Dart's 30 s: the app can never
    /// refuse to quit.
    private static let quitTimeout: TimeInterval = 35
    private var quitPending = false
    private var awaitingReply = false
    private var dartQuitDone = false
    private var poweringOff = false
    private var powerOffObserver: NSObjectProtocol?

    /// Every way of quitting (Cmd+Q, app menu, Dock, logout) goes through
    /// Dart `quit` (note saved, owned servers stopped), which answers with
    /// `terminate`; then the app quits for real.
    ///
    /// Cmd+Q: `.terminateCancel`, then `NSApp.terminate` again once Dart is
    /// done (as FlutterAppDelegate does). `.terminateLater` would run the
    /// loop in NSModalPanelRunLoopMode, where Flutter messages still flow
    /// (FlutterRunLoop schedules in common modes) but blocks sent with
    /// `DispatchQueue.main.async` do not (checked 2026-11-23 with a swiftc
    /// script) — and AudioCapturePlugin answers through the main queue, so
    /// stopping the note could stall. Logout/restart/shutdown: cancelling
    /// would abort them, so `.terminateLater` there, bounded by the same
    /// timer, which is added in common modes so it fires in modal mode.
    func shouldTerminate() -> NSApplication.TerminateReply {
        if dartQuitDone { return .terminateNow }
        if !quitPending {
            quitPending = true
            closePanel()
            channel.invokeMethod("quit", arguments: nil) { [weak self] reply in
                // No Dart handler or a Dart error: do not wait for `terminate`.
                if reply is FlutterError || (reply as? NSObject) === FlutterMethodNotImplemented {
                    self?.finishQuit()
                }
            }
            let timer = Timer(timeInterval: StatusPanelPlugin.quitTimeout, repeats: false) { [weak self] _ in
                self?.finishQuit()
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        if poweringOff || systemQuit() {
            awaitingReply = true
            return .terminateLater
        }
        return .terminateCancel
    }

    /// Logout, restart or shutdown: the quit Apple event carries a reason
    /// (keyAEQuitReason); Cmd+Q sends no Apple event, Dock › Quit no reason.
    /// willPowerOffNotification covers the same case if it arrives first.
    private func systemQuit() -> Bool {
        let quitReason = AEKeyword(0x7768_793F)  // keyAEQuitReason, 'why?'
        return NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: quitReason) != nil
    }

    /// Dart is done (or the bound passed): quit for real.
    private func finishQuit() {
        if dartQuitDone && !quitPending { return }
        quitPending = false
        dartQuitDone = true
        if awaitingReply {
            awaitingReply = false
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: - App Nap

    private var activity: NSObjectProtocol?

    /// A note in progress must not be throttled when the window is hidden.
    private func holdActivityWhileRecording() {
        let busy = status != "idle"
        if busy && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Oats records a note"
            )
        } else if !busy, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    /// Brings the main window back (closed windows are only hidden) and
    /// activates the app.
    static func showMainWindow() {
        guard let window = (NSApp.delegate as? FlutterAppDelegate)?.mainFlutterWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Snapshot reading

    private var status: String { snapshot["status"] as? String ?? "idle" }
    private var elapsed: Int { snapshot["elapsedSeconds"] as? Int ?? 0 }

    private static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Status item

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = StatusPanelPlugin.icon(for: status)
        let showsClock = status == "recording" || status == "paused"
        button.attributedTitle = NSAttributedString(
            string: showsClock ? " " + StatusPanelPlugin.clock(elapsed) : "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)]
        )
    }

    private static func icon(for status: String) -> NSImage? {
        if status == "recording" { return dot() }
        if status == "idle", let glyph = glyph() { return glyph }
        let name: String
        switch status {
        case "paused": name = "pause.circle"
        case "finalising": name = "hourglass"
        default: name = "waveform"
        }
        let image: NSImage?
        if #available(macOS 11.0, *) {
            image = NSImage(systemSymbolName: name, accessibilityDescription: "Oats")
        } else {
            image = ring()
        }
        image?.isTemplate = true
        return image
    }

    /// The logo (lowercase o on a note line), vector template from
    /// Assets.xcassets/MenuBarGlyph, 18 pt high; nil if the asset is missing.
    private static func glyph() -> NSImage? {
        guard let source = NSImage(named: "MenuBarGlyph"),
              let image = source.copy() as? NSImage,
              image.size.height > 0 else { return nil }
        let height: CGFloat = 18
        image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        image.isTemplate = true
        image.accessibilityDescription = "Oats"
        return image
    }

    /// The only colored mark of the app: a green dot while recording. The
    /// color is resolved at draw time, so it follows the menu bar appearance.
    private static func dot() -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            StatusPanelPlugin.live.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func ring() -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
    }

    // MARK: - Panel

    private func makePanel() -> StatusPanelWindow {
        let panel = StatusPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: StatusPanelPlugin.width, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.closePanel() }
        panel.contentView = PanelBackground()
        return panel
    }

    @objc private func toggle() {
        if panel.isVisible {
            closePanel()
            return
        }
        // The click that made the panel lose key focus also lands here.
        if Date().timeIntervalSince(closedAt) < 0.3 { return }
        rebuildPanel()
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.closePanel() }
        channel.invokeMethod("ready", arguments: nil)
    }

    /// Seconds a panel opened by `suggest` stays up (pointer outside).
    private static let suggestionVisible: TimeInterval = 12
    private var autoClose: Timer?

    /// A new meeting suggestion during a call in another app: show the panel
    /// without activating the app nor taking key focus; it closes by itself
    /// unless the pointer is inside. Never over a panel already open.
    private func showSuggestion(_ args: [String: Any]) {
        if panel.isVisible { return }
        // The matching `update` may still be throttled on the Dart side.
        var suggestion = args
        suggestion.removeValue(forKey: "key")
        snapshot["suggestion"] = suggestion
        snapshot["showStart"] = false
        rebuildPanel()
        panel.orderFrontRegardless()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.closePanel() }
        scheduleAutoClose(after: StatusPanelPlugin.suggestionVisible)
    }

    private func scheduleAutoClose(after seconds: TimeInterval) {
        autoClose?.invalidate()
        autoClose = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) {
                self.scheduleAutoClose(after: 3)
            } else {
                self.closePanel()
            }
        }
    }

    private func closePanel() {
        autoClose?.invalidate()
        autoClose = nil
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        clickMonitor = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        closedAt = Date()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    private func rebuildPanel() {
        guard let content = panel.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(
            top: StatusPanelPlugin.padding, left: StatusPanelPlugin.padding,
            bottom: StatusPanelPlugin.padding, right: StatusPanelPlugin.padding
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        let blocks: [[NSView]] = [
            statusBlock(),
            transcriptBlock(),
            questionBlock(),
            suggestionBlock(),
            [row([button(L.open, "openWindow"), button(L.quit, "quit")])],
        ].filter { !$0.isEmpty }  // empty blocks are hidden, not shown empty
        for (i, block) in blocks.enumerated() {
            if i > 0 { stack.addArrangedSubview(separator()) }
            block.forEach { stack.addArrangedSubview($0) }
        }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.widthAnchor.constraint(equalToConstant: StatusPanelPlugin.width),
        ])
        for view in stack.arrangedSubviews where view is Hairline {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * StatusPanelPlugin.padding)
                .isActive = true
        }
        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: StatusPanelPlugin.width, height: stack.fittingSize.height)
        panel.setFrame(frameUnderItem(size: size), display: true)
        panel.invalidateShadow()
    }

    /// Anchored under the status item, kept inside the screen.
    private func frameUnderItem(size: NSSize) -> NSRect {
        guard let itemWindow = statusItem.button?.window,
              let screen = itemWindow.screen ?? NSScreen.main else {
            return NSRect(origin: panel.frame.origin, size: size)
        }
        let item = itemWindow.frame
        let visible = screen.visibleFrame
        var x = item.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        return NSRect(x: x, y: item.minY - size.height - 4, width: size.width, height: size.height)
    }

    // MARK: - Blocks

    private func statusBlock() -> [NSView] {
        let title = snapshot["title"] as? String
        var views: [NSView] = []
        switch status {
        case "recording", "paused":
            let clock = StatusPanelPlugin.clock(elapsed)
            views.append(label(title ?? L.untitled, bold: true))
            if status == "paused" {
                views.append(label("\(L.paused) · \(clock)", secondary: true))
            } else {
                let time = row([LiveDot(), label(clock, secondary: true)])
                time.spacing = 6
                views.append(time)
            }
            views.append(row([
                button(L.stop, "stop", primary: true),
                button(status == "paused" ? L.resume : L.pause, "pauseResume"),
            ]))
        case "finalising":
            if let title = title { views.append(label(title, bold: true)) }
            let seconds = snapshot["finalisingSeconds"] as? Int ?? 0
            views.append(row([
                label(String(format: L.finalising, seconds), secondary: true),
                button(L.skip, "skipFinalising"),
            ]))
        default:
            views.append(label(L.idle, secondary: true))
            // One "Démarrer la note" only: a suggestion carries its own.
            if snapshot["showStart"] as? Bool ?? true {
                views.append(row([button(L.start, "start", primary: true)]))
            }
        }
        if snapshot["dictating"] as? Bool == true {
            views.append(label(L.dictating, secondary: true))
        }
        return views
    }

    private func transcriptBlock() -> [NSView] {
        let lines = snapshot["transcript"] as? [[String: Any]] ?? []
        return lines.map { line in
            let stack = NSStackView(views: [
                label(line["speaker"] as? String ?? "", secondary: true, small: true),
                label(line["text"] as? String ?? ""),
            ])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            return stack
        }
    }

    private func questionBlock() -> [NSView] {
        guard let q = snapshot["question"] as? [String: Any] else { return [] }
        let state = q["state"] as? String ?? ""
        var views: [NSView] = [
            label(q["text"] as? String ?? "", bold: true),
            label(L.questionStates[state] ?? "", secondary: true, small: true),
        ]
        if let answer = q["answer"] as? String, !answer.isEmpty {
            views.append(label(answer))
        }
        if q["truncated"] as? Bool == true {
            views.append(label(L.truncated, secondary: true, small: true))
        }
        if let sources = q["sources"] as? [String], !sources.isEmpty {
            views.append(label(L.sources + sources.joined(separator: ", "), secondary: true, small: true))
        }
        // `detected` = an answer can be asked for (local model, on demand).
        if state == "detected", let id = q["id"] as? String {
            let answerButton = button(L.answer, "answerNow")
            answerButton.identifier = NSUserInterfaceItemIdentifier("answerNow:" + id)
            views.append(row([answerButton]))
        }
        return views
    }

    private func suggestionBlock() -> [NSView] {
        guard let s = snapshot["suggestion"] as? [String: Any] else { return [] }
        var views: [NSView] = [label(s["title"] as? String ?? "", bold: true)]
        if let detail = s["detail"] as? String, !detail.isEmpty {
            views.append(label(detail, secondary: true))
        }
        views.append(row([
            button(L.start, "acceptSuggestion", primary: true),
            button(L.ignore, "dismissSuggestion"),
        ]))
        return views
    }

    // MARK: - Views

    private func label(_ text: String, bold: Bool = false, secondary: Bool = false, small: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        let size: CGFloat = small ? 11 : 13
        field.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        field.textColor = secondary ? PanelColor.muted : PanelColor.ink
        field.preferredMaxLayoutWidth = StatusPanelPlugin.width - 2 * StatusPanelPlugin.padding
        field.isSelectable = false
        return field
    }

    /// Small outlined button; [primary] (Démarrer la note / Arrêter) is the
    /// only filled one.
    private func button(_ title: String, _ method: String, primary: Bool = false) -> NSButton {
        let b = PanelButton(title: title, target: self, action: #selector(tap(_:)))
        b.primary = primary
        b.identifier = NSUserInterfaceItemIdentifier(method)
        return b
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func separator() -> NSView { Hairline() }

    @objc private func tap(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if id.hasPrefix("answerNow:") {
            channel.invokeMethod("answerNow", arguments: ["questionId": String(id.dropFirst("answerNow:".count))])
            return
        }
        if id == "openWindow" || id == "quit" { closePanel() }
        channel.invokeMethod(id, arguments: nil)
    }
}

/// Borderless non-activating panel that can still become key (Escape).
final class StatusPanelWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Colors of the app (packages/core_presentation/lib/theme/oats_tokens.dart),
/// resolved per appearance: white / near-black ground, no vibrancy.
private enum PanelColor {
    private static func pair(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    static let ground = pair(0xFFFFFF, 0x121212)  // background
    static let ink = pair(0x111111, 0xF2F2EF)  // ink
    static let onInk = pair(0xFFFFFF, 0x111111)  // onInk
    static let muted = pair(0x6C6E69, 0x8B8D87)  // muted
    static let line = pair(0xE8E8E6, 0x262725)  // line (hairline)
    static let hover = pair(0xF4F4F2, 0x1B1B1A)  // hover (pressed)
    static let accent = pair(0x2F7D4F, 0xA8E6BC)  // accent, "live" only
    static let border = pair(0x111111, 0xF2F2EF, alpha: 0.18)  // button outline
}

/// Panel ground: rounded 10, hairline border; the window adds the shadow.
private final class PanelBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        PanelColor.ground.setFill()
        path.fill()
        PanelColor.line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// 1 px separator between blocks.
private final class Hairline: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }

    override func draw(_ dirtyRect: NSRect) {
        PanelColor.line.setFill()
        bounds.fill()
    }
}

/// The green recording dot before the elapsed time.
private final class LiveDot: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 7, height: 7) }

    override func draw(_ dirtyRect: NSRect) {
        PanelColor.accent.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// Small button: 1 px outline, transparent fill, radius 6, 12 pt medium;
/// primary = filled with the ink color.
private final class PanelButton: NSButton {
    var primary = false

    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        setButtonType(.momentaryChange)
    }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        return NSSize(width: ceil(text.width) + 20, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        let pressed = isHighlighted
        if primary {
            (pressed ? PanelColor.muted : PanelColor.ink).setFill()
            path.fill()
        } else {
            if pressed {
                PanelColor.hover.setFill()
                path.fill()
            }
            PanelColor.border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: primary ? PanelColor.onInk : PanelColor.ink,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
