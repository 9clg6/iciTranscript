import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
