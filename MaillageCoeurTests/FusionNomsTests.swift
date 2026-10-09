import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Noms du pont Hue et releve de Maison reunis")
struct FusionNomsTests {
    typealias I = NomsDemo.Ieee
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let signify = "Signify Netherlands B.V."

    /// Un appareil du pont, d'une adresse longue inventee.
    static func hue(_ nom: String, _ piece: String?, modele: String? = "Hue White", idModele: String? = nil,
                    ieee: String) -> AccessoireMaison {
        AccessoireMaison(nom: nom, piece: piece, fabricant: signify, modele: modele, firmware: "1.0",
                         ieee: ieee, batterie: BatterieMaison(niveau: 40), connexion: .connecte, idModele: idModele)
    }

    /// Un accessoire de Maison, de Signify par defaut.
    static func maison(_ nom: String, _ piece: String?, modele: String? = "Hue White",
                       fabricant: String? = signify, noeud: String? = nil, pont: Bool? = nil) -> AccessoireReleve {
        AccessoireReleve(nom: nom, piece: piece, fabricant: fabricant, modele: modele, noeudMatter: noeud, pont: pont)
    }

    static func pont(_ a: [AccessoireMaison]) -> NomsMaison {
        NomsMaison(date: date, domicile: "C0FFEEFFFE012345", accessoires: a,
                   reseau: ReseauZigbee(canal: 25, epid: nil))
    }

    static func releve(_ a: [AccessoireReleve], zones: [ZoneMaison]? = nil,
                       domicile: String? = "Maison inventée") -> ReleveMaison {
        ReleveMaison(date: date.addingTimeInterval(-3600), domicile: domicile, accessoires: a, zones: zones)
    }

    /// Le nom de Maison de chaque appareil du pont apparie, par adresse longue ; « - » s'il garde celui de l'app Hue.
    static func noms(_ p: [AccessoireMaison], _ m: [AccessoireReleve]) -> [String: String] {
        let paires = FusionNoms.apparier(pont: p, maison: m)
        return Dictionary(uniqueKeysWithValues: p.indices.map { i in (p[i].ieee ?? "", paires[i].map { m[$0].nom } ?? "-") })
    }

    /// Normalisation : casse, accents, espaces (aux bords, doubles, insecables), apostrophes typographiques.
    @Test func normalisation() {
        #expect(FusionNoms.normaliser("  Lampe   CHAMBRE ") == "lampe chambre")
        #expect(FusionNoms.normaliser("Détecteur entrée") == FusionNoms.normaliser("detecteur ENTREE"))
        #expect(FusionNoms.normaliser("Lampe\u{00A0}salon") == "lampe salon")
        #expect(FusionNoms.normaliser("Chambre d\u{2019}amis") == FusionNoms.normaliser("chambre d'amis"))
        #expect(FusionNoms.normaliser("Lampe 1") != FusionNoms.normaliser("Lampe 2"))
        #expect(FusionNoms.normaliser("   ").isEmpty)
    }

    /// Nom exact, puis a la normalisation pres : le nom et la piece de Maison ; adresse longue, connexion, pile,
    /// fabricant et modele du pont.
    @Test func parLeNom() throws {
        let p = [Self.hue("Lampe bureau", "Bureau", ieee: "A0000000000000B1"),
                 Self.hue("detecteur  ENTREE", "Entree", modele: "Hue motion sensor", ieee: "A0000000000000B2")]
        let m = [Self.maison("Lampe bureau", "Bureau de Djoko"),
                 Self.maison("Détecteur entrée", "Hall", modele: "SML001")]
        let r = FusionNoms.fusionner(pont: Self.pont(p), maison: Self.releve(m))
        let n = try #require(r.noms)
        let lampe = try #require(n.accessoire(ieee: "A0000000000000B1"))
        #expect(lampe.nom == "Lampe bureau" && lampe.piece == "Bureau de Djoko" && lampe.origine == .maison)
        #expect(lampe.connexion == .connecte && lampe.batterie == BatterieMaison(niveau: 40) && lampe.firmware == "1.0")
        #expect(lampe.fabricant == Self.signify && lampe.modele == "Hue White")
        let detecteur = try #require(n.accessoire(ieee: "A0000000000000B2"))
        #expect(detecteur.nom == "Détecteur entrée" && detecteur.piece == "Hall" && detecteur.origine == .maison)
        #expect(r.bilan == FusionNoms.Bilan(apparies: 2, nonApparies: 0))
        #expect(n.date == Self.date && n.reseau?.canal == 25, "la date et le reseau du pont")
    }

    /// A defaut du nom : la piece et le modele, par le nom du produit ou par son code ; un seul candidat.
    @Test func parPieceEtModele() {
        let p = [Self.hue("Suspension cuisine", "Cuisine", ieee: "A0000000000000C1"),
                 Self.hue("Lampe 3", "Salon", modele: "Hue color lamp", idModele: "LCA001", ieee: "A0000000000000C2"),
                 Self.hue("Ruban", "Cuisine", modele: "Hue Lightstrip", ieee: "A0000000000000C3")]
        let m = [Self.maison("Suspension de l'îlot", "cuisine"),
                 Self.maison("Lampadaire", "Salon", modele: "LCA001"),
                 Self.maison("Ruban sous meuble", "Cuisine", modele: "Hue Lightstrip Plus")]
        #expect(Self.noms(p, m) == ["A0000000000000C1": "Suspension de l'îlot", "A0000000000000C2": "Lampadaire",
                                    "A0000000000000C3": "-"], "le ruban : autre modele")
    }

    /// Jamais d'appariement ambigu : deux candidats du meme nom (ou de la meme piece et du meme modele) pour un
    /// appareil, ou un candidat pour deux appareils, et personne n'est apparie a cette etape. La piece et le modele
    /// peuvent lever l'ambiguite d'un nom.
    @Test func ambiguite() {
        // Deux « Lampe » dans Maison, une seule dans le pont, et rien pour les departager.
        #expect(Self.noms([Self.hue("Lampe", nil, ieee: "A0000000000000D1")],
                          [Self.maison("Lampe", "Salon"), Self.maison("lampe", "Chambre")])
                == ["A0000000000000D1": "-"])
        // Les memes, departagees par la piece et le modele.
        #expect(Self.noms([Self.hue("Lampe", "Chambre", ieee: "A0000000000000D2")],
                          [Self.maison("Lampe", "Salon"), Self.maison("Lampe", "Chambre")])
                == ["A0000000000000D2": "Lampe"])
        // Deux appareils du pont du meme nom, un seul accessoire : aucun par le nom ; la piece et le modele ensuite.
        let deux = [Self.hue("Lampe", "Salon", ieee: "A0000000000000D3"), Self.hue("Lampe", "Bureau", ieee: "A0000000000000D4")]
        #expect(Self.noms(deux, [Self.maison("Lampe", "Grenier")]) == ["A0000000000000D3": "-", "A0000000000000D4": "-"])
        #expect(Self.noms(deux, [Self.maison("Lampe", "Bureau")]) == ["A0000000000000D3": "-", "A0000000000000D4": "Lampe"])
        // Deux candidats de la meme piece et du meme modele.
        #expect(Self.noms([Self.hue("Plafonnier", "Salon", ieee: "A0000000000000D5")],
                          [Self.maison("Spot 1", "Salon"), Self.maison("Spot 2", "Salon")])
                == ["A0000000000000D5": "-"])
        // Deux appareils de la meme piece et du meme modele pour un candidat.
        #expect(Self.noms([Self.hue("Spot A", "Salon", ieee: "A0000000000000D6"), Self.hue("Spot B", "Salon", ieee: "A0000000000000D7")],
                          [Self.maison("Plafonnier", "Salon")])
                == ["A0000000000000D6": "-", "A0000000000000D7": "-"])
        // Un accessoire pris par le nom n'est plus candidat pour la piece et le modele.
        #expect(Self.noms([Self.hue("Spot A", "Salon", ieee: "A0000000000000D8"), Self.hue("Spot B", "Salon", ieee: "A0000000000000D9")],
                          [Self.maison("Spot A", "Salon"), Self.maison("Plafonnier", "Salon")])
                == ["A0000000000000D8": "Spot A", "A0000000000000D9": "Plafonnier"])
    }

    /// Candidats : de Signify ou de Philips, ou sur le noeud Matter d'un pont Hue de Maison ; jamais un accessoire d'une
    /// autre marque (meme du meme nom), ni sans nom.
    @Test func candidats() {
        let m = [Self.maison("Pont Hue", "Salon", modele: "BSB002", noeud: "00000000000000AB", pont: true),
                 Self.maison("Lampe Matter", "Salon", fabricant: "Fabricant inventé", noeud: "00000000000000AB"),
                 Self.maison("Lampe Philips", "Salon", fabricant: "Philips"),
                 Self.maison("Prise", "Salon", fabricant: "Fabricant inventé"),
                 Self.maison("Autre pont", "Salon", fabricant: "Fabricant inventé", noeud: "00000000000000CD", pont: true),
                 Self.maison("Lampe d'un autre pont", "Salon", fabricant: "Fabricant inventé", noeud: "00000000000000CD"),
                 Self.maison("  ", "Salon")]
        #expect(FusionNoms.candidats(m) == [0, 1, 2])
        #expect(Self.noms([Self.hue("Prise", "Salon", ieee: "A0000000000000E1")], m) == ["A0000000000000E1": "-"],
                "une prise d'une autre marque du meme nom n'est pas celle du pont")
    }

    /// Non apparie : le nom et la piece de l'app Hue, signales ; sa piece prend l'ecriture de Maison quand Maison a la
    /// meme (elle trouve son etage), et garde la sienne sinon (« Autres pieces »). Les zones et le domicile viennent de
    /// Maison.
    @Test func nonApparie() throws {
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Séjour", "Cuisine"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let p = [Self.hue("Lampe séjour", "sejour", ieee: "A0000000000000F1"),
                 Self.hue("Lampe véranda", "Véranda", ieee: "A0000000000000F2"),
                 Self.hue("Lampe chambre", "Chambre", ieee: "A0000000000000F3")]
        let m = [Self.maison("Lampe chambre", "Chambre")]
        let r = FusionNoms.fusionner(pont: Self.pont(p), maison: Self.releve(m, zones: zones))
        let n = try #require(r.noms)
        let sejour = try #require(n.accessoire(ieee: "A0000000000000F1"))
        #expect(sejour.nom == "Lampe séjour" && sejour.piece == "Séjour" && sejour.origine == .pont)
        let veranda = try #require(n.accessoire(ieee: "A0000000000000F2"))
        #expect(veranda.piece == "Véranda" && veranda.origine == .pont)
        #expect(n.accessoire(ieee: "A0000000000000F3")?.origine == .maison)
        #expect(n.zones == zones && n.domicile == "Maison inventée")
        #expect(r.bilan == FusionNoms.Bilan(apparies: 1, nonApparies: 2))
        // Sans domicile ni zones dans Maison : ceux du pont.
        let sans = try #require(FusionNoms.fusionner(pont: Self.pont(p), maison: Self.releve(m, zones: [], domicile: nil)).noms)
        #expect(sans.domicile == "C0FFEEFFFE012345" && sans.zones == nil)
    }

    /// Un accessoire apparie sans piece dans Maison garde celle du pont.
    @Test func appariSansPiece() throws {
        let n = try #require(FusionNoms.fusionner(pont: Self.pont([Self.hue("Lampe", "Bureau", ieee: "A0000000000000F4")]),
                                                  maison: Self.releve([Self.maison("Lampe", nil)])).noms)
        #expect(n.accessoires.first?.piece == "Bureau" && n.accessoires.first?.origine == .maison)
    }

    /// Sans noms du pont : rien. Sans releve de Maison, ou avec un releve en echec : les noms du pont tels quels, sans
    /// origine ni bilan.
    @Test func sansLUnOuLAutre() {
        let p = Self.pont([Self.hue("Lampe", "Bureau", ieee: "A0000000000000F5")])
        #expect(FusionNoms.fusionner(pont: nil, maison: Self.releve([])) == FusionNoms.Resultat(noms: nil, bilan: nil))
        #expect(FusionNoms.fusionner(pont: p, maison: nil) == FusionNoms.Resultat(noms: p, bilan: nil))
        var echec = Self.releve([Self.maison("Autre nom", "Bureau")])
        echec.statut = .erreur
        #expect(FusionNoms.fusionner(pont: p, maison: echec) == FusionNoms.Resultat(noms: p, bilan: nil))
    }

    /// La demo : la suspension et l'interrupteur de la cuisine par la piece et le modele, la lampe de la salle de bain
    /// a la casse pres, le capteur de fuite (d'une autre marque dans Maison) sous son nom de l'app Hue ; quatre etages.
    @Test func demo() throws {
        let r = FusionNoms.fusionner(pont: NomsDemo.maison, maison: NomsDemo.releveMaison)
        let n = try #require(r.noms)
        #expect(n == NomsDemo.maisonFusionnee)
        #expect(r.bilan == FusionNoms.Bilan(apparies: 20, nonApparies: 1))
        #expect(n.accessoire(ieee: I.suspensionCuisine)?.nom == "Suspension de l'îlot")
        #expect(n.accessoire(ieee: I.interrupteurCuisine)?.nom == "Variateur cuisine")
        #expect(n.accessoire(ieee: I.lampeSalleDeBain)?.nom == "Lampe Salle de Bain")
        let fuite = try #require(n.accessoire(ieee: I.fuiteBuanderie))
        #expect(fuite.nom == "Capteur de fuite" && fuite.piece == "Buanderie" && fuite.origine == .pont)
        #expect(n.accessoire(ieee: I.lampeBureau)?.nom == "Lampe bureau")
        #expect(n.zones == NomsDemo.zones && n.domicile == NomsDemo.domicile)
        #expect(n.accessoires.count == NomsDemo.maison.accessoires.count, "les appareils du pont, rien de Maison seule")
    }

    /// Le JSON du Passeur, tel qu'il l'ecrit (format de Maillage Thread 1.1.0 : statut, noeud Matter, pont, batterie,
    /// zones), se lit ; un etat de charge inconnu est ignore ; une version plus recente est refusee ; le releve garde se
    /// relit tel quel.
    @Test func jsonDuPasseur() throws {
        let json = Data("""
            {"accessoires":[{"batterie":{"alerte":false,"charge":"horsCharge","niveau":80},"categorie":"Capteur",\
            "fabricant":"Signify Netherlands B.V.","firmware":"2.1","modele":"SML001","nom":"Détecteur",\
            "noeudMatter":"00000000000000AB","piece":"Entrée"},{"categorie":"Pont","fabricant":"Signify Netherlands B.V.",\
            "modele":"BSB002","nom":"Pont Hue","pont":true,"batterie":{"charge":"solaire"}}],\
            "date":"2026-10-08T07:00:00.000Z","domicile":"Maison inventée","statut":"ok","version":1,\
            "zones":[{"nom":"Rez-de-chaussée","pieces":["Entrée"]}]}
            """.utf8)
        let r = try ReleveMaison.lire(json)
        #expect(r.statut == .ok && r.domicile == "Maison inventée" && r.zones == [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Entrée"])])
        #expect(r.accessoires.first == AccessoireReleve(nom: "Détecteur", piece: "Entrée", fabricant: "Signify Netherlands B.V.",
                                                        modele: "SML001", firmware: "2.1", categorie: "Capteur",
                                                        noeudMatter: "00000000000000AB",
                                                        batterie: BatterieMaison(niveau: 80, charge: .horsCharge, alerte: false)))
        #expect(r.accessoires.last?.pont == true && r.accessoires.last?.batterie == BatterieMaison())
        let echec = try ReleveMaison.lire(Data(#"{"accessoires":[],"date":"2026-10-08T07:00:00Z","message":"Aucun domicile dans Maison","statut":"erreur","version":1}"#.utf8))
        #expect(echec.statut == .erreur && echec.message == "Aucun domicile dans Maison" && echec.zones == nil)
        var futur = NomsDemo.releveMaison
        futur.version = ReleveMaison.versionActuelle + 1
        #expect(throws: ReleveMaison.Erreur.versionTropRecente(2)) { try ReleveMaison.lire(try futur.donnees()) }
        #expect(try ReleveMaison.lire(try NomsDemo.releveMaison.donnees()) == NomsDemo.releveMaison)
    }

    /// Les noms reunis se gardent et se relisent avec leur origine et le code du modele.
    @Test func origineGardee() throws {
        let n = NomsDemo.maisonFusionnee
        #expect(try NomsMaison.lire(try n.donnees()) == n)
    }
}
