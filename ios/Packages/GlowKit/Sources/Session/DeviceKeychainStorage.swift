import Auth
import Foundation
import os
import Security

/// Where the Supabase session is kept: the Keychain, on this phone only.
///
/// `AfterFirstUnlockThisDeviceOnly`: readable once the phone has been unlocked since it started
/// (so the token can refresh in the background), never synced to iCloud Keychain, and never
/// restored from a backup onto another phone. supabase-swift's own storage allows backup
/// migration, so Glow uses this one instead.
struct DeviceKeychainStorage: AuthLocalStorage {
    let service: String

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func store(key: String, value: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func retrieve(key: String) throws -> Data? {
        var item: CFTypeRef?
        let lookup = query(key).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { $1 }
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A Keychain failure. Carries only the status code.
struct KeychainError: Error, Hashable {
    let status: OSStatus
}

/// Session storage in memory only, for tests and previews.
final class MemoryAuthStorage: AuthLocalStorage {
    private let items = OSAllocatedUnfairLockBox<[String: Data]>([:])

    func store(key: String, value: Data) throws {
        items.update { $0[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        items.read { $0[key] }
    }

    func remove(key: String) throws {
        items.update { $0[key] = nil }
    }
}

/// A tiny lock around a value.
final class OSAllocatedUnfairLockBox<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    func read<T: Sendable>(_ body: @Sendable (Value) -> T) -> T {
        lock.withLock { body($0) }
    }

    func update(_ body: @Sendable (inout Value) -> Void) {
        lock.withLock { body(&$0) }
    }
}
