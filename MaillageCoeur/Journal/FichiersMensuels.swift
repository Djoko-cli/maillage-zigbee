import Foundation

/// Fichiers JSON Lines mensuels d'un dossier ("<prefixe>-2026-09.jsonl", mois du calendrier
/// local) : une ligne par enregistrement, ajoutee a la fin du fichier de son mois ; un fichier
/// est supprime quand son mois est fini depuis plus de 90 jours. Le journal (`journal-…`) et
/// l'historique du maillage (`maillage-…`) en sont faits.
public struct FichiersMensuels: Sendable {
    public static let conservation: TimeInterval = 90 * 24 * 3600

    public let dossier: URL
    public let prefixe: String
    public let calendrier: Calendar

    public init(dossier: URL, prefixe: String, calendrier: Calendar = .current) {
        self.dossier = dossier
        self.prefixe = prefixe
        self.calendrier = calendrier
    }

    /// Nom du fichier du mois d'une date.
    public func nomFichier(_ date: Date) -> String {
        let c = calendrier.dateComponents([.year, .month], from: date)
        return prefixe + String(format: "-%04d-%02d.jsonl", c.year ?? 0, c.month ?? 0)
    }

    /// Ajoute chaque ligne (du JSON, sans fin de ligne) a la fin du fichier du mois de sa date.
    public func ajouter(_ lignes: [(date: Date, json: Data)]) throws {
        guard !lignes.isEmpty else { return }
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        for (nom, groupe) in Dictionary(grouping: lignes, by: { nomFichier($0.date) }) {
            var donnees = Data()
            for l in groupe {
                donnees.append(l.json)
                donnees.append(0x0A)
            }
            let url = dossier.appendingPathComponent(nom)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let f = try FileHandle(forWritingTo: url)
            defer { try? f.close() }
            try f.seekToEnd()
            try f.write(contentsOf: donnees)
        }
    }

    /// Lignes non vides et en UTF-8 valide des fichiers, dans l'ordre des mois puis des lignes ; `depuis` : seulement
    /// les fichiers des mois qui finissent apres cette date.
    public func lignes(depuis debut: Date? = nil) throws -> [Data] {
        var lignes: [Data] = []
        for url in try fichiers() {
            if let debut, let fin = finDuMois(url.lastPathComponent), fin <= debut { continue }
            // Ligne par ligne : une ligne abimee (octet non UTF-8, caractere coupe) est ignoree, les
            // autres du fichier restent lues.
            let donnees = try Data(contentsOf: url)
            for l in donnees.split(separator: 0x0A, omittingEmptySubsequences: true)
            where String(data: l, encoding: .utf8) != nil {
                lignes.append(Data(l))
            }
        }
        return lignes
    }

    /// Supprime les fichiers des mois finis depuis plus de 90 jours ; rend leurs noms.
    @discardableResult
    public func purger(maintenant: Date) throws -> [String] {
        var supprimes: [String] = []
        for url in try fichiers() {
            guard let fin = finDuMois(url.lastPathComponent),
                  maintenant.timeIntervalSince(fin) > Self.conservation else { continue }
            try FileManager.default.removeItem(at: url)
            supprimes.append(url.lastPathComponent)
        }
        return supprimes
    }

    /// Fichiers de ce prefixe, dans l'ordre des mois.
    func fichiers() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: dossier.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)
            .filter { finDuMois($0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Debut du mois suivant pour "<prefixe>-AAAA-MM.jsonl", nil pour un autre nom.
    func finDuMois(_ nom: String) -> Date? {
        guard nom.hasPrefix(prefixe + "-") else { return nil }
        let m = nom.dropFirst(prefixe.count + 1).wholeMatch(of: /(\d{4})-(\d{2})\.jsonl/)
        guard let m, let annee = Int(m.output.1), let mois = Int(m.output.2),
              let debut = calendrier.date(from: DateComponents(year: annee, month: mois, day: 1)) else { return nil }
        return calendrier.date(byAdding: .month, value: 1, to: debut)
    }
}
