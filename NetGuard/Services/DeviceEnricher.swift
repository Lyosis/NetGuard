import Foundation
import Network

// MARK: - BonjourInfo
/// Informations Bonjour associées à un appareil (indexées par IPv4)
private struct BonjourInfo {
    var instanceName: String        // ex: "Mon NAS" (nom Bonjour instance)
    var services: [String]          // ex: ["_smb._tcp", "_afpovertcp._tcp"]
    var model: String = ""          // ex: "Mac14,3" — clé model / am / rpMd du TXT
}

// MARK: - DeviceEnricher
/// Enrichit chaque appareil avec OS, Bonjour (NWBrowser), NetBIOS, HTTP banner, latence précise
actor DeviceEnricher {

    static let shared = DeviceEnricher()
    private init() {}

    // MARK: - Bonjour state (partagé entre discoverBonjourServices et enrichDevice)
    private var bonjourTable: [String: BonjourInfo] = [:]

    /// Types de services Bonjour à découvrir
    private static let bonjourServiceTypes: [String] = [
        "_http._tcp",
        "_https._tcp",
        "_ssh._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_raop._tcp",
        "_airplay._tcp",
        "_ipp._tcp",
        "_printer._tcp",
        "_homekit._tcp",
        "_googlecast._tcp",
        "_companion-link._tcp",
        "_sleep-proxy._tcp",
        "_rfb._tcp",
        "_ftp._tcp",
        "_daap._tcp",
    ]

    // MARK: - Enrich all devices
    /// Enrichit les appareils avec une concurrence bornée. Chaque `enrichDevice`
    /// passe l'essentiel de son temps suspendu (ping subprocess, requête HTTP) :
    /// la fenêtre glissante permet d'analyser plusieurs appareils en parallèle
    /// sans lancer des centaines de sous-processus simultanés.
    func enrichAll(
        devices: [NetworkDevice],
        progressHandler: @Sendable @escaping (Double, String) async -> Void
    ) async {
        let total = devices.count
        guard total > 0 else {
            await progressHandler(1.0, L10n.Scan.analysisDone)
            return
        }
        // Issue #41 — fenêtre réduite de 12 à 6 : chaque `enrichDevice` déclenche
        // lui-même un ping, un NetBIOS et une requête HTTP, soit ~3 flux par
        // appareil. La fenêtre volontairement basse évite de reconstituer un pic
        // de connexions après le balayage.
        //
        // Délibérément **hors** de `ScanThrottle` : l'enrichissement est composite
        // et pourrait un jour appeler du code lui-même throttlé — un `run { }`
        // imbriqué interbloquerait. L'étape est séquentielle par rapport au
        // balayage et au scan de ports, donc les plafonds ne se cumulent pas.
        let maxConcurrent = min(6, total)
        var iterator = devices.makeIterator()
        var completed = 0

        await withTaskGroup(of: Void.self) { group in
            // Amorçage : on remplit la fenêtre.
            for _ in 0..<maxConcurrent {
                if let device = iterator.next() {
                    group.addTask { await self.enrichDevice(device) }
                }
            }
            // Dès qu'un appareil est analysé, on en lance un nouveau.
            for await _ in group {
                completed += 1
                await progressHandler(Double(completed) / Double(total),
                                      "Analyse \(completed)/\(total)…")
                if let device = iterator.next() {
                    group.addTask { await self.enrichDevice(device) }
                }
            }
        }
        await progressHandler(1.0, L10n.Scan.analysisDone)
    }

    // MARK: - Enrich single device
    func enrichDevice(_ device: NetworkDevice) async {
        async let ping    = precisePing(ip: device.ip)
        async let nb      = resolveNetBIOS(ip: device.ip)
        async let http    = grabHTTP(ip: device.ip, ports: device.openPorts.map(\.port))

        let (pingResult, nbName, httpInfo) = await (ping, nb, http)

        // Récupérer les infos Bonjour depuis la table déjà remplie
        let bonjour = bonjourTable[device.ip]

        // Compute OS guess on the actor before switching to MainActor
        let (vendor, devType, hostname) = await MainActor.run {
            (device.vendor, device.type, device.hostname)
        }
        let os = guessOS(ttl: pingResult.ttl, vendor: vendor, type: devType, hostname: hostname)

        await MainActor.run {
            device.responseTime = pingResult.ms
            device.ttl          = pingResult.ttl
            // Jamais de rétrogradation : un OS déjà identifié ne redevient pas inconnu.
            if os != .unknown { device.osGuess = os }
            if let b = bonjour {
                if !b.instanceName.isEmpty { device.mdnsName = b.instanceName }
                if !b.model.isEmpty { device.bonjourModel = b.model }
                device.bonjourServices = b.services
            }
            if !nbName.isEmpty    { device.netbiosName = nbName }
            if !httpInfo.banner.isEmpty { device.httpBanner = httpInfo.banner }
            if !httpInfo.title.isEmpty  { device.httpTitle  = httpInfo.title }
            if let cert = httpInfo.certificate { device.sslCertificate = cert }
            if let port = httpInfo.nonWebPort {
                // Le port reste ouvert et signalé : seul le libellé « HTTP », déduit du
                // numéro de port, est corrigé.
                device.openPorts = device.openPorts.map { $0.port == port ? $0.markedNonWeb() : $0 }
            }
            device.lastSeen = Date()
        }

        // A12 — Fingerprinting du type après que tous les signaux soient collectés
        let snapshot = await MainActor.run { InferSnapshot(device: device) }
        if let inferred = Self.inferType(from: snapshot), inferred != snapshot.currentType {
            await MainActor.run { device.type = inferred }
        }
    }

    // MARK: - A12 Fingerprinting (Bonjour + vendor + banner + hostname + UPnP)
    private struct InferSnapshot {
        let vendor: String              // lowercased
        let mac: String
        let hostname: String            // lowercased
        let mdnsName: String            // lowercased
        let netbiosName: String         // lowercased
        let bonjourServices: Set<String>
        let httpBanner: String          // lowercased
        let httpTitle: String           // lowercased
        let upnpText: String            // friendlyName + modelName + manufacturer + server, lowercased
        let upnpDeviceType: String      // URN UPnP root device, lowercased
        let osGuess: OSGuess
        let isPrivateMAC: Bool
        let currentType: DeviceType
        let isCurrentDevice: Bool
        let appleModel: String

        @MainActor
        init(device: NetworkDevice) {
            self.vendor          = device.vendor.lowercased()
            self.mac             = device.mac
            self.hostname        = device.hostname.lowercased()
            self.mdnsName        = device.mdnsName.lowercased()
            self.netbiosName     = device.netbiosName.lowercased()
            self.bonjourServices = Set(device.bonjourServices)
            self.httpBanner      = device.httpBanner.lowercased()
            self.httpTitle       = device.httpTitle.lowercased()
            let u = device.upnp
            self.upnpText = [u?.friendlyName, u?.modelName, u?.manufacturer, u?.server]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            self.upnpDeviceType = (u?.deviceType ?? "").lowercased()
            self.osGuess         = device.osGuess
            self.isPrivateMAC    = device.isPrivateMAC
            self.currentType     = device.type
            self.isCurrentDevice = device.isCurrentDevice
            self.appleModel      = device.bonjourModel
        }
    }

    /// Type déduit des seules informations déjà connues de l'appareil, sans requête réseau.
    ///
    /// Sert aux fiches enregistrées dont le fabricant vient d'être retrouvé au chargement
    /// (cf. `AppState.refreshStoredIdentification`) : mêmes règles que l'enrichissement,
    /// pour qu'un appareil éteint soit classé comme il le serait en ligne.
    @MainActor
    static func inferredType(for device: NetworkDevice) -> DeviceType? {
        inferType(from: InferSnapshot(device: device))
    }

    /// Tente d'inférer un type plus précis qu'`.unknown` en croisant tous les
    /// signaux collectés pendant l'enrichissement.
    /// Renvoie `nil` si aucune amélioration n'est trouvée — on garde alors le
    /// type courant (qui peut déjà être bon, ou rester `.unknown`).
    private nonisolated static func inferType(from s: InferSnapshot) -> DeviceType? {
        // 1. Préserver les types déjà bien détectés à la découverte
        let strongTypes: Set<DeviceType> = [.router, .switch, .firewall, .wifi, .internet]
        if strongTypes.contains(s.currentType) { return nil }
        if s.isCurrentDevice { return nil }
        // 1a. Carte réseau virtuelle : quoi que la VM fasse tourner, c'est une VM.
        if DeviceType.isVirtualMachine(vendor: s.vendor, mac: s.mac) { return .virtualMachine }
        // 1b. Modèle Apple annoncé par l'appareil : plus sûr que le fabricant, illisible
        // derrière une MAC privée. Sans lui, un Mac récepteur AirPlay passait pour un objet
        // connecté (MAC privée) ou pour une Apple TV (MAC Apple).
        if let type = Self.typeFromAppleModel(s.appleModel) { return type }

        let services = s.bonjourServices
        let isApple  = s.vendor.contains("apple")
        let allNames = "\(s.hostname) \(s.mdnsName) \(s.netbiosName)"
        let webText  = "\(s.httpBanner) \(s.httpTitle)"

        // 1bis. Règles UPnP/SSDP — signal très fiable quand présent.
        // L'URN root device est l'identifiant le plus précis (schemes officiels).
        let urn = s.upnpDeviceType
        let upnp = s.upnpText
        if !urn.isEmpty || !upnp.isEmpty {
            // Consoles de jeu
            if urn.contains("xboxgaming") ||
               upnp.contains("xbox") ||
               (upnp.contains("microsoft") && upnp.contains("xbox")) {
                return .gaming
            }
            if upnp.contains("playstation") || upnp.contains("ps4") || upnp.contains("ps5") ||
               (upnp.contains("sony") && (upnp.contains("cuh-") || upnp.contains("cfi-"))) {
                return .gaming
            }
            // Smart TVs
            if upnp.contains("bravia") || upnp.contains("webos") ||
               upnp.contains("samsung tv") || upnp.contains("smart tv") {
                return .appletv
            }
            // Audio / domotique / caméras UPnP
            if upnp.contains("sonos") || upnp.contains("philips hue") ||
               upnp.contains("hue bridge") || upnp.contains("chromecast") ||
               upnp.contains("nest") || upnp.contains("ring ") {
                return .iot
            }
            // NAS UPnP MediaServer (Synology, QNAP, Plex Media Server…)
            if urn.contains("mediaserver") &&
               (upnp.contains("synology") || upnp.contains("qnap") ||
                upnp.contains("diskstation") || upnp.contains("plex")) {
                return .nas
            }
            // Imprimantes UPnP (rare mais existe — HP ePrint, Brother UPnP)
            if upnp.contains("brother") || upnp.contains("epson") ||
               upnp.contains("canon") || upnp.contains("hewlett") {
                return .printer
            }
            // Routeurs UPnP IGD (Internet Gateway Device) — déjà filtré par
            // strongTypes en général mais cas d'un IGD secondaire isolé.
            if urn.contains("internetgatewaydevice") { return .router }
        }

        // 2. Règles Bonjour (signal le plus fiable)
        if services.contains("_googlecast._tcp") { return .iot }

        let homeKitServices: Set<String> = ["_hap._tcp", "_homekit._tcp"]
        if !services.isDisjoint(with: homeKitServices) {
            // Si Apple + AirPlay → c'est Apple TV / HomePod
            let airplay: Set<String> = ["_airplay._tcp", "_raop._tcp"]
            if isApple && !services.isDisjoint(with: airplay) { return .appletv }
            return .iot
        }

        let airplay: Set<String> = ["_airplay._tcp", "_raop._tcp"]
        if !services.isDisjoint(with: airplay) {
            return isApple ? .appletv : .iot   // récepteur AirPlay tiers (Sonos, JBL…)
        }

        let printerServices: Set<String> = ["_ipp._tcp", "_ipps._tcp", "_printer._tcp"]
        if !services.isDisjoint(with: printerServices) { return .printer }

        let nasServices: Set<String> = ["_smb._tcp", "_afpovertcp._tcp"]
        if !services.isDisjoint(with: nasServices) { return .nas }

        if services.contains("_companion-link._tcp") && isApple {
            if allNames.contains("iphone") { return .iphone }
            if allNames.contains("ipad")   { return .ipad }
            return .mac
        }

        // 3. Bannières HTTP / titre web (signal fiable quand présent)
        if webText.contains("synology") || webText.contains("dsm ") ||
           webText.contains("diskstation") { return .nas }
        if webText.contains("qnap") { return .nas }
        if webText.contains("western digital") || webText.contains("mybook") { return .nas }
        if webText.contains("sonos") { return .iot }
        if webText.contains("philips hue") || webText.contains("hue bridge") { return .iot }
        if webText.contains("unifi") || webText.contains("ubiquiti") { return .wifi }
        if webText.contains("airport") || webText.contains("time capsule") { return .wifi }

        // 4. Vendor seul (signal moyen, mais avec la base IEEE on en a souvent un)
        // NAS / stockage
        if s.vendor.contains("synology") || s.vendor.contains("qnap") ||
           s.vendor.contains("western digital") || s.vendor.contains("buffalo") ||
           s.vendor.contains("netgear") && s.vendor.contains("readyn") {
            return .nas
        }
        // Imprimantes
        if s.vendor.contains("brother") || s.vendor.contains("epson") ||
           s.vendor.contains("canon") || s.vendor.contains("hewlett") ||
           s.vendor.contains("lexmark") || s.vendor.contains("kyocera") ||
           s.vendor.contains("ricoh") || s.vendor.contains("xerox") {
            return .printer
        }
        // WiFi AP / réseau actif (avant IoT car certains sont catégorisés ambigus)
        if s.vendor.contains("ubiquiti") || s.vendor.contains("aruba") ||
           s.vendor.contains("ruckus") || s.vendor.contains("mikrotik") {
            return .wifi
        }
        // IoT — domotique, smart home, caméras
        if s.vendor.contains("philips") || s.vendor.contains("signify") ||
           s.vendor.contains("sonos") || s.vendor.contains("ring") ||
           s.vendor.contains("nest") || s.vendor.contains("ecobee") ||
           s.vendor.contains("amazon") || s.vendor.contains("ezviz") ||
           s.vendor.contains("tp-link") || s.vendor.contains("xiaomi") ||
           s.vendor.contains("meross") || s.vendor.contains("tuya") ||
           s.vendor.contains("eufy") || s.vendor.contains("reolink") ||
           s.vendor.contains("arlo") || s.vendor.contains("anker") ||
           s.vendor.contains("blink") || s.vendor.contains("honeywell") ||
           s.vendor.contains("lutron") || s.vendor.contains("lifx") ||
           s.vendor.contains("wemo") || s.vendor.contains("belkin") ||
           s.vendor.contains("shelly") || s.vendor.contains("sonoff") ||
           s.vendor.contains("ikea") || s.vendor.contains("aqara") ||
           s.vendor.contains("withings") || s.vendor.contains("netatmo") {
            return .iot
        }
        // Consoles de jeu — le type dédié existe, la règle UPnP l'emploie déjà.
        if s.vendor.contains("nintendo") || allNames.contains("xbox") ||
           allNames.contains("playstation") {
            return .gaming
        }
        // TVs connectées (Sony : TV comme PlayStation, d'où la règle par nom ci-dessus)
        if s.vendor.contains("samsung") || s.vendor.contains("lg electronics") ||
           s.vendor.contains("sony") ||
           s.vendor.contains("roku") || s.vendor.contains("vizio") {
            return .iot
        }

        // 5. Hostname hints (fallback)
        if allNames.contains("iphone") { return .iphone }
        if allNames.contains("ipad")   { return .ipad }
        if allNames.contains("macbook") || allNames.contains("imac") ||
           allNames.contains("mac-mini") { return .mac }

        // 6. Apple sans autre signal → mac (catégorie Apple générique)
        if isApple && s.currentType == .unknown { return .mac }

        // 6a. Netgear ambigu (peut être routeur Nighthawk, Orbi mesh, switch,
        // ReadyNAS, Arlo…). Sans aucun signal Bonjour/HTTP, sur un réseau home
        // ~80% des cas sont des points d'accès WiFi (Orbi/Nighthawk). On code
        // l'heuristique.
        let webTextTrimmed = webText.trimmingCharacters(in: .whitespaces)
        let isUnixLike = s.osGuess == .macOS || s.osGuess == .linux
        if s.vendor.contains("netgear") && isUnixLike &&
           webTextTrimmed.isEmpty && services.isEmpty {
            return .wifi
        }

        // 6b. Silicon vendors (puces WiFi/BT embarquées) + TTL Unix-like (=
        // RTOS/Linux embarqué) → quasi-certain IoT silencieux : prise smart,
        // ampoule, capteur, robot, thermostat… Faillible (un PC avec carte
        // Realtek pourrait être classé IoT) mais sur un réseau home c'est
        // majoritairement vrai.
        let siliconVendors = ["texas instruments", "espressif", "realtek",
                              "mediatek", "murata", "ralink", "atheros",
                              "high-flying", "hi-flying"]
        if siliconVendors.contains(where: { s.vendor.contains($0) }) && isUnixLike {
            return .iot
        }

        // 7. MAC privée (privacy WiFi iOS/iPadOS/macOS Sonoma+/Android 10+).
        // Le vendor est forcément vide (pas dans IEEE par construction). TTL 64
        // = famille Unix-like → l'écrasante majorité sur réseau home = iPhone.
        // Heuristique faillible (pourrait être iPad ou Mac) → l'UI affiche un
        // badge « MAC privée » pour inviter l'utilisateur à vérifier.
        if s.isPrivateMAC && (s.osGuess == .macOS || s.osGuess == .ios) {
            return .iphone
        }

        // Aucune amélioration trouvée
        return nil
    }

    // MARK: - Bonjour Discovery (NWBrowser)

    /// Lance la découverte Bonjour pour tous les types de services en parallèle,
    /// résout les endpoints en IPv4, puis popule `bonjourTable`.
    /// Durée totale : ~3s browse + ~2s resolve (en parallèle). La résolution ne contacte
    /// aucun appareil : voir `BonjourResolver`.
    func discoverBonjourServices() async {
        // 1. Découverte de tous les types en parallèle (3s timeout)
        let allResults: [BrowseResult] = await withTaskGroup(of: [BrowseResult].self) { group in
            for serviceType in Self.bonjourServiceTypes {
                group.addTask {
                    await self.browse(serviceType, timeout: 3.0)
                }
            }
            var combined: [BrowseResult] = []
            for await partial in group {
                combined.append(contentsOf: partial)
            }
            return combined
        }

        // 2. Résolution en IPv4 en parallèle, sans connexion (2 s au plus par service)
        var table: [String: BonjourInfo] = [:]
        await withTaskGroup(of: ([String], BrowseResult).self) { group in
            for result in allResults {
                group.addTask {
                    let ips = await BonjourResolver.ipv4Addresses(name: result.instanceName,
                                                                  type: result.serviceType,
                                                                  domain: result.domain)
                    return (ips, result)
                }
            }
            // Un hôte a souvent plusieurs adresses (loopback, interfaces virtuelles, LAN) :
            // le service est rattaché à chacune, seule celle d'un appareil scanné servira.
            for await (ips, result) in group {
                let name = Self.displayInstanceName(result.instanceName)
                for ip in ips {
                    if var existing = table[ip] {
                        if !existing.services.contains(result.serviceType) {
                            existing.services.append(result.serviceType)
                        }
                        if existing.instanceName.isEmpty {
                            existing.instanceName = name
                        }
                        if existing.model.isEmpty {
                            existing.model = result.model
                        }
                        table[ip] = existing
                    } else {
                        table[ip] = BonjourInfo(instanceName: name,
                                                services: [result.serviceType],
                                                model: result.model)
                    }
                }
            }
        }

        bonjourTable = table
    }

    // MARK: - NWBrowser (un type de service, retourne tous les résultats en ~timeout secondes)

    private struct BrowseResult {
        var instanceName: String
        var serviceType: String
        var domain: String
        var model: String
    }

    private func browse(_ serviceType: String, timeout: TimeInterval) async -> [BrowseResult] {
        // NWBrowser doit être utilisé depuis une DispatchQueue — on utilise une queue sérialisée
        // par type de service pour éviter les conflits de concurrence Swift 6.
        let queueLabel = "netguard.bonjour.\(serviceType.filter { $0.isLetter || $0 == "." })"
        let queue = DispatchQueue(label: queueLabel, qos: .utility)

        // Box @unchecked Sendable : manipulée exclusivement sur `queue`
        final class Box: @unchecked Sendable {
            var results: [BrowseResult] = []
        }
        let box = Box()

        return await withCheckedContinuation { (continuation: CheckedContinuation<[BrowseResult], Never>) in
            // Utiliser un flag pour éviter le double-resume
            final class Flag: @unchecked Sendable { var done = false }
            let flag = Flag()

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: serviceType, domain: "local."),
                using: NWParameters()
            )

            browser.browseResultsChangedHandler = { currentResults, _ in
                // Appelé sur queue (NWBrowser hérite de la queue passée à start)
                box.results = currentResults.compactMap { result -> BrowseResult? in
                    guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                    // Normaliser le type : supprimer le point final éventuel ("_ssh._tcp." → "_ssh._tcp")
                    let normalizedType = type.hasSuffix(".") ? String(type.dropLast()) : type
                    var model = ""
                    if case let .bonjour(txt) = result.metadata {
                        // AirPlay : model ; AirPlay audio : am ; Continuité : rpMd.
                        model = ["model", "am", "rpMd"].lazy
                            .compactMap { txt[$0] }
                            .compactMap { Self.sanitizedModel($0) }
                            .first ?? ""
                    }
                    return BrowseResult(instanceName: name,
                                        serviceType: normalizedType,
                                        domain: domain.isEmpty ? "local." : domain,
                                        model: model)
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                guard !flag.done else { return }
                flag.done = true
                browser.cancel()
                continuation.resume(returning: box.results)
            }
        }
    }

    // MARK: - Modèle Apple (TXT Bonjour)

    /// Modèle annoncé, s'il a la forme d'un identifiant de modèle : 1 à 64 caractères,
    /// lettres et chiffres ASCII, virgule, tiret. Sinon nil — la donnée vient de l'appareil.
    nonisolated static func sanitizedModel(_ raw: String) -> String? {
        guard (1...64).contains(raw.count),
              raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "," || $0 == "-") })
        else { return nil }
        return raw
    }

    /// Type déduit d'un identifiant de modèle Apple. Nil si le modèle n'est pas reconnu :
    /// les autres règles s'appliquent alors.
    ///
    /// NetGuard n'a pas de type HomePod : `AudioAccessory` reste classé avec l'Apple TV,
    /// comme le faisait déjà la règle AirPlay.
    nonisolated static func typeFromAppleModel(_ model: String) -> DeviceType? {
        if model.hasPrefix("AppleTV") || model.hasPrefix("AudioAccessory") { return .appletv }
        if model.hasPrefix("iPhone") { return .iphone }
        if model.hasPrefix("iPad") { return .ipad }
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return .mac }
        return nil
    }

    // MARK: - Noms Bonjour

    /// Nom d'instance Bonjour lisible.
    ///
    /// Les récepteurs AirPlay audio (`_raop._tcp`) s'annoncent sous la forme
    /// `<12 chiffres hexadécimaux>@<nom>` : `062882A4DDF2@Chambre`. Le préfixe est
    /// l'adresse MAC du récepteur ; seul le nom est gardé.
    nonisolated static func displayInstanceName(_ raw: String) -> String {
        guard let at = raw.firstIndex(of: "@") else { return raw }
        let prefix = raw[..<at]
        let name = raw[raw.index(after: at)...]
        guard prefix.count == 12, prefix.allSatisfy(\.isHexDigit), !name.isEmpty else { return raw }
        return String(name)
    }

    // MARK: - Precise Ping (parses TTL + RTT)
    private struct PingResult { var ms: Double; var ttl: Int }

    private func precisePing(ip: String) async -> PingResult {
        // Défense en profondeur : jamais d'argument non validé dans l'argv de ping.
        guard IPv4.isValid(ip) else { return PingResult(ms: 0, ttl: 0) }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "3", "-W", "1000", ip]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            process.terminationHandler = { _ in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                continuation.resume(returning: Self.parsePing(out))
            }
            do {
                try process.run()
            } catch {
                // /sbin/ping absent ou non exécutable — résume immédiatement pour éviter le hang
                continuation.resume(returning: PingResult(ms: 0, ttl: 0))
            }
        }
    }

    private static func parsePing(_ output: String) -> PingResult {
        var ttl = 0
        var ms  = 0.0

        // Parse TTL from "ttl=64" or "TTL=64"
        if let r = output.range(of: #"ttl=(\d+)"#, options: .regularExpression) {
            let s = output[r].replacingOccurrences(of: "ttl=", with: "", options: .caseInsensitive)
            ttl = Int(s) ?? 0
        }

        // Parse avg RTT from "round-trip min/avg/max/stddev = 0.123/0.456/0.789/0.123 ms"
        if let r = output.range(of: #"min/avg/max[^=]+=\s*[\d.]+/([\d.]+)"#,
                                  options: .regularExpression) {
            let matched = String(output[r])
            let parts = matched.components(separatedBy: "/")
            if parts.count >= 2 { ms = Double(parts[1]) ?? 0 }
        }
        // Fallback: parse "time=X.X ms"
        if ms == 0, let r = output.range(of: #"time=([\d.]+) ms"#, options: .regularExpression) {
            let s = output[r]
                .replacingOccurrences(of: "time=", with: "")
                .replacingOccurrences(of: " ms", with: "")
            ms = Double(s) ?? 0
        }
        return PingResult(ms: ms, ttl: ttl)
    }

    // MARK: - OS Guess from TTL
    private func guessOS(ttl: Int, vendor: String, type: DeviceType, hostname: String) -> OSGuess {
        let v = vendor.lowercased()
        let h = hostname.lowercased()

        // Vendor-based hints
        if v.contains("apple") {
            if h.contains("iphone") || h.contains("ipad") { return .ios }
            return .macOS
        }
        if v.contains("microsoft") { return .windows }
        // Nom d'hôte explicite (souvent fourni par la box) : prime sur le TTL, qui ne
        // distingue pas iOS de macOS — cas des iPhone à MAC privée, sans fabricant.
        if h.contains("iphone") || h.contains("ipad") { return .ios }

        // TTL-based fingerprint (accounting for hops: ±10)
        switch ttl {
        case 1...65:   return .macOS   // macOS/Linux default 64
        case 66...130: return .windows // Windows default 128
        case 131...255:
            if type == .router || type == .firewall || type == .switch { return .router }
            return .linux
        default: return .unknown
        }
    }

    // MARK: - NetBIOS name (smbutil)
    /// Nom NetBIOS via `smbutil status`.
    ///
    /// Les versions jusqu'à 1.1.3 appelaient `/usr/bin/nmblookup`, absent de macOS
    /// depuis le retrait de Samba : l'appel échouait en silence, pour tous les
    /// appareils. Mesuré : `smbutil` répond en ~0,05 s pour un hôte SMB et abandonne
    /// seul en ~1 s sinon ; le délai de garde ne sert qu'en cas de blocage.
    private func resolveNetBIOS(ip: String) async -> String {
        // Défense en profondeur : jamais d'argument non validé dans l'argv de smbutil.
        guard IPv4.isValid(ip) else { return "" }
        return await withCheckedContinuation { continuation in
            let smb = Process()
            smb.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
            smb.arguments = ["status", ip]
            let pipe = Pipe()
            smb.standardOutput = pipe
            smb.standardError  = Pipe()
            // Délai de garde, annulé dès la fin du processus. `isRunning` protège aussi
            // le cas où `run()` échoue : `terminate()` sur un processus jamais lancé
            // lève une exception. `terminate()` déclenche `terminationHandler`.
            let watchdog = Task {
                guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                if smb.isRunning { smb.terminate() }
            }
            smb.terminationHandler = { _ in
                watchdog.cancel()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                continuation.resume(returning: Self.parseSMBStatus(out))
            }
            do {
                try smb.run()
            } catch {
                watchdog.cancel()
                continuation.resume(returning: "")
            }
        }
    }

    /// Extrait le nom de la ligne `Server: NOM` de `smbutil status`.
    ///
    /// Le nom vient de l'appareil : donnée non fiable. Un nom NetBIOS fait au plus
    /// 15 caractères ; tout ce qui sort d'un jeu restreint est rejeté plutôt qu'affiché.
    nonisolated static func parseSMBStatus(_ output: String) -> String {
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("Server:") else { continue }
            let name = line.dropFirst("Server:".count).trimmingCharacters(in: .whitespaces)
            let allowed = name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
            return (1...15).contains(name.count) && allowed ? name : ""
        }
        return ""
    }

    // MARK: - Récupération d'un SecTrust frais (A3 — bouton « Voir le certificat »)
    /// Effectue une requête `HEAD` minimale en HTTPS pour capter le `SecTrust`
    /// serveur via le délégué `CertificateCapturingDelegate`.
    /// Renvoie `nil` si aucun port HTTPS n'est ouvert ou si la connexion échoue.
    func fetchSSLTrust(for ip: String, ports: [Int]) async -> SecTrust? {
        let httpsPorts = [443, 8443].filter { ports.contains($0) }
        guard let port = httpsPorts.first,
              let url = URL(string: "https://\(ip):\(port)/") else { return nil }

        let delegate = CertificateCapturingDelegate()
        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url, timeoutInterval: 3.0)
            request.httpMethod = "HEAD"
            request.setValue("NetGuard/1.0", forHTTPHeaderField: "User-Agent")

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest  = 3
            config.timeoutIntervalForResource = 3
            let session = URLSession(configuration: config,
                                     delegate: delegate,
                                     delegateQueue: nil)

            session.dataTask(with: request) { _, _, _ in
                continuation.resume(returning: delegate.capturedTrust(for: ip))
                session.finishTasksAndInvalidate()   // libère session + delegate
            }.resume()
        }
    }

    // MARK: - HTTP Banner + Title grabbing (+ certificat SSL si HTTPS)
    private struct HTTPInfo {
        var banner: String
        var title: String
        var certificate: CertificateInfo?
        /// Port HTTP en clair (80, 8080, 8888) qui a accepté la connexion puis l'a
        /// fermée sans réponse HTTP. nil sinon — délai dépassé compris.
        var nonWebPort: Int? = nil
    }

    private func grabHTTP(ip: String, ports: [Int]) async -> HTTPInfo {
        // HTTPS prioritaire : sur un NAS qui ouvre 80 + 443, on veut taper
        // l'admin web HTTPS (et capter son certificat) plutôt que HTTP qui
        // se contente d'une redirection.
        let httpPorts = [443, 8443, 80, 8080, 8888].filter { ports.contains($0) }
        guard let port = httpPorts.first else {
            return HTTPInfo(banner: "", title: "", certificate: nil)
        }

        let isHTTPS = (port == 443 || port == 8443)
        let scheme  = isHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(ip):\(port)/") else {
            return HTTPInfo(banner: "", title: "", certificate: nil)
        }

        // Délégué qui accepte tous les certs (réseau local) + capture le SecTrust
        let delegate = CertificateCapturingDelegate()

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url, timeoutInterval: 3.0)
            request.httpMethod = "GET"
            request.setValue("NetGuard/1.0", forHTTPHeaderField: "User-Agent")

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest  = 3
            config.timeoutIntervalForResource = 3
            let session = URLSession(configuration: config,
                                     delegate: delegate,
                                     delegateQueue: nil)

            session.dataTask(with: request) { data, response, error in
                let banner = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Server") ?? ""

                var title = ""
                if let d = data, let html = String(data: d.prefix(512_000), encoding: .utf8) ?? String(data: d.prefix(512_000), encoding: .isoLatin1) {
                    if let r = html.range(of: #"<title[^>]*>([^<]+)</title>"#,
                                          options: [.regularExpression, .caseInsensitive]) {
                        title = String(html[r])
                            .replacingOccurrences(of: #"<title[^>]*>"#, with: "",
                                                  options: .regularExpression)
                            .replacingOccurrences(of: "</title>", with: "",
                                                  options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                // Extraction du certificat si HTTPS et trust capté
                var certificate: CertificateInfo? = nil
                if isHTTPS, let trust = delegate.capturedTrust(for: ip) {
                    certificate = CertificateInspector.inspect(trust: trust)
                }

                // Mesuré : connexion fermée sans réponse → -1005 en ~0,1 s ; appareil
                // lent → -1001 au bout du délai. Seul le premier cas prouve que le
                // service n'est pas un serveur web.
                let closedWithoutResponse = response == nil
                    && (error as? URLError)?.code == .networkConnectionLost

                continuation.resume(returning: HTTPInfo(banner: banner,
                                                        title: title,
                                                        certificate: certificate,
                                                        nonWebPort: !isHTTPS && closedWithoutResponse ? port : nil))
                session.finishTasksAndInvalidate()   // libère session + delegate
            }.resume()
        }
    }
}
