import Foundation

/// Champs d'un enregistrement TXT DNS-SD (RFC 6763, section 6) : cle -> octets.
/// Les cles sont gardees en minuscules (insensibles a la casse) ; une cle sans
/// "=" a une valeur vide.
public struct ChampsTXT: Hashable, Sendable {
    public private(set) var valeurs: [String: Data]

    public init(_ valeurs: [String: Data] = [:]) {
        self.valeurs = Dictionary(valeurs.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    /// Enregistrement brut : suite de chaines, chacune precedee de sa longueur
    /// (1 octet). La premiere occurrence d'une cle est retenue ; une chaine vide
    /// ou sans cle est ignoree ; une longueur qui deborde arrete la lecture.
    public init(brut: Data) {
        var v: [String: Data] = [:]
        let o = [UInt8](brut)
        var i = 0
        while i < o.count {
            let n = Int(o[i])
            i += 1
            guard i + n <= o.count else { break }
            let chaine = o[i..<(i + n)]
            i += n
            let egal = chaine.firstIndex(of: UInt8(ascii: "="))
            let octetsCle = chaine[chaine.startIndex..<(egal ?? chaine.endIndex)]
            guard !octetsCle.isEmpty, let cle = String(bytes: octetsCle, encoding: .utf8)?.lowercased() else { continue }
            let valeur = egal.map { Data(chaine[chaine.index(after: $0)...]) } ?? Data()
            if v[cle] == nil { v[cle] = valeur }
        }
        valeurs = v
    }

    public subscript(cle: String) -> Data? { valeurs[cle.lowercased()] }

    /// Valeur en texte UTF-8 (nil si absente ou invalide).
    public func texte(_ cle: String) -> String? {
        self[cle].flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Valeur entiere ecrite en decimal ("6000"), nil sinon.
    public func entier(_ cle: String) -> Int? {
        texte(cle).flatMap { Int($0) }
    }

    public var estVide: Bool { valeurs.isEmpty }
}

extension ChampsTXT: Codable {
    /// Format des captures : une valeur faite d'ASCII imprimable s'ecrit en texte
    /// (sauf si elle commence par "hex:"), toute autre en "hex:" + hexadecimal.
    public init(from decoder: Decoder) throws {
        let brut = try decoder.singleValueContainer().decode([String: String].self)
        var v: [String: Data] = [:]
        for (cle, texte) in brut {
            if texte.hasPrefix("hex:") {
                guard let d = Data(hexa: String(texte.dropFirst(4))) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                            debugDescription: "hexadecimal invalide pour \(cle)"))
                }
                v[cle.lowercased()] = d
            } else {
                v[cle.lowercased()] = Data(texte.utf8)
            }
        }
        valeurs = v
    }

    public func encode(to encoder: Encoder) throws {
        var brut: [String: String] = [:]
        for (cle, d) in valeurs {
            let texte = String(decoding: d, as: UTF8.self)
            let imprimable = d.allSatisfy { (0x20...0x7E).contains($0) } && !texte.hasPrefix("hex:")
            brut[cle] = imprimable ? texte : "hex:" + d.hexa
        }
        var c = encoder.singleValueContainer()
        try c.encode(brut)
    }
}

extension Data {
    /// "4B36A2" -> [0x4B, 0x36, 0xA2] ; nil si longueur impaire ou caractere invalide.
    init?(hexa: String) {
        var octets: [UInt8] = []
        var haut: UInt8?
        for c in hexa.utf8 {
            let v: UInt8
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): v = c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): v = c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): v = c - UInt8(ascii: "A") + 10
            default: return nil
            }
            if let h = haut {
                octets.append(h << 4 | v)
                haut = nil
            } else {
                haut = v
            }
        }
        guard haut == nil else { return nil }
        self.init(octets)
    }

    /// Hexadecimal majuscule ("4B36A2").
    var hexa: String { map { String(format: "%02X", $0) }.joined() }
}
