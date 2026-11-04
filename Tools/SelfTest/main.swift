import Foundation
import Security
import CryptoKit

// Autocomprobaciones sin televisor: protobuf, X.509 generado y hash de emparejamiento.
var failures = 0
func check(_ cond: Bool, _ name: String) { print((cond ? "  OK   " : "  FALLO ") + name); if !cond { failures += 1 } }
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

print("Protobuf / protocolo")
check(hex(RemoteProtocol.key(.dpadUp)) == "5204080 b".replacingOccurrences(of: " ", with: "") || hex(RemoteProtocol.key(.dpadUp)) == "520408131003", "tecla DPAD_UP = 52 04 08 13 10 03 (\(hex(RemoteProtocol.key(.dpadUp))))")
check(hex(RemoteProtocol.pingResponse(5)) == "4a020805", "ping response (\(hex(RemoteProtocol.pingResponse(5))))")
check(hex(RemoteProtocol.appLink("https://a.b")) == "d2050d0a0b68747470733a2f2f612e62", "app link (\(hex(RemoteProtocol.appLink("https://a.b"))))")
let parsed = try! RemoteProtocol.parse(Data([0x42, 0x02, 0x08, 0x07]))
if case .ping(7) = parsed { check(true, "parse ping") } else { check(false, "parse ping") }
let vol = try! RemoteProtocol.parse({ var w = PBWriter(); w.message(50) { $0.int(6, 100); $0.int(7, 42); $0.bool(8, true) }; return w.data }())
if case .volume(let v) = vol { check(v.level == 42 && v.max == 100 && v.muted, "parse volumen") } else { check(false, "parse volumen") }
check(Varint.encode(300) == Data([0xAC, 0x02]), "varint 300")

print("Certificado X.509")
let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
var err: Unmanaged<CFError>?
let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &err)!
let pub = SecKeyCopyPublicKey(priv)!
let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil)! as Data
let cert = try! CertificateManager.shared.buildCertificate(publicKeyPKCS1: [UInt8](pkcs1), privateKey: priv)
let out = CommandLine.arguments[1]
try! Data(cert).write(to: URL(fileURLWithPath: out + "/client.der"))
check(SecCertificateCreateWithData(nil, Data(cert) as CFData) != nil, "SecCertificateCreateWithData acepta el DER")
let nums = DER.parseRSAPublicKey(pkcs1)!
check(nums.modulus.count == 256 && nums.exponent == Data([1, 0, 1]), "módulo 256 B, exponente 010001")
try! (hex(nums.modulus) + "\n" + hex(nums.exponent) + "\n").write(toFile: out + "/numbers.txt", atomically: true, encoding: .utf8)

print("Hash de emparejamiento (vector fijo)")
var h = SHA256()
h.update(data: nums.modulus); h.update(data: nums.exponent); h.update(data: nums.modulus); h.update(data: nums.exponent)
h.update(data: Data(PairingManagerHex("1A2B3C").dropFirst()))
try! hex(Data(h.finalize())).write(toFile: out + "/hash.txt", atomically: true, encoding: .utf8)
func PairingManagerHex(_ s: String) -> [UInt8] { stride(from: 0, to: s.count, by: 2).map { UInt8(s[s.index(s.startIndex, offsetBy: $0)..<s.index(s.startIndex, offsetBy: $0 + 2)], radix: 16)! } }

print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
exit(failures == 0 ? 0 : 1)
