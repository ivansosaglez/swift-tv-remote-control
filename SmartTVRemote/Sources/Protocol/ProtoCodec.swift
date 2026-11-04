import Foundation

// MARK: - Varint helpers

/// Utilidades de varint usadas tanto por protobuf como por el enmarcado de mensajes del protocolo.
enum Varint {
    static func encode(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    /// Decodifica un varint al inicio de `bytes`. Devuelve `nil` si está incompleto.
    static func decode(_ bytes: [UInt8], from start: Int = 0) -> (value: UInt64, length: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            result |= UInt64(byte & 0x7F) << shift
            index += 1
            if byte & 0x80 == 0 { return (result, index - start) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}

// MARK: - Writer

/// Codificador protobuf mínimo (varint y length-delimited). Suficiente para los protocolos Polo y Remote v2.
struct PBWriter {
    private(set) var data = Data()

    private mutating func tag(_ field: Int, wire: Int) {
        data.append(Varint.encode(UInt64(field << 3 | wire)))
    }

    mutating func int(_ field: Int, _ value: Int) {
        tag(field, wire: 0)
        data.append(Varint.encode(UInt64(bitPattern: Int64(value))))
    }

    mutating func bool(_ field: Int, _ value: Bool) { int(field, value ? 1 : 0) }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, wire: 2)
        data.append(Varint.encode(UInt64(value.count)))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout PBWriter) -> Void) {
        var inner = PBWriter()
        build(&inner)
        bytes(field, inner.data)
    }
}

// MARK: - Reader

/// Decodificador protobuf mínimo. Conserva todos los campos para consultarlos por número.
struct PBReader {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
        case fixed(Data)
    }

    private(set) var fields: [(number: Int, value: Value)] = []

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard let (key, keyLen) = Varint.decode(bytes, from: index) else { throw TVError.protocolError("varint inválido") }
            index += keyLen
            let number = Int(key >> 3)
            switch key & 0x7 {
            case 0:
                guard let (v, l) = Varint.decode(bytes, from: index) else { throw TVError.protocolError("varint inválido") }
                index += l
                fields.append((number, .varint(v)))
            case 1:
                guard index + 8 <= bytes.count else { throw TVError.protocolError("fixed64 truncado") }
                fields.append((number, .fixed(Data(bytes[index..<index + 8]))))
                index += 8
            case 2:
                guard let (len, l) = Varint.decode(bytes, from: index) else { throw TVError.protocolError("longitud inválida") }
                index += l
                guard len <= UInt64(bytes.count - index) else { throw TVError.protocolError("campo truncado") }
                fields.append((number, .bytes(Data(bytes[index..<index + Int(len)]))))
                index += Int(len)
            case 5:
                guard index + 4 <= bytes.count else { throw TVError.protocolError("fixed32 truncado") }
                fields.append((number, .fixed(Data(bytes[index..<index + 4]))))
                index += 4
            default:
                throw TVError.protocolError("wire type no soportado")
            }
        }
    }

    func has(_ field: Int) -> Bool { fields.contains { $0.number == field } }

    func int(_ field: Int) -> Int? {
        for f in fields where f.number == field {
            if case .varint(let v) = f.value { return Int(Int64(bitPattern: v)) }
        }
        return nil
    }

    func bool(_ field: Int) -> Bool? { int(field).map { $0 != 0 } }

    func data(_ field: Int) -> Data? {
        for f in fields where f.number == field {
            if case .bytes(let d) = f.value { return d }
        }
        return nil
    }

    func string(_ field: Int) -> String? { data(field).flatMap { String(data: $0, encoding: .utf8) } }

    func message(_ field: Int) -> PBReader? { data(field).flatMap { try? PBReader($0) } }
}
