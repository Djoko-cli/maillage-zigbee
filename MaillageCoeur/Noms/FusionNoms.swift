import Foundation

/// Noms du pont Hue et releve de Maison reunis (decision de Djoko du 08/10 : il n'utilise que l'app Maison, ou ses
/// lampes Hue arrivent par le pont). Le pont reste la source des appareils : adresse longue, etat de connexion, pile,
/// fabricant et modele. Maison donne, a chaque appareil du pont qu'on y retrouve, son nom et sa piece, et a la maison ses
/// zones (les etages) et son domicile.
///
/// Retrouver un appareil du pont dans Maison (`apparier`) :
/// 1. parmi les candidats : les accessoires de Maison de Signify ou de Philips (fabricant), et ceux qui partagent le
///    noeud Matter d'un pont Hue de Maison (accessoire de categorie pont, de Signify ou de Philips) ; le releve du
///    Passeur ne dit pas quel pont porte un accessoire ;
/// 2. d'abord par le nom, egal apres normalisation (`normaliser` : casse, accents, espaces, apostrophes) ;
/// 3. puis par le nom « souple » (`normaliserSouple`) : sans ponctuation ni petits mots de liaison (Maison porte le
///    nom de la tuile, que l'utilisateur ecrit autrement que le nom du pont : « Plafonnier de cuisine 1 » pour
///    « Plafonnier cuisine 1 ») ; les chiffres et les autres mots comptent ;
/// 4. a defaut, par la piece et le modele (nom du produit ou code du modele du pont) ;
/// 5. jamais d'appariement ambigu : deux candidats pour un appareil, ou deux appareils pour un candidat, et aucun n'est
///    apparie a cette etape.
/// Un appareil apparie prend le nom et la piece de Maison ; un autre garde ceux de l'app Hue (sa piece prend
/// l'ecriture de Maison quand Maison a la meme, a la normalisation pres : elle trouve alors son etage). `origine` le
/// dit, pour la fiche. L'identifiant HomeKit de l'accessoire de Maison apparie suit l'appareil (`idMaison`).
public enum FusionNoms {
    /// Combien d'appareils du pont Maison nomme.
    public struct Bilan: Hashable, Sendable {
        /// Retrouves dans Maison : son nom et sa piece.
        public var apparies: Int
        /// Pas retrouves : le nom et la piece de l'app Hue.
        public var nonApparies: Int

        public init(apparies: Int, nonApparies: Int) {
            self.apparies = apparies
            self.nonApparies = nonApparies
        }
    }

    public struct Resultat: Hashable, Sendable {
        /// Les noms a montrer ; nil sans noms du pont.
        public var noms: NomsMaison?
        /// nil sans noms du pont, ou sans releve de Maison reussi.
        public var bilan: Bilan?
    }

    /// Les noms du pont, nommes par Maison. Sans noms du pont : rien (Maison seule ne donne aucune adresse longue). Sans
    /// releve de Maison reussi : les noms du pont tels quels, sans origine.
    public static func fusionner(pont: NomsMaison?, maison: ReleveMaison?) -> Resultat {
        guard var n = pont else { return Resultat(noms: nil, bilan: nil) }
        guard let r = maison, r.statut == .ok else { return Resultat(noms: pont, bilan: nil) }
        let paires = apparier(pont: n.accessoires, maison: r.accessoires)
        let pieces = piecesDeMaison(r)
        func ecriture(_ piece: String?) -> String? {
            piece.map { pieces[normaliser($0)] ?? $0 }
        }
        for i in n.accessoires.indices {
            if let j = paires[i] {
                let m = r.accessoires[j]
                n.accessoires[i].nom = m.nom
                let piece = m.piece?.isEmpty == false ? m.piece : nil
                n.accessoires[i].piece = piece ?? ecriture(n.accessoires[i].piece)
                n.accessoires[i].origine = .maison
                n.accessoires[i].idMaison = m.id
            } else {
                n.accessoires[i].piece = ecriture(n.accessoires[i].piece)
                n.accessoires[i].origine = .pont
                n.accessoires[i].idMaison = nil
            }
        }
        n.accessoires.sort { ($0.nom, $0.ieee ?? "") < ($1.nom, $1.ieee ?? "") }
        if let z = r.zones, !z.isEmpty { n.zones = z }
        if let d = r.domicile, !d.isEmpty { n.domicile = d }
        return Resultat(noms: n, bilan: Bilan(apparies: paires.count, nonApparies: n.accessoires.count - paires.count))
    }

    /// Appareil du pont (indice) -> accessoire de Maison (indice), un pour un (voir le type).
    public static func apparier(pont: [AccessoireMaison], maison: [AccessoireReleve]) -> [Int: Int] {
        var libres = Set(candidats(maison))
        var paires: [Int: Int] = [:]
        let nomsMaison = maison.map { normaliser($0.nom) }
        // 1. Par le nom exact (a la normalisation pres).
        var propositions: [Int: Int] = [:]
        for (i, p) in pont.enumerated() {
            let nom = normaliser(p.nom)
            guard !nom.isEmpty else { continue }
            let trouves = libres.filter { nomsMaison[$0] == nom }
            if trouves.count == 1, let j = trouves.first { propositions[i] = j }
        }
        retenir(propositions, dans: &paires, libres: &libres)
        // 2. Par le nom souple, pour ceux qui restent : egalite et unicite des deux cotes, comme le nom exact.
        propositions = [:]
        let soupleMaison = maison.map { normaliserSouple($0.nom) }
        for (i, p) in pont.enumerated() where paires[i] == nil {
            let nom = normaliserSouple(p.nom)
            guard !nom.isEmpty else { continue }
            let trouves = libres.filter { soupleMaison[$0] == nom }
            if trouves.count == 1, let j = trouves.first { propositions[i] = j }
        }
        retenir(propositions, dans: &paires, libres: &libres)
        // 3. Par la piece et le modele, pour ceux qui restent.
        propositions = [:]
        for (i, p) in pont.enumerated() where paires[i] == nil {
            let piece = normaliser(p.piece ?? "")
            let modeles = Set([p.modele, p.idModele].compactMap { $0 }.map(normaliser).filter { !$0.isEmpty })
            guard !piece.isEmpty, !modeles.isEmpty else { continue }
            let trouves = libres.filter {
                normaliser(maison[$0].piece ?? "") == piece && modeles.contains(normaliser(maison[$0].modele ?? ""))
            }
            if trouves.count == 1, let j = trouves.first { propositions[i] = j }
        }
        retenir(propositions, dans: &paires, libres: &libres)
        return paires
    }

    /// Garde les propositions dont l'accessoire de Maison n'est demande que par un appareil du pont.
    private static func retenir(_ propositions: [Int: Int], dans paires: inout [Int: Int], libres: inout Set<Int>) {
        var demandes: [Int: Int] = [:]
        for j in propositions.values { demandes[j, default: 0] += 1 }
        for (i, j) in propositions where demandes[j] == 1 {
            paires[i] = j
            libres.remove(j)
        }
    }

    /// Accessoires de Maison qui peuvent venir du pont Hue (indices) : de Signify ou de Philips, ou sur le noeud Matter
    /// d'un pont Hue de Maison ; jamais un accessoire sans nom.
    public static func candidats(_ maison: [AccessoireReleve]) -> [Int] {
        let noeudsPonts = Set(maison.filter { $0.pont == true && deHue($0.fabricant) }.compactMap(\.noeudMatter))
        return maison.indices.filter { i in
            let a = maison[i]
            guard !normaliser(a.nom).isEmpty else { return false }
            return deHue(a.fabricant) || a.noeudMatter.map(noeudsPonts.contains) == true
        }
    }

    /// Fabricant Signify ou Philips (« Signify Netherlands B.V. », « Philips »…).
    static func deHue(_ fabricant: String?) -> Bool {
        let f = normaliser(fabricant ?? "")
        return f.contains("signify") || f.contains("philips")
    }

    /// Pieces de Maison (zones et accessoires), par leur forme normalisee : la premiere ecriture rencontree.
    static func piecesDeMaison(_ r: ReleveMaison) -> [String: String] {
        var pieces: [String: String] = [:]
        for p in (r.zones ?? []).flatMap(\.pieces) + r.accessoires.compactMap(\.piece) {
            let n = normaliser(p)
            if !n.isEmpty, pieces[n] == nil { pieces[n] = p }
        }
        return pieces
    }

    /// Forme de comparaison d'un nom : sans casse, sans accents, espaces reduits a une seule entre les mots et retires
    /// aux bords, apostrophes typographiques (que Maison ecrit souvent) en apostrophe droite.
    public static func normaliser(_ texte: String) -> String {
        var t = texte
        for a in ["\u{2019}", "\u{2018}", "\u{02BC}"] { t = t.replacingOccurrences(of: a, with: "'") }
        t = t.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Petits mots de liaison du francais, retires du nom souple : de, du, des, la, le, les, l, d (apostrophes
    /// coupees : « l'ilot », « d'appoint »), a (le « a » nu et « à », apres le pliage des accents), au, aux, en, et.
    /// Articles et prepositions que l'utilisateur ajoute ou oublie en renommant une tuile. Pas « un » ni « une » (ils
    /// comptent : « un » peut etre un numero ecrit en lettres), ni de mot porteur de sens (haut, bas, entree, droite…).
    static let motsDeLiaison: Set<String> = ["de", "du", "des", "la", "le", "les", "l", "d", "a", "au", "aux", "en", "et"]

    /// Forme de comparaison « souple » d'un nom : `normaliser`, puis tout ce qui n'est ni lettre ni chiffre
    /// (parentheses, tirets, apostrophes, virgules…) devient un espace, les mots de liaison (`motsDeLiaison`) sont retires,
    /// les espaces reduits. Les chiffres et les autres mots sont gardes tels quels. Peut etre vide.
    public static func normaliserSouple(_ texte: String) -> String {
        normaliser(texte)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !motsDeLiaison.contains($0) }
            .joined(separator: " ")
    }
}
