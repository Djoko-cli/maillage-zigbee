import Foundation

/// Cartes des pieces (spec de la vue par pieces, section 4.2) : chaque piece est une carte qui liste
/// ses noeuds, une ligne par noeud, en 1 a 3 colonnes. Les largeurs des noms sont mesurees par
/// l'app (police et taille reelles) et passees ici, en px a l'echelle naturelle de la 2D.
public enum CartesPieces {
    /// Px par unite de la scene, a l'echelle naturelle de la 2D.
    public static let px = 24.0
    /// Au-dela, un nom est coupe, avec « … ».
    public static let longueurMax = 40

    public struct Carte: Hashable, Sendable {
        /// Largeur (x) et profondeur (z) de la carte, en unites.
        public var largeur: Double
        public var profondeur: Double
        public var colonnes: Int
        /// Centre de la pastille de chaque ligne (x, z), par rapport au centre de la carte, en unites.
        public var places: [SIMD2<Double>]
    }

    /// Une ligne : le rayon naturel de la pastille et la largeur de son nom, en px.
    public struct Ligne: Hashable, Sendable {
        public var rayon: Double
        public var largeurNom: Double

        public init(rayon: Double, largeurNom: Double) {
            self.rayon = rayon
            self.largeurNom = largeurNom
        }
    }

    /// Les badges d'un nom : la couronne du coordinateur, la lune d'un endormi, l'alerte d'un appareil injoignable ou disparu.
    public static let couronne = "👑"
    public static let lune = "☾"
    public static let alerte = "⚠︎"

    /// Le nom affiche d'un noeud : son nom, deja coupe, puis la couronne du coordinateur, ☾ endormi, ⚠︎ injoignable ou disparu.
    public static func texte(_ nom: String, chef: Bool, endormi: Bool, alerte a: Bool) -> String {
        var t = nom
        if chef { t += " " + couronne }
        if endormi { t += " " + lune }
        if a { t += " " + alerte }
        return t
    }

    /// Le texte que la carte reserve au nom d'un noeud (polissage D, section 2) : son nom et tous les badges qu'il peut
    /// porter, affiches ou non. La couronne va a un noeud qui route (le coordinateur), ☾ a un
    /// noeud qui ne route pas (un routeur n'est jamais endormi), ⚠︎ a tous.
    public static func texteReserve(_ nom: String, routeur: Bool) -> String {
        texte(nom, chef: routeur, endormi: !routeur, alerte: true)
    }

    /// Un nom de plus de 40 caracteres : ses 39 premiers, puis « … ».
    public static func couper(_ nom: String) -> String {
        nom.count > longueurMax ? String(nom.prefix(longueurMax - 1)) + "…" : nom
    }

    /// Hauteur d'une ligne (px).
    public static func hauteurLigne(_ rayon: Double) -> Double { max(30, 2 * rayon + 12) }

    /// Carte d'une piece, ses lignes dans l'ordre. Colonnes remplies dans l'ordre des lignes, sans
    /// colonne vide ; largeur d'une colonne : 14 + 2 rmax + 9 + le nom le plus long + 14 px ;
    /// hauteur : les lignes de la plus haute colonne + 16 px. On garde le nombre de colonnes dont le
    /// rapport largeur / hauteur est le plus proche de 1,3 (au sens de |log(l / h / 1,3)|). Une
    /// pastille est a 14 + rmax px du bord gauche de sa colonne, au milieu de sa ligne ; la
    /// premiere ligne commence a 8 px du haut.
    public static func carte(_ lignes: [Ligne]) -> Carte {
        guard !lignes.isEmpty else { return Carte(largeur: 1, profondeur: 1, colonnes: 1, places: []) }
        var meilleur: (score: Double, colonnes: [[Int]], larg: [Double], w: Double, h: Double)?
        for n in 1...min(3, lignes.count) {
            let parColonne = (lignes.count + n - 1) / n
            if (n - 1) * parColonne >= lignes.count { continue }
            let colonnes = (0..<n).map { c in Array((c * parColonne)..<min((c + 1) * parColonne, lignes.count)) }
            let larg = colonnes.map { c in
                14 + 2 * c.map { lignes[$0].rayon }.max()! + 9 + c.map { lignes[$0].largeurNom }.max()! + 14
            }
            let h = colonnes.map { c in c.reduce(0) { $0 + hauteurLigne(lignes[$1].rayon) } }.max()! + 16
            let w = larg.reduce(0, +)
            let score = abs(log(w / h / 1.3))
            if meilleur.map({ score < $0.score }) ?? true { meilleur = (score, colonnes, larg, w, h) }
        }
        let m = meilleur!
        var places = [SIMD2<Double>](repeating: .zero, count: lignes.count)
        var x0 = 0.0
        for (c, colonne) in m.colonnes.enumerated() {
            let rmax = colonne.map { lignes[$0].rayon }.max()!
            var y = 8.0
            for i in colonne {
                let h = hauteurLigne(lignes[i].rayon)
                places[i] = SIMD2((x0 + 14 + rmax - m.w / 2) / px, (y + h / 2 - m.h / 2) / px)
                y += h
            }
            x0 += m.larg[c]
        }
        return Carte(largeur: m.w / px, profondeur: m.h / px, colonnes: m.colonnes.count, places: places)
    }

    /// Carte de chaque piece de la scene ; `largeurs` : largeur du nom de chaque noeud (px), 0 a
    /// defaut.
    public static func cartes(_ scene: ScenePieces, largeurs: [String: Double]) -> [Carte] {
        scene.pieces.map { p in
            carte(p.noeuds.map { id in
                Ligne(rayon: scene.noeud(id)?.rayon ?? 7, largeurNom: largeurs[id] ?? 0)
            })
        }
    }
}
