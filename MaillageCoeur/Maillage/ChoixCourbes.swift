import Foundation

/// Les courbes de l'historique que la fiche montre (etape 5, section 3), sans protocole : au plus `maximum` par defaut,
/// celles que le protocole met en tete (Zigbee : `CourbesNoeud.prioritaires`, le chemin puis les dependants) ; la case
/// « tous les liens » montre le reste. La legende en pastilles met une courbe en avant.
public enum ChoixCourbes {
    /// Courbes montrees par defaut, au plus.
    public static let maximum = 6

    /// Les cles des courbes montrees, parmi `cles` (toutes les courbes, dans leur ordre) : par defaut, les
    /// `prioritaires` qui ont une courbe, dans leur ordre, au plus `maximum` ; sans prioritaire, les `maximum` premieres
    /// courbes ; `tous` : toutes, les prioritaires d'abord.
    public static func montrees(cles: [String], prioritaires: [String], tous: Bool, maximum: Int = maximum) -> [String] {
        let presentes = Set(cles)
        var tete: [String] = []
        for k in prioritaires where presentes.contains(k) && !tete.contains(k) { tete.append(k) }
        if tous { return tete + cles.filter { !tete.contains($0) } }
        return Array((tete.isEmpty ? cles : tete).prefix(maximum))
    }

    /// Le nombre de courbes que la case « tous les liens » ajoute ; 0 : la case n'a pas d'effet.
    public static func cachees(cles: [String], prioritaires: [String], maximum: Int = maximum) -> Int {
        cles.count - montrees(cles: cles, prioritaires: prioritaires, tous: false, maximum: maximum).count
    }

    /// La courbe mise en avant apres un clic sur la pastille de `cle` : elle, ou plus rien si elle l'etait deja.
    public static func basculer(_ enAvant: String?, _ cle: String) -> String? {
        enAvant == cle ? nil : cle
    }

    /// La courbe vraiment mise en avant parmi les courbes montrees : `enAvant` s'il en fait partie, sinon nil. Une
    /// courbe choisie puis cachee (case « tous » decochee, autre periode) n'estompe plus toutes les autres.
    public static func enAvant(_ enAvant: String?, parmi montrees: [String]) -> String? {
        guard let enAvant, montrees.contains(enAvant) else { return nil }
        return enAvant
    }
}
