import Foundation

/// Le contenu propre a Zigbee des colonnes de la fiche (etape 5, section 2), tire du maillage de la sonde.
public enum FicheZigbee {
    /// Les voisins entendus d'un noeud : ses liens radio reunis par paire, chacun avec sa qualite (la moins bonne des
    /// deux mesures) et le LQI de chaque sens (le noeud, puis le voisin) ; dans l'ordre du maillage.
    public static func voisins(de id: String, maillage m: MaillageZigbee) -> [VoisinFiche] {
        MaillageZigbee.reunir(m.liens(de: id)).compactMap { l in
            guard let autre = l.autre(que: id) else { return nil }
            return VoisinFiche(id: autre, qualite: l.qualite, lqiIci: l.a == id ? l.lqiA : l.lqiB,
                               lqiLa: l.a == id ? l.lqiB : l.lqiA)
        }
    }

    /// Les dependants d'un noeud : les routeurs dont le chemin vers le pont passe directement par lui (avec la qualite
    /// de leur lien radio, s'il est dans les tables), et les appareils dont il est le parent (avec la qualite que le
    /// parent mesure ; aucune pour un parent d'avant, perimee).
    public static func dependants(de id: String, maillage m: MaillageZigbee) -> [DependantFiche] {
        let routeurs = m.chemins.filter { $0.prochain == id && $0.routeur != id }.map {
            DependantFiche(id: $0.routeur, qualite: m.lien(entre: $0.routeur, et: id)?.qualite, routeur: true)
        }
        let enfants = m.enfants(de: id).map {
            DependantFiche(id: $0.enfant, qualite: $0.dAvant ? nil : $0.qualite, routeur: false)
        }
        return routeurs + enfants
    }

    /// Les routeurs qui parlent directement au pont : ceux dont le prochain saut est le coordinateur.
    public static func routeursDirects(_ m: MaillageZigbee) -> Int {
        guard let pont = m.coordinateur?.ieee else { return 0 }
        return m.chemins.count { $0.prochain == pont }
    }

    /// La date des qualites des liens : celle des tables de voisins d'ou elles viennent (une tournee sur quatre), sinon
    /// celle du maillage.
    public static func dateQualites(_ m: MaillageZigbee) -> Date { m.dateTables ?? m.date }
}
