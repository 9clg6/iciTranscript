import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register IciTranscript native plugins
    AudioCapturePlugin.register(with: flutterViewController.registrar(forPlugin: "AudioCapturePlugin"))
    KeychainPlugin.register(with: flutterViewController.registrar(forPlugin: "KeychainPlugin"))
    DocumentTextPlugin.register(with: flutterViewController.registrar(forPlugin: "DocumentTextPlugin"))
    FilePickerPlugin.register(with: flutterViewController.registrar(forPlugin: "FilePickerPlugin"))
    CalendarPlugin.register(with: flutterViewController.registrar(forPlugin: "CalendarPlugin"))
    MeetingDetectionPlugin.register(with: flutterViewController.registrar(forPlugin: "MeetingDetectionPlugin"))
    GlobalShortcutPlugin.register(with: flutterViewController.registrar(forPlugin: "GlobalShortcutPlugin"))
    TextOutputPlugin.register(with: flutterViewController.registrar(forPlugin: "TextOutputPlugin"))
    StatusPanelPlugin.register(with: flutterViewController.registrar(forPlugin: "StatusPanelPlugin"))

    // Flutter leaves the window delegate unset (checked 2026-11-23).
    delegate = self
    super.awakeFromNib()
  }

  /// Close button and Cmd+W only hide the window: the app stays in the menu
  /// bar and the Dock, a recording goes on. Quitting does not go through here
  /// (windowShouldClose(_:) doc). The close button does not call
  /// performClose(_:), hence the delegate.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    orderOut(nil)
    return false
  }
}
