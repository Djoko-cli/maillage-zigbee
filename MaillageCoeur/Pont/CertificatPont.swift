import Foundation
import Security

/// Ce que la verification du certificat d'un pont Hue conclut (`CertificatPont`).
public enum VerdictCertificat: Equatable, Sendable {
    /// Chaine signee par une des racines, et nom commun du sujet = l'identifiant attendu (ou, sans identifiant attendu,
    /// un identifiant de pont valide). `identifiant` : ce nom commun, en majuscules.
    case accepte(identifiant: String)
    /// Chaine qui ne remonte a aucune des racines donnees (autre autorite, certificat expire, chaine incomplete).
    case nonSigne
    /// Certificat auto-signe : un ancien pont (firmware d'avant les certificats de Signify), ou un autre appareil.
    case autoSigne
    /// Chaine valide, mais d'un autre pont que celui attendu (`vu` : son identifiant, en majuscules).
    case autrePont(vu: String)
    /// Chaine valide, mais sans nom commun qui soit un identifiant de pont (16 chiffres hexadecimaux).
    case sansIdentifiant
    /// Chaine valide et identifiant de pont, mais la feuille n'est pas celle d'un serveur TLS : une autorite, ou un
    /// certificat sans l'usage serverAuth (un certificat client d'un autre produit sous la meme racine).
    case pasUnServeur

    public var accepte: Bool {
        if case .accepte = self { return true }
        return false
    }
}

/// Verification du certificat TLS d'un pont Hue (spec de l'app, section 5). Le certificat du pont n'a pas de nom DNS :
/// son sujet a pour nom commun l'identifiant du pont, sans subjectAltName, et il est signe par une des racines de
/// Signify (`RacinesSignify`). Donc :
/// - politique X.509 de base (`SecPolicyCreateBasicX509`) : pas de verification de nom d'hote, il n'y en a pas ;
/// - ancres : les racines donnees, et elles seules (`SecTrustSetAnchorCertificatesOnly`) ; aucun telechargement
///   (intermediaires, revocation) : rien ne sort du reseau local ;
/// - puis le nom commun du **sujet** du certificat feuille (`SecCertificateCopyCommonName`, jamais une lecture du DER a
///   la main), compare sans egard a la casse a l'identifiant attendu ;
/// - et le role de la feuille (`estFeuilleServeur`, par `SecCertificateCopyValues`) : une feuille de serveur TLS, pas
///   une autorite.
/// Tout autre cas est un refus. Fonctions pures : aucun etat, aucun reseau.
public enum CertificatPont {
    /// Verifie une confiance presentee par le serveur (le defi `NSURLAuthenticationMethodServerTrust`). Ses politiques
    /// et ses ancres sont remplacees par les notres avant l'evaluation. `attendu` : l'identifiant du pont (nil : le
    /// premier contact apres une saisie manuelle d'adresse, ou tout identifiant valide est accepte, puis confirme par
    /// l'API). `date` : la date de la verification (nil : maintenant ; les tests la fixent).
    public static func verifier(_ confiance: SecTrust, attendu: String?, racines: [SecCertificate],
                                date: Date? = nil) -> VerdictCertificat {
        guard !racines.isEmpty,
              SecTrustSetPolicies(confiance, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustSetAnchorCertificates(confiance, racines as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(confiance, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(confiance, false) == errSecSuccess
        else { return .nonSigne }
        if let date, SecTrustSetVerifyDate(confiance, date as CFDate) != errSecSuccess { return .nonSigne }
        let valide = SecTrustEvaluateWithError(confiance, nil)
        // Le premier certificat de la chaine est la feuille, celle du serveur, evaluation reussie ou non.
        guard let feuille = (SecTrustCopyCertificateChain(confiance) as? [SecCertificate])?.first else { return .nonSigne }
        guard valide else { return autoSigne(feuille) ? .autoSigne : .nonSigne }
        var nom: CFString?
        guard SecCertificateCopyCommonName(feuille, &nom) == errSecSuccess, let nom,
              let vu = identifiant(nom as String) else { return .sansIdentifiant }
        // Apres le nom commun : une racine presentee comme feuille reste `sansIdentifiant`.
        guard estFeuilleServeur(feuille) else { return .pasUnServeur }
        guard let attendu else { return .accepte(identifiant: vu) }
        guard identifiant(attendu) == vu else { return .autrePont(vu: vu) }
        return .accepte(identifiant: vu)
    }

    /// Verifie une chaine de certificats, la feuille d'abord (les tests, et tout appelant sans `SecTrust`).
    public static func verifier(chaine: [SecCertificate], attendu: String?, racines: [SecCertificate],
                                date: Date? = nil) -> VerdictCertificat {
        var confiance: SecTrust?
        guard !chaine.isEmpty,
              SecTrustCreateWithCertificates(chaine as CFArray, SecPolicyCreateBasicX509(), &confiance) == errSecSuccess,
              let confiance else { return .nonSigne }
        return verifier(confiance, attendu: attendu, racines: racines, date: date)
    }

    /// Un identifiant de pont : 16 chiffres hexadecimaux (en TXT Bonjour, souvent en minuscules ; dans le certificat
    /// du Bridge Pro, en majuscules), rendu en majuscules ; nil pour toute autre chaine.
    public static func identifiant(_ texte: String) -> String? {
        let t = texte.trimmingCharacters(in: .whitespaces)
        guard t.utf8.count == 16, t.utf8.allSatisfy({ $0.estHexa }) else { return nil }
        return t.uppercased()
    }

    /// Une feuille de serveur TLS (relecture de securite, M6) : Extended Key Usage present avec serverAuth
    /// (1.3.6.1.5.5.7.3.1) ; Key Usage avec digitalSignature, sans keyCertSign ni cRLSign ; Basic Constraints sans CA.
    /// Lu par `SecCertificateCopyValues`, sans DER a la main : l'EKU en OID brut et le KU en nombre ne dependent pas de
    /// la langue (seule la valeur « Yes » du Basic Constraints pourrait etre traduite ; le KU attrape deja toute
    /// autorite). Le Bridge Pro (CA:FALSE, Digital Signature, TLS Web Server Authentication) passe.
    static func estFeuilleServeur(_ c: SecCertificate) -> Bool {
        let oids = [kSecOIDKeyUsage, kSecOIDExtendedKeyUsage, kSecOIDBasicConstraints] as CFArray
        guard let v = SecCertificateCopyValues(c, oids, nil) as? [String: [String: Any]] else { return false }
        let serverAuth = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])
        guard let eku = v[kSecOIDExtendedKeyUsage as String]?[kSecPropertyKeyValue as String] as? [Any],
              eku.contains(where: { ($0 as? Data) == serverAuth }) else { return false }
        guard let ku = (v[kSecOIDKeyUsage as String]?[kSecPropertyKeyValue as String] as? NSNumber)?.uint32Value
        else { return false }
        let digitalSignature: UInt32 = 1 << 0, keyCertSign: UInt32 = 1 << 5, cRLSign: UInt32 = 1 << 6
        guard ku & digitalSignature != 0, ku & (keyCertSign | cRLSign) == 0 else { return false }
        if let bc = v[kSecOIDBasicConstraints as String]?[kSecPropertyKeyValue as String] as? [[String: Any]],
           bc.contains(where: { ($0[kSecPropertyKeyLabel as String] as? String) == "Certificate Authority"
                                && ($0[kSecPropertyKeyValue as String] as? String) == "Yes" }) { return false }
        return true
    }

    /// Le certificat est emis par lui-meme (emetteur = sujet, compares sous leur forme normalisee par Security).
    static func autoSigne(_ c: SecCertificate) -> Bool {
        guard let emetteur = SecCertificateCopyNormalizedIssuerSequence(c),
              let sujet = SecCertificateCopyNormalizedSubjectSequence(c) else { return false }
        return (emetteur as Data) == (sujet as Data)
    }
}

extension UInt8 {
    /// Un chiffre hexadecimal ASCII (0-9, a-f, A-F).
    var estHexa: Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(self)
    }
}
