import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : noeuds et liens du reseau Zigbee")
struct GrapheReseauTests {
    typealias I = NomsDemo.Ieee

    /// Les appareils du pont de la demo, joignables s'ils sont dans le maillage, disparus sinon.
    static func affiches(_ m: MaillageZigbee) -> [AppareilAffiche] {
        NomsDemo.maison.accessoires.compactMap { a in
            guard let ieee = a.ieee else { return nil }
            return AppareilAffiche(id: ieee, nom: a.nom, piece: a.piece, etat: m.noeud(ieee) == nil ? .disparu : .joignable)
        }
    }

    /// La demo : le pont au centre, les routeurs, les appareils finaux ; le routeur que le pont ne connait pas est
    /// « inconnu », la sonde ne l'est pas ; la prise du salon, disparue, est un noeud sans lien. Toute la partition est
    /// la meme, aucun noeud n'est de bordure, et la cle de piece est l'adresse longue.
    @Test func demo() throws {
        let m = MaillageDemo.maillage
        let g = GrapheReseau(maillage: m, appareils: Self.affiches(m))
        let pont = try #require(g.noeud(I.pont))
        #expect(pont.genre == .centre && pont.routeur && !pont.inconnu)
        #expect(g.noeuds.filter { $0.genre == .routeur }.count == 13)
        #expect(g.noeud(I.lampeBureau)?.genre == .routeur && g.noeud(I.lampeBureau)?.routeur == true)
        let interrupteur = try #require(g.noeud(I.interrupteurSalon))
        #expect(interrupteur.genre == .appareil && !interrupteur.routeur && !interrupteur.inconnu)
        #expect(g.noeud(I.inconnu)?.inconnu == true, "vu par la sonde, inconnu du pont")
        #expect(g.noeud(I.sonde)?.inconnu == false, "la sonde n'est pas une inconnue")
        let prise = try #require(g.noeud(I.priseSalon))
        #expect(prise.genre == .appareil && !prise.routeur)
        #expect(!g.liens.contains { $0.de == I.priseSalon || $0.vers == I.priseSalon }, "disparue : sans lien")
        #expect(g.noeuds.allSatisfy { $0.partition == GrapheReseau.partitionUnique && !$0.bordure && $0.extMac == $0.id })
        #expect(g.noeuds.count == 23)
    }

    /// Les liens : radio entre routeurs (un par paire, la moins bonne des deux qualites, `QualiteLien`), et de chaque
    /// appareil final vers son parent, a la qualite que le parent mesure.
    @Test func liens() throws {
        let m = MaillageDemo.maillage
        let g = GrapheReseau(maillage: m, appareils: Self.affiches(m))
        let radio = g.liens.filter { $0.genre == .radio }
        #expect(radio.count == 16)
        func qualite(_ a: String, _ b: String) -> Int?? {
            radio.first { Set([$0.de, $0.vers]) == Set([a, b]) }.map(\.qualite)
        }
        #expect(qualite(I.pont, I.plafonnierSalon) == 3)
        #expect(qualite(I.rubanCuisine, I.priseTerrasse) == 1, "88 et 61 : la moins bonne, faible")
        #expect(qualite(I.lampeSalleDeBain, I.lampeGrenier) == 0, "46 et 52 : tres faible")
        #expect(qualite(I.ampouleEntree, I.inconnu) == 1, "un seul sens connu, 66")
        let parents = g.liens.filter { $0.genre == .parent }
        #expect(parents.count == 8)
        #expect(g.parent(de: I.detecteurAbri) == I.priseTerrasse)
        #expect(parents.first { $0.de == I.fuiteBuanderie }?.qualite == 0, "LQI 44")
        #expect(parents.first { $0.de == I.interrupteurSalon }?.qualite == 2, "LQI 112")
        #expect(!g.liens.contains { $0.genre == .rattachement })
    }

    /// Ordre des noeuds : le coordinateur, les routeurs, les appareils finaux (par adresse longue), puis les appareils
    /// du pont absents du maillage ; l'ordre d'arrivee des appareils ne compte pas.
    @Test func ordreEtStabilite() throws {
        let m = MaillageDemo.maillage
        let apps = Self.affiches(m)
        let g = GrapheReseau(maillage: m, appareils: apps)
        #expect(g.noeuds.first?.id == I.pont)
        let genres = g.noeuds.map(\.genre)
        #expect(genres.firstIndex(of: .appareil) ?? 0 > genres.lastIndex(of: .routeur) ?? 0)
        #expect(g.noeuds.last?.id == I.priseSalon, "absente du maillage : a la fin")
        #expect(GrapheReseau(maillage: m, appareils: apps.reversed()) == g)
    }

    /// Sans maillage : les appareils du pont seuls, sans lien ; un noeud vu deux fois n'en fait qu'un.
    @Test func sansMaillage() {
        let apps = [AppareilAffiche(id: "A0000000000000B1", nom: "Lampe", etat: .inconnu),
                    AppareilAffiche(id: "A0000000000000B2", nom: "Prise", etat: .inconnu)]
        let g = GrapheReseau(maillage: nil, appareils: apps + apps)
        #expect(g.noeuds.map(\.id) == ["A0000000000000B1", "A0000000000000B2"])
        #expect(g.noeuds.allSatisfy { $0.genre == .appareil && !$0.routeur && !$0.inconnu })
        #expect(g.liens.isEmpty)
    }

    /// Des noeuds et des liens deja faits : un lien dont un bout manque est ignore.
    @Test func noeudsDejaFaits() {
        let n = [GrapheReseau.Noeud(id: "a", genre: .centre, routeur: true, inconnu: false),
                 GrapheReseau.Noeud(id: "b", genre: .appareil, routeur: false, inconnu: false)]
        let g = GrapheReseau(noeuds: n, liens: [GrapheReseau.Lien(de: "b", vers: "a", genre: .parent, qualite: 2),
                                                 GrapheReseau.Lien(de: "c", vers: "a", genre: .parent)])
        #expect(g.liens.count == 1 && g.parent(de: "b") == "a" && g.parent(de: "a") == nil)
    }

    /// Les chemins vers le pont : un lien `chemin` par routeur vers son prochain saut, de la qualite du lien radio entre
    /// les deux (inconnue sans lien), suppose ou non ; en mode « chemins », ils sont traces avec les liens vers un parent,
    /// et les liens radio seulement ceux du noeud selectionne (en voisins) ; en mode « tous », l'inverse des chemins.
    @Test func cheminsEtModes() throws {
        let m = MaillageDemo.maillage
        let g = GrapheReseau(maillage: m, appareils: Self.affiches(m))
        let chemins = g.liens.filter { $0.genre == .chemin }
        #expect(chemins.count == 13, "les 13 routeurs, dont deux supposes (pas le pont)")
        let bureau = try #require(g.chemin(de: I.lampeBureau))
        #expect(bureau.vers == I.lampadaireSalon && bureau.qualite == 2 && !bureau.suppose)
        let terrasse = try #require(g.chemin(de: I.priseTerrasse))
        #expect(terrasse.vers == I.rubanCuisine && terrasse.suppose && terrasse.qualite == 1)
        #expect(g.chemin(de: I.plafonnierSalon)?.vers == I.pont && g.chemin(de: I.pont) == nil)
        let radio = try #require(g.liens.first { $0.genre == .radio && ($0.de == I.lampeBureau || $0.vers == I.lampeBureau) })
        let parent = try #require(g.liens.first { $0.genre == .parent })
        #expect(SceneProjetee.trace(bureau, mode: .chemins, selection: nil) == .normal)
        #expect(SceneProjetee.trace(bureau, mode: .tous, selection: nil) == nil)
        #expect(SceneProjetee.trace(radio, mode: .chemins, selection: nil) == nil)
        #expect(SceneProjetee.trace(radio, mode: .chemins, selection: I.lampeBureau) == .voisin)
        #expect(SceneProjetee.trace(radio, mode: .chemins, selection: I.capteurGrenier) == nil)
        #expect(SceneProjetee.trace(radio, mode: .tous, selection: nil) == .normal)
        #expect(SceneProjetee.trace(parent, mode: .chemins, selection: nil) == .normal)
        #expect(SceneProjetee.trace(parent, mode: .tous, selection: nil) == .normal)
    }
}
