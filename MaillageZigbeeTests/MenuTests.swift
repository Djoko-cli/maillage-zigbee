import AppKit
import Foundation
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Barre des menus : icone")
struct MenuTests {
    @Test func icone() {
        #expect(IconeBarre.image(alerte: false).isTemplate)
        #expect(!IconeBarre.image(alerte: true).isTemplate, "orange : pas une image modele")
    }

    /// Le badge Zigbee agrandit le canevas du symbole seul (15 pt de haut) vers le bas et vers la droite.
    @Test func iconeAvecBadge() throws {
        let seul = try #require(NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                                        accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)))
        let largeurSeul = seul.size.width * 15 / seul.size.height
        let icone = IconeBarre.image(alerte: false)
        #expect(icone.size.height > 15 && icone.size.width > largeurSeul)
    }

    /// Le trace du logo est normalise : 1 de haut, la proportion attendue de large.
    @Test func traceDuLogo() {
        let boite = MarqueZigbee.trace.boundingBoxOfPath
        #expect(abs(boite.minY) < 0.01 && abs(boite.height - 1) < 0.01)
        #expect(abs(boite.width - MarqueZigbee.proportion) < 0.01)
    }

    /// « Ouvrir le graphe » et « Journal… » ferment le menu, comme « Reglages… » (01b0a42) : l'app inactive, le menu
    /// restait ouvert (reverification du 02/10). Les deux boutons passent par `MenuBarre.ouvrir` : la fenetre demandee
    /// s'ouvre, puis celle du menu, ici une fenetre hors ecran, se ferme. (Les boutons ne se pressent pas d'un test :
    /// SwiftUI n'y construit pas leur accessibilite.)
    @Test(arguments: ["graphe", "journal"]) func ouvrirUneFenetreFermeLeMenu(_ id: String) {
        let menu = NSPanel(contentRect: NSRect(x: -6000, y: -6000, width: 320, height: 200), styleMask: [.borderless],
                           backing: .buffered, defer: false)
        menu.isReleasedWhenClosed = false
        menu.orderFrontRegardless()
        defer { menu.orderOut(nil) }
        var ouvertes: [String] = []
        #expect(menu.isVisible)
        MenuBarre.ouvrir(id, par: { ouvertes.append($0) }, menu: menu)
        #expect(ouvertes == [id], "la fenetre demandee")
        #expect(!menu.isVisible, "le menu se ferme")
    }
}
