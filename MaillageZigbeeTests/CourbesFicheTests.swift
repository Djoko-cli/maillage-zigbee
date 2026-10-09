import AppKit
import Foundation
@testable import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Courbes de l'historique dans la fiche")
struct CourbesFicheTests {
    /// Deux tournees (`JournalMaillageTests`) : l'appareil passe du routeur 1 au routeur 5.
    static func surveillance() throws -> Surveillance {
        let s = JournalMaillageTests.surveillance(dossier: nil)
        let t = Date().addingTimeInterval(-600)
        s.recevoir(try JournalMaillageTests.maillage(s, t, parent: 1), a: t)
        s.recevoir(try JournalMaillageTests.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        return s
    }

    /// Cle d'un noeud dans l'historique : son adresse longue, son id ; et le nom d'une cle : celui du noeud (surnom,
    /// nom sur le pont), sinon la cle.
    @Test func clesEtNoms() throws {
        let s = try Self.surveillance()
        let id = JournalMaillageTests.appareil
        #expect(s.cleHistorique(noeud: id) == id)
        #expect(s.cleHistorique(noeud: JournalMaillageTests.r1) == JournalMaillageTests.r1)
        #expect(s.cleHistorique(noeud: "") == nil)
        let noms = s.nomsHistorique([id, JournalMaillageTests.r5, "A0000000000000EE"])
        #expect(noms[id] == "Interrupteur salon")
        #expect(noms[JournalMaillageTests.r5] == JournalMaillageTests.r5, "inconnu du pont : son adresse longue")
        #expect(noms["A0000000000000EE"] == "A0000000000000EE", "inconnue : la cle")
        #expect(CourbesFiche.nomLien(CourbesNoeud.cleParent, noms) == String(localized: "Parent"))
    }

    /// Courbes de l'appareil : la qualite vers son parent et son changement de parent ; du routeur r1 : son lien avec
    /// r5, celui de son enfant (tant qu'il l'est), et le LQI que la sonde en recoit.
    @Test func courbes() throws {
        let s = try Self.surveillance()
        let c = try #require(s.courbes(noeud: JournalMaillageTests.appareil, periode: .jour, fin: Date()))
        #expect(c.liens.map(\.id) == [CourbesNoeud.cleParent])
        #expect(c.liens.first?.points.count == 2)
        #expect(c.parents.map(\.parent) == [JournalMaillageTests.r5])
        let r = try #require(s.courbes(noeud: JournalMaillageTests.r1, periode: .jour, fin: Date()))
        #expect(r.courbe(JournalMaillageTests.r5) != nil, "son lien avec r5")
        #expect(r.courbe(JournalMaillageTests.appareil)?.points.count == 1, "son enfant, a la premiere tournee")
        #expect(r.signal.map(\.valeur) == [170, 170])
    }

    /// L'echelle du signal de la fiche (polissage D, section 4.3) : celle du coeur, sur les valeurs de la courbe ; deux
    /// releves egaux a un LQI de 170 donnent 150 ... 200, gradue 150, 200 ; sans valeur, 0 ... 255.
    @Test func echelleDuSignal() throws {
        let s = try Self.surveillance()
        let r = try #require(s.courbes(noeud: JournalMaillageTests.r1, periode: .jour, fin: Date()))
        let e = CourbesFiche.echelle(r)
        #expect(e.domaine == 150 ... 200 && e.graduations == [150, 200])
        let vide = try #require(s.courbes(noeud: JournalMaillageTests.appareil, periode: .jour, fin: Date()))
        #expect(vide.signal.isEmpty && CourbesFiche.echelle(vide).domaine == 0 ... 255)
        #expect(CourbesFiche.echelle(vide).graduations == [0, 50, 100, 150, 200, 250])
    }

    /// Ce que le graphe du signal affiche, decide sans fenetre (`GrapheSignal.affichage`, lu par la vue) : le domaine
    /// et les graduations ; le releve sous l'heure survolee, aucun sans survol ni dans un trou ; l'etiquette a gauche
    /// du trait (alignement `.trailing`) dans la moitie droite de la periode, a droite (`.leading`) sinon. Les
    /// changements de parent de la sonde n'ont plus de nom dans le trace (`ReperesFicheTests`).
    @Test func affichageDuSignal() throws {
        let s = try Self.surveillance()
        let maintenant = Date()
        // Les deux releves (LQI 170) datent des dix dernieres minutes : a droite d'une periode qui finit maintenant, a
        // gauche d'une periode qui finit 21 h plus tard.
        let droite = try #require(s.courbes(noeud: JournalMaillageTests.r1, periode: .jour, fin: maintenant))
        let tard = maintenant.addingTimeInterval(21 * 3600)
        let gauche = try #require(s.courbes(noeud: JournalMaillageTests.r1, periode: .jour, fin: tard))
        let p0 = try #require(droite.signal.first), q0 = try #require(gauche.signal.first)
        let a = GrapheSignal.affichage(droite, survole: p0.date.addingTimeInterval(60), periode: .jour)
        #expect(a.domaine == 150 ... 200 && a.graduations == [150, 200])
        #expect(a.releve == p0 && a.alignement == .trailing)
        let b = GrapheSignal.affichage(gauche, survole: q0.date, periode: .jour)
        #expect(b.releve == q0 && b.alignement == .leading)
        #expect(b.domaine == a.domaine && b.graduations == a.graduations)
        #expect(GrapheSignal.affichage(droite, survole: nil, periode: .jour).releve == nil)
        #expect(GrapheSignal.affichage(droite, survole: droite.debut, periode: .jour).releve == nil, "dans un trou")
    }

    /// Le pointeur : l'heure du releve le plus proche de sa position dans la zone de trace, la meme tant que ce releve
    /// ne change pas (relecture finale, Mineur 4 : l'etat du graphe ne change pas a chaque pixel) ; aucune dans un
    /// trou, hors de la zone, et a la sortie (`.ended`). Sur 24 h, un releve compte a moins de 20 min.
    @Test func heureSurvolee() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let signal = [PointCourbe(date: d, valeur: -60, troncon: 0),
                      PointCourbe(date: d.addingTimeInterval(300), valeur: -62, troncon: 0),
                      PointCourbe(date: d.addingTimeInterval(7200), valeur: -64, troncon: 1)]
        func heure(_ phase: HoverPhase) -> Date? {
            GrapheSignal.heureSurvolee(phase, signal: signal, periode: .jour) { d.addingTimeInterval($0.x) }
        }
        #expect(heure(.active(CGPoint(x: 10, y: 5))) == d && heure(.active(CGPoint(x: 100, y: 40))) == d,
                "deux positions proches du meme releve : son heure")
        #expect(heure(.active(CGPoint(x: 200, y: 5))) == d.addingTimeInterval(300), "le suivant, plus proche")
        #expect(heure(.active(CGPoint(x: 3750, y: 5))) == nil, "dans un trou")
        #expect(GrapheSignal.heureSurvolee(.active(.zero), signal: signal, periode: .jour) { _ in nil } == nil,
                "hors de la zone de trace")
        #expect(GrapheSignal.heureSurvolee(.ended, signal: signal, periode: .jour) { _ in d } == nil)
    }

    /// La fiche montre les courbes des qu'il y a un historique (jamais en demo), et la vue lui
    /// garde plus de place en bas : la marge du bas suit la pile mesuree, plus haute avec les courbes (elle
    /// remplace les 190 et 360 pt fixes) ; pour un noeud sans historique, une ligne de texte.
    @Test func ficheEtMarge() throws {
        let s = try Self.surveillance()
        #expect(FicheNoeud.courbesVisibles(dans: s))
        let demo = NomsSceneTests.surveillanceDemo()
        #expect(!FicheNoeud.courbesVisibles(dans: demo))
        let entree = FenetrePiecesTests.entree(s)
        func pile(_ id: String) -> CGFloat {
            let v = VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                LigneDuBas(moteur: MoteurPieces(), entree: entree, legendeForcee: true)
                FicheNoeud(id: id, entree: entree, instant: Date(), aRenommer: .constant(nil)) {}
            }.frame(width: FenetrePieces.largeurParDefaut - 2 * FenetrePieces.bord)
            return NSHostingView(rootView: v.environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize.height
        }
        let avecCourbes = pile(JournalMaillageTests.appareil)
        let sansCourbes = pile("A0000000000000EE")
        #expect(FenetrePieces.margeBas(pile: avecCourbes) > FenetrePieces.margeBas(pile: sansCourbes) + 100,
                "\(avecCourbes) \(sansCourbes)")
        let avec = NSHostingView(rootView: CourbesFiche(id: JournalMaillageTests.appareil, instant: Date()).environment(s)).fittingSize
        let sans = NSHostingView(rootView: CourbesFiche(id: "A0000000000000EE", instant: Date()).environment(s)).fittingSize
        #expect(avec.height > sans.height + 100, "\(avec) \(sans)")
    }

    /// Un troncon d'un seul point est dessine en point : une ligne en demande deux (ajout du
    /// controleur, relecture de la tache 9).
    @Test func tronconsDUnPoint() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let points = [PointCourbe(date: t, valeur: 1, troncon: 0),
                      PointCourbe(date: t.addingTimeInterval(300), valeur: 2, troncon: 0),
                      PointCourbe(date: t.addingTimeInterval(3600), valeur: 3, troncon: 1)]
        #expect(CourbesFiche.tronconsSeuls(points) == [1])
        #expect(CourbesFiche.tronconsSeuls([]).isEmpty)
    }
}
