import Foundation

/// Utilidades mínimas de ASN.1 DER para construir el certificado autofirmado del cliente
/// y para extraer módulo/exponente de claves RSA PKCS#1.
enum DER {
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func set(_ parts: [UInt8]...) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }
    static func null() -> [UInt8] { [0x05, 0x00] }
    static func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }
    static func utcTime(_ s: String) -> [UInt8] { tlv(0x17, Array(s.utf8)) }
    static func bitString(_ content: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + content) }
    static func contextExplicit(_ n: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xA0 | n, content) }

    /// INTEGER positivo a partir de bytes big-endian sin signo.
    static func integer(_ magnitude: [UInt8]) -> [UInt8] {
        var m = Array(magnitude.drop { $0 == 0 })
        if m.isEmpty { m = [0] }
        if m[0] & 0x80 != 0 { m.insert(0, at: 0) }
        return tlv(0x02, m)
    }

    // OIDs codificados
    static let oidRSAEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    static let oidSHA256WithRSA: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    static let oidCommonName: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]

    // MARK: Lectura

    /// Extrae (módulo, exponente) sin ceros iniciales desde una clave pública RSA PKCS#1.
    static func parseRSAPublicKey(_ data: Data) -> (modulus: Data, exponent: Data)? {
        let b = [UInt8](data)
        var i = 0
        guard let seq = readHeader(b, &i), seq.tag == 0x30 else { return nil }
        guard let nHdr = readHeader(b, &i), nHdr.tag == 0x02, i + nHdr.length <= b.count else { return nil }
        let n = Array(b[i..<i + nHdr.length]).drop { $0 == 0 }
        i += nHdr.length
        guard let eHdr = readHeader(b, &i), eHdr.tag == 0x02, i + eHdr.length <= b.count else { return nil }
        let e = Array(b[i..<i + eHdr.length]).drop { $0 == 0 }
        return (Data(n), Data(e))
    }

    private static func readHeader(_ b: [UInt8], _ i: inout Int) -> (tag: UInt8, length: Int)? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]; i += 1
        var len = Int(b[i]); i += 1
        if len & 0x80 != 0 {
            let count = len & 0x7F
            guard count > 0, count <= 4, i + count <= b.count else { return nil }
            len = 0
            for _ in 0..<count { len = (len << 8) | Int(b[i]); i += 1 }
        }
        return (tag, len)
    }
}
