// Apple docs consulted (2026-11-22):
// - PDFDocument.init(url:) — returns nil when the file cannot be opened as a PDF:
//   https://developer.apple.com/documentation/pdfkit/pdfdocument/init(url:)
// - PDFDocument.string — "textual content of the entire document", pages
//   delimited with linefeeds; optional (nil when there is no text), macOS 10.4+:
//   https://developer.apple.com/documentation/pdfkit/pdfdocument/string
// - PDFDocument.isLocked — only encrypted documents can be locked; an empty
//   password is tried automatically, macOS 10.4+:
//   https://developer.apple.com/documentation/pdfkit/pdfdocument/islocked
import FlutterMacOS
import Foundation
import PDFKit

/// Flutter plugin extracting the text of a PDF with PDFKit.
///
/// Channel `com.icitranscript/document_text`:
/// - `extractText` {path} -> String (empty when the PDF has no text layer)
/// Unreadable, damaged or password-protected files -> FlutterError "unreadable".
/// Work runs off the main thread; the reply is sent on the main thread.
class DocumentTextPlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/document_text",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(DocumentTextPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "extractText" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "Missing path", details: nil))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = DocumentTextPlugin.extract(path)
            DispatchQueue.main.async { result(reply) }
        }
    }

    private static func extract(_ path: String) -> Any {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return FlutterError(code: "unreadable", message: "Not a readable PDF", details: nil)
        }
        if document.isLocked {
            return FlutterError(code: "unreadable", message: "Password-protected PDF", details: nil)
        }
        return document.string ?? ""
    }
}
