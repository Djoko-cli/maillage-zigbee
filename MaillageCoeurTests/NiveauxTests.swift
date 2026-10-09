import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : niveaux de la maison")
struct NiveauxTests {
    typealias A = PlacesGardees.ACote

    /// Sans choix : un etage par plateau, chacun sur son niveau, dans l'ordre garde.
    @Test func etagesSeulement() {
        let n = Niveaux(["rdc", "etage", "combles"], aCote: [:])
        #expect(n.liste == [["rdc"], ["etage"], ["combles"]])
        #expect(n.aCote.isEmpty && n.plateaux == ["rdc", "etage", "combles"])
        #expect(n.niveau("combles") == 2 && n.estPrincipal("etage") && !n.dehors("etage"))
        #expect(n.niveau("absent") == nil)
    }

    /// Une zone a cote partage le niveau de son etage principal, apres lui, dans ou hors de la maison ; elle
    /// le rejoint meme rangee avant lui dans l'ordre garde.
    @Test func zoneACote() {
        let dehors = Niveaux(["rdc", "jardin", "etage"], aCote: ["jardin": A(etage: "rdc", dehors: true)])
        #expect(dehors.liste == [["rdc", "jardin"], ["etage"]])
        #expect(dehors.niveau("jardin") == 0 && !dehors.estPrincipal("jardin") && dehors.dehors("jardin"))
        let dedans = Niveaux(["jardin", "etage", "rdc"], aCote: ["jardin": A(etage: "rdc")])
        #expect(dedans.liste == [["etage"], ["rdc", "jardin"]])
        #expect(!dedans.dehors("jardin") && dedans.aCote == ["jardin": A(etage: "rdc")])
    }

    /// Les cas tordus (spec de C, section 1.2) : un etage principal absent, une chaine, une boucle, une zone a
    /// cote d'elle-meme.
    @Test func casTordus() {
        let absent = Niveaux(["rdc", "jardin"], aCote: ["jardin": A(etage: "zone:Ailleurs", dehors: true)])
        #expect(absent.liste == [["rdc"], ["jardin"]] && absent.aCote.isEmpty, "la zone redevient un etage, a sa place")
        let chaine = Niveaux(["a", "b", "c"], aCote: ["a": A(etage: "b", dehors: true), "b": A(etage: "c")])
        #expect(chaine.liste == [["c", "a", "b"]])
        #expect(chaine.aCote == ["a": A(etage: "c", dehors: true), "b": A(etage: "c")], "A et B a cote de C")
        let boucle = Niveaux(["a", "b", "c"], aCote: ["a": A(etage: "b"), "b": A(etage: "a"), "c": A(etage: "a")])
        #expect(boucle.liste == [["a", "c"], ["b"]], "la boucle redevient des etages ; C rejoint le premier qu'il atteint")
        let soi = Niveaux(["a", "b"], aCote: ["a": A(etage: "a")])
        #expect(soi.liste == [["a"], ["b"]] && soi.aCote.isEmpty)
    }

    /// « Monter » et « Descendre » d'un niveau entier, zones a cote comprises ; grises pour une zone a cote, en
    /// haut et en bas de la pile.
    @Test func monterEtDescendre() {
        let choix = ["jardin": A(etage: "rdc", dehors: true)]
        let n = Niveaux(["rdc", "jardin", "etage", "combles"], aCote: choix)
        #expect(n.deplacer("rdc", de: 1, choix: choix) == Rangement(ordre: ["etage", "rdc", "jardin", "combles"], aCote: choix))
        #expect(n.deplacer("combles", de: -1, choix: choix)?.ordre == ["rdc", "jardin", "combles", "etage"])
        #expect(n.deplacer("jardin", de: 1, choix: choix) == nil, "une zone a cote")
        #expect(n.deplacer("combles", de: 1, choix: choix) == nil && n.deplacer("rdc", de: -1, choix: choix) == nil)
    }

    /// « Au meme niveau que » : la zone passe a cote de l'etage principal du niveau choisi, dans la maison, apres
    /// le groupe de cet etage ; ses propres zones a cote la suivent, avec leur choix. Le niveau ou elle est deja
    /// (l'article coche) ne change rien, ni pour un etage son propre niveau.
    @Test func auMemeNiveauQue() throws {
        let choix = ["jardin": A(etage: "rdc", dehors: true), "abri": A(etage: "combles", dehors: true)]
        let n = Niveaux(["rdc", "jardin", "etage", "combles", "abri"], aCote: choix)
        let combles = try #require(n.rejoindre("combles", niveau: 0, choix: choix))
        #expect(combles.ordre == ["rdc", "jardin", "combles", "abri", "etage"])
        #expect(combles.aCote == ["jardin": A(etage: "rdc", dehors: true), "combles": A(etage: "rdc"),
                                  "abri": A(etage: "rdc", dehors: true)])
        let jardin = try #require(n.rejoindre("jardin", niveau: 1, choix: choix))
        #expect(jardin.ordre == ["rdc", "etage", "jardin", "combles", "abri"])
        #expect(jardin.aCote["jardin"] == A(etage: "etage"), "dans la maison")
        #expect(n.rejoindre("jardin", niveau: 0, choix: choix) == nil, "deja a ce niveau")
        #expect(n.rejoindre("etage", niveau: 1, choix: choix) == nil, "son propre niveau")
        #expect(n.rejoindre("etage", niveau: 3, choix: choix) == nil, "un niveau qui n'existe pas")
    }

    /// « Hors de la maison », une case a cocher pour une zone a cote ; « Sur son propre niveau » : la zone
    /// redevient un etage, juste au-dessus du niveau qu'elle partageait. Rien pour un etage.
    @Test func dehorsEtPropreNiveau() throws {
        let choix = ["jardin": A(etage: "rdc", dehors: true), "garage": A(etage: "rdc")]
        let n = Niveaux(["rdc", "jardin", "garage", "etage"], aCote: choix)
        let rentre = try #require(n.basculerDehors("jardin", choix: choix))
        #expect(rentre.aCote["jardin"] == A(etage: "rdc") && rentre.ordre == n.plateaux)
        #expect(n.basculerDehors("rdc", choix: choix) == nil)
        let propre = try #require(n.propreNiveau("jardin", choix: choix))
        #expect(propre.ordre == ["rdc", "garage", "jardin", "etage"] && propre.aCote == ["garage": A(etage: "rdc")])
        #expect(Niveaux(propre.ordre, aCote: propre.aCote).liste == [["rdc", "garage"], ["jardin"], ["etage"]])
        #expect(n.propreNiveau("etage", choix: choix) == nil)
    }

    /// Les choix rendus : ceux des plateaux de la scene remis a plat (une chaine resolue, une zone a cote
    /// d'elle-meme oubliee) ; celui d'une zone dont l'etage principal est absent reste, comme celui d'un
    /// plateau absent.
    @Test func choixRendus() throws {
        let choix = ["a": A(etage: "b", dehors: true), "b": A(etage: "c"), "d": A(etage: "d"),
                     "e": A(etage: "zone:Ailleurs"), "zone:Absente": A(etage: "c")]
        let n = Niveaux(["a", "b", "c", "d", "e"], aCote: choix)
        let r = try #require(n.deplacer("d", de: 1, choix: choix))
        #expect(r.aCote == ["a": A(etage: "c", dehors: true), "b": A(etage: "c"), "e": A(etage: "zone:Ailleurs"),
                            "zone:Absente": A(etage: "c")])
        #expect(r.ordre == ["c", "a", "b", "e", "d"])
    }

    /// Le nouvel ordre fondu dans l'ordre garde (polissage D, section 4) : un plateau absent de la scene y garde son
    /// rang relatif, juste apres celui qui le precedait ; en tete s'il l'etait ; plusieurs absents de suite restent
    /// ensemble, dans leur ordre. Un plateau nouveau garde la place que lui donne le nouvel ordre ; sans ordre garde,
    /// le nouvel ordre.
    @Test func ordreFondu() {
        #expect(Rangement.fondre(["a", "c", "b"], dans: ["a", "x", "b", "c"]) == ["a", "x", "c", "b"])
        #expect(Rangement.fondre(["b", "a"], dans: ["x", "a", "b"]) == ["x", "b", "a"])
        #expect(Rangement.fondre(["b", "a"], dans: ["a", "x", "y", "b"]) == ["b", "a", "x", "y"])
        #expect(Rangement.fondre(["a", "n", "b"], dans: ["a", "b", "z"]) == ["a", "n", "b", "z"])
        #expect(Rangement.fondre(["a", "b"], dans: []) == ["a", "b"], "sans ordre garde : le nouvel ordre")
        #expect(Rangement.fondre(["b", "a"], dans: ["a", "b"]) == ["b", "a"], "sans absent : le nouvel ordre")
        var p = PlacesGardees()
        p.ordonner(["a", "x", "b"], domicile: "Maison")
        p.ranger(Rangement(ordre: ["b", "a"], aCote: [:]), domicile: "Maison")
        #expect(p.maison("Maison").ordreEtages == ["b", "a", "x"])
    }
}
