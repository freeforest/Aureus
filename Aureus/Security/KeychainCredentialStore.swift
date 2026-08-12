import Foundation
import Security

enum CredentialStoreError: Error, Equatable, Sendable {
    case invalidCredential
    case keychainStatus(Int32)
    case injectedFailure
}

actor KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = "com.aureus.wealthterminal.provider-credentials") {
        self.service = service
    }

    func credential(for descriptor: CredentialDescriptor) throws -> Data? {
        var query = baseQuery(for: descriptor)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw CredentialStoreError.invalidCredential
        }
        return data
    }

    func store(_ credential: Data, for descriptor: CredentialDescriptor) throws {
        guard !credential.isEmpty else { throw CredentialStoreError.invalidCredential }
        let query = baseQuery(for: descriptor)
        let updates: [String: Any] = [kSecValueData as String: credential]
        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = credential
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychainStatus(updateStatus)
        }
    }

    func deleteCredential(for descriptor: CredentialDescriptor) throws {
        let status = SecItemDelete(baseQuery(for: descriptor) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(for descriptor: CredentialDescriptor) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String:
                "\(descriptor.providerIdentifier):\(descriptor.accountIdentifier)",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
