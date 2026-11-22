// Apple docs consulted (2026-11-22):
// - NSOpenPanel — allowsMultipleSelection, canChooseFiles, canChooseDirectories:
//   https://developer.apple.com/documentation/appkit/nsopenpanel
// - NSSavePanel.allowedContentTypes ([UTType]) — macOS 11.0+:
//   https://developer.apple.com/documentation/appkit/nssavepanel/allowedcontenttypes
// - NSSavePanel.allowedFileTypes — macOS 10.3+, deprecated in macOS 12.0
//   ("Use -allowedContentTypes instead"); kept as the fallback because the
//   deployment target is macOS 10.15:
//   https://developer.apple.com/documentation/appkit/nssavepanel/allowedfiletypes
// - NSSavePanel.beginSheetModal(for:completionHandler:) — sheet on a window:
//   https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)
import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// Flutter plugin showing the native open panel.
///
/// Channel `com.icitranscript/file_picker`:
/// - `pickFiles` {extensions: [String]} -> [String] absolute paths, nil when
///   the user cancels. Multiple selection, files only, filtered by extension,
///   shown as a sheet on the main window (a free panel if there is none).
class FilePickerPlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/file_picker",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(FilePickerPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "pickFiles" else {
            result(FlutterMethodNotImplemented)
            return
        }
        let extensions = ((call.arguments as? [String: Any])?["extensions"] as? [String]) ?? []

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if !extensions.isEmpty {
            if #available(macOS 11.0, *) {
                panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
            } else {
                panel.allowedFileTypes = extensions
            }
        }

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else {
                result(nil)
                return
            }
            result(panel.urls.map { $0.path })
        }
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
