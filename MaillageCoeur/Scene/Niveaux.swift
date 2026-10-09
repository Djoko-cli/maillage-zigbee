import Foundation

/// Niveaux de la maison (polissage C, section 1) : chaque plateau est un etage, sur son propre niveau, ou
/// une zone a cote d'un etage, l'etage principal du niveau qu'elle partage, dans ou hors de la maison.
/// Les niveaux vont du bas vers le haut, dans l'ordre des etages ; dans un niveau, l'etage principal vient
/// d'abord, puis ses zones a cote, dans l'ordre garde.
///
/// Les choix gardes (`PlacesGardees.Maison.aCote`) sont resolus sur les plateaux de la scene :
/// - un etage principal absent de la scene : la zone redevient un etage, a sa place dans l'ordre (son choix
///   reste dans le fichier) ;
/// - une chaine (A a cote de B, B a cote de C) : A et B sont a cote de C ;
/// - une boucle : ses plateaux redeviennent des etages ;
/// - une zone a cote d'elle-meme : le choix est ignore.
public struct Niveaux: Hashable, Sendable {
    /// Plateaux de chaque niveau, du bas vers le haut : l'etage principal, puis ses zones a cote.
    public let liste: [[String]]
    /// Zones a cote, resolues : la cle de chacune -> son etage principal, et si elle est hors de la maison.
    public let aCote: [String: PlacesGardees.ACote]

    /// `cles` : les plateaux de la scene, dans l'ordre garde, du bas vers le haut ; `choix` : les choix gardes.
    public init(_ cles: [String], aCote choix: [String: PlacesGardees.ACote]) {
        let presents = Set(cles)
        // Le plateau dont `x` partage le niveau, d'apres son choix : ni lui-meme, ni un plateau absent.
        func suivant(_ x: String) -> String? {
            guard let a = choix[x], a.etage != x, presents.contains(a.etage) else { return nil }
            return a.etage
        }
        // Les plateaux d'une boucle redeviennent des etages.
        var boucles = Set<String>()
        for c in cles {
            var chemin: [String] = []
            var rang: [String: Int] = [:]
            var x: String? = c
            while let y = x, rang[y] == nil {
                rang[y] = chemin.count
                chemin.append(y)
                x = suivant(y)
            }
            if let y = x, let k = rang[y] { boucles.formUnion(chemin[k...]) }
        }
        // L'etage principal d'un plateau : le bout de sa chaine (lui-meme pour un etage).
        func principal(_ c: String) -> String {
            var x = c
            while !boucles.contains(x), let y = suivant(x) { x = y }
            return x
        }
        var resolus: [String: PlacesGardees.ACote] = [:]
        for c in cles {
            let p = principal(c)
            if p != c, let a = choix[c] { resolus[c] = PlacesGardees.ACote(etage: p, dehors: a.dehors) }
        }
        aCote = resolus
        liste = cles.filter { resolus[$0] == nil }.map { e in [e] + cles.filter { resolus[$0]?.etage == e } }
    }

    /// Tous les plateaux, niveau par niveau, du bas vers le haut.
    public var plateaux: [String] { liste.flatMap { $0 } }

    /// Le niveau d'un plateau (0 en bas) ; nil s'il n'est pas dans la scene.
    public func niveau(_ cle: String) -> Int? { liste.firstIndex { $0.contains(cle) } }

    /// Le plateau est un etage, l'etage principal de son niveau.
    public func estPrincipal(_ cle: String) -> Bool { liste.contains { $0.first == cle } }

    /// La zone a cote est hors de la maison.
    public func dehors(_ cle: String) -> Bool { aCote[cle]?.dehors == true }
}

/// Ce que les places gardent des niveaux d'une maison (polissage C, section 1.2) : l'ordre de ses plateaux,
/// du bas vers le haut, zones a cote comprises, et le choix de chaque zone a cote.
public struct Rangement: Hashable, Sendable {
    public var ordre: [String]
    public var aCote: [String: PlacesGardees.ACote]

    public init(ordre: [String], aCote: [String: PlacesGardees.ACote]) {
        self.ordre = ordre
        self.aCote = aCote
    }
}

extension Rangement {
    /// Le nouvel ordre `nouveau`, fondu dans l'ordre garde `garde` (polissage D, section 4) : les plateaux du nouvel
    /// ordre y sont dans le leur ; un plateau du garde absent du nouveau, absent de la scene, y garde son rang relatif,
    /// juste apres celui qui le precedait dans le garde (en tete s'il n'en avait pas).
    public static func fondre(_ nouveau: [String], dans garde: [String]) -> [String] {
        var r = nouveau
        var precedent: String?
        for c in garde {
            if !r.contains(c) {
                let i = precedent.flatMap { r.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                r.insert(c, at: i)
            }
            precedent = c
        }
        return r
    }
}

/// Les operations du menu du clic droit (polissage C, section 1.3) : chacune rend le nouvel ordre des
/// plateaux de la scene et les nouveaux choix, ou nil quand elle n'a pas lieu (un article grise, ou deja
/// coche). Les choix des plateaux de la scene y sont ceux qui valent (`aCote`, resolus) : une chaine est
/// remise a plat, une boucle et une zone a cote d'elle-meme sont oubliees ; ceux des plateaux absents
/// restent tels quels.
extension Niveaux {
    /// « Monter d'un etage » (+1), « Descendre d'un etage » (-1) : le niveau entier de l'etage `cle`, zones a
    /// cote comprises, change de place avec le niveau voisin. Rien pour une zone a cote, ni en haut et en bas
    /// de la pile.
    public func deplacer(_ cle: String, de pas: Int, choix: [String: PlacesGardees.ACote]) -> Rangement? {
        guard estPrincipal(cle), let i = niveau(cle), liste.indices.contains(i + pas) else { return nil }
        var l = liste
        l.swapAt(i, i + pas)
        return Rangement(ordre: l.flatMap { $0 }, aCote: aPlat(choix))
    }

    /// « Au meme niveau que » l'etage principal du niveau `i` : la zone passe a cote de lui, dans la maison,
    /// juste apres le groupe de cet etage ; ses propres zones a cote la suivent. Rien pour le niveau ou la
    /// zone est deja (l'article coche), ni pour un etage et son propre niveau.
    public func rejoindre(_ cle: String, niveau i: Int, choix: [String: PlacesGardees.ACote]) -> Rangement? {
        guard let n = niveau(cle), liste.indices.contains(i), n != i else { return nil }
        let p = liste[i][0]
        let groupe = estPrincipal(cle) ? liste[n] : [cle]
        var r = aPlat(choix)
        r[cle] = PlacesGardees.ACote(etage: p, dehors: false)
        for z in groupe.dropFirst() { r[z] = PlacesGardees.ACote(etage: p, dehors: dehors(z)) }
        var l = liste
        l[i] += groupe
        l[n].removeAll { groupe.contains($0) }
        return Rangement(ordre: l.filter { !$0.isEmpty }.flatMap { $0 }, aCote: r)
    }

    /// « Hors de la maison » : une case a cocher, pour une zone a cote seulement.
    public func basculerDehors(_ cle: String, choix: [String: PlacesGardees.ACote]) -> Rangement? {
        guard let a = aCote[cle] else { return nil }
        var r = aPlat(choix)
        r[cle] = PlacesGardees.ACote(etage: a.etage, dehors: !a.dehors)
        return Rangement(ordre: plateaux, aCote: r)
    }

    /// « Sur son propre niveau », pour une zone a cote seulement : elle redevient un etage, juste au-dessus
    /// du niveau qu'elle partageait.
    public func propreNiveau(_ cle: String, choix: [String: PlacesGardees.ACote]) -> Rangement? {
        guard aCote[cle] != nil, let n = niveau(cle) else { return nil }
        var r = aPlat(choix)
        r[cle] = nil
        var l = liste
        l[n].removeAll { $0 == cle }
        l.insert([cle], at: n + 1)
        return Rangement(ordre: l.flatMap { $0 }, aCote: r)
    }

    /// Les choix gardes, ceux des plateaux de la scene remis a plat : ceux qui valent, resolus ; un choix
    /// ignore (a cote de soi-meme, d'une boucle) est oublie ; un etage principal absent garde son choix.
    func aPlat(_ choix: [String: PlacesGardees.ACote]) -> [String: PlacesGardees.ACote] {
        var r = choix
        let presents = Set(plateaux)
        for c in plateaux {
            if let a = aCote[c] {
                r[c] = a
            } else if let a = choix[c], presents.contains(a.etage) {
                r[c] = nil
            }
        }
        return r
    }
}
