import MaillageCoeur
import SwiftUI

/// Reglages › Maison : le demon Passeur Noms (etat, ouverture de session, profil), le dernier releve de Maison qu'il a
/// servi (etat, date, accessoires et zones), combien d'appareils du pont Maison nomme, « Rafraichir depuis Maison », le
/// probleme du dernier releve, et l'aide quand le demon manque.
struct ReglagesMaison: View {
    @Environment(NomsPasseur.self) private var passeur
    @Environment(Surveillance.self) private var surveillance

    var body: some View {
        if surveillance.mode == .demo {
            Text("Mode démo : le relevé de Maison de la démo, pas de Passeur.").foregroundStyle(.secondary)
        }
        LabeledContent("Passeur Noms", value: NomsPasseur.texteDemon(connecte: passeur.connecte, etat: passeur.etat))
        Toggle("Ouvrir Passeur Noms à l'ouverture de session", isOn: Binding(
            get: { passeur.etat?.ouvertureSession == .active },
            set: { passeur.reglerOuvertureSession($0) }))
            .disabled(!NomsPasseur.interrupteurActif(connecte: passeur.connecte, etat: passeur.etat))
        if passeur.connecte, passeur.etat?.ouvertureSession == .aApprouver {
            Text("Accepte Passeur Noms dans Réglages Système › Général › Ouverture.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let fin = passeur.etat?.profilExpire, NomsPasseur.profilBientotExpire(passeur.etat, maintenant: surveillance.maintenant) {
            Text("Le profil de Passeur Noms expire le \(fin.formatted(date: .abbreviated, time: .omitted)) : relance outils/passeur.sh.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        LabeledContent("État", value: Self.texteEtat(releve: passeur.releve, enCours: passeur.releveEnCours))
        if let r = passeur.releve {
            LabeledContent("Dernier relevé", value: Self.texteReleve(r))
            LabeledContent("Étages", value: Self.texteZones(r.zones ?? []))
        }
        LabeledContent("Appareils du pont", value: Self.texteBilan(surveillance.bilanFusion))
        if let p = passeur.probleme {
            Text(p).font(.caption).foregroundStyle(.red)
        }
        if passeur.passeurAbsent {
            Text("Passeur Noms s'installe avec Maillage Thread (outils/passeur.sh), puis sert aussi Maillage Zigbee : voir le README.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        HStack {
            Button("Rafraîchir depuis Maison") { passeur.relire() }
                .disabled(passeur.inerte || passeur.releveEnCours)
            Spacer()
        }
        Text("Les noms, les pièces et les étages (zones) viennent de l'app Maison, lus par Passeur Noms, qui les envoie dès qu'ils changent ; le pont Hue donne les adresses, l'état de connexion et les piles.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// L'etat en quelques mots.
    static func texteEtat(releve: ReleveMaison?, enCours: Bool) -> String {
        if enCours { return String(localized: "relevé en cours…") }
        return releve == nil ? String(localized: "aucun relevé : noms de l'app Hue") : String(localized: "relevé reçu")
    }

    /// « 42 accessoires · 8 oct. 2026 à 14:32 ».
    static func texteReleve(_ r: ReleveMaison) -> String {
        String(localized: "\(r.accessoires.count) accessoires · \(r.date.formatted(date: .abbreviated, time: .shortened))")
    }

    /// Les zones de Maison, dans son ordre : les etages de la vue par pieces.
    static func texteZones(_ zones: [ZoneMaison]) -> String {
        zones.isEmpty ? String(localized: "aucune zone dans Maison") : zones.map(\.nom).joined(separator: ", ")
    }

    /// « 20 nommés par Maison · 1 avec le nom de l'app Hue » ; sans pont lu ou sans releve, ce qui manque.
    static func texteBilan(_ b: FusionNoms.Bilan?) -> String {
        guard let b else { return String(localized: "noms de l'app Hue seulement") }
        return String(localized: "\(b.apparies) nommés par Maison · \(b.nonApparies) avec le nom de l'app Hue")
    }
}
