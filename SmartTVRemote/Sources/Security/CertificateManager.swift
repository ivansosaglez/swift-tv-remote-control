import Foundation
import Security
import CryptoKit

/// Gestiona la identidad TLS del cliente (par RSA-2048 + certificado autofirmado).
///
/// El protocolo Android TV Remote autentica al cliente por su certificado: el televisor
/// recuerda el certificado con el que se emparejó. Por eso la identidad se genera una sola vez
/// y se conserva en el Keychain (clave privada no exportable + certificado).
final class CertificateManager {
    static let shared = CertificateManager()

    private let label = "com.ivansosa.smarttvremote.client-identity"
    private let tag = Data("com.ivansosa.smarttvremote.client-key".utf8)
    private let lock = NSLock()
    private var cached: SecIdentity?

    /// Devuelve la identidad existente o crea una nueva.
    func identity() throws -> SecIdentity {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        if let existing = findIdentity() {
            cached = existing
            return existing
        }
        let created = try createIdentity()
        cached = created
        return created
    }

    /// Módulo y exponente (big-endian sin ceros iniciales) de la clave pública del cliente.
    func clientPublicNumbers() throws -> (modulus: Data, exponent: Data) {
        let id = try identity()
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(id, &cert) == errSecSuccess, let cert,
              let key = SecCertificateCopyKey(cert),
              let ext = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let numbers = DER.parseRSAPublicKey(ext)
        else { throw TVError.identityUnavailable("clave pública ilegible") }
        return numbers
    }

    /// Borra la identidad (fuerza a volver a emparejar todos los televisores).
    func reset() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        SecItemDelete([kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag] as CFDictionary)
    }

    // MARK: Privado

    private func findIdentity() -> SecIdentity? {
        let q: [String: Any] = [kSecClass as String: kSecClassIdentity,
                                kSecAttrLabel as String: label,
                                kSecReturnRef as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let out else { return nil }
        return (out as! SecIdentity)
    }

    private func createIdentity() throws -> SecIdentity {
        // Limpia restos de intentos anteriores.
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag] as CFDictionary)

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &error) else {
            throw TVError.identityUnavailable(error?.takeRetainedValue().localizedDescription ?? "sin clave")
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw TVError.identityUnavailable("sin clave pública")
        }

        let certDER = try buildCertificate(publicKeyPKCS1: [UInt8](pkcs1), privateKey: privateKey)
        guard let cert = SecCertificateCreateWithData(nil, Data(certDER) as CFData) else {
            throw TVError.identityUnavailable("certificado inválido")
        }

        let status = SecItemAdd([kSecClass as String: kSecClassCertificate,
                                 kSecValueRef as String: cert,
                                 kSecAttrLabel as String: label,
                                 kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw TVError.identityUnavailable("Keychain \(status)")
        }
        guard let identity = findIdentity() else {
            throw TVError.identityUnavailable("identidad no enlazada")
        }
        return identity
    }

    /// Construye un X.509 v3 autofirmado (sha256WithRSAEncryption) en DER.
    func buildCertificate(publicKeyPKCS1: [UInt8], privateKey: SecKey) throws -> [UInt8] {
        let algorithm = DER.sequence(DER.oidSHA256WithRSA, DER.null())

        func name(_ cn: String) -> [UInt8] {
            DER.sequence(DER.set(DER.sequence(DER.oidCommonName, DER.utf8(cn))))
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyMMddHHmmss'Z'"
        let notBefore = Date().addingTimeInterval(-86_400)
        let notAfter = Calendar(identifier: .gregorian).date(byAdding: .year, value: 20, to: Date())!
        let validity = DER.sequence(DER.utcTime(fmt.string(from: notBefore)), DER.utcTime(fmt.string(from: notAfter)))

        var serial = (0..<8).map { _ in UInt8.random(in: 0...255) }
        serial[0] &= 0x7F
        if serial[0] == 0 { serial[0] = 1 }

        let spki = DER.sequence(
            DER.sequence(DER.oidRSAEncryption, DER.null()),
            DER.bitString(publicKeyPKCS1)
        )

        let tbs = DER.sequence(
            DER.contextExplicit(0, DER.integer([2])),
            DER.integer(serial),
            algorithm,
            name("atvremote"),
            validity,
            name("atvremote"),
            spki
        )

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(tbs) as CFData, &error) as Data? else {
            throw TVError.identityUnavailable(error?.takeRetainedValue().localizedDescription ?? "firma fallida")
        }
        return DER.sequence(tbs, algorithm, DER.bitString([UInt8](signature)))
    }
}

extension Data {
    var sha256: Data { Data(SHA256.hash(data: self)) }
}
