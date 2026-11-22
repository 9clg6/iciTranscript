import FlutterMacOS
import Foundation
import Security

/// Flutter plugin storing LLM API keys in the macOS login keychain.
///
/// Channel `com.icitranscript/keychain`, generic password items:
/// service = bundle identifier, account = provider id.
/// - `readKey`   {provider} -> String? (nil when absent)
/// - `writeKey`  {provider, key} -> nil
/// - `deleteKey` {provider} -> nil
/// Errors carry the OSStatus only, never the key.
class KeychainPlugin: NSObject, FlutterPlugin {

    private let service = Bundle.main.bundleIdentifier ?? "com.icitranscript"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.icitranscript/keychain",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(KeychainPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let provider = args["provider"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "Missing provider", details: nil))
            return
        }
        switch call.method {
        case "readKey":
            result(reply(read(provider)))
        case "writeKey":
            guard let key = args["key"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing key", details: nil))
                return
            }
            result(reply(write(provider, key)))
        case "deleteKey":
            result(reply(delete(provider)))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Keychain

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) -> Result<String?, KeychainError> {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .success(nil) }
        guard status == errSecSuccess, let data = item as? Data else {
            return .failure(KeychainError(status: status))
        }
        return .success(String(data: data, encoding: .utf8))
    }

    private func write(_ account: String, _ key: String) -> Result<String?, KeychainError> {
        let data = Data(key.utf8)
        let query = baseQuery(account)
        var status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess ? .success(nil) : .failure(KeychainError(status: status))
    }

    private func delete(_ account: String) -> Result<String?, KeychainError> {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
            ? .success(nil) : .failure(KeychainError(status: status))
    }

    private func reply(_ outcome: Result<String?, KeychainError>) -> Any? {
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            let message = SecCopyErrorMessageString(error.status, nil) as String?
            return FlutterError(code: "errSec\(error.status)", message: message, details: nil)
        }
    }
}

private struct KeychainError: Error {
    let status: OSStatus
}
