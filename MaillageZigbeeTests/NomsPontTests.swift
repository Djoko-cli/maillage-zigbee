import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Synchronization
import Testing
@testable import MaillageZigbee

/// Un pont Hue simule, derriere le transport : aucun reseau. Identifiant, cle, reponses et pannes inventes ; le
/// certificat est suppose verifie (le transport rend son identifiant), sauf panne de certificat demandee.
final class PontSimule: TransportHue {
    static let identifiant = "C0FFEEFFFE012345"
    static let cle = "cle-inventee-0123"
    static let appareilPont = "d0000000-0000-4000-8000-000000000001"

    struct Appel: Equatable, Sendable {
        var requete: RequeteHue
        var adresse: String
        var attendu: String?
    }

    struct Etat: Sendable {
        var appels: [Appel] = []
        /// Erreurs 101 avant la cle ; nil : le bouton n'est jamais appuye.
        var attentesAvantBouton: Int? = 0
        var cleValide = true
        /// L'identifiant que donne l'API, et celui du certificat.
        var identifiantApi = PontSimule.identifiant
        var identifiantCertificat = PontSimule.identifiant
        /// Un certificat refuse a chaque connexion.
        var refus: VerdictCertificat?
        var reseauCoupe = false
        /// Le statut d'une cle refusee : 403, ou 401.
        var statutCleRefusee = 403
    }

    let etat = Mutex(Etat())
    /// La prochaine requete de cette methode (« POST », « GET ») attend `liberer()` avant de repondre.
    private let retenue = Mutex<(methode: String?, suite: CheckedContinuation<Void, Never>?)>((nil, nil))

    var appels: [Appel] { etat.withLock { $0.appels } }

    func retenir(_ methode: String) { retenue.withLock { $0.methode = methode } }

    /// Une requete est retenue.
    var retient: Bool { retenue.withLock { $0.suite != nil } }

    func liberer() {
        let suite = retenue.withLock { r -> CheckedContinuation<Void, Never>? in
            defer { r.suite = nil }
            return r.suite
        }
        suite?.resume()
    }

    func modifier(_ f: (inout Etat) -> Void) { etat.withLock { f(&$0) } }

    func envoyer(_ requete: RequeteHue, adresse: String, attendu: String?) async throws(ErreurTransport) -> ReponseHue {
        // Pour une demande de liaison : la cle est-elle donnee ? (le bouton, appuye apres `attentesAvantBouton` demandes)
        let (e, cleDonnee) = etat.withLock { e -> (Etat, Bool) in
            e.appels.append(Appel(requete: requete, adresse: adresse, attendu: attendu))
            guard requete.methode == "POST", let n = e.attentesAvantBouton else { return (e, false) }
            if n > 0 { e.attentesAvantBouton = n - 1 }
            return (e, n == 0)
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let libre = retenue.withLock { r -> Bool in
                guard r.methode == requete.methode else { return true }
                r.methode = nil
                r.suite = c
                return false
            }
            if libre { c.resume() }
        }
        if e.reseauCoupe { throw .reseau("coupé") }
        if let v = e.refus { throw .certificat(v) }
        if let attendu, CertificatPont.identifiant(attendu) != e.identifiantCertificat {
            throw .certificat(.autrePont(vu: e.identifiantCertificat))
        }
        func reponse(_ statut: Int, _ corps: String) -> ReponseHue {
            ReponseHue(statut: statut, corps: Data(corps.utf8), identifiantCertificat: e.identifiantCertificat)
        }
        if requete.methode == "POST" && requete.chemin == "/api" {
            guard cleDonnee else {
                return reponse(200, #"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#)
            }
            return reponse(200, #"[{"success":{"username":"\#(Self.cle)","clientkey":"CLIENTINVENTE"}}]"#)
        }
        guard requete.cle == Self.cle, e.cleValide else {
            return reponse(e.statutCleRefusee, #"{"errors":[{"description":"unauthorized user"}],"data":[]}"#)
        }
        let ressource = requete.chemin.replacingOccurrences(of: "/clip/v2/resource/", with: "")
        // « Identifier » : le pont accepte un device qu'il connait, et repond 404 pour un autre.
        if requete.methode == "PUT", ressource.hasPrefix("device/") {
            let device = String(ressource.dropFirst("device/".count))
            guard [Self.appareilPont, "d2", "d3"].contains(device) else {
                return reponse(404, #"{"errors":[{"description":"resource not found"}],"data":[]}"#)
            }
            return reponse(200, #"{"errors":[],"data":[{"rid":"\#(device)","rtype":"device"}]}"#)
        }
        switch ressource {
        case "bridge":
            return reponse(200, #"{"errors":[],"data":[{"id":"b1","owner":{"rid":"\#(Self.appareilPont)","rtype":"device"},"bridge_id":"\#(e.identifiantApi.lowercased())","type":"bridge"}]}"#)
        case "device":
            return reponse(200, #"""
                {"errors":[],"data":[
                 {"id":"\#(Self.appareilPont)","metadata":{"name":"Pont du salon","archetype":"bridge_v2"},
                  "product_data":{"model_id":"BSB002","manufacturer_name":"Signify","product_name":"Hue Bridge"}},
                 {"id":"d2","metadata":{"name":"Lampe du bureau","archetype":"sultan_bulb"},
                  "product_data":{"manufacturer_name":"Signify","product_name":"Hue color lamp"}},
                 {"id":"d3","metadata":{"name":"Détecteur de l'entrée"},"product_data":{"product_name":"Hue motion sensor"}}]}
                """#)
        case "zigbee_connectivity":
            return reponse(200, #"""
                {"errors":[],"data":[
                 {"owner":{"rid":"\#(Self.appareilPont)","rtype":"device"},"status":"connected","mac_address":"a0:00:00:00:00:00:00:01"},
                 {"owner":{"rid":"d2","rtype":"device"},"status":"connected","mac_address":"a0:00:00:00:00:00:00:15"},
                 {"owner":{"rid":"d3","rtype":"device"},"status":"disconnected","mac_address":"a0:00:00:00:00:00:00:20"}]}
                """#)
        case "room":
            return reponse(200, #"{"errors":[],"data":[{"metadata":{"name":"Bureau"},"children":[{"rid":"d2","rtype":"device"}]}]}"#)
        case "device_power":
            return reponse(200, #"{"errors":[],"data":[{"owner":{"rid":"d3","rtype":"device"},"power_state":{"battery_state":"normal","battery_level":80}}]}"#)
        default:
            return reponse(404, "{}")
        }
    }
}

/// Ce que l'attente a vu : chaque duree attendue, et l'etat du pont a ce moment.
@MainActor
final class ReleveAttentes {
    var attentes: [Duration] = []
    /// Combien de requetes le pont avait recues quand chaque attente a commence (meme ordre que `attentes`).
    var appelsAvantAttente: [Int] = []
    var etats: [NomsPont.Etat] = []
    weak var pont: NomsPont?
}

@MainActor
@Suite("Pont Hue : decouverte, liaison, lecture, oubli (transport simule, trousseau en memoire)")
struct NomsPontTests {
    typealias S = PontSimule
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let decouvert = PontDecouvert(adresse: "192.0.2.10", identifiant: "c0ffeefffe012345", modele: "BSB002")

    struct Banc {
        let pont: NomsPont
        let simule: PontSimule
        let trousseau: TrousseauMemoire
        let memoire: MemoireVive
        let cache: URL
        let releve: ReleveAttentes
    }

    /// Un pont et ses dependances simulees : l'attente des 2 s de la liaison est instantanee ; celle des 5 min de la
    /// relecture dure jusqu'a l'annulation (`arreter`).
    func banc(memoire: PontRetenu? = nil, cles: [String: String] = [:], cache: NomsMaison? = nil,
              horloge: (@Sendable () -> Date)? = nil) throws -> Banc {
        let simule = PontSimule()
        let trousseau = TrousseauMemoire(cles)
        let m = MemoireVive(memoire)
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("pont-\(UUID().uuidString)")
        let fichier = dossier.appendingPathComponent("noms-pont.json")
        if let cache {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try cache.donnees().write(to: fichier)
        }
        let releve = ReleveAttentes()
        let date = Self.date
        let d = DependancesPont(transport: simule, trousseau: trousseau, memoire: m, cache: fichier, attendre: { duree in
            await MainActor.run {
                releve.attentes.append(duree)
                releve.appelsAvantAttente.append(simule.appels.count)
                if let p = releve.pont { releve.etats.append(p.etat) }
            }
            if duree > .seconds(NomsPont.pasLiaison) { try await Task.sleep(for: .seconds(3600)) }
            try Task.checkCancellation()
        }, maintenant: horloge ?? { date }, nomMac: "Mac inventé")
        let pont = NomsPont(dependances: d)
        releve.pont = pont
        return Banc(pont: pont, simule: simule, trousseau: trousseau, memoire: m, cache: fichier, releve: releve)
    }

    static let retenu = PontRetenu(adresse: "192.0.2.10", identifiant: S.identifiant, modele: "Hue Bridge", manuel: false)

    /// Bonjour trouve le pont (identifiant du TXT en minuscules) ; « Lier » : deux erreurs 101, puis la cle. La cle,
    /// confirmee par une lecture (meme identifiant), va au trousseau ; le pont est retenu, ses noms lus, gardes sur
    /// disque et passes a la surveillance ; le compte a rebours descend de 2 s en 2 s.
    @Test func liaisonParLeBouton() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.simule.modifier { $0.attentesAvantBouton = 2 }
        var recus: [NomsMaison?] = []
        var lectures: [NomsMaison] = []
        b.pont.surNoms = { recus.append($0) }
        b.pont.surLecture = { lectures.append($0) }
        b.pont.demarrer()
        #expect(b.pont.etat == .introuvable)
        b.pont.pontDecouvert(Self.decouvert)
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant))
        #expect(b.memoire.lire() == PontRetenu(adresse: "192.0.2.10", identifiant: S.identifiant, modele: "BSB002",
                                               manuel: false))
        await b.pont.lier()?.value
        #expect(b.pont.etat == .lie && b.pont.lie)
        #expect(Array(b.releve.etats.prefix(2)) == [.liaisonEnCours(reste: 60), .liaisonEnCours(reste: 58)])
        #expect(b.releve.attentes.filter { $0 == .seconds(2) }.count == 2)
        #expect(b.trousseau.identifiants == [S.identifiant])
        #expect(try b.trousseau.lire(identifiant: S.identifiant) == S.cle)
        #expect(b.memoire.lire()?.modele == "Hue Bridge", "le nom du produit du pont remplace le code du TXT")

        let posts = b.simule.appels.filter { $0.requete.methode == "POST" }
        #expect(posts.count == 3 && posts.allSatisfy { $0.requete.cle == nil && $0.attendu == S.identifiant })
        let corps = try JSONSerialization.jsonObject(with: try #require(posts.first?.requete.corps)) as? [String: Any]
        #expect(corps?["devicetype"] as? String == "maillage_zigbee#Mac inventé")
        #expect(corps?["generateclientkey"] as? Bool == true)
        let gets = b.simule.appels.filter { $0.requete.methode == "GET" }
        #expect(gets.map(\.requete.chemin) == PontHue.ressources.map { "/clip/v2/resource/\($0)" })
        #expect(gets.allSatisfy { $0.requete.cle == S.cle && $0.attendu == S.identifiant && $0.adresse == "192.0.2.10" })
        #expect(!gets.contains { $0.requete.description.contains(S.cle) }, "la cle n'est dans aucune description")

        let noms = try #require(b.pont.noms)
        #expect(noms.domicile == S.identifiant && noms.date == Self.date && noms.accessoires.count == 3)
        #expect(noms.accessoire(ieee: "A000000000000015")?.piece == "Bureau")
        #expect(noms.accessoire(ieee: "A000000000000020")?.connexion == .deconnecte)
        #expect(noms.accessoire(ieee: "A000000000000020")?.batterie?.niveau == 80)
        #expect(recus == [noms])
        #expect(lectures == [noms], "une lecture reussie va au suivi des connexions")
        #expect(try NomsMaison.lire(Data(contentsOf: b.cache)) == noms, "garde sur disque")
    }

    /// Le bouton n'est pas appuye : 30 demandes en 60 s, puis l'abandon ; aucune cle.
    @Test func delaiDeLiaisonDepasse() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.simule.modifier { $0.attentesAvantBouton = nil }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        await b.pont.lier()?.value
        #expect(b.pont.etat == .erreur(String(localized: "Le bouton du pont n'a pas été appuyé dans les 60 secondes.")))
        #expect(b.simule.appels.count == 30 && b.releve.attentes.count == 30)
        #expect(b.releve.etats.last == .liaisonEnCours(reste: 2))
        #expect(b.trousseau.identifiants.isEmpty && !b.pont.lie && b.pont.noms == nil)
        // On peut relancer la liaison.
        b.simule.modifier { $0.attentesAvantBouton = 0 }
        await b.pont.lier()?.value
        #expect(b.pont.etat == .lie)
    }

    /// Un pont lent a repondre : l'horloge borne l'attente a 60 s, quel que soit le nombre de demandes (M10). Ici
    /// chaque lecture de l'horloge avance de 25 s : deux demandes, a 35 s puis 10 s de la limite (au lieu de 60 et 58),
    /// puis l'abandon ; aucune cle.
    @Test func liaisonBorneeParLHorloge() async throws {
        let instant = Mutex(Self.date)
        let b = try banc(horloge: { instant.withLock { $0 = $0.addingTimeInterval(25); return $0 } })
        defer { b.pont.arreter() }
        b.simule.modifier { $0.attentesAvantBouton = nil }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        await b.pont.lier()?.value
        #expect(b.pont.etat == .erreur(String(localized: "Le bouton du pont n'a pas été appuyé dans les 60 secondes.")))
        #expect(b.simule.appels.count == 2)
        #expect(b.releve.etats == [.liaisonEnCours(reste: 35), .liaisonEnCours(reste: 10)])
        #expect(b.trousseau.identifiants.isEmpty && !b.pont.lie)
    }

    /// « Annuler » pendant l'attente : retour a « trouve », sans cle.
    @Test func liaisonAnnulee() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.simule.modifier { $0.attentesAvantBouton = nil }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        let t = b.pont.lier()
        b.pont.annulerLiaison()
        await t?.value
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant))
        #expect(b.simule.appels.count == 1 && b.trousseau.identifiants.isEmpty)
    }

    /// Attend, 5 s au plus, que `condition` soit vraie.
    static func sonder(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Pendant une liaison, « Utiliser cette adresse » est sans effet (relecture de securite de l'etape 2, M3) : ni
    /// requete, ni autre pont ; la liaison finit avec le pont d'avant.
    @Test func adresseIgnoreePendantLaLiaison() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        b.simule.retenir("POST")
        let t = b.pont.lier()
        #expect(await Self.sonder { b.simule.retient })
        #expect(b.pont.liaisonEnCours)
        let avant = b.simule.appels.count
        await b.pont.utiliserAdresse("192.0.2.20")
        #expect(b.simule.appels.count == avant && b.pont.pont?.adresse == "192.0.2.10" && b.pont.liaisonEnCours)
        b.simule.liberer()
        await t?.value
        #expect(b.pont.etat == .lie && b.trousseau.identifiants == [S.identifiant])
    }

    /// La liaison annulee pendant la lecture qui confirme la cle : la cle n'est pas gardee, retour a « trouve ».
    @Test func cleNonGardeeApresAnnulation() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        b.simule.retenir("GET")
        let t = b.pont.lier()
        #expect(await Self.sonder { b.simule.retient })
        b.pont.annulerLiaison()
        b.simule.liberer()
        await t?.value
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant))
        #expect(b.trousseau.identifiants.isEmpty && !b.pont.lie)
    }

    /// Le pont oublie pendant une liaison, puis relie : l'ancienne liaison, qui finit apres, ne touche plus a rien (ni
    /// l'etat de la nouvelle, ni le trousseau, ni sa tache) ; la cle est rangee une fois, sous l'identifiant du pont.
    @Test func ancienneLiaisonSansEffet() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        b.simule.retenir("POST")
        let ancienne = b.pont.lier()
        #expect(await Self.sonder { b.simule.retient })
        b.pont.oublier()
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant), "toujours vu par Bonjour")
        let nouvelle = b.pont.lier()
        #expect(nouvelle != nil, "l'oubli a libere la liaison")
        await nouvelle?.value
        #expect(b.pont.etat == .lie && b.trousseau.identifiants == [S.identifiant])
        b.simule.liberer()
        await ancienne?.value
        #expect(b.pont.etat == .lie && b.pont.lie && b.pont.tacheLiaison == nil)
        #expect(b.trousseau.identifiants == [S.identifiant])
    }

    /// Le pont refuse la cle (HTTP 403 : l'app retiree dans l'app Hue) : la cle sort du trousseau, le pont est a relier.
    @Test func cleRefuseeARelier() async throws {
        let b = try banc(memoire: Self.retenu, cles: [S.identifiant: S.cle])
        defer { b.pont.arreter() }
        b.simule.modifier { $0.cleValide = false }
        b.pont.demarrer()
        #expect(b.pont.etat == .lie, "la cle est au trousseau : le pont est lu au lancement")
        await b.pont.tacheLecture?.value
        #expect(b.pont.etat == .aLier && !b.pont.lie)
        #expect(b.trousseau.identifiants.isEmpty)
        #expect(b.pont.pont == Self.retenu, "le pont reste retenu, a relier")
        b.simule.modifier { $0.cleValide = true }
        await b.pont.lier()?.value
        #expect(b.pont.etat == .lie && b.trousseau.identifiants == [S.identifiant])
    }

    /// Relecture finale, M11 : une lecture partie avec une ancienne cle revient refusee (403) apres qu'une nouvelle
    /// liaison a range une autre cle : la nouvelle cle reste au trousseau.
    @Test func refusDUneAncienneCleApresUneNouvelleLiaison() async throws {
        let b = try banc(memoire: Self.retenu, cles: [S.identifiant: "cle-ancienne-inventee"])
        defer { b.pont.arreter() }
        b.simule.retenir("GET")
        b.pont.demarrer()
        #expect(await Self.sonder { b.simule.retient })
        try b.trousseau.ranger(identifiant: S.identifiant, cle: S.cle)
        b.simule.liberer()
        await b.pont.tacheLecture?.value
        #expect(try b.trousseau.lire(identifiant: S.identifiant) == S.cle, "la nouvelle cle reste")
    }

    /// Demarrage sans reseau : les noms gardes sur disque sont la tout de suite ; la lecture echoue, la cle reste, la
    /// decouverte est relancee. Un releve garde d'un autre pont est ignore.
    @Test func demarrageSansReseau() async throws {
        let garde = NomsMaison(date: Self.date, domicile: S.identifiant, accessoires: [AccessoireMaison(nom: "Lampe")])
        let b = try banc(memoire: Self.retenu, cles: [S.identifiant: S.cle], cache: garde)
        defer { b.pont.arreter() }
        b.simule.modifier { $0.reseauCoupe = true }
        var recus: [NomsMaison?] = []
        var relances = 0
        var lectures = 0
        b.pont.surNoms = { recus.append($0) }
        b.pont.surLecture = { _ in lectures += 1 }
        b.pont.surEchecReseau = { relances += 1 }
        b.pont.demarrer()
        #expect(b.pont.noms == garde && recus == [garde])
        await b.pont.tacheLecture?.value
        let coupe = "coupé"
        #expect(b.pont.etat == .erreur(String(localized: "Pont injoignable : \(coupe)")), "meme cle que l'app : traduite en anglais aussi")
        #expect(b.pont.lie && b.trousseau.identifiants == [S.identifiant] && relances == 1)
        #expect(lectures == 0, "ni le cache ni une lecture echouee ne vont au suivi des connexions")
        #expect(b.pont.noms == garde)

        var autre = garde
        autre.domicile = "C0FFEEFFFE099999"
        let c = try banc(memoire: Self.retenu, cache: autre)
        c.pont.demarrer()
        #expect(c.pont.noms == nil, "le releve d'un autre pont")
        #expect(c.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant), "sans cle : a lier")
    }

    /// Le certificat refuse a la lecture : erreur, la cle reste, la decouverte est relancee.
    @Test func certificatRefuseALaLecture() async throws {
        let b = try banc(memoire: Self.retenu, cles: [S.identifiant: S.cle])
        defer { b.pont.arreter() }
        b.simule.modifier { $0.identifiantCertificat = "C0FFEEFFFE099999" }
        var relances = 0
        b.pont.surEchecReseau = { relances += 1 }
        b.pont.demarrer()
        await b.pont.tacheLecture?.value
        #expect(b.pont.etat == .erreur(NomsPont.message(VerdictCertificat.autrePont(vu: "C0FFEEFFFE099999"))))
        #expect(b.pont.lie && b.trousseau.identifiants == [S.identifiant] && b.pont.noms == nil)
        #expect(relances == 1, "la decouverte est relancee : l'ancienne adresse a pu passer a une autre machine (M4)")
    }

    /// Saisie manuelle : un premier contact sans cle ni identifiant attendu lit l'identifiant dans le certificat ; il
    /// est exige ensuite. Si l'API donne un autre identifiant apres la liaison, la cle n'est pas gardee.
    @Test func adresseManuelle() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.pont.demarrer()
        await b.pont.utiliserAdresse(" 192.0.2.20 ")
        let premier = try #require(b.simule.appels.first)
        #expect(premier == PontSimule.Appel(requete: .lire("/clip/v2/resource/bridge", cle: nil), adresse: "192.0.2.20",
                                            attendu: nil))
        #expect(b.pont.pont == PontRetenu(adresse: "192.0.2.20", identifiant: S.identifiant, modele: nil, manuel: true))
        #expect(b.pont.etat == .trouve(ip: "192.0.2.20", identifiant: S.identifiant))
        #expect(b.memoire.lire() == b.pont.pont)

        b.simule.modifier { $0.identifiantApi = "C0FFEEFFFE099999" }
        await b.pont.lier()?.value
        #expect(b.pont.etat == .erreur(NomsPont.message(PontHue.Erreur.autrePont(vu: "C0FFEEFFFE099999"))))
        #expect(b.trousseau.identifiants.isEmpty && !b.pont.lie)
        #expect(b.simule.appels.dropFirst().allSatisfy { $0.attendu == S.identifiant }, "l'identifiant est exige")
    }

    /// Saisie manuelle refusee : adresse invalide (aucune requete), ancien pont au certificat auto-signe, autre
    /// autorite ; et un autre pont quand un pont est deja lie.
    @Test func adresseManuelleRefusee() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        b.pont.demarrer()
        await b.pont.utiliserAdresse("pont du salon")
        let saisie = "pont du salon"
        #expect(b.pont.etat == .erreur(String(localized: "Adresse invalide : \(saisie)")) && b.simule.appels.isEmpty)
        b.simule.modifier { $0.refus = .autoSigne }
        await b.pont.utiliserAdresse("192.0.2.30")
        #expect(b.pont.etat == .erreur(NomsPont.message(.autoSigne)) && b.pont.pont == nil)
        #expect(NomsPont.message(.autoSigne) == String(localized: "Pont trop ancien : son certificat est auto-signé, ce que l'app ne prend pas en charge."))
        b.simule.modifier { $0.refus = .nonSigne }
        await b.pont.utiliserAdresse("192.0.2.30")
        #expect(b.pont.etat == .erreur(NomsPont.message(.nonSigne)) && b.pont.pont == nil)

        let c = try banc(memoire: Self.retenu, cles: [S.identifiant: S.cle])
        defer { c.pont.arreter() }
        c.pont.demarrer()
        await c.pont.tacheLecture?.value
        c.simule.modifier { $0.identifiantCertificat = "C0FFEEFFFE099999" }
        await c.pont.utiliserAdresse("192.0.2.40")
        #expect(c.pont.etat == .erreur(String(localized: "Un autre pont (\(S.identifiant)) est déjà lié : oubliez-le d'abord.")))
        #expect(c.pont.pont == Self.retenu && c.trousseau.identifiants == [S.identifiant])
    }

    /// Bonjour : le pont retenu suit son adresse ; un autre pont est ignore ; un TXT sans identifiant ne retient rien.
    @Test func decouverte() throws {
        let b = try banc()
        b.pont.demarrer()
        b.pont.pontDecouvert(PontDecouvert(adresse: "192.0.2.50", identifiant: nil, modele: nil))
        #expect(b.pont.pont == nil && b.pont.etat == .introuvable)
        b.pont.pontDecouvert(Self.decouvert)
        b.pont.pontDecouvert(PontDecouvert(adresse: "192.0.2.11", identifiant: "C0FFEEFFFE012345", modele: "BSB002"))
        #expect(b.pont.etat == .trouve(ip: "192.0.2.11", identifiant: S.identifiant))
        #expect(b.memoire.lire()?.adresse == "192.0.2.11")
        b.pont.pontDecouvert(PontDecouvert(adresse: "192.0.2.12", identifiant: "C0FFEEFFFE099999", modele: "BSB002"))
        #expect(b.pont.pont?.identifiant == S.identifiant && b.pont.pont?.adresse == "192.0.2.11")
    }

    /// « Oublier le pont » : la cle sort du trousseau, le pont des preferences, ses noms du disque et de la vue ; le
    /// pont encore vu par Bonjour est retenu de nouveau, a lier.
    @Test func oublier() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        var recus: [NomsMaison?] = []
        b.pont.surNoms = { recus.append($0) }
        b.pont.demarrer()
        b.pont.pontDecouvert(Self.decouvert)
        await b.pont.lier()?.value
        #expect(b.pont.etat == .lie && FileManager.default.fileExists(atPath: b.cache.path))
        b.pont.oublier()
        #expect(b.trousseau.identifiants.isEmpty && b.pont.noms == nil && recus.last == .some(nil))
        #expect(!FileManager.default.fileExists(atPath: b.cache.path))
        #expect(b.pont.etat == .trouve(ip: "192.0.2.10", identifiant: S.identifiant) && !b.pont.lie)
        #expect(b.memoire.lire()?.identifiant == S.identifiant, "retenu de nouveau, sans cle")
    }

    /// Inerte (demo, tests des vues) : rien ne demarre, rien ne se lie.
    @Test func inerte() {
        let p = NomsPont(noms: NomsDemo.maison)
        p.demarrer()
        #expect(p.lier() == nil && p.etat == .introuvable && p.noms == NomsDemo.maison)
        p.pontDecouvert(Self.decouvert)
        #expect(p.pont == nil)
    }

    /// Le corps de la liaison : le nom du Mac, sans « # », coupe a 19 caracteres ; `generateclientkey`.
    @Test func corpsDeLiaison() throws {
        func devicetype(_ nom: String) throws -> String? {
            try (JSONSerialization.jsonObject(with: PontHue.corpsLiaison(nomMac: nom)) as? [String: Any])?["devicetype"]
                as? String
        }
        #expect(try devicetype("MacBook Pro de Camille") == "maillage_zigbee#MacBook Pro de Cami")
        #expect(try devicetype("Mac#1") == "maillage_zigbee#Mac 1")
        #expect(try devicetype("  ") == "maillage_zigbee#Mac")
    }

    /// L'URL du pont : toujours en HTTPS ; IPv6 entre crochets ; rien pour une adresse qui n'en est pas une.
    @Test func urlDuPont() {
        #expect(TransportURLSession.url(adresse: "192.0.2.10", chemin: "/api")?.absoluteString == "https://192.0.2.10/api")
        #expect(TransportURLSession.url(adresse: "2001:db8::1", chemin: "/api")?.absoluteString == "https://[2001:db8::1]/api")
        #expect(TransportURLSession.url(adresse: "pont-inventé.local", chemin: "/api") == nil)
        #expect(TransportURLSession.url(adresse: "pont.local", chemin: "/api")?.host() == "pont.local")
        #expect(TransportURLSession.url(adresse: "192.0.2.10/x", chemin: "/api") == nil)
        #expect(TransportURLSession.url(adresse: "", chemin: "/api") == nil)
    }

    /// Le delegue de la session refuse tout autre defi que la confiance du serveur (mot de passe, certificat client),
    /// et une confiance sans `SecTrust` ; aucun verdict n'est alors rendu.
    @Test func delegueRefuseLesAutresDefis() async {
        final class Expediteur: NSObject, URLAuthenticationChallengeSender {
            func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
            func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
            func cancel(_ challenge: URLAuthenticationChallenge) {}
        }
        let delegue = DelegueCertificatPont(attendu: S.identifiant)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for methode in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate,
                        NSURLAuthenticationMethodServerTrust] {
            let espace = URLProtectionSpace(host: "192.0.2.10", port: 443, protocol: "https", realm: nil,
                                            authenticationMethod: methode)
            let defi = URLAuthenticationChallenge(protectionSpace: espace, proposedCredential: nil, previousFailureCount: 0,
                                                  failureResponse: nil, error: nil, sender: Expediteur())
            let reponse = await withCheckedContinuation { c in
                delegue.urlSession(session, didReceive: defi) { disposition, cred in c.resume(returning: (disposition, cred)) }
            }
            #expect(reponse.0 == .cancelAuthenticationChallenge && reponse.1 == nil, "\(methode)")
        }
        #expect(delegue.verdict == nil)
    }

    /// Le chemin d'acceptation du delegue : la confiance d'un faux pont signe par une fausse autorite (copies de
    /// `FauxCertificats` des tests du coeur), cette autorite en ancre : `.useCredential` avec la confiance, et le
    /// verdict garde. Avec les racines de Signify (le delegue de l'app) : refuse. Un autre identifiant attendu : refuse.
    @Test func delegueAccepteUnPontSigne() throws {
        func certificat(_ b: String) throws -> SecCertificate {
            let der = try #require(Data(base64Encoded: b))
            return try #require(SecCertificateCreateWithData(nil, der as CFData))
        }
        let autorite = try certificat("""
        MIIB1jCCAXygAwIBAgIULjj/GlpJcTIKKNsd79oKqniJC28wCgYIKoZIzj0EAwIwSDELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTAgFw0yNjEwMDgwNjIxMzRaGA8yMTI2MDkxNDA2MjEzNFowSDELMAkGA1UEBhMC\
        RlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTBZMBMGByqGSM49AgEGCCqGSM49AwEH\
        A0IABGBT9Pe1LAtVQg4EKMhK3ukqjk+AJ+S5gRZ8gZVhlcTTz5+GI6uW2aXEcUNUUOCGUDfvDkHDqKu9hKzc2rQrmIajQjBAMA8GA1UdEwEB/wQF\
        MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSQPrCsYvcasV78JTWSCXz6P2N3dDAKBggqhkjOPQQDAgNIADBFAiB00+jNSAlpnKXWGJsC\
        13KJKBfbhzcmN2zxi/zosjpYGAIhAPXqUURQ9B3Tb+S2lmox1EhwETy1gc/RKkzG3aY3EhQO
        """)
        let faux = try certificat("""
        MIICADCCAaagAwIBAgIUfroxklfE3Xddk+Txi42cx/7B0CkwCgYIKoZIzj0EAwIwSDELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTAgFw0yNjEwMDgwNjIxNDJaGA8yMTI2MDkxNDA2MjE0MlowPzELMAkGA1UEBhMC\
        RlIxFTATBgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABGlourwn\
        rPz1fTJ1HbF7+H+mx8Je1yAJcSwzRDRyQYjoaajBwFROiVc6fJEFI1IHGxKk4VXF3e/ZpU1geWmAfmujdTBzMAwGA1UdEwEB/wQCMAAwDgYDVR0P\
        AQH/BAQDAgOIMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBRM4/cv+4OaJuARiT0MHjQ4qLQPWDAfBgNVHSMEGDAWgBSQPrCsYvcasV78\
        JTWSCXz6P2N3dDAKBggqhkjOPQQDAgNIADBFAiB3iV5plyGWKWpd6rvMcMd2aKDx6vTYl4vKVsugerjTNQIhAJg0UBXC/P5afe4ThWQE11qV+PEh\
        MhasnW4KCC5FCmxV
        """)
        func confiance() throws -> SecTrust {
            var t: SecTrust?
            #expect(SecTrustCreateWithCertificates([faux] as CFArray, SecPolicyCreateBasicX509(), &t) == errSecSuccess)
            return try #require(t)
        }
        let delegue = DelegueCertificatPont(attendu: "c0ffeefffe012345", racines: { [autorite] })
        let (disposition, accreditation) = delegue.repondre(methode: NSURLAuthenticationMethodServerTrust,
                                                            confiance: try confiance())
        #expect(disposition == .useCredential && accreditation != nil)
        #expect(delegue.verdict == .accepte(identifiant: S.identifiant))
        let signify = DelegueCertificatPont(attendu: S.identifiant)
        #expect(signify.repondre(methode: NSURLAuthenticationMethodServerTrust, confiance: try confiance()).0
                == .cancelAuthenticationChallenge)
        #expect(signify.verdict == .nonSigne)
        let autre = DelegueCertificatPont(attendu: "C0FFEEFFFE099999", racines: { [autorite] })
        #expect(autre.repondre(methode: NSURLAuthenticationMethodServerTrust, confiance: try confiance()).0
                == .cancelAuthenticationChallenge)
        #expect(autre.verdict == .autrePont(vu: S.identifiant))
        #expect(delegue.repondre(methode: NSURLAuthenticationMethodServerTrust, confiance: nil).0
                == .cancelAuthenticationChallenge, "un defi sans confiance")
    }

    /// L'adresse retenue d'un pont vu par Bonjour : IPv4 d'abord, puis IPv6 hors lien local ; sa cible en « .local ».
    @Test func adresseBonjour() {
        #expect(DecouvertePont.choisirAdresse(["2001:db8::1", "192.0.2.10"]) == "192.0.2.10")
        #expect(DecouvertePont.choisirAdresse(["fe80::1", "2001:db8::1"]) == "2001:db8::1")
        #expect(DecouvertePont.choisirAdresse(["fe80::1"]) == nil)
        // La cible de l'annonce : un nom du reseau local seulement (M5).
        #expect(DecouvertePont.estLocal("Hue-Bridge-012345.local."))
        #expect(DecouvertePont.estLocal("pont.local"))
        #expect(!DecouvertePont.estLocal("pont.example.com."))
        #expect(!DecouvertePont.estLocal("local") && !DecouvertePont.estLocal(".local.") && !DecouvertePont.estLocal(""))
        #expect(!DecouvertePont.estLocal("pont.local.example.com"))
    }

    /// La page Reglages › Pont Hue se construit dans chaque etat ; elle grandit quand un pont est trouve, puis lu.
    @Test func pageDesReglages() async throws {
        let b = try banc()
        defer { b.pont.arreter() }
        func taille() -> CGSize {
            NSHostingView(rootView: Form { ReglagesPont() }.formStyle(.grouped).frame(width: 560)
                .fixedSize(horizontal: false, vertical: true).environment(b.pont)).fittingSize
        }
        b.pont.demarrer()
        let vide = taille()
        b.pont.pontDecouvert(Self.decouvert)
        let trouve = taille()
        await b.pont.lier()?.value
        let lu = taille()
        b.pont.oublier()
        b.simule.modifier { $0.refus = .autoSigne }
        await b.pont.utiliserAdresse("192.0.2.30")
        _ = taille()
        #expect(vide.height > 0 && trouve.height > vide.height && lu.height > vide.height)
    }

    /// Les textes de l'etat (Reglages) et la ligne du menu.
    @Test func textes() {
        #expect(ReglagesPont.texteEtat(.lie, lie: true, lecture: true) == String(localized: "lié · lecture…"))
        #expect(ReglagesPont.texteEtat(.erreur("x"), lie: true, lecture: false) == String(localized: "lié · erreur"))
        #expect(ReglagesPont.message(.erreur("x")) == "x" && ReglagesPont.message(.lie) == nil)
        #expect(MenuBarre.lignePont(.lie, lie: true) == nil)
        #expect(MenuBarre.lignePont(.trouve(ip: "192.0.2.10", identifiant: S.identifiant), lie: false)
                == String(localized: "Pont Hue non lié"))
        #expect(MenuBarre.lignePont(.erreur("x"), lie: true) == String(localized: "Pont Hue : erreur (voir les Réglages)"))
        for v in [VerdictCertificat.nonSigne, .autoSigne, .autrePont(vu: S.identifiant), .sansIdentifiant, .pasUnServeur] {
            #expect(!NomsPont.message(v).isEmpty)
        }
    }
}
