import Foundation
import MaillageCoeur

/// Client de l'API du pont Hue (spec de l'app, section 5), sans etat : un pont a une adresse, et son identifiant
/// attendu dans son certificat (nil : premier contact apres une saisie manuelle). Tout passe par le transport injecte,
/// toujours en HTTPS verifie (`TransportURLSession`) ; les tests en simulent un, sans reseau.
struct PontHue: Sendable {
    let transport: any TransportHue
    let adresse: String
    let attendu: String?

    /// Pourquoi une operation n'a pas abouti.
    enum Erreur: Error, Equatable, Sendable {
        case transport(ErreurTransport)
        /// HTTP 401 ou 403 : la cle n'est plus reconnue (l'app a ete retiree dans l'app Hue).
        case cleRefusee
        /// Un autre statut HTTP que 200.
        case http(Int, String)
        /// Reponse illisible (chemin, detail).
        case illisible(String)
        /// L'API donne un autre identifiant que celui du certificat ou de Bonjour.
        case autrePont(vu: String)
        /// Le premier contact n'a pas presente de certificat a verifier.
        case sansCertificat
    }

    /// Les ressources lues, dans l'ordre.
    static let ressources = ["bridge", "device", "zigbee_connectivity", "room", "device_power"]

    /// Premier contact, apres une saisie manuelle d'adresse : une requete sans cle (la reponse, 403 sans doute, est
    /// ignoree) pour lire l'identifiant du pont dans son certificat, la chaine une fois validee.
    func sonder() async throws(Erreur) -> String {
        let r = try await envoyer(.lire("/clip/v2/resource/bridge", cle: nil))
        guard let id = r.identifiantCertificat else { throw .sansCertificat }
        return id
    }

    /// Le corps de la demande de liaison : `devicetype` « maillage_zigbee#<nom du Mac> » (l'API limite le nom de l'app
    /// a 20 caracteres et celui de l'appareil a 19) ; `generateclientkey` comme le veut l'API v2 (le `clientkey` rendu
    /// n'est pas garde).
    static func corpsLiaison(nomMac: String) -> Data {
        let nettoye = nomMac.replacingOccurrences(of: "#", with: " ").trimmingCharacters(in: .whitespaces)
        let appareil = String((nettoye.isEmpty ? "Mac" : nettoye).prefix(19))
        let corps: [String: Any] = ["devicetype": "maillage_zigbee#\(appareil)", "generateclientkey": true]
        return (try? JSONSerialization.data(withJSONObject: corps, options: [.sortedKeys])) ?? Data()
    }

    /// Une demande de liaison : la cle, ou l'attente du bouton.
    func demanderCle(nomMac: String) async throws(Erreur) -> ReponseLiaison {
        let r = try await envoyer(RequeteHue(methode: "POST", chemin: "/api", corps: Self.corpsLiaison(nomMac: nomMac),
                                             cle: nil))
        guard r.statut == 200 else { throw .http(r.statut, "/api") }
        guard let reponse = ReponseLiaison.lire(r.corps) else { throw .illisible("/api") }
        return reponse
    }

    /// Les cinq ressources, lues l'une apres l'autre avec la cle. L'identifiant donne par l'API doit etre celui
    /// attendu (sans egard a la casse).
    func lire(cle: String) async throws(Erreur) -> LectureHue {
        let ponts = try await ressource(ApiHue.Pont.self, "bridge", cle: cle)
        guard let pont = ponts.first else { throw .illisible("bridge") }
        if let attendu, CertificatPont.identifiant(pont.identifiant) != CertificatPont.identifiant(attendu) {
            throw .autrePont(vu: pont.identifiant.uppercased())
        }
        return LectureHue(pont: pont,
                          appareils: try await ressource(ApiHue.Appareil.self, "device", cle: cle),
                          connectivites: try await ressource(ApiHue.Connectivite.self, "zigbee_connectivity", cle: cle),
                          pieces: try await ressource(ApiHue.Piece.self, "room", cle: cle),
                          alimentations: try await ressource(ApiHue.Alimentation.self, "device_power", cle: cle))
    }

    private func ressource<T: Decodable>(_ type: T.Type, _ nom: String, cle: String) async throws(Erreur) -> [T] {
        let chemin = "/clip/v2/resource/\(nom)"
        let r = try await envoyer(.lire(chemin, cle: cle))
        if r.statut == 401 || r.statut == 403 { throw .cleRefusee }
        guard r.statut == 200 else { throw .http(r.statut, chemin) }
        do {
            return try ApiHue.lire(T.self, r.corps)
        } catch {
            switch error {
            case .illisible: throw .illisible(chemin)
            case .erreurs(let d): throw .illisible("\(chemin) : \(d)")
            }
        }
    }

    private func envoyer(_ r: RequeteHue) async throws(Erreur) -> ReponseHue {
        do {
            return try await transport.envoyer(r, adresse: adresse, attendu: attendu)
        } catch {
            throw .transport(error)
        }
    }
}
