import Foundation

// MARK: - Códigos de tecla (android.view.KeyEvent)

/// Subconjunto de `KeyEvent.KEYCODE_*` de Android usado por el mando.
enum AndroidKey: Int {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case search = 84
    case enter = 66
    case delete = 67
    case menu = 82
    case mediaPlayPause = 85
    case mediaRewind = 89
    case mediaFastForward = 90
    case volumeMute = 164
    case settings = 176
    case assist = 219
}

enum KeyDirection: Int {
    case startLong = 1
    case endLong = 2
    case short = 3
}

// MARK: - Modelos de eventos

struct VolumeInfo: Equatable {
    var level: Int
    var max: Int
    var muted: Bool
    var fraction: Double { max > 0 ? Double(level) / Double(max) : 0 }
}

/// Estado del campo de texto enfocado en el televisor (IME remoto).
struct ImeFieldState: Equatable {
    var imeCounter: Int
    var fieldCounter: Int
    var value: String
}

enum RemoteEvent {
    case configure
    case setActive
    case start(started: Bool)
    case ping(Int)
    case volume(VolumeInfo)
    case ime(app: String?, field: ImeFieldState?)
    case imeShow(ImeFieldState?)
    case error
    case other(field: Int)
}

// MARK: - Protocolo de emparejamiento (Polo)

/// Mensajes del protocolo de emparejamiento «Polo» de Android TV (puerto 6467).
enum PairingProtocol {
    static let port: UInt16 = 6467
    static let protocolVersion = 2
    static let statusOK = 200
    /// Codificación hexadecimal con códigos de 6 símbolos, como el mando oficial.
    static let hexEncoding = 3
    static let roleInput = 1
    static let symbolLength = 6

    private static func envelope(_ body: (inout PBWriter) -> Void) -> Data {
        var w = PBWriter()
        w.int(1, protocolVersion)
        w.int(2, statusOK)
        body(&w)
        return w.data
    }

    static func pairingRequest(clientName: String) -> Data {
        envelope { w in
            w.message(10) { m in
                m.string(1, "atvremote")
                m.string(2, clientName)
            }
        }
    }

    static func options() -> Data {
        envelope { w in
            w.message(20) { o in
                o.message(1) { e in
                    e.int(1, hexEncoding)
                    e.int(2, symbolLength)
                }
                o.int(3, roleInput)
            }
        }
    }

    static func configuration() -> Data {
        envelope { w in
            w.message(30) { c in
                c.message(1) { e in
                    e.int(1, hexEncoding)
                    e.int(2, symbolLength)
                }
                c.int(2, roleInput)
            }
        }
    }

    static func secret(_ hash: Data) -> Data {
        envelope { w in w.message(40) { $0.bytes(1, hash) } }
    }

    struct Response {
        let status: Int
        let hasPairingRequestAck: Bool
        let hasOptions: Bool
        let hasConfigurationAck: Bool
        let hasSecretAck: Bool
    }

    static func parse(_ data: Data) throws -> Response {
        let r = try PBReader(data)
        return Response(
            status: r.int(2) ?? 0,
            hasPairingRequestAck: r.has(11),
            hasOptions: r.has(20),
            hasConfigurationAck: r.has(31),
            hasSecretAck: r.has(41)
        )
    }
}

// MARK: - Protocolo de mando remoto (v2)

/// Mensajes del protocolo «Android TV Remote v2» (puerto 6466).
enum RemoteProtocol {
    static let port: UInt16 = 6466
    /// Bitmask de funcionalidades que anuncia el cliente (ping, teclas, IME, volumen, enlaces de app…).
    static let features = 622

    static func configure(model: String, vendor: String, package: String, version: String) -> Data {
        var w = PBWriter()
        w.message(1) { c in
            c.int(1, features)
            c.message(2) { d in
                d.string(1, model)
                d.string(2, vendor)
                d.int(3, 1)
                d.string(4, "1")
                d.string(5, package)
                d.string(6, version)
            }
        }
        return w.data
    }

    static func setActive() -> Data {
        var w = PBWriter()
        w.message(2) { $0.int(1, features) }
        return w.data
    }

    static func pingResponse(_ value: Int) -> Data {
        var w = PBWriter()
        w.message(9) { $0.int(1, value) }
        return w.data
    }

    static func key(_ code: AndroidKey, direction: KeyDirection = .short) -> Data {
        var w = PBWriter()
        w.message(10) { k in
            k.int(1, code.rawValue)
            k.int(2, direction.rawValue)
        }
        return w.data
    }

    static func appLink(_ url: String) -> Data {
        var w = PBWriter()
        w.message(90) { $0.string(1, url) }
        return w.data
    }

    /// Sustituye el contenido completo del campo de texto enfocado en el televisor.
    static func text(_ text: String, field: ImeFieldState) -> Data {
        let cursor = max(text.utf16.count - 1, 0)
        var w = PBWriter()
        w.message(21) { b in
            b.int(1, field.imeCounter)
            b.int(2, field.fieldCounter)
            b.message(3) { e in
                e.int(1, 1)
                e.message(2) { s in
                    s.int(1, cursor)
                    s.int(2, cursor)
                    s.string(3, text)
                }
            }
        }
        return w.data
    }

    static func parse(_ data: Data) throws -> RemoteEvent {
        let r = try PBReader(data)
        if r.has(1) { return .configure }
        if r.has(2) { return .setActive }
        if r.has(3) { return .error }
        if let p = r.message(8) { return .ping(p.int(1) ?? 0) }
        if let s = r.message(40) { return .start(started: s.bool(1) ?? false) }
        if let v = r.message(50) {
            return .volume(VolumeInfo(level: v.int(7) ?? 0, max: v.int(6) ?? 0, muted: v.bool(8) ?? false))
        }
        if let ime = r.message(20) {
            let app = ime.message(1)
            let package = app?.string(12)
            var field: ImeFieldState?
            if let tf = ime.message(2) {
                field = ImeFieldState(imeCounter: app?.int(1) ?? 0, fieldCounter: tf.int(1) ?? 0, value: tf.string(2) ?? "")
            }
            return .ime(app: package, field: field)
        }
        if let show = r.message(22) {
            var field: ImeFieldState?
            if let tf = show.message(2) {
                field = ImeFieldState(imeCounter: 0, fieldCounter: tf.int(1) ?? 0, value: tf.string(2) ?? "")
            }
            return .imeShow(field)
        }
        return .other(field: r.fields.first?.number ?? 0)
    }
}
