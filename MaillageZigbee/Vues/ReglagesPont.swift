import MaillageCoeur
import SwiftUI

/// Reglages › Pont Hue : l'etat du pont ; le pont trouve (modele, adresse, identifiant) ; « Lier… », l'instruction et
/// le compte a rebours de l'attente du bouton ; « Oublier le pont » ; la saisie d'une adresse, si Bonjour ne trouve
/// pas le pont ; la derniere lecture et le nombre d'appareils lus.
struct ReglagesPont: View {
    @Environment(NomsPont.self) private var pont
    @State private var adresse = ""
    @State private var verification = false

    var body: some View {
        LabeledContent("État", value: Self.texteEtat(pont.etat, lie: pont.lie, lecture: pont.lectureEnCours))
        if let p = pont.pont {
            LabeledContent("Modèle", value: p.modele ?? "—")
            LabeledContent("Adresse") { Text(verbatim: p.adresse).textSelection(.enabled) }
            LabeledContent("Identifiant") { Text(verbatim: p.identifiant).textSelection(.enabled) }
        }
        if let n = pont.noms {
            LabeledContent("Dernière lecture", value: Self.texteLecture(n))
        }
        liaison
        if pont.reseauLocalRefuse {
            Text("Réseau local refusé : autorisez Maillage Zigbee dans Réglages Système › Confidentialité et sécurité › Réseau local.")
                .font(.caption)
                .foregroundStyle(.red)
        }
        if let m = Self.message(pont.etat) {
            Text(m).font(.caption).foregroundStyle(pont.etat == .aLier ? .orange : .red)
        }
        HStack {
            TextField("Adresse IP du pont", text: $adresse)
                .textFieldStyle(.roundedBorder)
                .onSubmit(utiliser)
            Button("Utiliser cette adresse", action: utiliser)
                .disabled(adresse.trimmingCharacters(in: .whitespaces).isEmpty || verification || pont.liaisonEnCours)
        }
        Text("Si le pont n'est pas trouvé : son adresse IP est dans l'app Hue, parmi les réglages du pont.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if pont.pont != nil {
            Button("Oublier le pont") { pont.oublier() }
                .disabled(Self.enLiaison(pont.etat))
        }
    }

    /// « Lier… » et son explication ; pendant l'attente, l'instruction, le compte a rebours et « Annuler ».
    @ViewBuilder
    private var liaison: some View {
        if case .liaisonEnCours(let reste) = pont.etat {
            VStack(alignment: .leading, spacing: 6) {
                Text("Appuyez sur le bouton rond du pont Hue.").font(.headline)
                ProgressView(value: Double(NomsPont.dureeLiaison - reste), total: Double(NomsPont.dureeLiaison))
                HStack {
                    Text("Encore \(reste) s").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Annuler") { pont.annulerLiaison() }
                }
            }
        } else if pont.pont != nil && !pont.lie {
            HStack {
                Button("Lier…") { pont.lier() }
                Spacer()
            }
            Text("Après « Lier… », appuyez dans les 60 secondes sur le bouton rond du pont Hue. La clé donnée par le pont va au trousseau de ce Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func utiliser() {
        let a = adresse
        guard !a.trimmingCharacters(in: .whitespaces).isEmpty, !verification, !pont.liaisonEnCours else { return }
        verification = true
        Task {
            await pont.utiliserAdresse(a)
            verification = false
        }
    }

    static func enLiaison(_ e: NomsPont.Etat) -> Bool {
        if case .liaisonEnCours = e { return true }
        return false
    }

    /// L'etat en quelques mots.
    static func texteEtat(_ e: NomsPont.Etat, lie: Bool, lecture: Bool) -> String {
        switch e {
        case .introuvable: String(localized: "aucun pont trouvé")
        case .trouve: String(localized: "trouvé, non lié")
        case .aLier: String(localized: "à relier")
        case .liaisonEnCours: String(localized: "liaison en cours…")
        case .lie: lecture ? String(localized: "lié · lecture…") : String(localized: "lié")
        case .erreur: lie ? String(localized: "lié · erreur") : String(localized: "erreur")
        }
    }

    /// Le message a montrer sous l'etat : l'erreur, ou la cle refusee.
    static func message(_ e: NomsPont.Etat) -> String? {
        switch e {
        case .erreur(let m): m
        case .aLier: String(localized: "Le pont a refusé la clé (l'app a été retirée dans l'app Hue ?) : liez-le de nouveau.")
        default: nil
        }
    }

    /// « 23 appareils · 8 oct. 2026 à 14:32 ».
    static func texteLecture(_ n: NomsMaison) -> String {
        String(localized: "\(n.accessoires.count) appareils · \(n.date.formatted(date: .abbreviated, time: .shortened))")
    }
}
