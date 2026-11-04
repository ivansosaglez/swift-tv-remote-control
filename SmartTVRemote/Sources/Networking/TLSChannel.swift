import Foundation
import Network
import Security

/// Información del certificado que presenta el televisor.
struct ServerCertificate {
    let fingerprint: Data
    let modulus: Data?
    let exponent: Data?
}

/// Canal TLS con autenticación mutua y mensajes enmarcados con prefijo de longitud (varint).
///
/// El televisor usa un certificado autofirmado, por lo que no se valida contra la CA del sistema:
/// se captura su huella y, si existe un anclaje (`pinnedFingerprint`) guardado en el emparejamiento,
/// se exige que coincida (confianza en el primer uso + anclaje).
final class TLSChannel {
    private final class Capture {
        let lock = NSLock()
        var cert: ServerCertificate?
        var pinViolation = false
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "smarttvremote.tls", qos: .userInteractive)
    private let capture = Capture()
    private let host: String
    private var buffer = [UInt8]()

    var serverCertificate: ServerCertificate? {
        capture.lock.lock(); defer { capture.lock.unlock() }
        return capture.cert
    }

    init(host: String, port: UInt16, identity: SecIdentity, pinnedFingerprint: Data?) {
        self.host = host
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        if let id = sec_identity_create(identity) { sec_protocol_options_set_local_identity(sec, id) }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)

        let capture = self.capture
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else {
                complete(false); return
            }
            let der = SecCertificateCopyData(leaf) as Data
            let fingerprint = der.sha256
            var modulus: Data?, exponent: Data?
            if let key = SecCertificateCopyKey(leaf),
               let ext = SecKeyCopyExternalRepresentation(key, nil) as Data?,
               let n = DER.parseRSAPublicKey(ext) {
                modulus = n.modulus; exponent = n.exponent
            }
            if let pin = pinnedFingerprint, pin != fingerprint {
                capture.lock.lock(); capture.pinViolation = true; capture.lock.unlock()
                complete(false); return
            }
            capture.lock.lock()
            capture.cert = ServerCertificate(fingerprint: fingerprint, modulus: modulus, exponent: exponent)
            capture.lock.unlock()
            complete(true)
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 20
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 8

        let params = NWParameters(tls: tls, tcp: tcp)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
    }

    // MARK: Ciclo de vida

    private final class Once {
        private var done = false
        func run(_ block: () -> Void) { if !done { done = true; block() } }
    }

    func open(timeout: TimeInterval = 8) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            let host = self.host
            let finish: (Error?) -> Void = { err in
                once.run { if let err { cont.resume(throwing: err) } else { cont.resume() } }
            }
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    finish(nil)
                case .failed(let e):
                    finish(self.mapped(e, host: host))
                case .waiting(let e):
                    finish(self.mapped(e, host: host))
                    self.connection.cancel()
                case .cancelled:
                    finish(TVError.connectionClosed)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                finish(TVError.timeout)
                self?.connection.cancel()
            }
        }
    }

    private func mapped(_ error: NWError, host: String) -> TVError {
        capture.lock.lock(); let pin = capture.pinViolation; capture.lock.unlock()
        if pin { return .certificateMismatch }
        return TVError.from(error, host: host)
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    // MARK: Envío / recepción

    func send(_ payload: Data, completion: ((Error?) -> Void)? = nil) {
        var framed = Varint.encode(UInt64(payload.count))
        framed.append(payload)
        connection.send(content: framed, completion: .contentProcessed { error in
            if let error { completion?(TVError.from(error)) } else { completion?(nil) }
        })
    }

    /// Siguiente mensaje completo (sin el prefijo de longitud).
    func receiveMessage() async throws -> Data {
        while true {
            if let (length, used) = Varint.decode(buffer) {
                guard length < 1_048_576 else { throw TVError.protocolError("mensaje demasiado grande") }
                let total = used + Int(length)
                if buffer.count >= total {
                    let message = Data(buffer[used..<total])
                    buffer.removeFirst(total)
                    return message
                }
            }
            try await fill()
        }
    }

    private func fill() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { cont.resume(throwing: TVError.connectionClosed); return }
                if let error { cont.resume(throwing: self.mapped(error, host: self.host)); return }
                if let data, !data.isEmpty {
                    self.buffer.append(contentsOf: data)
                    cont.resume()
                } else if isComplete {
                    cont.resume(throwing: TVError.connectionClosed)
                } else {
                    cont.resume()
                }
            }
        }
    }
}
