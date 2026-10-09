import AppKit
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Affichage de la sonde : noms, qualites, fiche, menu, reglages")
struct AffichageSondeTests {
    typealias I = NomsDemo.Ieee

    /// La fiche d'un appareil final au parent d'avant (absent des dernieres tables) dit l'age de ce parent : « parent
    /// connu il y a 40 min : Prise terrasse », sans qualite ; son role reste « Appareil final ».
    @Test func ficheDuParentDAvant() {
        var m = MaillageDemo.maillage
        let s = NomsSceneTests.surveillanceDemo()
        let maintenant = m.date.addingTimeInterval(40 * 60)
        if let i = m.parents.firstIndex(where: { $0.enfant == I.detecteurAbri }) {
            m.parents[i].dAvant = true
        }
        let age = FicheNoeud.relatif(m.date, maintenant, unites: .short)
        let ligne = FicheNoeud.ligneParent(I.detecteurAbri, maillage: m, nom: s.nom, maintenant: maintenant)
        #expect(ligne == String(localized: "parent connu \(age) : \("Prise terrasse")"))
        #expect(age.contains("40") && !age.hasPrefix("-"), "l'age relatif, jamais « -40 min » : \(age)")
        #expect(FicheNoeud.texteRole(m.noeud(I.detecteurAbri)?.type, endormi: true)
                == String(localized: "\(String(localized: "Appareil final")) · endormi"))
        // La colonne du chemin : le parent d'avant, puis le chemin par lui.
        #expect(FicheNoeud.lignesChemin(I.detecteurAbri, maillage: m, nom: s.nom, maintenant: maintenant)
                == [String(localized: "parent connu \(age) : \("Prise terrasse")"),
                    String(localized: "vers le pont : via \("Prise terrasse") · \(4) sauts")])
        // Un parent lu garde sa ligne d'avant.
        #expect(FicheNoeud.ligneParent(I.detecteurAbri, maillage: MaillageDemo.maillage, nom: s.nom)
                == String(localized: "parent \("Prise terrasse"), \(FicheNoeud.texteQualite(1))\(" (LQI 72)")"))
    }

    /// Fiche d'un noeud : le role, l'adresse courte, le parent avec la qualite du lien et son LQI ; pour un routeur, ses
    /// voisins, chaque lien avec sa qualite et les LQI des deux sens ; le chemin vers le pont ; un routeur muet, un
    /// routeur dont la table n'a pas ete lue une fois ; la date des qualites. Les attentes reprennent les cles du code.
    @Test func ficheDuMaillage() throws {
        let m = MaillageDemo.maillage
        let s = NomsSceneTests.surveillanceDemo()
        #expect(FicheNoeud.texteRole(.coordinateur) == String(localized: "Coordinateur (le pont)"))
        #expect(FicheNoeud.texteRole(.final, endormi: true)
                == String(localized: "\(String(localized: "Appareil final")) · endormi"))
        #expect(FicheNoeud.texteRole(nil) == String(localized: "Rôle inconnu"))
        #expect(FicheNoeud.texteCourt(0x0A14) == String(localized: "adresse courte \("0A14")"))
        #expect(FicheNoeud.ligneParent(I.detecteurAbri, maillage: m, nom: s.nom)
                == String(localized: "parent \("Prise terrasse"), \(FicheNoeud.texteQualite(1))\(" (LQI 72)")"))
        #expect(FicheNoeud.ligneParent(I.priseTerrasse, maillage: m, nom: s.nom) == nil, "un routeur n'a pas de parent")
        // Les voisins entendus, chacun avec les LQI des deux sens (le noeud, puis le voisin).
        let terrasse = FicheZigbee.voisins(de: I.priseTerrasse, maillage: m)
        #expect(terrasse == [VoisinFiche(id: I.rubanCuisine, qualite: 1, lqiIci: 61, lqiLa: 88)])
        #expect(FicheNoeud.texteLQIs(terrasse[0]) == String(localized: "LQI \("61") / \("88")"))
        let inconnu = try #require(FicheZigbee.voisins(de: I.inconnu, maillage: m).first)
        #expect(FicheNoeud.texteLQIs(inconnu) == String(localized: "LQI \("?") / \("66")"))
        #expect(FicheNoeud.lignesTable(I.inconnu, maillage: m) == [String(localized: "muet : sans réponse à deux tournées de suite")])
        #expect(FicheNoeud.lignesTable(I.lampeGrenier, maillage: m).isEmpty)
        // Un routeur dont la table n'a pas ete lue une fois (pas encore muet).
        var unSilence = m
        if let i = unSilence.noeuds.firstIndex(where: { $0.ieee == I.lampeGrenier }) { unSilence.noeuds[i].tableNonLue = true }
        #expect(FicheNoeud.lignesTable(I.lampeGrenier, maillage: unSilence)
                == [String(localized: "table non lue : liens vus seulement par ses voisins")])
        #expect(FicheNoeud.texteQualite(nil) == String(localized: "qualité inconnue"))
        // Le chemin vers le pont : lu (route active), suppose, d'un appareil final (par son parent).
        #expect(FicheNoeud.lignesVersPont(I.ampouleEntree, maillage: m, nom: s.nom)
                == [String(localized: "vers le pont : via \("Plafonnier salon") · \(2) sauts")])
        #expect(FicheNoeud.lignesVersPont(I.plafonnierSalon, maillage: m, nom: s.nom)
                == [String(localized: "vers le pont : direct")])
        #expect(FicheNoeud.lignesVersPont(I.pont, maillage: m, nom: s.nom).isEmpty)
        #expect(FicheNoeud.lignesVersPont(I.interrupteurSalon, maillage: m, nom: s.nom)
                == [String(localized: "vers le pont : via \("Lampe chambre") · \(4) sauts")], "parent, puis ses chemins")
        #expect(FicheNoeud.lignesVersPont(I.detecteurEntree, maillage: m, nom: s.nom)
                == [String(localized: "vers le pont : direct")], "enfant du pont")
        #expect(FicheNoeud.lignesVersPont(I.priseTerrasse, maillage: m, nom: s.nom)
                == [String(localized: "vers le pont : via \("Ruban cuisine") · \(3) sauts"),
                    String(localized: "chemin supposé (aucune route active vers le pont)")])
        // Une boucle : chemin incomplet, sans boucle infinie.
        var boucle = m
        boucle.chemins = [CheminPont(routeur: I.lampeChambre, prochain: I.lampeBureau),
                          CheminPont(routeur: I.lampeBureau, prochain: I.lampeChambre)]
        #expect(FicheNoeud.lignesVersPont(I.lampeChambre, maillage: boucle, nom: s.nom)
                == [String(localized: "vers le pont : via \("Lampe bureau") · chemin incomplet")])
        let d = Date(timeIntervalSince1970: 1_791_450_000)
        let jour = d.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
        // L'age d'un chemin lu (les routes des routeurs sont lues en plusieurs passes) ; rien pour un suppose ou sans date.
        var dates = m
        dates.chemins = [CheminPont(routeur: I.lampeChambre, prochain: I.pont, date: d),
                         CheminPont(routeur: I.lampeBureau, prochain: I.pont, suppose: true, date: d),
                         CheminPont(routeur: I.lampeGrenier, prochain: I.pont)]
        let ilYa = FicheNoeud.relatif(d, d.addingTimeInterval(720), unites: .short)
        #expect(FicheNoeud.ligneAgeChemin(I.lampeChambre, maillage: dates, maintenant: d.addingTimeInterval(720))
                == String(localized: "chemin lu \(ilYa)"))
        #expect(ilYa != FicheNoeud.relatif(d, d.addingTimeInterval(720)), "« il y a 12 min », abrege")
        #expect(FicheNoeud.ligneAgeChemin(I.lampeBureau, maillage: dates, maintenant: d) == nil)
        #expect(FicheNoeud.ligneAgeChemin(I.lampeGrenier, maillage: dates, maintenant: d) == nil)
        #expect(FicheNoeud.ligneAgeChemin(I.pont, maillage: dates, maintenant: d) == nil)
        #expect(FicheZigbee.dateQualites(m) == m.date, "les qualites de la derniere tournee")
        var leger = m
        leger.date = d.addingTimeInterval(900)
        leger.dateTables = d
        #expect(FicheZigbee.dateQualites(leger) == d, "une tournee sans tables : les qualites d'avant")
        leger.dateTables = nil
        #expect(FicheZigbee.dateQualites(leger) == leger.date, "sans date des tables : celle du maillage")
        #expect(FicheNoeud.ligneQualites(d)
                == String(localized: "qualités du \(jour) à \(d.formatted(date: .omitted, time: .shortened))"))
    }

    /// Etat d'un noeud dans sa fiche : celui de son appareil ; « inconnu du pont », « la sonde ».
    @Test func etatDansLaFiche() {
        let joignable = AppareilAffiche(id: "x", nom: "x", etat: .joignable)
        #expect(FicheNoeud.etat(joignable, inconnu: false, sonde: false) == String(localized: "joignable"))
        #expect(FicheNoeud.etat(nil, inconnu: true, sonde: false) == String(localized: "inconnu du pont"))
        #expect(FicheNoeud.etat(nil, inconnu: false, sonde: true) == String(localized: "la sonde"))
        #expect(FicheNoeud.couleur(.disparu, inconnu: false) == .red && FicheNoeud.couleur(.joignable, inconnu: true) == .gray)
    }

    /// « Renommer… » : tout noeud du graphe (son surnom est garde sous son adresse longue), la sonde et le routeur
    /// inconnu compris ; un noeud absent n'a pas de fiche.
    @Test func renommable() throws {
        let (_, e) = try NomsSceneTests.demo()
        for id in [I.pont, I.interrupteurSalon, I.sonde, I.inconnu, I.priseSalon] {
            #expect(FicheNoeud.renommable(id, entree: e), "\(id)")
        }
        #expect(!FicheNoeud.renommable("A0000000000000EE", entree: e))
        #expect(!FicheNoeud.renommable("~0A13", entree: e), "une cle provisoire n'est pas une adresse longue")
        #expect(!FicheNoeud.renommable(I.pont, entree: nil))
    }

    /// Le reseau de la sonde dans les Reglages (`etat`) : le canal et le parent avec son LQI ; « hors reseau ».
    @Test func reseauDeLaSonde() {
        let e = EtatSonde(membre: true, court: "5E6F", parent: ParentSonde(court: "1A2B", ieee: nil, lqi: 180, rssi: -71),
                          canal: 25)
        #expect(FenetreReglages.texteReseau(e)
                == [String(localized: "canal \(25)"), String(localized: "parent \("1A2B") (LQI \(180))")].joined(separator: " · "))
        #expect(FenetreReglages.texteReseau(EtatSonde(membre: false)) == String(localized: "hors réseau"))
        #expect(FenetreReglages.texteReseau(EtatSonde(membre: true))
                == String(localized: "sans parent (rattachement en cours)"))
    }

    /// Titre du menu : en attente sans rien a montrer ; l'alerte de l'heure ; sinon le reseau normal.
    @Test func titreDuMenu() {
        let r = ResumeReseau(routeurs: 14, appareils: 8, injoignables: 1)
        #expect(MenuBarre.titre(resume: nil, alerte: true) == String(localized: "En attente du maillage de la sonde…"))
        #expect(MenuBarre.titre(resume: r, alerte: true) == String(localized: "Alerte dans l'heure"))
        #expect(MenuBarre.titre(resume: r, alerte: false) == String(localized: "Réseau Zigbee normal"))
    }

    /// Ligne du menu : le nom de la sonde a la place de « Sonde » quand il est donne (celui de la
    /// sonde retenue, quand l'etat la concerne : `SondeMaillage.nomEtat`) ; pendant une tournee,
    /// son etape et son compteur. Etat des Reglages : « SONDE-01 · connectee », l'etat seul sans nom.
    @Test func menuEtReglages() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let sonde = String(localized: "Sonde")
        #expect(SondeMaillage.nomAffiche(nil) == sonde)
        #expect(SondeMaillage.nomAffiche("SONDE-01") == "SONDE-01")
        #expect(MenuBarre.ligneSonde(.sansSonde, nom: nil, derniere: nil, avancement: nil, maintenant: t) == nil)
        #expect(MenuBarre.ligneSonde(.absente, nom: nil, derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\(sonde) : absente"))
        #expect(MenuBarre.ligneSonde(.absente, nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : absente"))
        #expect(MenuBarre.ligneSonde(.connexion, nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connexion…"))
        #expect(MenuBarre.ligneSonde(.erreur("x"), nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : erreur (voir les Réglages)"))
        guard case .bonjour(let b)? = MessageSonde.lire(Data(CanalRejoue.bonjourNomme.utf8)) else {
            Issue.record("bonjour illisible")
            return
        }
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: nil, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connectée"))
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t - 120, avancement: nil, maintenant: t)
                == String(localized: "\("SONDE-01") : connectée · relevé \(FicheNoeud.relatif(t - 120, t))"))
        let tables = AvancementTournee(etape: .tables, fait: 24, total: 48)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t - 120, avancement: tables, maintenant: t)
                == String(localized: "\("SONDE-01") : \(TexteTournee.etape(.tables)) \(24)/\(48)…"))
        let rien = AvancementTournee(etape: .routes, fait: 0, total: 0)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: nil, derniere: nil, avancement: rien, maintenant: t)
                == String(localized: "\(sonde) : \(TexteTournee.etape(.routes))…"))
        #expect(FenetreReglages.texteEtatSonde(.connectee(b), nom: "SONDE-01")
                == String(localized: "\("SONDE-01") · \(String(localized: "connectée"))"))
        #expect(FenetreReglages.texteEtatSonde(.absente, nom: "SONDE-01")
                == String(localized: "\("SONDE-01") · \(String(localized: "absente (débranchée ?)"))"))
        #expect(FenetreReglages.texteEtatSonde(.connectee(b), nom: nil) == String(localized: "connectée"))
        #expect(FenetreReglages.texteEtatSonde(.refusee("pas une sonde"), nom: nil)
                == String(localized: "refusée : \("pas une sonde")"))
        #expect(FenetreReglages.texteEtatSonde(.sansSonde, nom: nil) == String(localized: "aucune sonde choisie"))
    }

    /// Choix du port : la sonde retenue sous son nom seul ; un autre port, un port sans numero
    /// de serie ou la sonde retenue sans nom connu (firmware 1.0.0), sous son nom de port et son
    /// numero de serie USB (la MAC) : seul moyen de distinguer la sonde du pont Halo avant la
    /// premiere connexion. Un port Espressif n'est pas forcement un C6 : rien ne l'affirme.
    @Test func libellesDesPorts() {
        let retenue = PortUSB(chemin: "/dev/cu.usbmodem11301", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                              produit: nil)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let sansSerie = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: nil, produit: nil)
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: "A0:00:00:00:00:01", nom: "SONDE-01") == "SONDE-01")
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: "A0:00:00:00:00:01", nom: nil)
                == "usbmodem11301 · A0:00:00:00:00:01")
        #expect(FenetreReglages.libellePort(autre, serieRetenue: "A0:00:00:00:00:01", nom: "SONDE-01")
                == "usbmodemFACTICE02 · B0:00:00:00:00:02")
        #expect(FenetreReglages.libellePort(retenue, serieRetenue: nil, nom: "SONDE-01") == "usbmodem11301 · A0:00:00:00:00:01",
                "aucune sonde retenue")
        #expect(FenetreReglages.libellePort(sansSerie, serieRetenue: nil, nom: "SONDE-01") == "usbmodemFACTICE03")
    }

    /// Textes de l'avancement : libelles d'etape distincts ; « etape · fait/total », l'etape
    /// seule quand elle n'a rien a faire ; duree en m:ss dans la barre du graphe, en unites
    /// dans les Reglages.
    @Test func texteAvancement() {
        let etapes = AvancementTournee.Etape.allCases.map(TexteTournee.etape)
        #expect(Set(etapes).count == etapes.count)
        #expect(!etapes.contains(""))
        let a = AvancementTournee(etape: .tables, fait: 24, total: 48)
        #expect(TexteTournee.avancement(a) == String(localized: "\(TexteTournee.etape(.tables)) · \(24)/\(48)"))
        #expect(TexteTournee.avancement(AvancementTournee(etape: .routes, fait: 0, total: 0))
                == TexteTournee.etape(.routes))
        #expect(TexteTournee.chrono(42) == "0:42")
        #expect(TexteTournee.chrono(600) == "10:00")
        #expect(TexteTournee.chrono(3723) == "1:02:03")
        #expect(TexteTournee.chrono(-3) == "0:00", "horloge qui recule")
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(TexteTournee.barre(a, debut: t, maintenant: t + 42) == String(localized: "\(TexteTournee.avancement(a)) · \("0:42")"))
        #expect(TexteTournee.reglages(a, debut: t, maintenant: t + 42)
                == String(localized: "\(TexteTournee.avancement(a)) · depuis \(TexteTournee.duree(42))"))
        #expect(TexteTournee.duree(42).contains("42"))
        #expect(TexteTournee.duree(90).contains("1") && TexteTournee.duree(90).contains("30"))
    }
}
