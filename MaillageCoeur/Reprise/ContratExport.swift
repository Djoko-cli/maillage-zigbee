import CryptoKit
import Foundation

/// Contrat de l'export de reprise entre Maillage Thread, Maillage Zigbee et Maillage IoT (spec 4.1, 6.8). Les deux
/// anciennes apps ECRIVENT un dossier d'export, Maillage IoT le LIT : ce fichier est le seul endroit qui dit comment.
/// Il est identique a l'octet dans les trois depots (`outils/verifier-contrats.sh` le compare par `cmp`) : il ne depend
/// que de Foundation et de CryptoKit, aucun autre fichier du coeur, pour se compiler seul dans chaque ancienne app.
///
/// Le dossier d'export contient, a plat :
/// - `manifeste.json` (`Manifeste`) : format 1, identifiant d'export, app source et sa version, date, la liste de
///   TOUS les autres fichiers du dossier (taille, SHA-256), `reglages.json` compris, et la liste des fichiers vus dans
///   `Application Support/<app>/` mais non copies (`fichiersNonRepris`, avec leur raison). Jamais `manifeste.json`
///   lui-meme dans ses listes ;
/// - `reglages.json` (`Reglages`) : les reglages repris (UserDefaults), valeurs typees, sous leurs cles d'origine, et
///   les cles du domaine de l'app non reprises (`nonRepris`, nom et raison, jamais la valeur) ;
/// - une copie des fichiers de `Application Support/<app>/` (`fichiersConnus(de:)`), sous le meme chemin relatif
///   (`Journal/journal-AAAA-MM.jsonl`), sans changement de contenu. Aucun secret du trousseau n'y figure.
/// Rien n'est perdu en silence : ce que l'export ne reprend pas est cite, pour que l'import le dise au resume.
/// Les fichiers que macOS pose de lui-meme sont toleres, a n'importe quelle profondeur, sans etre listes ni lus : le
/// `.DS_Store` du Finder et les compagnons AppleDouble `._<nom>` d'une copie sur cle FAT ou exFAT (`estFichierDeSysteme`).
///
/// Ecrire (dans chaque ancienne app) : `classerFichiers` partage les fichiers vus, `reglagesPersistants` lit les
/// reglages ; chaque fichier se decrit sur sa COPIE, dans le dossier d'export, jamais sur l'original que l'app continue
/// d'ecrire (`Fichier.decrire`, un seul passage) ; puis `verifierDossier` relit l'export avant de dire "Export reussi".
/// Lire (Maillage IoT) : `verifierDossier` fait toute la validation ; l'import ne fait que traduire ses erreurs.
///
/// Les deux ecritures (`ecrire`) et les deux lectures (`lireManifeste`, `lireReglages`) partagent les memes reglages
/// d'encodage (`encodeur()`, `decodeur()`) : cles triees, dates ISO 8601 a la seconde, sans echappement des barres.
/// Un format ou une app inconnus sont refuses avec une erreur typee (`Erreur`), jamais lus au mieux. En revanche la
/// lecture est tolerante aux champs ajoutes (cles inconnues ignorees, la premiere cle JSON en double l'emporte) : une
/// version future du format 1 peut en ajouter sans casser les lecteurs ; un champ obligatoire absent est refuse.
public enum ContratExport {
    /// Version du format du manifeste et de `reglages.json`. Un autre nombre est refuse (`Erreur.formatInconnu`).
    public static let formatCourant = 1
    /// Nom du manifeste, a la racine du dossier d'export. Reserve : aucun fichier repris ne le porte.
    public static let nomManifeste = "manifeste.json"
    /// Nom du fichier des reglages, a la racine du dossier d'export. Reserve : il est ecrit par l'export, jamais copie
    /// d'un dossier de l'app. Il est liste dans le manifeste, comme les autres fichiers.
    public static let nomReglages = "reglages.json"

    // MARK: Erreurs

    /// Ce qui fait refuser un manifeste ou un fichier de reglages, ou un chemin.
    public enum Erreur: Error, Equatable, Sendable {
        /// Le champ `format` est un entier autre que `formatCourant`.
        case formatInconnu(Int)
        /// L'app source n'est pas l'une des valeurs brutes de `AppSource`.
        case appInconnue(String)
        /// JSON invalide, champ manquant ou d'un mauvais type : la cause en texte court, avec le nom du champ ou le
        /// chemin (`fichiers[0].taille`), jamais une valeur lue (`JSON invalide`, `champ manquant : versionApp`,
        /// `type inattendu : format`, `valeur invalide : identifiant`).
        case illisible(String)
        /// Chemin absolu, avec `..` ou `.`, vide, avec un caractere de controle, ou trop long (`verifierChemin`).
        case cheminInvalide(String)
        /// Un lien symbolique est sur le chemin (`resoudre`) : dans un export, il n'a pas sa place.
        case lienSymbolique(String)
        /// Empreinte qui n'est pas 64 chiffres hexadecimaux minuscules (le chemin du fichier).
        case empreinteInvalide(String)
        /// Taille negative (le chemin du fichier).
        case tailleInvalide(String)
        /// Deux fichiers du manifeste portent le meme chemin, a la casse et a la normalisation Unicode pres (le
        /// systeme de fichiers du Mac les confondrait).
        case cheminEnDouble(String)
        /// Le manifeste liste `manifeste.json` (a la casse pres).
        case nomReserve(String)
        /// Un reglage a un type que ce contrat ne connait pas : jamais ignore en silence.
        case valeurInconnue(cle: String, type: String)
        /// Cle de reglage vide.
        case cleInvalide
        /// Une cle est a la fois dans `valeurs` et dans `nonRepris` (la cle).
        case cleEnDouble(String)
        // Verification d'un dossier d'export (`verifierDossier`), une cause par cas :
        /// Pas de `manifeste.json` dans le dossier (ou pas de dossier).
        case manifesteAbsent
        /// Le manifeste ne liste pas `reglages.json`.
        case reglagesAbsents
        /// Un fichier liste au manifeste n'est pas dans le dossier (le chemin).
        case fichierManquant(String)
        /// Un fichier du dossier n'est pas liste au manifeste (le chemin ; `manifeste.json`, `.DS_Store` et les fichiers
        /// AppleDouble `._*` exceptes : `estFichierDeSysteme`).
        case fichierEnTrop(String)
        /// Un fichier liste n'est ni un fichier connu de l'app (`fichiersConnus`) ni `reglages.json` (le chemin).
        case fichierInconnu(String)
        /// La taille d'un fichier liste n'est pas celle du fichier du dossier (le chemin).
        case tailleFausse(String)
        /// L'empreinte d'un fichier liste n'est pas celle du fichier du dossier (le chemin).
        case empreinteFausse(String)
        /// L'app de `reglages.json` n'est pas celle du manifeste.
        case appDifferente
    }

    // MARK: App source

    /// L'ancienne app qui a ecrit l'export. Les valeurs brutes sont celles du manifeste : elles ne changent jamais ; ce
    /// sont aussi les cles de protocole de Maillage IoT (`thread`, `zigbee`).
    public enum AppSource: String, Sendable, CaseIterable, Codable {
        case maillageThread = "thread"
        case maillageZigbee = "zigbee"

        public init(from decoder: any Decoder) throws {
            let brut = try decoder.singleValueContainer().decode(String.self)
            guard let app = AppSource(rawValue: brut) else { throw Erreur.appInconnue(brut) }
            self = app
        }

        /// Identifiant de bundle de l'ancienne app (`project.yml`) : le domaine de ses UserDefaults, et ce qui sert a
        /// savoir si elle tourne encore. Constante du contrat, jamais ecrite dans un export.
        public var identifiantBundle: String {
            switch self {
            case .maillageThread: "fr.djoko.maillage"
            case .maillageZigbee: "fr.djoko.maillage.zigbee"
            }
        }

        /// Nom affiche de l'ancienne app ("Quitter Maillage Thread").
        public var nomApp: String {
            switch self {
            case .maillageThread: "Maillage Thread"
            case .maillageZigbee: "Maillage Zigbee"
            }
        }

        /// Nom du dossier de l'app sous `Application Support` (`Surveillance.swift` de chaque ancienne app).
        public var dossierDonnees: String {
            switch self {
            case .maillageThread: "Maillage Thread"
            case .maillageZigbee: "Maillage Zigbee"
            }
        }
    }

    // MARK: Encodage commun a l'ecriture et a la lecture

    /// L'encodeur de l'export : cles triees, dates ISO 8601 (`2026-10-17T12:00:00Z`), barres non echappees, mise en page
    /// lisible. Deux ecritures du meme contenu donnent les memes octets.
    public static func encodeur() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Le decodeur de l'export : dates ISO 8601, comme `encodeur()`.
    public static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Manifeste

    /// Un fichier du dossier d'export.
    public struct Fichier: Codable, Equatable, Hashable, Sendable {
        /// Chemin relatif au dossier d'export, avec des `/` (`Journal/journal-2026-10.jsonl`).
        public let chemin: String
        /// Taille en octets.
        public let taille: Int64
        /// SHA-256 du contenu : 64 chiffres hexadecimaux minuscules.
        public let sha256: String

        public init(chemin: String, taille: Int64, sha256: String) {
            self.chemin = chemin
            self.taille = taille
            self.sha256 = sha256
        }

        private enum CodingKeys: String, CodingKey { case chemin, taille, sha256 }

        /// Lecture stricte : chemin valide, taille positive ou nulle, empreinte bien formee.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chemin = try c.decode(String.self, forKey: .chemin)
            taille = try c.decode(Int64.self, forKey: .taille)
            sha256 = try c.decode(String.self, forKey: .sha256)
            try ContratExport.verifier(self)
        }

        /// Le fichier `chemin` du dossier : sa taille et son empreinte, lues sur le disque en UN seul passage
        /// (`empreinte(fichier:)` : la taille est celle des octets hachés). Refuse un chemin invalide, un lien
        /// symbolique, un fichier absent ou qui n'est pas un fichier ordinaire.
        ///
        /// Regle d'export : on decrit la COPIE, dans le dossier d'export, jamais l'original que l'ancienne app continue
        /// d'ecrire. Meme si la copie bouge encore, la taille et l'empreinte portent sur les memes octets : l'import
        /// ne verra pas d'incoherence sans cause.
        public static func decrire(chemin: String, dans dossier: URL) throws -> Fichier {
            let url = try ContratExport.resoudre(chemin, dans: dossier)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw Erreur.cheminInvalide(chemin)
            }
            let (taille, sha256) = try ContratExport.empreinte(fichier: url)
            return Fichier(chemin: chemin, taille: taille, sha256: sha256)
        }
    }

    /// Pourquoi un fichier ou un reglage n'est pas repris.
    public enum RaisonNonRepris: String, Codable, Sendable, CaseIterable {
        /// Ni connu de l'app (`fichiersConnus`, `reglagesConnus`) ni reserve au contrat : Sparkle, fenetres, onglet des
        /// reglages, ancien dossier des noms, ou tout ce qu'une version future aurait ajoute.
        case horsContrat
        /// Fichier que l'export ne copie jamais (`estExcluDeLExport` : `.DS_Store`, `._*`, `*.illisible-*.json`).
        case exclu
        /// Reglage connu mais d'un autre type que celui de l'inventaire (un `1` entier pour un booleen) : cite, jamais
        /// converti ni perdu en silence. Ne s'applique qu'aux reglages.
        case typeInattendu
        /// Reglage connu mais sans sens apres coup (la fenetre glissante de 10 minutes du budget de la tournee,
        /// `transitoires(de:)`) : cite, sans valeur, quel que soit son type. Ne s'applique qu'aux reglages.
        case transitoire
    }

    /// Un fichier vu dans `Application Support/<app>/` et non copie dans l'export, avec la raison (`horsContrat` ou
    /// `exclu`). Le nom seulement, jamais le contenu.
    public struct FichierNonRepris: Codable, Equatable, Hashable, Sendable {
        public let chemin: String
        public let raison: RaisonNonRepris

        public init(chemin: String, raison: RaisonNonRepris) {
            self.chemin = chemin
            self.raison = raison
        }
    }

    /// Le manifeste (`manifeste.json`), version 1.
    public struct Manifeste: Codable, Equatable, Sendable {
        /// Toujours `formatCourant` : un autre nombre est refuse a la lecture.
        public let format: Int
        /// Identifiant unique de cet export : Maillage IoT le garde (`imports.json`) pour ne pas reimporter le meme.
        public let identifiant: UUID
        /// L'ancienne app qui a ecrit l'export.
        public let app: AppSource
        /// Version de l'ancienne app (`1.4.0`), en texte libre.
        public let versionApp: String
        /// Date de l'export. Ecrite a la seconde (les fractions sont retirees a la construction : ce qui s'ecrit se
        /// relit egal) ; la lecture, elle, tolere une date a fractions.
        public let date: Date
        /// Tous les fichiers du dossier sauf le manifeste, `reglages.json` compris, dans l'ordre de l'ecriture.
        public let fichiers: [Fichier]
        /// Les fichiers vus dans `Application Support/<app>/` et non copies, tries par chemin (`classerFichiers`) :
        /// l'import les cite au resume. Obligatoire (liste vide s'il n'y en a pas).
        public let fichiersNonRepris: [FichierNonRepris]

        public init(identifiant: UUID, app: AppSource, versionApp: String, date: Date, fichiers: [Fichier],
                    fichiersNonRepris: [FichierNonRepris]) {
            self.format = ContratExport.formatCourant
            self.identifiant = identifiant
            self.app = app
            self.versionApp = versionApp
            self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
            self.fichiers = fichiers
            self.fichiersNonRepris = fichiersNonRepris.sorted { $0.chemin < $1.chemin }
        }

        private enum CodingKeys: String, CodingKey {
            case format, identifiant, app, versionApp, date, fichiers, fichiersNonRepris
        }

        /// Lecture stricte : format reconnu d'abord (un manifeste d'un autre format peut avoir une autre forme), puis
        /// app, puis chaque fichier (`ContratExport.verifier(_:)`), sans chemin en double ni nom reserve, puis les
        /// fichiers non repris (chemins valides, sans doublon entre eux ni avec les fichiers repris).
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let format = try c.decode(Int.self, forKey: .format)
            guard format == ContratExport.formatCourant else { throw Erreur.formatInconnu(format) }
            let app = try c.decode(AppSource.self, forKey: .app)
            let fichiers = try c.decode([Fichier].self, forKey: .fichiers)
            try ContratExport.verifierListe(fichiers)
            let nonRepris = try c.decode([FichierNonRepris].self, forKey: .fichiersNonRepris)
            try ContratExport.verifierNonRepris(nonRepris, fichiers: fichiers)
            self.format = format
            self.app = app
            self.fichiers = fichiers
            self.fichiersNonRepris = nonRepris
            identifiant = try c.decode(UUID.self, forKey: .identifiant)
            versionApp = try c.decode(String.self, forKey: .versionApp)
            date = try c.decode(Date.self, forKey: .date)
        }
    }

    /// Le manifeste en JSON. Refuse ce que `lireManifeste` refuserait : on ne produit pas un export illisible.
    public static func ecrire(_ manifeste: Manifeste) throws -> Data {
        guard manifeste.format == formatCourant else { throw Erreur.formatInconnu(manifeste.format) }
        try verifierListe(manifeste.fichiers)
        try verifierNonRepris(manifeste.fichiersNonRepris, fichiers: manifeste.fichiers)
        return try encodeur().encode(manifeste)
    }

    /// Lit un manifeste : format 1 seulement, app connue, fichiers valides ; toute autre erreur de forme donne
    /// `Erreur.illisible(cause)`.
    public static func lireManifeste(_ donnees: Data) throws -> Manifeste {
        try lire(Manifeste.self, donnees)
    }

    // MARK: Reglages

    /// Les types de valeur qu'un reglage repris peut avoir : ceux des UserDefaults de l'inventaire du 17/10.
    /// Les valeurs brutes sont celles de `reglages.json`.
    public enum TypeValeur: String, Sendable, CaseIterable, Codable {
        case bool, entier, decimal, texte, donnees, listeTextes, listeEntiers
    }

    /// La valeur d'un reglage, avec son type. Ecrite `{"type": "<TypeValeur>", "valeur": ...}` : un `1` entier, un
    /// `1,0` decimal et un booleen ne se confondent pas a la relecture. `donnees` est en base64 (la valeur Data d'un
    /// UserDefaults, comme `pont.hue`).
    public enum Valeur: Equatable, Hashable, Sendable, Codable {
        case bool(Bool)
        case entier(Int)
        case decimal(Double)
        case texte(String)
        case donnees(Data)
        case listeTextes([String])
        case listeEntiers([Int])

        public var type: TypeValeur {
            switch self {
            case .bool: .bool
            case .entier: .entier
            case .decimal: .decimal
            case .texte: .texte
            case .donnees: .donnees
            case .listeTextes: .listeTextes
            case .listeEntiers: .listeEntiers
            }
        }

        private enum CodingKeys: String, CodingKey { case type, valeur }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let brut = try c.decode(String.self, forKey: .type)
            // Le dernier element du chemin est la cle du reglage quand la valeur est lue dans `Reglages`.
            guard let type = TypeValeur(rawValue: brut) else {
                throw Erreur.valeurInconnue(cle: decoder.codingPath.last?.stringValue ?? "", type: brut)
            }
            switch type {
            case .bool: self = .bool(try c.decode(Bool.self, forKey: .valeur))
            case .entier: self = .entier(try c.decode(Int.self, forKey: .valeur))
            case .decimal: self = .decimal(try c.decode(Double.self, forKey: .valeur))
            case .texte: self = .texte(try c.decode(String.self, forKey: .valeur))
            case .donnees: self = .donnees(try c.decode(Data.self, forKey: .valeur))
            case .listeTextes: self = .listeTextes(try c.decode([String].self, forKey: .valeur))
            case .listeEntiers: self = .listeEntiers(try c.decode([Int].self, forKey: .valeur))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            switch self {
            case .bool(let v): try c.encode(v, forKey: .valeur)
            case .entier(let v): try c.encode(v, forKey: .valeur)
            case .decimal(let v): try c.encode(v, forKey: .valeur)
            case .texte(let v): try c.encode(v, forKey: .valeur)
            case .donnees(let v): try c.encode(v, forKey: .valeur)
            case .listeTextes(let v): try c.encode(v, forKey: .valeur)
            case .listeEntiers(let v): try c.encode(v, forKey: .valeur)
            }
        }
    }

    /// `reglages.json` : les reglages repris de l'ancienne app, sous leurs cles d'origine (sans prefixe : c'est
    /// l'import qui les range sous les cles de Maillage IoT). Une cle absente du fichier n'avait pas de valeur dans
    /// l'ancienne app : l'export n'ecrit jamais de valeur par defaut a sa place. Les cles du domaine de l'app qui ne
    /// sont pas reprises sont dans `nonRepris`, avec leur raison, pour que l'import les cite.
    public struct Reglages: Codable, Equatable, Sendable {
        public let format: Int
        /// L'app dont ils viennent : le manifeste dit la meme.
        public let app: AppSource
        public let valeurs: [String: Valeur]
        /// Les cles non reprises : leur nom et la raison (`horsContrat`, `typeInattendu` ou `transitoire`), jamais la
        /// valeur (elle peut etre personnelle). Obligatoire (dictionnaire vide s'il n'y en a pas) ; aucune cle n'est
        /// aussi dans `valeurs`.
        public let nonRepris: [String: RaisonNonRepris]

        public init(app: AppSource, valeurs: [String: Valeur], nonRepris: [String: RaisonNonRepris]) {
            self.format = ContratExport.formatCourant
            self.app = app
            self.valeurs = valeurs
            self.nonRepris = nonRepris
        }

        private enum CodingKeys: String, CodingKey { case format, app, valeurs, nonRepris }

        private struct CleDynamique: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        /// Lecture stricte : format reconnu, app connue, aucune cle vide ni en double, aucun type de valeur inconnu.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let format = try c.decode(Int.self, forKey: .format)
            guard format == ContratExport.formatCourant else { throw Erreur.formatInconnu(format) }
            let app = try c.decode(AppSource.self, forKey: .app)
            let v = try c.nestedContainer(keyedBy: CleDynamique.self, forKey: .valeurs)
            var valeurs: [String: Valeur] = [:]
            for cle in v.allKeys {
                guard !cle.stringValue.isEmpty else { throw Erreur.cleInvalide }
                valeurs[cle.stringValue] = try v.decode(Valeur.self, forKey: cle)
            }
            let n = try c.nestedContainer(keyedBy: CleDynamique.self, forKey: .nonRepris)
            var nonRepris: [String: RaisonNonRepris] = [:]
            for cle in n.allKeys {
                guard !cle.stringValue.isEmpty else { throw Erreur.cleInvalide }
                guard valeurs[cle.stringValue] == nil else { throw Erreur.cleEnDouble(cle.stringValue) }
                nonRepris[cle.stringValue] = try n.decode(RaisonNonRepris.self, forKey: cle)
            }
            self.format = format
            self.app = app
            self.valeurs = valeurs
            self.nonRepris = nonRepris
        }
    }

    /// Les reglages en JSON. Refuse une cle vide ou en double (dans `valeurs` et `nonRepris`) ; un decimal non fini
    /// (NaN, infini) fait echouer l'ecriture.
    public static func ecrire(_ reglages: Reglages) throws -> Data {
        guard reglages.format == formatCourant else { throw Erreur.formatInconnu(reglages.format) }
        guard !reglages.valeurs.keys.contains(""), !reglages.nonRepris.keys.contains("") else { throw Erreur.cleInvalide }
        if let double = reglages.nonRepris.keys.sorted().first(where: { reglages.valeurs[$0] != nil }) {
            throw Erreur.cleEnDouble(double)
        }
        return try encodeur().encode(reglages)
    }

    /// Lit `reglages.json` : format 1, app connue, types connus ; toute autre erreur de forme donne
    /// `Erreur.illisible(cause)`.
    public static func lireReglages(_ donnees: Data) throws -> Reglages {
        try lire(Reglages.self, donnees)
    }

    private static func lire<T: Decodable>(_ type: T.Type, _ donnees: Data) throws -> T {
        do {
            return try decodeur().decode(type, from: donnees)
        } catch let e as Erreur {
            throw e
        } catch let e as DecodingError {
            throw Erreur.illisible(cause(e))
        } catch {
            throw Erreur.illisible("lecture impossible")
        }
    }

    /// La cause d'une erreur de decodage, en texte court : le nom du champ ou le chemin, jamais la valeur lue.
    private static func cause(_ erreur: DecodingError) -> String {
        func chemin(_ cles: [any CodingKey]) -> String {
            var texte = ""
            for cle in cles {
                if let i = cle.intValue { texte += "[\(i)]" } else { texte += texte.isEmpty ? cle.stringValue : "." + cle.stringValue }
            }
            return texte.isEmpty ? "(racine)" : texte
        }
        switch erreur {
        case .keyNotFound(let cle, let contexte): return "champ manquant : " + chemin(contexte.codingPath + [cle])
        case .typeMismatch(_, let contexte): return "type inattendu : " + chemin(contexte.codingPath)
        case .valueNotFound(_, let contexte): return "valeur absente : " + chemin(contexte.codingPath)
        case .dataCorrupted(let contexte):
            if !contexte.codingPath.isEmpty { return "valeur invalide : " + chemin(contexte.codingPath) }
            // Sans chemin : un JSON mal forme (l'erreur du lecteur) ou une valeur que le decodeur ne situe pas (une date).
            return contexte.underlyingError != nil ? "JSON invalide" : "valeur invalide"
        @unknown default: return "illisible"
        }
    }

    // MARK: Fichiers et reglages connus

    /// Un mois de calendrier d'un fichier mensuel (`maillage-2026-10.jsonl`), pour la coupe a 90 jours.
    public struct Mois: Equatable, Hashable, Comparable, Sendable {
        public let annee: Int
        public let mois: Int

        public init(annee: Int, mois: Int) {
            self.annee = annee
            self.mois = mois
        }

        public static func < (a: Mois, b: Mois) -> Bool {
            (a.annee, a.mois) < (b.annee, b.mois)
        }
    }

    /// Un fichier connu de l'ancienne app : son chemin relatif, ou son modele quand il est mensuel
    /// (`maillage-AAAA-MM.jsonl`, `Journal/journal-AAAA-MM.jsonl`).
    public struct FichierConnu: Equatable, Hashable, Sendable {
        public let modele: String

        public init(_ modele: String) {
            self.modele = modele
        }

        /// Un fichier par mois : le modele porte `AAAA-MM`.
        public var estMensuel: Bool { modele.contains(Self.joker) }

        static let joker = "AAAA-MM"

        /// Le chemin `chemin` est celui de ce fichier (pour un mensuel : une annee de 4 chiffres, un mois de 01 a 12).
        public func correspond(_ chemin: String) -> Bool {
            guard estMensuel else { return chemin == modele }
            return Self.mois(de: chemin, modele: modele) != nil
        }

        /// Le mois d'un chemin mensuel qui suit le modele.
        static func mois(de chemin: String, modele: String) -> Mois? {
            guard let separation = modele.range(of: joker) else { return nil }
            let debut = String(modele[..<separation.lowerBound]), fin = String(modele[separation.upperBound...])
            guard chemin.hasPrefix(debut), chemin.hasSuffix(fin),
                  chemin.utf8.count == debut.utf8.count + joker.utf8.count + fin.utf8.count else { return nil }
            let milieu = Array(chemin.utf8.dropFirst(debut.utf8.count).prefix(joker.utf8.count))
            // AAAA-MM : quatre chiffres, un tiret, deux chiffres.
            func chiffres(_ r: Range<Int>) -> Int? {
                let tranche = milieu[r]
                guard tranche.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
                return tranche.reduce(0) { $0 * 10 + Int($1 - 0x30) }
            }
            guard milieu.count == 7, milieu[4] == 0x2D, let annee = chiffres(0..<4), let mois = chiffres(5..<7),
                  (1...12).contains(mois) else { return nil }
            return Mois(annee: annee, mois: mois)
        }
    }

    /// Les fichiers que l'export reprend de `Application Support/<app>/` (inventaire du 17/10, section 5). Un fichier
    /// LISTE au manifeste qui n'est pas dans cette liste (ni `reglages.json`) est refuse (`Erreur.fichierInconnu`) ; un
    /// fichier du dossier qui n'est pas liste est refuse aussi (`Erreur.fichierEnTrop`). Ce que l'ancienne app a en plus
    /// n'est pas copie : il va dans `fichiersNonRepris` (`classerFichiers`).
    public static func fichiersConnus(de app: AppSource) -> [FichierConnu] {
        let mensuels = ["maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        let modeles: [String]
        switch app {
        case .maillageThread:
            // noms.json : le releve de Maison de Thread (devient releve-maison.json a l'import).
            modeles = ["surnoms.json", "associations.json", "identites-routeurs.json", "dernier-maillage.json",
                       "dernieres-adresses.json", "noms.json", "pieces-routeurs.json", "positions-pieces.json"] + mensuels
        case .maillageZigbee:
            modeles = ["surnoms.json", "dernier-maillage.json", "appariements-maison.json", "noms-pont.json",
                       "releve-maison.json", "pieces-routeurs.json", "positions-pieces.json"] + mensuels
        }
        return modeles.map(FichierConnu.init)
    }

    /// Le chemin est celui d'un fichier connu de l'app (`fichiersConnus(de:)`).
    public static func estConnu(_ chemin: String, de app: AppSource) -> Bool {
        fichiersConnus(de: app).contains { $0.correspond(chemin) }
    }

    /// Le mois d'un fichier mensuel connu (`maillage-2026-10.jsonl`, `Journal/journal-2026-10.jsonl`) ; nil pour tout
    /// autre chemin. Le mois est celui du nom, jamais recalcule d'un contenu (les fichiers sont groupes par le calendrier
    /// local de l'ancienne app).
    public static func mois(de chemin: String) -> Mois? {
        for modele in ["maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"] {
            if let m = FichierConnu.mois(de: chemin, modele: modele) { return m }
        }
        return nil
    }

    /// Ce que l'export ne copie jamais : les fichiers de systeme (`estFichierDeSysteme`) et les fichiers mis de cote par
    /// l'app quand ils etaient illisibles (`*.illisible-*.json`), a n'importe quelle profondeur.
    public static func estExcluDeLExport(_ chemin: String) -> Bool {
        let nom = chemin.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? chemin
        return estFichierDeSysteme(chemin) || (nom.hasSuffix(".json") && nom.contains(".illisible-"))
    }

    /// Ce que macOS pose de lui-meme dans un dossier : `.DS_Store` (le Finder) et les compagnons AppleDouble `._<nom>`
    /// que macOS ecrit a cote de chaque fichier (attributs etendus comme `com.apple.quarantine`) quand le dossier est
    /// copie sur un volume FAT ou exFAT (une cle USB), a n'importe quelle profondeur. Seul le NOM compte : il est
    /// exactement `.DS_Store` ou COMMENCE par `._` (`_x.json`, `x._json` n'en sont pas). Un tel fichier n'a pas a etre
    /// liste au manifeste, n'est jamais lu ni copie, et ne fait pas refuser le dossier (`verifierDossier`). Un export
    /// ecrit par l'app n'en produit jamais : elle n'ecrit pas sur ces volumes, c'est la copie du Finder qui les ajoute.
    static func estFichierDeSysteme(_ chemin: String) -> Bool {
        let nom = chemin.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? chemin
        return nom == ".DS_Store" || nom.hasPrefix("._")
    }

    /// Un reglage repris : sa cle dans les UserDefaults de l'ancienne app, et son type.
    public struct ReglageConnu: Equatable, Hashable, Sendable {
        public let cle: String
        public let type: TypeValeur

        public init(_ cle: String, _ type: TypeValeur) {
            self.cle = cle
            self.type = type
        }
    }

    /// Les reglages que l'export ecrit dans `reglages.json` (inventaire du 17/10, section 5), sous leurs cles
    /// d'origine. Sont absents a dessein : les reglages de Sparkle (`SU*`), les etats de fenetre (`NSWindow Frame *`,
    /// `NSNav*`), `reglages.onglet`, `dossierNoms`, les secrets (trousseau, mot de passe Wi-Fi) : ils sont cites dans
    /// `Reglages.nonRepris`, sans valeur. Une cle absente de l'UserDefaults de l'ancienne app est absente du fichier,
    /// jamais ecrite avec une valeur par defaut.
    public static func reglagesConnus(de app: AppSource) -> [ReglageConnu] {
        let communs: [ReglageConnu] = [
            ReglageConnu("vuePieces3D", .bool), ReglageConnu("etagesEnGrille", .bool),
            ReglageConnu("legendeRepliee", .bool), ReglageConnu("grapheDejaOuvert", .bool),
            ReglageConnu("ouvertureSessionProposee", .bool), ReglageConnu("AppleLanguages", .listeTextes),
        ]
        switch app {
        case .maillageThread:
            return [
                ReglageConnu("sondeSerieUSB", .texte), ReglageConnu("sondeNom", .texte), ReglageConnu("sondeHote", .texte),
                // Recopiee telle quelle, jamais de defaut : absente, l'ancienne app la lit comme USB.
                ReglageConnu("sondeLiaison", .texte),
                ReglageConnu("scissionsNotifiees", .listeTextes),
                ReglageConnu("notification.scission", .bool), ReglageConnu("notification.routeurDisparu", .bool),
                ReglageConnu("notification.pertes", .bool), ReglageConnu("notification.informations", .bool),
            ] + communs
        case .maillageZigbee:
            return [
                ReglageConnu("sondeSerieUSB", .texte), ReglageConnu("sondeNom", .texte), ReglageConnu("sondeIeee", .texte),
                ReglageConnu("sondeNomWifi", .texte),
                // Les pages de la derniere lecture des tables (spec 4.2). Le journal des pages de la tournee
                // (`sondeJournalPages`, liste de Double) est transitoire : `transitoires(de:)`.
                ReglageConnu("sondePagesTables", .entier),
                ReglageConnu("sondeChemin", .texte),
                // JSON du pont retenu (adresse, identifiant, modele ; jamais sa cle) : donnee personnelle.
                ReglageConnu("pont.hue", .donnees),
                ReglageConnu("liensMontres", .texte), ReglageConnu("voisinsALaSelection", .bool),
                ReglageConnu("notification.routeurDisparu", .bool), ReglageConnu("notification.pertes", .bool),
                ReglageConnu("notification.informations", .bool),
            ] + communs
        }
    }

    /// Les cles que l'app ecrit mais que l'export ne reprend jamais, car sans sens apres coup : `reglages(depuis:app:)`
    /// les cite `transitoire`, sans valeur ni controle de type. `sondeJournalPages` de Maillage Zigbee : le journal des
    /// pages envoyees a la sonde dans les 10 dernieres minutes (`[Double]` : instant, pages...).
    public static func transitoires(de app: AppSource) -> Set<String> {
        switch app {
        case .maillageThread: []
        case .maillageZigbee: ["sondeJournalPages"]
        }
    }

    /// Le type que `reglagesConnus(de:)` donne a la cle ; nil si la cle n'est pas un reglage repris de cette app
    /// (`reglages(depuis:app:)` la cite alors `horsContrat`).
    public static func typeAttendu(cle: String, de app: AppSource) -> TypeValeur? {
        reglagesConnus(de: app).first { $0.cle == cle }?.type
    }

    /// Partage les fichiers vus dans `Application Support/<app>/` (chemins relatifs, avec des `/`) entre ceux que
    /// l'export copie (`fichiersConnus`, hors `estExcluDeLExport`) et ceux qu'il cite dans `fichiersNonRepris` (`exclu`
    /// ou `horsContrat`). Exception : `manifeste.json` et `reglages.json` a la RACINE du dossier de l'app (a la casse
    /// pres : ce sont eux qui entreraient en collision avec ceux de l'export) sont ecartes, ni copies ni cites ; plus
    /// bas (`Journal/manifeste.json`) ils sont un fichier comme un autre. Les deux listes sont triees par chemin ;
    /// rien n'est perdu : `aCopier.count + nonRepris.count == vus.count` moins ces deux noms. Un chemin invalide
    /// (`verifierChemin`) fait echouer le classement.
    public static func classerFichiers(vus: [String], de app: AppSource) throws
        -> (aCopier: [String], nonRepris: [FichierNonRepris]) {
        var aCopier: [String] = []
        var nonRepris: [FichierNonRepris] = []
        for chemin in vus {
            try verifierChemin(chemin)
            if [nomManifeste, nomReglages].contains(cle(chemin)) {
                continue
            } else if estExcluDeLExport(chemin) {
                nonRepris.append(FichierNonRepris(chemin: chemin, raison: .exclu))
            } else if estConnu(chemin, de: app) {
                aCopier.append(chemin)
            } else {
                nonRepris.append(FichierNonRepris(chemin: chemin, raison: .horsContrat))
            }
        }
        return (aCopier.sorted(), nonRepris.sorted { $0.chemin < $1.chemin })
    }

    // MARK: Lecture des UserDefaults

    /// Les reglages repris du domaine persistant d'une ancienne app (`domaine`, ce que rend
    /// `UserDefaults.persistentDomain(forName: app.identifiantBundle)`). Chaque cle de `reglagesConnus(de:)` presente
    /// va dans `valeurs` sous son type ; toute autre cle va dans `nonRepris` : `transitoire` pour `transitoires(de:)`,
    /// `typeInattendu` si la cle est connue mais d'un autre type, `horsContrat` sinon. Lecture stricte : un booleen
    /// n'est pas un nombre (`1` n'est jamais `true`, `true` jamais `1`), un entier n'est pas un decimal, les listes sont entierement du bon type. Une cle connue
    /// absente reste absente (aucun defaut) ; une cle vide est ignoree.
    ///
    /// Piege : ne jamais lire `UserDefaults.standard.array(forKey: "AppleLanguages")` ni `dictionaryRepresentation()` :
    /// ils rendent les valeurs GLOBALES du Mac, pas le choix de l'app. Seul le domaine persistant de l'app compte.
    public static func reglages(depuis domaine: [String: Any], app: AppSource) -> Reglages {
        var valeurs: [String: Valeur] = [:]
        var nonRepris: [String: RaisonNonRepris] = [:]
        for (cle, brut) in domaine where !cle.isEmpty {
            if transitoires(de: app).contains(cle) {
                nonRepris[cle] = .transitoire
            } else if let type = typeAttendu(cle: cle, de: app) {
                if let valeur = convertir(brut, en: type) { valeurs[cle] = valeur } else { nonRepris[cle] = .typeInattendu }
            } else {
                nonRepris[cle] = .horsContrat
            }
        }
        return Reglages(app: app, valeurs: valeurs, nonRepris: nonRepris)
    }

    /// `reglages(depuis:app:)` sur le domaine persistant de l'app (`app.identifiantBundle`, ou `domaine` pour un
    /// essai) de `defauts`. Un domaine vide donne des reglages vides.
    public static func reglagesPersistants(de app: AppSource, domaine: String? = nil,
                                           defauts: UserDefaults = .standard) -> Reglages {
        reglages(depuis: defauts.persistentDomain(forName: domaine ?? app.identifiantBundle) ?? [:], app: app)
    }

    private static func convertir(_ brut: Any, en type: TypeValeur) -> Valeur? {
        switch type {
        case .bool:
            guard let n = brut as? NSNumber, estBooleen(n) else { return nil }
            return .bool(n.boolValue)
        case .entier:
            return entier(brut).map(Valeur.entier)
        case .decimal:
            guard let n = brut as? NSNumber, !estBooleen(n), CFNumberIsFloatType(n as CFNumber), n.doubleValue.isFinite else {
                return nil
            }
            return .decimal(n.doubleValue)
        case .texte:
            return (brut as? String).map(Valeur.texte)
        case .donnees:
            return (brut as? Data).map(Valeur.donnees)
        case .listeTextes:
            guard let liste = brut as? [Any] else { return nil }
            let textes = liste.compactMap { $0 as? String }
            return textes.count == liste.count ? .listeTextes(textes) : nil
        case .listeEntiers:
            guard let liste = brut as? [Any] else { return nil }
            let entiers = liste.compactMap(entier)
            return entiers.count == liste.count ? .listeEntiers(entiers) : nil
        }
    }

    /// Un `NSNumber` booleen (`CFBoolean`), distinct d'un nombre 0 ou 1.
    private static func estBooleen(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    /// Un entier strict : un nombre non booleen, non decimal, qui tient dans un `Int` sans perte.
    private static func entier(_ brut: Any) -> Int? {
        guard let n = brut as? NSNumber, !estBooleen(n), !CFNumberIsFloatType(n as CFNumber) else { return nil }
        var valeur: Int64 = 0
        guard CFNumberGetValue(n as CFNumber, .sInt64Type, &valeur) else { return nil }
        return Int(exactly: valeur)
    }

    // MARK: Verification d'un dossier d'export

    /// Relit un dossier d'export en entier : l'export l'appelle sur son propre dossier avant de dire "Export reussi",
    /// l'import avant de toucher a quoi que ce soit. Rend le manifeste et les reglages lus. Une erreur typee par cause,
    /// la premiere trouvee :
    /// - `manifesteAbsent`, ou un manifeste refuse par `lireManifeste` (format, app, chemins, empreintes mal formes) ;
    /// - `reglagesAbsents` : `reglages.json` n'est pas liste ;
    /// - `fichierInconnu` : un fichier liste n'est ni `reglages.json` ni connu de l'app (`fichiersConnus`) ;
    /// - `lienSymbolique` : un lien dans le dossier, liste ou non ; `fichierEnTrop` : un fichier non liste (hors
    ///   `manifeste.json`, `.DS_Store` et les fichiers AppleDouble `._*`, que le Finder ou une copie sur cle FAT ou
    ///   exFAT peuvent poser : `estFichierDeSysteme`, jamais lus) ;
    /// - `fichierManquant`, `tailleFausse`, `empreinteFausse` : un fichier liste absent, ou dont la taille ou le SHA-256
    ///   n'est pas celui du manifeste (`Fichier.decrire`, un passage) ;
    /// - pour `reglages.json` : octets lus une seule fois, verifies puis decodes (`lireReglages`) ; `appDifferente` si
    ///   son app n'est pas celle du manifeste.
    public static func verifierDossier(_ dossier: URL) throws -> (Manifeste, Reglages) {
        let gestionnaire = FileManager.default
        let urlManifeste = try resoudre(nomManifeste, dans: dossier)
        guard gestionnaire.fileExists(atPath: urlManifeste.path) else { throw Erreur.manifesteAbsent }
        let manifeste = try lireManifeste(try lireOctets(urlManifeste))

        guard let fichierReglages = manifeste.fichiers.first(where: { $0.chemin == nomReglages }) else {
            throw Erreur.reglagesAbsents
        }
        for f in manifeste.fichiers where f.chemin != nomReglages && !estConnu(f.chemin, de: manifeste.app) {
            throw Erreur.fichierInconnu(f.chemin)
        }
        let listes = Set(manifeste.fichiers.map { cle($0.chemin) })
        for chemin in try fichiersPresents(dans: dossier, prefixe: "") {
            if cle(chemin) == nomManifeste || estFichierDeSysteme(chemin) { continue }
            guard listes.contains(cle(chemin)) else { throw Erreur.fichierEnTrop(chemin) }
        }
        for f in manifeste.fichiers where f.chemin != nomReglages {
            guard gestionnaire.fileExists(atPath: try resoudre(f.chemin, dans: dossier).path) else {
                throw Erreur.fichierManquant(f.chemin)
            }
            let vu = try Fichier.decrire(chemin: f.chemin, dans: dossier)
            guard vu.taille == f.taille else { throw Erreur.tailleFausse(f.chemin) }
            guard vu.sha256 == f.sha256 else { throw Erreur.empreinteFausse(f.chemin) }
        }
        let urlReglages = try resoudre(nomReglages, dans: dossier)
        guard gestionnaire.fileExists(atPath: urlReglages.path) else { throw Erreur.fichierManquant(nomReglages) }
        let octets = try lireOctets(urlReglages)
        guard Int64(octets.count) == fichierReglages.taille else { throw Erreur.tailleFausse(nomReglages) }
        guard sha256(octets) == fichierReglages.sha256 else { throw Erreur.empreinteFausse(nomReglages) }
        let reglages = try lireReglages(octets)
        guard reglages.app == manifeste.app else { throw Erreur.appDifferente }
        return (manifeste, reglages)
    }

    private static func lireOctets(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw Erreur.illisible("lecture impossible") }
    }

    /// Les chemins relatifs de tous les fichiers sous `dossier`, tries, avec des `/`. Un lien symbolique (fichier ou
    /// dossier) est refuse ; les dossiers vides sont ignores.
    private static func fichiersPresents(dans dossier: URL, prefixe: String) throws -> [String] {
        var chemins: [String] = []
        for nom in try FileManager.default.contentsOfDirectory(atPath: dossier.path).sorted() {
            let chemin = prefixe + nom
            let url = dossier.appendingPathComponent(nom)
            let valeurs = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if valeurs.isSymbolicLink == true { throw Erreur.lienSymbolique(chemin) }
            if valeurs.isDirectory == true {
                chemins += try fichiersPresents(dans: url, prefixe: chemin + "/")
            } else {
                chemins.append(chemin)
            }
        }
        return chemins
    }

    // MARK: Chemins

    /// Un chemin d'export est relatif et reste dans le dossier. Verification lexicale seulement (`resoudre` ajoute les
    /// liens symboliques) : refuse le chemin vide ou absolu, un composant vide, `.` ou `..`, un `\`, un caractere de
    /// controle (dont NUL), un composant de plus de 255 octets ou un chemin de plus de 1024 octets.
    public static func cheminEstValide(_ chemin: String) -> Bool {
        guard !chemin.isEmpty, chemin.utf8.count <= 1024, !chemin.hasPrefix("/") else { return false }
        guard !chemin.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\\" }) else {
            return false
        }
        return chemin.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { composant in
            !composant.isEmpty && composant != "." && composant != ".." && composant.utf8.count <= 255
        }
    }

    /// `cheminEstValide`, ou `Erreur.cheminInvalide(chemin)`.
    public static func verifierChemin(_ chemin: String) throws {
        guard cheminEstValide(chemin) else { throw Erreur.cheminInvalide(chemin) }
    }

    /// L'URL du fichier `chemin` du dossier d'export, apres verification : chemin valide (`verifierChemin`), aucun
    /// lien symbolique sur le chemin (le fichier lui-meme compris), et le resultat reste dans le dossier. Le fichier
    /// peut ne pas exister encore (a l'ecriture). Le dossier lui-meme peut etre derriere un lien.
    public static func resoudre(_ chemin: String, dans dossier: URL) throws -> URL {
        try verifierChemin(chemin)
        let base = dossier.standardizedFileURL
        var courant = base
        for composant in chemin.split(separator: "/") {
            courant = courant.appendingPathComponent(String(composant))
            // Un composant absent n'est pas un lien : seul un lien existant est refuse.
            if (try? courant.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Erreur.lienSymbolique(chemin)
            }
        }
        let racine = base.resolvingSymlinksInPath().path
        let fichier = courant.resolvingSymlinksInPath().path
        guard fichier.hasPrefix(racine.hasSuffix("/") ? racine : racine + "/") else { throw Erreur.cheminInvalide(chemin) }
        return courant
    }

    // MARK: Empreintes

    /// Taille du bloc lu a la fois pour l'empreinte d'un fichier : 1 Mio. Un historique de 100 Mo n'est jamais en memoire.
    private static let tailleBloc = 1 << 20

    /// SHA-256 de `donnees`, en hexadecimal minuscule (64 caracteres).
    public static func sha256(_ donnees: Data) -> String {
        hexadecimal(SHA256.hash(data: donnees))
    }

    /// La taille et le SHA-256 du contenu du fichier, lus en UN seul passage, par blocs de 1 Mio : la taille est le
    /// nombre d'octets haches, donc les deux decrivent les memes octets meme si le fichier grandit pendant la lecture
    /// (journal en cours d'ecriture). Les erreurs de lecture passent (fichier absent, illisible) : rien n'est invente.
    public static func empreinte(fichier: URL) throws -> (taille: Int64, sha256: String) {
        let lecteur = try FileHandle(forReadingFrom: fichier)
        defer { try? lecteur.close() }
        var hachage = SHA256()
        var taille: Int64 = 0
        while try autoreleasepool(invoking: {
            guard let bloc = try lecteur.read(upToCount: tailleBloc), !bloc.isEmpty else { return false }
            hachage.update(data: bloc)
            taille += Int64(bloc.count)
            return true
        }) {}
        return (taille, hexadecimal(hachage.finalize()))
    }

    /// SHA-256 du contenu du fichier, en hexadecimal minuscule (`empreinte(fichier:)` sans la taille).
    public static func sha256(fichier: URL) throws -> String {
        try empreinte(fichier: fichier).sha256
    }

    /// 64 chiffres hexadecimaux minuscules : la forme d'une empreinte du manifeste.
    public static func empreinteEstValide(_ empreinte: String) -> Bool {
        empreinte.utf8.count == 64 && empreinte.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    private static func hexadecimal(_ resume: some Sequence<UInt8>) -> String {
        let chiffres = Array("0123456789abcdef".utf8)
        var octets: [UInt8] = []
        octets.reserveCapacity(64)
        for o in resume {
            octets.append(chiffres[Int(o >> 4)])
            octets.append(chiffres[Int(o & 0x0F)])
        }
        return String(decoding: octets, as: UTF8.self)
    }

    // MARK: Verifications du manifeste

    /// Un fichier du manifeste : chemin valide, taille positive ou nulle, empreinte bien formee.
    static func verifier(_ fichier: Fichier) throws {
        try verifierChemin(fichier.chemin)
        guard fichier.taille >= 0 else { throw Erreur.tailleInvalide(fichier.chemin) }
        guard empreinteEstValide(fichier.sha256) else { throw Erreur.empreinteInvalide(fichier.chemin) }
    }

    /// Ce que le Mac confond : le chemin a la casse et a la normalisation Unicode pres.
    private static func cle(_ chemin: String) -> String {
        chemin.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// La liste du manifeste : chaque fichier valide, aucun doublon (casse et normalisation Unicode comprises), jamais
    /// `manifeste.json`.
    static func verifierListe(_ fichiers: [Fichier]) throws {
        var vus: Set<String> = []
        for f in fichiers {
            try verifier(f)
            let cle = cle(f.chemin)
            guard cle != nomManifeste else { throw Erreur.nomReserve(f.chemin) }
            guard vus.insert(cle).inserted else { throw Erreur.cheminEnDouble(f.chemin) }
        }
    }

    /// Les fichiers non repris : chemins valides, jamais `manifeste.json`, aucun doublon entre eux ni avec les fichiers
    /// repris (un fichier est copie ou non repris, pas les deux).
    static func verifierNonRepris(_ nonRepris: [FichierNonRepris], fichiers: [Fichier]) throws {
        var vus = Set(fichiers.map { cle($0.chemin) })
        for n in nonRepris {
            try verifierChemin(n.chemin)
            let cle = cle(n.chemin)
            guard cle != nomManifeste else { throw Erreur.nomReserve(n.chemin) }
            guard vus.insert(cle).inserted else { throw Erreur.cheminEnDouble(n.chemin) }
        }
    }
}
