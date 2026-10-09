import Foundation
import MaillageCoeur

/// Decouverte du pont Hue par Bonjour (`_hue._tcp`, sur le reseau local seulement : jamais par le nuage). Chaque
/// instance vue est resolue une fois (hote, puis adresse IPv4 de preference) et donnee a `surPont` avec les champs
/// `bridgeid` et `modelid` de son TXT. `relancer` resout de nouveau les instances vues (le pont a pu changer
/// d'adresse).
@MainActor
final class DecouvertePont {
    static let type = "_hue._tcp"

    /// Un pont resolu.
    var surPont: ((PontDecouvert) -> Void)?
    /// Bonjour est refuse (reseau local refuse a l'app), ou de nouveau permis.
    var surRefus: ((Bool) -> Void)?
    private let navigateur = NavigateurBonjour(type: DecouvertePont.type)
    /// Instance -> TXT deja resolu.
    private var resolues: [String: Data] = [:]

    func demarrer() {
        navigateur.surChangement = { [weak self] in self?.examiner() }
        navigateur.demarrer()
    }

    func arreter() {
        navigateur.arreter()
    }

    /// Resout de nouveau toutes les instances vues.
    func relancer() {
        resolues = [:]
        examiner()
    }

    private func examiner() {
        surRefus?(navigateur.etat == .refuse)
        for (instance, txt) in navigateur.instances where resolues[instance] != txt {
            resolues[instance] = txt
            Task { [weak self] in
                guard let p = await Self.resoudre(instance: instance, txt: txt) else {
                    // Sans reponse : un prochain changement, ou `relancer`, reessaiera.
                    if self?.resolues[instance] == txt { self?.resolues[instance] = nil }
                    return
                }
                self?.surPont?(p)
            }
        }
        resolues = resolues.filter { navigateur.instances[$0.key] != nil }
    }

    /// Hote et TXT de l'instance, puis son adresse : la premiere IPv4, sinon une IPv6 qui n'est pas de lien local,
    /// sinon le nom d'hote s'il est en « .local ». Nil sans reponse, et pour une cible qui n'est pas en « .local » : un
    /// nom public ferait sortir la requete du reseau local (relecture de securite, M5).
    nonisolated static func resoudre(instance: String, txt: Data) async -> PontDecouvert? {
        guard let cible = await ResolveurDNSSD.resoudre(instance: instance, type: type), estLocal(cible.hote) else {
            return nil
        }
        let adresses = await ResolveurDNSSD.adresses(hote: cible.hote)
        let champs = ChampsTXT(brut: cible.txt.isEmpty ? txt : cible.txt)
        return PontDecouvert(adresse: choisirAdresse(adresses) ?? cible.hote, identifiant: champs.texte("bridgeid"),
                             modele: champs.texte("modelid"))
    }

    /// Un nom d'hote du reseau local (mDNS) : « xxxx.local », avec ou sans le point final, sans egard a la casse.
    nonisolated static func estLocal(_ hote: String) -> Bool {
        let h = hote.lowercased()
        let sansPoint = h.hasSuffix(".") ? String(h.dropLast()) : h
        return sansPoint.hasSuffix(".local") && sansPoint.count > ".local".count
    }

    /// La premiere IPv4, sinon la premiere IPv6 hors lien local (fe80::/10).
    nonisolated static func choisirAdresse(_ adresses: [String]) -> String? {
        adresses.first { !$0.contains(":") }
            ?? adresses.first { $0.contains(":") && !$0.lowercased().hasPrefix("fe8") && !$0.lowercased().hasPrefix("fe9")
                && !$0.lowercased().hasPrefix("fea") && !$0.lowercased().hasPrefix("feb") }
    }
}
