import AppKit
import SwiftUI

/// App de la barre des menus : pas d'icone dans le Dock, sauf tant qu'une de
/// ses fenetres (graphe, journal) est ouverte.
@MainActor
enum PolitiqueActivation {
    private static var ouvertes = 0

    static func ouverte() {
        ouvertes += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func fermee() {
        ouvertes = max(0, ouvertes - 1)
        if ouvertes == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

extension View {
    /// Fenetre de l'app : l'icone du Dock et le menu de l'app tant qu'elle est ouverte.
    func fenetreDeLApp() -> some View {
        onAppear { PolitiqueActivation.ouverte() }
            .onDisappear { PolitiqueActivation.fermee() }
    }
}
