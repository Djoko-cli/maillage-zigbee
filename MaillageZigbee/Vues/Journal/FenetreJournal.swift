import MaillageCoeur
import SwiftUI

/// Familles d'evenements, pour le filtre du journal.
enum FamilleEvenement: String, CaseIterable, Identifiable {
    case toutes, surveillance, routeurs, appareils, maillage

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .toutes: String(localized: "Tous")
        case .surveillance: String(localized: "Surveillance")
        case .routeurs: String(localized: "Routeurs")
        case .appareils: String(localized: "Appareils")
        case .maillage: String(localized: "Maillage")
        }
    }

    func contient(_ t: TypeEvenement) -> Bool {
        switch self {
        case .toutes:
            true
        case .surveillance:
            [.surveillanceDemarree, .veille].contains(t)
        case .routeurs:
            [.routeurApparu, .routeurDisparu].contains(t)
        case .appareils:
            [.appareilNouveau, .appareilDisparu, .appareilRevenu].contains(t)
        case .maillage:
            [.parentChange, .sansParent, .cheminChange].contains(t)
        }
    }
}

/// Filtre du journal : famille, gravite minimale, recherche dans le titre, le sujet et les noms
/// « avant » et « apres » (les parents d'un changement de parent regroupe ne sont pas dans son titre).
struct FiltreJournal: Equatable {
    var famille: FamilleEvenement = .toutes
    var graviteMinimale: Gravite = .info
    var recherche = ""

    func appliquer(_ lignes: [LigneJournal]) -> [LigneJournal] {
        let r = recherche.trimmingCharacters(in: .whitespaces)
        return lignes.filter { l in
            let ev = l.evenements
            guard ev.contains(where: { famille.contient($0.type) }), l.gravite >= graviteMinimale else { return false }
            guard !r.isEmpty else { return true }
            return TexteEvenement.titre(l).localizedCaseInsensitiveContains(r)
                || ev.contains { ($0.sujet?.id ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.sujet?.nom ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.avant ?? "").localizedCaseInsensitiveContains(r)
                    || ($0.apres ?? "").localizedCaseInsensitiveContains(r) }
        }
    }
}

/// Fenetre du journal : evenements dates, filtres par famille et gravite, recherche.
struct FenetreJournal: View {
    @Environment(Surveillance.self) private var surveillance
    @State private var filtre = FiltreJournal()

    var body: some View {
        let lignes = filtre.appliquer(surveillance.lignesJournal)
        List(lignes) { ligne in
            LigneJournalVue(ligne: ligne)
        }
        .overlay {
            if lignes.isEmpty {
                ContentUnavailableView("Aucun événement", systemImage: "list.bullet.rectangle")
            }
        }
        .searchable(text: $filtre.recherche)
        .toolbar {
            Picker("Famille", selection: $filtre.famille) {
                ForEach(FamilleEvenement.allCases) { Text($0.titre).tag($0) }
            }
            Picker("Gravité", selection: $filtre.graviteMinimale) {
                Text("Tout").tag(Gravite.info)
                Text("Attention et alertes").tag(Gravite.attention)
                Text("Alertes").tag(Gravite.alerte)
            }
        }
        .navigationTitle("Journal")
        .frame(minWidth: 560, minHeight: 360)
        .fenetreDeLApp()
    }
}

/// Une ligne : pastille de gravite, titre, quand ; le detail des pertes regroupees ; pour les changements de parent ou
/// de chemin regroupes, les relais et, a deplier, leurs changements (comme dans la fiche).
struct LigneJournalVue: View {
    let ligne: LigneJournal
    /// Les changements regroupes deplies d'office (captures) ; sinon, replies.
    var deplie = false

    var body: some View {
        switch ligne {
        case .evenement(let e):
            contenu(TexteEvenement.titre(e), quand: TexteEvenement.quand(e), gravite: e.gravite)
        case .parents(let groupe), .chemins(let groupe):
            LigneChangements(groupe: groupe, police: .callout, deplie: deplie) {
                contenu(TexteEvenement.titre(ligne), quand: TexteEvenement.quand(ligne), gravite: ligne.gravite)
            }
        case .pertes(let groupe):
            DisclosureGroup {
                ForEach(groupe) { e in
                    Text("\(TexteEvenement.heure(e.date)) · \(TexteEvenement.titre(e))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } label: {
                contenu(TexteEvenement.titre(ligne), quand: TexteEvenement.quand(ligne),
                        gravite: ligne.gravite)
            }
        }
    }

    private func contenu(_ titre: String, quand: String, gravite: Gravite) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Self.couleur(gravite)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                Text(quand).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func couleur(_ g: Gravite) -> Color {
        switch g {
        case .info: .secondary
        case .attention: .orange
        case .alerte: .red
        }
    }
}
