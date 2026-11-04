import Foundation
import Network
import Darwin

/// Envío de paquetes mágicos Wake‑on‑LAN.
///
/// LIMITACIÓN: muchos Android TV no escuchan WoL en Wi‑Fi (solo por Ethernet) y requieren activar
/// «Encender con red / Wake on LAN/Wi‑Fi» en sus ajustes. Además iOS puede exigir el entitlement
/// de multicast para tráfico broadcast. Es una vía "mejor esfuerzo": no hay confirmación de recepción.
enum WakeOnLAN {
    static func normalizedMAC(_ s: String) -> [UInt8]? {
        let hex = s.filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        var out: [UInt8] = []
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b); idx = next
        }
        return out
    }

    static func send(mac: String, targetHost: String) -> Bool {
        guard let macBytes = normalizedMAC(mac) else { return false }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: macBytes) }

        var targets = ["255.255.255.255", targetHost]
        if let b = subnetBroadcast() { targets.insert(b, at: 1) }
        for t in targets {
            for port: UInt16 in [9, 7] {
                let conn = NWConnection(host: NWEndpoint.Host(t), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
                conn.start(queue: .global())
                conn.send(content: packet, completion: .contentProcessed { _ in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { conn.cancel() }
                })
            }
        }
        return true
    }

    /// Dirección broadcast de la interfaz Wi‑Fi (en0).
    private static func subnetBroadcast() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let name = String(validatingUTF8: ifa.ifa_name), name == "en0",
               let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               let mask = ifa.ifa_netmask {
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                let nm = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                var bc = in_addr(s_addr: ip | ~nm)
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &bc, &buf, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buf)
            }
            ptr = ifa.ifa_next
        }
        return nil
    }
}
