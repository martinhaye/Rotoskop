import Foundation
import Security

/// Stores and retrieves a GitHub personal access token.
public protocol PATStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// In-memory PAT store for tests.
public final class InMemoryPATStore: PATStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func save(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}

/// GitHub PAT in the Keychain (DESIGN §1.3).
public struct KeychainPATStore: PATStore, Sendable {
    public static let defaultService = "com.rotoskop.github-pat"
    public static let defaultAccount = "github"

    public let service: String
    public let account: String

    public init(service: String = Self.defaultService, account: String = Self.defaultAccount) {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GitError(.other("Keychain read failed (\(status))"))
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw GitError(.other("Keychain token was not valid UTF-8"))
        }
        return token
    }

    public func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clear()
            return
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        if update == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw GitError(.other("Keychain save failed (\(status))"))
            }
            return
        }
        throw GitError(.other("Keychain update failed (\(update))"))
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitError(.other("Keychain delete failed (\(status))"))
        }
    }
}
