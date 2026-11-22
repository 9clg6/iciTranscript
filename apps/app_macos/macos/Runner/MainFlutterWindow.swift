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
    ProcessManagerPlugin.register(with: flutterViewController.registrar(forPlugin: "ProcessManagerPlugin"))
    KeychainPlugin.register(with: flutterViewController.registrar(forPlugin: "KeychainPlugin"))

    super.awakeFromNib()
  }
}
