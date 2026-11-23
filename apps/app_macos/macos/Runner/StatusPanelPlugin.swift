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

    /// Pastel green of the app, reserved for "live": the recording dot only.
    private static let live = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xA8 / 255, green: 0xE6 / 255, blue: 0xBC / 255, alpha: 1)
            : NSColor(srgbRed: 0x2F / 255, green: 0x7D / 255, blue: 0x4F / 255, alpha: 1)
    }

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
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/status_panel",
            binaryMessenger: registrar.messenger
        )
        let instance = StatusPanelPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        // Dart may not listen yet: it also sends a first snapshot itself.
        channel.invokeMethod("ready", arguments: nil)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "update":
            snapshot = call.arguments as? [String: Any] ?? [:]
            refreshStatusItem()
            if panel.isVisible { rebuildPanel() }
            result(nil)
        case "showWindow":
            closePanel()
            StatusPanelPlugin.showMainWindow()
            result(nil)
        case "terminate":
            result(nil)
            NSApp.terminate(nil)
        default:
            result(FlutterMethodNotImplemented)
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
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        panel.contentView = background
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

    private func closePanel() {
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
        stack.spacing = 10
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
        for view in stack.arrangedSubviews where view is NSBox {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * StatusPanelPlugin.padding)
                .isActive = true
        }
        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: StatusPanelPlugin.width, height: stack.fittingSize.height)
        panel.setFrame(frameUnderItem(size: size), display: true)
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
            views.append(label(status == "paused" ? "\(L.paused) · \(clock)" : clock, secondary: true))
            views.append(row([
                button(L.stop, "stop"),
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
            views.append(row([button(L.start, "start")]))
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
        views.append(row([button(L.start, "acceptSuggestion"), button(L.ignore, "dismissSuggestion")]))
        return views
    }

    // MARK: - Views

    private func label(_ text: String, bold: Bool = false, secondary: Bool = false, small: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        let size: CGFloat = small ? 11 : 13
        field.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.preferredMaxLayoutWidth = StatusPanelPlugin.width - 2 * StatusPanelPlugin.padding
        field.isSelectable = false
        return field
    }

    private func button(_ title: String, _ method: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(tap(_:)))
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 12)
        b.identifier = NSUserInterfaceItemIdentifier(method)
        return b
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

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
