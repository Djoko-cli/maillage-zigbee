import Foundation
import Testing
@testable import MaillageCoeur

/// Reponses inventees de l'API v2 du pont Hue (noms, ressources, adresses longues `A0000000000000xx` et identifiant de
/// pont inventes), dans la forme de la documentation publique : un pont, ses quatre appareils (le pont, une lampe,
/// une prise, un detecteur a pile, une telecommande en Wi-Fi sans Zigbee), deux pieces.
enum ReponsesInventees {
    static let pont = """
        {"errors":[],"data":[{"id":"b0000000-0000-4000-8000-0000000000b1","id_v1":"",
         "owner":{"rid":"d0000000-0000-4000-8000-000000000001","rtype":"device"},
         "bridge_id":"c0ffeefffe012345","time_zone":{"time_zone":"Europe/Paris"},"type":"bridge"}]}
        """

    static let appareils = """
        {"errors":[],"data":[
         {"id":"d0000000-0000-4000-8000-000000000001","metadata":{"name":"Pont du salon","archetype":"bridge_v2"},
          "product_data":{"model_id":"BSB002","manufacturer_name":"Signify Netherlands B.V.","product_name":"Hue Bridge",
          "product_archetype":"bridge_v2","certified":true,"software_version":"1.70.1970000000"},
          "services":[{"rid":"c0000000-0000-4000-8000-000000000001","rtype":"zigbee_connectivity"}],"type":"device"},
         {"id":"d0000000-0000-4000-8000-000000000002","metadata":{"name":"Lampe du bureau","archetype":"sultan_bulb"},
          "product_data":{"model_id":"LCA001","manufacturer_name":"Signify Netherlands B.V.","product_name":"Hue color lamp",
          "software_version":"1.122.2"},
          "services":[{"rid":"c0000000-0000-4000-8000-000000000002","rtype":"zigbee_connectivity"}],"type":"device"},
         {"id":"d0000000-0000-4000-8000-000000000003","metadata":{"name":"Prise de la terrasse","archetype":"plug"},
          "product_data":{"model_id":"LOM007","manufacturer_name":"Signify Netherlands B.V.",
          "software_version":"1.122.2"},"services":[],"type":"device"},
         {"id":"d0000000-0000-4000-8000-000000000004","metadata":{"name":"Détecteur de l'entrée","archetype":"unknown_archetype"},
          "product_data":{"model_id":"SML003","manufacturer_name":"Signify Netherlands B.V.","product_name":"Hue motion sensor",
          "software_version":"2.53.6"},"services":[],"type":"device"},
         {"id":"d0000000-0000-4000-8000-000000000005","metadata":{"name":"Télécommande Wi-Fi"},"services":[],"type":"device"},
         {"id":"d0000000-0000-4000-8000-000000000006","type":"device"}
        ]}
        """

    static let connectivites = """
        {"errors":[],"data":[
         {"id":"c0000000-0000-4000-8000-000000000001","owner":{"rid":"d0000000-0000-4000-8000-000000000001","rtype":"device"},
          "status":"connected","mac_address":"a0:00:00:00:00:00:00:01","channel":{"status":"set","value":"channel_25"},
          "extended_pan_id":"a0:00:00:00:00:00:00:ff","type":"zigbee_connectivity"},
         {"id":"c0000000-0000-4000-8000-000000000002","owner":{"rid":"d0000000-0000-4000-8000-000000000002","rtype":"device"},
          "status":"connected","mac_address":"a0:00:00:00:00:00:00:15-0b","type":"zigbee_connectivity"},
         {"id":"c0000000-0000-4000-8000-000000000003","owner":{"rid":"d0000000-0000-4000-8000-000000000003","rtype":"device"},
          "status":"connectivity_issue","mac_address":"A0:00:00:00:00:00:00:18","type":"zigbee_connectivity"},
         {"id":"c0000000-0000-4000-8000-000000000004","owner":{"rid":"d0000000-0000-4000-8000-000000000004","rtype":"device"},
          "status":"tout_nouvel_etat","mac_address":"a0:00:00:00:00:00:00:20","type":"zigbee_connectivity"}
        ]}
        """

    static let pieces = """
        {"errors":[],"data":[
         {"id":"e0000000-0000-4000-8000-000000000001","metadata":{"name":"Bureau","archetype":"office"},
          "children":[{"rid":"d0000000-0000-4000-8000-000000000002","rtype":"device"},
                      {"rid":"d0000000-0000-4000-8000-000000000001","rtype":"device"}],
          "services":[{"rid":"f0000000-0000-4000-8000-000000000001","rtype":"grouped_light"}],"type":"room"},
         {"id":"e0000000-0000-4000-8000-000000000002","metadata":{"name":"Entrée","archetype":"front_door"},
          "children":[{"rid":"d0000000-0000-4000-8000-000000000004","rtype":"device"},
                      {"rid":"x","rtype":"light"}],"type":"room"}
        ]}
        """

    static let alimentations = """
        {"errors":[],"data":[
         {"id":"a1000000-0000-4000-8000-000000000004","owner":{"rid":"d0000000-0000-4000-8000-000000000004","rtype":"device"},
          "power_state":{"battery_state":"low","battery_level":12},"type":"device_power"},
         {"id":"a1000000-0000-4000-8000-000000000003","owner":{"rid":"d0000000-0000-4000-8000-000000000003","rtype":"device"},
          "power_state":{},"type":"device_power"}
        ]}
        """

    static func lecture() throws -> LectureHue {
        LectureHue(pont: try #require(ApiHue.lire(ApiHue.Pont.self, Data(pont.utf8)).first),
                   appareils: try ApiHue.lire(ApiHue.Appareil.self, Data(appareils.utf8)),
                   connectivites: try ApiHue.lire(ApiHue.Connectivite.self, Data(connectivites.utf8)),
                   pieces: try ApiHue.lire(ApiHue.Piece.self, Data(pieces.utf8)),
                   alimentations: try ApiHue.lire(ApiHue.Alimentation.self, Data(alimentations.utf8)))
    }
}

@Suite("API v2 du pont Hue : reponses, adresse longue, noms de la maison")
struct ApiHueTests {
    typealias R = ReponsesInventees

    /// Chaque ressource est lue ; un element illisible (l'appareil sans `metadata`) est ignore.
    @Test func lireLesRessources() throws {
        let l = try R.lecture()
        #expect(l.pont == ApiHue.Pont(identifiant: "c0ffeefffe012345", appareil: "d0000000-0000-4000-8000-000000000001"))
        #expect(l.appareils.count == 5, "le sixieme, sans metadata, est ignore")
        #expect(l.appareils[1].nom == "Lampe du bureau" && l.appareils[1].produit == "Hue color lamp"
                && l.appareils[1].modeleId == "LCA001" && l.appareils[1].logiciel == "1.122.2")
        #expect(l.connectivites.map(\.etat) == ["connected", "connected", "connectivity_issue", "tout_nouvel_etat"])
        #expect(l.pieces.map(\.nom) == ["Bureau", "Entrée"])
        #expect(l.pieces[1].appareils == ["d0000000-0000-4000-8000-000000000004"], "seuls les enfants de type device")
        #expect(l.alimentations[0].batterie == BatterieMaison(niveau: 12, alerte: true))
        #expect(l.alimentations[1].batterie == nil, "sans niveau ni etat : pas de pile")
        #expect(l.appareilDuPont?.produit == "Hue Bridge")
    }

    /// Le reseau du pont (`channel`, `extended_pan_id` de son `zigbee_connectivity`) ; la sonde y est-elle ? Le canal
    /// et l'extended PAN ID se comparent (celui-ci dans les deux ordres des octets) ; rien a comparer : oui.
    @Test func reseauDuPont() throws {
        let n = try R.lecture().noms(date: Date(timeIntervalSince1970: 1_800_000_000))
        let r = try #require(n.reseau)
        #expect(r == ReseauZigbee(canal: 25, epid: "A0000000000000FF"))
        #expect(try NomsMaison.lire(n.donnees()).reseau == r, "garde dans le cache")
        func etat(canal: Int?, epid: String?, membre: Bool = true) -> EtatSonde {
            EtatSonde(membre: membre, epid: epid, canal: canal)
        }
        #expect(r.accueille(etat(canal: 25, epid: "A0000000000000FF")))
        #expect(r.accueille(etat(canal: 25, epid: "FF000000000000A0")), "octets dans l'autre ordre")
        #expect(!r.accueille(etat(canal: 20, epid: "A0000000000000FF")), "autre canal")
        #expect(!r.accueille(etat(canal: 25, epid: "A0000000000000EE")), "autre reseau")
        #expect(r.accueille(etat(canal: nil, epid: nil, membre: false)), "hors du reseau : rien a dire")
        #expect(ReseauZigbee(canal: nil, epid: nil).accueille(etat(canal: 11, epid: "A0000000000000EE")))
        let entier = #"{"errors":[],"data":[{"owner":{"rid":"x","rtype":"device"},"channel":15}]}"#
        #expect(try ApiHue.lire(ApiHue.Connectivite.self, Data(entier.utf8)).first?.canal == 15)
        #expect(try R.lecture().connectivites[1].canal == nil, "une lampe n'a pas de canal")
    }

    /// `mac_address` : 16 hexa majuscules, sans separateurs ni endpoint ; nil sinon.
    @Test func adresseLongue() {
        #expect(ApiHue.adresseLongue("a0:00:00:00:00:00:00:15") == "A000000000000015")
        #expect(ApiHue.adresseLongue("a0:00:00:00:00:00:00:15-0b") == "A000000000000015")
        #expect(ApiHue.adresseLongue("A000000000000015") == "A000000000000015")
        #expect(ApiHue.adresseLongue("a0:00:00:00:00:00:15") == nil, "7 octets")
        #expect(ApiHue.adresseLongue("a0:00:00:00:00:00:00:1g") == nil)
        #expect(ApiHue.adresseLongue("") == nil)
    }

    /// Les noms de la maison : l'identifiant du pont en majuscules ; un appareil par device, le pont compris (son
    /// adresse longue sera celle du coordinateur) ; pieces, piles, etats de connexion (un etat inconnu de l'app est
    /// garde comme tel) ; un appareil sans Zigbee n'a pas d'adresse longue. Pas de zones.
    @Test func nomsDeLaMaison() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let n = try R.lecture().noms(date: date)
        #expect(n.domicile == "C0FFEEFFFE012345" && n.date == date && n.zones == nil)
        #expect(n.accessoires.map(\.nom) == ["Détecteur de l'entrée", "Lampe du bureau", "Pont du salon",
                                             "Prise de la terrasse", "Télécommande Wi-Fi"])
        let pont = try #require(n.accessoire(ieee: "A000000000000001"))
        #expect(pont == AccessoireMaison(nom: "Pont du salon", piece: "Bureau", fabricant: "Signify Netherlands B.V.",
                                         modele: "Hue Bridge", firmware: "1.70.1970000000", categorie: "bridge_v2",
                                         ieee: "A000000000000001", connexion: .connecte, idModele: "BSB002",
                                         idHue: "d0000000-0000-4000-8000-000000000001"))
        #expect(n.accessoires.allSatisfy { $0.idHue != nil }, "l'identifiant du device de chaque appareil, Zigbee ou non")
        #expect(n.accessoire(ieee: "A000000000000015")?.idHue == "d0000000-0000-4000-8000-000000000002")
        #expect(n.accessoire(ieee: "a000000000000015")?.piece == "Bureau")
        let prise = try #require(n.accessoire(ieee: "A000000000000018"))
        #expect(prise.connexion == .problemeConnexion && prise.piece == nil && prise.batterie == nil)
        #expect(prise.modele == "LOM007" && prise.idModele == nil, "sans nom de produit, le code du modele")
        let detecteur = try #require(n.accessoire(ieee: "A000000000000020"))
        #expect(detecteur.connexion == .inconnue && detecteur.piece == "Entrée")
        #expect(detecteur.batterie?.niveau == 12 && detecteur.batterie?.faible == true)
        let wifi = try #require(n.accessoires.last)
        #expect(wifi.ieee == nil && wifi.connexion == nil && wifi.fabricant == nil)
        // Aller-retour du releve garde (le cache) : l'etat de connexion y est.
        #expect(try NomsMaison.lire(n.donnees()) == n)
    }

    /// Un etat de connexion inconnu, relu d'un releve garde : `inconnue`, sans rendre le releve illisible.
    @Test func connexionInconnueRelue() throws {
        let json = #"{"nom":"X","connexion":"etat_futur"}"#
        let a = try JSONDecoder().decode(AccessoireMaison.self, from: Data(json.utf8))
        #expect(a.connexion == .inconnue)
        #expect(ConnexionZigbee.depuis(api: "unidirectional_incoming") == .entrantSeul)
        #expect(ConnexionZigbee.depuis(api: "disconnected") == .deconnecte && ConnexionZigbee.depuis(api: nil) == nil)
    }

    /// Enveloppe : sans `data`, illisible ; `data` vide avec des erreurs, l'erreur ; des erreurs a cote de donnees sont
    /// ignorees.
    @Test func enveloppe() throws {
        #expect(throws: ApiHue.ErreurLecture.illisible) { try ApiHue.lire(ApiHue.Piece.self, Data("{}".utf8)) }
        #expect(throws: ApiHue.ErreurLecture.illisible) { try ApiHue.lire(ApiHue.Piece.self, Data("<html>".utf8)) }
        #expect(throws: ApiHue.ErreurLecture.erreurs("unauthorized user")) {
            try ApiHue.lire(ApiHue.Piece.self, Data(#"{"errors":[{"description":"unauthorized user"}],"data":[]}"#.utf8))
        }
        let pieces = try ApiHue.lire(ApiHue.Piece.self, Data(#"""
            {"errors":[{"description":"x"}],"data":[{"metadata":{"name":"Cuisine"},"children":[]}]}
            """#.utf8))
        #expect(pieces.map(\.nom) == ["Cuisine"])
        #expect(try ApiHue.lire(ApiHue.Piece.self, Data(#"{"data":[]}"#.utf8)).isEmpty)
    }

    /// Reponse a la liaison : attente du bouton (101), cle (seul `username` est garde), autre erreur, illisible. La cle
    /// n'apparait dans aucune description.
    @Test func reponseLiaison() {
        let attente = #"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#
        #expect(ReponseLiaison.lire(Data(attente.utf8)) == .boutonNonAppuye)
        let succes = #"[{"success":{"username":"cle-inventee-0123","clientkey":"CLIENT0123"}}]"#
        let r = ReponseLiaison.lire(Data(succes.utf8))
        #expect(r == .cle("cle-inventee-0123"))
        #expect(!String(describing: r as Any).contains("cle-inventee") && !String(reflecting: r as Any).contains("cle-inventee"))
        let autre = #"[{"error":{"type":7,"description":"invalid value"}}]"#
        #expect(ReponseLiaison.lire(Data(autre.utf8)) == .erreur(type: 7, description: "invalid value"))
        #expect(ReponseLiaison.lire(Data("[]".utf8)) == nil)
        #expect(ReponseLiaison.lire(Data(#"{"a":1}"#.utf8)) == nil)
    }
}
