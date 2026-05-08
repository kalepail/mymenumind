import Foundation
import Security

struct MymindCredentials: Codable {
    var keyID: String
    var secret: String
}

enum KeychainCredentialsStoreError: LocalizedError {
    case encodingFailed
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode mymind credentials for Keychain storage."
        case .unhandledStatus(let status):
            return "Could not update macOS Keychain credentials. OSStatus \(status)."
        }
    }
}

enum KeychainCredentialsStore {
    private static let service = "com.mymenumind.api-credentials"
    private static let account = "mymind"

    static func load() -> MymindCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(MymindCredentials.self, from: data) else {
            return MymindCredentials(keyID: "", secret: "")
        }

        return credentials
    }

    static func save(_ credentials: MymindCredentials) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if credentials.keyID.isEmpty && credentials.secret.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainCredentialsStoreError.unhandledStatus(status)
            }
            return
        }

        guard let data = try? JSONEncoder().encode(credentials) else {
            throw KeychainCredentialsStoreError.encodingFailed
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialsStoreError.unhandledStatus(updateStatus)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialsStoreError.unhandledStatus(addStatus)
        }
    }
}
