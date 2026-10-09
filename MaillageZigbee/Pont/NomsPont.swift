import Foundation
import MaillageCoeur
import Observation
import Synchronization
import SystemConfiguration

/// Le pont retenu : son adresse, son identifiant (celui du TXT Bonjour, ou lu dans son certificat apres une saisie
/// manuelle), le code de son modele s'il est connu. Garde dans les preferences (`MemoirePont`) : ni la cle, ni rien
/// de secret.
struct PontRetenu: Codable, Hashable, Sendable {
    var adresse: String
    /// 16 hexa majuscules.
    var identifiant: String
    /// `modelid` du TXT Bonjour (« BSB002 »), puis le nom du produit du pont, une fois lu.
    var modele: String?
    /// Adresse saisie a la main.
    var manuel: Bool
}

/// Un pont vu par Bonjour (`_hue._tcp`) : son adresse et les champs `bridgeid` et `modelid` de son TXT.
struct PontDecouvert: Hashable, Sendable {
    var adresse: String
    var identifiant: String?
    var modele: String?
}

/// Ou le pont retenu est garde d'un lancement a l'autre : les preferences dans l'app, la memoire dans les tests.
protocol MemoirePont: Sendable {
    func lire() -> PontRetenu?
    func ecrire(_ p: PontRetenu?)
}

/// Les preferences de l'app (`UserDefaults`, cle `pont.hue`) : adresse, identifiant, modele ; jamais la cle.
struct MemoirePreferences: MemoirePont {
    static let cle = "pont.hue"

    func lire() -> PontRetenu? {
        UserDefaults.standard.data(forKey: Self.cle).flatMap { try? JSONDecoder().decode(PontRetenu.self, from: $0) }
    }

    func ecrire(_ p: PontRetenu?) {
        if let p, let d = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(d, forKey: Self.cle)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cle)
        }
    }
}

/// La memoire des tests.
final class MemoireVive: MemoirePont {
    private let pont: Mutex<PontRetenu?>

    init(_ p: PontRetenu? = nil) {
        pont = Mutex(p)
    }

    func lire() -> PontRetenu? { pont.withLock { $0 } }
    func ecrire(_ p: PontRetenu?) { pont.withLock { $0 = p } }
}

/// Ce dont le client du pont a besoin, injecte : reseau, trousseau, preferences, cache, horloge. Les tests donnent un
/// transport simule, un trousseau en memoire, une attente instantanee.
struct DependancesPont: Sendable {
    var transport: any TransportHue
    var trousseau: any TrousseauCles
    var memoire: any MemoirePont
    /// Le dernier releve du pont, pour un demarrage sans reseau (`noms-pont.json`) ; nil : aucun cache.
    var cache: URL?
    /// Une attente (`Task.sleep`), interrompue par l'annulation de la tache.
    var attendre: @Sendable (Duration) async throws -> Void
    var maintenant: @Sendable () -> Date
    /// Le nom du Mac, donne au pont a la liaison (il apparait dans l'app Hue).
    var nomMac: String

    /// Celles de l'app : URLSession verifie, trousseau du Mac, preferences, `Application Support`.
    static func systeme(cache: URL?) -> DependancesPont {
        DependancesPont(transport: TransportURLSession(), trousseau: TrousseauSysteme(), memoire: MemoirePreferences(),
                        cache: cache, attendre: { try await Task.sleep(for: $0) }, maintenant: { Date() },
                        nomMac: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac")
    }
}

/// Le pont Hue et les noms de la maison qu'il donne (spec de l'app, section 5) : trouve par Bonjour
/// (`DecouvertePont`) ou par son adresse saisie a la main, lie par l'appui sur son bouton (la cle va au trousseau),
/// lu en HTTPS verifie au lancement puis toutes les 5 minutes. Le dernier releve est garde sur disque, pour un
/// demarrage sans reseau.
///
/// Sans dependances (`init(noms:)`) : inerte, pour la demo et les tests des vues.
@MainActor
@Observable
final class NomsPont {
    enum Etat: Equatable, Sendable {
        /// Aucun pont : Bonjour n'en voit pas, et aucune adresse n'a ete saisie.
        case introuvable
        /// Un pont est la, sans cle : il reste a le lier.
        case trouve(ip: String, identifiant: String)
        /// Le pont a refuse la cle (l'app a ete retiree dans l'app Hue) : elle a ete retiree du trousseau, il faut
        /// relier le pont.
        case aLier
        /// Attente de l'appui sur le bouton du pont ; `reste` : secondes avant l'abandon.
        case liaisonEnCours(reste: Int)
        /// Lie : la cle est au trousseau, le pont est lu.
        case lie
        /// La derniere operation a echoue (reseau, certificat refuse, delai de liaison depasse...) ; la cle, s'il y en
        /// a une, est gardee.
        case erreur(String)
    }

    /// Duree de l'attente du bouton, et pas des demandes de liaison.
    nonisolated static let dureeLiaison = 60
    nonisolated static let pasLiaison = 2
    /// Relecture du pont.
    nonisolated static let periodeLecture: Duration = .seconds(5 * 60)

    private(set) var etat: Etat = .introuvable
    /// Le pont retenu (trouve ou saisi), lie ou non ; nil sans pont.
    private(set) var pont: PontRetenu?
    /// Le dernier releve du pont (lu, ou garde sur disque) ; nil tant qu'il n'y en a pas.
    private(set) var noms: NomsMaison?
    /// La cle du pont retenu est au trousseau.
    private(set) var lie = false
    /// Une lecture est en cours.
    private(set) var lectureEnCours = false
    /// Bonjour est refuse (Reglages Systeme › Confidentialite › Reseau local).
    var reseauLocalRefuse = false
    /// Appele a chaque nouveau releve (nil : le pont est oublie).
    @ObservationIgnored var surNoms: ((NomsMaison?) -> Void)?
    /// Appele apres `surNoms` a chaque lecture reussie du pont seulement (ni le cache relu au lancement, ni la demo) :
    /// l'etat de connexion des appareils, d'une lecture a l'autre.
    @ObservationIgnored var surLecture: ((NomsMaison) -> Void)?
    /// Une lecture a echoue faute de reseau : la decouverte peut resoudre de nouveau l'adresse du pont.
    @ObservationIgnored var surEchecReseau: (() -> Void)?
    @ObservationIgnored private let dependances: DependancesPont?
    /// Les ponts vus par Bonjour, du plus ancien au plus recent.
    @ObservationIgnored private var decouverts: [PontDecouvert] = []
    @ObservationIgnored private(set) var tacheLiaison: Task<Void, Never>?
    /// Numero de la liaison en cours, change par une nouvelle liaison et par `annulerTaches` (oubli du pont, autre
    /// adresse) : une liaison qui n'est plus la courante ne touche plus ni a l'etat, ni au trousseau, ni a
    /// `tacheLiaison`.
    @ObservationIgnored private var numeroLiaison = 0
    @ObservationIgnored private(set) var tacheLecture: Task<Void, Never>?
    @ObservationIgnored private var tachePeriodique: Task<Void, Never>?

    /// Inerte : les noms donnes (demo) ou aucun (tests des vues) ; ni reseau, ni trousseau, ni fichier.
    init(noms: NomsMaison? = nil) {
        self.noms = noms
        dependances = nil
    }

    /// Inerte aussi, mais montre lie a un pont invente (`pont`), avec les noms donnes : pour l'image de la page des
    /// Reglages en demo (`CapturesPieces`) ; ni reseau, ni trousseau, ni fichier.
    init(capture pont: PontRetenu, noms: NomsMaison) {
        self.pont = pont
        self.noms = noms
        lie = true
        etat = .lie
        dependances = nil
    }

    init(dependances: DependancesPont) {
        self.dependances = dependances
    }

    /// Les noms d'un releve (demo, tests) : gardes, et passes a `surNoms`.
    func integrer(_ n: NomsMaison) {
        noms = n
        surNoms?(n)
    }

    // MARK: - Demarrage, decouverte

    /// Lit le cache et le pont retenu ; lit le pont s'il est lie, puis toutes les 5 minutes.
    func demarrer() {
        guard let d = dependances else { return }
        pont = d.memoire.lire()
        if let p = pont, let cache = d.cache, let n = try? NomsMaison.lire(Data(contentsOf: cache)),
           n.domicile?.uppercased() == p.identifiant {
            integrer(n)
        }
        reprendre()
    }

    /// L'etat du pont retenu : lie (et lu) si sa cle est au trousseau, trouve sinon ; introuvable sans pont (un pont
    /// deja vu par Bonjour est alors retenu).
    private func reprendre() {
        guard let d = dependances else { return }
        guard let p = pont else {
            etat = .introuvable
            lie = false
            if let vu = decouverts.last(where: { $0.identifiant != nil }) { pontDecouvert(vu) }
            return
        }
        lie = (try? d.trousseau.lire(identifiant: p.identifiant)) != nil
        if lie {
            etat = .lie
            relire()
            lancerRelectures()
        } else {
            etat = .trouve(ip: p.adresse, identifiant: p.identifiant)
        }
    }

    /// Un pont vu par Bonjour. Le pont retenu, s'il change d'adresse, la prend ; sans pont retenu, le premier pont vu
    /// (avec un identifiant) est retenu. Un autre pont que celui retenu est ignore.
    func pontDecouvert(_ vu: PontDecouvert) {
        guard dependances != nil else { return }
        let id = vu.identifiant.flatMap(CertificatPont.identifiant)
        decouverts.removeAll { $0.adresse == vu.adresse || ($0.identifiant.flatMap(CertificatPont.identifiant) == id && id != nil) }
        decouverts.append(PontDecouvert(adresse: vu.adresse, identifiant: id, modele: vu.modele))
        guard let id else { return }
        if var p = pont {
            guard p.identifiant == id, p.adresse != vu.adresse || (p.modele == nil && vu.modele != nil) else { return }
            let nouvelleAdresse = p.adresse != vu.adresse
            p.adresse = vu.adresse
            p.modele = p.modele ?? vu.modele
            p.manuel = p.manuel && !nouvelleAdresse
            retenir(p)
            if case .trouve = etat { etat = .trouve(ip: p.adresse, identifiant: p.identifiant) }
            if lie && nouvelleAdresse { relire() }
            return
        }
        retenir(PontRetenu(adresse: vu.adresse, identifiant: id, modele: vu.modele, manuel: false))
        reprendre()
    }

    /// Une adresse saisie a la main (repli si Bonjour ne trouve rien) : un premier contact lit l'identifiant du pont
    /// dans son certificat, la chaine validee ; il sera confirme par l'API apres la liaison, puis exige. L'adresse du
    /// pont deja retenu se change ainsi ; un autre pont ne remplace pas un pont lie (l'oublier d'abord).
    func utiliserAdresse(_ texte: String) async {
        // Pendant une liaison, le pont ne change pas (la cle rendue irait a l'autre) : « Annuler » d'abord.
        guard let d = dependances, !liaisonEnCours else { return }
        let adresse = texte.trimmingCharacters(in: .whitespaces)
        guard TransportURLSession.url(adresse: adresse, chemin: "/") != nil else {
            etat = .erreur(String(localized: "Adresse invalide : \(adresse)"))
            return
        }
        let id: String
        do {
            id = try await PontHue(transport: d.transport, adresse: adresse, attendu: nil).sonder()
        } catch {
            etat = .erreur(Self.message(error))
            return
        }
        if let p = pont, p.identifiant != id, lie {
            etat = .erreur(String(localized: "Un autre pont (\(p.identifiant)) est déjà lié : oubliez-le d'abord."))
            return
        }
        let modele = pont?.identifiant == id ? pont?.modele : nil
        annulerTaches()
        retenir(PontRetenu(adresse: adresse, identifiant: id, modele: modele, manuel: true))
        reprendre()
    }

    // MARK: - Liaison

    /// Une liaison attend l'appui sur le bouton du pont.
    var liaisonEnCours: Bool {
        if case .liaisonEnCours = etat { true } else { false }
    }

    /// Lance la liaison : une demande toutes les 2 s pendant 60 s, le temps d'appuyer sur le bouton du pont. La cle
    /// rendue n'est gardee qu'apres une lecture du pont avec elle, qui confirme son identifiant.
    @discardableResult
    func lier() -> Task<Void, Never>? {
        guard dependances != nil, pont != nil, tacheLiaison == nil else { return nil }
        numeroLiaison += 1
        let n = numeroLiaison
        let t = Task { [weak self] in
            await self?.boucleLiaison(n)
            if let self, self.numeroLiaison == n { self.tacheLiaison = nil }
        }
        tacheLiaison = t
        return t
    }

    /// Arrete l'attente du bouton.
    func annulerLiaison() {
        tacheLiaison?.cancel()
    }

    /// L'attente du bouton, liaison numero `n`. Apres chaque attente, elle ne touche plus a rien si elle n'est plus la
    /// liaison en cours (`numeroLiaison` change avec une autre liaison, l'oubli du pont ou une autre adresse) ou si un
    /// autre pont est retenu ; annulee (« Annuler »), elle revient a « trouve ».
    private func boucleLiaison(_ n: Int) async {
        guard let d = dependances, let p = pont else { return }
        func courante() -> Bool { numeroLiaison == n && pont?.identifiant == p.identifiant }
        let client = PontHue(transport: d.transport, adresse: p.adresse, attendu: p.identifiant)
        var derniereErreur: String?
        // Le compte a rebours descend de 2 s par demande, et l'horloge le borne : un pont lent a repondre (jusqu'a 8 s
        // par demande) ne fait pas durer l'attente au-dela de 60 s (relecture de securite, M10).
        let limite = d.maintenant().addingTimeInterval(TimeInterval(Self.dureeLiaison))
        var reste = Self.dureeLiaison
        while reste > 0 {
            reste = min(reste, Int(limite.timeIntervalSince(d.maintenant()).rounded(.up)))
            guard reste > 0 else { break }
            etat = .liaisonEnCours(reste: reste)
            do {
                let reponse = try await client.demanderCle(nomMac: d.nomMac)
                guard courante() else { return }
                if Task.isCancelled {
                    etat = .trouve(ip: p.adresse, identifiant: p.identifiant)
                    return
                }
                switch reponse {
                case .cle(let cle):
                    await confirmer(cle: cle, client: client, liaison: n)
                    return
                case .boutonNonAppuye:
                    break
                case .erreur(_, let description):
                    etat = .erreur(String(localized: "Liaison refusée par le pont : \(description)"))
                    return
                }
            } catch {
                guard courante() else { return }
                // Un certificat refuse arrete tout ; une coupure du reseau peut passer : on continue d'attendre.
                if case .transport(.certificat) = error {
                    etat = .erreur(Self.message(error))
                    return
                }
                derniereErreur = Self.message(error)
            }
            let annulee: Bool
            do {
                try await d.attendre(.seconds(Self.pasLiaison))
                annulee = Task.isCancelled
            } catch {
                annulee = true
            }
            guard courante() else { return }
            if annulee {
                etat = .trouve(ip: p.adresse, identifiant: p.identifiant)
                return
            }
            reste -= Self.pasLiaison
        }
        etat = .erreur(derniereErreur.map { String(localized: "Le bouton du pont n'a pas été appuyé dans les 60 secondes (\($0)).") }
            ?? String(localized: "Le bouton du pont n'a pas été appuyé dans les 60 secondes."))
    }

    /// La cle rendue : lue une fois avec elle (l'identifiant de l'API doit etre celui attendu), puis rangee sous
    /// l'identifiant du pont qui l'a donnee (`client.attendu`). Si la liaison a ete annulee pendant cette lecture, ou si
    /// elle n'est plus la liaison en cours, ou qu'un autre pont a ete retenu entre-temps, la cle n'est pas gardee.
    private func confirmer(cle: String, client: PontHue, liaison n: Int) async {
        guard let d = dependances, let attendu = client.attendu else { return }
        func courante() -> Bool { numeroLiaison == n && pont?.identifiant == attendu }
        guard courante() else { return }
        let lecture: LectureHue
        do {
            lecture = try await client.lire(cle: cle)
        } catch {
            guard courante() else { return }
            etat = .erreur(Self.message(error))
            return
        }
        guard courante(), let p = pont else { return }
        if Task.isCancelled {
            etat = .trouve(ip: p.adresse, identifiant: p.identifiant)
            return
        }
        do {
            try d.trousseau.ranger(identifiant: attendu, cle: cle)
        } catch {
            etat = .erreur(error.localizedDescription)
            return
        }
        lie = true
        appliquer(lecture)
        lancerRelectures()
    }

    // MARK: - Lecture

    /// Une lecture du pont, tout de suite (au lancement, apres un changement d'adresse) ; rien si une lecture est en
    /// cours.
    @discardableResult
    func relire() -> Task<Void, Never>? {
        guard dependances != nil, lie, !lectureEnCours else { return nil }
        let t = Task { [weak self] () -> Void in await self?.lireUneFois() }
        tacheLecture = t
        return t
    }

    /// Relit le pont toutes les 5 minutes, tant qu'il est lie.
    private func lancerRelectures() {
        tachePeriodique?.cancel()
        guard let d = dependances else { return }
        tachePeriodique = Task { [weak self] in
            while true {
                do {
                    try await d.attendre(Self.periodeLecture)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.lie else { return }
                await self.lireUneFois()
            }
        }
    }

    private func lireUneFois() async {
        guard let d = dependances, let p = pont, lie, !lectureEnCours else { return }
        lectureEnCours = true
        defer { lectureEnCours = false }
        let cle: String
        do {
            cle = try d.trousseau.lire(identifiant: p.identifiant)
        } catch .absente {
            lie = false
            etat = .aLier
            return
        } catch {
            etat = .erreur(error.localizedDescription)
            return
        }
        do {
            let lecture = try await PontHue(transport: d.transport, adresse: p.adresse, attendu: p.identifiant).lire(cle: cle)
            guard pont?.identifiant == p.identifiant, lie else { return }
            appliquer(lecture)
        } catch .cleRefusee {
            // Une liaison faite pendant la lecture a range une autre cle : seule la cle refusee sort du trousseau.
            guard pont?.identifiant == p.identifiant, (try? d.trousseau.lire(identifiant: p.identifiant)) == cle else {
                return
            }
            try? d.trousseau.oublier(identifiant: p.identifiant)
            lie = false
            tachePeriodique?.cancel()
            etat = .aLier
        } catch {
            etat = .erreur(Self.message(error))
            // Faute de reseau, ou un certificat refuse a l'adresse retenue (le pont a pu changer d'adresse, et une autre
            // machine prendre l'ancienne) : la decouverte resout de nouveau le pont.
            switch error {
            case .transport(.reseau), .transport(.certificat): surEchecReseau?()
            default: break
            }
        }
    }

    /// Une lecture reussie : les noms (gardes sur disque), le nom du modele du pont, l'etat lie.
    private func appliquer(_ lecture: LectureHue) {
        guard let d = dependances, var p = pont else { return }
        let n = lecture.noms(date: d.maintenant())
        if let produit = lecture.appareilDuPont?.produit, p.modele != produit {
            p.modele = produit
            retenir(p)
        }
        etat = .lie
        integrer(n)
        surLecture?(n)
        if let cache = d.cache, let donnees = try? n.donnees() {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try donnees.write(to: cache, options: .atomic)
            } catch {
                Surveillance.journalMac.error("noms du pont non gardes : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Oubli

    /// « Oublier le pont » : la cle sort du trousseau, le pont des preferences, ses noms du disque. Un pont encore vu
    /// par Bonjour est aussitot retenu de nouveau, a lier.
    func oublier() {
        guard let d = dependances else { return }
        annulerTaches()
        if let p = pont { try? d.trousseau.oublier(identifiant: p.identifiant) }
        retenir(nil)
        lie = false
        if let cache = d.cache { try? FileManager.default.removeItem(at: cache) }
        noms = nil
        surNoms?(nil)
        reprendre()
    }

    /// Arrete la liaison et les lectures (fin des tests).
    func arreter() {
        annulerTaches()
    }

    private func annulerTaches() {
        tacheLiaison?.cancel()
        tacheLiaison = nil
        numeroLiaison += 1
        tacheLecture?.cancel()
        tacheLecture = nil
        tachePeriodique?.cancel()
        tachePeriodique = nil
    }

    private func retenir(_ p: PontRetenu?) {
        pont = p
        dependances?.memoire.ecrire(p)
    }

    // MARK: - Messages

    static func message(_ e: PontHue.Erreur) -> String {
        switch e {
        case .transport(.certificat(let v)): message(v)
        case .transport(.reseau(let d)): String(localized: "Pont injoignable : \(d)")
        case .cleRefusee: String(localized: "Le pont a refusé la clé : liez-le de nouveau.")
        case .http(let code, _): String(localized: "Réponse inattendue du pont (HTTP \(code)).")
        case .illisible(let chemin): String(localized: "Réponse illisible du pont (\(chemin)).")
        case .autrePont(let vu): String(localized: "L'API répond pour un autre pont (\(vu)).")
        case .sansCertificat: String(localized: "Le pont n'a pas présenté de certificat.")
        }
    }

    static func message(_ v: VerdictCertificat) -> String {
        switch v {
        case .accepte: ""
        case .nonSigne: String(localized: "Certificat refusé : il n'est pas signé par Signify. Ce n'est pas un pont Hue, ou il est trop ancien.")
        case .autoSigne: String(localized: "Pont trop ancien : son certificat est auto-signé, ce que l'app ne prend pas en charge.")
        case .autrePont(let vu): String(localized: "Ce n'est pas le pont attendu (certificat du pont \(vu)).")
        case .sansIdentifiant: String(localized: "Certificat refusé : il ne porte pas d'identifiant de pont.")
        case .pasUnServeur: String(localized: "Certificat refusé : ce n'est pas celui d'un serveur de pont.")
        }
    }
}
