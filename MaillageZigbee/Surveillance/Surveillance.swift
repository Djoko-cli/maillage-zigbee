import AppKit
import MaillageCoeur
import Observation
import os

/// Chiffres du reseau affiche, pour la barre des menus.
struct ResumeReseau: Equatable {
    /// Routeurs du maillage, le coordinateur compris.
    var routeurs: Int
    /// Appareils du pont, et noeuds finaux du maillage qu'il ne connait pas.
    var appareils: Int
    /// Appareils qui ne sont pas joignables (disparus, injoignables).
    var injoignables: Int
}

/// Modele de l'app : maillages de la sonde -> journal, notifications et historique ; noms du pont et de Maison ; etat lu
/// par les vues. Le pont la nourrit par `nomsPont` (`NomsPont.surNoms`), le Passeur par `releveMaison`
/// (`NomsPasseur.surReleve`) : `noms.maison` est leur fusion (`FusionNoms`) ; la sonde, a chaque tournee, par
/// `recevoir`.
@MainActor
@Observable
final class Surveillance {
    enum Mode: Equatable {
        /// Journal et historique sur disque, notifications.
        case direct
        /// Le faux reseau Hue de la demo, rien sur disque, pas de notification.
        case demo
    }

    let mode: Mode
    /// Journal : evenements gardes (90 jours) puis ceux de la session, du plus ancien au plus recent.
    private(set) var evenements: [Evenement] = []
    private(set) var erreurJournal: String?
    var noms: ResolveurNoms
    /// Les noms lus sur le pont Hue ; nil sans pont lu (le pont oublie : le suivi des connexions repart de zero).
    var nomsPont: NomsMaison? {
        didSet {
            fusionner()
            if nomsPont == nil { suiviConnexions = SuiviConnexions() }
        }
    }
    /// Le dernier releve de Maison reussi, par le Passeur ; nil sans releve.
    var releveMaison: ReleveMaison? {
        didSet { fusionner() }
    }
    /// Combien d'appareils du pont Maison nomme ; nil sans pont ou sans releve de Maison.
    private(set) var bilanFusion: FusionNoms.Bilan?
    /// Dernier maillage de la sonde ; nil sans sonde.
    private(set) var maillage: MaillageZigbee?
    /// Reception du dernier maillage, a la fin de sa tournee : son age se compte depuis (le maillage, lui, est date du
    /// debut de sa tournee).
    private(set) var maillageRecu: Date?
    /// Une tournee de la sonde est en cours (`SondeMaillage.surTournee`) : le maillage affiche attend le suivant, il
    /// n'est pas « ancien ».
    var tourneeEnCours = false
    /// Historique de la sonde : les releves des 30 derniers jours, du plus ancien au plus recent ; toujours vide en
    /// demo, sauf dans ses captures (`historiqueDeCapture`).
    private(set) var historique: [ReleveMaillage] = []

    /// Les captures de la demo montrent les courbes de la fiche (etape 5) : l'historique invente de la demo
    /// (`MaillageDemo.historique`). En demo seulement, et seulement pour elles ; rien sur disque.
    func historiqueDeCapture(_ releves: [ReleveMaillage]) {
        guard mode == .demo else { return }
        historique = releves
    }

    /// Les captures de la demo montrent un noeud qui hesite entre plusieurs relais (changements regroupes du journal) :
    /// ces evenements inventes s'ajoutent a ceux de la demo. En demo seulement, et seulement pour elles ; rien sur
    /// disque.
    func evenementsDeCapture(_ nouveaux: [Evenement]) {
        guard mode == .demo else { return }
        let tous = (evenements + nouveaux).enumerated()
        evenements = tous.sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// Age du maillage de la sonde, depuis sa reception : frais jusqu'a 16 min (une tournee toutes les 15 min), et tant
    /// qu'une tournee est en cours ; ancien ensuite (la sonde ne repond plus) jusqu'a 45 min ; perime au-dela, tournee
    /// ou non (le graphe n'a plus de liens).
    enum Fraicheur: Equatable {
        case frais, ancien, perime
    }

    /// Branche sur les notifications (mode direct seulement).
    @ObservationIgnored var surAlertes: (([AlerteAEnvoyer]) -> Void)?
    @ObservationIgnored private let journal: JournalFichiers?
    @ObservationIgnored private let fichierSurnoms: URL?
    @ObservationIgnored private var alertes = Alertes()
    @ObservationIgnored private var suiviMaillage = SuiviMaillage()
    /// L'etat de connexion de chaque appareil selon le pont, d'une lecture a l'autre : « disparu », « revenu ».
    @ObservationIgnored private var suiviConnexions = SuiviConnexions()
    /// Le dernier parent connu de chaque appareil final (mode direct seulement) : un appareil final absent des dernieres
    /// tables garde son parent d'avant 24 h, en pointilles (`ParentsConnus`).
    @ObservationIgnored private var parentsConnus = ParentsConnus()
    /// Historique sur disque : mode direct avec un dossier ; nil : nulle part (demo, tests).
    @ObservationIgnored private let fichiersHistorique: HistoriqueFichiers?
    /// Mois (annee, mois) de la derniere purge des fichiers ; nil : pas encore purges.
    @ObservationIgnored private var moisDernierePurge: DateComponents?
    @ObservationIgnored private var debutVeille: Date?
    @ObservationIgnored private var observateurs: [NSObjectProtocol] = []

    /// Historique garde en memoire : les courbes de la fiche vont jusqu'a 30 jours.
    static let dureeHistorique: TimeInterval = 30 * 24 * 3600
    /// Fraicheur du maillage (`Fraicheur`).
    nonisolated static let ageFrais: TimeInterval = 16 * 60
    nonisolated static let agePerime: TimeInterval = 45 * 60
    /// Journal du Mac (Console, sous-systeme fr.djoko.maillage.zigbee) : jamais de donnees du reseau.
    nonisolated static let journalMac = Logger(subsystem: "fr.djoko.maillage.zigbee", category: "historique")

    /// Lance par les tests (heberges dans l'app) : ne rien ecouter ni ecrire.
    static var sousTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// Dossier de l'app : Application Support/Maillage Zigbee (dans le conteneur du bac a sable).
    static var dossierParDefaut: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Maillage Zigbee")
    }

    /// `dossier` : ou garder le journal, les surnoms et l'historique de la sonde (nil : nulle part).
    init(mode: Mode, dossier: URL?) {
        self.mode = mode
        switch mode {
        case .direct:
            journal = dossier.map { JournalFichiers(dossier: $0.appendingPathComponent("Journal")) }
            fichierSurnoms = dossier?.appendingPathComponent("surnoms.json")
            noms = ResolveurNoms(surnoms: fichierSurnoms.map(Surnoms.lire) ?? [:])
            fichiersHistorique = dossier.map { HistoriqueFichiers(dossier: $0) }
        case .demo:
            journal = nil
            fichierSurnoms = nil
            nomsPont = NomsDemo.maison
            releveMaison = NomsDemo.releveMaison
            let f = FusionNoms.fusionner(pont: NomsDemo.maison, maison: NomsDemo.releveMaison)
            noms = ResolveurNoms(maison: f.noms)
            bilanFusion = f.bilan
            fichiersHistorique = nil
        }
    }

    /// Une lecture reussie du pont (`NomsPont.surLecture`, apres `nomsPont`) : les appareils passes de joignables a
    /// injoignables, ou revenus, d'apres l'etat de connexion que le pont donne, vont au journal (et aux notifications :
    /// les pertes groupees). La premiere lecture est un etat initial ; le cache relu au lancement n'arrive pas ici.
    func lecturePont(_ n: NomsMaison) {
        ajouter(suiviConnexions.integrer(n) { [noms, maillage] ieee in
            Self.nom(ieee, noms: noms, sonde: maillage?.sonde)
        })
    }

    /// Les noms du pont, nommes par Maison (`FusionNoms`) : a chaque nouveau releve, de l'un ou de l'autre.
    private func fusionner() {
        let f = FusionNoms.fusionner(pont: nomsPont, maison: releveMaison)
        noms.maison = f.noms
        bilanFusion = f.bilan
    }

    func demarrer() {
        switch mode {
        case .demo:
            recevoir(MaillageDemo.maillageAvant, a: MaillageDemo.debut)
            recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        case .direct:
            chargerJournal()
            Task { [weak self] in await self?.chargerHistorique() }
            observerVeille()
        }
    }

    /// Purge le journal (mois finis depuis plus de 90 jours) puis le lit. Une purge qui echoue (droits sur un vieux
    /// fichier) n'empeche pas la lecture. Sans dossier : rien.
    func chargerJournal() {
        guard let journal else { return }
        let maintenant = Date()
        moisDernierePurge = Calendar.current.dateComponents([.year, .month], from: maintenant)
        _ = try? journal.purger(maintenant: maintenant)
        do {
            evenements = try journal.lire()
        } catch {
            erreurJournal = error.localizedDescription
        }
    }

    func arreter() {
        observateurs.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observateurs = []
    }

    /// Nouveau maillage de la sonde, recu a `date` (fin de sa tournee) : ses evenements vont au journal ; en mode
    /// direct, son releve va a l'historique, en memoire et, avec un dossier, sur disque. Un echec d'ecriture est
    /// consigne dans le journal du Mac ; le releve reste en memoire.
    func recevoir(_ recu: MaillageZigbee, a date: Date) {
        // Les parents lus d'abord (ils prennent la place de ceux d'avant), puis ceux d'avant pour les appareils finaux que
        // les dernieres tables n'ont plus (mode direct seulement : la demo n'a pas d'avant).
        if mode == .direct { parentsConnus.retenir(recu) }
        let m = mode == .direct ? parentsConnus.completer(recu) : recu
        maillage = m
        maillageRecu = date
        ajouter(suiviMaillage.integrer(m) { [noms] ieee in Self.nom(ieee, noms: noms, sonde: m.sonde) })
        guard mode == .direct else { return }
        let r = ReleveMaillage(m)
        let limite = date.addingTimeInterval(-Self.dureeHistorique)
        historique = historique.filter { $0.date >= limite } + [r]
        purgerSiNouveauMois(date)
        guard let f = fichiersHistorique else { return }
        do {
            try f.ajouter(r)
        } catch {
            Self.journalMac.error("releve de l'historique non ecrit : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purge le journal et l'historique (mois finis depuis plus de 90 jours, comme au lancement) quand le mois de
    /// `date` n'est pas celui de la derniere purge : l'app de la barre des menus peut tourner des semaines sans etre
    /// relancee. Un echec est ignore : la purge reviendra au lancement suivant. Sans dossier (demo, tests) : rien.
    private func purgerSiNouveauMois(_ date: Date) {
        let mois = Calendar.current.dateComponents([.year, .month], from: date)
        guard mois != moisDernierePurge else { return }
        moisDernierePurge = mois
        _ = try? journal?.purger(maintenant: date)
        _ = try? fichiersHistorique?.purger(maintenant: date)
    }

    /// Relit les 30 derniers jours de l'historique, hors de l'acteur principal, apres avoir purge les mois finis depuis
    /// plus de 90 jours ; les releves recus entre-temps restent. Les releves des dernieres 24 h redonnent le dernier parent
    /// connu des appareils finaux (`ParentsConnus`). `maintenant` : l'heure du lancement (injectee par les tests). Sans
    /// dossier (demo, tests) : rien.
    func chargerHistorique(maintenant: Date = Date()) async {
        guard let f = fichiersHistorique else { return }
        moisDernierePurge = Calendar.current.dateComponents([.year, .month], from: maintenant)
        let debut = maintenant.addingTimeInterval(-Self.dureeHistorique)
        do {
            let lus = try await Task.detached(priority: .utility) {
                // Une purge qui echoue n'empeche pas la lecture.
                _ = try? f.purger(maintenant: maintenant)
                return try f.lire(depuis: debut)
            }.value
            // Les dates relues sont tronquees a la milliseconde (codage) : un releve recu pendant la lecture, ecrit
            // puis relu, garde jusqu'a 1 ms de moins que sa copie en memoire. Il n'est pas repris.
            let premier = (historique.first?.date ?? .distantFuture).addingTimeInterval(-0.001)
            historique = lus.filter { $0.date < premier } + historique
            // Le dernier parent connu des appareils finaux, retrouve dans les releves des dernieres 24 h.
            for r in lus.filter({ $0.date >= maintenant.addingTimeInterval(-ParentsConnus.duree) }) {
                parentsConnus.retenir(r)
            }
        } catch {
            Self.journalMac.error("historique illisible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sonde oubliee (`SondeMaillage.surOubli`) : son maillage part tout de suite, sans attendre qu'il soit perime. Son
    /// suivi aussi : le maillage suivant (une autre sonde, plus tard) est un point de depart, sans evenement.
    /// L'historique reste : il parle du reseau, pas de la sonde.
    func oublierMaillage() {
        maillage = nil
        maillageRecu = nil
        suiviMaillage = SuiviMaillage()
        parentsConnus = ParentsConnus()
    }

    /// Veille du Mac (appele au reveil).
    func noterVeille(debut: Date, fin: Date) {
        ajouter(suiviMaillage.noterVeille(DateInterval(start: debut, end: max(fin, debut))))
    }

    /// Donne (ou retire, avec nil ou "") un surnom a un noeud.
    func renommer(_ id: String, en surnom: String?) {
        let s = surnom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        noms.surnoms[id] = s.isEmpty ? nil : s
        guard let fichierSurnoms else { return }
        do {
            try Surnoms.ecrire(noms.surnoms, dans: fichierSurnoms)
        } catch {
            erreurJournal = error.localizedDescription
        }
    }

    /// Dernier maillage en JSON (Reglages › Diagnostic, « Enregistrer une capture… ») ; nil sans maillage.
    func captureJSON() throws -> Data? {
        try maillage.map { try CodageJSON.encodeur(lisible: true).encode($0) }
    }

    private func ajouter(_ nouveaux: [Evenement]) {
        guard !nouveaux.isEmpty else { return }
        evenements.append(contentsOf: nouveaux)
        do {
            try journal?.ajouter(nouveaux)
        } catch {
            erreurJournal = error.localizedDescription
        }
        let envoyer = alertes.traiter(nouveaux)
        if mode == .direct && !envoyer.isEmpty { surAlertes?(envoyer) }
    }

    private func observerVeille() {
        let nc = NSWorkspace.shared.notificationCenter
        observateurs.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.debutVeille = Date() }
        })
        observateurs.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let debut = self.debutVeille else { return }
                self.debutVeille = nil
                self.noterVeille(debut: debut, fin: Date())
            }
        })
    }

    // MARK: - Pour les vues

    /// Reference a l'heure du Mac : la fraicheur du graphe ; la fin de la demo en demo. La fiche passe par
    /// `maintenant(a:)`, a l'heure de sa fenetre.
    var maintenant: Date { maintenant(a: Date()) }

    /// Reference des durees a l'heure `horloge` (celle de la fenetre du graphe, que sa `TimelineView` avance chaque
    /// minute) : cette heure, ou la fin de la demo.
    func maintenant(a horloge: Date) -> Date { mode == .demo ? MaillageDemo.fin : horloge }

    /// Nom affiche d'un noeud par son adresse longue : surnom, nom sur le pont, « Sonde » pour la sonde, sinon
    /// l'adresse longue ; « Nœud 1A2B » pour un noeud sans adresse longue (cle provisoire), jamais renomme.
    static func nom(_ ieee: String, noms: ResolveurNoms, sonde: String?) -> String {
        guard NoeudZigbee.cleConnue(ieee) else {
            return String(localized: "Nœud \(String(ieee.drop { $0 == "~" }))")
        }
        if let n = noms.nomConnu(ieee: ieee) { return n }
        if ieee == sonde { return String(localized: "Sonde") }
        return ieee
    }

    /// Nom affiche d'un noeud du graphe (son adresse longue).
    func nom(_ ieee: String) -> String { Self.nom(ieee, noms: noms, sonde: maillage?.sonde) }

    /// L'appareil du pont d'un noeud ; nil si le pont ne le connait pas.
    func accessoire(_ ieee: String) -> AccessoireMaison? { noms.accessoire(ieee: ieee) }

    /// Les appareils du pont qui ont une adresse longue, a dessiner (`etat(_:presents:)`). Endormi : un appareil final
    /// dont la table de son parent dit le recepteur eteint au repos (`ecoute` faux) ; sans maillage, rien n'est dit.
    var appareilsAffiches: [AppareilAffiche] {
        let m = maillageAffiche
        let presents = m.map { Set($0.noeuds.map(\.ieee)) }
        return (noms.maison?.accessoires ?? []).compactMap { a in
            guard let ieee = a.ieee?.uppercased() else { return nil }
            let etat = Self.etat(a, presents: presents)
            return AppareilAffiche(id: ieee, nom: nom(ieee), piece: a.piece, etat: etat,
                                   endormi: m?.noeud(ieee)?.endormi == true, batterie: a.batterie)
        }
    }

    /// Etat affiche d'un appareil du pont. L'etat de connexion que donne le pont l'emporte : `connected`, joignable ;
    /// `connectivity_issue`, `disconnected`, `unidirectional_incoming`, injoignable. Sans cet etat (demo, etat inconnu
    /// de l'app) : joignable s'il est dans le maillage, disparu sinon, inconnu sans maillage (`presents` nil).
    nonisolated static func etat(_ a: AccessoireMaison, presents: Set<String>?) -> EtatAffiche {
        switch a.connexion {
        case .connecte: return .joignable
        case .deconnecte, .problemeConnexion, .entrantSeul: return .injoignable
        case .inconnue, nil: break
        }
        guard let presents, let ieee = a.ieee?.uppercased() else { return .inconnu }
        return presents.contains(ieee) ? .joignable : .disparu
    }

    /// Fraicheur d'un maillage recu a `recu`.
    nonisolated static func fraicheur(_ recu: Date, maintenant: Date, tourneeEnCours: Bool = false) -> Fraicheur {
        let age = maintenant.timeIntervalSince(recu)
        if age > agePerime { return .perime }
        return age <= ageFrais || tourneeEnCours ? .frais : .ancien
    }

    /// Fraicheur du maillage de la sonde a `maintenant` ; nil sans maillage.
    func fraicheurMaillage(a maintenant: Date) -> Fraicheur? {
        maillageRecu.map { Self.fraicheur($0, maintenant: maintenant, tourneeEnCours: tourneeEnCours) }
    }

    /// Le maillage a montrer ; nil sans sonde ou s'il est perime.
    var maillageAffiche: MaillageZigbee? {
        guard let m = maillage, fraicheurMaillage(a: maintenant) != .perime else { return nil }
        return m
    }

    /// Le maillage affiche a ete recu il y a plus de 16 min, et aucune tournee n'est en cours : la sonde ne repond plus.
    var maillageAncien: Bool {
        fraicheurMaillage(a: maintenant) == .ancien
    }

    /// Il y a un reseau a dessiner : un maillage, ou des appareils du pont.
    var aUnReseau: Bool { maillageAffiche != nil || !appareilsAffiches.isEmpty }

    /// Chiffres du reseau affiche ; nil sans rien a montrer.
    var resume: ResumeReseau? {
        guard aUnReseau else { return nil }
        let affiches = appareilsAffiches
        let m = maillageAffiche
        let connus = Set(affiches.map(\.id))
        let routeurs = m?.noeuds.filter(\.route).count ?? 0
        let finauxInconnus = m?.noeuds.filter { !$0.route && !connus.contains($0.ieee) }.count ?? 0
        let appareilsRoutant = Set(m?.noeuds.filter(\.route).map(\.ieee) ?? [])
        return ResumeReseau(routeurs: routeurs,
                            appareils: affiches.filter { !appareilsRoutant.contains($0.id) }.count + finauxInconnus,
                            injoignables: affiches.filter { $0.etat == .disparu || $0.etat == .injoignable }.count)
    }

    /// Alerte en cours : un evenement grave dans l'heure.
    var alerte: Bool {
        let recent = maintenant.addingTimeInterval(-3600)
        return evenements.reversed().prefix { $0.date >= recent }.contains { $0.gravite == .alerte }
    }

    var lignesJournal: [LigneJournal] { Regroupement.lignes(evenements) }

    /// 5 derniers evenements d'un noeud (son adresse longue), du plus recent au plus ancien : ceux dont il est le sujet,
    /// ou qui portent son adresse longue (`details["ieee"]`).
    func evenements(de id: String) -> [Evenement] {
        Array(evenements.reversed().filter { $0.sujet?.id == id || $0.details["ieee"] == id }.prefix(5))
    }

    /// Lignes du journal d'un noeud (son adresse longue), de la plus recente a la plus ancienne, 5 au plus : ses
    /// evenements regroupes comme ceux de la fenetre du journal (`Regroupement.lignes`), ses changements de parent ou de
    /// chemin d'une meme heure en une seule ligne.
    func lignesJournal(de id: String) -> [LigneJournal] {
        let siens = evenements.filter { $0.sujet?.id == id || $0.details["ieee"] == id }
        return Array(Regroupement.lignes(siens).prefix(5))
    }

    /// Cle d'un noeud du graphe dans l'historique : son adresse longue, son id ; nil pour une cle provisoire.
    func cleHistorique(noeud id: String) -> String? { NoeudZigbee.cleConnue(id) ? id : nil }

    /// Noms de noeuds de l'historique, par adresse longue.
    func nomsHistorique(_ cles: Set<String>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: cles.map { ($0, nom($0)) })
    }

    /// Courbes d'un noeud du graphe sur une periode qui finit a `fin` ; nil sans cle.
    func courbes(noeud id: String, periode: PeriodeCourbes, fin: Date) -> CourbesNoeud? {
        cleHistorique(noeud: id).map { CourbesNoeud(cle: $0, releves: historique, periode: periode, fin: fin) }
    }
}
