import Foundation

/// L'export de Maillage Zigbee pour Maillage IoT (spec de Maillage IoT, sections 4.1, 4.2 et 6.8) : assemble le dossier
/// d'export du contrat (`ContratExport`) sans rien modifier dans l'app.
///
/// Ordre, dans un dossier temporaire (jamais directement a la destination) :
/// 1. les fichiers vus dans le dossier de l'app sont classes (`classerFichiers`) ; les fichiers connus sont copies a
///    l'octet, sous le meme chemin relatif ; les autres sont cites dans le manifeste, sans etre copies ;
/// 2. `reglages.json` est ecrit par le contrat, d'apres les reglages donnes (`reglagesPersistants`) ;
/// 3. chaque fichier est decrit sur sa COPIE (`Fichier.decrire`), puis `manifeste.json` est ecrit ;
/// 4. le dossier est relu par `verifierDossier` : seule une relecture reussie le laisse passer ;
/// 5. il est deplace a la destination, puis relu une derniere fois la. Un dossier de meme nom (que l'utilisateur a
///    confirme de remplacer) n'est detruit qu'apres cette derniere relecture : d'abord mis de cote dans le dossier
///    temporaire, il est remis en place si la relecture echoue.
/// Aucun secret du trousseau n'est lu : ni la cle du pont, ni celle de la sonde, ni le mot de passe Wi-Fi.
public enum ExportReprise {
    public enum Erreur: Error, Equatable {
        /// La destination est dans le dossier de donnees de l'app, est ce dossier, ou le contient : l'export s'y copierait
        /// lui-meme, ou remplacerait les donnees avec le dossier.
        case destinationDansLesDonnees
        /// Le contrat refuse quelque chose pendant l'assemblage, avant la relecture (un chemin invalide, un lien
        /// symbolique...) : rien n'a ete ecrit a la destination.
        case assemblage(ContratExport.Erreur)
        /// Le dossier d'export ne passe pas la relecture du contrat (la cause, ou la premiere trouvee). La destination
        /// est restee comme avant : un ancien dossier y est intact.
        case relecture(ContratExport.Erreur)
        /// La relecture finale a echoue et l'ancien dossier n'a pas pu etre remis en place : il est conserve dans le
        /// dossier donne.
        case ancienNonRestaure(URL)
    }

    /// Ce qu'un export reussi a ecrit.
    public struct Resultat: Equatable, Sendable {
        /// Le dossier d'export, a sa destination.
        public let dossier: URL
        public let manifeste: ContratExport.Manifeste
        public let reglages: ContratExport.Reglages
    }

    /// Exporte `source` (le dossier de l'app sous `Application Support`) et `reglages` dans le dossier `destination`.
    ///
    /// - `temporaire` : le dossier dans lequel l'export est d'abord assemble.
    /// - `avantRelecture` : appele sur le dossier assemble, juste avant la relecture (les tests y abiment le dossier).
    /// - `apresDeplacement` : appele sur le dossier a sa destination, juste avant la relecture finale (idem).
    public static func exporter(depuis source: URL, app: ContratExport.AppSource, versionApp: String,
                                reglages: ContratExport.Reglages, vers destination: URL,
                                identifiant: UUID = UUID(), date: Date = Date(),
                                temporaire: URL = FileManager.default.temporaryDirectory,
                                avantRelecture: (URL) throws -> Void = { _ in },
                                apresDeplacement: (URL) throws -> Void = { _ in }) throws -> Resultat {
        let gestionnaire = FileManager.default
        guard reglages.app == app else { throw Erreur.relecture(.appDifferente) }
        guard !contient(source, destination) else { throw Erreur.destinationDansLesDonnees }

        let brouillon = temporaire.appendingPathComponent(".export-maillage-iot-" + UUID().uuidString)
        try gestionnaire.createDirectory(at: brouillon, withIntermediateDirectories: true)
        defer { try? gestionnaire.removeItem(at: brouillon) }

        // 1 a 3 : les erreurs du contrat sont celles de l'assemblage (`Erreur.assemblage`), pas des erreurs brutes.
        let (_, citesParLeContrat, speciaux, fichiers) = try assembler(
            source: source, app: app, reglages: reglages, dans: brouillon)
        // `manifeste.json` et `reglages.json` d'un dossier de l'app sont classes `horsContrat` par `classerFichiers`, mais
        // le manifeste ne peut pas les citer (`nomReserve`, `cheminEnDouble` : ces noms sont ceux de l'export). L'app
        // n'en ecrit aucun ; s'il y en avait, ils ne sont ni copies ni cites.
        let reserves: Set<String> = [ContratExport.nomManifeste, ContratExport.nomReglages]
        let nonRepris = (citesParLeContrat + speciaux.map { ContratExport.FichierNonRepris(chemin: $0, raison: .horsContrat) })
            .filter { !reserves.contains($0.chemin.precomposedStringWithCanonicalMapping.lowercased()) }
            .sorted { $0.chemin < $1.chemin }
        let manifeste = ContratExport.Manifeste(identifiant: identifiant, app: app, versionApp: versionApp, date: date,
                                                fichiers: fichiers, fichiersNonRepris: nonRepris)
        do {
            try ContratExport.ecrire(manifeste).write(to: try ContratExport.resoudre(ContratExport.nomManifeste, dans: brouillon))
        } catch let e as ContratExport.Erreur {
            throw Erreur.assemblage(e)
        }
        // 4. La relecture du dossier assemble.
        try avantRelecture(brouillon)
        let (lu, reglagesLus) = try relire(brouillon)

        // 5. La destination. Un dossier existant (que le panneau d'enregistrement a fait confirmer) n'est pas detruit
        // avant la relecture finale : il est mis de cote dans le dossier temporaire, et remis en place si elle echoue.
        let aPart: URL? = gestionnaire.fileExists(atPath: destination.path)
            ? temporaire.appendingPathComponent(".export-maillage-iot-ancien-" + UUID().uuidString) : nil
        if let aPart { try gestionnaire.moveItem(at: destination, to: aPart) }
        do {
            try gestionnaire.moveItem(at: brouillon, to: destination)
            try apresDeplacement(destination)
            _ = try relire(destination)
        } catch {
            try? gestionnaire.removeItem(at: destination)
            if let aPart {
                do { try gestionnaire.moveItem(at: aPart, to: destination) } catch { throw Erreur.ancienNonRestaure(aPart) }
            }
            throw error
        }
        if let aPart { try? gestionnaire.removeItem(at: aPart) }
        return Resultat(dossier: destination, manifeste: lu, reglages: reglagesLus)
    }

    /// Les etapes 1 a 3 : copie des fichiers connus dans `brouillon`, `reglages.json`, description des copies. Toute
    /// erreur du contrat sort sous `Erreur.assemblage`.
    private static func assembler(source: URL, app: ContratExport.AppSource, reglages: ContratExport.Reglages,
                                  dans brouillon: URL) throws
        -> (aCopier: [String], cites: [ContratExport.FichierNonRepris], speciaux: [String], fichiers: [ContratExport.Fichier]) {
        let gestionnaire = FileManager.default
        do {
            // 1. Les fichiers de l'app : copies ou cites.
            let (vus, speciaux) = try fichiersVus(dans: source)
            let (aCopier, cites) = try ContratExport.classerFichiers(vus: vus, de: app)
            for chemin in aCopier {
                let cible = try ContratExport.resoudre(chemin, dans: brouillon)
                try gestionnaire.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
                try gestionnaire.copyItem(at: source.appendingPathComponent(chemin), to: cible)
            }
            // 2. Les reglages.
            try ContratExport.ecrire(reglages).write(to: try ContratExport.resoudre(ContratExport.nomReglages, dans: brouillon))
            // 3. Le manifeste, d'apres les COPIES : ici, la description de chaque fichier.
            let fichiers = try (aCopier + [ContratExport.nomReglages]).map {
                try ContratExport.Fichier.decrire(chemin: $0, dans: brouillon)
            }
            return (aCopier, cites, speciaux, fichiers)
        } catch let e as ContratExport.Erreur {
            throw Erreur.assemblage(e)
        }
    }

    /// `verifierDossier`, ses erreurs sous `Erreur.relecture`.
    private static func relire(_ dossier: URL) throws -> (ContratExport.Manifeste, ContratExport.Reglages) {
        do {
            return try ContratExport.verifierDossier(dossier)
        } catch let e as ContratExport.Erreur {
            throw Erreur.relecture(e)
        }
    }

    /// `destination` est `source`, est dedans, ou la contient (liens symboliques resolus) : dans les deux derniers cas,
    /// l'export se copierait lui-meme, ou remplacerait les donnees de l'app avec le dossier qui les porte.
    private static func contient(_ source: URL, _ destination: URL) -> Bool {
        let racine = resolu(source), cible = resolu(destination)
        func dedans(_ chemin: String, _ parent: String) -> Bool {
            chemin == parent || chemin.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
        }
        return dedans(cible, racine) || dedans(racine, cible)
    }

    /// Le chemin avec les liens symboliques resolus jusqu'au premier ancetre qui existe (la destination n'existe pas
    /// encore), puis le reste tel quel.
    private static func resolu(_ url: URL) -> String {
        var existant = url.standardizedFileURL
        var reste: [String] = []
        while !FileManager.default.fileExists(atPath: existant.path), existant.pathComponents.count > 1 {
            reste.insert(existant.lastPathComponent, at: 0)
            existant = existant.deletingLastPathComponent()
        }
        return reste.reduce(existant.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.path
    }

    /// Les fichiers ordinaires sous `source` (chemins relatifs, avec des `/`), et les elements qui n'en sont pas (lien
    /// symbolique, socket...) et ne seront pas copies. Les dossiers n'y sont pas ; un dossier absent donne deux listes
    /// vides (l'app n'a encore rien ecrit).
    private static func fichiersVus(dans source: URL) throws -> (fichiers: [String], speciaux: [String]) {
        guard FileManager.default.fileExists(atPath: source.path) else { return ([], []) }
        var fichiers: [String] = [], speciaux: [String] = []
        func parcourir(_ dossier: URL, _ prefixe: String) throws {
            for nom in try FileManager.default.contentsOfDirectory(atPath: dossier.path).sorted() {
                let url = dossier.appendingPathComponent(nom)
                let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if v.isSymbolicLink == true {
                    speciaux.append(prefixe + nom)
                } else if v.isDirectory == true {
                    try parcourir(url, prefixe + nom + "/")
                } else if v.isRegularFile == true {
                    fichiers.append(prefixe + nom)
                } else {
                    speciaux.append(prefixe + nom)
                }
            }
        }
        try parcourir(source, "")
        return (fichiers, speciaux)
    }
}
