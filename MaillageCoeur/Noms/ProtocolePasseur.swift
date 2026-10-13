import Foundation

/// Echange entre les apps (Maillage Thread, Maillage Zigbee) et le passeur Passeur Noms par la boucle locale du Mac
/// (TCP sur 127.0.0.1), sans dossier partage ni App Group (spec du demon, 12/10/2026, section 2) :
/// 1. l'app ecoute sur 127.0.0.1, sur un port choisi par le systeme, et tire un jeton a usage unique ;
/// 2. elle ouvre le passeur, sans l'activer, avec l'URL `maillage-passeur://<demande>?port=<port>&jeton=<jeton>`
///    (`Cible`) : une app du bac a sable ne peut pas passer d'arguments de lancement, macOS les retire ;
/// 3. `releve` (releve ponctuel) : le passeur se connecte, envoie le jeton sur une ligne, la longueur du JSON sur une
///    ligne, puis le JSON du releve, et ferme (`trame(jeton:json:)`, lu par `Lecture`) ;
/// 4. `abonner` : le passeur se connecte, envoie le jeton sur une ligne (`ligneJeton`), puis les deux cotes
///    echangent des messages (`MessagePasseur`), chacun en trame `<longueur>\n<JSON>` (`trame(_:)`, lu par
///    `LectureTrames` et `LectureFlux`) ; la connexion reste ouverte.
/// Ce fichier est identique a l'octet dans les deux depots, et compile aussi dans le passeur (`project.yml`) : il ne
/// depend que de Foundation et de `CodageJSON`.
public enum EnvoiPasseur {
    /// JSON lu au plus par l'app : 8 Mo (le releve du 30/09, 133 accessoires, en fait 32 Ko).
    public static let tailleMax = 8 * 1024 * 1024
    /// Jeton : autant d'octets aleatoires, en chiffres hexadecimaux (64).
    public static let octetsJeton = 32
    /// Schema d'URL du passeur : il le declare dans son Info.plist (`CFBundleURLTypes`, `project.yml`).
    public static let schema = "maillage-passeur"
    /// Second schema, declare par le nouveau demon seulement (l'ancien passeur, app iOS, ne l'a pas). Une app trouve le
    /// demon en demandant a LaunchServices quelle app ouvre ce schema (`NSWorkspace.urlForApplication(toOpen:)`) : sans
    /// lire aucun paquet (le bac a sable l'interdit). Il exclut seulement l'ancien passeur : des copies perimees du
    /// nouveau demon declarent aussi ce schema, et `outils/passeur.sh` desinscrit les doublons.
    public static let schemaProtocole = "maillage-passeur-1"
    /// Chiffres d'un jeton : hexadecimaux, en minuscules. `nouveauJeton()` les tire, `Cible(url:)`
    /// n'en accepte pas d'autres.
    private static let chiffresJeton = "0123456789abcdef"

    /// Ce que l'URL demande au passeur : un releve ponctuel, puis la connexion est fermee (`releve`), ou un
    /// abonnement, dont la connexion reste ouverte (`abonner`). C'est l'hote de l'URL.
    public enum Demande: String, Hashable, Sendable, CaseIterable {
        case releve
        case abonner
    }

    /// Ou le passeur se connecte : 127.0.0.1, au port et avec le jeton que donne l'URL que l'app ouvre avec lui. Pour
    /// `releve`, il envoie une seule trame (`<64 hexa>\n<longueur>\n<JSON>`) puis ferme ; pour `abonner`, il envoie le
    /// jeton sur une ligne, puis les deux cotes echangent des trames `<longueur>\n<JSON>`.
    /// Toute app du Mac, du bac a sable ou non, peut ouvrir cette URL (des arguments de lancement, seul un processus
    /// hors du bac a sable pouvait en passer) : le passeur lit alors Maison et ecrit a 127.0.0.1, au port que l'URL
    /// nomme. Rien ne sort du Mac, et l'app n'accepte que son propre jeton ; mais un processus local qui ecoute sur
    /// 127.0.0.1 peut ainsi recevoir le releve (noms, pieces, zones, fabricants, batteries) : le passeur ne peut pas
    /// reconnaitre l'app, faute de secret partage (ni App Group ni equipe commune).
    /// La lecture de l'URL est stricte (`init?(url:)`) : celui qui ouvre l'URL ne choisit que la demande (l'hote), le
    /// port et les 64 chiffres du jeton, rien d'autre.
    public struct Cible: Hashable, Sendable {
        public var port: UInt16
        public var jeton: String
        public var demande: Demande

        public init(port: UInt16, jeton: String, demande: Demande = .releve) {
            self.port = port
            self.jeton = jeton
            self.demande = demande
        }

        /// URL que l'app ouvre avec le passeur : `maillage-passeur://<demande>?port=<port>&jeton=<jeton>`.
        public var url: URL {
            var c = URLComponents()
            c.scheme = EnvoiPasseur.schema
            c.host = demande.rawValue
            c.queryItems = [URLQueryItem(name: "port", value: String(port)),
                            URLQueryItem(name: "jeton", value: jeton)]
            // Toujours une URL : schema et hote fixes, requete encodee par URLComponents.
            guard let url = c.url else { preconditionFailure("URL du passeur impossible a construire") }
            return url
        }

        /// Lue dans l'URL recue par le passeur ; nil si ce n'est pas la sienne (autre schema ou hote qui n'est pas une
        /// `Demande`, sans tenir compte de la casse). Lecture stricte : `URLComponents` decode le
        /// pourcent-encodage (`%0D%0A`, `%00` et `%20` arrivent en octets), et le passeur ecrit le
        /// jeton tel quel sur le port nomme. Le jeton est donc exactement `2 * octetsJeton` chiffres
        /// hexadecimaux minuscules, comme `nouveauJeton()` en tire ; le port, un entier de 1 a 65535
        /// en chiffres seuls (ni signe, ni espace, ni zero de tete). Tout le reste donne nil. Les
        /// autres parametres de la requete sont ignores ; un parametre repete ne compte que pour
        /// sa premiere valeur, lue et verifiee une seule fois.
        public init?(url: URL) {
            guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  c.scheme?.lowercased() == EnvoiPasseur.schema,
                  let demande = c.host.flatMap({ Demande(rawValue: $0.lowercased()) }) else { return nil }
            func valeur(_ nom: String) -> String? {
                c.queryItems?.first { $0.name == nom }?.value
            }
            guard let port = valeur("port").flatMap(Self.lirePort),
                  let jeton = valeur("jeton"), Self.estUnJeton(jeton) else { return nil }
            self.init(port: port, jeton: jeton, demande: demande)
        }

        /// Port ecrit en chiffres decimaux seuls (`Lecture.entier` : ni signe, ni espace), sans zero
        /// de tete : de 1 a 65535.
        private static func lirePort(_ texte: String) -> UInt16? {
            let chiffres = Array(texte.utf8)
            guard chiffres.first != 0x30, let n = EnvoiPasseur.Lecture.entier(chiffres) else { return nil }
            return UInt16(exactly: n)
        }

        /// Jeton de `2 * octetsJeton` chiffres hexadecimaux minuscules, lu octet par octet.
        private static func estUnJeton(_ texte: String) -> Bool {
            let permis = Set(EnvoiPasseur.chiffresJeton.utf8)
            return texte.utf8.count == 2 * EnvoiPasseur.octetsJeton && texte.utf8.allSatisfy { permis.contains($0) }
        }
    }

    /// Jeton neuf : `octetsJeton` octets du generateur aleatoire du systeme (cryptographique),
    /// en hexadecimal minuscule.
    public static func nouveauJeton() -> String {
        var generateur = SystemRandomNumberGenerator()
        let chiffres = Array(chiffresJeton)
        var jeton = ""
        for _ in 0..<octetsJeton {
            let o = UInt8.random(in: .min ... .max, using: &generateur)
            jeton.append(chiffres[Int(o >> 4)])
            jeton.append(chiffres[Int(o & 0x0F)])
        }
        return jeton
    }

    /// Trame envoyee par le passeur.
    public static func trame(jeton: String, json: Data) -> Data {
        Data("\(jeton)\n\(json.count)\n".utf8) + json
    }

    /// Lecture d'une trame par l'app, au fil des octets recus.
    public struct Lecture: Sendable {
        public enum Issue: Equatable, Sendable {
            /// Il faut d'autres octets.
            case incomplete
            /// Le JSON, de la longueur annoncee ; ce qui le suit est ignore.
            case json(Data)
            /// Premiere ligne autre que le jeton attendu, ou connexion fermee avant sa fin.
            case jetonFaux
            /// Longueur illisible, nulle ou au-dela de `tailleMax`, ou trame plus courte qu'annoncee.
            case longueurFausse
        }

        private enum Etape: Sendable {
            case jeton, longueur
            case json(Int)
            case finie(Issue)
        }

        private enum Ligne {
            case manque, tropLongue
            case ligne([UInt8])
        }

        /// Chiffres d'une longueur, au plus (`tailleMax` en a 7). Seize chiffres valent moins de
        /// 10^16, sous `Int.max` (19 chiffres en 64 bits) : le calcul de `entier` ne deborde pas.
        static let chiffresMax = 16

        private let attendu: [UInt8]
        private var tampon = Data()
        private var etape = Etape.jeton

        public init(jeton: String) {
            attendu = Array(jeton.utf8)
        }

        /// Ajoute des octets recus ; rend l'issue, `incomplete` tant qu'il en faut d'autres.
        /// Une fois connue, l'issue ne change plus.
        public mutating func ajouter(_ octets: Data) -> Issue {
            if case .finie(let issue) = etape { return issue }
            tampon.append(octets)
            while true {
                switch etape {
                case .finie(let issue):
                    return issue
                case .jeton:
                    switch prendreLigne(auPlus: attendu.count) {
                    case .manque: return .incomplete
                    case .tropLongue: return finir(.jetonFaux)
                    case .ligne(let l):
                        guard Self.egaux(l, attendu) else { return finir(.jetonFaux) }
                        etape = .longueur
                    }
                case .longueur:
                    switch prendreLigne(auPlus: Self.chiffresMax) {
                    case .manque: return .incomplete
                    case .tropLongue: return finir(.longueurFausse)
                    case .ligne(let l):
                        guard let n = Self.entier(l), n > 0, n <= EnvoiPasseur.tailleMax else {
                            return finir(.longueurFausse)
                        }
                        etape = .json(n)
                    }
                case .json(let n):
                    guard tampon.count >= n else { return .incomplete }
                    return finir(.json(Data(tampon.prefix(n))))
                }
            }
        }

        /// La connexion s'est fermee : une trame inachevee est fausse.
        public func fin() -> Issue {
            switch etape {
            case .finie(let issue): issue
            case .jeton: .jetonFaux
            case .longueur, .json: .longueurFausse
            }
        }

        /// Premiere ligne du tampon, sans sa fin, retiree du tampon : au plus `max` octets.
        private mutating func prendreLigne(auPlus max: Int) -> Ligne {
            guard let fin = tampon.firstIndex(of: 0x0A) else {
                return tampon.count > max ? .tropLongue : .manque
            }
            let ligne = Array(tampon[tampon.startIndex..<fin])
            tampon.removeSubrange(tampon.startIndex...fin)
            return ligne.count > max ? .tropLongue : .ligne(ligne)
        }

        private mutating func finir(_ issue: Issue) -> Issue {
            etape = .finie(issue)
            tampon = Data()
            return issue
        }

        /// Entier ecrit en chiffres decimaux seuls (ni signe ni espace).
        static func entier(_ l: [UInt8]) -> Int? {
            guard !l.isEmpty, l.count <= chiffresMax, l.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
            return l.reduce(0) { $0 * 10 + Int($1 - 0x30) }
        }

        /// Comparaison a temps constant : sa duree ne depend pas de la place du premier ecart.
        /// Jamais vraie face a un jeton attendu vide : il ne laisse rien passer.
        static func egaux(_ a: [UInt8], _ b: [UInt8]) -> Bool {
            guard !b.isEmpty else { return false }
            guard a.count == b.count else { return false }
            var ecart: UInt8 = 0
            for (x, y) in zip(a, b) { ecart |= x ^ y }
            return ecart == 0
        }
    }
}

/// Etat du passeur, envoye a chaque abonne a la connexion, puis a chaque changement.
public struct EtatPasseur: Hashable, Sendable {
    /// Acces a Maison (`HMHomeManager.authorizationStatus`).
    public enum Acces: String, Hashable, Sendable {
        case attente, autorise, refuse
    }

    /// Ouverture a la session du passeur (`SMAppService.Status`) : `enabled` -> `active`, `notRegistered` ->
    /// `inactive`, `requiresApproval` -> `aApprouver` (refusee, ou pas encore acceptee dans Reglages > General >
    /// Ouverture), `notFound` -> `indisponible`.
    public enum Ouverture: String, Hashable, Sendable {
        case active, inactive, aApprouver, indisponible
    }

    public var version: String
    public var acces: Acces
    public var ouvertureSession: Ouverture
    /// Expiration du profil de developpement du passeur ; nil s'il est illisible.
    public var profilExpire: Date?

    public init(version: String, acces: Acces, ouvertureSession: Ouverture, profilExpire: Date?) {
        self.version = version
        self.acces = acces
        self.ouvertureSession = ouvertureSession
        self.profilExpire = profilExpire
    }
}

/// Reponse du passeur a `identifier`.
public struct ReponseIdentifier: Hashable, Sendable {
    /// `erreur` : aucun accessoire de Maison n'a cet identifiant.
    public static let inconnu = "inconnu"
    /// `erreur` : l'accessoire ne sait pas s'identifier (`supportsIdentify` faux).
    public static let nonIdentifiable = "nonIdentifiable"

    /// Le numero de la demande, choisi par l'app.
    public var demande: Int
    public var ok: Bool
    /// nil si `ok` ; sinon `inconnu`, `nonIdentifiable`, ou le texte de l'erreur de HomeKit.
    public var erreur: String?

    public init(demande: Int, ok: Bool, erreur: String? = nil) {
        self.demande = demande
        self.ok = ok
        self.erreur = erreur
    }
}

/// Message de l'abonnement, dans un sens ou dans l'autre : un objet JSON `{"v":1,"t":"<type>", ...}`.
public enum MessagePasseur: Hashable, Sendable {
    // Du passeur vers l'app.
    case etat(EtatPasseur)
    /// `noms` : le JSON du releve, objet tel quel. Chaque app le lit dans son propre type (`NomsMaison` dans Maillage
    /// Thread, `ReleveMaison` dans Maillage Zigbee) : ce fichier, commun aux deux, n'en depend pas.
    case releve(Data)
    case identifie(ReponseIdentifier)
    // De l'app vers le passeur.
    case relire
    case identifier(demande: Int, accessoire: String)
    case ouvertureSession(actif: Bool)

    /// Version du format des messages (`v`).
    public static let version = 1

    /// Issue de la lecture d'un message.
    public enum Lu: Hashable, Sendable {
        case message(MessagePasseur)
        /// Type inconnu, ou type connu dont les champs ne se lisent pas : ignore, pour qu'une version suivante ne casse
        /// pas une ancienne. Son type, pour le journal.
        case ignore(String)
        /// Pas un objet JSON, ou sans type `t` texte : la trame est mal formee, la connexion se ferme.
        case illisible
    }

    /// Le `t` du message.
    public var type: String {
        switch self {
        case .etat: "etat"
        case .releve: "releve"
        case .identifie: "identifie"
        case .relire: "relire"
        case .identifier: "identifier"
        case .ouvertureSession: "ouvertureSession"
        }
    }

    /// Le JSON du message : cles triees, barres obliques non echappees ; `null` explicite pour un champ absent
    /// (`profilExpire`, `erreur`). Un releve qui n'est pas du JSON (jamais : il sort d'un encodeur) part en `null`.
    public func json() -> Data {
        var d: [String: Any] = ["v": Self.version, "t": type]
        switch self {
        case .etat(let e):
            d["version"] = e.version
            d["acces"] = e.acces.rawValue
            d["ouvertureSession"] = e.ouvertureSession.rawValue
            d["profilExpire"] = e.profilExpire.map { $0.formatted(CodageJSON.avecMillisecondes) } ?? NSNull()
        case .releve(let noms):
            d["noms"] = (try? JSONSerialization.jsonObject(with: noms)) ?? NSNull()
        case .identifie(let r):
            d["demande"] = r.demande
            d["ok"] = r.ok
            d["erreur"] = r.erreur ?? NSNull()
        case .relire:
            break
        case .identifier(let demande, let accessoire):
            d["demande"] = demande
            d["accessoire"] = accessoire
        case .ouvertureSession(let actif):
            d["actif"] = actif
        }
        // Que des valeurs de JSON (textes, nombres, booleens, null, objets lus par JSONSerialization).
        guard let json = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .withoutEscapingSlashes])
        else { preconditionFailure("message du passeur impossible a encoder") }
        return json
    }

    /// Lit un message.
    public static func lire(_ json: Data) -> Lu {
        guard let d = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let t = d["t"] as? String else { return .illisible }
        let m: MessagePasseur?
        switch t {
        case "etat":
            m = lireEtat(d).map { .etat($0) }
        case "releve":
            m = (d["noms"] as? [String: Any])
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
                .map { .releve($0) }
        case "identifie":
            if let demande = entier(d["demande"]), let ok = booleen(d["ok"]) {
                m = .identifie(ReponseIdentifier(demande: demande, ok: ok, erreur: d["erreur"] as? String))
            } else {
                m = nil
            }
        case "relire":
            m = .relire
        case "identifier":
            if let demande = entier(d["demande"]), let accessoire = d["accessoire"] as? String {
                m = .identifier(demande: demande, accessoire: accessoire)
            } else {
                m = nil
            }
        case "ouvertureSession":
            m = booleen(d["actif"]).map { .ouvertureSession(actif: $0) }
        default:
            m = nil
        }
        return m.map(Lu.message) ?? .ignore(t)
    }

    private static func lireEtat(_ d: [String: Any]) -> EtatPasseur? {
        guard let version = d["version"] as? String,
              let acces = (d["acces"] as? String).flatMap(EtatPasseur.Acces.init(rawValue:)),
              let ouverture = (d["ouvertureSession"] as? String).flatMap(EtatPasseur.Ouverture.init(rawValue:))
        else { return nil }
        let brut = d["profilExpire"]
        let profil: Date?
        if brut == nil || brut is NSNull {
            profil = nil
        } else if let texte = brut as? String,
                  let date = (try? CodageJSON.avecMillisecondes.parse(texte)) ?? (try? CodageJSON.sansMillisecondes.parse(texte)) {
            profil = date
        } else {
            return nil
        }
        return EtatPasseur(version: version, acces: acces, ouvertureSession: ouverture, profilExpire: profil)
    }

    /// Booleen JSON, pas un nombre : JSONSerialization rend les deux en NSNumber.
    private static func booleen(_ v: Any?) -> Bool? {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// Entier JSON : ni booleen, ni nombre a virgule.
    private static func entier(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: n.doubleValue)
    }
}

extension EnvoiPasseur {
    /// Premiere ligne d'une connexion d'abonnement, du passeur vers l'app : le jeton.
    public static func ligneJeton(_ jeton: String) -> Data {
        Data("\(jeton)\n".utf8)
    }

    /// Trame d'un message de l'abonnement : sa longueur en decimal sur une ligne, puis son JSON.
    public static func trame(_ m: MessagePasseur) -> Data {
        let json = m.json()
        return Data("\(json.count)\n".utf8) + json
    }

    /// Ce que rend une lecture de flux : les JSON des trames completes, dans l'ordre, et l'erreur qui a arrete la
    /// lecture (la connexion se ferme alors ; les trames rendues avec elle restent valables).
    public struct IssueFlux: Equatable, Sendable {
        public enum Erreur: Equatable, Sendable {
            /// Premiere ligne autre que le jeton attendu.
            case jetonFaux
            /// Longueur illisible, nulle ou au-dela de `tailleMax`.
            case trameFausse
        }

        public var trames: [Data]
        public var erreur: Erreur?

        public init(trames: [Data], erreur: Erreur?) {
            self.trames = trames
            self.erreur = erreur
        }
    }

    /// Lecture d'une suite de trames `<longueur>\n<JSON>` au fil des octets recus, sans jeton : le passeur lit ainsi ce
    /// que l'app lui envoie. Plusieurs trames peuvent arriver d'un coup, une trame en plusieurs fois. Apres une
    /// erreur, plus rien ne se lit.
    public struct LectureTrames: Sendable {
        private var tampon = Data()
        /// Longueur lue, JSON pas encore complet.
        private var attendue: Int?
        private var faussee = false

        public init() {}

        public mutating func ajouter(_ octets: Data) -> IssueFlux {
            guard !faussee else { return IssueFlux(trames: [], erreur: .trameFausse) }
            tampon.append(octets)
            var trames: [Data] = []
            while true {
                if let n = attendue {
                    guard tampon.count >= n else { break }
                    let debut = tampon.startIndex
                    trames.append(Data(tampon[debut..<debut + n]))
                    tampon.removeSubrange(debut..<debut + n)
                    attendue = nil
                } else {
                    guard let fin = tampon.firstIndex(of: 0x0A) else {
                        if tampon.count > Lecture.chiffresMax { return fausser(trames) }
                        break
                    }
                    let ligne = Array(tampon[tampon.startIndex..<fin])
                    tampon.removeSubrange(tampon.startIndex...fin)
                    guard let n = Lecture.entier(ligne), n > 0, n <= EnvoiPasseur.tailleMax else { return fausser(trames) }
                    attendue = n
                }
            }
            return IssueFlux(trames: trames, erreur: nil)
        }

        private mutating func fausser(_ trames: [Data]) -> IssueFlux {
            faussee = true
            tampon = Data()
            return IssueFlux(trames: trames, erreur: .trameFausse)
        }
    }

    /// Lecture d'une connexion d'abonnement par l'app : le jeton sur la premiere ligne (compare a temps constant),
    /// puis des trames (`LectureTrames`). Apres une erreur, plus rien ne se lit.
    public struct LectureFlux: Sendable {
        private let attendu: [UInt8]
        private var avantJeton = Data()
        private var trames = LectureTrames()
        private var erreur: IssueFlux.Erreur?
        /// Le jeton est arrive et c'est le bon.
        public private(set) var jetonAccepte = false

        public init(jeton: String) {
            attendu = Array(jeton.utf8)
        }

        public mutating func ajouter(_ octets: Data) -> IssueFlux {
            if let erreur { return IssueFlux(trames: [], erreur: erreur) }
            var reste = octets
            if !jetonAccepte {
                avantJeton.append(octets)
                guard let fin = avantJeton.firstIndex(of: 0x0A) else {
                    if avantJeton.count > attendu.count { return echouer(.jetonFaux) }
                    return IssueFlux(trames: [], erreur: nil)
                }
                guard Lecture.egaux(Array(avantJeton[avantJeton.startIndex..<fin]), attendu) else {
                    return echouer(.jetonFaux)
                }
                jetonAccepte = true
                reste = Data(avantJeton[avantJeton.index(after: fin)...])
                avantJeton = Data()
            }
            let issue = trames.ajouter(reste)
            if let e = issue.erreur { erreur = e }
            return issue
        }

        private mutating func echouer(_ e: IssueFlux.Erreur) -> IssueFlux {
            erreur = e
            avantJeton = Data()
            return IssueFlux(trames: [], erreur: e)
        }
    }
}
