import Foundation
import os

/// Fichiers JSON gardes dans le conteneur de l'app : les places des pieces (`positions-pieces.json`),
/// les pieces choisies (`pieces-routeurs.json`), les surnoms (`surnoms.json`) et les identites des
/// routeurs (`identites-routeurs.json`). Une regle commune, pour ne jamais perdre ce qu'ils gardent :
/// - absent, ou lisible et d'une version connue : lu et ecrit comme d'habitude ;
/// - d'une version plus recente (une app plus recente l'a ecrit, peut-etre sous un autre schema) : lu
///   comme vide, et jamais reecrit ; l'app travaille en memoire, et le note une fois au journal du Mac ;
/// - present mais illisible : lu comme vide ; avant la premiere ecriture, il est mis de cote, renomme
///   `<nom>.illisible-AAAAMMJJ-HHMMSS.json` dans le meme dossier, et jamais efface.
/// L'etat du fichier est relu avant chaque ecriture : rien n'est retenu d'une lecture a l'autre.
enum FichiersGardes {
    /// Ce qu'est le fichier sur le disque.
    enum Etat: Equatable {
        case absent, lisible, plusRecent, illisible
    }

    /// Le numero de version d'un fichier qui en a un, lu seul : un fichier plus recent peut avoir un
    /// autre schema.
    private struct Version: Decodable {
        var version: Int
    }

    /// Journal du Mac (Console, sous-systeme fr.djoko.maillage.zigbee) : le nom du fichier, jamais son contenu.
    static let journal = Logger(subsystem: "fr.djoko.maillage.zigbee", category: "fichiers")
    /// Fichiers d'une version plus recente deja notes au journal, dans ce processus.
    private static let notes = OSAllocatedUnfairLock(initialState: Set<String>())

    /// L'etat du fichier, et son contenu s'il est lisible. `version` : la plus recente que l'app sait
    /// lire ; nil pour un fichier sans version.
    static func examiner<T: Decodable>(_ type: T.Type, _ url: URL, version: Int?) -> (etat: Etat, contenu: T?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (.absent, nil) }
        guard let d = try? Data(contentsOf: url) else { return (.illisible, nil) }
        if let version {
            guard let v = try? JSONDecoder().decode(Version.self, from: d) else { return (.illisible, nil) }
            if v.version > version { return (.plusRecent, nil) }
        }
        guard let contenu = try? JSONDecoder().decode(T.self, from: d) else { return (.illisible, nil) }
        return (.lisible, contenu)
    }

    /// Le contenu du fichier ; nil s'il manque, s'il est illisible ou d'une version plus recente.
    static func lire<T: Decodable>(_ type: T.Type, _ url: URL, version: Int? = nil) -> T? {
        let (etat, contenu) = examiner(type, url, version: version)
        if etat == .plusRecent { noterPlusRecent(url) }
        return contenu
    }

    /// Ecrit `valeur` en JSON (cles triees, indente), d'un bloc. Sur un fichier d'une version plus
    /// recente, rien n'est ecrit, sans erreur. Un fichier illisible est d'abord mis de cote.
    static func ecrire<T: Codable>(_ valeur: T, dans url: URL, version: Int? = nil) throws {
        switch examiner(T.self, url, version: version).etat {
        case .plusRecent:
            noterPlusRecent(url)
            return
        case .illisible:
            try mettreDeCote(url)
        case .absent, .lisible:
            break
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try e.encode(valeur).write(to: url, options: .atomic)
    }

    /// Renomme le fichier `<nom>.illisible-AAAAMMJJ-HHMMSS.json` dans son dossier, a l'heure locale, et
    /// le note au journal ; rend son nouveau chemin. Un fichier deja la sous ce nom n'est pas remplace :
    /// le renommage echoue.
    @discardableResult
    static func mettreDeCote(_ url: URL, maintenant: Date = Date()) throws -> URL {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = .current
        let c = calendrier.dateComponents([.year, .month, .day, .hour, .minute, .second], from: maintenant)
        let horodatage = String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                                c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let nom = url.deletingPathExtension().lastPathComponent + ".illisible-" + horodatage + ".json"
        let cible = url.deletingLastPathComponent().appendingPathComponent(nom)
        try FileManager.default.moveItem(at: url, to: cible)
        journal.notice("\(url.lastPathComponent, privacy: .public) illisible, mis de cote : \(nom, privacy: .public)")
        return cible
    }

    /// Note au journal, une fois par fichier et par lancement, qu'il est d'une version plus recente.
    private static func noterPlusRecent(_ url: URL) {
        guard notes.withLock({ $0.insert(url.path).inserted }) else { return }
        journal.notice("\(url.lastPathComponent, privacy: .public) d'une version plus recente : lu comme vide, jamais reecrit")
    }
}
