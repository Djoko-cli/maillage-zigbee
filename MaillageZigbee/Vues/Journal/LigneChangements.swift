import MaillageCoeur
import SwiftUI

/// Les changements d'une ligne regroupee, un par ligne (« 20:58 → Plan de travail (droit) »), derriere un filet
/// vertical a gauche.
struct ListeChangements: View {
    let groupe: [Evenement]
    var police: Font = .caption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(groupe.enumerated()), id: \.offset) { _, e in
                Text(TexteEvenement.changement(e))
                    .font(police)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle().fill(.tertiary).frame(width: 1)
        }
    }
}

/// Une ligne de changements de parent ou de chemin regroupes, dans la fiche comme dans la fenetre du journal : la tete
/// (a la charge de l'appelant), les relais en texte secondaire, et, sous un chevron, la liste des changements. Repliee
/// par defaut.
struct LigneChangements<Tete: View>: View {
    let groupe: [Evenement]
    var police: Font = .caption
    @State private var deplie: Bool
    private let tete: Tete

    init(groupe: [Evenement], police: Font = .caption, deplie: Bool = false, @ViewBuilder tete: () -> Tete) {
        self.groupe = groupe
        self.police = police
        self._deplie = State(initialValue: deplie)
        self.tete = tete()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { deplie.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(deplie ? 90 : 0))
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        tete
                        Text(TexteEvenement.resume(Regroupement.resumeRelais(groupe)))
                            .font(police)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(deplie ? Text("déplié") : Text("replié"))
            if deplie {
                ListeChangements(groupe: groupe, police: police)
                    .padding(.leading, 14)
            }
        }
    }
}
