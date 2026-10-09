import MaillageCoeur
import SwiftUI

// Morceaux de la fenetre de la vue par pieces, repris de celle du graphe : barre d'outils, ligne de la tournee, ecran
// d'attente, « Renommer… ».

/// Noeud choisi pour une feuille (surnom).
struct NoeudChoisi: Identifiable {
    let id: String
}

/// Capsule de gauche du haut de la fenetre : journal, rafraichir.
struct BarreOutils: View {
    @Environment(SondeMaillage.self) private var sonde
    @Environment(\.openWindow) private var openWindow

    /// Aide du bouton rafraichir : ce qu'il lancera vraiment, une tournee si la sonde est connectee et libre
    /// (`SondeMaillage.tourneeAuRafraichir`).
    static func aideRafraichir(tournee: Bool) -> String {
        tournee ? String(localized: "Rafraîchir : tournée de la sonde") : String(localized: "Rafraîchir : rien à relever sans sonde connectée")
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("Réseau Zigbee")
                .padding(.horizontal, 4)
            Button("Journal") {
                openWindow(id: "journal")
            }
            .buttonStyle(StyleBoutonCapsule())
            // Pendant une tournee : rien de plus.
            Button {
                sonde.rafraichir()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(StyleBoutonCapsule())
            .help(Self.aideRafraichir(tournee: sonde.tourneeAuRafraichir))
        }
    }
}

/// Ligne de la tournee en cours, en haut de la colonne de gauche, en plus petit : la capsule garde sa largeur, son
/// bouton rafraichir ne bouge pas sous le pointeur. Elle n'est la que pendant une tournee, et ne garde plus sa place
/// hors tournee (ronde finale du 02/10) : quand elle disparait, les bandeaux et le fil remontent ; quand elle
/// parait, ils redescendent, avec l'animation des bandeaux (`HautPieces`). La scene, elle, ne bouge pas : la marge du
/// haut compte sa place (`gabarit`) tant qu'une sonde est retenue, comme avant, et la vue d'ensemble ne se recadre pas
/// a chaque tournee. Vue a part : seule elle se redessine a chaque pas de la tournee, pas la fenetre de la vue.
struct LigneTournee: View {
    @Environment(SondeMaillage.self) private var sonde

    /// Ce que fait la ligne : montree pendant une tournee ; hors tournee, une sonde retenue, cachee, mais sa place
    /// comptee dans la marge du haut ; rien sans sonde.
    enum Place: Equatable {
        case montree
        case comptee
        case aucune
    }

    /// `debut` : celui de la tournee en cours, nil hors tournee. La fenetre ne lit que lui et la sonde retenue : elle ne
    /// se redessine qu'au debut et a la fin d'une tournee, pas a chaque pas.
    static func place(serie: String?, debut: Date?) -> Place {
        if debut != nil { return .montree }
        return serie != nil ? .comptee : .aucune
    }

    /// Le premier pas d'une tournee, montre avant le premier avancement recu ; et celui du gabarit.
    static let premierPas = AvancementTournee(etape: .etatSonde, fait: 0, total: 1)

    /// La ligne, cachee et sans horloge : sa place, de la taille de la ligne montree, que compte la marge du haut.
    static var gabarit: some View {
        IndicateurTournee(avancement: premierPas, debut: nil)
            .hidden()
            .accessibilityHidden(true)
    }

    var body: some View {
        if let debut = sonde.debutTournee {
            IndicateurTournee(avancement: sonde.avancement ?? Self.premierPas, debut: debut)
        }
    }
}

/// Tournee de la sonde en cours : un petit indicateur de progression et « Tables des routeurs · 12/26 · 0:42 », la
/// duree a jour chaque seconde. Sans debut : la place de la
/// ligne, sans horloge.
struct IndicateurTournee: View {
    let avancement: AvancementTournee
    let debut: Date?

    var body: some View {
        HStack(spacing: 6) {
            if avancement.total > 0 {
                ProgressView(value: Double(avancement.fait), total: Double(avancement.total))
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
            }
            // Largeur de la plus longue etape, compteur et duree compris : la capsule ne change
            // pas de taille d'une etape a l'autre (texte cale a gauche).
            ZStack(alignment: .leading) {
                ForEach(AvancementTournee.Etape.allCases, id: \.self) { e in
                    Text(TexteTournee.gabaritBarre(e)).hidden()
                }
                if let debut {
                    TimelineView(.periodic(from: debut, by: 1)) { contexte in
                        Text(TexteTournee.barre(avancement, debut: debut, maintenant: contexte.date))
                    }
                }
            }
            .monospacedDigit()
        }
        .controlSize(.small)
        .piluleDuHaut()
    }
}

/// Ecran d'attente, quand il n'y a pas de reseau a dessiner : ni maillage, ni appareil du pont.
struct EtatVide: View {
    var body: some View {
        ContentUnavailableView {
            Label("En attente du maillage de la sonde", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Choisissez la sonde dans Réglages › Sonde. La liaison au pont Hue viendra ensuite.")
        }
    }
}

/// Surnom d'un noeud : reste sur ce Mac, passe avant le nom du pont.
struct FeuilleRenommer: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.dismiss) private var fermer
    let id: String
    @State private var texte = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renommer « \(id) »").font(.headline)
            TextField("Surnom", text: $texte)
            Text("Le surnom reste sur ce Mac et passe avant le nom donné par le pont.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retirer le surnom") {
                    surveillance.renommer(id, en: nil)
                    fermer()
                }
                Spacer()
                Button("Annuler", role: .cancel) { fermer() }
                Button("Enregistrer") {
                    surveillance.renommer(id, en: texte)
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { texte = surveillance.noms.surnoms[id] ?? "" }
    }
}
