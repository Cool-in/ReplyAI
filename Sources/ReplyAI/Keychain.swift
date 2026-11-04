import Foundation
import Security
import ReplyCore

enum Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain could not complete this action (\(status))." }
    }

    private static func query(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.replyai.provider",
            kSecAttrAccount as String: provider.rawValue
        ]
    }

    static func read(_ provider: Provider) throws -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func exists(_ provider: Provider) -> Bool {
        SecItemCopyMatching(query(provider) as CFDictionary, nil) == errSecSuccess
    }

    static func save(_ key: String, for provider: Provider) throws {
        let data = [kSecValueData as String: Data(key.utf8)]
        let query = query(provider)
        let update = SecItemUpdate(query as CFDictionary, data as CFDictionary)
        if update == errSecItemNotFound {
            let add = SecItemAdd(query.merging(data) { _, new in new } as CFDictionary, nil)
            guard add == errSecSuccess else { throw Failure(status: add) }
        } else if update != errSecSuccess {
            throw Failure(status: update)
        }
    }

    static func remove(_ provider: Provider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
