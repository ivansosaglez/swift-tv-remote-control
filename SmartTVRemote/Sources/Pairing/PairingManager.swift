import Foundation
import CryptoKit
import UIKit

/// Gestiona el emparejamiento seguro con el televisor (protocolo «Polo», puerto 6467).
///
/// Flujo: TLS con certificado de cliente → PairingRequest → Options → Configuration → el televisor
/// muestra un código hexadecimal de 6 caracteres → el usuario lo escribe → se envía
/// `SHA-256(módulo_cliente ‖ exp_cliente ‖ módulo_servidor ‖ exp_servidor ‖ código[1...])`.
@MainActor
final class PairingManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case waitingForCode
        case verifying
        case success
        case failed(TVError)
    }

    @Published private(set) var phase: Phase = .idle

    private var channel: TLSChannel?
    private var device: TVDevice?
    private var task: Task<Void, Never>?

    func begin(device: TVDevice) {
        cancel()
        self.device = device
        phase = .connecting
        task = Task {
            do {
                let identity = try CertificateManager.shared.identity()
                let channel = TLSChannel(host: device.host, port: PairingProtocol.port, identity: identity, pinnedFingerprint: nil)
                self.channel = channel
                try await channel.open()

                channel.send(PairingProtocol.pairingRequest(clientName: "iPhone · Smart TV Remote"))
                try await expect(on: channel) { $0.hasPairingRequestAck }

                channel.send(PairingProtocol.options())
                try await expect(on: channel) { $0.hasOptions }

                channel.send(PairingProtocol.configuration())
                try await expect(on: channel) { $0.hasConfigurationAck }

                guard !Task.isCancelled else { return }
                phase = .waitingForCode
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(TVError.from(error, host: device.host))
                channel?.close()
            }
        }
    }

    /// Envía el código mostrado en el televisor (6 caracteres hexadecimales).
    func submit(code rawCode: String) {
        guard phase == .waitingForCode, let channel, let device else { return }
        phase = .verifying
        task = Task {
            do {
                let code = rawCode.trimmingCharacters(in: .whitespaces).uppercased()
                guard code.count == 6, let codeBytes = Self.hexBytes(code) else { throw TVError.wrongCode }
                let client = try CertificateManager.shared.clientPublicNumbers()
                guard let server = channel.serverCertificate, let sMod = server.modulus, let sExp = server.exponent else {
                    throw TVError.pairingNotAvailable
                }

                var hasher = SHA256()
                hasher.update(data: client.modulus)
                hasher.update(data: client.exponent)
                hasher.update(data: sMod)
                hasher.update(data: sExp)
                hasher.update(data: Data(codeBytes.dropFirst()))
                let hash = Data(hasher.finalize())

                channel.send(PairingProtocol.secret(hash))
                let response = try PairingProtocol.parse(await channel.receiveMessage())
                guard response.status == PairingProtocol.statusOK, response.hasSecretAck else {
                    throw response.status == 402 ? TVError.wrongCode : TVError.pairingRejected
                }
                KeychainStore.savePinnedFingerprint(server.fingerprint, deviceID: device.id)
                channel.close()
                phase = .success
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(TVError.from(error, host: device.host))
                channel.close()
            }
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        channel?.close(); channel = nil
        phase = .idle
    }

    private func expect(on channel: TLSChannel, _ check: (PairingProtocol.Response) -> Bool) async throws {
        let response = try PairingProtocol.parse(await channel.receiveMessage())
        guard response.status == PairingProtocol.statusOK else { throw TVError.pairingRejected }
        guard check(response) else { throw TVError.protocolError("paso de emparejamiento inesperado") }
    }

    static func hexBytes(_ s: String) -> [UInt8]? {
        guard s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
}
