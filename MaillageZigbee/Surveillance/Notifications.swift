import Foundation
import MaillageCoeur
import UserNotifications
import os

/// Notifications du systeme (le mode Concentration s'applique de lui-meme).
/// Une categorie se coupe dans les reglages ; une notification de meme
/// identifiant remplace la precedente (pertes groupees). Un refus ou un echec
/// du systeme est consigne dans le journal du Mac (Console, sous-systeme
/// fr.djoko.maillage.zigbee), jamais perdu en silence. Presentees aussi quand une
/// fenetre de l'app est au premier plan.
@MainActor
final class Notifications {
    nonisolated static let journal = Logger(subsystem: "fr.djoko.maillage.zigbee", category: "notifications")
    /// Delegue du centre de notifications, retenu ici : le centre ne le garde qu'en reference faible.
    private let presentation = PresentationAuPremierPlan()

    static func cle(_ c: CategorieAlerte) -> String { "notification.\(c.rawValue)" }

    static func active(_ c: CategorieAlerte, preferences: UserDefaults = .standard) -> Bool {
        preferences.object(forKey: cle(c)) as? Bool ?? c.parDefaut
    }

    func demanderAutorisation() {
        UNUserNotificationCenter.current().delegate = presentation
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { accordee, erreur in
            if let erreur {
                Self.journal.error("autorisation des notifications : \(erreur.localizedDescription, privacy: .public)")
            } else if !accordee {
                Self.journal.notice("notifications refusees : rien ne sera presente")
            }
        }
    }

    func presenter(_ alertes: [AlerteAEnvoyer]) {
        for a in alertes where Self.active(a.categorie) {
            let (titre, corps) = TexteEvenement.notification(a)
            let contenu = UNMutableNotificationContent()
            contenu.title = titre
            contenu.body = corps
            if a.categorie != .informations { contenu.sound = .default }
            let identifiant = a.identifiant
            let requete = UNNotificationRequest(identifier: identifiant, content: contenu, trigger: nil)
            UNUserNotificationCenter.current().add(requete) { erreur in
                if let erreur {
                    Self.journal.error("notification \(identifiant, privacy: .public) non presentee : \(erreur.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

/// Sans delegue, macOS tait les notifications tant qu'une fenetre de l'app a
/// le focus : celui-ci les presente toujours (banniere, son, centre de notifications).
@MainActor
final class PresentationAuPremierPlan: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
