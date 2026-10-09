import Charts
import MaillageCoeur
import SwiftUI

/// Courbes de l'historique dans la fiche (spec de l'app, section 7 ; etape 5, section 3), sur 24 h, 7 j ou 30 j, en une
/// bande large sous les colonnes de la fiche : la qualite des liens du noeud (au plus six courbes par defaut, celles du
/// chemin et des dependants, `ChoixCourbes` ; la case « tous les liens » montre le reste), leur legende en pastilles
/// (un clic met une courbe en avant, un second rend les autres), un axe nomme « bonne / moyenne / faible », l'heure et
/// le LQI au survol, des reperes aux changements de chemin ou de parent (de simples traits, sans texte ; la bulle d'un
/// repere donne l'heure et la destination, et des reperes proches se fondent en un seul, `ReperesCourbe`) ; et, pour un
/// routeur, le signal que la sonde en recoit, avec les changements de parent de la sonde marques de meme (ce signal
/// depend d'abord de l'endroit ou elle est posee). Le signal a toujours une echelle, et sa valeur se lit au survol (polissage D, section 4.3).
struct CourbesFiche: View {
    @Environment(Surveillance.self) private var surveillance
    /// Une capture ne rend pas les controles d'AppKit (le choix de la periode, la case) : elle les dessine.
    @Environment(\.capturePieces) private var capture
    let id: String
    /// Fin des courbes : l'heure de la fiche (`FicheNoeud.instant`), qui avance chaque minute.
    let instant: Date
    @State private var periodeChoisie: PeriodeCourbes = .jour
    /// La periode imposee a une capture (qui ne rend pas le choix de la periode) ; nil, celle du choix.
    @Environment(\.periodeCapture) private var periodeCapture
    /// La case « tous les liens » : toutes les courbes, et non les six du chemin et des dependants.
    @State private var tous = false
    private var periode: PeriodeCourbes { periodeCapture ?? periodeChoisie }

    /// Hauteur des graphes de la bande (pt).
    static let hauteur: CGFloat = 170
    /// Largeur du graphe du signal, a droite de la bande (pt).
    static let largeurSignal: CGFloat = 300

    var body: some View {
        let courbes = surveillance.courbes(noeud: id, periode: periode, fin: instant)
        let noms = courbes.map { c in
            surveillance.nomsHistorique(Set(c.liens.map(\.id) + (c.parents + c.chemins + c.parentsSonde).map(\.parent)))
        } ?? [:]
        let cachees = courbes.map { ChoixCourbes.cachees(cles: $0.liens.map(\.id), prioritaires: $0.prioritaires) } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Historique de la sonde").font(.headline)
                if capture {
                    HStack(spacing: 2) {
                        ForEach(PeriodeCourbes.allCases) { p in
                            Text(Self.titre(p)).font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(p == periode ? 0.22 : 0.06)))
                        }
                    }
                } else {
                    Picker("Période", selection: $periodeChoisie) {
                        ForEach(PeriodeCourbes.allCases) { Text(Self.titre($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if cachees > 0 || tous {
                    if capture {
                        Label(Self.texteTous(cachees: cachees), systemImage: tous ? "checkmark.square" : "square")
                            .font(.caption)
                    } else {
                        Toggle(isOn: $tous) {
                            Text(Self.texteTous(cachees: cachees)).font(.caption)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            if let c = courbes, !c.estVide {
                let montrees = ChoixCourbes.montrees(cles: c.liens.map(\.id), prioritaires: c.prioritaires, tous: tous)
                HStack(alignment: .top, spacing: 24) {
                    if !montrees.isEmpty {
                        GrapheQualite(courbes: c.liens, debut: c.debut, fin: c.fin, reperes: Self.reperes(c),
                                      titre: Self.titreQualite(c), cles: montrees, noms: noms,
                                      nomCourbe: { Self.nomLien($0, noms) }, periode: periode)
                            .id(Self.identiteGraphe(id: id, tous: tous, periode: periode))
                    }
                    if !c.signal.isEmpty {
                        GrapheSignal(c: c, noms: noms, periode: periode)
                            .frame(width: montrees.isEmpty ? nil : Self.largeurSignal)
                    }
                }
            } else {
                Text("Pas encore d'historique de la sonde pour ce nœud sur cette période.")
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: id) { tous = false }
    }

    /// L'identite du graphe de qualite : un autre noeud, la case « tous les liens » ou une autre periode le refont, et la
    /// courbe mise en avant (l'etat du graphe) s'efface. Cliquer une pastille ne change que cet etat : seul le graphe se
    /// recalcule, non l'historique de la periode (relecture de l'etape 5, Mineur 4).
    static func identiteGraphe(id: String, tous: Bool, periode: PeriodeCourbes) -> String {
        "\(id)|\(tous)|\(periode.rawValue)"
    }

    static func titre(_ p: PeriodeCourbes) -> String {
        switch p {
        case .jour: String(localized: "24 h")
        case .semaine: String(localized: "7 j")
        case .mois: String(localized: "30 j")
        }
    }

    /// « tous les liens (+4) » : la case, et ce qu'elle ajoute.
    static func texteTous(cachees: Int) -> String {
        cachees > 0 ? String(localized: "tous les liens (+\(cachees))") : String(localized: "tous les liens")
    }

    /// « Qualité du lien vers le parent » pour un appareil final, « Qualité des liens » pour un routeur.
    static func titreQualite(_ c: CourbesNoeud) -> String {
        c.liens.allSatisfy { $0.id == CourbesNoeud.cleParent }
            ? String(localized: "Qualité du lien vers le parent") : String(localized: "Qualité des liens")
    }

    /// Nom d'une courbe de lien : le noeud a l'autre bout, ou « Parent » pour le lien d'un appareil final.
    static func nomLien(_ cle: String, _ noms: [String: String]) -> String {
        cle == CourbesNoeud.cleParent ? String(localized: "Parent") : noms[cle] ?? cle
    }

    /// Le nom d'une qualite sur l'axe vertical : 3 bonne, 2 moyenne, 1 faible, 0 tres faible.
    static func nomQualite(_ v: Double) -> String {
        switch Int(v.rounded()) {
        case 3...: String(localized: "bonne")
        case 2: String(localized: "moyenne")
        case 1: String(localized: "faible")
        default: String(localized: "très faible")
        }
    }

    /// Couleurs des courbes, dans l'ordre des courbes montrees (le chemin et les dependants d'abord, qui les gardent
    /// avec « tous les liens ») ; ni vert, ni jaune, ni orange : ce sont les couleurs des qualites.
    static let couleurs: [Color] = [
        Color(red: 0.36, green: 0.66, blue: 1.0), Color(red: 1.0, green: 0.47, blue: 0.72),
        Color(red: 0.32, green: 0.86, blue: 0.9), Color(red: 0.74, green: 0.56, blue: 1.0),
        Color(red: 0.9, green: 0.82, blue: 0.62), Color(red: 1.0, green: 0.52, blue: 0.47),
        Color(red: 0.58, green: 0.62, blue: 1.0), Color(white: 0.82),
    ]

    static func couleur(_ rang: Int) -> Color { couleurs[rang % couleurs.count] }

    /// Le motif du trait de la courbe de rang `rang` : plein pour les huit premieres, puis les couleurs se repetent
    /// (« tous les liens ») avec un trait tirete, puis pointille, pour que deux courbes de meme couleur se distinguent.
    static func tirets(_ rang: Int) -> [CGFloat] {
        switch rang / couleurs.count {
        case 0: []
        case 1: [5, 3]
        default: [1.5, 2.5]
        }
    }

    /// Troncons d'un seul point : une ligne a besoin de deux points, ceux-la sont dessines en point
    /// (juste apres la premiere tournee, ou un point isole entre deux trous ; ajout du controleur,
    /// relecture de la tache 9).
    static func tronconsSeuls(_ points: [PointCourbe]) -> Set<Int> {
        Set(Dictionary(grouping: points, by: \.troncon).filter { $0.value.count == 1 }.keys)
    }

    /// Les reperes du graphe de qualite : les changements de parent (appareil final) et de prochain saut vers le pont
    /// (routeur), par date.
    static func reperes(_ c: CourbesNoeud) -> [ChangementParent] {
        (c.parents + c.chemins).sorted { $0.date < $1.date }
    }

    /// Les graduations de l'heure, espacees : toutes les 3 h sur 24 h, chaque jour sur 7 j, tous les 5 jours sur 30 j.
    static func graduations(_ p: PeriodeCourbes) -> (unite: Calendar.Component, pas: Int) {
        switch p {
        case .jour: (.hour, 3)
        case .semaine: (.day, 1)
        case .mois: (.day, 5)
        }
    }

    /// L'echelle du signal (polissage D, section 4.3) : son domaine, des multiples de 50 de LQI autour de ses valeurs,
    /// et ses graduations ; sans valeur, de 0 a 255.
    static func echelle(_ c: CourbesNoeud) -> (domaine: ClosedRange<Double>, graduations: [Double]) {
        let d = EchelleSignal.domaine(c.signal.map(\.valeur)) ?? EchelleSignal.bornes
        return (d, EchelleSignal.graduations(d))
    }
}

/// Le graphe de la qualite des liens d'un noeud (etape 5, section 3) : ses courbes montrees (`cles`), leur legende en
/// pastilles cliquables (une courbe mise en avant estompe les autres), l'axe nomme, les reperes des changements, et au
/// survol l'heure et le LQI de chaque courbe (ou de celle mise en avant). Une vue a part, comme `GrapheSignal` : le
/// survol ne refait qu'elle. Generique, elle ne sait rien du protocole (reprise par Maillage Thread) : on lui donne les
/// courbes, la fenetre de temps, les reperes, le titre et le nom de chaque courbe ; `CourbesFiche` les tire de
/// `CourbesNoeud`.
struct GrapheQualite: View {
    @Environment(\.locale) private var langue
    /// Les courbes de lien ; `cles` dit lesquelles se montrent, et dans quel ordre.
    let courbes: [CourbeLien]
    let debut: Date
    let fin: Date
    /// Les changements de chemin ou de parent, en reperes sur le trace (par date).
    let reperes: [ChangementParent]
    /// Le titre du graphe, au-dessus de la legende.
    let titre: String
    let cles: [String]
    /// Les noms des noeuds nommes par les bulles des reperes (par cle de noeud).
    let noms: [String: String]
    /// Le nom d'une courbe (sa pastille de legende et son etiquette de survol), par sa cle.
    let nomCourbe: (String) -> String
    let periode: PeriodeCourbes
    /// La courbe mise en avant par sa pastille ; nil, aucune. L'etat est celui du graphe : le parent le refait (`id`) a
    /// un autre noeud, une autre periode ou un autre choix de courbes.
    @State private var enAvant: String?
    /// L'heure du releve sous le pointeur ; nil, ailleurs.
    @State private var survole: Date?
    /// La date du repere dont la pointe est sous le pointeur ; nil, ailleurs. Jamais en meme temps que `survole`.
    @State private var repereSurvole: Date?

    /// Opacite d'une courbe estompee par la mise en avant d'une autre.
    static let opaciteEstompee = 0.15

    /// Ce que le survol montre a l'heure `heure` : pour chaque courbe montree (ou celle mise en avant seulement), son
    /// releve le plus proche, a moins du seuil du survol (`EchelleSignal.plusProche`) ; dans l'ordre des courbes.
    static func releves(_ courbes: [CourbeLien], cles: [String], enAvant: String?, heure: Date?,
                        periode: PeriodeCourbes) -> [(cle: String, point: PointCourbe)] {
        guard let heure else { return [] }
        return cles.filter { enAvant == nil || enAvant == $0 }.compactMap { k in
            courbes.first { $0.id == k }.flatMap { EchelleSignal.plusProche($0.points, de: heure, periode: periode) }
                .map { (k, $0) }
        }
    }

    /// Une ligne du survol : « Lampe bureau : LQI 182 » ; sans LQI, le nom de sa qualite.
    static func ligneSurvol(_ nom: String, _ p: PointCourbe) -> String {
        if let lqi = p.lqi { return String(localized: "\(nom) : LQI \(Int(lqi.rounded()))") }
        return String(localized: "\(nom) : \(CourbesFiche.nomQualite(p.valeur))")
    }

    /// La courbe mise en avant, si elle est montree (relecture de l'etape 5, I1) ; nil, aucune.
    private var miseEnAvant: String? { ChoixCourbes.enAvant(enAvant, parmi: cles) }

    func opacite(_ cle: String) -> Double { miseEnAvant == nil || miseEnAvant == cle ? 1 : Self.opaciteEstompee }

    /// Le petit decalage vertical de la courbe de rang `rang` parmi `n` : deux liens de meme qualite ne se cachent pas
    /// l'un l'autre ; centre sur le niveau, au plus 0,12 de part et d'autre. Le survol donne la vraie valeur.
    static func decalage(_ rang: Int, sur n: Int) -> Double {
        guard n > 1 else { return 0 }
        let pas = min(0.05, 0.24 / Double(n - 1))
        return (Double(rang) - Double(n - 1) / 2) * pas
    }

    var body: some View {
        let rangs = Dictionary(uniqueKeysWithValues: cles.enumerated().map { ($1, $0) })
        let montrees = cles.compactMap { cle in courbes.first { $0.id == cle } }
        let survol = Self.releves(courbes, cles: cles, enAvant: miseEnAvant, heure: survole, periode: periode)
        let g = CourbesFiche.graduations(periode)
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: titre).font(.caption).foregroundStyle(.secondary)
            RangeesFluides {
                ForEach(cles, id: \.self) { k in
                    PastilleNoeud(nom: nomCourbe(k), couleur: CourbesFiche.couleur(rangs[k] ?? 0),
                                  indice: String(localized: "Met la courbe en avant ; un second clic rend les autres"),
                                  enAvant: miseEnAvant == k) {
                        enAvant = ChoixCourbes.basculer(enAvant, k)
                    }
                    .opacity(opacite(k) < 1 ? 0.45 : 1)
                }
            }
            Chart {
                ForEach(montrees, id: \.id) { l in
                    let seuls = CourbesFiche.tronconsSeuls(l.points)
                    let couleur = CourbesFiche.couleur(rangs[l.id] ?? 0).opacity(opacite(l.id))
                    let ecart = Self.decalage(rangs[l.id] ?? 0, sur: cles.count)
                    ForEach(l.points, id: \.date) { p in
                        LineMark(x: .value("Heure", p.date), y: .value("Qualité", p.valeur + ecart),
                                 series: .value("Tronçon", "\(l.id)#\(p.troncon)"))
                            .foregroundStyle(couleur)
                            .lineStyle(StrokeStyle(lineWidth: miseEnAvant == l.id ? 2.6 : 1.6,
                                                   dash: CourbesFiche.tirets(rangs[l.id] ?? 0)))
                            .interpolationMethod(.stepEnd)
                        if seuls.contains(p.troncon) {
                            PointMark(x: .value("Heure", p.date), y: .value("Qualité", p.valeur + ecart))
                                .foregroundStyle(couleur)
                                .symbolSize(18)
                        }
                    }
                }
                if let h = survol.first?.point.date {
                    RuleMark(x: .value("Heure", h)).foregroundStyle(.primary.opacity(0.5))
                }
            }
            .chartXScale(domain: debut ... fin)
            .chartYScale(domain: -0.25 ... 3.25)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text(CourbesFiche.nomQualite(v.as(Double.self) ?? 0)) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: g.unite, count: g.pas)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: periode == .jour ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let cadre = proxy.plotFrame.map { geo[$0] }
                    let groupes = cadre.map { ReperesFiche.regrouper(reperes, debut: debut, fin: fin, largeur: $0.width) } ?? []
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            var heure: Date?
                            var repere: Date?
                            if case .active(let position) = phase, let cadre {
                                let convertir = { (x: CGFloat) in proxy.value(atX: x, as: Date.self) }
                                // La pointe d'un repere, en haut du trace, prend le survol ; ailleurs, celui des courbes.
                                repere = ReperesFiche.repereSous(position, cadre: cadre, reperes: groupes, debut: debut,
                                                                 fin: fin, convertir: convertir)
                                if repere == nil {
                                    heure = convertir(position.x - cadre.minX).flatMap { h in
                                        Self.releves(courbes, cles: cles, enAvant: miseEnAvant, heure: h, periode: periode).first?.point.date
                                    }
                                }
                            }
                            if heure != survole { survole = heure }
                            if repere != repereSurvole { repereSurvole = repere }
                        }
                    CoucheReperes(reperes: groupes, survole: repereSurvole, noms: noms, periode: periode, debut: debut,
                                  fin: fin, proxy: proxy, geo: geo)
                    if let cadre = proxy.plotFrame, let d = survol.first?.point.date,
                       let x = proxy.position(forX: d) {
                        etiquette(survol, date: d)
                            .fixedSize()
                            .frame(width: 0, height: 0,
                                   alignment: EchelleSignal.aGauche(d, debut: debut, fin: fin) ? .topTrailing : .topLeading)
                            .position(x: geo[cadre].origin.x + x, y: geo[cadre].origin.y + 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: CourbesFiche.hauteur)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: periode) {
            survole = nil
            repereSurvole = nil
        }
    }

    /// L'etiquette du survol : l'heure du releve, puis chaque courbe avec son point de couleur et son LQI.
    private func etiquette(_ survol: [(cle: String, point: PointCourbe)], date: Date) -> some View {
        let rangs = Dictionary(uniqueKeysWithValues: cles.enumerated().map { ($1, $0) })
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: EchelleSignal.heure(date, periode: periode, locale: langue, fuseau: .current))
                .font(.caption2.weight(.semibold))
            ForEach(survol, id: \.cle) { r in
                HStack(spacing: 4) {
                    Circle().fill(CourbesFiche.couleur(rangs[r.cle] ?? 0)).frame(width: 6, height: 6)
                    Text(verbatim: Self.ligneSurvol(nomCourbe(r.cle), r.point))
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 4)
    }
}

/// Le graphe du signal vu par la sonde, avec sa valeur au survol (polissage D, section 4.3). Une vue a part : le survol
/// change `survole` quand le releve sous le pointeur change, et seul ce graphe se recalcule, non les courbes de
/// `CourbesFiche` (qui relisent l'historique de la periode).
struct GrapheSignal: View {
    @Environment(\.locale) private var langue
    let c: CourbesNoeud
    let noms: [String: String]
    let periode: PeriodeCourbes
    /// L'heure du releve sous le pointeur ; nil, ailleurs. L'etat disparait avec le graphe, et se remet a zero quand la
    /// periode change.
    @State private var survole: Date?
    /// La date du repere (changement de parent de la sonde) dont la pointe est sous le pointeur ; nil, ailleurs.
    @State private var repereSurvole: Date?

    /// Ce que la vue affiche, decide sans fenetre : l'echelle, le releve sous l'heure survolee (aucun dans un trou), et le
    /// cote de son etiquette (a gauche du trait dans la moitie droite du graphe, a droite sinon). Les changements de
    /// parent de la sonde n'ont pas de texte dans le trace : leur bulle ne s'ouvre qu'au survol de leur pointe
    /// (`ReperesFiche`).
    struct Affichage {
        let domaine: ClosedRange<Double>
        let graduations: [Double]
        let releve: PointCourbe?
        let alignement: Alignment
    }

    static func affichage(_ c: CourbesNoeud, survole: Date?, periode: PeriodeCourbes) -> Affichage {
        let echelle = CourbesFiche.echelle(c)
        let releve = survole.flatMap { EchelleSignal.plusProche(c.signal, de: $0, periode: periode) }
        let aGauche = releve.map { EchelleSignal.aGauche($0.date, debut: c.debut, fin: c.fin) } ?? false
        return Affichage(domaine: echelle.domaine, graduations: echelle.graduations, releve: releve,
                         alignement: aGauche ? .trailing : .leading)
    }

    /// L'heure survolee apres un evenement du pointeur : celle du releve le plus proche de sa position (`convertir`,
    /// nil hors de la zone de trace), nil dans un trou de la courbe et quand il sort. Elle ne change que lorsque ce
    /// releve change : le graphe ne se refait pas a chaque pixel (relecture finale, Mineur 4).
    static func heureSurvolee(_ phase: HoverPhase, signal: [PointCourbe], periode: PeriodeCourbes,
                              convertir: (CGPoint) -> Date?) -> Date? {
        switch phase {
        case .active(let position):
            convertir(position).flatMap { EchelleSignal.plusProche(signal, de: $0, periode: periode)?.date }
        case .ended: nil
        }
    }

    var body: some View {
        let a = Self.affichage(c, survole: survole, periode: periode)
        VStack(alignment: .leading, spacing: 2) {
            Text("Signal vu par la sonde (LQI)").font(.caption).foregroundStyle(.secondary)
            Chart {
                let seuls = CourbesFiche.tronconsSeuls(c.signal)
                ForEach(c.signal, id: \.date) { p in
                    LineMark(x: .value("Heure", p.date), y: .value("Signal", p.valeur),
                             series: .value("Tronçon", p.troncon))
                    if seuls.contains(p.troncon) {
                        PointMark(x: .value("Heure", p.date), y: .value("Signal", p.valeur))
                            .symbolSize(16)
                    }
                }
                // Le releve survole : un trait a son heure, un point sur sa valeur ; son etiquette est dans `chartOverlay`.
                if let r = a.releve {
                    RuleMark(x: .value("Heure", r.date))
                        .foregroundStyle(.primary.opacity(0.5))
                    PointMark(x: .value("Heure", r.date), y: .value("Signal", r.valeur))
                        .symbolSize(30)
                }
            }
            .chartXScale(domain: c.debut ... c.fin)
            .chartYScale(domain: a.domaine)
            .chartYAxis { AxisMarks(values: a.graduations) }
            .chartXAxis {
                // Etroit : deux fois moins de graduations que le graphe de qualite.
                let g = CourbesFiche.graduations(periode)
                AxisMarks(values: .stride(by: g.unite, count: 2 * g.pas)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: periode == .jour ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    let cadre = proxy.plotFrame.map { g[$0] }
                    let groupes = cadre.map {
                        ReperesFiche.regrouper(c.parentsSonde, debut: c.debut, fin: c.fin, largeur: $0.width)
                    } ?? []
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            var repere: Date?
                            if case .active(let position) = phase, let cadre {
                                repere = ReperesFiche.repereSous(position, cadre: cadre, reperes: groupes, debut: c.debut,
                                                                 fin: c.fin) { proxy.value(atX: $0, as: Date.self) }
                            }
                            let heure = repere != nil ? nil : Self.heureSurvolee(phase, signal: c.signal, periode: periode) { position in
                                proxy.plotFrame.flatMap { cadre in
                                    proxy.value(atX: position.x - g[cadre].origin.x, as: Date.self)
                                }
                            }
                            if heure != survole { survole = heure }
                            if repere != repereSurvole { repereSurvole = repere }
                        }
                    CoucheReperes(reperes: groupes, survole: repereSurvole, noms: noms, periode: periode, debut: c.debut,
                                  fin: c.fin, proxy: proxy, geo: g)
                    // L'etiquette du releve survole, en haut du trace, a gauche du trait dans la moitie droite, a droite
                    // sinon. Posee ici et non en `annotation` : sous le verre de la fiche, les annotations du graphe ne
                    // se dessinent pas (verification du 05/10).
                    if let r = a.releve, let cadre = proxy.plotFrame, let x = proxy.position(forX: r.date) {
                        Text(verbatim: EchelleSignal.etiquette(r, periode: periode, locale: langue, fuseau: .current))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                            .frame(width: 0, height: 0, alignment: a.alignement)
                            .position(x: g[cadre].origin.x + x, y: g[cadre].origin.y + 8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: CourbesFiche.hauteur)
            if !c.parentsSonde.isEmpty {
                Text("Trait vertical : la sonde change de parent.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: periode) {
            survole = nil
            repereSurvole = nil
        }
    }
}
