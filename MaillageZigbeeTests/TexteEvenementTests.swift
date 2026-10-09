import Foundation
import MaillageCoeur
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Textes des evenements et des notifications")
struct TexteEvenementTests {
    static let t = MaillageDemo.fin

    /// Chaque type d'evenement a un titre ; les pertes regroupees, leur nombre et leurs heures ; les categories de
    /// notification, et ce qu'elles sont par defaut.
    @Test func textes() throws {
        for type in TypeEvenement.allCases {
            let e = Evenement(date: Self.t, type: type, sujet: Sujet(id: "x", nom: "Interrupteur salon"), avant: "A",
                              apres: "B", periode: type == .veille ? DateInterval(start: Self.t, end: Self.t.addingTimeInterval(60)) : nil)
            #expect(!TexteEvenement.titre(e).isEmpty, "\(type)")
        }
        let pertes = (0..<5).map { k in
            Evenement(date: Self.t.addingTimeInterval(Double(k) * 60), type: .appareilDisparu,
                      sujet: Sujet(id: "A00000000000002\(k)", nom: "Appareil \(k)"))
        }
        let titre = TexteEvenement.titre(LigneJournal.pertes(pertes))
        #expect(titre.contains("5"))
        #expect(titre.contains(TexteEvenement.heure(Self.t.addingTimeInterval(240))))
        let notification = TexteEvenement.notification(AlerteAEnvoyer(categorie: .pertes, identifiant: "p", evenements: pertes))
        #expect(notification.corps.contains("Appareil 3"))
        #expect(notification.titre == String(localized: "\(5) appareils perdus"))
        let routeur = Evenement(date: Self.t, type: .routeurDisparu, sujet: Sujet(id: "x", nom: "Prise salon"))
        let r = TexteEvenement.notification(AlerteAEnvoyer(categorie: .routeurDisparu, identifiant: "r", evenements: [routeur]))
        #expect(r.titre == String(localized: "Routeur disparu") && r.corps.contains("Prise salon"))
        let vides = try #require(UserDefaults(suiteName: "vide-\(UUID())"))
        #expect(Notifications.active(.routeurDisparu, preferences: vides))
        let videsAussi = try #require(UserDefaults(suiteName: "vide-\(UUID())"))
        #expect(!Notifications.active(.informations, preferences: videsAussi))
    }

    /// Evenements du maillage de la sonde : les attentes reprennent les cles du code (independantes de la langue de
    /// l'hote).
    @Test func maillage() {
        let s = Sujet(id: NomsDemo.Ieee.detecteurAbri, nom: "Détecteur abri")
        let change = Evenement(date: Self.t, type: .parentChange, sujet: s, avant: "Ruban cuisine", apres: "Prise terrasse")
        #expect(TexteEvenement.titre(change)
                == String(localized: "\("Détecteur abri") a changé de parent : \("Ruban cuisine") → \("Prise terrasse")"))
        #expect(TexteEvenement.titre(Evenement(date: Self.t, type: .sansParent, sujet: s, avant: "Ruban cuisine"))
                == String(localized: "\("Détecteur abri") n'a plus de parent"))
        let r = Sujet(id: NomsDemo.Ieee.priseSalon, nom: "Prise salon")
        #expect(TexteEvenement.titre(Evenement(date: Self.t, type: .routeurApparu, sujet: r))
                == String(localized: "Routeur apparu : \("Prise salon")"))
        #expect(TexteEvenement.titre(Evenement(date: Self.t, type: .routeurDisparu, sujet: r))
                == String(localized: "Routeur disparu : \("Prise salon")"))
        #expect(TexteEvenement.titre(Evenement(date: Self.t, type: .appareilRevenu, sujet: s))
                == String(localized: "\("Détecteur abri") est revenu"))
    }

    /// Changements de parent regroupes : le noeud, et leur nombre dans l'heure.
    @Test func parentsRegroupes() {
        let change = Evenement(date: Self.t, type: .parentChange,
                               sujet: Sujet(id: NomsDemo.Ieee.detecteurAbri, nom: "Détecteur abri"), avant: "A", apres: "B")
        let n = 4
        #expect(TexteEvenement.titre(LigneJournal.parents(Array(repeating: change, count: n)))
                == String(localized: "\("Détecteur abri") a changé \(n) fois de parent en 1 h"))
    }

    /// Une ligne de changements de parent regroupes porte l'heure et le nom du dernier changement
    /// (celui qui la classe dans le journal), pas ceux du premier.
    @Test func parentsRegroupesDuDernierChangement() {
        let avant = Evenement(date: Self.t, type: .parentChange, sujet: Sujet(id: "x", nom: "Ancien nom"), avant: "A", apres: "B")
        let apres = Evenement(date: Self.t.addingTimeInterval(52 * 60), type: .parentChange,
                              sujet: Sujet(id: "x", nom: "Nouveau nom"), avant: "B", apres: "A")
        let ligne = LigneJournal.parents([avant, apres])
        #expect(TexteEvenement.quand(ligne) == TexteEvenement.quand(apres))
        #expect(TexteEvenement.quand(ligne) != TexteEvenement.quand(avant))
        let n = 2
        #expect(TexteEvenement.titre(ligne) == String(localized: "\("Nouveau nom") a changé \(n) fois de parent en 1 h"))
        let seul = Evenement(date: Self.t, type: .appareilNouveau, sujet: Sujet(id: "x", nom: "X"))
        #expect(TexteEvenement.quand(LigneJournal.evenement(seul)) == TexteEvenement.quand(seul))
    }

    /// Le demarrage : le nombre de routeurs et d'appareils.
    @Test func demarrage() {
        let e = Evenement(date: Self.t, type: .surveillanceDemarree, details: ["routeurs": "13", "appareils": "8"])
        #expect(TexteEvenement.titre(e) == String(localized: "Surveillance démarrée (routeurs : \("13"), appareils : \("8"))"))
    }

    /// Une ligne de changements regroupes dans la fiche : la plage horaire (le jour repete si elle passe minuit), ce
    /// qu'elle dit sans le nom du noeud, les relais (deux qui alternent, plus de deux, un seul), et un changement du detail.
    @Test func changementsRegroupes() {
        func chemin(_ minutes: Double, _ avant: String, _ apres: String) -> Evenement {
            Evenement(date: Self.t.addingTimeInterval(minutes * 60), type: .cheminChange,
                      sujet: Sujet(id: "x", nom: "Lampe"), avant: avant, apres: apres, details: ["ieee": "x"])
        }
        let groupe = [chemin(0, "A", "B"), chemin(10, "B", "A"), chemin(20, "A", "B"), chemin(30, "B", "A")]
        let debut = Self.t, fin = Self.t.addingTimeInterval(30 * 60)
        if Calendar.current.isDate(debut, inSameDayAs: fin) {
            #expect(TexteEvenement.plage(groupe)
                    == "\(TexteEvenement.jour(debut)) \(TexteEvenement.heure(debut)) – \(TexteEvenement.heure(fin))")
        }
        let minuit = Calendar.current.startOfDay(for: Self.t).addingTimeInterval(24 * 3600 - 600)
        let traverse = [Evenement(date: minuit, type: .cheminChange), Evenement(date: minuit.addingTimeInterval(1200), type: .cheminChange)]
        #expect(TexteEvenement.plage(traverse).components(separatedBy: " – ")[1].contains(TexteEvenement.jour(minuit.addingTimeInterval(1200))),
                "le jour repete passe minuit")
        let n = 4
        #expect(TexteEvenement.changements(.chemins(groupe)) == String(localized: "a changé \(n) fois de chemin"))
        #expect(TexteEvenement.changements(.parents(groupe)) == String(localized: "a changé \(n) fois de parent"))
        #expect(TexteEvenement.changements(.evenement(groupe[0])).isEmpty)
        let a = "A"
        #expect(TexteEvenement.resume(Regroupement.resumeRelais(groupe)) == "A ⇄ B · " + String(localized: "finit sur \(a)"))
        let c = "C"
        let trois = [chemin(0, "A", "B"), chemin(5, "B", "C"), chemin(9, "C", "B")]
        let b = "B"
        #expect(TexteEvenement.resume(Regroupement.resumeRelais(trois)) == "A → B → C · " + String(localized: "finit sur \(b)"))
        #expect(TexteEvenement.resume(ResumeRelais(relais: [c], dernier: c)) == String(localized: "finit sur \(c)"))
        #expect(TexteEvenement.resume(ResumeRelais(relais: [], dernier: nil)).isEmpty)
        #expect(TexteEvenement.changement(groupe[0]) == "\(TexteEvenement.heure(Self.t)) → B")
        #expect(TexteEvenement.changement(Evenement(date: Self.t, type: .cheminChange)) == "\(TexteEvenement.heure(Self.t)) → ?")
    }
}
