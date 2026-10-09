import Foundation
import MaillageCoeur
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Surveillance (modele de l'app)")
struct SurveillanceTests {
    typealias I = NomsDemo.Ieee

    /// La demo : deux tournees du faux reseau Hue ; le journal (le demarrage, puis la prise du salon qui quitte le
    /// maillage, le detecteur de l'abri qui change de parent et la lampe du bureau qui change de chemin vers le pont),
    /// l'alerte de l'heure, le resume, les appareils.
    @Test func modeDemo() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .routeurDisparu, .parentChange, .cheminChange])
        #expect(s.evenements[3].sujet?.nom == "Lampe bureau" && s.evenements[3].avant == "Pont Hue"
                && s.evenements[3].apres == "Lampadaire salon")
        #expect(s.evenements.first?.details == ["routeurs": "14", "appareils": "8"], "la tournee d'avant : la prise y est")
        #expect(s.evenements[1].sujet == Sujet(id: I.priseSalon, nom: "Prise salon"))
        #expect(s.evenements[2].avant == "Ruban cuisine" && s.evenements[2].apres == "Prise terrasse")
        #expect(s.alerte, "un routeur disparu dans l'heure")
        #expect(s.maintenant == MaillageDemo.fin && s.maintenant(a: .distantFuture) == MaillageDemo.fin)
        #expect(s.fraicheurMaillage(a: s.maintenant) == .frais && !s.maillageAncien)
        #expect(s.resume == ResumeReseau(routeurs: 14, appareils: 9, injoignables: 1),
                "le pont et 13 routeurs ; 7 appareils finaux du pont, la prise disparue et la sonde")
        let affiches = s.appareilsAffiches
        #expect(affiches.count == 21)
        #expect(affiches.filter { $0.etat == .disparu }.map(\.nom) == ["Prise salon"])
        #expect(affiches.first { $0.id == I.lampeBureau }?.piece == "Bureau")
        #expect(affiches.filter { $0.endormi }.count == 7, "les appareils finaux a pile")
        #expect(affiches.filter { $0.batterie?.faible == true }.map(\.nom).sorted() == ["Capteur grenier", "Télécommande chambre"])
        #expect(s.evenements(de: I.priseSalon).first?.type == .routeurDisparu)
        #expect(s.evenements(de: I.detecteurAbri).first?.type == .parentChange)
        #expect(s.historique.isEmpty, "la demo ne garde pas d'historique")
        #expect(s.nom(I.sonde) == String(localized: "Sonde") && s.nom(I.inconnu) == I.inconnu)
    }

    /// Le journal d'un noeud regroupe comme la fenetre du journal : ses changements de chemin (ou de parent) d'une meme
    /// heure en une ligne, la plus recente d'abord ; un changement isole reste un evenement ; les captures ajoutent des
    /// evenements en demo seulement.
    @Test func lignesJournalDUnNoeud() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        #expect(s.lignesJournal(de: I.lampeBureau).map(\.evenements.count) == [1], "le changement de la demo, seul")
        s.evenementsDeCapture(CapturesPieces.evenementsHesitants)
        let bureau = s.lignesJournal(de: I.lampeBureau)
        try #require(bureau.count == 1)
        guard case .chemins(let groupe) = bureau[0] else {
            Issue.record("4 changements de chemin dans l'heure : une ligne")
            return
        }
        #expect(groupe.count == 4 && groupe.last?.apres == "Lampadaire salon" && groupe.first?.avant == "Lampadaire salon")
        let resume = Regroupement.resumeRelais(groupe)
        #expect(resume.relais == ["Lampadaire salon", "Lampe chambre", "Plafonnier salon", "Pont Hue"]
                && resume.dernier == "Lampadaire salon")
        guard case .parents(let abri)? = s.lignesJournal(de: I.detecteurAbri).first else {
            Issue.record("les changements de parent du detecteur : une ligne")
            return
        }
        #expect(abri.count == 4 && Regroupement.resumeRelais(abri).alternent)
        #expect(s.lignesJournal(de: I.priseSalon).map(\.evenements.count) == [1], "un evenement isole")
        #expect(s.lignesJournal(de: I.lampeChambre).isEmpty)
        let direct = Surveillance(mode: .direct, dossier: nil)
        direct.evenementsDeCapture(CapturesPieces.evenementsHesitants)
        #expect(direct.evenements.isEmpty, "sans effet hors demo")
    }

    /// Endormi : d'apres `ecoute` dans le maillage (un appareil final au recepteur eteint), plus d'apres la pile ; sans
    /// maillage, rien n'est dit. Un noeud sans adresse longue (cle provisoire) a un nom tire de son adresse courte et
    /// pas de cle d'historique.
    @Test func endormiEtClesProvisoires() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.noms.maison = NomsDemo.maison
        #expect(s.appareilsAffiches.allSatisfy { !$0.endormi }, "sans maillage")
        var m = MaillageDemo.maillage
        if let i = m.noeuds.firstIndex(where: { $0.ieee == I.capteurGrenier }) { m.noeuds[i].ecoute = true }
        m.noeuds.append(NoeudZigbee(ieee: NoeudZigbee.cleProvisoire(court: 0x0A13), court: 0x0A13, type: .final))
        s.recevoir(m, a: Date())
        let affiches = s.appareilsAffiches
        #expect(affiches.first { $0.id == I.capteurGrenier }?.endormi == false, "pile, mais il ecoute")
        #expect(affiches.first { $0.id == I.detecteurAbri }?.endormi == true)
        #expect(affiches.first { $0.id == I.lampeBureau }?.endormi == false, "un routeur n'est jamais endormi")
        #expect(s.nom("~0A13") == String(localized: "Nœud \("0A13")"))
        #expect(s.cleHistorique(noeud: "~0A13") == nil && s.cleHistorique(noeud: I.lampeBureau) == I.lampeBureau)
        #expect(!(s.historique.last?.noeuds.contains { $0.ieee == "~0A13" } ?? true))
    }

    /// Sans maillage ni appareils : rien a montrer, ni resume ; sans maillage, les appareils du pont sont d'etat
    /// inconnu.
    @Test func sansMaillage() {
        let s = Surveillance(mode: .direct, dossier: nil)
        #expect(!s.aUnReseau && s.resume == nil && s.maillageAffiche == nil)
        s.noms.maison = NomsDemo.maison
        #expect(s.aUnReseau && s.appareilsAffiches.allSatisfy { $0.etat == .inconnu })
        #expect(s.resume == ResumeReseau(routeurs: 0, appareils: 21, injoignables: 0), "sans maillage, rien ne route")
    }

    /// Fraicheur d'un maillage : frais jusqu'a 16 min (une tournee toutes les 15 min) et pendant une tournee ; ancien
    /// ensuite ; perime au-dela de 45 min, tournee ou non.
    @Test func fraicheur() {
        let t = MaillageDemo.fin
        #expect(Surveillance.fraicheur(t, maintenant: t.addingTimeInterval(16 * 60)) == .frais)
        #expect(Surveillance.fraicheur(t, maintenant: t.addingTimeInterval(16 * 60 + 1)) == .ancien)
        #expect(Surveillance.fraicheur(t, maintenant: t.addingTimeInterval(30 * 60), tourneeEnCours: true) == .frais)
        #expect(Surveillance.fraicheur(t, maintenant: t.addingTimeInterval(45 * 60 + 1), tourneeEnCours: true) == .perime)
    }

    /// En mode direct, un maillage recu va au journal, a l'historique en memoire et sur disque ; les surnoms aussi
    /// sont gardes. Le dernier maillage se capture en JSON.
    @Test func journalHistoriqueEtSurnomsSurDisque() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.noms.maison = NomsDemo.maison
        s.recevoir(MaillageDemo.maillageAvant, a: MaillageDemo.debut)
        s.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .routeurDisparu, .parentChange, .cheminChange])
        let journal = JournalFichiers(dossier: dossier.appendingPathComponent("Journal"))
        #expect(try journal.lire().count == 4)
        #expect(s.historique == [ReleveMaillage(MaillageDemo.maillageAvant), ReleveMaillage(MaillageDemo.maillage)])
        #expect(try HistoriqueFichiers(dossier: dossier).lire(depuis: .distantPast).count == 2)
        let courbes = try #require(s.courbes(noeud: I.lampeBureau, periode: .jour, fin: MaillageDemo.fin))
        #expect(courbes.signal.map(\.valeur) == [188, 188], "le LQI que la sonde recoit de la lampe du bureau")
        #expect(s.nomsHistorique([I.lampeBureau, I.sonde]) == [I.lampeBureau: "Lampe bureau", I.sonde: String(localized: "Sonde")])

        s.renommer(I.lampeBureau, en: "  Lampe de travail ")
        #expect(s.nom(I.lampeBureau) == "Lampe de travail")
        let relu = Surveillance(mode: .direct, dossier: dossier)
        #expect(relu.noms.surnoms == [I.lampeBureau: "Lampe de travail"])
        s.renommer(I.lampeBureau, en: "")
        #expect(s.nom(I.lampeBureau) == "Lampe bureau")

        let capture = try #require(try s.captureJSON())
        #expect(try CodageJSON.decodeur().decode(MaillageZigbee.self, from: capture) == MaillageDemo.maillage)
    }

    /// La sonde oubliee : son maillage part tout de suite, et le suivant est un point de depart ; l'historique reste.
    @Test func sondeOubliee() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.recevoir(MaillageDemo.maillageAvant, a: MaillageDemo.debut)
        s.oublierMaillage()
        #expect(s.maillage == nil && s.maillageRecu == nil && s.historique.count == 1)
        s.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .surveillanceDemarree], "un nouveau point de depart")
    }

    @Test func veilleDuMac() {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.noterVeille(debut: MaillageDemo.fin, fin: MaillageDemo.debut)
        #expect(s.evenements.last?.type == .veille)
        #expect(s.evenements.last?.periode?.duration == 0, "fin avant le debut : ramenee au debut")
    }

    /// Les alertes ne partent qu'en mode direct : la demo ne notifie rien.
    @Test func alertesEnModeDirect() {
        var envoyees: [CategorieAlerte] = []
        let demo = Surveillance(mode: .demo, dossier: nil)
        demo.surAlertes = { envoyees += $0.map(\.categorie) }
        demo.demarrer()
        #expect(envoyees.isEmpty)
        let s = Surveillance(mode: .direct, dossier: nil)
        s.surAlertes = { envoyees += $0.map(\.categorie) }
        s.recevoir(MaillageDemo.maillageAvant, a: MaillageDemo.debut)
        s.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        #expect(envoyees == [.routeurDisparu, .informations, .informations])
    }

    /// L'etat de connexion du pont l'emporte : `connected`, joignable (meme absent du maillage) ; `connectivity_issue`,
    /// `disconnected`, `unidirectional_incoming`, injoignable (meme present). Sans lui : le maillage decide. Le
    /// coordinateur du maillage est l'appareil du pont qui a son adresse longue (celle de son `zigbee_connectivity`).
    @Test func etatSelonLePont() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        var maison = NomsDemo.maison
        func changer(_ ieee: String, _ c: ConnexionZigbee) {
            if let i = maison.accessoires.firstIndex(where: { $0.ieee == ieee }) { maison.accessoires[i].connexion = c }
        }
        changer(I.priseSalon, .connecte)
        changer(I.lampeBureau, .problemeConnexion)
        changer(I.lampeChambre, .entrantSeul)
        changer(I.lampeChambreAmis, .deconnecte)
        changer(I.lampeSalleDeBain, .inconnue)
        s.noms.maison = maison
        let etats = Dictionary(uniqueKeysWithValues: s.appareilsAffiches.map { ($0.id, $0.etat) })
        #expect(etats[I.priseSalon] == .joignable, "absente du maillage, mais le pont la dit connectee")
        #expect(etats[I.lampeBureau] == .injoignable && etats[I.lampeChambre] == .injoignable
                && etats[I.lampeChambreAmis] == .injoignable)
        #expect(etats[I.lampeSalleDeBain] == .joignable, "etat inconnu de l'app : le maillage decide")
        #expect(s.resume?.injoignables == 3)
        let sans = AccessoireMaison(nom: "X", ieee: I.lampeBureau, connexion: .deconnecte)
        #expect(Surveillance.etat(sans, presents: nil) == .injoignable, "sans maillage, l'etat du pont")
        #expect(Surveillance.etat(AccessoireMaison(nom: "X", ieee: I.lampeBureau), presents: nil) == .inconnu)

        // Le coordinateur : l'appareil du pont, rapproche par son adresse longue.
        let coordinateur = try #require(s.maillage?.noeuds.first { $0.type == .coordinateur })
        #expect(coordinateur.ieee == I.pont && s.nom(I.pont) == "Pont Hue")
        let graphe = GrapheReseau(maillage: s.maillageAffiche, appareils: s.appareilsAffiches)
        #expect(graphe.noeud(I.pont)?.genre == .centre && graphe.noeud(I.pont)?.inconnu == false)
    }

    /// Les noms du pont (minimal a l'etape 1) : un releve integre est garde, et passe a la surveillance par `surNoms`.
    @Test func nomsDuPont() {
        let s = Surveillance(mode: .direct, dossier: nil)
        let pont = NomsPont()
        #expect(pont.noms == nil)
        pont.surNoms = { s.noms.maison = $0 }
        pont.integrer(NomsDemo.maison)
        #expect(pont.noms == NomsDemo.maison && s.noms.maison == NomsDemo.maison)
        #expect(s.nom(I.lampeBureau) == "Lampe bureau")
    }

    /// Relecture finale, I3 : les lectures du pont (`lecturePont`) donnent « disparu » et « revenu » d'apres l'etat de
    /// connexion, nommes par le pont ; trois pertes d'une lecture partent en une notification groupee (`pertes`) et
    /// font une ligne du journal. La premiere lecture est un etat initial ; le pont oublie (`nomsPont` nil), la
    /// lecture suivante aussi. Valeurs inventees.
    @Test func pertesSelonLePont() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        var envoyees: [AlerteAEnvoyer] = []
        s.surAlertes = { envoyees += $0 }
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        func lecture(_ minutes: Double, _ connexions: [ConnexionZigbee]) -> NomsMaison {
            NomsMaison(date: t0.addingTimeInterval(minutes * 60), domicile: "C0FFEEFFFE012345",
                       accessoires: connexions.enumerated().map { k, c in
                           AccessoireMaison(nom: "Lampe \(k)", ieee: String(format: "A0000000000000D%X", k), connexion: c)
                       })
        }
        func lire(_ n: NomsMaison) {
            s.nomsPont = n
            s.lecturePont(n)
        }
        lire(lecture(0, [.deconnecte, .connecte, .connecte, .connecte]))
        #expect(s.evenements.isEmpty && envoyees.isEmpty, "premiere lecture : etat initial")
        lire(lecture(5, [.deconnecte, .deconnecte, .problemeConnexion, .entrantSeul]))
        #expect(s.evenements.isEmpty && envoyees.isEmpty, "une seule lecture injoignable : pas encore (choix de Majid)")
        lire(lecture(10, [.deconnecte, .deconnecte, .problemeConnexion, .entrantSeul]))
        #expect(s.evenements.map(\.type) == [.appareilDisparu, .appareilDisparu, .appareilDisparu])
        #expect(s.evenements.map { $0.sujet?.nom } == ["Lampe 1", "Lampe 2", "Lampe 3"])
        #expect(envoyees.map(\.categorie) == [.pertes] && envoyees.first?.evenements.count == 3)
        let ligne = try #require(s.lignesJournal.first)
        if case .pertes(let p) = ligne { #expect(p.count == 3) } else { Issue.record("une ligne de pertes") }
        lire(lecture(15, [.connecte, .deconnecte, .problemeConnexion, .entrantSeul]))
        #expect(s.evenements.last?.type == .appareilRevenu && s.evenements.last?.sujet?.nom == "Lampe 0")
        #expect(s.evenements(de: "A0000000000000D0").first?.type == .appareilRevenu)
        // Le pont oublie, puis lu de nouveau : etat initial, rien.
        let avant = s.evenements.count
        s.nomsPont = nil
        lire(lecture(20, [.connecte, .connecte, .connecte, .connecte]))
        #expect(s.evenements.count == avant)
    }

    /// Le maillage de la fin de la demo, `minutes` plus tard, sans le detecteur de l'abri (un appareil final endormi que
    /// son parent n'a pas liste a cette tournee) : ni son noeud, ni son parent.
    static func sansDetecteur(_ minutes: Double) -> MaillageZigbee {
        var m = MaillageDemo.maillage
        m.date = m.date.addingTimeInterval(minutes * 60)
        m.noeuds.removeAll { $0.ieee == I.detecteurAbri }
        m.parents.removeAll { $0.enfant == I.detecteurAbri }
        return m
    }

    /// Un appareil final absent des dernieres tables garde son parent d'avant 24 h (mode direct) : son role reste
    /// « appareil final » (endormi), son lien est un parent d'avant, le journal ne dit rien, et l'historique ne le compte
    /// pas comme vu. Au-dela de 24 h, comportement d'avant : deux tournees, puis « n'a plus de parent ».
    @Test func parentDAvantPendantVingtQuatreHeures() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.noms.maison = NomsDemo.maison
        s.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        s.recevoir(Self.sansDetecteur(40), a: MaillageDemo.fin.addingTimeInterval(40 * 60))
        let m = try #require(s.maillage)
        let lien = try #require(m.parent(de: I.detecteurAbri))
        #expect(lien.dAvant && lien.parent == I.priseTerrasse && lien.date == MaillageDemo.fin)
        #expect(m.noeud(I.detecteurAbri)?.type == .final && m.noeud(I.detecteurAbri)?.endormi == true)
        #expect(GrapheReseau(maillage: m, appareils: []).liens.contains {
            $0.genre == .parent && $0.de == I.detecteurAbri && $0.vers == I.priseTerrasse && $0.suppose
        })
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree], "ni « sans parent » ni changement de parent")
        let releve = try #require(s.historique.last)
        #expect(!releve.parents.contains { $0.enfant == I.detecteurAbri } && !releve.noeuds.contains { $0.ieee == I.detecteurAbri })
        // Toutes les 15 min pendant 24 h : rien.
        for minutes in stride(from: 55.0, through: 24 * 60, by: 15) {
            s.recevoir(Self.sansDetecteur(minutes), a: MaillageDemo.fin.addingTimeInterval(minutes * 60))
        }
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree])
        #expect(s.maillage?.parent(de: I.detecteurAbri)?.dAvant == true)
        // Plus de 24 h apres sa derniere lecture : plus de parent, ni de noeud.
        s.recevoir(Self.sansDetecteur(24 * 60 + 15), a: MaillageDemo.fin.addingTimeInterval((24 * 60 + 15) * 60))
        #expect(s.maillage?.parent(de: I.detecteurAbri) == nil && s.maillage?.noeud(I.detecteurAbri) == nil)
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree], "une absence : on attend")
        s.recevoir(Self.sansDetecteur(24 * 60 + 30), a: MaillageDemo.fin.addingTimeInterval((24 * 60 + 30) * 60))
        #expect(s.evenements.map(\.type) == [.surveillanceDemarree, .sansParent])
        #expect(s.evenements.last?.sujet?.id == I.detecteurAbri && s.evenements.last?.avant == "Prise terrasse")
    }

    /// La demo n'a pas de parent d'avant : son maillage est rendu tel quel ; la sonde oubliee oublie aussi ses parents
    /// connus.
    @Test func demoEtSondeOubliee() throws {
        let demo = Surveillance(mode: .demo, dossier: nil)
        demo.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        demo.recevoir(Self.sansDetecteur(40), a: MaillageDemo.fin.addingTimeInterval(40 * 60))
        #expect(demo.maillage == Self.sansDetecteur(40))
        let s = Surveillance(mode: .direct, dossier: nil)
        s.recevoir(MaillageDemo.maillage, a: MaillageDemo.fin)
        s.oublierMaillage()
        s.recevoir(Self.sansDetecteur(40), a: MaillageDemo.fin.addingTimeInterval(40 * 60))
        #expect(s.maillage == Self.sansDetecteur(40), "une autre sonde : on ne sait rien de l'avant")
    }

    /// Au lancement, le dernier parent connu est retrouve dans l'historique (releves des dernieres 24 h), a la date du
    /// dernier releve qui le portait ; un releve de plus de 24 h n'y est pas.
    @Test func parentDAvantRetrouveDansLHistorique() async throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        try HistoriqueFichiers(dossier: dossier).ajouter(ReleveMaillage(MaillageDemo.maillage))
        let tard = MaillageDemo.fin.addingTimeInterval(40 * 60)
        let s = Surveillance(mode: .direct, dossier: dossier)
        await s.chargerHistorique(maintenant: tard)
        s.recevoir(Self.sansDetecteur(40), a: tard)
        let lien = try #require(s.maillage?.parent(de: I.detecteurAbri))
        #expect(lien.dAvant && lien.parent == I.priseTerrasse)
        #expect(abs(lien.date?.timeIntervalSince(MaillageDemo.fin) ?? 1000) < 1, "la date du releve")
        #expect(s.maillage?.noeud(I.detecteurAbri)?.type == .final)
        // Un lancement 25 h plus tard : le releve est trop vieux.
        let trop = Surveillance(mode: .direct, dossier: dossier)
        let apres = MaillageDemo.fin.addingTimeInterval(25 * 3600)
        await trop.chargerHistorique(maintenant: apres)
        trop.recevoir(Self.sansDetecteur(25 * 60), a: apres)
        #expect(trop.maillage?.parent(de: I.detecteurAbri) == nil)
    }
}

