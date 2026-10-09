import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

/// Etape 5 dans l'app : le mode focus du moteur (selection, second clic, Echap, bouton « Voisins »), les colonnes de la
/// fiche et leurs textes, la bande des courbes. Sur la demo (valeurs inventees).
@MainActor
@Suite("Mode focus, fiche en colonnes et courbes de la fiche")
struct FocusFicheTests {
    typealias I = NomsDemo.Ieee

    /// Le moteur suit la selection : a la selection d'une lampe, ce qui n'est pas mis en avant s'estompe (une capture,
    /// figee, le prend tout de suite) ; ses pastilles et ses noms s'estompent, pas celles du chemin. Le bouton « Voisins »
    /// change ce qui reste net ; un clic dans le vide, Echap ou un second clic sur le noeud rendent la vue normale.
    @Test func focusDuMoteur() throws {
        let (m, e) = try MoteurPiecesTests.moteur()
        m.fige = true
        #expect(m.miseEnAvant == nil && m.noeudsEstompes.isEmpty)
        m.selection = I.lampeBureau
        let focus = try #require(m.miseEnAvant)
        #expect(focus == e.miseEnAvant(de: I.lampeBureau, voisins: true))
        #expect(m.noeudsEstompes[I.lampeGrenier] == 1 && m.noeudsEstompes[I.lampeBureau] == nil)
        #expect(m.noeudsEstompes.count == e.scene.noeuds.count - focus.noeuds.count)
        MoteurPiecesTests.dessiner(m)
        let p = try #require(m.projetee)
        #expect(p.disques.first { $0.noeud == I.lampeGrenier }?.focus == MiseEnAvant.opaciteEstompee)
        #expect(p.disques.first { $0.noeud == I.lampadaireSalon }?.focus == 1, "son prochain saut reste net")
        #expect(p.facteur(noeud: I.lampeGrenier) < 1 && p.facteur(noeud: I.pont) == 1)
        // Sans les voisins : le lien vers le pont, un voisin, s'estompe ; en mode « tous », les voisins reviennent.
        m.voisins = false
        #expect(m.miseEnAvant?.liens.contains(MiseEnAvant.cle(I.lampeBureau, I.pont)) == false)
        #expect(m.liensEstompes[MiseEnAvant.cle(I.lampeBureau, I.pont)] == 1)
        m.liens = .tous
        #expect(m.miseEnAvant?.liens.contains(MiseEnAvant.cle(I.lampeBureau, I.pont)) == true, "« tous » : voisins montres")
        m.liens = .chemins
        m.voisins = true
        // Echap : la vue normale.
        #expect(m.sortir())
        #expect(m.selection == nil && m.miseEnAvant == nil && m.noeudsEstompes.isEmpty && m.liensEstompes.isEmpty)
    }

    /// Un clic sur un noeud le choisit ; un second clic sur lui le relache (la vue normale) ; un clic sur un autre noeud
    /// change le focus ; un clic dans le vide le relache.
    @Test func secondClicEtVide() throws {
        let (m, _) = try MoteurPiecesTests.moteur()
        func centre(_ id: String) throws -> CGPoint {
            MoteurPiecesTests.dessiner(m)
            return try #require(m.projetee?.disques.first { $0.noeud == id }).centre
        }
        let pont = try centre(I.pont)
        m.cliquer(pont)
        #expect(m.selection == I.pont && m.miseEnAvant != nil)
        m.cliquer(pont)
        #expect(m.selection == nil && m.miseEnAvant == nil, "second clic : la vue normale")
        m.cliquer(pont)
        m.cliquer(try centre(I.plafonnierSalon))
        #expect(m.selection == I.plafonnierSalon && m.miseEnAvant?.noeuds.contains(I.plafonnierSalon) == true)
        m.cliquer(CGPoint(x: 5, y: MoteurPiecesTests.taille.height / 2))
        #expect(m.selection == nil && m.miseEnAvant == nil, "clic dans le vide")
    }

    /// L'estompement va en douceur : l'horloge continue tant qu'il est en route, et il arrive a sa cible.
    @Test func transitionDouce() throws {
        let (m, _) = try MoteurPiecesTests.moteur()
        m.selection = I.lampeChambre
        #expect(m.focusEnRoute && m.doitContinuer(MoteurPieces.maintenant()))
        m.dt = 0.05
        m.noeudsEstompes = MiseEnAvant.tendre(m.noeudsEstompes, vers: m.ciblesFocus.noeuds, k: m.dt * MoteurPieces.vitesseFocus)
        let mi = m.noeudsEstompes[I.lampeGrenier] ?? 0
        #expect(mi > 0 && mi < 1, "en route : \(mi)")
        for _ in 0..<60 {
            m.noeudsEstompes = MiseEnAvant.tendre(m.noeudsEstompes, vers: m.ciblesFocus.noeuds, k: 0.05 * MoteurPieces.vitesseFocus)
            m.liensEstompes = MiseEnAvant.tendre(m.liensEstompes, vers: m.ciblesFocus.liens, k: 0.05 * MoteurPieces.vitesseFocus)
        }
        #expect(!m.focusEnRoute, "arrive en 3 s au plus")
    }

    /// Les couleurs des qualites viennent du niveau du coeur : `lienSonde` et `couleur(_:)` disent la meme chose.
    @Test func couleursDesNiveaux() {
        let p = Palette(sombre: true)
        let qualites: [Int?] = [3, 2, 1, 0, nil]
        for q in qualites {
            #expect(p.lienSonde(q) == p.couleur(NiveauQualite(q)))
        }
        #expect(p.lienSonde(0) == p.lienSonde(1), "0 est un lien faible")
        #expect(Set([3, 2, 1].map { p.lienSonde($0) }).count == 3 && p.lienSonde(nil) != p.lienSonde(1))
    }

    /// Les rangees fluides : a la ligne quand la place manque ; un element plus large que la rangee est ramene a sa
    /// largeur (il ne deborde pas), avec ou sans largeur proposee, et une largeur infinie vaut aucune.
    @Test func rangeesFluides() {
        let t = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 12), CGSize(width: 200, height: 10)]
        let large = RangeesFluides.disposer(t, largeur: 100, espacement: 5, interligne: 4)
        #expect(large.places == [CGPoint(x: 0, y: 0), CGPoint(x: 45, y: 0), CGPoint(x: 0, y: 16)])
        #expect(large.tailles.map(\.width) == [40, 50, 100], "la pastille trop large est bornee a la rangee")
        #expect(large.total == CGSize(width: 100, height: 26))
        let libre = RangeesFluides.disposer(t, largeur: nil, espacement: 5, interligne: 4)
        #expect(libre.places.map(\.y) == [0, 0, 0] && libre.total.width == 40 + 5 + 50 + 5 + 200)
        #expect(RangeesFluides.disposer(t, largeur: .infinity).tailles.map(\.width) == [40, 50, 200])
        #expect(RangeesFluides.disposer([], largeur: 100).total == CGSize(width: 100, height: 0))
    }

    // MARK: Fiche

    /// Les colonnes de la fiche : quatre, puis deux, puis une, selon la place ; la grille des voisins, autant de colonnes
    /// que la place en donne (de 210 pt au moins). Le decalage des courbes de qualite, centre et borne.
    @Test func colonnesSelonLaPlace() {
        #expect(ColonnesFiche.colonnes(largeur: 1000, nombre: 4) == 4)
        #expect(ColonnesFiche.colonnes(largeur: 4 * 190 + 3 * 24, nombre: 4) == 4)
        #expect(ColonnesFiche.colonnes(largeur: 4 * 190 + 3 * 24 - 1, nombre: 4) == 2, "jamais trois : des rangees pleines")
        #expect(ColonnesFiche.colonnes(largeur: 300, nombre: 4) == 1)
        #expect(ColonnesFiche.colonnes(largeur: nil, nombre: 4) == 4)
        #expect(ColonnesFiche.grille(largeur: 1000, nombre: 4).colonnes == 4)
        let sansLimite = ColonnesFiche.grille(largeur: .infinity, nombre: 4)
        #expect(sansLimite.colonnes == 4 && sansLimite.largeur == ColonnesFiche.largeurMinimale,
                "une largeur infinie ne donne pas de colonne infinie")
        #expect(ColonnesFiche.grille(largeur: nil, nombre: 4).largeur == ColonnesFiche.largeurMinimale)
        #expect(GrilleListe.colonnes(largeur: 1000) == 4)
        #expect(GrilleListe.colonnes(largeur: 100) == 1)
        #expect(GrapheQualite.decalage(0, sur: 1) == 0)
        #expect(GrapheQualite.decalage(0, sur: 3) == -0.05 && GrapheQualite.decalage(2, sur: 3) == 0.05)
        #expect(abs(GrapheQualite.decalage(0, sur: 9) + 0.12) < 1e-9 && abs(GrapheQualite.decalage(8, sur: 9) - 0.12) < 1e-9)
    }

    /// Les textes des colonnes : le pont (les routeurs qui lui parlent directement), un routeur (son chemin), un
    /// appareil final (son parent, puis son chemin) ; le resume des voisins, les dependants.
    @Test func textesDesColonnes() {
        let m = MaillageDemo.maillage
        let s = NomsSceneTests.surveillanceDemo()
        #expect(FicheNoeud.lignesChemin(I.pont, maillage: m, nom: s.nom, maintenant: m.date)
                == [String(localized: "\(3) routeurs lui parlent directement")])
        #expect(FicheNoeud.ligneRouteursDirects(1) == String(localized: "1 routeur lui parle directement"))
        #expect(FicheNoeud.ligneRouteursDirects(0) == String(localized: "aucun routeur ne lui parle directement"))
        let age = FicheNoeud.relatif(m.date, m.date.addingTimeInterval(720), unites: .short)
        #expect(FicheNoeud.lignesChemin(I.lampeChambre, maillage: m, nom: s.nom, maintenant: m.date.addingTimeInterval(720))
                == [String(localized: "vers le pont : via \("Lampe bureau") · \(3) sauts"), String(localized: "chemin lu \(age)")])
        #expect(FicheNoeud.lignesChemin(I.interrupteurSalon, maillage: m, nom: s.nom, maintenant: m.date)
                == [String(localized: "parent \("Lampe chambre"), \(FicheNoeud.texteQualite(2))\(" (LQI 112)")"),
                    String(localized: "vers le pont : via \("Lampe chambre") · \(4) sauts")])
        #expect(FicheNoeud.lignesChemin("A0000000000000EE", maillage: m, nom: s.nom, maintenant: m.date).isEmpty)
        let r = ResumeVoisins(FicheZigbee.voisins(de: I.lampeChambre, maillage: m))
        #expect(FicheNoeud.ligneResume(r) == [String(localized: "\(3) voisins"), String(localized: "\(2) bons"),
                                              String(localized: "1 faible")].joined(separator: " · "))
        let un = ResumeVoisins([VoisinFiche(id: "a", qualite: 2), VoisinFiche(id: "b", qualite: nil)])
        #expect(FicheNoeud.ligneResume(un) == [String(localized: "\(2) voisins"), String(localized: "1 moyen"),
                                               String(localized: "1 inconnu")].joined(separator: " · "))
        let d = FicheZigbee.dependants(de: I.lampeChambre, maillage: m)
        #expect(FicheNoeud.ligneDependants(d) == [String(localized: "\(2) routeurs"), String(localized: "\(2) appareils")]
            .joined(separator: " · "))
        #expect(FicheNoeud.ligneDependants([DependantFiche(id: "a", qualite: 3, routeur: true)])
                == String(localized: "1 routeur"))
    }

    /// La fiche : sa liste de voisins depliee est plus haute que repliee (repliee par defaut) ; dans une fenetre etroite,
    /// les colonnes passent sur deux rangees, la fiche est plus haute.
    @Test func ficheRepliableEtEtroite() throws {
        let (s, e) = try NomsSceneTests.demo()
        func hauteur(_ largeur: CGFloat, deplie: Bool) -> CGFloat {
            let v = FicheNoeud(id: I.lampeBureau, entree: e, instant: s.maintenant, aRenommer: .constant(nil),
                               listeDepliee: deplie) {}
                .frame(width: largeur)
                .environment(s)
                .environment(PiecesChoisies(fichier: nil))
            return NSHostingView(rootView: v).fittingSize.height
        }
        let repliee = hauteur(1100, deplie: false), depliee = hauteur(1100, deplie: true)
        #expect(depliee > repliee + 10, "\(depliee) \(repliee)")
        #expect(hauteur(700, deplie: false) > repliee + 40, "deux rangees de colonnes")
    }

    // MARK: Courbes

    /// La bande des courbes : l'axe nomme, la case « tous les liens », les reperes (changements de chemin et de
    /// parent), les graduations espacees ; au survol, chaque courbe montree (ou celle mise en avant) avec son LQI.
    @Test func bandeDesCourbes() throws {
        #expect(CourbesFiche.nomQualite(3) == String(localized: "bonne"))
        #expect(CourbesFiche.nomQualite(2) == String(localized: "moyenne"))
        #expect(CourbesFiche.nomQualite(1) == String(localized: "faible"))
        #expect(CourbesFiche.nomQualite(0) == String(localized: "très faible"))
        #expect(CourbesFiche.texteTous(cachees: 3) == String(localized: "tous les liens (+\(3))"))
        #expect(CourbesFiche.texteTous(cachees: 0) == String(localized: "tous les liens"))
        #expect(CourbesFiche.graduations(.jour) == (.hour, 3) && CourbesFiche.graduations(.mois) == (.day, 5))
        let h = MaillageDemo.historique
        let c = CourbesNoeud(cle: I.lampeBureau, releves: h, periode: .jour, fin: MaillageDemo.fin)
        #expect(CourbesFiche.reperes(c).count == 11 && CourbesFiche.reperes(c).last?.parent == I.lampadaireSalon)
        let cles = ChoixCourbes.montrees(cles: c.liens.map(\.id), prioritaires: c.prioritaires, tous: false)
        let heure = MaillageDemo.fin.addingTimeInterval(-3600)
        let tous = GrapheQualite.releves(c.liens, cles: cles, enAvant: nil, heure: heure, periode: .jour)
        #expect(tous.map(\.cle) == cles && tous.allSatisfy { $0.point.date == heure })
        let un = GrapheQualite.releves(c.liens, cles: cles, enAvant: I.pont, heure: heure, periode: .jour)
        #expect(un.map(\.cle) == [I.pont])
        #expect(GrapheQualite.releves(c.liens, cles: cles, enAvant: nil, heure: nil, periode: .jour).isEmpty)
        #expect(GrapheQualite.releves(c.liens, cles: cles, enAvant: nil, heure: MaillageDemo.fin.addingTimeInterval(-16 * 3600 - 300),
                                      periode: .jour).isEmpty, "dans le trou d'une heure")
        let p = try #require(un.first?.point)
        #expect(GrapheQualite.ligneSurvol("Pont Hue", p) == String(localized: "\("Pont Hue") : LQI \(Int(try #require(p.lqi).rounded()))"))
        #expect(GrapheQualite.ligneSurvol("X", PointCourbe(date: heure, valeur: 2, troncon: 0))
                == "X : " + String(localized: "moyenne"))
        // Un appareil final : une seule courbe, vers son parent, et son changement de parent en repere.
        let abri = CourbesNoeud(cle: I.detecteurAbri, releves: h, periode: .jour, fin: MaillageDemo.fin)
        #expect(ChoixCourbes.montrees(cles: abri.liens.map(\.id), prioritaires: abri.prioritaires, tous: false)
                == [CourbesNoeud.cleParent])
        #expect(CourbesFiche.reperes(abri).map(\.parent) == [I.priseTerrasse])
        #expect(CourbesFiche.titreQualite(abri) == String(localized: "Qualité du lien vers le parent"))
    }

    /// L'historique des captures : en demo seulement ; une surveillance directe n'en prend pas.
    @Test func historiqueDeCapture() {
        let demo = NomsSceneTests.surveillanceDemo()
        #expect(!FicheNoeud.courbesVisibles(dans: demo))
        demo.historiqueDeCapture(MaillageDemo.historique)
        #expect(FicheNoeud.courbesVisibles(dans: demo))
        let direct = Surveillance(mode: .direct, dossier: nil)
        direct.historiqueDeCapture(MaillageDemo.historique)
        #expect(!FicheNoeud.courbesVisibles(dans: direct))
    }
}
