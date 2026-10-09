import Foundation
import Testing
@testable import MaillageCoeur

/// Relecture finale, I3 : « appareil disparu » et « appareil revenu » d'apres l'etat de connexion que donne le pont,
/// d'une lecture a l'autre. Valeurs inventees.
@Suite("Suivi des connexions vues par le pont")
struct SuiviConnexionsTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let domicile = "C0FFEEFFFE012345"

    static func appareil(_ k: Int) -> String { String(format: "A0000000000000C%X", k) }

    /// Une lecture a `minutes` : l'appareil k a l'etat `etats[k]` (nil : le pont ne le donne pas).
    static func lecture(_ minutes: Double, _ etats: [Int: ConnexionZigbee?], domicile: String? = domicile) -> NomsMaison {
        NomsMaison(date: t0.addingTimeInterval(minutes * 60), domicile: domicile,
                   accessoires: etats.keys.sorted().map {
                       AccessoireMaison(nom: "Lampe \($0)", ieee: appareil($0), connexion: etats[$0] ?? nil)
                   })
    }

    static func suivre(_ lectures: [NomsMaison]) -> [[Evenement]] {
        var s = SuiviConnexions()
        return lectures.map { s.integrer($0) { "N" + $0.suffix(1) } }
    }

    /// La premiere lecture est un etat initial, meme avec des appareils injoignables : rien.
    @Test func premiereLectureSansEvenement() {
        let ev = Self.suivre([Self.lecture(0, [1: .connecte, 2: .deconnecte, 3: .problemeConnexion])])
        #expect(ev[0].isEmpty)
    }

    /// `connected` puis un etat injoignable (les trois) a deux lectures de suite : « disparu » a la seconde, date de la
    /// premiere, par l'adresse longue ; le retour a `connected` : « revenu ». Un appareil qui reste injoignable ne
    /// redonne rien.
    @Test func disparuPuisRevenu() throws {
        let ev = Self.suivre([
            Self.lecture(0, [1: .connecte, 2: .connecte, 3: .connecte, 4: .connecte]),
            Self.lecture(5, [1: .deconnecte, 2: .problemeConnexion, 3: .entrantSeul, 4: .connecte]),
            Self.lecture(10, [1: .deconnecte, 2: .problemeConnexion, 3: .entrantSeul, 4: .connecte]),
            Self.lecture(15, [1: .connecte, 2: .problemeConnexion, 3: .entrantSeul, 4: .connecte]),
        ])
        #expect(ev[1].isEmpty, "une seule lecture injoignable : pas encore")
        #expect(ev[2].map(\.type) == [.appareilDisparu, .appareilDisparu, .appareilDisparu])
        #expect(ev[2].map { $0.sujet?.id } == [Self.appareil(1), Self.appareil(2), Self.appareil(3)])
        #expect(ev[2].allSatisfy { $0.details["ieee"] == $0.sujet?.id && $0.date == Self.t0.addingTimeInterval(300) })
        #expect(ev[2].first?.sujet?.nom == "N1" && ev[2].first?.gravite == .attention)
        #expect(ev[3].map(\.type) == [.appareilRevenu] && ev[3].first?.sujet?.id == Self.appareil(1))
        // Trois pertes d'une meme lecture : une notification groupee, une ligne du journal.
        var alertes = Alertes()
        let envoyees = alertes.traiter(ev[2])
        #expect(envoyees.map(\.categorie) == [.pertes] && envoyees.first?.evenements.count == 3)
        #expect(Regroupement.lignes(ev[2]).count == 1)
    }

    /// Choix de Majid (09/10) : un decrochage d'une seule lecture, suivi d'un retour a `connected`, ne donne rien.
    @Test func decrochageDUneLectureSansEvenement() {
        let ev = Self.suivre([
            Self.lecture(0, [1: .connecte]),
            Self.lecture(5, [1: .problemeConnexion]),
            Self.lecture(10, [1: .connecte]),
            Self.lecture(15, [1: .deconnecte]),
            Self.lecture(20, [1: .inconnue]),
            Self.lecture(25, [1: .deconnecte]),
        ])
        #expect(ev[1].isEmpty && ev[2].isEmpty && ev[3].isEmpty && ev[4].isEmpty)
        #expect(ev[5].map(\.type) == [.appareilDisparu] && ev[5].first?.date == Self.t0.addingTimeInterval(900),
                "deux lectures injoignables, un etat inconnu entre les deux ne les separe pas")
    }

    /// Un etat absent ou inconnu de l'app ne change rien ; un appareil sorti de la liste n'est plus suivi ; un appareil
    /// injoignable au depart qui se connecte : « revenu ».
    @Test func etatsInconnusEtAppareilsRetires() {
        let ev = Self.suivre([
            Self.lecture(0, [1: .connecte, 2: .connecte, 3: .deconnecte]),
            Self.lecture(5, [1: .inconnue, 2: nil, 3: .deconnecte]),
            Self.lecture(10, [1: .connecte, 2: .connecte, 3: .connecte]),
            Self.lecture(15, [1: .connecte, 3: .connecte]),
            Self.lecture(20, [1: .connecte, 2: .deconnecte, 3: .connecte]),
        ])
        #expect(ev[1].isEmpty && ev[3].isEmpty)
        #expect(ev[2].map(\.type) == [.appareilRevenu] && ev[2].first?.sujet?.id == Self.appareil(3))
        #expect(ev[4].isEmpty, "revenu dans la liste : son etat d'alors, sans evenement")
    }

    /// Un autre pont repart de zero : sa premiere lecture est un etat initial.
    @Test func autrePont() {
        let ev = Self.suivre([Self.lecture(0, [1: .connecte]),
                              Self.lecture(5, [1: .deconnecte], domicile: "C0FFEEFFFE099999"),
                              Self.lecture(10, [1: .connecte], domicile: "C0FFEEFFFE099999")])
        #expect(ev[1].isEmpty && ev[2].map(\.type) == [.appareilRevenu])
    }
}
