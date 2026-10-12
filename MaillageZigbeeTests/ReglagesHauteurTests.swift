import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

/// La hauteur de la fenetre des Reglages suit celle de la page (`OngletsReglages.ajuster`), hors ecran.
@MainActor
@Suite("Reglages : hauteur de la fenetre", .serialized, .timeLimit(.minutes(1)))
struct ReglagesHauteurTests {
    static func defilements(_ v: NSView) -> [NSScrollView] {
        ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap { defilements($0) }
    }

    static func segments(_ v: NSView) -> [NSSegmentedControl] {
        ((v as? NSSegmentedControl).map { [$0] } ?? []) + v.subviews.flatMap { segments($0) }
    }

    /// Une fenetre des Reglages sur l'onglet Sonde, sonde USB connectee, montree hors ecran (transparente, loin de tout
    /// ecran) : visible pour AppKit, donc animee comme dans l'app, sans rien montrer.
    static func fenetreSonde(_ sonde: SondeMaillage) async throws -> (NSWindow, OngletsReglages) {
        let controleur = ControleurReglages(surveillance: Surveillance(mode: .direct, dossier: nil),
                                            ouverture: OuvertureSession(), nomsPont: NomsPont(),
                                            nomsPasseur: NomsPasseur(), sonde: sonde, misesAJour: MisesAJour(demarrer: false))
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        UserDefaults.standard.set(OngletReglages.sonde.rawValue, forKey: OngletReglages.cle)
        let fenetre = controleur.creerFenetre()
        fenetre.alphaValue = 0
        fenetre.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        fenetre.orderFrontRegardless()
        return (fenetre, try #require(fenetre.contentViewController as? OngletsReglages))
    }

    /// Les mesures d'une fenetre des Reglages : la hauteur de sa zone de contenu, la taille ideale de la page choisie, la
    /// hauteur de la page dans la fenetre, et ce que la vue de defilement du formulaire cache (en points).
    struct Mesure: CustomStringConvertible {
        var contenu: CGFloat, ideale: CGFloat, page: CGFloat, cache: CGFloat
        var description: String { "contenu \(contenu), ideale \(ideale), page \(page), cache \(cache)" }
        var juste: Bool { abs(contenu - ideale) < 0.5 && abs(page - contenu) < 0.5 && ideale > 0 && cache < 0.5 }
    }

    static func mesurer(_ fenetre: NSWindow, _ onglets: OngletsReglages) -> Mesure {
        let page = onglets.tabViewItems[onglets.selectedTabViewItemIndex].viewController!.view
        let cache = defilements(fenetre.contentView!).map { max(($0.documentView?.frame.height ?? 0) - $0.documentVisibleRect.height, 0) }
        return Mesure(contenu: fenetre.contentLayoutRect.height, ideale: page.fittingSize.height, page: page.frame.height,
                      cache: cache.max() ?? 0)
    }

    /// Attend, 3 s au plus, que la fenetre se soit ajustee a la page ; rend la derniere mesure.
    static func attendreAjustement(_ fenetre: NSWindow, _ onglets: OngletsReglages) async throws -> Mesure {
        var m = mesurer(fenetre, onglets)
        for _ in 0..<60 where !m.juste {
            try await Task.sleep(for: .milliseconds(50))
            m = mesurer(fenetre, onglets)
        }
        return m
    }

    /// Le bug du banc (11/10) : Liaison Automatique, puis Wi-Fi (la page perd des lignes), puis de nouveau Automatique
    /// (elle en retrouve) : la fenetre doit suivre la page chaque fois, la page entiere visible, bord du haut fixe.
    @Test func lAjustementSuitLaPage() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let sonde = SondeMaillage(preferences: p, actif: true, trousseau: TrousseauMemoire(),
                                  ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } })
        let (fenetre, onglets) = try await Self.fenetreSonde(sonde)
        defer { fenetre.orderOut(nil); fenetre.contentViewController = nil }
        let segments = try #require(Self.segments(fenetre.contentView!).first)
        let haut = try await { () -> CGFloat in
            _ = try await Self.attendreAjustement(fenetre, onglets)
            return fenetre.frame.maxY
        }()
        for (indice, nom) in [(1, "USB"), (0, "Automatique"), (2, "Wi-Fi"), (0, "Automatique"), (2, "Wi-Fi"), (0, "Automatique"),
                              (1, "USB"), (0, "Automatique")] {
            segments.selectedSegment = indice
            segments.performClick(nil)
            // Une pause courte, avant la fin de l'animation precedente, puis la mesure une fois la fenetre posee.
            try await Task.sleep(for: .milliseconds(120))
            let m = try await Self.attendreAjustement(fenetre, onglets)
            #expect(m.juste, "apres \(nom) : \(m)")
            #expect(abs(fenetre.frame.maxY - haut) < 0.5, "apres \(nom) : le bord du haut a bouge")
        }
        await sonde.oublier()
    }
}
