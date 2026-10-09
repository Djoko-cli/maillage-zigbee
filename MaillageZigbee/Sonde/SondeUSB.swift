import Foundation
import MaillageCoeur

/// Lignes machine de la sonde et envoi des commandes : la liaison serie dans
/// l'app, un canal rejoue dans les tests.
protocol CanalSonde: Sendable {
    /// Lignes machine (JSON, sans RS ni LF) ; le flux finit quand le port se ferme.
    func ouvrir() throws -> AsyncStream<Data>
    func envoyer(_ ligne: String)
    func fermer()
}

/// Canal sur la liaison serie : le flux USB decoupe en lignes machine.
struct CanalSerie: CanalSonde {
    let liaison: LiaisonSerie

    func ouvrir() throws -> AsyncStream<Data> {
        let flux = try liaison.ouvrir()
        let (lignes, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        let lecture = Task {
            var decoupeur = DecoupeurLignes()
            for await e in flux {
                guard case .donnees(let d) = e else { break }
                for l in decoupeur.ajouter(d) { suite.yield(l) }
            }
            suite.finish()
        }
        suite.onTermination = { _ in lecture.cancel() }
        return lignes
    }

    func envoyer(_ ligne: String) { liaison.envoyer(Data(ligne.utf8)) }
    func fermer() { liaison.fermer() }
}

/// Attentes d'une commande sans id (`bonjour`, `etat`, `voisins`) : les reponses les servent
/// dans l'ordre. Chaque attente a son jeton : son echeance n'expire qu'elle, et plus rien une
/// fois qu'elle est servie (une reponse lente ne fait plus echouer la requete suivante).
private struct FileAttentes<Valeur: Sendable> {
    private var attentes: [(jeton: Int, suite: CheckedContinuation<Valeur?, Never>)] = []

    var estVide: Bool { attentes.isEmpty }

    mutating func ajouter(_ jeton: Int, _ suite: CheckedContinuation<Valeur?, Never>) {
        attentes.append((jeton, suite))
    }

    /// La premiere attente recoit `valeur` ; rien sans attente.
    mutating func servir(_ valeur: Valeur?) {
        guard !attentes.isEmpty else { return }
        attentes.removeFirst().suite.resume(returning: valeur)
    }

    /// Echeance de l'attente `jeton` : nil pour elle si elle attend encore. Rend son rang dans
    /// la file (0 : la premiere), nil si elle est deja servie.
    @discardableResult
    mutating func expirer(_ jeton: Int) -> Int? {
        guard let i = attentes.firstIndex(where: { $0.jeton == jeton }) else { return nil }
        attentes.remove(at: i).suite.resume(returning: nil)
        return i
    }

    /// Liaison fermee : toutes recoivent nil.
    mutating func liberer() {
        attentes.forEach { $0.suite.resume(returning: nil) }
        attentes = []
    }
}

/// Sonde branchee en USB : envoie les commandes et apparie les reponses. `bonjour`, `etat` et `voisins`, sans id, par
/// ordre ; `table` et `routes` par id **et** cible, une seule a la fois (la sonde repondrait `occupee`), leurs lignes
/// `suite` reunies jusqu'a la derniere. Chaque requete a sa propre echeance : 3 s pour les commandes locales, 125 s pour
/// une table (la sonde en borne une a 120 s). Les lignes `signal` ne font qu'avancer un compteur.
actor SondeUSB: InterlocuteurSonde {
    enum Erreur: Error, LocalizedError, Equatable {
        case fermee
        case sansReponse(String)
        /// La sonde refuse, pour une autre raison qu'`occupee` (la raison, telle que la sonde la donne).
        case refusee(String)
        /// La sonde n'a pas servi la commande (`occupee` : verrou de la pile Zigbee refuse, ou une table deja en
        /// cours) : elle le dit tout de suite, sans attendre l'echeance.
        case occupee(String)

        var errorDescription: String? {
            switch self {
            case .fermee: String(localized: "liaison avec la sonde fermée")
            case .sansReponse(let commande): String(localized: "la sonde ne répond pas à « \(commande) »")
            case .refusee(let raison): String(localized: "la sonde refuse : \(raison)")
            case .occupee(let commande): String(localized: "la sonde est occupée et n'a pas répondu à « \(commande) »")
            }
        }
    }

    /// Attente de `bonjour`, `etat` et `voisins` : 3 s en USB, qui ne perd rien.
    static let delaiCommandeUSB: Duration = .seconds(3)

    /// La requete reseau en cours (une seule a la fois) : son id, sa cible, ses lignes deja recues.
    private enum EnCours {
        case table(id: Int, cible: String, FusionLignes<EntreeTable>, CheckedContinuation<ReponseListe<EntreeTable>?, Never>)
        case routes(id: Int, cible: String, FusionLignes<EntreeRoute>, CheckedContinuation<ReponseListe<EntreeRoute>?, Never>)

        var id: Int {
            switch self {
            case .table(let id, _, _, _), .routes(let id, _, _, _): id
            }
        }

        /// Fin de la requete : un echec (`erreur`), ou nil (echeance, liaison fermee).
        func finir(_ erreur: String?) {
            switch self {
            case let .table(id, cible, _, k): k.resume(returning: erreur.map { .echec($0, id: id, cible: cible) })
            case let .routes(id, cible, _, k): k.resume(returning: erreur.map { .echec($0, id: id, cible: cible) })
            }
        }
    }

    private let canal: any CanalSonde
    nonisolated let delaiCommande: Duration
    nonisolated let delaiTable: Duration
    /// Jetons des attentes des commandes sans id (jamais envoyes a la sonde).
    private var prochainJeton = 1
    /// Id des requetes reseau : de 1 a chaque connexion (spec de la sonde, section 2).
    private var prochainId = 1
    /// `etat` : la reponse, ou le refus de la sonde (`occupee`).
    private var attenteEtat = FileAttentes<Result<EtatSonde, Erreur>>()
    private var attenteBonjour = FileAttentes<Bonjour>()
    private var attenteVoisins = FileAttentes<Result<[VoisinDeLaSonde], Erreur>>()
    private var fusionVoisins = FusionLignes<VoisinDeLaSonde>()
    private var enCours: EnCours?
    private var echeanceReseau: Task<Void, Never>?
    private var lecture: Task<Void, Never>?
    private(set) var fermee = false
    /// Dernier `bonjour` recu sans l'avoir demande : la sonde vient de (re)demarrer.
    private(set) var bonjourSpontane: Bonjour?
    /// Lignes `signal` recues, et celles qui disent le parent perdu (journal de diagnostic, jamais celui de
    /// l'utilisateur).
    private(set) var signaux = 0
    private(set) var pertesParent = 0

    init(canal: any CanalSonde, delaiCommande: Duration = SondeUSB.delaiCommandeUSB,
         delaiTable: Duration = ProtocoleSonde.echeanceTable) {
        self.canal = canal
        self.delaiCommande = delaiCommande
        self.delaiTable = delaiTable
    }

    /// Ouvre le canal et lit ses lignes ; `surFermeture` quand il se ferme.
    /// Une sonde fermee ne s'ouvre plus : fermee avant d'avoir demarre (connexion
    /// abandonnee), elle n'ouvre jamais le canal.
    func demarrer(surFermeture: @escaping @Sendable () -> Void) throws {
        guard !fermee else { throw Erreur.fermee }
        let lignes = try canal.ouvrir()
        lecture = Task {
            for await l in lignes { self.recevoir(l) }
            self.clore()
            surFermeture()
        }
    }

    /// Ferme le canal et attend la fin de la lecture, qui suit celle du flux :
    /// la liaison serie ne finit son flux qu'apres avoir ferme le port. Sans
    /// lecture (jamais demarree, ou ouverture en echec), la sonde est seulement
    /// marquee fermee.
    func fermer() async {
        guard let lecture else {
            clore()
            return
        }
        canal.fermer()
        await lecture.value
    }

    func bonjour() async throws -> Bonjour {
        guard !fermee else { throw Erreur.fermee }
        let jeton = nouveauJeton()
        let b = await withCheckedContinuation { c in
            attenteBonjour.ajouter(jeton, c)
            canal.envoyer(CommandeSonde.bonjour.ligne)
            Task {
                try? await Task.sleep(for: self.delaiCommande)
                self.attenteBonjour.expirer(jeton)
            }
        }
        guard let b else { throw fermee ? Erreur.fermee : Erreur.sansReponse("bonjour") }
        return b
    }

    func etat() async throws -> EtatSonde {
        guard !fermee else { throw Erreur.fermee }
        let jeton = nouveauJeton()
        let e = await withCheckedContinuation { c in
            attenteEtat.ajouter(jeton, c)
            canal.envoyer(CommandeSonde.etat.ligne)
            Task {
                try? await Task.sleep(for: self.delaiCommande)
                self.attenteEtat.expirer(jeton)
            }
        }
        guard let e else { throw fermee ? Erreur.fermee : Erreur.sansReponse("etat") }
        return try e.get()
    }

    func voisins() async throws -> [VoisinDeLaSonde] {
        guard !fermee else { throw Erreur.fermee }
        let jeton = nouveauJeton()
        let v = await withCheckedContinuation { c in
            attenteVoisins.ajouter(jeton, c)
            canal.envoyer(CommandeSonde.voisins.ligne)
            Task {
                try? await Task.sleep(for: self.delaiCommande)
                // Expiree sans reponse : ses lignes deja recues (sans la derniere) ne s'ajoutent pas a la suivante.
                if self.attenteVoisins.expirer(jeton) != nil { self.fusionVoisins = FusionLignes() }
            }
        }
        guard let v else { throw fermee ? Erreur.fermee : Erreur.sansReponse("voisins") }
        return try v.get()
    }

    /// La table des voisins de `cible` ; nil sans reponse dans `delaiTable`. Leve `occupee` si une requete reseau est
    /// deja en cours, `fermee` si la liaison l'est.
    func table(_ cible: UInt16) async throws -> ReponseListe<EntreeTable>? {
        try verifierLibre("table")
        let id = nouvelId()
        let c = ProtocoleSonde.texte(court: cible)
        let r = await withCheckedContinuation { k in
            enCours = .table(id: id, cible: c, FusionLignes(), k)
            canal.envoyer(CommandeSonde.table(cible: cible, id: id).ligne)
            armerEcheance(id)
        }
        if r == nil && fermee { throw Erreur.fermee }
        return r
    }

    /// La table de routage de `cible`, memes regles que `table`.
    func routes(_ cible: UInt16) async throws -> ReponseListe<EntreeRoute>? {
        try verifierLibre("routes")
        let id = nouvelId()
        let c = ProtocoleSonde.texte(court: cible)
        let r = await withCheckedContinuation { k in
            enCours = .routes(id: id, cible: c, FusionLignes(), k)
            canal.envoyer(CommandeSonde.routes(cible: cible, id: id).ligne)
            armerEcheance(id)
        }
        if r == nil && fermee { throw Erreur.fermee }
        return r
    }

    private func verifierLibre(_ commande: String) throws {
        guard !fermee else { throw Erreur.fermee }
        guard enCours == nil else { throw Erreur.occupee(commande) }
    }

    private func armerEcheance(_ id: Int) {
        echeanceReseau?.cancel()
        let delai = delaiTable
        echeanceReseau = Task {
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            self.finirReseau(id: id, erreur: nil)
        }
    }

    /// Finit la requete reseau `id` (si c'est encore elle) : un echec, ou nil.
    private func finirReseau(id: Int, erreur: String?) {
        guard let e = enCours, e.id == id else { return }
        enCours = nil
        echeanceReseau?.cancel()
        echeanceReseau = nil
        e.finir(erreur)
    }

    private func nouveauJeton() -> Int {
        defer { prochainJeton += 1 }
        return prochainJeton
    }

    private func nouvelId() -> Int {
        defer { prochainId += 1 }
        return prochainId
    }

    /// Erreur d'une commande sans id que la sonde n'a pas servie : `occupee` (verrou de la pile refuse), ou une autre
    /// raison.
    private static func refus(_ commande: String, _ erreur: String) -> Erreur {
        erreur == "occupee" ? .occupee(commande) : .refusee(erreur)
    }

    private func recevoir(_ ligne: Data) {
        switch MessageSonde.lire(ligne) {
        case .etat(let e)?:
            attenteEtat.servir(.success(e))
        case .refusee(commande: "etat", let erreur)?:
            attenteEtat.servir(.failure(Self.refus("etat", erreur)))
        case .voisins(let l)?:
            if let r = fusionVoisins.ajouter(l) { attenteVoisins.servir(.success(r.liste)) }
        case .refusee(commande: "voisins", let erreur)?:
            fusionVoisins = FusionLignes()
            attenteVoisins.servir(.failure(Self.refus("voisins", erreur)))
        case .table(let l)?:
            // Une ligne d'une autre requete (en retard, d'un autre id ou d'une autre cible) est ignoree.
            guard case .table(let id, let cible, var fusion, let k)? = enCours, l.id == id, l.cible == cible else { return }
            if let r = fusion.ajouter(l) {
                enCours = nil
                echeanceReseau?.cancel()
                echeanceReseau = nil
                k.resume(returning: r)
            } else {
                enCours = .table(id: id, cible: cible, fusion, k)
            }
        case .routes(let l)?:
            guard case .routes(let id, let cible, var fusion, let k)? = enCours, l.id == id, l.cible == cible else { return }
            if let r = fusion.ajouter(l) {
                enCours = nil
                echeanceReseau?.cancel()
                echeanceReseau = nil
                k.resume(returning: r)
            } else {
                enCours = .routes(id: id, cible: cible, fusion, k)
            }
        case .erreur(let e)?:
            // Erreur generale (`syntaxe`, `inconnue`, ligne trop longue) : elle repond a la requete reseau en cours,
            // sinon a la plus ancienne commande sans id qui attend.
            if let r = enCours {
                finirReseau(id: r.id, erreur: e)
            } else if !attenteEtat.estVide {
                attenteEtat.servir(.failure(Self.refus("etat", e)))
            } else {
                attenteVoisins.servir(.failure(Self.refus("voisins", e)))
            }
        case .signal(let s)?:
            signaux += 1
            if s.parentPerdu { pertesParent += 1 }
        case .bonjour(let b)?:
            if attenteBonjour.estVide {
                bonjourSpontane = b
                // La sonde a redemarre : la requete en cours ne finira pas.
                if let r = enCours { finirReseau(id: r.id, erreur: "redemarree") }
            } else {
                attenteBonjour.servir(b)
            }
        default:
            break
        }
    }

    /// Liaison fermee : toutes les attentes sont liberees.
    private func clore() {
        fermee = true
        attenteEtat.liberer()
        attenteBonjour.liberer()
        attenteVoisins.liberer()
        if let r = enCours { finirReseau(id: r.id, erreur: nil) }
    }
}
