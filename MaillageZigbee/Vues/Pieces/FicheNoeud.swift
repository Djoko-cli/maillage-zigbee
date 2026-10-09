import MaillageCoeur
import SwiftUI

/// Fiche du noeud choisi : carte de verre en bas de la fenetre, sur toute sa largeur (etape 5, section 2), en quatre
/// colonnes cote a cote (`ColonnesFiche`, moins dans une fenetre etroite) :
/// 1. identite : le nom, la piece, la marque, le modele, le firmware, l'origine du nom, l'etat, le role (endormi d'apres
///    `ecoute`), la pile, les adresses, et les boutons « Renommer… », « Identifier » (l'appareil clignote, par le pont
///    Hue : seulement pour un appareil que le pont connait) et « Placer dans une pièce… » ;
/// 2. chemin : vers le pont (direct, ou via son prochain saut, en sauts ; suppose ; l'age de la route), le parent d'un
///    appareil final (ou son parent d'avant), le nombre de routeurs qui parlent directement au pont ; puis le journal
///    du noeud (ses changements de parent ou de chemin d'une meme heure en une ligne, a deplier) ;
/// 3. dependants : en pastilles, les routeurs qui passent par lui et les appareils dont il est le parent ;
/// 4. voisins entendus, resumes (nombre par qualite, barre de repartition, date des qualites) ; un clic deplie leur
///    liste complete en grille, sous les colonnes.
/// Dessous, sur toute la largeur, les courbes de l'historique (`CourbesFiche`). Le contenu des colonnes est propre a
/// Zigbee ; les colonnes et leurs composants sont generiques (`ComposantsFiche`).
struct FicheNoeud: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.colorScheme) private var apparence
    /// Une capture ne rend pas un bouton en lien : elle dessine son texte.
    @Environment(\.capturePieces) private var capture
    /// Pieces choisies pour les noeuds que le pont ne place pas : la vue par pieces seule les donne.
    @Environment(PiecesChoisies.self) private var piecesChoisies: PiecesChoisies?
    /// Le pont Hue : « Identifier » passe par lui. nil dans les vues de test sans pont.
    @Environment(NomsPont.self) private var nomsPont: NomsPont?
    let id: String
    /// La scene du meme rendu (`EntreeScene`), avec ce dont elle est faite : la fiche y lit le maillage, et « Placer
    /// dans une piece… » le graphe, sans rien reconstruire ; nil sans reseau.
    let entree: EntreeScene?
    /// Heure de la fenetre du graphe (sa `TimelineView`, chaque minute ; la fin de la demo en demo) : les durees de
    /// la fiche (« releve il y a... ») suivent l'heure sans autre evenement.
    let instant: Date
    @Binding var aRenommer: NoeudChoisi?
    /// Choisit un autre noeud (un dependant, un voisin).
    var choisir: (String) -> Void = { _ in }
    /// La liste des voisins entendus depliee d'office (captures) ; sinon, au clic.
    var listeDepliee = false
    /// Les lignes de changements regroupes du journal depliees d'office (captures) ; sinon, repliees, au clic.
    var changementsDeplies = false
    var fermer: () -> Void
    /// La liste des voisins entendus, depliee d'un clic ; repliee par defaut, et de nouveau a chaque autre noeud.
    @State private var voisinsDeplies = false

    private var deplies: Bool { listeDepliee || voisinsDeplies }

    /// Les couleurs des qualites, celles de la legende (la fenetre reste sombre).
    private static let palette = Palette(sombre: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let n = entree?.graphe.noeud(id) {
                ColonnesFiche {
                    colonneIdentite(n)
                    colonneChemin()
                    colonneDependants()
                    colonneVoisins()
                }
                // La place du bouton de fermeture, en haut a droite.
                .padding(.trailing, 30)
                if deplies, let m = entree?.maillage {
                    listeVoisins(m)
                }
            } else {
                Text("Ce nœud n'est plus visible.").foregroundStyle(.secondary)
            }
            if Self.courbesVisibles(dans: surveillance) {
                Divider().opacity(0.5)
                CourbesFiche(id: id, instant: instant)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button {
                fermer()
            } label: {
                Image(systemName: "xmark")
            }
            .boutonDeFiche()
            .help("Fermer")
            .padding(12)
        }
        .modifier(FondDeFiche())
        .onChange(of: id) { voisinsDeplies = false }
    }

    /// Le noeud est couronne : le coordinateur de la scene du meme rendu (`EntreeScene.chefs`) ; la fiche couronne le
    /// meme noeud que la scene.
    static func couronne(_ id: String, entree: EntreeScene?) -> Bool {
        entree?.chefs.contains(id) == true
    }

    /// Courbes de l'historique sous les colonnes, pour tout noeud, des que l'historique de la sonde a un releve (jamais
    /// en demo, sauf ses captures) : la fiche garde sa hauteur d'un noeud a l'autre.
    static func courbesVisibles(dans surveillance: Surveillance) -> Bool {
        !surveillance.historique.isEmpty
    }

    /// « Renommer… » : tout noeud du graphe, dont le surnom est garde sous son adresse longue ; pas un noeud sans
    /// adresse longue (cle provisoire).
    static func renommable(_ id: String, entree: EntreeScene?) -> Bool {
        entree?.graphe.noeud(id) != nil && NoeudZigbee.cleConnue(id)
    }

    // MARK: Colonne 1 : identite

    private func colonneIdentite(_ n: GrapheReseau.Noeud) -> some View {
        let a = entree?.appareils[id]
        let accessoire = surveillance.accessoire(id)
        let m = entree?.maillage
        let noeud = m?.noeud(id)
        return VStack(alignment: .leading, spacing: 4) {
            Text(surveillance.nom(id)).font(.title3.weight(.semibold))
            let description = Self.ligneDescription(maison: accessoire)
            if !description.isEmpty {
                Text(description).foregroundStyle(.secondary)
            }
            if let origine = Self.ligneOrigine(accessoire) {
                Text(origine).font(.caption).foregroundStyle(.secondary)
            }
            if Self.couronne(id, entree: entree) {
                PastilleChef()
            }
            HStack(spacing: 6) {
                let etat = Self.etat(a, inconnu: n.inconnu, sonde: id == m?.sonde)
                PointEtat(couleur: Self.couleur(a?.etat, inconnu: n.inconnu), pulse: a?.etat == .joignable)
                Text(etat)
                Text(verbatim: "· " + Self.texteRole(noeud?.type, endormi: a?.endormi == true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let b = accessoire?.batterie {
                HStack(spacing: 6) {
                    Image(systemName: Self.symboleBatterie(b))
                        .foregroundStyle(b.faible ? orange : b.charge == .enCharge ? Color.green : Color.primary)
                    Text(Self.ligneBatterie(b)).foregroundStyle(b.faible ? orange : Color.primary)
                    if let releve = surveillance.noms.maison?.date {
                        Text("· relevé \(Self.relatif(releve, instant))").foregroundStyle(.secondary)
                    }
                }
            }
            // Les adresses, sur une ligne si elle tient.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { adresses(noeud?.court) }
                VStack(alignment: .leading, spacing: 4) { adresses(noeud?.court) }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if Self.renommable(id, entree: entree) {
                    Button("Renommer…") { aRenommer = NoeudChoisi(id: id) }
                        .boutonDeFiche()
                }
                if let nomsPont, nomsPont.peutIdentifier(ieee: id) {
                    BoutonIdentifier(enCours: nomsPont.identification(ieee: id) == .enCours) {
                        nomsPont.identifier(ieee: id)
                    }
                }
                if let piecesChoisies, let entree,
                   let placement = PiecesChoisies.placement(id, dans: surveillance, entree: entree) {
                    MenuPlacer(placement: placement, domicile: surveillance.noms.maison?.domicile ?? "",
                               choisies: piecesChoisies)
                }
            }
            .padding(.top, 4)
            if let nomsPont, case .erreur(let message)? = nomsPont.identification(ieee: id) {
                Text(message).font(.caption).foregroundStyle(orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .colonneDuChef(Self.couronne(id, entree: entree))
    }

    /// L'adresse longue, selectionnable, puis l'adresse courte.
    @ViewBuilder
    private func adresses(_ court: UInt16?) -> some View {
        Text(verbatim: id).textSelection(.enabled).fixedSize()
        if let court {
            Text(Self.texteCourt(court)).fixedSize()
        }
    }

    // MARK: Colonne 2 : chemin

    private func colonneChemin() -> some View {
        let lignes = entree?.maillage.map { Self.lignesChemin(id, maillage: $0, nom: surveillance.nom, maintenant: instant) }
            ?? []
        let journal = surveillance.lignesJournal(de: id)
        return VStack(alignment: .leading, spacing: 4) {
            TitreColonne(titre: "Chemin")
            if lignes.isEmpty {
                Text("aucun chemin connu").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(lignes, id: \.self) { ligne in
                Text(ligne).font(.caption)
            }
            if !journal.isEmpty {
                TitreColonne(titre: "Journal").padding(.top, 8)
                ForEach(journal) { ligne in ligneJournal(ligne) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Une ligne du journal du noeud : un evenement isole sur une ligne ; les changements de parent ou de chemin d'une
    /// meme heure en une seule, repliee (plage horaire, nombre de changements, relais), a deplier.
    @ViewBuilder
    private func ligneJournal(_ ligne: LigneJournal) -> some View {
        switch ligne {
        case .parents(let groupe), .chemins(let groupe):
            LigneChangements(groupe: groupe, deplie: changementsDeplies) {
                Text("\(TexteEvenement.plage(groupe)) · \(TexteEvenement.changements(ligne))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .evenement, .pertes:
            ForEach(ligne.evenements) { e in
                Text("\(TexteEvenement.quand(e)) · \(TexteEvenement.titre(e))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Colonne 3 : dependants

    private func colonneDependants() -> some View {
        let dependants = entree?.maillage.map {
            DependantFiche.trier(FicheZigbee.dependants(de: id, maillage: $0), nom: surveillance.nom)
        } ?? []
        return VStack(alignment: .leading, spacing: 6) {
            TitreColonne(titre: "Dépendants")
            if dependants.isEmpty {
                texteAucun(vu: Self.vuParLaSonde(id, maillage: entree?.maillage))
            } else {
                Text(Self.ligneDependants(dependants)).font(.caption).foregroundStyle(.secondary)
                RangeesFluides {
                    ForEach(dependants) { d in
                        PastilleNoeud(nom: surveillance.nom(d.id), couleur: Self.palette.lienSonde(d.qualite),
                                      valeur: Self.valeurPastille(qualite: d.qualite)) {
                            choisir(d.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Colonne 4 : voisins entendus

    private func colonneVoisins() -> some View {
        let m = entree?.maillage
        let voisins = m.map { FicheZigbee.voisins(de: id, maillage: $0) } ?? []
        let resume = ResumeVoisins(voisins)
        return VStack(alignment: .leading, spacing: 5) {
            TitreColonne(titre: "Voisins entendus")
            if voisins.isEmpty {
                texteAucun(vu: Self.vuParLaSonde(id, maillage: m))
            } else {
                Text(Self.ligneResume(resume)).font(.caption)
                BarreRepartition(parts: resume.parts.map { (Self.palette.couleur($0.niveau), $0.nombre) })
                    .frame(maxWidth: 220)
                if capture {
                    etiquetteListe.foregroundStyle(.link)
                } else {
                    Button {
                        voisinsDeplies.toggle()
                    } label: {
                        etiquetteListe
                    }
                    .buttonStyle(.link)
                }
            }
            if let m, m.noeud(id) != nil, !voisins.isEmpty || m.noeud(id)?.route == true {
                Text(Self.ligneQualites(FicheZigbee.dateQualites(m))).font(.caption).foregroundStyle(.secondary)
            }
            if let m {
                ForEach(Self.lignesTable(id, maillage: m), id: \.self) { ligne in
                    Text(ligne).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Afficher la liste » ou « Replier la liste », selon la liste des voisins.
    @ViewBuilder
    private var etiquetteListe: some View {
        if deplies {
            Label("Replier la liste", systemImage: "chevron.up").font(.caption)
        } else {
            Label("Afficher la liste", systemImage: "chevron.down").font(.caption)
        }
    }

    /// La liste complete des voisins entendus, depliee sous les colonnes, en grille sur plusieurs colonnes : de la
    /// meilleure qualite a la plus faible, chacun avec son point de couleur et « LQI 230 / 224 » (le noeud, puis le
    /// voisin) ; un clic le choisit.
    private func listeVoisins(_ m: MaillageZigbee) -> some View {
        let voisins = ResumeVoisins.trier(FicheZigbee.voisins(de: id, maillage: m), nom: surveillance.nom)
        return GrilleListe {
            ForEach(voisins) { v in
                Button {
                    choisir(v.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Self.palette.lienSonde(v.qualite)).frame(width: 7, height: 7)
                        Text(verbatim: surveillance.nom(v.id)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.texteLQIs(v)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Textes des colonnes

    /// La colonne du chemin : pour le pont, combien de routeurs lui parlent directement ; pour un appareil final, son
    /// parent (ou son parent d'avant, avec son age), puis son chemin vers le pont ; pour un routeur, son chemin vers le
    /// pont et l'age de sa route.
    static func lignesChemin(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String,
                             maintenant: Date) -> [String] {
        guard let n = m.noeud(id) else { return [] }
        if n.type == .coordinateur { return [ligneRouteursDirects(FicheZigbee.routeursDirects(m))] }
        var lignes: [String] = []
        if !n.route, let p = ligneParent(id, maillage: m, nom: nom, maintenant: maintenant) { lignes.append(p) }
        lignes += lignesVersPont(id, maillage: m, nom: nom)
        if let age = ligneAgeChemin(id, maillage: m, maintenant: maintenant) { lignes.append(age) }
        return lignes
    }

    /// « 20 routeurs lui parlent directement » (le pont).
    static func ligneRouteursDirects(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "aucun routeur ne lui parle directement")
        case 1: String(localized: "1 routeur lui parle directement")
        default: String(localized: "\(n) routeurs lui parlent directement")
        }
    }

    /// Le parent d'un appareil final, avec la qualite du lien et son LQI ; le parent d'avant (`LienParent.dAvant`,
    /// absent des dernieres tables) avec son age, a `maintenant` (par defaut la date du maillage) : « parent connu il
    /// y a 40 min : Lampe bureau ». Nil sans parent.
    static func ligneParent(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String,
                            maintenant: Date? = nil) -> String? {
        guard let p = m.parent(de: id) else { return nil }
        if p.dAvant, let d = p.date {
            let age = relatif(d, maintenant ?? m.date, unites: .short)
            return String(localized: "parent connu \(age) : \(nom(p.parent))")
        }
        return String(localized: "parent \(nom(p.parent)), \(texteQualite(p.qualite))\(texteLQI(p.lqi))")
    }

    /// Ce que la sonde dit de la table d'un routeur : muet a deux tournees, ou non lue a celle-ci.
    static func lignesTable(_ id: String, maillage m: MaillageZigbee) -> [String] {
        guard let n = m.noeud(id) else { return [] }
        if n.muet { return [String(localized: "muet : sans réponse à deux tournées de suite")] }
        if n.route && n.tableNonLue { return [String(localized: "table non lue : liens vus seulement par ses voisins")] }
        return []
    }

    /// « 3 routeurs · 2 appareils » : le compte des dependants.
    static func ligneDependants(_ d: [DependantFiche]) -> String {
        let routeurs = d.count(where: \.routeur), appareils = d.count - routeurs
        return [routeurs == 0 ? nil : routeurs == 1 ? String(localized: "1 routeur") : String(localized: "\(routeurs) routeurs"),
                appareils == 0 ? nil : appareils == 1 ? String(localized: "1 appareil")
                    : String(localized: "\(appareils) appareils")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// « 28 voisins · 6 bons · 9 moyens · 13 faibles » (« · 2 inconnus ») : les niveaux absents n'y sont pas.
    static func ligneResume(_ r: ResumeVoisins) -> String {
        func compte(_ n: Int, un: String, plusieurs: String) -> String? {
            n == 0 ? nil : n == 1 ? un : plusieurs
        }
        let b = r.nombre(.bonne), m = r.nombre(.moyenne), f = r.nombre(.faible), i = r.nombre(.inconnue)
        return [r.total == 1 ? String(localized: "1 voisin") : String(localized: "\(r.total) voisins"),
                compte(b, un: String(localized: "1 bon"), plusieurs: String(localized: "\(b) bons")),
                compte(m, un: String(localized: "1 moyen"), plusieurs: String(localized: "\(m) moyens")),
                compte(f, un: String(localized: "1 faible"), plusieurs: String(localized: "\(f) faibles")),
                compte(i, un: String(localized: "1 inconnu"), plusieurs: String(localized: "\(i) inconnus"))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// « LQI 230 / 224 » : le LQI que le noeud mesure, puis celui du voisin ; « ? » pour un sens inconnu.
    static func texteLQIs(_ v: VoisinFiche) -> String {
        String(localized: "LQI \(texteLQI(v.lqiIci, seul: true)) / \(texteLQI(v.lqiLa, seul: true))")
    }

    /// L'appareil n'a pas ete retrouve dans Maison (`FusionNoms`) : son nom et sa piece sont ceux de l'app Hue. Rien
    /// quand il l'a ete, ni sans releve de Maison.
    static func ligneOrigine(_ a: AccessoireMaison?) -> String? {
        a?.origine == .pont ? String(localized: "nom de l'app Hue (pas trouvé dans Maison)") : nil
    }

    /// Piece, fabricant, modele, et firmware quand le pont le donne.
    static func ligneDescription(maison: AccessoireMaison?) -> String {
        let firmware = maison?.firmware.flatMap { $0.isEmpty ? nil : String(localized: "firmware \($0)") }
        return [maison?.piece, maison?.fabricant, maison?.modele, firmware].compactMap { $0 }.joined(separator: " · ")
    }

    /// « Coordinateur (le pont) », « Routeur », « Appareil final » (« · endormi ») ; « Rôle inconnu » hors maillage.
    static func texteRole(_ t: TypeNoeud?, endormi: Bool = false) -> String {
        let role = switch t {
        case .coordinateur?: String(localized: "Coordinateur (le pont)")
        case .routeur?: String(localized: "Routeur")
        case .final?: String(localized: "Appareil final")
        case .inconnu?, nil: String(localized: "Rôle inconnu")
        }
        return endormi ? String(localized: "\(role) · endormi") : role
    }

    /// « adresse courte 1A2B ».
    static func texteCourt(_ court: UInt16) -> String {
        String(localized: "adresse courte \(String(format: "%04X", court))")
    }

    /// « qualite 3 » ; « qualite inconnue » sans mesure.
    static func texteQualite(_ q: Int?) -> String {
        q.map { String(localized: "qualité \($0)") } ?? String(localized: "qualité inconnue")
    }

    /// La sonde a vu le noeud : il est dans le maillage qu'elle a releve. Un appareil que seuls le pont ou Maison
    /// connaissent n'y est pas : ses dependants et ses voisins ne sont pas « aucun », la sonde ne les connait pas.
    static func vuParLaSonde(_ id: String, maillage: MaillageZigbee?) -> Bool { maillage?.noeud(id) != nil }

    /// Une colonne vide : « aucun » si la sonde a vu le noeud (il n'a ni dependant ni voisin), « pas vu par la sonde »
    /// sinon.
    @ViewBuilder
    private func texteAucun(vu: Bool) -> some View {
        if vu {
            Text("aucun").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("pas vu par la sonde").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Ce que le point de couleur d'une pastille de dependant dit a VoiceOver : « qualité du lien : bonne ».
    static func valeurPastille(qualite: Int?) -> String {
        String(localized: "qualité du lien : \(NiveauQualite(qualite).nom)")
    }

    /// Un LQI : « 182 » seul, « ? » inconnu ; sinon « (LQI 182) », rien d'inconnu.
    static func texteLQI(_ lqi: Int?, seul: Bool = false) -> String {
        if seul { return lqi.map(String.init) ?? "?" }
        return lqi.map { " (LQI \($0))" } ?? ""
    }

    /// Le chemin d'un noeud vers le pont : « vers le pont : direct » quand son prochain saut est le pont ; sinon
    /// « vers le pont : via Plafonnier salon · 3 sauts » (le prochain saut : le chemin d'un routeur, le parent d'un
    /// appareil final ; les sauts jusqu'au pont), ou « … · chemin incomplet » (une boucle, ou un saut sans chemin) ;
    /// puis « chemin supposé (aucune route active vers le pont) » le cas echeant. Rien pour le pont, ni sans chemin.
    static func lignesVersPont(_ id: String, maillage m: MaillageZigbee, nom: (String) -> String) -> [String] {
        guard m.noeud(id)?.type != .coordinateur, let prochain = m.prochainSaut(de: id) else { return [] }
        var lignes: [String] = []
        if prochain == m.coordinateur?.ieee {
            lignes.append(String(localized: "vers le pont : direct"))
        } else if let n = m.sauts(de: id) {
            lignes.append(String(localized: "vers le pont : via \(nom(prochain)) · \(n) sauts"))
        } else {
            lignes.append(String(localized: "vers le pont : via \(nom(prochain)) · chemin incomplet"))
        }
        if m.chemin(de: id)?.suppose == true {
            lignes.append(String(localized: "chemin supposé (aucune route active vers le pont)"))
        }
        return lignes
    }

    /// L'age du chemin lu d'un routeur (sa route vers le pont, lue a une tournee qui peut etre d'avant : les routes des
    /// routeurs sont lues en plusieurs passes) : « chemin lu il y a 12 min » ; nil pour un chemin suppose ou sans date.
    static func ligneAgeChemin(_ id: String, maillage m: MaillageZigbee, maintenant: Date) -> String? {
        guard let c = m.chemin(de: id), !c.suppose, let d = c.date else { return nil }
        return String(localized: "chemin lu \(relatif(d, maintenant, unites: .short))")
    }

    /// La date des tables de voisins d'ou viennent les qualites : « qualités du 08/10 à 14:05 ».
    static func ligneQualites(_ d: Date) -> String {
        let jour = d.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
        let heure = d.formatted(date: .omitted, time: .shortened)
        return String(localized: "qualités du \(jour) à \(heure)")
    }

    /// Etat d'un noeud : celui de son appareil ; « inconnu du pont » pour un noeud que le pont ne connait pas ; « la
    /// sonde » pour elle.
    static func etat(_ a: AppareilAffiche?, inconnu: Bool, sonde: Bool) -> String {
        if sonde { return String(localized: "la sonde") }
        if inconnu { return String(localized: "inconnu du pont") }
        switch a?.etat {
        case .joignable?: return String(localized: "joignable")
        case .injoignable?: return String(localized: "injoignable")
        case .disparu?: return String(localized: "disparu")
        case .inconnu?, nil: return String(localized: "état inconnu")
        }
    }

    static func couleur(_ e: EtatAffiche?, inconnu: Bool) -> Color {
        if inconnu { return .gray }
        switch e {
        case .joignable?: return .green
        case .injoignable?, .disparu?: return .red
        case .inconnu?, nil: return .gray
        }
    }

    /// Niveau, puis l'etat de charge ; faible, « batterie faible » (et « en
    /// charge » seulement) ; sans niveau, l'alerte : « batterie OK » seulement
    /// si l'appareil le dit.
    static func ligneBatterie(_ b: BatterieMaison) -> String {
        var parties: [String] = []
        if let n = b.niveau {
            parties.append(String(localized: "\(n)\u{202F}%"))
            if b.faible { parties.append(String(localized: "batterie faible")) }
        } else if b.faible {
            parties.append(String(localized: "batterie faible"))
        } else if b.alerte == false {
            parties.append(String(localized: "batterie OK"))
        }
        switch b.charge {
        case .enCharge: parties.append(String(localized: "en charge"))
        case .horsCharge where !b.faible: parties.append(String(localized: "sur batterie"))
        case .nonRechargeable where !b.faible: parties.append(String(localized: "non rechargeable"))
        default: break
        }
        return parties.joined(separator: " · ")
    }

    /// Triangle si faible, eclair en charge, sinon le niveau par quart.
    static func symboleBatterie(_ b: BatterieMaison) -> String {
        if b.faible { return "exclamationmark.triangle.fill" }
        if b.charge == .enCharge { return "battery.100percent.bolt" }
        switch b.niveau ?? 100 {
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Orange de la batterie faible, assez fonce en mode clair pour se lire sur le verre pale.
    private var orange: Color { apparence == .dark ? .orange : Color(red: 0.72, green: 0.36, blue: 0) }

    /// "il y a 12 secondes", "maintenant" ; "il y a 12 min" en unites courtes (`.short` : en francais, `.abbreviated`
    /// donne « -12 min »).
    static func relatif(_ d: Date, _ reference: Date,
                        unites: RelativeDateTimeFormatter.UnitsStyle = .full) -> String {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = unites
        // L'heure de la fiche est un debut de minute (TimelineView de la fenetre) : une date plus
        // recente, d'un releve fait depuis, se lirait « dans 20 secondes ». Jamais dans le futur :
        // « maintenant » jusqu'a la minute suivante (la spec admet une minute de retard).
        return f.localizedString(for: d, relativeTo: max(d, reference))
    }
}

/// « Identifier » : fait clignoter l'appareil par le pont Hue. Grise pendant l'envoi des identifications.
struct BoutonIdentifier: View {
    let enCours: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if enCours {
                Label("Identification…", systemImage: "light.beacon.max")
            } else {
                Label("Identifier", systemImage: "light.beacon.max")
            }
        }
        .boutonDeFiche()
        .disabled(enCours)
        .help("Fait clignoter l'appareil, par le pont Hue, pour le repérer")
    }
}

extension View {
    /// Bouton de verre de la fiche ; dans une capture, qui ne rend pas le verre, celui des capsules.
    func boutonDeFiche() -> some View {
        modifier(BoutonDeFiche())
    }

    /// Colonne de la fiche qui porte la pastille du coordinateur : elle passe avant les autres. La pastille garde
    /// sa ligne (`PastilleChef`), mais le `.frame(minWidth:)` de la colonne ne la fait pas plus large que la
    /// place que la fiche lui propose : quand les colonnes se serrent, la pastille deborderait sur la
    /// colonne voisine.
    func colonneDuChef(_ couronne: Bool) -> some View {
        layoutPriority(couronne ? 1 : 0)
    }
}

private struct BoutonDeFiche: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content.buttonStyle(StyleBoutonCapsule())
        } else {
            content.buttonStyle(.glass)
        }
    }
}

/// Fond de la fiche : du verre aux coins de 22 pt (le Liquid Glass de macOS). Une capture, qui ne rend pas
/// le verre, dessine a sa place un fond proche de celui de la maquette de la fiche (rgba(40, 48, 72, 0,40),
/// filet de 0,5 pt blanc a 0,22, ombre noire a 0,4), avec deux ecarts : l'ombre est posee sur ce fond
/// translucide, donc multipliee par son opacite (0,4) ; et l'ombre interne de la maquette (un lisere clair
/// d'un point en haut) n'y est pas. Ce dessin ne sert qu'aux captures.
private struct FondDeFiche: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content
                .background(RoundedRectangle(cornerRadius: 22).fill(fondVerreCapture.opacity(0.4))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 8))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}

/// « 👑 Coordinateur du réseau Zigbee », sous le nom du noeud couronne (polissage B, section 3 ; maquette de la
/// fiche, `.chef`) : 10,5 pt, marges de 2 x 8 pt, en capsule, sur une ligne : les colonnes de la fiche, serrees dans
/// une fenetre etroite, ne la font pas passer a la ligne. La plus etroite des quatre colonnes fait environ 190 pt : le
/// texte se reduit alors, jusqu'a 70 %, au lieu de deborder sur la colonne voisine.
struct PastilleChef: View {
    var body: some View {
        Text("👑 Coordinateur du réseau Zigbee")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.texteChef)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.jauneChef.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Palette.jauneChef.opacity(0.5), lineWidth: 0.5))
    }
}

/// Point d'etat de la fiche. Joignable, il pulse doucement : un halo s'elargit
/// et s'efface toutes les 2 s, sauf si « Reduire les animations » est active.
private struct PointEtat: View {
    let couleur: Color
    let pulse: Bool
    @Environment(\.accessibilityReduceMotion) private var reduire

    var body: some View {
        Circle().fill(couleur).frame(width: 8, height: 8)
            .background {
                if pulse && !reduire {
                    Circle().fill(couleur)
                        .phaseAnimator([false, true]) { halo, etendu in
                            halo.scaleEffect(etendu ? 2.6 : 1).opacity(etendu ? 0 : 0.55)
                        } animation: { etendu in
                            etendu ? .easeOut(duration: 2) : nil
                        }
                }
            }
    }
}
