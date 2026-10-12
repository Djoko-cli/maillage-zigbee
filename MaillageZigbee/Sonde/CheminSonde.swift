import Foundation
import MaillageCoeur

/// Reglage « Liaison » de la sonde (spec sonde Wi-Fi, 4.2), garde dans les preferences.
enum ReglageChemin: String, CaseIterable, Sendable {
    case automatique, usb, reseau

    var libelle: String {
        switch self {
        case .automatique: String(localized: "Automatique")
        case .usb: String(localized: "USB")
        case .reseau: String(localized: "Wi-Fi")
        }
    }
}

/// Par ou passe la sonde connectee.
enum Acces: Equatable, Sendable {
    case usb, reseau

    var libelle: String {
        switch self {
        case .usb: String(localized: "USB")
        case .reseau: String(localized: "Wi-Fi")
        }
    }
}

enum CheminSonde {
    /// Cle des preferences du reglage.
    static let cleReglage = "sondeChemin"
    /// Trousseau des cles de l'acces par le reseau : compte = adresse longue de la sonde.
    static let serviceTrousseau = "fr.djoko.maillage.zigbee.sonde"

    /// Le trousseau du systeme pour les cles de l'acces par le reseau (l'app seulement, jamais les tests) : libelle
    /// « sonde Maillage Zigbee <adresse longue> (clé <empreinte>) », commentaire = empreinte (spec sonde Wi-Fi, 4.3).
    static func trousseau() -> TrousseauSysteme {
        TrousseauSysteme(service: serviceTrousseau) { ieee, cle in
            let empreinte = H1.octets(hexa: cle).map { H1.kid(cle: $0) }
            return ("sonde Maillage Zigbee \(ieee)" + (empreinte.map { " (clé \($0))" } ?? ""), empreinte)
        }
    }

    /// Le chemin a prendre, ou nil (aucun possible). Automatique : l'USB si la sonde retenue est branchee, sinon le
    /// reseau si une cle est connue et la sonde annoncee par Bonjour.
    static func choisir(_ r: ReglageChemin, branchee: Bool, cleConnue: Bool, annoncee: Bool) -> Acces? {
        let reseau = cleConnue && annoncee
        switch r {
        case .automatique: return branchee ? .usb : reseau ? .reseau : nil
        case .usb: return branchee ? .usb : nil
        case .reseau: return reseau ? .reseau : nil
        }
    }
}
