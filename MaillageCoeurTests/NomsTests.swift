import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Noms : surnoms, noms du pont, adresse longue")
struct NomsTests {
    typealias I = NomsDemo.Ieee

    /// Maison de demo : un faux reseau Hue ; chaque appareil a une adresse longue inventee (`A0000000000000xx`), une
    /// piece, et une pile s'il n'est pas sur secteur. Sans zones (le pont n'a pas d'etages) ; la maison etagee des
    /// essais de la vue range les memes pieces sur quatre etages, et son choix de niveau, en memoire, met le jardin a
    /// cote du rez-de-chaussee, hors de la maison.
    @Test func maisonDeDemo() {
        let m = NomsDemo.maison
        #expect(m.accessoires.count == 21, "le pont, 13 lampes et prises, 7 appareils finaux")
        #expect(m.zones == nil && NomsDemo.maisonEtagee.zones == NomsDemo.zones)
        #expect(m.domicile == NomsDemo.domicile)
        #expect(m.accessoires.allSatisfy { ($0.ieee ?? "").hasPrefix("A0000000000000") && $0.ieee?.count == 16 })
        #expect(Set(m.accessoires.compactMap(\.ieee)).count == m.accessoires.count, "une adresse par appareil")
        #expect(Set(m.accessoires.compactMap(\.piece)) == Set(NomsDemo.zones.flatMap(\.pieces)))
        #expect(NomsDemo.places().rangement(NomsDemo.domicile) == Rangement(ordre: [], aCote: [:]), "aucune place")
        #expect(NomsDemo.places(etagee: true).rangement(NomsDemo.domicile)
                == Rangement(ordre: ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage", "zone:Combles"],
                             aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)]))
        #expect(NomsDemo.places(etagee: true, dehors: false).rangement(NomsDemo.domicile).aCote["zone:Jardin"]?.dehors
                == false)
        // Sur secteur : ni lampe, ni prise, ni pont ne porte une pile.
        let surSecteur: Set<String> = ["Lampe", "Prise", "Pont"]
        let piles = m.accessoires.filter { surSecteur.contains($0.categorie ?? "") && $0.batterie != nil }.map(\.nom)
        #expect(piles.isEmpty, "sur secteur, sans pile : \(piles)")
        #expect(m.accessoires.filter { $0.batterie?.faible == true }.map(\.nom).sorted()
                == ["Capteur grenier", "Télécommande chambre"])
    }

    /// Le pont par l'adresse longue, sans egard a la casse.
    @Test func accessoireParAdresseLongue() {
        let m = NomsDemo.maison
        #expect(m.accessoire(ieee: I.lampeBureau)?.nom == "Lampe bureau")
        #expect(m.accessoire(ieee: I.lampeArcade.lowercased())?.nom == "Lampe arcade")
        #expect(m.accessoire(ieee: I.sonde) == nil, "la sonde n'est pas un appareil du pont")
    }

    /// Priorite des noms : le surnom, puis le nom sur le pont, puis l'adresse longue ; un surnom vide est ignore.
    @Test func priorite() {
        #expect(ResolveurNoms().nom(ieee: I.lampeBureau) == I.lampeBureau, "l'adresse longue a defaut")
        #expect(ResolveurNoms().nomConnu(ieee: I.lampeBureau) == nil)
        let pont = ResolveurNoms(maison: NomsDemo.maison)
        #expect(pont.nom(ieee: I.lampeBureau) == "Lampe bureau")
        #expect(pont.accessoire(ieee: I.lampeBureau)?.piece == "Bureau")
        let surnom = ResolveurNoms(surnoms: [I.lampeBureau: "Lampe de travail"], maison: NomsDemo.maison)
        #expect(surnom.nom(ieee: I.lampeBureau) == "Lampe de travail")
        #expect(ResolveurNoms(surnoms: [I.lampeBureau: ""], maison: NomsDemo.maison).nom(ieee: I.lampeBureau)
                == "Lampe bureau", "surnom vide ignore")
    }

    /// Le releve garde : il se relit tel quel ; une version plus recente est refusee.
    @Test func fichierNomsJSON() throws {
        let d = try NomsDemo.maison.donnees()
        #expect(try NomsMaison.lire(d) == NomsDemo.maison)
        var futur = NomsDemo.maison
        futur.version = 2
        #expect(throws: NomsMaison.Erreur.versionTropRecente(2)) { try NomsMaison.lire(try futur.donnees()) }
    }

    /// Les champs facultatifs (firmware, adresse longue, batterie, zones) : absents, ils se lisent nil ; presents, ils
    /// sont gardes. Sans zones, le champ n'est pas ecrit.
    @Test func contratChampsFacultatifs() throws {
        let nu = #"{"accessoires":[{"nom":"Lampe"}],"date":"2026-10-08T12:00:00.000Z","version":1}"#
        let a = try #require(try NomsMaison.lire(Data(nu.utf8)).accessoires.first)
        #expect(a.firmware == nil && a.ieee == nil && a.batterie == nil)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let n = NomsMaison(date: date, domicile: "Pont inventé", accessoires: [
            AccessoireMaison(nom: "Lampe", piece: "Salon", modele: "Hue", firmware: "1.4.2", ieee: "A0000000000000B1"),
            AccessoireMaison(nom: "Interrupteur", ieee: "A0000000000000B2", batterie: BatterieMaison(alerte: true)),
        ], zones: [ZoneMaison(nom: "Étage", pieces: ["Salon"])])
        #expect(try NomsMaison.lire(try n.donnees()) == n)
        #expect(try NomsMaison.lire(try NomsMaison(date: date, zones: []).donnees()).zones == [])
        #expect(!String(decoding: try NomsMaison(date: date).donnees(), as: UTF8.self).contains("zones"))
        #expect(NomsMaison.versionActuelle == 1)
    }

    /// Un etat de charge inconnu (version plus recente) ne rend pas le releve illisible : seule la charge est perdue.
    @Test func chargeInconnue() throws {
        let json = #"{"accessoires":[{"batterie":{"charge":"sansFil","niveau":40},"nom":"Store"}],"date":"2026-09-28T12:00:00.000Z","version":1}"#
        #expect(try NomsMaison.lire(Data(json.utf8)).accessoires.first?.batterie == BatterieMaison(niveau: 40))
    }

    /// Faible : l'appareil le signale, ou son niveau est a 20 % ou moins.
    @Test func batterieFaible() {
        #expect(BatterieMaison(niveau: 20).faible)
        #expect(!BatterieMaison(niveau: 21).faible)
        #expect(BatterieMaison(niveau: 90, alerte: true).faible, "l'appareil le signale")
        #expect(BatterieMaison(alerte: true).faible, "alerte sans niveau")
        #expect(!BatterieMaison(alerte: false).faible)
        #expect(!BatterieMaison().faible)
    }

    @Test func fichierSurnoms() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let url = dossier.appendingPathComponent("sous/surnoms.json")
        #expect(Surnoms.lire(url) == [:], "absent")
        try Surnoms.ecrire([I.lampeBureau: "Lampe de travail"], dans: url)
        #expect(Surnoms.lire(url) == [I.lampeBureau: "Lampe de travail"])
        try Data("pas du json".utf8).write(to: url)
        #expect(Surnoms.lire(url) == [:], "illisible")
    }
}
