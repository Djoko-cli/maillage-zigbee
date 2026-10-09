import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Vue par pieces : la legende")
struct LegendePiecesTests {
    typealias Entree = LegendePieces.Entree
    typealias Lecture = LegendePieces.Lecture

    static func radio(_ qualite: Int?) -> ScenePieces.Lien {
        ScenePieces.Lien(de: "A0000000000000A1", vers: "A0000000000000A2", genre: .radio, qualite: qualite)
    }

    /// Une scene inventee par signe : chacune ne contient que lui, et la legende n'a que son entree. Un noeud que le
    /// pont ne connait pas, routeur ou appareil, est « inconnu du pont » ; un appareil d'etat inconnu, gris lui aussi,
    /// n'a pas d'entree. Une qualite de 0 (un LQI sous 50) est un lien faible : Zigbee le mesure (`NiveauQualite`).
    @Test func uneEntreeParSigne() {
        let cas: [(Lecture, Set<Entree>)] = [
            (Lecture(couleurs: ["A000000000000001": .routeur]), [.routeur]),
            (Lecture(couleurs: ["A0000000000000FD": .routeurInconnu], inconnus: ["A0000000000000FD"]), [.nonIdentifie]),
            (Lecture(couleurs: ["A0000000000000FC": .appareil(.inconnu)], inconnus: ["A0000000000000FC"]), [.nonIdentifie]),
            (Lecture(chefs: ["A000000000000001"]), [.coordinateur]),
            (Lecture(couleurs: ["A000000000000021": .appareil(.joignable)]), [.joignable]),
            (Lecture(couleurs: ["A000000000000022": .appareil(.injoignable)]), [.injoignable]),
            (Lecture(couleurs: ["A000000000000023": .appareil(.disparu)]), [.disparu]),
            (Lecture(endormis: ["A000000000000024"]), [.endormi]),
            (Lecture(piles: ["A000000000000025"]), [.pile]),
            (Lecture(liens: [Self.radio(3)]), [.bonne]),
            (Lecture(liens: [Self.radio(2)]), [.moyenne]),
            (Lecture(liens: [Self.radio(1)]), [.faible]),
            (Lecture(liens: [Self.radio(0)]), [.faible]),
            (Lecture(liens: [Self.radio(nil)]), [.inconnue]),
            (Lecture(liens: [ScenePieces.Lien(de: "A000000000000021", vers: "A0000000000000A1", genre: .parent, qualite: 3)]),
             [.versParent]),
            (Lecture(liens: [ScenePieces.Lien(de: "A000000000000021", vers: "A000000000000001")]), []),
            (Lecture(ailleurs: true), [.ailleurs]),
            (Lecture(couleurs: ["A000000000000027": .appareil(.inconnu)]), []),
            (Lecture(), []),
        ]
        for (lecture, attendu) in cas {
            #expect(LegendePieces.entrees(lecture) == attendu, "\(attendu)")
        }
    }

    /// Les groupes dans l'ordre de la grille (routeurs, appareils, liens radio, autres), leurs entrees
    /// dans l'ordre de la spec ; un groupe sans entree disparait, et une scene vide n'a pas de legende.
    @Test func groupesEtOrdre() {
        let tout = Lecture(couleurs: ["a": .routeur, "c": .appareil(.joignable), "d": .appareil(.injoignable),
                                      "f": .appareil(.disparu)],
                           inconnus: ["g"], chefs: ["a"], endormis: ["c"], piles: ["c"],
                           liens: [Self.radio(3), Self.radio(2), Self.radio(1), Self.radio(nil),
                                   ScenePieces.Lien(de: "c", vers: "a", genre: .parent),
                                   ScenePieces.Lien(de: "g", vers: "a", genre: .parent, suppose: true),
                                   ScenePieces.Lien(de: "A0000000000000A2", vers: "a", genre: .chemin, qualite: 3),
                                   ScenePieces.Lien(de: "A0000000000000A1", vers: "a", genre: .chemin, suppose: true)],
                           ailleurs: true, mode: .chemins)
        #expect(LegendePieces.rubriques(tout) == LegendePieces.Groupe.allCases.map {
            LegendePieces.Rubrique(groupe: $0, entrees: $0.entrees)
        })
        // En mode « tous » : ni chemin, ni voisin entendu, les qualites des liens radio.
        var tous = tout
        tous.mode = .tous
        #expect(LegendePieces.rubriques(tous).first { $0.groupe == .liens }?.entrees == [.bonne, .moyenne, .faible, .inconnue])
        // Voisins entendus masques (mode « chemins ») : ni leur entree ni les qualites des liens radio ; les chemins
        // gardent les leurs (bonne, et inconnue pour le chemin suppose sans mesure).
        var masques = tout
        masques.voisins = false
        let sansVoisins = LegendePieces.rubriques(masques)
        #expect(sansVoisins.first { $0.groupe == .autres }?.entrees == [.chemin, .cheminSuppose, .versParent, .parentDAvant, .ailleurs])
        #expect(sansVoisins.first { $0.groupe == .liens }?.entrees == [.bonne, .inconnue])
        #expect(LegendePieces.entrees(masques).contains(.voisinEntendu) == false)
        // Un parent d'avant (pointille) a son entree, a cote de « vers son parent ».
        let davant = Lecture(liens: [ScenePieces.Lien(de: "c", vers: "a", genre: .parent, suppose: true)])
        #expect(LegendePieces.entrees(davant) == [.parentDAvant])
        #expect(LegendePieces.signe(.parentDAvant) == .lienEnfant(rattachement: true))
        #expect(Entree.parentDAvant.texte == String(localized: "parent d'avant (pointillé)"))
        // En mode « chemins » sans liens radio : les chemins et leurs qualites seulement.
        let chemins = Lecture(liens: [ScenePieces.Lien(de: "x", vers: "a", genre: .chemin, qualite: 2)], mode: .chemins)
        #expect(LegendePieces.entrees(chemins) == [.chemin, .moyenne])
        #expect(Set(LegendePieces.Groupe.allCases.flatMap(\.entrees)) == Set(Entree.allCases), "chaque entree a son groupe")
        let sansLiens = Lecture(couleurs: ["c": .appareil(.joignable)], chefs: ["a"], ailleurs: true)
        #expect(LegendePieces.rubriques(sansLiens) == [
            LegendePieces.Rubrique(groupe: .routeurs, entrees: [.coordinateur]),
            LegendePieces.Rubrique(groupe: .appareils, entrees: [.joignable]),
            LegendePieces.Rubrique(groupe: .autres, entrees: [.ailleurs]),
        ])
        #expect(LegendePieces.rubriques(Lecture()).isEmpty)
    }

    /// La scene de la demo, lue telle que la fenetre la dessine : avec la sonde, puis sans (plus de liens : les groupes
    /// des liens et des autres disparaissent) ; une piece isolee qui pose des reperes « ailleurs ».
    @Test func legendeDeLaDemo() throws {
        let (s, e) = try NomsSceneTests.demo()
        let avec = LegendePieces.entrees(Lecture(e, ailleurs: false))
        #expect(avec == [.routeur, .nonIdentifie, .coordinateur, .joignable, .disparu, .endormi, .pile, .bonne, .moyenne,
                         .faible, .versParent, .parentDAvant])
        #expect(LegendePieces.entrees(Lecture(e, ailleurs: true)).contains(.ailleurs))
        // En mode « chemins » (celui de la fenetre par defaut) : les chemins lus et supposes, les voisins entendus.
        let chemins = LegendePieces.entrees(Lecture(e, ailleurs: false, mode: .chemins))
        #expect(chemins.isSuperset(of: [.chemin, .cheminSuppose, .voisinEntendu, .versParent]))
        s.oublierMaillage()
        let sans = try #require(FenetrePiecesTests.entree(s))
        #expect(sans.maillage == nil)
        let rubriques = LegendePieces.rubriques(Lecture(sans, ailleurs: false))
        #expect(rubriques.map(\.groupe) == [.appareils])
    }

    /// Les signes de la legende reprennent ceux de la scene : la pastille d'une pile (« 12 % »), un repere « ailleurs ».
    @Test func exemples() {
        #expect(LegendePieces.exemplePile == String(localized: "\(12)\u{202F}%"))
        #expect(LegendePieces.exempleAilleurs == String(localized: "→ Salon"))
    }

    /// Deux colonnes de meme largeur : la moitie d'un panneau de 440 pt, ou celle du groupe le plus large.
    @Test func colonnes() {
        #expect(GrilleLegende.largeurColonne([120, 150]) == 199)
        #expect(GrilleLegende.largeurColonne([251, 120]) == 251)
        #expect(GrilleLegende.largeurColonne([]) == 199)
    }

    /// Le repli est garde dans les preferences (`legendeRepliee`), par la ligne du bas : repliee, il ne
    /// reste que l'etiquette ; un etat impose (captures) passe avant, sans ecrire la preference.
    @Test func repliGarde() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let (_, e) = try NomsSceneTests.demo()
        #expect(LegendePieces.cleRepliee == "legendeRepliee")
        func taille(_ v: LigneDuBas) -> CGSize {
            NSHostingView(rootView: v.defaultAppStorage(p)).fittingSize
        }
        let ouverte = taille(LigneDuBas(moteur: MoteurPieces(), entree: e))
        p.set(true, forKey: LegendePieces.cleRepliee)
        let repliee = taille(LigneDuBas(moteur: MoteurPieces(), entree: e))
        #expect(repliee.height < 40 && ouverte.height > 4 * repliee.height, "\(repliee) \(ouverte)")
        #expect(taille(LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: false)) == ouverte)
        p.set(false, forKey: LegendePieces.cleRepliee)
        #expect(taille(LigneDuBas(moteur: MoteurPieces(), entree: e)) == ouverte)
        #expect(taille(LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: true)) == repliee)
        #expect(p.bool(forKey: LegendePieces.cleRepliee) == false, "l'etat impose n'ecrit rien")
        let tout = LegendePieces.Groupe.allCases.map { LegendePieces.Rubrique(groupe: $0, entrees: $0.entrees) }
        func legende(_ r: [LegendePieces.Rubrique]) -> CGSize {
            NSHostingView(rootView: LegendePieces(rubriques: r, repliee: .constant(false))).fittingSize
        }
        #expect(legende(tout).width >= GrilleLegende.largeurPanneau)
        #expect(legende([]) == .zero, "sans entree, pas de legende")
    }

    /// La marge du bas suit la hauteur mesuree de tout ce qui est pose en bas (decision de Djoko du 01/10 pour la
    /// legende ouverte, du 02/10 pour la fiche, comme la marge du haut suit le bandeau) : la pile, de haut en bas la
    /// legende, puis la fiche ; le bord et l'espacement en plus. La ligne de niveau, montee en haut le 02/10, n'y est
    /// plus : la rangee du bas a la hauteur de la legende seule. La legende repliee sans fiche : la marge d'avant,
    /// 30 pt. Les valeurs fixes de la fiche (190 et 360 pt) ne sont plus : la pile d'une fiche est mesuree, legende
    /// ouverte ou repliee au-dessus d'elle.
    @Test func margeDuBas() throws {
        let (s, e) = try NomsSceneTests.demo()
        func hauteur(_ v: some View) -> CGFloat {
            NSHostingView(rootView: v.environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize.height
        }
        let h = hauteur(LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: false))
        #expect(h > 150, "la legende de la demo, ouverte : \(h)")
        let rubriques = LegendePieces.rubriques(LegendePieces.Lecture(e, ailleurs: false, mode: .chemins))
        #expect(h == hauteur(LegendePieces(rubriques: rubriques, repliee: .constant(false))), "la legende seule, sans la ligne de niveau")
        #expect(FenetrePieces.margeBas(pile: h) == FenetrePieces.bord + ceil(h) + FenetrePieces.espacement)
        #expect(FenetrePieces.margeBas(pile: nil) == 30, "repliee, sans fiche")
        #expect(FenetrePieces.margeBas(pile: 2) == 30)
        for repliee in [false, true] {
            let rangee = hauteur(LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee))
            let pile = hauteur(VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee)
                FicheNoeud(id: NomsDemo.Ieee.pont, entree: e, instant: Date(), aRenommer: .constant(nil)) {}
            }.frame(width: FenetrePieces.largeurParDefaut - 2 * FenetrePieces.bord))
            #expect(pile > rangee + FenetrePieces.espacement + 80, "repliee : \(repliee) ; la fiche sous la rangee (\(pile) pt)")
            #expect(FenetrePieces.margeBas(pile: pile) == FenetrePieces.bord + ceil(pile) + FenetrePieces.espacement)
        }
    }

    /// La vue d'ensemble se cadre au-dessus de la legende ouverte : dans une fenetre de 1440 x 900, aucun
    /// bloc, aucune pastille ni aucun nom de piece de la demo ne descend sous son bord du haut, en 2D
    /// comme en 3D.
    @Test(arguments: [false, true]) func vueAuDessusDeLaLegende(_ troisD: Bool) throws {
        let (_, e) = try NomsSceneTests.demo()
        let h = NSHostingView(rootView: LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: false))
            .fittingSize.height
        let taille = CGSize(width: 1440, height: 900)
        let m = MoteurPieces(troisD: troisD)
        m.fige = true
        m.marges = (FenetrePieces.margeHaut(bas: 90), FenetrePieces.margeBas(pile: h))
        m.poserTaille(taille)
        m.installerMaintenant(e)
        m.poserTaille(taille)
        MoteurPiecesTests.dessiner(m, taille: taille)
        let haut = taille.height - FenetrePieces.bord - h
        let p = try #require(m.projetee)
        #expect(!p.blocs.isEmpty && !p.disques.isEmpty)
        #expect(p.blocs.allSatisfy { b in b.faces.allSatisfy { f in f.points.allSatisfy { $0.y <= haut } } })
        #expect(p.disques.allSatisfy { $0.centre.y + $0.rayon <= haut })
        #expect(p.ancresPieces.values.allSatisfy { $0.maxY <= haut })
    }

    /// « Releve de la sonde ancien » n'est plus dans la legende : c'est une pastille a cote de la ligne de
    /// niveau, quand le releve est ancien, en haut a gauche dans la colonne (`RangeeNiveau`, decision de Djoko du
    /// 02/10, qui l'avait en bas). La rangee garde la hauteur de la pastille, qu'elle soit la ou non : elle est plus
    /// large avec elle, pas plus haute.
    @Test func pastilleDuReleveAncien() {
        let m = MoteurPieces()
        func taille(_ ancien: Bool) -> CGSize {
            NSHostingView(rootView: RangeeNiveau(moteur: m, ancien: ancien)).fittingSize
        }
        #expect(taille(true).width > taille(false).width, "la pastille a cote de la ligne de niveau")
        #expect(taille(true).height == RangeeNiveau.hauteur && taille(false).height == RangeeNiveau.hauteur,
                "la meme hauteur, avec ou sans la pastille : \(taille(true)), \(taille(false))")
        #expect(NSHostingView(rootView: PastilleAncien()).fittingSize.height == RangeeNiveau.hauteur)
        #expect(NSHostingView(rootView: LigneNiveauVue(ligne: .pieces)).fittingSize.height < RangeeNiveau.hauteur,
                "la pastille est plus haute que la ligne de niveau")
    }

    /// La ligne de niveau tient sur une seule ligne, coupee par des points de suspension si elle est trop longue :
    /// dans une largeur trop etroite, sa hauteur ne change pas (la colonne ne change jamais de hauteur au fil des
    /// zooms), meme pour la piece isolee, dont le texte est le plus long ; sans contrainte, elle garde son texte entier.
    @Test func ligneDeNiveauSurUneLigne() {
        let lignes: [LigneNiveau] = [.pieces, .routeurs, .masques(1), .masques(12), .lisibles, .isolee("Salon"),
                                     .etageIsole("Rez-de-chaussée")]
        let seule = NSHostingView(rootView: LigneNiveauVue(ligne: .pieces).fixedSize()).fittingSize.height
        for l in lignes {
            let libre = NSHostingView(rootView: LigneNiveauVue(ligne: l).fixedSize()).fittingSize
            let etroite = NSHostingView(rootView: LigneNiveauVue(ligne: l).frame(width: 120)).fittingSize
            #expect(libre.height == seule, "\(l) : une ligne, sans contrainte (\(libre))")
            #expect(etroite.height == seule && etroite.width <= 120, "\(l) : coupee dans 120 pt, pas sur deux lignes (\(etroite))")
        }
        let longue = NSHostingView(rootView: LigneNiveauVue(ligne: .isolee("Salon")).fixedSize()).fittingSize.width
        #expect(longue > 400, "le texte le plus long de la ligne de niveau : \(longue) pt")
    }

    /// Les signes de la legende sont dessines comme dans la scene, par les memes fonctions que le rendu (verification
    /// du 02/10) : un routeur en sphere brillante, avec halo et reflet, bleue, grise s'il est inconnu du pont
    /// ; un appareil en pastille de la couleur de son etat, en anneau s'il a disparu : les apparences
    /// de `DessinNoeud` que portent les noeuds de la scene. Le coordinateur porte sa couronne et l'endormi sa lune, celles des
    /// noms de la scene (sans leur pastille : `couronneEtLuneSansPastille`) ; la pile, sa pastille ; les liens, leur
    /// epaisseur, leur couleur et leur trait, avec l'opacite d'un lien au repos dans la scene. La legende les pose par
    /// `SigneLegende`, qui dessine par `DessinNoeud` et `RenduCanvas` : ses images sont celles de ces fonctions, avec
    /// ces parametres.
    @Test func signesCommeLaScene() throws {
        let (_, e) = try NomsSceneTests.demo()
        var vues = Set<Entree>()
        for n in e.scene.noeuds {
            let a = try #require(e.apparences[n.id])
            let entree: Entree? = switch a.couleur {
            case .routeur: .routeur
            case .routeurInconnu: .nonIdentifie
            case .appareil(.joignable): .joignable
            case .appareil(.injoignable): .injoignable
            case .appareil(.disparu): .disparu
            case .appareil(.inconnu): nil
            }
            guard let entree else { continue }
            vues.insert(entree)
            // Le coordinateur a un plus grand halo (10) : la legende montre un routeur, au halo de 5.
            let attendue = n.genre == .centre ? DessinNoeud.Apparence(forme: .sphere(halo: 5), couleur: a.couleur) : a
            #expect(n.genre != .centre || a.forme == .sphere(halo: 10))
            let routeur = n.genre != .appareil
            #expect(LegendePieces.signe(entree)
                    == .noeud(attendue, rayon: routeur ? LegendePieces.rayonRouteur : LegendePieces.rayonAppareil),
                    "\(n.id) : la meme apparence que dans la scene")
        }
        #expect(vues == [.routeur, .nonIdentifie, .joignable, .disparu])
        #expect(LegendePieces.signe(.injoignable)
                == .noeud(DessinNoeud.apparenceAppareil(.injoignable), rayon: LegendePieces.rayonAppareil))
        // La couronne et la lune : celles des noms de la scene, seules (`couronneEtLuneSansPastille`).
        let chef = try #require(e.chefs.first)
        #expect(LegendePieces.signe(.coordinateur) == .glyphe("👑", routeur: true))
        #expect(try #require(e.libelles[chef]).texte.contains(" 👑"))
        #expect(LegendePieces.signe(.endormi) == .glyphe("☾", routeur: false))
        #expect(e.libelles.values.contains { $0.texte.contains(" ☾") })
        #expect(LegendePieces.signe(.pile) == .pastille(LegendePieces.exemplePile))
        #expect(LegendePieces.signe(.ailleurs) == .ailleurs(LegendePieces.exempleAilleurs))
        // Les liens : radio par qualite, enfant -> parent ; l'opacite d'un lien au repos dans la scene.
        #expect([Entree.bonne, .moyenne, .faible, .inconnue].map(LegendePieces.signe)
                == [.lienRadio(qualite: 3), .lienRadio(qualite: 2), .lienRadio(qualite: 1), .lienRadio(qualite: nil)])
        #expect(LegendePieces.signe(.versParent) == .lienEnfant(rattachement: false))
        let projetee = try #require(MoteurPiecesTests.moteur(e).projetee)
        #expect(!projetee.liensRouteurs.isEmpty && !projetee.liensEnfants.isEmpty)
        #expect(projetee.liensRouteurs.allSatisfy { $0.opacite == LegendePieces.opaciteLienRadio })
        #expect(projetee.liensEnfants.allSatisfy { !$0.eclaire && $0.opacite == LegendePieces.opaciteLienEnfant })
        // La legende pose ses signes par `SigneLegende`, qui dessine par les fonctions du rendu.
        #expect(String(reflecting: LegendePieces.Body.self).contains("SigneLegende"))
        let p = Palette(sombre: true)
        let cadre = CGRect(x: 20, y: 10, width: 14, height: 14)
        let routeur = DessinNoeud.apparenceRouteur(inconnu: false)
        // Les pixels d'un dessin, en RVBA de 8 bits (le tampon brut d'une image a des octets de remplissage).
        func image(_ dessin: @escaping (inout GraphicsContext) -> Void) throws -> [UInt8] {
            let rendu = ImageRenderer(content: Canvas { ctx, _ in dessin(&ctx) }.frame(width: 60, height: 34))
            rendu.scale = 2
            let image = try #require(rendu.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let espace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let ctx = try #require(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: espace,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            #expect(pixels.contains { $0 > 0 }, "un dessin")
            return pixels
        }
        // La couronne et le symbole de la pastille d'une pile se chargent au premier rendu (et un `ImageRenderer` garde
        // son premier rendu) : un rendu a blanc de chacun d'abord.
        _ = try image { ctx in
            let couronne = ctx.resolve(RenduCanvas.texteNom("👑", routeur: true, fort: false, palette: p))
            RenduCanvas.dessinerNom(&ctx, couronne, dans: cadre, palette: p)
            DessinNoeud.dessinerPastille(&ctx, "12 %", gauche: .zero, palette: p)
        }
        // Chaque signe, et la fonction du rendu avec les parametres de la scene : les memes pixels, a quelques pixels
        // pres (le flou d'un halo ou d'une ombre varie d'un rendu a l'autre, selon ce que le processus a rendu avant :
        // jusqu'a 14 octets apres la scene de la demo de C) ; un autre dessin en changerait des milliers.
        func memes(_ signe: LegendePieces.Signe, _ reference: @escaping (inout GraphicsContext) -> Void) throws {
            let legende = try image { SigneLegende.dessiner(signe, &$0, dans: cadre, echelle: 2, palette: p) }
            let scene = try image(reference)
            let ecarts = zip(legende, scene).filter { $0 != $1 }.count
            #expect(ecarts <= 32, "\(signe) : \(ecarts) octets differents")
        }
        try memes(.noeud(routeur, rayon: 7)) {
            DessinNoeud.dessiner(&$0, centre: CGPoint(x: 27, y: 17), rayon: 7, apparence: routeur, palette: p)
        }
        try memes(.lienRadio(qualite: 2)) {
            RenduCanvas.dessinerLienRadio(&$0, de: CGPoint(x: 21, y: 17), a: CGPoint(x: 33, y: 17), qualite: 2,
                                          opacite: LegendePieces.opaciteLienRadio, palette: p)
        }
        try memes(.lienEnfant(rattachement: true)) {
            RenduCanvas.dessinerLienEnfant(&$0, de: CGPoint(x: 21, y: 17), a: CGPoint(x: 33, y: 17), rattachement: true,
                                           opacite: LegendePieces.opaciteLienEnfant, eclaire: false, pixel: 0.5, palette: p)
        }
        try memes(.nom("👑", routeur: true)) { ctx in
            let couronne = ctx.resolve(RenduCanvas.texteNom("👑", routeur: true, fort: false, palette: p))
            RenduCanvas.dessinerNom(&ctx, couronne, dans: cadre, palette: p)
        }
        try memes(.pastille("12 %")) {
            DessinNoeud.dessinerPastille(&$0, "12 %", gauche: CGPoint(x: 20, y: 17), palette: p)
        }
    }

    /// Les noeuds de la legende ont la taille d'un noeud de la scene dans la vue d'ensemble (verification du 02/10),
    /// ramenee au plus a la hauteur d'une ligne de la legende : un routeur de bordure y mesure 13 fois le zoom, un
    /// appareil 7 fois (3 pt au moins dans la scene), au zoom de la vue d'ensemble de reference, celle de la demo de
    /// deux etages de B (0,53 a la taille des images, 1440 x 900, en 2D). La demo de C, a quatre plateaux, a une vue
    /// d'ensemble plus petite (0,47, en rangee) : la legende garde la taille de B (decision de Djoko du 03/10), que
    /// le test epingle par des valeurs fixes, non par la formule de `SigneLegende`.
    @Test func tailleDesSignes() throws {
        let (_, e) = try NomsSceneTests.demo()
        #expect(LegendePieces.hauteurLigne == NSHostingView(rootView: Text(verbatim: "joignable").font(.system(size: 11))).fittingSize.height)
        let h = NSHostingView(rootView: LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: false)).fittingSize.height
        let taille = CapturesPieces.taille
        let m = MoteurPieces()
        m.fige = true
        m.marges = (FenetrePieces.margeHaut(bas: 88), FenetrePieces.margeBas(pile: h))
        m.poserTaille(taille)
        m.installerMaintenant(e)
        m.poserTaille(taille)
        MoteurPiecesTests.dessiner(m, taille: taille)
        let p = try #require(m.projetee)
        #expect(p.echelle < LegendePieces.zoomVueDEnsemble, "la vue d'ensemble de la demo de C : \(p.echelle)")
        func rayon(_ garder: (ScenePieces.Noeud) -> Bool) throws -> Double {
            let id = try #require(e.scene.noeuds.first(where: garder)?.id)
            return try #require(p.disques.first { $0.noeud == id }).rayon
        }
        let routeur = try rayon { $0.genre == .routeur }
        let appareil = try rayon { $0.genre == .appareil && !$0.routeur }
        #expect(abs(routeur - max(3, 8 * p.echelle)) < 0.15 && abs(appareil - max(3, 7 * p.echelle)) < 0.15,
                "\(routeur) et \(appareil) au zoom \(p.echelle)")
        // La legende garde la taille de B (decision de Djoko du 03/10) : des valeurs fixes, non la formule de
        // `SigneLegende`, qui ne pourrait pas echouer. Le zoom de B, 0,53 : un rayon naturel de 13 et de 7 pt y donne
        // 6,89 et 3,71 pt.
        #expect(LegendePieces.zoomVueDEnsemble == 0.53)
        #expect(abs(LegendePieces.rayonRouteur - 6.89) < 0.005 && abs(LegendePieces.rayonAppareil - 3.71) < 0.005,
                "\(LegendePieces.rayonRouteur) et \(LegendePieces.rayonAppareil)")
        #expect(2 * LegendePieces.rayonRouteur <= LegendePieces.hauteurLigne && LegendePieces.rayonAppareil >= 3)
    }

    // MARK: Le chevron, la couronne et la lune (reverification en vrai du 02/10)

    /// Les pixels d'une vue, rendue a l'echelle 2 comme dans une capture (sans verre : le fond des captures), en RVBA
    /// de 8 bits ; sa largeur et sa hauteur en pixels.
    static func pixels(_ vue: some View) throws -> (largeur: Int, hauteur: Int, octets: [UInt8]) {
        let rendu = ImageRenderer(content: vue.environment(\.capturePieces, true))
        rendu.scale = 2
        let image = try #require(rendu.cgImage)
        var octets = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let espace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(data: &octets, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: espace,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (image.width, image.height, octets)
    }

    /// Le chevron d'une legende rendue (`pixels`) : l'encre claire du texte (blanc a 0,88 sur le fond sombre), dans les
    /// rangs `rangs` ; le chevron est son dernier amas de colonnes, a droite. Son cadre en pixels (rangs du haut en bas),
    /// et l'etendue de son encre dans son rang du haut et dans celui du bas.
    static func chevron(_ p: (largeur: Int, hauteur: Int, octets: [UInt8]), rangs: Range<Int>? = nil) throws
        -> (cadre: (x: ClosedRange<Int>, y: ClosedRange<Int>), haut: Int, bas: Int) {
        let rangs = rangs ?? 0..<p.hauteur
        func encre(_ x: Int, _ y: Int) -> Bool {
            let i = (y * p.largeur + x) * 4
            return p.octets[i] > 140 && p.octets[i + 1] > 140 && p.octets[i + 2] > 140
        }
        let colonnes = (0..<p.largeur).filter { x in rangs.contains { encre(x, $0) } }
        let derniere = try #require(colonnes.last, "de l'encre")
        var premiere = derniere
        while colonnes.contains(premiere - 1) { premiere -= 1 }
        let xs = premiere...derniere
        let ys = rangs.filter { y in xs.contains { encre($0, y) } }
        let cadreY = try #require(ys.first)...(try #require(ys.last))
        func etendue(_ y: Int) -> Int {
            let encrees = xs.filter { encre($0, y) }
            return (encrees.last ?? 0) - (encrees.first ?? 0)
        }
        return ((xs, cadreY), max(etendue(cadreY.lowerBound), etendue(cadreY.lowerBound + 1)),
                max(etendue(cadreY.upperBound), etendue(cadreY.upperBound - 1)))
    }

    /// Le chevron montre ce que fait un clic (choix de Djoko, 02/10, a l'inverse de la maquette A) : vers le bas (⌄)
    /// quand la legende est ouverte, pour la replier ; vers le haut (⌃) quand elle est repliee, pour l'ouvrir. Lu sur
    /// l'encre du rendu : un chevron vers le haut est etroit en haut (sa pointe) et large en bas, l'inverse vers le bas.
    @Test func chevronSelonLEtat() throws {
        let tout = LegendePieces.Groupe.allCases.map { LegendePieces.Rubrique(groupe: $0, entrees: $0.entrees) }
        let repliee = try Self.chevron(try Self.pixels(LegendePieces(rubriques: tout, repliee: .constant(true))))
        #expect(repliee.bas > repliee.haut + 2, "repliee : vers le haut (haut \(repliee.haut) px, bas \(repliee.bas) px)")
        // Ouverte : le chevron de l'en-tete, dans la bande de la premiere ligne d'encre (l'en-tete), au-dessus de la grille.
        let panneau = try Self.pixels(LegendePieces(rubriques: tout, repliee: .constant(false)))
        func ligneVide(_ y: Int) -> Bool {
            (0..<panneau.largeur).allSatisfy { x in
                let i = (y * panneau.largeur + x) * 4
                return !(panneau.octets[i] > 140 && panneau.octets[i + 1] > 140 && panneau.octets[i + 2] > 140)
            }
        }
        let debut = try #require((0..<panneau.hauteur).first { !ligneVide($0) })
        let fin = try #require((debut..<panneau.hauteur).first { ligneVide($0) })
        let ouverte = try Self.chevron(panneau, rangs: debut..<fin)
        #expect(ouverte.haut > ouverte.bas + 2, "ouverte : vers le bas (haut \(ouverte.haut) px, bas \(ouverte.bas) px)")
    }

    /// Repliee, le chevron est centre verticalement sur la ligne de l'etiquette « Legende » (reverification du 02/10 :
    /// il etait trop bas) : le milieu de son encre est celui de l'etiquette, dont les marges du haut et du bas sont
    /// egales, a un demi-point pres.
    @Test func chevronCentreSurLEtiquette() throws {
        let tout = LegendePieces.Groupe.allCases.map { LegendePieces.Rubrique(groupe: $0, entrees: $0.entrees) }
        let p = try Self.pixels(LegendePieces(rubriques: tout, repliee: .constant(true)))
        let c = try Self.chevron(p)
        let milieu = Double(c.cadre.y.lowerBound + c.cadre.y.upperBound + 1) / 2
        #expect(abs(milieu - Double(p.hauteur) / 2) <= 1, "milieu du chevron \(milieu) px, de l'etiquette \(Double(p.hauteur) / 2) px")
    }

    /// Les textes des lignes 👑 et ☾ s'alignent sur ceux des autres signes de leur groupe (ronde finale du 02/10 :
    /// ils etaient decales d'environ 3,5 pt vers la droite) : une ligne est son signe, 7 pt, puis son texte, et le glyphe
    /// prend la place d'un noeud de son groupe (un routeur pour la couronne, un appareil pour la lune), centre sur elle,
    /// comme les noeuds. Seule la pastille d'une pile, plus large, garde sa place.
    @Test func couronneEtLuneAlignees() throws {
        for (glyphe, noeud) in [(Entree.coordinateur, Entree.routeur), (.endormi, .joignable)] {
            let place = SigneLegende.taille(LegendePieces.signe(glyphe))
            let reference = SigneLegende.taille(LegendePieces.signe(noeud))
            #expect(place.width == reference.width, "\(glyphe) : la largeur d'un noeud (\(place.width) au lieu de \(reference.width))")
        }
        // Les groupes de la couronne et de la lune : une colonne de signes commune, la pile mise a part.
        for groupe in [LegendePieces.Groupe.routeurs, .appareils] {
            let largeurs = Set(groupe.entrees.filter { $0 != .pile }.map { SigneLegende.taille(LegendePieces.signe($0)).width })
            #expect(largeurs.count == 1, "\(groupe) : une colonne de signes commune (\(largeurs))")
        }
        // Le glyphe est centre sur sa place, comme un noeud : le milieu de son encre, a un pixel pres.
        let p = Palette(sombre: true)
        for entree in [Entree.coordinateur, .endormi] {
            let signe = LegendePieces.signe(entree)
            let taille = SigneLegende.taille(signe)
            let cadre = CGRect(origin: CGPoint(x: 30 - taille.width / 2, y: 17 - taille.height / 2), size: taille)
            var image = try Self.pixels(Canvas { ctx, _ in SigneLegende.dessiner(signe, &ctx, dans: cadre, echelle: 2, palette: p) }
                .frame(width: 60, height: 34))
            // La couronne se charge au premier rendu : un second rendu.
            image = try Self.pixels(Canvas { ctx, _ in SigneLegende.dessiner(signe, &ctx, dans: cadre, echelle: 2, palette: p) }
                .frame(width: 60, height: 34))
            let colonnes = (0..<image.largeur).filter { x in
                (0..<image.hauteur).contains { y in image.octets[(y * image.largeur + x) * 4 + 3] > 40 }
            }
            let premiere = try #require(colonnes.first, "\(entree) : de l'encre")
            let derniere = try #require(colonnes.last)
            let milieu = Double(premiere + derniere + 1) / 2
            #expect(abs(milieu - 60) <= 2, "\(entree) : le glyphe centre (milieu de l'encre a \(milieu) px, de la place a 60)")
        }
    }

    /// La couronne du chef et la lune d'un endormi, dans la legende, sans la pastille sombre d'un nom (reverification
    /// du 02/10 : « une ombre disgracieuse et inutile ») : le glyphe seul, dans le texte des noms de la scene, centre
    /// sur la place d'un noeud de son groupe (`couronneEtLuneAlignees`). Dans la scene, les noms gardent leur pastille.
    @Test func couronneEtLuneSansPastille() throws {
        let p = Palette(sombre: true)
        func image(_ dessin: @escaping (inout GraphicsContext) -> Void) throws -> [UInt8] {
            try Self.pixels(Canvas { ctx, _ in dessin(&ctx) }.frame(width: 60, height: 34)).octets
        }
        // La couronne se charge au premier rendu : un rendu a blanc d'abord.
        _ = try image { ctx in
            ctx.draw(ctx.resolve(RenduCanvas.texteNom(LibellesNoeuds.couronne, routeur: true, fort: false, palette: p)),
                     at: CGPoint(x: 20, y: 17), anchor: .leading)
        }
        for (entree, glyphe, routeur) in [(Entree.coordinateur, LibellesNoeuds.couronne, true), (.endormi, LibellesNoeuds.lune, false)] {
            let signe = LegendePieces.signe(entree)
            let nom = MesureNoms().noeud(LibellesNoeuds.Libelle(texte: glyphe), routeur: routeur)
            let taille = SigneLegende.taille(signe)
            #expect(taille == CGSize(width: SigneLegende.largeurGlyphe(routeur: routeur), height: nom.height),
                    "\(glyphe) : la place d'un noeud de son groupe, a la hauteur du nom (\(taille))")
            let cadre = CGRect(origin: CGPoint(x: 20, y: 17 - taille.height / 2), size: taille)
            let legende = try image { SigneLegende.dessiner(signe, &$0, dans: cadre, echelle: 2, palette: p) }
            let seul = try image { ctx in
                ctx.draw(ctx.resolve(RenduCanvas.texteNom(glyphe, routeur: routeur, fort: false, palette: p)),
                         at: CGPoint(x: cadre.midX, y: cadre.midY), anchor: .center)
            }
            let ecarts = zip(legende, seul).filter { $0 != $1 }.count
            #expect(ecarts <= 8, "\(glyphe) : le glyphe seul, sans pastille (\(ecarts) octets differents)")
        }
    }
}
