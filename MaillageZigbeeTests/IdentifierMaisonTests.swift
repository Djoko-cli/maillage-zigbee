import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

/// « Identifier par Maison » : le demon Passeur Noms appelle `identify()` sur l'accessoire de Maison apparie a
/// l'appareil du pont (`idMaison`, par `FusionNoms`). Il coexiste avec « Identifier » par le pont Hue (`IdentifierTests`),
/// qui reste le seul bouton quand Maison n'a pas retrouve l'appareil. Jamais de vrai demon ici.
@MainActor
@Suite("Identifier par Maison : bouton de la fiche, coexistence avec le pont")
struct IdentifierMaisonTests {
    static let id = "8D3C2A10-0000-4000-8000-000000000001"

    /// Offert pour un appareil apparie a un accessoire qui a un `id` ; actif seulement avec un demon connecte.
    @Test func boutonOffertEtActif() {
        let apparie = AccessoireMaison(nom: "Lampe", ieee: "A000000000000015", idMaison: Self.id)
        let sans = AccessoireMaison(nom: "Lampe", ieee: "A000000000000015")
        #expect(FicheNoeud.identifiableParMaison(apparie))
        #expect(!FicheNoeud.identifiableParMaison(sans), "pas apparie, ou releve sans id")
        #expect(!FicheNoeud.identifiableParMaison(nil))
        #expect(!FicheNoeud.identifiableParMaison(AccessoireMaison(nom: "Lampe", idMaison: "")))
        #expect(BoutonIdentifierMaison.actif(connecte: true))
        #expect(!BoutonIdentifierMaison.actif(connecte: false))
    }

    /// Le bouton envoie `identifier` au demon pour l'`id` de Maison ; la reponse s'affiche pour cet accessoire.
    @Test func texteDeLaReponse() async throws {
        let (n, d, _, cache) = try await NomsPasseurTests.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        n.identifier(accessoire: Self.id)
        #expect(await attendreQue { d.messages == [.identifier(demande: 1, accessoire: Self.id)] })
        #expect(BoutonIdentifierMaison.texte(n.identification, accessoire: Self.id) == nil)
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 1, ok: true))))
        #expect(await attendreQue { n.identification != nil })
        #expect(BoutonIdentifierMaison.texte(n.identification, accessoire: Self.id) == String(localized: "Identification demandée"))
        #expect(BoutonIdentifierMaison.texte(n.identification, accessoire: "autre") == nil, "pas pour un autre appareil")
    }

    /// La fiche d'un appareil apparie se construit avec le bouton, avec et sans demon ; sans NomsPasseur dans
    /// l'environnement (vues de test), pas de bouton.
    @Test func ficheAvecLeBouton() {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        for passeur in [NomsPasseur(demo: NomsDemo.releveMaison), nil] {
            let fiche = FicheNoeud(id: NomsDemo.Ieee.lampeBureau, entree: e, instant: s.maintenant,
                                   aRenommer: .constant(nil), fermer: {})
                .environment(s)
                .environment(PiecesChoisies(fichier: nil))
            let vue = passeur.map { AnyView(fiche.environment($0)) } ?? AnyView(fiche)
            #expect(NSHostingView(rootView: vue).fittingSize.height > 50)
        }
    }
}
