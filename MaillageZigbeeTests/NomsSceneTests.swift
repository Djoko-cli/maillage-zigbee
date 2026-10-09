import AppKit
import Foundation
@testable import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Vue par pieces : noms, apparences et scene de l'app")
struct NomsSceneTests {
    typealias I = NomsDemo.Ieee

    /// La demo, sur la maison des essais de la vue : quatre etages (`NomsDemo.maisonEtagee`), sans places gardees.
    static func surveillanceDemo() -> Surveillance {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        s.noms.maison = NomsDemo.maisonEtagee
        return s
    }

    static func demo() throws -> (Surveillance, EntreeScene) {
        let s = surveillanceDemo()
        return (s, EntreeScene(surveillance: s, places: PlacesGardees()))
    }

    /// Libelle d'un noeud : le nom coupe a 40 caracteres, la couronne du coordinateur, ☾ endormi, ⚠︎ disparu ; la
    /// pastille d'une batterie faible. Un noeud que le pont ne connait pas porte son adresse longue ; la sonde, « Sonde ».
    @Test func libelles() throws {
        let (_, e) = try Self.demo()
        #expect(e.libelles[I.pont]?.texte == "Pont Hue 👑")
        #expect(e.libelles[I.interrupteurSalon] == LibellesNoeuds.Libelle(texte: "Interrupteur salon ☾", nom: "Interrupteur salon"))
        #expect(e.libelles[I.priseSalon]?.texte == "Prise salon ⚠︎", "disparue")
        #expect(e.libelles[I.telecommandeChambre]?.pastille == String(localized: "\(12)\u{202F}%"))
        #expect(e.libelles[I.capteurGrenier]?.pastille == String(localized: "faible"))
        #expect(e.libelles[I.inconnu]?.texte == I.inconnu, "inconnu du pont : son adresse longue")
        #expect(e.libelles[I.sonde]?.texte == String(localized: "Sonde"))
        #expect(LibellesNoeuds.chefs(e.graphe) == [I.pont])
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(alerte: true)) == String(localized: "faible"))
        #expect(LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: 52)) == nil)
    }

    /// Pas de ☾ pour un noeud qui route : un routeur n'est jamais endormi, meme s'il a une pile ; la legende, qui reprend
    /// les signes de la scene, ne le compte pas parmi les endormis. Un appareil final a pile garde sa lune.
    @Test func pasDeLunePourUnNoeudQuiRoute() throws {
        let s = Self.surveillanceDemo()
        var maison = try #require(s.noms.maison)
        let k = try #require(maison.accessoires.firstIndex { $0.ieee == I.lampeArcade })
        maison.accessoires[k].batterie = BatterieMaison(niveau: 60)
        s.noms.maison = maison
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let n = try #require(e.scene.noeud(I.lampeArcade))
        #expect(n.routeur && e.appareils[I.lampeArcade]?.endormi == false)
        let texte = e.libelles[I.lampeArcade]?.texte ?? ""
        #expect(!texte.isEmpty && !texte.contains(LibellesNoeuds.lune), "\(texte)")
        #expect(!LibellesNoeuds.endormi(AppareilAffiche(id: "x", nom: "x", etat: .joignable, endormi: true), routeur: true))
        let lecture = LegendePieces.Lecture(e, ailleurs: false)
        #expect(!lecture.endormis.contains(I.lampeArcade) && lecture.endormis.contains(I.interrupteurSalon),
                "la legende : \(lecture.endormis.sorted())")
    }

    /// Pieces : celle que le pont donne a chaque appareil ; la sonde et le routeur inconnu n'en ont pas. Noms des etages,
    /// des pieces, compte, repere « ailleurs ».
    @Test func piecesEtNoms() throws {
        let (s, e) = try Self.demo()
        let pieces = LibellesNoeuds.pieces(appareils: s.appareilsAffiches, maison: s.noms.maison, graphe: e.graphe)
        #expect(pieces[I.pont] == "Salon" && pieces[I.lampeChambre] == "Chambre" && pieces[I.lampeBureau] == "Bureau")
        #expect(pieces[I.sonde] == nil && pieces[I.inconnu] == nil)
        #expect(LibellesNoeuds.nom(ScenePieces.NomEtage.zone("Étage")) == "Étage")
        #expect(LibellesNoeuds.nom(ScenePieces.NomEtage.maison) == String(localized: "Maison"))
        #expect(LibellesNoeuds.nom(ScenePieces.NomPiece.sansPiece, libelles: [:]) == String(localized: "Sans pièce"))
        #expect(LibellesNoeuds.nom(.routeur(I.pont), libelles: e.libelles) == "Pont Hue 👑")
        #expect(LibellesNoeuds.compte(1) == String(localized: "1 appareil"))
        #expect(LibellesNoeuds.compte(6) == String(localized: "\(6) appareils"))
        let sans = try #require(e.scene.pieces.firstIndex { $0.nom == .sansPiece })
        let sonde = try #require(SceneProjetee.reperes(e.scene, focus: sans).first { $0.enfant == I.sonde })
        #expect(LibellesNoeuds.ailleurs(sonde, scene: e.scene, libelles: e.libelles) == "↑ Lampe bureau · Bureau, Étage")
    }

    /// Un nom de plus de 40 caracteres est coupe a 39, suivi de « … », avant la couronne et ☾.
    @Test func nomCoupeA40Caracteres() throws {
        let (s, _) = try Self.demo()
        let interrupteur = "Interrupteur du salon, près de la baie vitrée"
        let pont = "Pont Hue du salon, derrière la télévision"
        #expect(interrupteur.count == 45 && pont.count == 41)
        s.renommer(I.interrupteurSalon, en: interrupteur)
        s.renommer(I.pont, en: pont)
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(e.libelles[I.interrupteurSalon]?.texte == "Interrupteur du salon, près de la baie …" + " ☾")
        #expect(e.libelles[I.pont]?.texte == "Pont Hue du salon, derrière la télévisi…" + " 👑")
    }

    /// Repere « ailleurs » d'un enfant dont le parent est le coordinateur : le nom du parent sans la couronne, avec ☾ ou
    /// ⚠︎ s'il en a (precision 20). Le detecteur de l'entree est sous le pont, au salon.
    @Test func repereAilleursSansCouronne() throws {
        let (_, e) = try Self.demo()
        #expect(e.libelles[I.pont]?.texte == "Pont Hue 👑")
        let reperes = e.scene.pieces.indices.flatMap { SceneProjetee.reperes(e.scene, focus: $0) }
        let a = try #require(reperes.first { $0.parent == I.pont })
        #expect(a.enfant == I.detecteurEntree)
        #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles) == "↗ Pont Hue · Salon")
        var disparu = e.libelles
        disparu[I.pont]?.texte = "Pont Hue 👑 ☾ ⚠︎"
        #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: disparu) == "↗ Pont Hue ☾ ⚠︎ · Salon")
    }

    /// Repere « ailleurs » d'un parent au meme niveau, dans une autre zone (polissage C, section 5.2) : ↗, avec le nom
    /// de sa zone. L'entree mise dans un « Jardin » a cote du rez-de-chaussee : le parent de son detecteur, le pont, est
    /// au salon. Sans le choix, le jardin est un etage au-dessus : ↓.
    @Test func repereAuMemeNiveau() throws {
        let (s, _) = try Self.demo()
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Buanderie"]),
                        ZoneMaison(nom: "Jardin", pieces: ["Entrée"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
                        ZoneMaison(nom: "Combles", pieces: ["Terrasse", "Abri", "Grenier", "Salle de jeux"])]
        s.noms.maison = maison
        var places = PlacesGardees()
        places.ranger(Rangement(ordre: [], aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée")]),
                      domicile: maison.domicile ?? "")
        for (p, attendu) in [(places, "↗ Pont Hue · Salon, Rez-de-chaussée"), (PlacesGardees(), "↓ Pont Hue · Salon, Rez-de-chaussée")] {
            let e = EntreeScene(surveillance: s, places: p)
            let entree = try #require(e.scene.pieces.firstIndex { $0.nom == .maison("Entrée") })
            let a = try #require(SceneProjetee.reperes(e.scene, focus: entree).first { $0.enfant == I.detecteurEntree })
            #expect(LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles) == attendu)
        }
    }

    /// Un noeud que le pont ne place pas passe dans la piece choisie pour son adresse longue (precision 27) : la sonde,
    /// le routeur inconnu ; la piece du pont passe avant le choix. La disposition suit.
    @Test func piecesDesAppareils() throws {
        let (s, _) = try Self.demo()
        let domicile = try #require(s.noms.maison?.domicile)
        var choix = PiecesRouteurs()
        choix.choisir("Cuisine", appareil: I.inconnu, domicile: domicile)
        choix.choisir("Bureau", appareil: I.sonde, domicile: domicile)
        choix.choisir("Salon", appareil: I.lampeBureau, domicile: domicile)
        let avant = EntreeScene(surveillance: s, places: PlacesGardees())
        let e = EntreeScene(surveillance: s, places: PlacesGardees(), choix: choix)
        func piece(_ e: EntreeScene, _ id: String) throws -> ScenePieces.NomPiece {
            e.scene.pieces[try #require(e.scene.noeud(id)).piece].nom
        }
        #expect(try piece(avant, I.inconnu) == .sansPiece && piece(avant, I.sonde) == .sansPiece)
        #expect(try piece(e, I.inconnu) == .maison("Cuisine"), "inconnu du pont")
        #expect(try piece(e, I.sonde) == .maison("Bureau"), "la sonde")
        #expect(try piece(e, I.lampeBureau) == .maison("Bureau"), "le pont passe avant le choix")
        #expect(e.cleDisposition != avant.cleDisposition)
    }

    /// La maison des essais (polissage C, section 7) : les quatre plateaux et les douze pieces des maquettes, « Sans
    /// piece » sur le plateau du bas ; avec son choix de niveau, le jardin au niveau du rez-de-chaussee, hors de la
    /// maison ; les apparences des noeuds.
    @Test func sceneDeLaDemo() throws {
        let (s, e) = try Self.demo()
        #expect(e.scene.etages.map(\.nom) == [.zone("Rez-de-chaussée"), .zone("Jardin"), .zone("Étage"), .zone("Combles")])
        func pieces(_ k: Int) -> [ScenePieces.NomPiece] { e.scene.etages[k].pieces.map { e.scene.pieces[$0].nom } }
        #expect(pieces(0) == [.maison("Buanderie"), .maison("Cuisine"), .maison("Entrée"), .maison("Salon"), .sansPiece])
        #expect(pieces(1) == [.maison("Abri"), .maison("Terrasse")])
        #expect(pieces(2) == [.maison("Bureau"), .maison("Chambre"), .maison("Chambre d'amis"), .maison("Salle de bain")])
        #expect(pieces(3) == [.maison("Grenier"), .maison("Salle de jeux")])
        let niveaux = EntreeScene(surveillance: s, places: NomsDemo.places(etagee: true)).scene
        #expect(niveaux.niveaux.liste == [["zone:Rez-de-chaussée", "zone:Jardin"], ["zone:Étage"], ["zone:Combles"]])
        #expect(niveaux.etages.map(\.dehors) == [false, true, false, false])
        // Un routeur dans la salle de jeux et sur la terrasse ; des liens entre niveaux et au meme niveau.
        for (id, piece) in [(I.lampeArcade, "Salle de jeux"), (I.priseTerrasse, "Terrasse")] {
            let n = try #require(niveaux.noeud(id))
            #expect(n.routeur && niveaux.pieces[n.piece].nom == .maison(piece))
        }
        let niveau = { (id: String) in niveaux.noeud(id).map { niveaux.etages[niveaux.pieces[$0.piece].etage].niveau } }
        let liens = niveaux.liens.filter { $0.genre == .radio }.map { (niveau($0.de), niveau($0.vers)) }
        #expect(liens.contains { $0.0 != $0.1 } && liens.contains { $0.0 == $0.1 })
        #expect(!e.scene.sansPiecesMaison)
        #expect(e.domicile == "Maison (démo)")
        #expect(e.apparences[I.pont] == DessinNoeud.Apparence(forme: .sphere(halo: 10), couleur: .routeur))
        #expect(e.apparences[I.lampeBureau] == DessinNoeud.Apparence(forme: .sphere(halo: 5), couleur: .routeur))
        #expect(e.apparences[I.inconnu]?.couleur == .routeurInconnu)
        #expect(e.apparences[I.priseSalon] == DessinNoeud.Apparence(forme: .anneau, couleur: .appareil(.disparu)))
        #expect(e.apparences[I.interrupteurSalon] == DessinNoeud.Apparence(forme: .pastille, couleur: .appareil(.joignable)))
        #expect(e.apparences[I.sonde]?.couleur == .appareil(.inconnu), "la sonde n'est pas un appareil du pont")
    }

    /// La demo de l'app a les etages de son releve de Maison (etape 4 bis) : les quatre zones, dans l'ordre garde (le
    /// jardin a cote du rez-de-chaussee) ; sans releve de Maison, les noms du pont seuls n'en ont pas : un plateau.
    @Test func demoDeLAppParEtages() {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let e = EntreeScene(surveillance: s, places: NomsDemo.places(etagee: true))
        #expect(e.scene.etages.map(\.nom) == NomsDemo.zones.map { .zone($0.nom) })
        #expect(e.scene.pieces.count == 13, "les douze pieces et « Sans piece »")
        s.releveMaison = nil
        let pont = EntreeScene(surveillance: s, places: NomsDemo.places(etagee: true))
        #expect(pont.scene.etages.map(\.nom) == [.maison])
        #expect(pont.scene.pieces.count == 13)
    }

    /// La cle de la disposition ne change pas avec l'etat d'un noeud ; elle change avec son nom. Elle suit les
    /// niveaux tels que les voit le cout (polissage C, section 4) : une zone mise a cote d'un etage la change ;
    /// l'ordre des niveaux au-dessus du plateau du bas (qui porte « Sans piece »), ou une zone sortie de la
    /// maison, non.
    @Test func cleDeLaDisposition() throws {
        let (s, e) = try Self.demo()
        #expect(EntreeScene(surveillance: s, places: PlacesGardees()).cleDisposition == e.cleDisposition)
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Chambre d'amis"]),
                        ZoneMaison(nom: "Combles", pieces: ["Bureau", "Salle de bain"])]
        s.noms.maison = maison
        let domicile = maison.domicile ?? ""
        func cle(_ ordre: [String], _ aCote: [String: PlacesGardees.ACote]) -> EntreeScene.CleDisposition {
            var p = PlacesGardees()
            p.ranger(Rangement(ordre: ordre, aCote: aCote), domicile: domicile)
            return EntreeScene(surveillance: s, places: p).cleDisposition
        }
        let rdc = "zone:Rez-de-chaussée", etage = "zone:Étage", combles = "zone:Combles"
        let depart = cle([rdc, etage, combles], [:])
        let aCote = cle([rdc, etage, combles], [combles: PlacesGardees.ACote(etage: etage)])
        #expect(aCote != depart, "les combles a cote de l'etage")
        #expect(cle([rdc, combles, etage], [:]) == depart, "l'ordre des niveaux")
        #expect(cle([rdc, etage, combles], [combles: PlacesGardees.ACote(etage: etage, dehors: true)]) == aCote,
                "hors de la maison")
        s.renommer(I.lampeBureau, en: "Lampe de travail")
        #expect(cle([rdc, etage, combles], [:]) != depart)
    }

    /// Un badge qui change ne change ni la scene ni la cle de la disposition (polissage D, section 2) : une pile qui
    /// faiblit donne sa pastille au libelle, sans plus. Le moteur pose la scene tout de suite, sans calcul : rien ne
    /// bouge, ni piece ni carte, rien ne glisse ; seul le nom change.
    @Test func unBadgeNeBougeRien() throws {
        let (s, e) = try Self.demo()
        let m = MoteurPiecesTests.moteur(e)
        var maison = try #require(s.noms.maison)
        let k = try #require(maison.accessoires.firstIndex { $0.ieee == I.interrupteurSalon })
        maison.accessoires[k].batterie = BatterieMaison(niveau: 5)
        s.noms.maison = maison
        let e2 = EntreeScene(surveillance: s, places: PlacesGardees())
        let inter = I.interrupteurSalon
        #expect(e2.libelles[inter]?.pastille == String(localized: "\(5)\u{202F}%") && e.libelles[inter]?.pastille == nil)
        #expect(e2.scene == e.scene && e2.cleDisposition == e.cleDisposition && e2 != e)
        // La scene ne voit que les noms : ni ☾, ni la couronne du coordinateur.
        #expect(e.libelles[inter]?.texte == "Interrupteur salon ☾" && e.scene.noeud(inter)?.libelle == "Interrupteur salon")
        #expect(e.libelles[I.pont]?.texte == "Pont Hue 👑" && e.scene.noeud(I.pont)?.libelle == "Pont Hue")
        let (positions, cartes) = (m.positions, m.cartes)
        // Les cartes tiennent le pire cas de chaque nom, tel qu'il s'afficherait : tous les badges qu'il peut porter, et la
        // plus large des pastilles si sa pile est connue. Le noeud route selon le graphe, non selon son rang.
        let mesure = MesureNoms()
        let pires = Dictionary(uniqueKeysWithValues: e.scene.noeuds.map { n -> (String, Double) in
            let route = n.bordure || n.routeur
            let texte = CartesPieces.texte(n.libelle, chef: route, endormi: !route, alerte: true)
            let pastille = n.pile ? Self.pastilleLaPlusLarge(mesure) : nil
            let pire = LibellesNoeuds.Libelle(texte: texte, pastille: pastille, nom: n.libelle)
            return (n.id, Double(mesure.noeud(pire, routeur: route).width))
        })
        #expect(cartes == CartesPieces.cartes(e.scene, largeurs: pires), "les cartes reservent la place des badges")
        #expect(MoteurPiecesTests.moteur(e2).cartes == cartes, "la pastille de l'interrupteur ne change pas les cartes")
        m.recevoir(e2)
        #expect(m.entree == e2, "posee tout de suite, sans calcul")
        #expect(m.positions == positions && m.cartes == cartes && m.transition == nil && m.glissementPlateaux == nil)
        #expect(m.textes.noeuds[inter]?.pastille == String(localized: "\(5)\u{202F}%"))
        // Une pile qui devient connue (decision du 05/10) : la cle change, et la carte de la cuisine s'elargit, une fois.
        let k2 = try #require(maison.accessoires.firstIndex { $0.ieee == I.suspensionCuisine })
        maison.accessoires[k2].batterie = BatterieMaison(niveau: 80)
        s.noms.maison = maison
        let e3 = EntreeScene(surveillance: s, places: PlacesGardees())
        let cuisine = try MoteurPiecesTests.indice(e, "Cuisine")
        #expect(e3.cleDisposition != e.cleDisposition && e3.scene.noeud(I.suspensionCuisine)?.pile == true)
        #expect(e.scene.noeud(I.suspensionCuisine)?.pile == false && e.scene.noeud(inter)?.pile == true)
        #expect(MoteurPiecesTests.moteur(e3).cartes[cuisine].largeur > cartes[cuisine].largeur)
    }

    /// Les pastilles d'une pile faible, en valeurs fixes : un niveau de 1 a 3 chiffres (0 a 100 %), ou « faible ».
    static let pastilles = [0, 5, 9, 10, 50, 88, 99, 100].map { String(localized: "\($0)\u{202F}%") }
        + [String(localized: "faible")]

    /// La plus large d'entre elles, mesuree : celle que la carte reserve.
    static func pastilleLaPlusLarge(_ mesure: MesureNoms) -> String {
        pastilles.max { mesure.pastille($0).width < mesure.pastille($1).width } ?? ""
    }

    /// La place que la carte reserve au nom de chaque noeud de la demo (polissage D, section 2), avec la vraie police :
    /// chacun de ses noms affiches y tient, quels que soient ses badges, la pastille la plus large comprise pour un noeud
    /// dont la pile est connue ; sans pile connue, la reserve n'a pas de pastille (decision du 05/10).
    @Test func reserveDesBadges() throws {
        let (_, e) = try Self.demo()
        let mesure = MesureNoms()
        let large = mesure.pastilleReservee
        let largeur = mesure.pastille(large).width
        #expect(Self.pastilles.contains(large) && Self.pastilles.allSatisfy { mesure.pastille($0).width <= largeur })
        for n in e.scene.noeuds {
            let routeur = n.route
            let reserve = mesure.reserve(n.libelle, routeur: routeur, pile: n.pile)
            for badge in [false, true] {
                for alerte in [false, true] {
                    let texte = CartesPieces.texte(n.libelle, chef: routeur && badge, endormi: !routeur && badge, alerte: alerte)
                    let pire = LibellesNoeuds.Libelle(texte: texte, pastille: n.pile ? large : nil, nom: n.libelle)
                    let affiche = mesure.noeud(pire, routeur: routeur)
                    #expect(affiche.width <= reserve.width && affiche.height <= reserve.height, "\(texte)")
                }
            }
            let sansPastille = mesure.noeud(LibellesNoeuds.Libelle(texte: CartesPieces.texteReserve(n.libelle, routeur: routeur)),
                                            routeur: routeur)
            #expect(n.pile ? reserve.width > sansPastille.width : reserve == sansPastille, "\(n.libelle)")
            #expect(mesure.reserve(n.libelle, routeur: routeur, pile: true).width > sansPastille.width)
        }
        #expect(e.scene.noeuds.filter(\.pile).count == 7, "les sept piles connues de la demo")
    }

    /// La scene porte ce dont elle est faite, construit une fois avec elle : le graphe, le maillage de la sonde, le
    /// coordinateur couronne et les appareils affiches. Ils n'entrent pas dans l'egalite : un maillage recu plus tard, qui
    /// ne change rien a la scene, ne la fait pas reposer par le moteur.
    @Test func constructionDeLaScene() throws {
        let (s, e) = try Self.demo()
        let m = try #require(s.maillageAffiche)
        #expect(e.maillage == m)
        #expect(e.graphe == GrapheReseau(maillage: m, appareils: s.appareilsAffiches))
        #expect(e.chefs == [I.pont])
        #expect(Set(e.libelles.filter { $0.value.texte.contains("👑") }.keys) == e.chefs, "la couronne suit le coordinateur")
        #expect(e.appareils[I.lampeBureau]?.piece == "Bureau")
        var plusTard = m
        plusTard.date = m.date.addingTimeInterval(60)
        s.recevoir(plusTard, a: s.maintenant)
        let apres = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(apres.maillage?.date != e.maillage?.date)
        #expect(apres == e, "la meme scene")
    }

    /// Sur la maison de demo, avec les cartes du moteur, qui reservent la place des badges (polissage D, section 2) :
    /// aucun lien ne passe sur une piece autre que celles de ses bouts, aucune carte n'en recouvre une autre.
    @Test func demoSansTraversee() throws {
        let (_, e) = try Self.demo()
        let cartes = MoteurPiecesTests.moteur(e).cartes
        let d = DispositionPieces(scene: e.scene, cartes: cartes)
        let calcul = DispositionPieces.Calcul(scene: e.scene, cartes: cartes, fixees: [:])
        #expect(calcul.traversees(d.positions) == 0)
        #expect(d.cout < d.coutDepart)
        for et in e.scene.etages {
            for (k, a) in et.pieces.enumerated() {
                for b in et.pieces[(k + 1)...] {
                    let dx = abs(d.positions[b].x - d.positions[a].x), dz = abs(d.positions[b].y - d.positions[a].y)
                    let px = (cartes[a].largeur + cartes[b].largeur) / 2 + DispositionPieces.gap - dx
                    let pz = (cartes[a].profondeur + cartes[b].profondeur) / 2 + DispositionPieces.gap + DispositionPieces.lab - dz
                    #expect(!(px > 1e-6 && pz > 1e-6), "\(e.scene.pieces[a].id) / \(e.scene.pieces[b].id)")
                }
            }
        }
    }

    /// Tailles des textes rendues par `Canvas` a l'echelle 1, 2 et 3.
    static func taillesDessinees(_ textes: [Text], echelle: CGFloat) -> [CGSize] {
        final class Boite: @unchecked Sendable { var tailles: [CGSize] = [] }
        let boite = Boite()
        let rendu = ImageRenderer(content: Canvas { ctx, _ in
            boite.tailles = textes.map { ctx.resolve($0).measure(in: StylesNoms.grand) }
        }.frame(width: 10, height: 10))
        rendu.scale = echelle
        _ = rendu.cgImage
        return boite.tailles
    }

    /// La taille mesuree hors du `Canvas` couvre le texte dessine, a toute echelle : un nom ne deborde
    /// pas de la place que le placement lui donne (moins d'un point pres). Noms nus ou coupes a 40
    /// caracteres, en ecriture latine, chinoise ou japonaise ; pastille d'une batterie faible ; nom
    /// d'etage, de piece avec son compte, de la maison ; repere « ailleurs ». Les marges sont celles du
    /// dessin (`RenduCanvas.dessinerNoms`).
    @Test func tailleMesureeCommeDessinee() {
        let mesure = MesureNoms()
        let long = CartesPieces.couper("Serrure connectée de la porte arrière, garage")
        #expect(long.count == 40)
        let noms = ["Détecteur de passage lingerie sud ☾", "Lampe chambre d'amis", "Pont Hue 👑", "Salon", long,
                    long + " 👑 ☾ ⚠︎", "客厅吸顶灯 ☾", "寝室のスマートプラグ ⚠︎"]
        let pastilles = [String(localized: "\(12)\u{202F}%"), String(localized: "faible")]
        let comptes = [LibellesNoeuds.compte(1), LibellesNoeuds.compte(12)]
        for echelle in [1.0, 2.0, 3.0] {
            for n in noms {
                for routeur in [false, true] {
                    let dessinee = Self.taillesDessinees([StylesNoms.noeud(n, routeur: routeur, fort: true)],
                                                         echelle: echelle)[0]
                    let place = mesure.noeud(LibellesNoeuds.Libelle(texte: n), routeur: routeur)
                    #expect(dessinee.width + 10 <= place.width + 1 && dessinee.height <= place.height + 1,
                            "\(n) a \(echelle) : \(dessinee) dans \(place)")
                    // Pastille : 5 points, le texte, 5 points, la capsule, 5 points.
                    for v in pastilles {
                        let t = Self.taillesDessinees([DessinNoeud.iconePastille, DessinNoeud.textePastille(v)],
                                                      echelle: echelle)
                        let capsule = DessinNoeud.taillePastille(icone: t[0], valeur: t[1])
                        let avec = mesure.noeud(LibellesNoeuds.Libelle(texte: n, pastille: v, nom: n), routeur: routeur)
                        #expect(5 + ceil(dessinee.width) + 5 + capsule.width + 5 <= avec.width + 1
                                && capsule.height <= avec.height + 1 && dessinee.height <= avec.height + 1,
                                "\(n) et \(v) a \(echelle) : \(dessinee) et \(capsule) dans \(avec)")
                    }
                }
                let t = Self.taillesDessinees([StylesNoms.etage(n)], echelle: echelle)[0]
                let e = mesure.etage(n)
                #expect(t.width <= e.width + 1 && t.height <= e.height + 1)
                // Piece : bordure 1, marge 7, point 8, 6, nom, 6, compte, marge 7, bordure 1 ; 20 de haut.
                for c in comptes {
                    let d = Self.taillesDessinees([StylesNoms.nomPiece(n), StylesNoms.comptePiece(c)], echelle: echelle)
                    let piece = mesure.piece(nom: n, compte: c)
                    #expect(28 + ceil(d[0].width) + d[1].width + 8 <= piece.width + 1
                            && max(d[0].height, d[1].height) <= piece.height + 1,
                            "\(n), \(c) a \(echelle) : \(d) dans \(piece)")
                }
                // Repere « ailleurs » : bordure 1, marge 5, texte, marge 5, bordure 1 ; 1 dessus et dessous.
                let ailleurs = "↓ " + n + " · Chambre d'amis, Rez-de-chaussée"
                let a = Self.taillesDessinees([StylesNoms.ailleurs(ailleurs)], echelle: echelle)[0]
                let place = mesure.ailleurs(ailleurs)
                #expect(a.width + 12 <= place.width + 1 && a.height + 2 <= place.height + 1,
                        "\(ailleurs) a \(echelle) : \(a) dans \(place)")
            }
            let maison = String(localized: "⌂ Maison")
            let m = Self.taillesDessinees([StylesNoms.maison(maison)], echelle: echelle)[0]
            #expect(m.width <= mesure.maison(maison).width + 1 && m.height <= mesure.maison(maison).height + 1)
        }
    }

    /// Le noeud route, dans le moteur (relecture finale, Mineur 11) : les routeurs du dessin sont
    /// les noeuds qui routent, de rang 1 ou 2 ; le nom de chacun est mesure en routeur (12 points), plus large que le
    /// meme texte en appareil.
    @Test func routeursDuMoteur() throws {
        let (_, e) = try Self.demo()
        let m = MoteurPiecesTests.moteur(e)
        let routent = e.scene.noeuds.filter(\.route)
        #expect(routent.contains { $0.rang == 2 } && routent.contains { $0.rang == 1 }, "des deux rangs")
        #expect(m.routeurs == Set(routent.map(\.id)) && !m.routeurs.isEmpty)
        let mesure = MesureNoms()
        for n in routent {
            let libelle = try #require(m.textes.noeuds[n.id])
            let taille = try #require(m.etiquettes.first { $0.genre == .noeud(n.id) }?.taille)
            let routeur = mesure.noeud(libelle, routeur: true), appareil = mesure.noeud(libelle, routeur: false)
            #expect(taille == routeur && routeur.width > appareil.width, "\(n.id) : \(taille) \(appareil)")
        }
    }
}
