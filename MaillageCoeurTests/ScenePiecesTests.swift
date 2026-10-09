import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : etages, pieces et noeuds")
struct ScenePiecesTests {
    /// Petit reseau : l'Apple TV (le coordinateur, couronne) et le HomePod, routeurs ; quatre appareils. Sans la
    /// sonde, aucun lien, et E...04 est un appareil final. Avec la sonde : E...04 route, E...02 est l'enfant de l'Apple
    /// TV, E...03 celui du HomePod ; E...05 n'a pas de parent connu : il porte un rattachement suppose a l'Apple TV, que
    /// le graphe Zigbee ne trace pas, mais que la scene et sa projection savent encore dessiner.
    static func graphe(sonde: Bool) throws -> GrapheReseau {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var noeuds = [NoeudZigbee(ieee: "Apple TV", court: 0, type: .coordinateur),
                      NoeudZigbee(ieee: "HomePod", court: 0x1000, type: .routeur)]
        noeuds += (2...5).map { k in
            NoeudZigbee(ieee: String(format: "E00000000000000%d", k), court: UInt16(0x2000 + k),
                        type: sonde && k == 4 ? .routeur : .final)
        }
        let apps = noeuds.map { AppareilAffiche(id: $0.ieee, nom: $0.ieee, etat: .joignable) }
        guard sonde else { return GrapheReseau(maillage: MaillageZigbee(date: date, noeuds: noeuds), appareils: apps) }
        let liens = [LienRadio(a: "Apple TV", b: "HomePod", lqiA: 200, lqiB: 120),
                     LienRadio(a: "Apple TV", b: "E000000000000004", lqiA: 120, lqiB: 120)]
        let parents = [LienParent(enfant: "E000000000000002", parent: "Apple TV", lqi: 200),
                       LienParent(enfant: "E000000000000003", parent: "HomePod", lqi: 120)]
        let m = MaillageZigbee(date: date, noeuds: noeuds, liens: liens, parents: parents)
        let g = GrapheReseau(maillage: m, appareils: apps)
        return GrapheReseau(noeuds: g.noeuds, liens: g.liens + [GrapheReseau.Lien(de: "E000000000000005", vers: "Apple TV")])
    }

    static let libelles = ["Apple TV": "Apple TV 👑", "HomePod": "HomePod", "E000000000000002": "Lampe salon",
                           "E000000000000003": "Capteur", "E000000000000004": "Prise", "E000000000000005": "Bouton"]

    static func noms(_ s: ScenePieces, etage e: Int) -> [ScenePieces.NomPiece] {
        s.etages[e].pieces.map { s.pieces[$0].nom }
    }

    static func piece(_ s: ScenePieces, _ nom: ScenePieces.NomPiece) throws -> ScenePieces.Piece {
        try #require(s.pieces.first { $0.nom == nom })
    }

    /// Zones : une piece dans deux zones va dans la premiere ; une zone sans piece montree n'est pas un
    /// etage ; les pieces hors zone forment « Autres pieces » ; une piece sans noeud n'est pas montree.
    @Test func zones() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Bureau",
                      "E000000000000003": "Garage", "E000000000000004": "Salon", "E000000000000005": "Chambre"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Chambre"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"]),
                     ZoneMaison(nom: "Grenier", pieces: ["Débarras"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true)
        #expect(s.etages.map(\.nom) == [.zone("Rez-de-chaussée"), .zone("Étage"), .autresPieces])
        #expect(Self.noms(s, etage: 0) == [.maison("Chambre"), .maison("Salon")], "Chambre : la premiere zone")
        #expect(Self.noms(s, etage: 1) == [.maison("Bureau")])
        #expect(Self.noms(s, etage: 2) == [.maison("Garage")])
        #expect(!s.pieces.contains { $0.nom == .maison("Cuisine") || $0.nom == .maison("Débarras") })
        #expect(try Self.piece(s, .maison("Salon")).noeuds == ["Apple TV", "E000000000000004"])
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage", "autres-pieces"])
        #expect(!s.sansPiecesMaison)
    }

    /// Niveaux (polissage C, section 1) : une zone a cote rejoint son etage principal, juste apres lui, meme
    /// rangee avant lui par Maison ; les plateaux sont ranges niveau par niveau. « Sans piece » va sur le
    /// plateau du bas, l'etage principal du premier niveau. Sans choix, l'ordre de Maison.
    @Test func niveaux() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Terrasse"]
        let zones = [ZoneMaison(nom: "Jardin", pieces: ["Terrasse"]), ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true,
                            aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)])
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage"])
        #expect(s.etages.map(\.niveau) == [0, 0, 1] && s.etages.map(\.principal) == [true, false, true])
        #expect(s.etages.map(\.dehors) == [false, true, false])
        #expect(s.niveaux.liste == [["zone:Rez-de-chaussée", "zone:Jardin"], ["zone:Étage"]])
        #expect(Self.noms(s, etage: 0) == [.maison("Salon"), .sansPiece], "« Sans piece » sur le plateau du bas")
        #expect(Self.noms(s, etage: 1) == [.maison("Terrasse")])
        let sans = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                               piecesMaison: true)
        #expect(sans.etages.map(\.id) == ["zone:Jardin", "zone:Rez-de-chaussée", "zone:Étage"])
        #expect(sans.etages.map(\.niveau) == [0, 1, 2] && sans.etages.allSatisfy(\.principal))
    }

    /// Deux zones de Maison du meme nom (inattendu) : un seul etage, a la place de la premiere, avec les
    /// pieces des deux ; aucune cle d'etage en double. La premiere compte meme sans piece montree.
    @Test func zonesHomonymes() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Bureau"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                     ZoneMaison(nom: "Étage", pieces: ["Chambre"]),
                     ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Bureau", "Salon"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true)
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage"])
        #expect(Self.noms(s, etage: 0) == [.maison("Bureau"), .maison("Salon"), .sansPiece])
        #expect(Self.noms(s, etage: 1) == [.maison("Chambre")])
        let vide = [ZoneMaison(nom: "Étage", pieces: ["Grenier"]), ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]),
                    ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau"])]
        let t = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: vide, chefs: [],
                            piecesMaison: true)
        #expect(t.etages.map(\.id) == ["zone:Étage", "zone:Rez-de-chaussée"])
        #expect(Self.noms(t, etage: 0) == [.maison("Bureau"), .maison("Chambre"), .sansPiece])
    }

    /// Maison sans zones, ou fichier d'avant les zones (le champ manque : nil) : un seul plateau.
    @Test func sansZones() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre"]
        for zones in [nil, []] as [[ZoneMaison]?] {
            let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                                piecesMaison: true)
            #expect(s.etages.map(\.nom) == [.maison])
            #expect(Self.noms(s, etage: 0) == [.maison("Chambre"), .maison("Salon"), .sansPiece])
        }
        let ancien = """
        {"version": 1, "date": "2026-09-28T10:00:00Z", "statut": "ok", "accessoires": [{"nom": "Lampe", "piece": "Salon"}]}
        """
        let n = try NomsMaison.lire(Data(ancien.utf8))
        #expect(n.zones == nil)
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: n.zones, chefs: [],
                            piecesMaison: true)
        #expect(s.etages.map(\.nom) == [.maison])
    }

    /// « Sans piece » : les noeuds que Maison ne place pas, sur le plateau du bas, celui de l'ordre
    /// garde s'il y en a un ; une cle inconnue de l'ordre garde est ignoree.
    @Test func sansPieceSurLePlateauDuBas() throws {
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true)
        #expect(Self.noms(s, etage: 0) == [.maison("Salon"), .sansPiece])
        #expect(try Self.piece(s, .sansPiece).noeuds == ["E000000000000005", "E000000000000003", "E000000000000002",
                                                          "E000000000000004"], "par libelle")
        let inverse = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                                  piecesMaison: true, ordreEtages: ["zone:Étage", "inconnu", "zone:Rez-de-chaussée"])
        #expect(inverse.etages.map(\.nom) == [.zone("Étage"), .zone("Rez-de-chaussée")])
        #expect(Self.noms(inverse, etage: 0) == [.maison("Chambre"), .sansPiece])
        #expect(try Self.piece(inverse, .sansPiece).etage == 0)
    }

    /// Pas encore de pieces de Maison : un plateau « Maison », une carte par routeur avec ses enfants
    /// (vus par la sonde) ; sans parent connu, « Sans piece ». Sans sonde, aucun parent : chaque
    /// routeur seul dans sa carte.
    @Test func groupementParRouteur() throws {
        let s = ScenePieces(graphe: try Self.graphe(sonde: true), libelles: Self.libelles, piecesNoeuds: [:], zones: nil,
                            chefs: [], piecesMaison: false)
        #expect(s.sansPiecesMaison)
        #expect(s.etages.map(\.nom) == [.maison])
        #expect(try Self.piece(s, .routeur("Apple TV")).noeuds == ["Apple TV", "E000000000000002"])
        #expect(try Self.piece(s, .routeur("HomePod")).noeuds == ["HomePod", "E000000000000003"])
        #expect(try Self.piece(s, .routeur("E000000000000004")).noeuds == ["E000000000000004"], "appareil qui route")
        #expect(try Self.piece(s, .sansPiece).noeuds == ["E000000000000005"])
        let sans = ScenePieces(graphe: try Self.graphe(sonde: false), libelles: Self.libelles, piecesNoeuds: [:],
                               zones: nil, chefs: [], piecesMaison: false)
        #expect(try Self.piece(sans, .routeur("Apple TV")).noeuds == ["Apple TV"])
        #expect(try Self.piece(sans, .sansPiece).noeuds.count == 4)
    }

    /// La cle de la disposition et les cartes ne dependent pas des badges (polissage D, section 2) : la scene voit les
    /// noms sans eux, et un autre chef ne reordonne pas les lignes. Un autre nom, une autre piece, une pile qui devient
    /// connue changent la cle ; la largeur reservee d'un nom (ici 7 px par caractere de `texteReserve`, plus 50 pour la
    /// pastille d'une pile connue) fait des cartes egales, avec ou sans badge, et une carte plus large avec une pile
    /// connue (polissage D, section 2, decision du 05/10).
    @Test func cleSansLesBadges() throws {
        let g = try Self.graphe(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        func scene(chefs: Set<String>, libelles: [String: String] = Self.libelles, pieces: [String: String]? = nil,
                   piles: Set<String> = []) -> ScenePieces {
            ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: pieces ?? tous, zones: nil, chefs: chefs, piecesMaison: true,
                        piles: piles)
        }
        let a = scene(chefs: ["Apple TV"]), b = scene(chefs: ["HomePod"]), c = scene(chefs: [])
        #expect(a.cleDisposition == b.cleDisposition && a.cleDisposition == c.cleDisposition)
        #expect(a.pieces.map(\.noeuds) == b.pieces.map(\.noeuds))
        func largeurs(_ s: ScenePieces) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: s.noeuds.map {
                ($0.id, 7.0 * Double(CartesPieces.texteReserve($0.libelle, routeur: $0.route).count) + ($0.pile ? 50 : 0))
            })
        }
        #expect(CartesPieces.cartes(a, largeurs: largeurs(a)) == CartesPieces.cartes(b, largeurs: largeurs(b)))
        let pile = scene(chefs: ["Apple TV"], piles: ["E000000000000002"])
        #expect(pile.noeud("E000000000000002")?.pile == true && a.noeud("E000000000000002")?.pile == false)
        #expect(pile.cleDisposition != a.cleDisposition, "une pile connue")
        let salonPile = try #require(pile.pieces.firstIndex { $0.nom == .maison("Salon") })
        #expect(CartesPieces.cartes(pile, largeurs: largeurs(pile))[salonPile].largeur
                > CartesPieces.cartes(a, largeurs: largeurs(a))[salonPile].largeur, "une carte plus large avec une pile connue")
        var renomme = Self.libelles
        renomme["E000000000000002"] = "Lampe du salon"
        #expect(scene(chefs: ["Apple TV"], libelles: renomme).cleDisposition != a.cleDisposition, "un autre nom")
        var ailleurs = tous
        ailleurs["E000000000000002"] = "Cuisine"
        #expect(scene(chefs: ["Apple TV"], pieces: ailleurs).cleDisposition != a.cleDisposition, "une autre piece")
        let salon = try #require(a.cleDisposition.pieces["maison"]?["piece:Salon"])
        #expect(salon.contains("HomePod|HomePod|R|") && salon.contains("E000000000000002|Lampe salon||"), "l'id, le nom, s'il route")
        #expect(try #require(pile.cleDisposition.pieces["maison"]?["piece:Salon"]).contains("E000000000000002|Lampe salon||P"),
                "et si sa pile est connue")
        #expect(a.cleDisposition.niveaux == ["maison": "maison#0"])
    }

    /// « Le noeud route » (polissage D, section 2) s'ecrit d'une seule facon, `Noeud.route` : le coordinateur ou un
    /// routeur, jamais un autre noeud ; il suit le graphe et le rang de la carte (1 ou 2). La cle de la disposition en
    /// tire son « R ».
    @Test func leNoeudRoute() throws {
        let g = try Self.graphe(sonde: true)
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: Dictionary(uniqueKeysWithValues: g.noeuds.map {
            ($0.id, "Salon")
        }), zones: nil, chefs: [], piecesMaison: true)
        #expect(Set(s.noeuds.map(\.rang)) == [1, 2, 3], "des noeuds de chaque rang")
        let cles = try #require(s.cleDisposition.pieces["maison"]?["piece:Salon"])
        for n in s.noeuds {
            #expect(!n.bordure && n.route == n.routeur, "\(n.id) : le graphe")
            #expect(n.route == (n.rang == 1 || n.rang == 2), "\(n.id) : le rang")
            let cle = try #require(cles.first { $0.hasPrefix(n.id + "|") }).split(separator: "|", omittingEmptySubsequences: false)
            #expect(cle[2] == (n.route ? "R" : ""), "\(n.id) : la cle")
        }
    }

    /// Lignes d'une carte : le coordinateur, les routeurs, puis les appareils finaux, par nom ; la couronne ne change pas
    /// de groupe (polissage D, section 2) ; rayons 15 (coordinateur), 8 (routeur) et 7.
    @Test func lignesEtRayons() throws {
        let g = try Self.graphe(sonde: true)
        let tous = Dictionary(uniqueKeysWithValues: g.noeuds.map { ($0.id, "Salon") })
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: tous, zones: nil, chefs: ["HomePod"],
                            piecesMaison: true)
        #expect(try Self.piece(s, .maison("Salon")).noeuds
                == ["Apple TV", "HomePod", "E000000000000004", "E000000000000005", "E000000000000003", "E000000000000002"])
        #expect(s.noeud("HomePod")?.rang == 2 && s.noeud("HomePod")?.rayon == 8 && s.noeud("HomePod")?.chef == true)
        #expect(s.noeud("Apple TV")?.rang == 1 && s.noeud("Apple TV")?.rayon == 15)
        #expect(s.noeud("E000000000000004")?.rang == 2 && s.noeud("E000000000000004")?.rayon == 8)
        #expect(s.noeud("E000000000000002")?.rang == 3 && s.noeud("E000000000000002")?.rayon == 7)
        #expect(s.noeud("E000000000000002")?.libelle == "Lampe salon")
        #expect(s.liens == g.liens)
    }

    /// Teintes : FNV-1a 32 bits du nom, modulo 8 ; dans un etage, la suivante libre si elle est prise
    /// (Chambre, Salle de bain et Cellier donnent 3) ; d'un etage a l'autre, pas de conflit.
    @Test func teintes() throws {
        #expect(ScenePieces.fnv1a("") == 0x811C_9DC5)
        #expect(ScenePieces.fnv1a("a") == 0xE40C_292C)
        #expect(ScenePieces.fnv1a("foobar") == 0xBF9C_F968)
        let g = try Self.graphe(sonde: false)
        let pieces = ["Apple TV": "Salle de bain", "HomePod": "Chambre", "E000000000000002": "Cellier",
                      "E000000000000003": "Salon", "E000000000000004": "Chambre", "E000000000000005": "Salon"]
        let zones = [ZoneMaison(nom: "Étage", pieces: ["Salle de bain", "Chambre", "Cellier"]),
                     ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"])]
        let s = ScenePieces(graphe: g, libelles: Self.libelles, piecesNoeuds: pieces, zones: zones, chefs: [],
                            piecesMaison: true)
        #expect(try Self.piece(s, .maison("Cellier")).teinte == 3, "premier par nom")
        #expect(try Self.piece(s, .maison("Chambre")).teinte == 4)
        #expect(try Self.piece(s, .maison("Salle de bain")).teinte == 5)
        #expect(try Self.piece(s, .maison("Salon")).teinte == 2)
        #expect(ScenePieces.teintes.count == 8 && ScenePieces.teintes[0] == 0x3B82F5)
    }

    /// Maison sans pieces : la teinte et le rang de la carte d'un routeur viennent de son id, pas de son
    /// libelle decore ; ils ne changent ni quand la couronne passe a un autre routeur, ni quand ☾ ou ⚠︎
    /// apparait.
    @Test func cartesDeRouteurStables() throws {
        let g = try Self.graphe(sonde: true)
        func cartes(_ libelles: [String: String], chef: String) -> [String] {
            let s = ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: [:], zones: nil, chefs: [chef],
                                piecesMaison: false)
            return s.etages[0].pieces.map { "\(s.pieces[$0].id) #\(s.pieces[$0].teinte)" }
        }
        var libelles = Self.libelles
        libelles["Apple TV"] = "Salon 👑"
        libelles["HomePod"] = "Salon bas"
        let avant = cartes(libelles, chef: "Apple TV")
        #expect(avant.count == 4)
        libelles["Apple TV"] = "Salon"
        libelles["HomePod"] = "Salon bas 👑"
        #expect(cartes(libelles, chef: "HomePod") == avant, "la couronne passe a l'autre routeur")
        libelles["E000000000000004"] = "Prise ☾ ⚠︎"
        #expect(cartes(libelles, chef: "HomePod") == avant, "l'appareil qui route s'endort et n'a plus d'adresse")
    }
}
