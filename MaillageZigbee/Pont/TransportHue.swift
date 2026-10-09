import Foundation
import MaillageCoeur
import Security
import Synchronization

/// Une requete au pont Hue : methode, chemin (« /clip/v2/resource/device »), corps JSON, et la cle d'application a
/// mettre dans l'en-tete `hue-application-key` (nil : sans cle, pour la liaison ou un premier contact).
struct RequeteHue: Equatable, Sendable, CustomStringConvertible {
    var methode: String
    var chemin: String
    var corps: Data?
    var cle: String?

    static func lire(_ chemin: String, cle: String?) -> RequeteHue {
        RequeteHue(methode: "GET", chemin: chemin, corps: nil, cle: cle)
    }

    /// Sans la cle : une requete peut finir dans un message d'erreur ou d'echec de test.
    var description: String { "\(methode) \(chemin)\(cle == nil ? "" : " (avec cle)")" }
}

/// La reponse HTTP du pont, et l'identifiant lu dans son certificat, apres validation de la chaine.
struct ReponseHue: Sendable {
    var statut: Int
    var corps: Data
    /// Toujours donne par `TransportURLSession` ; nil pour un transport simule qui ne le donne pas.
    var identifiantCertificat: String?
}

/// Pourquoi une requete au pont n'a pas abouti.
enum ErreurTransport: Error, Equatable, Sendable {
    /// Certificat refuse (`CertificatPont`) : la connexion a ete coupee avant tout envoi.
    case certificat(VerdictCertificat)
    /// Le pont ne repond pas, ou le reseau manque (description du systeme).
    case reseau(String)
}

/// Le transport HTTPS vers le pont, injectable : URLSession dans l'app, simule dans les tests (aucun reseau).
/// `adresse` : l'IP du pont ; `attendu` : son identifiant, exige dans le certificat (nil : premier contact apres une
/// saisie manuelle, tout pont valide est accepte et son identifiant rendu).
protocol TransportHue: Sendable {
    func envoyer(_ requete: RequeteHue, adresse: String, attendu: String?) async throws(ErreurTransport) -> ReponseHue
}

/// Transport par URLSession, toujours en HTTPS, le certificat verifie par `CertificatPont` contre les seules racines de
/// Signify. Une session ephemere par requete : rien n'est garde (ni cache, ni cookie, ni identifiant), et chaque
/// connexion presente son certificat, verifie a chaque fois.
struct TransportURLSession: TransportHue {
    /// Delai d'une requete : le pont est sur le reseau local.
    var delai: TimeInterval = 8

    func envoyer(_ requete: RequeteHue, adresse: String, attendu: String?) async throws(ErreurTransport) -> ReponseHue {
        guard let url = Self.url(adresse: adresse, chemin: requete.chemin) else {
            throw .reseau(String(localized: "Adresse du pont invalide : \(adresse)"))
        }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: delai)
        r.httpMethod = requete.methode
        r.httpBody = requete.corps
        if requete.corps != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let cle = requete.cle { r.setValue(cle, forHTTPHeaderField: "hue-application-key") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = delai
        config.timeoutIntervalForResource = delai * 2
        config.waitsForConnectivity = false
        config.connectionProxyDictionary = [:]  // le pont est sur le reseau local : jamais par un proxy
        let delegue = DelegueCertificatPont(attendu: attendu)
        let session = URLSession(configuration: config, delegate: delegue, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (corps, reponse) = try await session.data(for: r)
            // Une reponse sans certificat verifie par `CertificatPont` (aucun defi recu) n'est pas lue : jamais de
            // certificat accepte sans verification. Ce controle vient apres l'envoi (relecture de securite, M2) : il
            // protege la lecture, pas la requete. Chaque requete a sa session ephemere, donc sa propre poignee de main,
            // et au banc du 08/10 les lectures successives du vrai pont ont passe : sans defi, elles echoueraient ici.
            guard let id = delegue.verdict?.identifiant else {
                throw ErreurTransport.certificat(delegue.verdict ?? .nonSigne)
            }
            let statut = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            return ReponseHue(statut: statut, corps: corps, identifiantCertificat: id)
        } catch let e as ErreurTransport {
            throw e
        } catch {
            if let v = delegue.verdict, !v.accepte { throw .certificat(v) }
            throw .reseau((error as NSError).localizedDescription)
        }
    }

    /// `https://<adresse><chemin>`, l'adresse IPv6 entre crochets ; nil pour une adresse qui n'en est pas une.
    static func url(adresse: String, chemin: String) -> URL? {
        let a = adresse.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, a.unicodeScalars.allSatisfy({ $0.isASCII }),
              a.allSatisfy({ $0.isLetter || $0.isNumber || ".:-".contains($0) }) else { return nil }
        let hote = a.contains(":") ? "[\(a)]" : a
        return URL(string: "https://\(hote)\(chemin)")
    }
}

extension VerdictCertificat {
    /// L'identifiant d'un verdict accepte.
    var identifiant: String? {
        if case .accepte(let id) = self { return id }
        return nil
    }
}

/// Delegue de la session d'une requete : le seul defi accepte est la confiance du serveur, verifiee par
/// `CertificatPont` contre les racines de Signify et l'identifiant attendu ; tout autre defi, et tout refus, coupe la
/// connexion (`.cancelAuthenticationChallenge`). Le verdict est garde pour l'appelant. Aucune redirection n'est
/// suivie : la cle d'application (en-tete `hue-application-key`) ne part jamais vers une autre adresse ni en HTTP.
final class DelegueCertificatPont: NSObject, URLSessionTaskDelegate, Sendable {
    let attendu: String?
    /// Les ancres : les racines de Signify ; les tests en donnent d'autres, pour suivre le chemin d'acceptation.
    private let racines: @Sendable () -> [SecCertificate]
    private let dernier = Mutex<VerdictCertificat?>(nil)

    init(attendu: String?, racines: @escaping @Sendable () -> [SecCertificate] = { RacinesSignify.certificats() }) {
        self.attendu = attendu
        self.racines = racines
    }

    /// Le verdict du dernier certificat presente ; nil si aucun ne l'a ete.
    var verdict: VerdictCertificat? { dernier.withLock { $0 } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, accreditation) = repondre(methode: challenge.protectionSpace.authenticationMethod,
                                                   confiance: challenge.protectionSpace.serverTrust)
        completionHandler(disposition, accreditation)
    }

    /// La reponse a un defi : la confiance du serveur seule est examinee (`CertificatPont`, contre `racines` et
    /// l'identifiant attendu), et acceptee si le verdict l'est ; tout le reste coupe la connexion.
    func repondre(methode: String, confiance: SecTrust?) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard methode == NSURLAuthenticationMethodServerTrust, let confiance else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let v = CertificatPont.verifier(confiance, attendu: attendu, racines: racines())
        dernier.withLock { $0 = v }
        guard v.accepte else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: confiance))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)  // la reponse de redirection est rendue telle quelle, et traitee comme une erreur
    }
}
