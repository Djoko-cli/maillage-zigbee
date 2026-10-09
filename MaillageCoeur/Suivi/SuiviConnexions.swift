import Foundation

/// Suit l'etat de connexion des appareils vu par le pont Hue (`zigbee_connectivity.status`), de lecture en lecture, et
/// en tire « appareil disparu » et « appareil revenu » (spec de l'app, section 7). Un appareil se suit par son adresse
/// longue (l'id de son sujet, et `details["ieee"]`).
/// - La premiere lecture d'un pont est un etat initial : aucun evenement. Un autre pont (`domicile`) repart de zero.
/// - `connected` puis `disconnected`, `connectivity_issue` ou `unidirectional_incoming` **a deux lectures de suite**
///   (choix de Majid, 09/10 : un decrochage d'une seule lecture n'alerte pas) : « disparu », date de la premiere de
///   ces deux lectures ; le retour a `connected` ensuite : « revenu ». Perdu a une lecture puis de nouveau
///   `connected` : aucun evenement.
/// - Un etat absent, ou que l'app ne connait pas (`unknown`), ne change rien. Un appareil sorti de la liste du pont
///   (retire de l'app Hue) n'est plus suivi : ni disparu, ni revenu ; s'il y revient, il repart de son etat d'alors.
/// - Une lecture echouee (pont injoignable) n'arrive pas ici : elle ne change aucun etat.
public struct SuiviConnexions: Sendable {
    /// L'etat retenu d'un appareil : joignable (`connected`), perdu a une seule lecture (depuis cette date), ou perdu.
    private enum Etat: Sendable, Equatable {
        case joignable, suspect(Date), perdu
    }

    /// Ce qu'une lecture dit d'un appareil.
    private enum Lu: Sendable {
        case joignable, perdu
    }

    private var demarre = false
    private var domicile: String?
    private var etats: [String: Etat] = [:]

    public init() {}

    private static func etat(_ c: ConnexionZigbee?) -> Lu? {
        switch c {
        case .connecte?: .joignable
        case .deconnecte?, .problemeConnexion?, .entrantSeul?: .perdu
        case .inconnue?, nil: nil
        }
    }

    /// Evenements d'une lecture reussie du pont, dates de cette lecture (`NomsMaison.date`) ; `nom` : le nom affiche
    /// d'un appareil, par son adresse longue.
    public mutating func integrer(_ n: NomsMaison, nom: (String) -> String) -> [Evenement] {
        let dom = n.domicile?.uppercased()
        if demarre && dom != domicile {
            etats = [:]
            demarre = false
        }
        let initial = !demarre
        var nouveaux: [String: Etat] = [:]
        var ev: [Evenement] = []
        for a in n.accessoires {
            guard let ieee = a.ieee?.uppercased(), NoeudZigbee.cleConnue(ieee) else { continue }
            let avant = etats[ieee]
            guard let lu = Self.etat(a.connexion) else {
                // Etat inconnu a cette lecture : celui d'avant reste.
                if let avant { nouveaux[ieee] = avant }
                continue
            }
            let sujet = Sujet(id: ieee, nom: nom(ieee))
            switch (avant, lu) {
            case (nil, .joignable), (.joignable?, .joignable), (.suspect?, .joignable):
                nouveaux[ieee] = .joignable
            case (nil, .perdu), (.perdu?, .perdu):
                // Premiere lecture, ou appareil nouveau dans la liste : son etat d'alors, sans evenement.
                nouveaux[ieee] = .perdu
            case (.joignable?, .perdu):
                nouveaux[ieee] = initial ? .perdu : .suspect(n.date)
            case (.suspect(let depuis)?, .perdu):
                nouveaux[ieee] = .perdu
                ev.append(Evenement(date: depuis, type: .appareilDisparu, sujet: sujet, details: ["ieee": ieee]))
            case (.perdu?, .joignable):
                nouveaux[ieee] = .joignable
                if !initial {
                    ev.append(Evenement(date: n.date, type: .appareilRevenu, sujet: sujet, details: ["ieee": ieee]))
                }
            }
        }
        etats = nouveaux
        domicile = dom
        demarre = true
        return initial ? [] : ev.sorted { ($0.sujet?.id ?? "") < ($1.sujet?.id ?? "") }
    }
}
