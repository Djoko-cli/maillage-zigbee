import Foundation
import Testing
@testable import MaillageCoeur

/// Precision 27 (spec de la vue par pieces, section 2.3), en Zigbee : un noeud que le pont ne place pas se place au
/// choix, sous son adresse longue, par maison ; la piece du pont passe avant le choix. Donnees inventees.
@Suite("Scene : piece choisie d'un noeud que le pont ne place pas, sous son adresse longue")
struct PiecesAppareilsTests {
    static let domicile = "Maison inventée"
    /// Pieces d'une maison inventee.
    static let pieces = ["Bureau", "Cuisine", "Salon"]
    static let pont = "A0000000000000C1"
    static let routeur = "A0000000000000C2"
    static let detecteur = "A0000000000000C3"

    /// Maillage invente : le pont, un routeur, et un detecteur sous `parent`, que le pont ne connait pas.
    static func graphe(parent: String = routeur, connu: Bool = false) -> GrapheReseau {
        let m = MaillageZigbee(date: Date(timeIntervalSince1970: 1_790_000_000),
                               noeuds: [NoeudZigbee(ieee: pont, court: 0, type: .coordinateur),
                                        NoeudZigbee(ieee: routeur, court: 0x1A2B, type: .routeur),
                                        NoeudZigbee(ieee: detecteur, court: 0x0A11, type: .final)],
                               liens: [LienRadio(a: pont, b: routeur, lqiA: 200, lqiB: 190)],
                               parents: [LienParent(enfant: detecteur, parent: parent, lqi: 150)])
        var apps = [AppareilAffiche(id: pont, nom: "Pont", etat: .joignable),
                    AppareilAffiche(id: routeur, nom: "Lampe", etat: .joignable)]
        if connu { apps.append(AppareilAffiche(id: detecteur, nom: "Détecteur", etat: .joignable)) }
        return GrapheReseau(maillage: m, appareils: apps)
    }

    /// Un choix sous l'adresse longue place le noeud ; tout noeud du graphe a une cle (son adresse longue), le pont et
    /// les routeurs compris. Le choix vaut pour sa maison, et tant que sa piece est une piece de la maison.
    @Test func choixParAdresseLongue() throws {
        let g = Self.graphe()
        let detecteur = try #require(g.noeud(Self.detecteur))
        #expect(detecteur.inconnu && PiecesRouteurs.cle(detecteur) == Self.detecteur)
        #expect(PiecesRouteurs.cle(try #require(g.noeud(Self.pont))) == Self.pont)
        var p = PiecesRouteurs()
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile).isEmpty, "sans choix")
        p.choisir("Salon", appareil: Self.detecteur, domicile: Self.domicile)
        p.choisir("Bureau", appareil: Self.routeur, domicile: Self.domicile)
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile)
                == [Self.detecteur: "Salon", Self.routeur: "Bureau"])
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: "Chalet").isEmpty, "une autre maison")
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: ["Bureau", "Cuisine"], domicile: Self.domicile)
                == [Self.routeur: "Bureau"], "le salon n'est plus une piece de la maison : le choix ne compte plus")
        #expect(p.choix(appareil: Self.detecteur, domicile: Self.domicile) == "Salon", "il reste dans le fichier")
    }

    /// Le meme noeud garde son choix sous un autre parent (une autre adresse courte), et quand le pont le connait.
    @Test func memeNoeudAutreParent() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: Self.detecteur, domicile: Self.domicile)
        for g in [Self.graphe(), Self.graphe(parent: Self.pont), Self.graphe(connu: true)] {
            #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile)[Self.detecteur] == "Salon")
        }
    }

    /// La piece du pont passe avant le choix ; le choix reste, sans effet.
    @Test func lePontLEmporte() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: Self.detecteur, domicile: Self.domicile)
        let g = Self.graphe(connu: true)
        let avecPont = p.piecesNoeuds(g, deMaison: [Self.detecteur: "Cuisine"], parmi: Self.pieces, domicile: Self.domicile)
        #expect(avecPont == [Self.detecteur: "Cuisine"], "le pont l'emporte")
        #expect(p.choix(appareil: Self.detecteur, domicile: Self.domicile) == "Salon", "le choix reste")
    }

    /// Un noeud sans adresse longue connue n'a ni cle, ni choix.
    @Test func sansAdresseLongueNiChoix() throws {
        let g = GrapheReseau(noeuds: [GrapheReseau.Noeud(id: "x", genre: .appareil, routeur: false, inconnu: true)])
        let n = try #require(g.noeud("x"))
        #expect(PiecesRouteurs.cle(n) == nil)
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: "x", domicile: Self.domicile)
        #expect(p.piecesNoeuds(g, deMaison: [:], parmi: Self.pieces, domicile: Self.domicile).isEmpty)
    }

    /// Un `appareils` mal forme (fichier edite a la main ou abime) est ignore ; le prochain choix reecrit un fichier
    /// sain. `null` vaut un champ absent.
    @Test(arguments: [#"["x"]"#, #""texte""#, #"{"Maison inventée": ["x"]}"#,
                      #"{"Maison inventée": {"A0000000000000C3": 5}}"#, "null"])
    func appareilsMalForme(champ: String) throws {
        let url = PiecesRouteursTests.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"appareils" : \#(champ), "version" : 1}"#.utf8).write(to: url)
        var p = PiecesRouteurs.lire(url)
        #expect(p.appareils.isEmpty && p.version == 1, "le champ mal forme est ignore")
        p.choisir("Salon", appareil: Self.detecteur, domicile: Self.domicile)
        try p.ecrire(dans: url)
        let relu = PiecesRouteurs.lire(url)
        #expect(relu == p && relu.choix(appareil: Self.detecteur, domicile: Self.domicile) == "Salon")
    }

    /// « Sans piece » (nil) efface le choix ; la cle est l'adresse longue en majuscules ; une maison sans choix
    /// disparait du fichier.
    @Test func sansPieceEffaceLeChoix() throws {
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: Self.detecteur, domicile: Self.domicile)
        p.choisir("Bureau", appareil: "a0000000000000c4", domicile: Self.domicile)
        #expect(p.choix(appareil: "A0000000000000C4", domicile: Self.domicile) == "Bureau", "en majuscules")
        p.choisir(nil, appareil: Self.detecteur, domicile: Self.domicile)
        #expect(p.choix(appareil: Self.detecteur, domicile: Self.domicile) == nil)
        p.choisir(nil, appareil: "A0000000000000C4", domicile: Self.domicile)
        #expect(p == PiecesRouteurs(), "plus aucun choix pour cette maison")
    }
}
