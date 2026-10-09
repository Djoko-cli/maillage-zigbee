import Foundation

/// Mode focus du graphe (etape 5, section 1) : les noeuds et les liens qui restent nets a la selection d'un noeud ; le
/// reste s'estompe, sans disparaitre. Generique : le moteur ne connait que ces deux ensembles et estompe le reste ; le
/// protocole fournit la fonction qui les calcule depuis son graphe (Zigbee : `FocusZigbee.miseEnAvant`).
public struct MiseEnAvant: Hashable, Sendable {
    /// Noeuds nets, par identifiant.
    public var noeuds: Set<String>
    /// Liens nets, par paire de bouts, sans ordre ni genre (`cle(_:_:)`) : un lien radio et un chemin entre les memes
    /// noeuds restent nets ensemble (en mode « tous », le lien radio porte le chemin).
    public var liens: Set<String>

    public init(noeuds: Set<String> = [], liens: Set<String> = []) {
        self.noeuds = noeuds
        self.liens = liens
    }

    /// Opacite d'un noeud ou d'un lien estompe, pleinement : assez basse pour que le chemin se detache, assez haute pour
    /// que le reste du reseau se devine sur le fond sombre.
    public static let opaciteEstompee = 0.18

    /// Le facteur d'opacite d'un estompement `e`, de 0 (net : 1) a 1 (estompe : `opaciteEstompee`).
    public static func facteur(_ e: Double) -> Double {
        if e <= 0 { return 1 }
        if e >= 1 { return opaciteEstompee }
        return 1 - (1 - opaciteEstompee) * e
    }

    /// La cle d'un lien entre `a` et `b`, dans un ordre ou dans l'autre.
    public static func cle(_ a: String, _ b: String) -> String {
        a < b ? a + "|" + b : b + "|" + a
    }

    /// La cle d'un lien du graphe.
    public static func cle(_ l: GrapheReseau.Lien) -> String { cle(l.de, l.vers) }

    /// Met en avant le lien entre `a` et `b`, et ses deux bouts.
    public mutating func ajouter(lien a: String, _ b: String) {
        noeuds.insert(a)
        noeuds.insert(b)
        liens.insert(Self.cle(a, b))
    }

    public func contient(lien l: GrapheReseau.Lien) -> Bool { liens.contains(Self.cle(l)) }

    /// L'estompement vise de chaque noeud et de chaque lien de `noeuds` et `liens` sous `m` : 0 (net) pour ce qui est
    /// mis en avant, 1 pour le reste ; tout a 0 sans mise en avant (nil).
    public static func cibles(_ m: MiseEnAvant?, noeuds: [String], liens: [String])
        -> (noeuds: [String: Double], liens: [String: Double]) {
        guard let m else { return ([:], [:]) }
        var n: [String: Double] = [:], l: [String: Double] = [:]
        for id in noeuds where !m.noeuds.contains(id) { n[id] = 1 }
        for c in liens where !m.liens.contains(c) { l[c] = 1 }
        return (n, l)
    }

    /// Un pas de la transition douce des estompements `actuels` vers `cibles` (absents : 0), comme les parts de
    /// l'isolement d'une piece : `k` la part du chemin faite a cette image ; une valeur a moins de 0,001 de sa cible la
    /// prend, et une valeur nulle n'est pas gardee.
    public static func tendre(_ actuels: [String: Double], vers cibles: [String: Double], k: Double) -> [String: Double] {
        var r: [String: Double] = [:]
        for cle in Set(actuels.keys).union(cibles.keys) {
            let c = cibles[cle] ?? 0
            var f = actuels[cle] ?? 0
            f += (c - f) * min(1, max(0, k))
            if abs(c - f) < 1e-3 { f = c }
            if f != 0 { r[cle] = f }
        }
        return r
    }
}
