import Foundation
import Security

/// Almacén de secretos del emparejamiento en el Keychain de iOS.
///
/// Guarda, por televisor, la huella SHA-256 del certificado del servidor (anclaje de confianza tras
/// el emparejamiento). La clave privada del cliente vive también en el Keychain (ver `CertificateManager`).
enum KeychainStore {
    private static let service = "com.ivansosa.smarttvremote.pairing"

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data, account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var q = baseQuery(account: account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // API específica del emparejamiento
    static func savePinnedFingerprint(_ fp: Data, deviceID: String) { save(fp, account: "pin.\(deviceID)") }
    static func pinnedFingerprint(deviceID: String) -> Data? { load(account: "pin.\(deviceID)") }
    static func removePairing(deviceID: String) { delete(account: "pin.\(deviceID)") }
}
