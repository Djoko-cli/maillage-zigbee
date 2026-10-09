import Foundation

/// Ce qui reste net a la selection d'un noeud Zigbee (etape 5, section 1) : la part propre a Zigbee du mode focus, que
/// le moteur generique recoit (`MiseEnAvant`).
public enum FocusZigbee {
    /// La mise en avant du noeud `id` du graphe `g` : nil s'il n'y est pas. Restent nets :
    /// - le noeud lui-meme ;
    /// - son chemin complet jusqu'au pont, saut par saut, en suivant les prochains sauts (le chemin d'un routeur ; pour
    ///   un appareil final, son parent, puis le chemin du parent) ; une boucle ou un saut sans chemin l'arrete ;
    /// - ses dependants, directement : les appareils dont il est le parent et les routeurs dont le prochain saut est
    ///   lui, avec leur lien vers lui ;
    /// - si `voisins` est vrai, ses voisins entendus (ses liens radio) et ces liens.
    public static func miseEnAvant(de id: String, graphe g: GrapheReseau, voisins: Bool) -> MiseEnAvant? {
        guard g.noeud(id) != nil else { return nil }
        var m = MiseEnAvant(noeuds: [id])
        // Le chemin vers le pont.
        var x = id
        var vus: Set<String> = [id]
        while g.noeud(x)?.genre != .centre, let p = prochain(de: x, graphe: g) {
            m.ajouter(lien: x, p)
            guard vus.insert(p).inserted else { break }
            x = p
        }
        // Les dependants, et les voisins entendus.
        for l in g.liens {
            switch l.genre {
            case .parent where l.vers == id, .chemin where l.vers == id:
                m.ajouter(lien: l.de, id)
            case .radio where voisins && (l.de == id || l.vers == id):
                m.ajouter(lien: l.de, l.vers)
            default:
                break
            }
        }
        return m
    }

    /// Le prochain saut d'un noeud vers le pont dans le graphe : le chemin d'un routeur, sinon son parent (appareil
    /// final) ; nil sans l'un ni l'autre.
    static func prochain(de x: String, graphe g: GrapheReseau) -> String? {
        if let c = g.chemin(de: x) { return c.vers }
        guard g.noeud(x)?.routeur != true else { return nil }
        return g.parent(de: x)
    }

    /// Les dependants directs d'un noeud, par leur lien vers lui : les routeurs dont le prochain saut est lui, et les
    /// appareils dont il est le parent.
    public static func dependants(de id: String, graphe g: GrapheReseau) -> [GrapheReseau.Lien] {
        g.liens.filter { ($0.genre == .chemin || $0.genre == .parent) && $0.vers == id }
    }
}
