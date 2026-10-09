import Foundation

/// Categories de notifications (cases des reglages).
public enum CategorieAlerte: String, Codable, Hashable, Sendable, CaseIterable {
    /// Routeur disparu du maillage (par defaut : oui).
    case routeurDisparu
    /// Au moins 3 appareils perdus en 10 min, une notification groupee (par defaut : oui).
    case pertes
    /// Le reste (par defaut : non).
    case informations

    public var parDefaut: Bool { self != .informations }
}

/// Notification a presenter ; un meme identifiant remplace la precedente.
public struct AlerteAEnvoyer: Hashable, Sendable {
    public var categorie: CategorieAlerte
    public var identifiant: String
    public var evenements: [Evenement]

    public init(categorie: CategorieAlerte, identifiant: String, evenements: [Evenement]) {
        self.categorie = categorie
        self.identifiant = identifiant
        self.evenements = evenements
    }
}

/// Decide des notifications a partir des nouveaux evenements : un routeur disparu, tout de suite ; les pertes
/// d'appareils, regroupees (au moins 3 dans une fenetre de 10 min, une notification qui se remplace) ; le reste, une
/// par evenement, sauf le demarrage et la veille.
public struct Alertes: Sendable {
    public static let seuilPertes = 3

    private var debutFenetre: Date?
    /// Identifiant de la notification groupee, fixe a l'ouverture de la fenetre
    /// (d'apres sa premiere perte) : une perte datee plus tot ne le change pas.
    private var identifiantPertes: String?
    private var pertes: [Evenement] = []

    public init() {}

    public mutating func traiter(_ evenements: [Evenement]) -> [AlerteAEnvoyer] {
        var sortie: [AlerteAEnvoyer] = []
        var pertesModifiees = false
        for e in evenements {
            if Regroupement.estPerte(e) {
                if let d = debutFenetre, abs(e.date.timeIntervalSince(d)) < Regroupement.fenetre {
                    pertes.append(e)
                    debutFenetre = min(d, e.date)
                } else {
                    debutFenetre = e.date
                    identifiantPertes = "pertes-\(Int(e.date.timeIntervalSince1970))"
                    pertes = [e]
                }
                pertesModifiees = true
            } else {
                switch e.type {
                case .routeurDisparu:
                    sortie.append(AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: e.id, evenements: [e]))
                case .surveillanceDemarree, .veille:
                    break
                default:
                    sortie.append(AlerteAEnvoyer(categorie: .informations, identifiant: e.id, evenements: [e]))
                }
            }
        }
        if pertesModifiees, let identifiant = identifiantPertes, pertes.count >= Self.seuilPertes {
            sortie.append(AlerteAEnvoyer(categorie: .pertes, identifiant: identifiant,
                                         evenements: pertes.sorted { $0.date < $1.date }))
        }
        return sortie
    }
}
