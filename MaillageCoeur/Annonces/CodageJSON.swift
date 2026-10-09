import Foundation

/// JSON des captures et du journal : cles triees, dates ISO 8601 en UTC avec
/// les millisecondes ("2026-09-27T00:14:00.000Z"). La lecture accepte aussi
/// les dates sans millisecondes.
public enum CodageJSON {
    static let avecMillisecondes = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let sansMillisecondes = Date.ISO8601FormatStyle()

    public static func encodeur(lisible: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = lisible ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                                     : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(avecMillisecondes))
        }
        return e
    }

    public static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let texte = try c.decode(String.self)
            if let date = (try? avecMillisecondes.parse(texte)) ?? (try? sansMillisecondes.parse(texte)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "date invalide : \(texte)")
        }
        return d
    }
}
