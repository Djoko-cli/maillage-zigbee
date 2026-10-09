import Foundation
import dnssd

/// Resolutions DNS-SD ponctuelles (API dns_sd) : chaque requete est ecoutee
/// pendant une fenetre courte, puis fermee.
enum ResolveurDNSSD {
    /// Cible SRV d'une instance, et son TXT brut.
    struct Cible: Equatable, Sendable {
        /// Hote sans point final ("Apple-TV-4K.local").
        let hote: String
        let port: UInt16
        let txt: Data
    }

    /// Hote, port et TXT d'une instance ; nil sans reponse dans la fenetre.
    static func resoudre(instance: String, type: String, domaine: String = "local.",
                         duree: TimeInterval = 2) async -> Cible? {
        let collecte = Collecte<Cible>()
        let reponses = await collecte.executer(duree: duree) { contexte in
            var ref: DNSServiceRef?
            let erreur = DNSServiceResolve(&ref, 0, 0, instance, type, domaine, { _, _, _, erreur, _, hote, port, longueurTXT, txt, contexte in
                guard erreur == kDNSServiceErr_NoError, let hote, let contexte else { return }
                let collecte = Unmanaged<Collecte<Cible>>.fromOpaque(contexte).takeUnretainedValue()
                let octets = txt.map { Data(bytes: $0, count: Int(longueurTXT)) } ?? Data()
                collecte.ajouter(Cible(hote: ResolveurDNSSD.sansPointFinal(String(cString: hote)),
                                       port: UInt16(bigEndian: port), txt: octets))
                collecte.terminer()
            }, contexte)
            return (erreur, ref)
        }
        return reponses.first
    }

    /// Adresses IPv6 et IPv4 d'un hote, en texte, triees ; vide sans reponse.
    static func adresses(hote: String, duree: TimeInterval = 1.5) async -> [String] {
        let collecte = Collecte<String>()
        let reponses = await collecte.executer(duree: duree) { contexte in
            var ref: DNSServiceRef?
            let protocoles = DNSServiceProtocol(kDNSServiceProtocol_IPv6 | kDNSServiceProtocol_IPv4)
            let erreur = DNSServiceGetAddrInfo(&ref, 0, 0, protocoles, hote, { _, drapeaux, _, erreur, _, adresse, _, contexte in
                guard erreur == kDNSServiceErr_NoError, drapeaux & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
                      let adresse, let contexte else { return }
                let collecte = Unmanaged<Collecte<String>>.fromOpaque(contexte).takeUnretainedValue()
                if let texte = ResolveurDNSSD.texte(adresse) { collecte.ajouter(texte) }
            }, contexte)
            return (erreur, ref)
        }
        return Array(Set(reponses)).sorted()
    }

    static func sansPointFinal(_ hote: String) -> String {
        hote.hasSuffix(".") ? String(hote.dropLast()) : hote
    }

    /// Texte d'une adresse IPv6 (sans zone) ou IPv4.
    static func texte(_ adresse: UnsafePointer<sockaddr>) -> String? {
        var tampon = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let taille = socklen_t(tampon.count)
        switch Int32(adresse.pointee.sa_family) {
        case AF_INET6:
            var a = adresse.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            guard inet_ntop(AF_INET6, &a, &tampon, taille) != nil else { return nil }
        case AF_INET:
            var a = adresse.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet_ntop(AF_INET, &a, &tampon, taille) != nil else { return nil }
        default:
            return nil
        }
        return tampon.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}

/// Reponses d'une requete dns_sd, recues sur une file serie qui lui est propre :
/// tout l'etat n'est touche que sur cette file (d'ou @unchecked Sendable).
private final class Collecte<Resultat: Sendable>: @unchecked Sendable {
    private let file = DispatchQueue(label: "fr.djoko.maillage.zigbee.dnssd")
    private var ref: DNSServiceRef?
    private var reponses: [Resultat] = []
    private var continuation: CheckedContinuation<[Resultat], Never>?
    private var fini = false

    /// Sur la file (rappel de dns_sd).
    func ajouter(_ r: Resultat) { reponses.append(r) }

    /// Lance la requete sur la file et rend les reponses recues pendant `duree`.
    func executer(duree: TimeInterval,
                  demarrer: @escaping @Sendable (UnsafeMutableRawPointer) -> (DNSServiceErrorType, DNSServiceRef?)) async -> [Resultat] {
        await withCheckedContinuation { c in
            file.async {
                self.continuation = c
                let (erreur, ref) = demarrer(Unmanaged.passUnretained(self).toOpaque())
                guard erreur == kDNSServiceErr_NoError, let ref else {
                    self.terminer()
                    return
                }
                self.ref = ref
                DNSServiceSetDispatchQueue(ref, self.file)
                self.file.asyncAfter(deadline: .now() + duree) { self.terminer() }
            }
        }
    }

    /// Sur la file : ferme la requete et rend les reponses (une seule fois).
    func terminer() {
        guard !fini else { return }
        fini = true
        if let ref {
            DNSServiceRefDeallocate(ref)
            self.ref = nil
        }
        continuation?.resume(returning: reponses)
        continuation = nil
    }
}
