import Charts
import MaillageCoeur
import SwiftUI

/// Les reperes de changement de parent ou de chemin sur les graphes de la fiche : de simples traits verticaux, sans
/// texte dans le trace (au 09/10, les noms ecrits au-dessus de la courbe se superposaient quand un routeur changeait
/// plusieurs fois de prochain saut en quelques heures). Un trait fin sur toute la hauteur, tres leger, et une pointe plus
/// marquee en haut du trace ; des changements proches, a l'echelle affichee, se fondent en un seul trait marque de leur
/// nombre (« x4 », `ReperesCourbe`). Au survol de la pointe, une bulle donne l'heure et la destination, ou la liste.
enum ReperesFiche {
    /// Hauteur de la zone haute du trace ou la pointe d'un repere se survole (pt) : plus bas, le survol est celui des
    /// courbes, sans conflit.
    static let zone: CGFloat = 20
    /// Longueur de la pointe en haut du trait (pt).
    static let pointe: CGFloat = 10

    /// Les reperes d'un graphe qui couvre `debut` a `fin` sur `largeur` pt.
    static func regrouper(_ changements: [ChangementParent], debut: Date, fin: Date, largeur: CGFloat) -> [RepereCourbe] {
        ReperesCourbe.regrouper(changements, duree: fin.timeIntervalSince(debut), largeur: Double(largeur))
    }

    /// La date du repere survole (celle de son premier changement) : le pointeur est dans la zone haute du trace
    /// `cadre` (l'espace du pointeur) et a moins de `ReperesCourbe.portee` du trait ; nil ailleurs, et le survol est alors
    /// celui des courbes. `convertir` donne l'heure d'une abscisse du trace (depuis son bord gauche).
    static func repereSous(_ position: CGPoint, cadre: CGRect, reperes: [RepereCourbe], debut: Date, fin: Date,
                           convertir: (CGFloat) -> Date?) -> Date? {
        let y = position.y - cadre.minY
        guard y >= 0, y < zone, let date = convertir(position.x - cadre.minX) else { return nil }
        return ReperesCourbe.sous(date, parmi: reperes, duree: fin.timeIntervalSince(debut), largeur: Double(cadre.width))?.date
    }

    /// Une ligne de la bulle : « 14:21 → Plan de travail (gauche) » ; en 7 j et 30 j, le jour aussi.
    static func ligne(_ ch: ChangementParent, noms: [String: String], periode: PeriodeCourbes, locale: Locale,
                      fuseau: TimeZone = .current) -> String {
        EchelleSignal.heure(ch.date, periode: periode, locale: locale, fuseau: fuseau) + " → " + (noms[ch.parent] ?? ch.parent)
    }

    /// La derniere ligne d'une bulle trop longue : « et 3 autres » (« et 1 autre »).
    static func texteAutres(_ n: Int) -> String {
        n == 1 ? String(localized: "et 1 autre") : String(localized: "et \(n) autres")
    }

    /// Le petit nombre d'un repere groupe : « ×4 ».
    static func texteNombre(_ r: RepereCourbe) -> String { "×\(r.nombre)" }
}

/// Les traits des reperes et, au survol de l'un, sa bulle ; posee dans le `chartOverlay` d'un graphe (et non en
/// `RuleMark` ni en `annotation` : sous le verre de la fiche, les annotations du graphe ne se dessinent pas, verification
/// du 05/10). Ne capte aucun geste : le survol est celui du graphe.
struct CoucheReperes: View {
    @Environment(\.locale) private var langue
    let reperes: [RepereCourbe]
    /// La date du repere survole ; nil, aucun.
    let survole: Date?
    let noms: [String: String]
    let periode: PeriodeCourbes
    let debut: Date
    let fin: Date
    let proxy: ChartProxy
    let geo: GeometryProxy

    var body: some View {
        if let plot = proxy.plotFrame {
            let cadre = geo[plot]
            ZStack(alignment: .topLeading) {
                ForEach(reperes, id: \.date) { r in
                    if let x = proxy.position(forX: r.date) {
                        trait(r, x: cadre.minX + x, cadre: cadre)
                    }
                }
                if let r = reperes.first(where: { $0.date == survole }), let x = proxy.position(forX: r.date) {
                    bulle(r)
                        .fixedSize()
                        .frame(width: 0, height: 0,
                               alignment: EchelleSignal.aGauche(r.date, debut: debut, fin: fin) ? .topTrailing : .topLeading)
                        .position(x: cadre.minX + x, y: cadre.minY + ReperesFiche.pointe + 4)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Le trait d'un repere : tres leger sur toute la hauteur, plus net sur sa pointe, et son nombre s'il en fond plusieurs.
    private func trait(_ r: RepereCourbe, x: CGFloat, cadre: CGRect) -> some View {
        let actif = r.date == survole
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: x, y: cadre.minY))
                p.addLine(to: CGPoint(x: x, y: cadre.maxY))
            }
            .stroke(Color.primary.opacity(actif ? 0.4 : 0.16), lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: x, y: cadre.minY))
                p.addLine(to: CGPoint(x: x, y: cadre.minY + ReperesFiche.pointe))
            }
            .stroke(Color.primary.opacity(actif ? 0.95 : 0.6), lineWidth: actif ? 2 : 1.4)
            if r.nombre > 1 {
                Text(verbatim: ReperesFiche.texteNombre(r))
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(actif ? 0.95 : 0.7))
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .topLeading)
                    .position(x: x + 2, y: cadre.minY)
            }
        }
    }

    /// La bulle d'un repere : un changement par ligne (heure → destination), au plus `lignesMax`, puis « et n autres ».
    private func bulle(_ r: RepereCourbe) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(r.visibles().enumerated()), id: \.offset) { _, ch in
                Text(verbatim: ReperesFiche.ligne(ch, noms: noms, periode: periode, locale: langue))
            }
            if r.autres() > 0 {
                Text(verbatim: ReperesFiche.texteAutres(r.autres())).foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 4)
    }
}
