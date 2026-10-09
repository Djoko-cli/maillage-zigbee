import Foundation

/// Journal sur disque : JSON Lines, un fichier par mois ("journal-2026-09.jsonl",
/// mois du calendrier local), un fichier supprime quand son mois est fini depuis
/// plus de 90 jours (`FichiersMensuels`).
public struct JournalFichiers: Sendable {
    public static let conservation = FichiersMensuels.conservation

    public let dossier: URL
    public let calendrier: Calendar
    private let fichiersMensuels: FichiersMensuels

    public init(dossier: URL, calendrier: Calendar = .current) {
        self.dossier = dossier
        self.calendrier = calendrier
        fichiersMensuels = FichiersMensuels(dossier: dossier, prefixe: "journal", calendrier: calendrier)
    }

    /// Nom du fichier du mois d'une date.
    public func nomFichier(_ date: Date) -> String { fichiersMensuels.nomFichier(date) }

    /// Ajoute les evenements a la fin du fichier de leur mois.
    public func ajouter(_ evenements: [Evenement]) throws {
        let encodeur = CodageJSON.encodeur()
        try fichiersMensuels.ajouter(evenements.map { (date: $0.date, json: try encodeur.encode($0)) })
    }

    /// Tous les evenements gardes, du plus ancien au plus recent ; une ligne
    /// illisible est ignoree.
    public func lire() throws -> [Evenement] {
        let decodeur = CodageJSON.decodeur()
        let tous = try fichiersMensuels.lignes().compactMap { try? decodeur.decode(Evenement.self, from: $0) }
        return tous.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }

    /// Supprime les fichiers des mois finis depuis plus de 90 jours ; rend leurs noms.
    @discardableResult
    public func purger(maintenant: Date) throws -> [String] {
        try fichiersMensuels.purger(maintenant: maintenant)
    }

    /// Fichiers du journal, dans l'ordre des mois.
    func fichiers() throws -> [URL] { try fichiersMensuels.fichiers() }

    /// Debut du mois suivant pour "journal-AAAA-MM.jsonl", nil pour un autre nom.
    func finDuMois(_ nom: String) -> Date? { fichiersMensuels.finDuMois(nom) }
}
