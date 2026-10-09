import Foundation
import Security
import Synchronization

/// La cle d'application du pont Hue, donnee une fois par l'appui sur son bouton, rangee sous l'identifiant du pont.
/// Repris du trousseau de Maillage Thread. La cle ne quitte le trousseau que pour une requete au pont : jamais dans un
/// journal, une preference ni un fichier.
protocol TrousseauCles: Sendable {
    /// La cle du pont `identifiant` ; `ErreurTrousseau.absente` s'il n'y en a pas.
    func lire(identifiant: String) throws(ErreurTrousseau) -> String
    func ranger(identifiant: String, cle: String) throws(ErreurTrousseau)
    /// Sans erreur si la cle n'y est pas.
    func oublier(identifiant: String) throws(ErreurTrousseau)
}

enum ErreurTrousseau: Error, Equatable, Sendable, LocalizedError {
    case absente(String)
    case systeme(Int32)

    var errorDescription: String? {
        switch self {
        case .absente(let identifiant):
            String(localized: "Clé absente de ce Mac pour le pont \(identifiant) : liez le pont depuis les Réglages.")
        case .systeme(let s):
            String(localized: "Trousseau : \(SecCopyErrorMessageString(s, nil) as String? ?? String(s))")
        }
    }
}

/// Trousseau de session du Mac : mot de passe generique, service `fr.djoko.maillage.zigbee.pont`, compte =
/// identifiant du pont, libelle « Maillage Zigbee - pont Hue <identifiant> », valeur = la cle en UTF-8. Accessible apres
/// le premier deverrouillage, sur ce Mac seulement, jamais synchronise par iCloud. (Dans le trousseau de session de
/// macOS, ou l'app range ses elements, l'accessibilite n'est pas appliquee : l'element suit le verrou du trousseau,
/// ouvert a la connexion ; elle est donnee pour le jour ou l'element irait au trousseau a protection des donnees.)
struct TrousseauSysteme: TrousseauCles {
    let service: String

    init(service: String = "fr.djoko.maillage.zigbee.pont") {
        self.service = service
    }

    private func requete(_ identifiant: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: identifiant,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func lire(identifiant: String) throws(ErreurTrousseau) -> String {
        var q = requete(identifiant)
        q[kSecReturnData as String] = true
        var r: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &r)
        if s == errSecItemNotFound { throw .absente(identifiant) }
        guard s == errSecSuccess else { throw .systeme(s) }
        guard let d = r as? Data, let cle = String(data: d, encoding: .utf8), !cle.isEmpty else {
            throw .systeme(errSecDecode)
        }
        return cle
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseau) {
        let valeurs: [String: Any] = [kSecValueData as String: Data(cle.utf8),
                                      kSecAttrLabel as String: "Maillage Zigbee - pont Hue \(identifiant)",
                                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var s = SecItemUpdate(requete(identifiant) as CFDictionary, valeurs as CFDictionary)
        if s == errSecItemNotFound {
            s = SecItemAdd(requete(identifiant).merging(valeurs) { $1 } as CFDictionary, nil)
        }
        guard s == errSecSuccess else { throw .systeme(s) }
    }

    func oublier(identifiant: String) throws(ErreurTrousseau) {
        let s = SecItemDelete(requete(identifiant) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw .systeme(s) }
    }
}

/// Trousseau en memoire : celui des tests (aucun acces au vrai trousseau).
final class TrousseauMemoire: TrousseauCles {
    private let cles: Mutex<[String: String]>

    init(_ cles: [String: String] = [:]) {
        self.cles = Mutex(cles)
    }

    func lire(identifiant: String) throws(ErreurTrousseau) -> String {
        guard let c = cles.withLock({ $0[identifiant] }) else { throw .absente(identifiant) }
        return c
    }

    func ranger(identifiant: String, cle: String) throws(ErreurTrousseau) {
        cles.withLock { $0[identifiant] = cle }
    }

    func oublier(identifiant: String) throws(ErreurTrousseau) {
        _ = cles.withLock { $0.removeValue(forKey: identifiant) }
    }

    /// Les identifiants qui ont une cle (tests).
    var identifiants: [String] { cles.withLock { $0.keys.sorted() } }
}
