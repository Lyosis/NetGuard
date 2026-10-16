import Darwin

// MARK: - ARPTable
/// Lecture de la table ARP IPv4 du système, **dans le processus**, via `sysctl`.
///
/// Sous macOS 27, la table ARP est masquée — vide, sans aucune erreur — pour tout
/// processus dont la signature ne porte pas de bundle ID. `/usr/sbin/arp`, lancé par
/// l'app, en hérite : il renvoyait une table vide, et NetGuard perdait toutes les MAC,
/// donc les constructeurs et l'identité des appareils. Lue ici, la table est filtrée
/// selon l'identité de NetGuard lui-même, qui a un bundle ID.
///
/// Comportement non documenté par Apple, établi par mesure (octobre 2026) : même code
/// `sysctl`, 34 MAC sur 34 avec bundle ID, 0 sans. Le scan signale désormais une
/// lecture vide (`AppState`), pour qu'un futur durcissement ne passe pas inaperçu.
enum ARPTable {

    /// Entrées résolues `(ip, mac)` — les entrées incomplètes sont ignorées.
    ///
    /// La MAC est au format de `arp -an` : octets hexadécimaux minuscules **sans zéro
    /// de tête** (`0:17:88:74:49:3d`). Les clés de persistance existantes ont été
    /// construites sur ce format ; le changer re-clé silencieusement tout appareil
    /// dont un octet est inférieur à `0x10`.
    static func read() -> [(ip: String, mac: String)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        // La table peut grossir entre la mesure de taille et la lecture (ENOMEM).
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
            size += size / 8
            var buffer = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 {
                return parse(buffer, length: min(size, buffer.count))
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    /// Décode une suite de messages `rt_msghdr` + `sockaddr_in` (RTA_DST) +
    /// `sockaddr_dl` (RTA_GATEWAY). Chaque lecture est bornée par la longueur du
    /// message : un message tronqué ou incohérent arrête le décodage, sans plantage.
    static func parse(_ buffer: [UInt8], length: Int) -> [(ip: String, mac: String)] {
        let headerSize = MemoryLayout<rt_msghdr>.size
        let sinSize    = MemoryLayout<sockaddr_in>.size
        let sdlSize    = MemoryLayout<sockaddr_dl>.size
        let sdlDataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
        let required   = RTA_DST | RTA_GATEWAY

        var results: [(ip: String, mac: String)] = []
        buffer.withUnsafeBytes { raw in
            let end = min(length, raw.count)
            var offset = 0
            while offset + headerSize <= end {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let messageLength = Int(header.rtm_msglen)
                guard messageLength >= headerSize, offset + messageLength <= end else { break }
                let messageEnd = offset + messageLength
                defer { offset = messageEnd }

                guard header.rtm_addrs & required == required else { continue }

                let sinOffset = offset + headerSize
                guard sinOffset + sinSize <= messageEnd else { continue }
                let sin = raw.loadUnaligned(fromByteOffset: sinOffset, as: sockaddr_in.self)
                guard sin.sin_family == sa_family_t(AF_INET) else { continue }

                let sdlOffset = sinOffset + roundUp(Int(sin.sin_len))
                guard sdlOffset + sdlSize <= messageEnd else { continue }
                let sdl = raw.loadUnaligned(fromByteOffset: sdlOffset, as: sockaddr_dl.self)
                guard sdl.sdl_family == sa_family_t(AF_LINK), sdl.sdl_alen == 6 else { continue }

                let macOffset = sdlOffset + sdlDataOffset + Int(sdl.sdl_nlen)
                guard macOffset + 6 <= messageEnd else { continue }
                let mac = (0..<6)
                    .map { String(raw[macOffset + $0], radix: 16) }
                    .joined(separator: ":")

                guard let ip = ipString(sin.sin_addr) else { continue }
                results.append((ip, mac))
            }
        }
        return results
    }

    /// Alignement des `sockaddr` dans les messages de routage (cf. `ROUNDUP` de arp.c).
    private static func roundUp(_ length: Int) -> Int {
        let word = MemoryLayout<UInt32>.size
        return length > 0 ? 1 + ((length - 1) | (word - 1)) : word
    }

    private static func ipString(_ address: in_addr) -> String? {
        var address = address
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil else { return nil }
        return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
