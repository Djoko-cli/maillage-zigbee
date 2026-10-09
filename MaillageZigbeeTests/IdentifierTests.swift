import Foundation
import MaillageCoeur
import Testing
@testable import MaillageZigbee

/// « Identifier » : fait clignoter un appareil par le pont Hue (`PUT /clip/v2/resource/device/<id>`). Pont simule
/// (`PontSimule`), trousseau en memoire, attente instantanee : aucun reseau, jamais le vrai pont.
@MainActor
@Suite("Identifier : requete du pont, trois envois espaces, erreurs, id du device garde")
struct IdentifierTests {
    typealias S = PontSimule
    /// La lampe du bureau du pont simule : son device (`d2`) et son adresse longue.
    static let lampe = "A000000000000015"
    static let capteur = "A000000000000020"

    /// Un pont lie et lu : le banc de `NomsPontTests`, le pont demarre et sa premiere lecture faite.
    func banc() async throws -> NomsPontTests.Banc {
        let b = try NomsPontTests().banc(memoire: NomsPontTests.retenu, cles: [S.identifiant: S.cle])
        b.pont.demarrer()
        await b.pont.tacheLecture?.value
        #expect(b.pont.etat == .lie && b.pont.noms != nil)
        return b
    }

    static func puts(_ b: NomsPontTests.Banc) -> [PontSimule.Appel] {
        b.simule.appels.filter { $0.requete.methode == "PUT" }
    }

    // MARK: La requete

    /// Methode, chemin, corps et en-tete (la cle part dans `hue-application-key`, par le transport) ; l'adresse et
    /// l'identifiant du pont attendu, comme pour une lecture.
    @Test func requeteConstruite() async throws {
        let simule = PontSimule()
        let client = PontHue(transport: simule, adresse: "192.0.2.10", attendu: S.identifiant)
        try await client.identifier(device: "d2", cle: S.cle)
        let appel = try #require(simule.appels.first)
        #expect(simule.appels.count == 1)
        #expect(appel.requete.methode == "PUT")
        #expect(appel.requete.chemin == "/clip/v2/resource/device/d2")
        #expect(appel.requete.cle == S.cle)
        #expect(appel.adresse == "192.0.2.10" && appel.attendu == S.identifiant)
        let corps = try #require(appel.requete.corps)
        #expect(try JSONSerialization.jsonObject(with: corps) as? NSDictionary == ["identify": ["action": "identify"]])
        #expect(!appel.requete.description.contains(S.cle), "la cle n'est dans aucune description")
    }

    /// L'identifiant du device va dans le chemin : seuls lettres, chiffres et tirets passent ; rien n'est envoye sinon.
    @Test func identifiantDeDeviceSain() async throws {
        for bon in ["d2", "d0000000-0000-4000-8000-000000000002", "ABC-def-123"] {
            #expect(PontHue.identifiantDeviceValide(bon), "\(bon)")
        }
        for mauvais in ["", "../bridge", "d2/../x", "d2?x=1", "d 2", "d2#", "é", String(repeating: "a", count: 65)] {
            #expect(!PontHue.identifiantDeviceValide(mauvais), "\(mauvais)")
        }
        let simule = PontSimule()
        let client = PontHue(transport: simule, adresse: "192.0.2.10", attendu: S.identifiant)
        await #expect(throws: PontHue.Erreur.illisible("device")) {
            try await client.identifier(device: "../bridge", cle: S.cle)
        }
        #expect(simule.appels.isEmpty)
    }

    /// Cle refusee (401 ou 403) : `cleRefusee`, comme une lecture ; un autre statut : `http`.
    @Test func erreursDeLaRequete() async throws {
        let simule = PontSimule()
        let client = PontHue(transport: simule, adresse: "192.0.2.10", attendu: S.identifiant)
        for statut in [401, 403] {
            simule.modifier { $0.cleValide = false; $0.statutCleRefusee = statut }
            await #expect(throws: PontHue.Erreur.cleRefusee, "HTTP \(statut)") {
                try await client.identifier(device: "d2", cle: S.cle)
            }
        }
        simule.modifier { $0.cleValide = true }
        await #expect(throws: PontHue.Erreur.http(404, "/clip/v2/resource/device/inconnu")) {
            try await client.identifier(device: "inconnu", cle: S.cle)
        }
        simule.modifier { $0.reseauCoupe = true }
        await #expect(throws: PontHue.Erreur.transport(.reseau("coupé"))) {
            try await client.identifier(device: "d2", cle: S.cle)
        }
    }

    // MARK: Trois envois

    /// Un clic : trois PUT sur le device de l'appareil, espaces de 2 s (l'attente est injectee : deux attentes, la
    /// premiere apres le premier envoi, la seconde apres le deuxieme, aucune apres le dernier) ; l'etat passe a
    /// « en cours » puis « fait ».
    @Test func troisEnvoisEspaces() async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        #expect(b.pont.peutIdentifier(ieee: Self.lampe))
        #expect(b.pont.identification(ieee: Self.lampe) == nil)
        let avant = b.simule.appels.count
        b.simule.retenir("PUT")
        let tache = try #require(b.pont.identifier(ieee: Self.lampe))
        #expect(b.pont.identification(ieee: Self.lampe) == .enCours)
        #expect(await NomsPontTests.sonder { b.simule.retient })
        #expect(b.pont.identifier(ieee: Self.lampe) == nil, "un deuxieme clic pendant l'envoi est sans effet")
        b.simule.liberer()
        await tache.value

        #expect(b.pont.identification(ieee: Self.lampe) == .fait)
        #expect(b.pont.identification(ieee: Self.lampe.lowercased()) == .fait, "sans egard a la casse")
        let envois = Self.puts(b)
        #expect(envois.count == NomsPont.nombreIdentifications && envois.count == 3)
        #expect(envois.allSatisfy { $0.requete.chemin == "/clip/v2/resource/device/d2" && $0.requete.cle == S.cle
                && $0.attendu == S.identifiant && $0.adresse == "192.0.2.10" })
        let attentes = zip(b.releve.attentes, b.releve.appelsAvantAttente).filter { $0.0 == NomsPont.intervalleIdentification }
        #expect(NomsPont.intervalleIdentification == .seconds(2))
        #expect(attentes.map(\.1) == [avant + 1, avant + 2], "une attente de 2 s apres le 1er et apres le 2e envoi")
        // Rien d'autre que ces trois requetes depuis la lecture, et aucune ecriture ailleurs.
        #expect(b.simule.appels.count == avant + 3)
        // On peut recommencer.
        await b.pont.identifier(ieee: Self.lampe)?.value
        #expect(Self.puts(b).count == 6)
    }

    /// Le pont lui-meme et un capteur ont un device : ils s'identifient aussi (le pont fait clignoter sa LED).
    @Test func pontEtCapteur() async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        await b.pont.identifier(ieee: "A000000000000001")?.value
        await b.pont.identifier(ieee: Self.capteur)?.value
        let chemins = Set(Self.puts(b).map(\.requete.chemin))
        #expect(chemins == ["/clip/v2/resource/device/\(S.appareilPont)", "/clip/v2/resource/device/d3"])
    }

    // MARK: Refus

    /// Pas de pont lie (un pont retenu, sans cle) : refus, rien n'est envoye. Un pont lie qui ne connait pas
    /// l'appareil : refus aussi, et pas de bouton (`peutIdentifier`).
    @Test func refusSansPontLieOuSansDevice() async throws {
        let sansDevice = NomsMaison(date: NomsPontTests.date, domicile: S.identifiant,
                                    accessoires: [AccessoireMaison(nom: "Lampe", ieee: Self.lampe)])
        let a = try NomsPontTests().banc(memoire: NomsPontTests.retenu, cache: sansDevice)
        defer { a.pont.arreter() }
        a.pont.demarrer()
        #expect(a.pont.noms == sansDevice && !a.pont.lie)
        #expect(!a.pont.peutIdentifier(ieee: Self.lampe), "un releve garde avant cette version n'a pas d'identifiant de device")
        #expect(a.pont.identifier(ieee: Self.lampe) == nil)
        #expect(a.pont.identification(ieee: Self.lampe) == .erreur(String(localized: "Pont non lié : liez-le d'abord dans les Réglages.")))
        #expect(a.simule.appels.isEmpty)

        // Lie, mais sans identifiant de device connu pour cet appareil (releve garde avant cette version).
        let b = try NomsPontTests().banc(memoire: NomsPontTests.retenu, cles: [S.identifiant: S.cle], cache: sansDevice)
        defer { b.pont.arreter() }
        b.simule.modifier { $0.reseauCoupe = true }
        b.pont.demarrer()
        await b.pont.tacheLecture?.value
        #expect(b.pont.lie && !b.pont.peutIdentifier(ieee: Self.lampe))
        #expect(b.pont.identifier(ieee: Self.lampe) == nil)
        #expect(b.pont.identification(ieee: Self.lampe) == .erreur(String(localized: "Cet appareil n'est pas connu du pont.")))
        #expect(b.pont.identifier(ieee: "A0000000000000FF") == nil, "un appareil que le pont ne connait pas")
        #expect(Self.puts(b).isEmpty)
    }

    /// Ni demo ni vue de test : `NomsPont` inerte, sans dependances. Pas de bouton, rien n'est envoye.
    @Test func inerteEnDemo() {
        let demo = NomsPont(noms: NomsDemo.maison)
        #expect(NomsDemo.maison.accessoires.allSatisfy { $0.idHue == nil })
        for a in NomsDemo.maison.accessoires {
            #expect(!demo.peutIdentifier(ieee: a.ieee ?? ""))
        }
        #expect(demo.identifier(ieee: NomsDemo.Ieee.pont) == nil)
        #expect(demo.identifications.isEmpty)
    }

    /// Cle refusee par le pont (403, puis 401) : un seul envoi, la cle sort du trousseau, le pont est « a lier », comme
    /// pour une lecture ; le message de la fiche le dit.
    @Test(arguments: [403, 401]) func cleRefusee(statut: Int) async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        b.simule.modifier { $0.cleValide = false; $0.statutCleRefusee = statut }
        await b.pont.identifier(ieee: Self.lampe)?.value
        #expect(Self.puts(b).count == 1, "pas de deuxieme envoi avec une cle refusee")
        #expect(b.pont.etat == .aLier && !b.pont.lie && b.trousseau.identifiants.isEmpty)
        #expect(b.pont.identification(ieee: Self.lampe) == .erreur(NomsPont.message(.cleRefusee)))
        // Delie : un nouveau clic est refuse sans rien envoyer.
        #expect(b.pont.identifier(ieee: Self.lampe) == nil)
        #expect(Self.puts(b).count == 1)
    }

    /// Un autre echec (le pont ne connait plus le device : 404 ; reseau coupe) : un seul envoi, un message, le pont
    /// reste lie et sa cle aussi.
    @Test func autresEchecs() async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        b.simule.modifier { $0.reseauCoupe = true }
        await b.pont.identifier(ieee: Self.lampe)?.value
        #expect(b.pont.identification(ieee: Self.lampe) == .erreur(NomsPont.message(.transport(.reseau("coupé")))))
        #expect(Self.puts(b).count == 1 && b.pont.lie && b.trousseau.identifiants == [S.identifiant] && b.pont.etat == .lie)

        // Un device que le pont a perdu depuis la derniere lecture : 404.
        b.simule.modifier { $0.reseauCoupe = false }
        let perdu = NomsMaison(date: NomsPontTests.date, domicile: S.identifiant,
                               accessoires: [AccessoireMaison(nom: "Lampe", ieee: Self.lampe, idHue: "disparu")])
        b.pont.integrer(perdu)
        await b.pont.identifier(ieee: Self.lampe)?.value
        #expect(b.pont.identification(ieee: Self.lampe) == .erreur(NomsPont.message(.http(404, ""))))
        #expect(Self.puts(b).count == 2, "une identification de plus, un seul envoi")
        #expect(b.pont.lie)
    }

    /// « Oublier le pont » pendant une identification : elle s'arrete (aucun autre envoi), et son etat disparait.
    @Test func oubliPendantLIdentification() async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        b.simule.retenir("PUT")
        let tache = try #require(b.pont.identifier(ieee: Self.lampe))
        #expect(await NomsPontTests.sonder { b.simule.retient })
        b.pont.oublier()
        b.simule.liberer()
        await tache.value
        #expect(Self.puts(b).count == 1)
        #expect(b.pont.identification(ieee: Self.lampe) == nil && b.pont.identifications.isEmpty)
    }

    // MARK: L'identifiant du device

    /// L'identifiant du device suit l'appareil : lu sur le pont, garde dans `noms-pont.json`, relu au lancement (avant
    /// toute lecture), et conserve par la fusion avec Maison.
    @Test func identifiantGardeParLeCacheEtLaFusion() async throws {
        let b = try await banc()
        defer { b.pont.arreter() }
        let lu = try #require(b.pont.noms?.accessoire(ieee: Self.lampe))
        #expect(lu.idHue == "d2")
        #expect(b.pont.noms?.accessoire(ieee: "A000000000000001")?.idHue == S.appareilPont)

        let garde = try NomsMaison.lire(Data(contentsOf: b.cache))
        #expect(garde.accessoire(ieee: Self.lampe)?.idHue == "d2" && garde == b.pont.noms)

        // Relu au lancement, sans reseau.
        let c = try NomsPontTests().banc(memoire: NomsPontTests.retenu, cles: [S.identifiant: S.cle], cache: garde)
        defer { c.pont.arreter() }
        c.simule.modifier { $0.reseauCoupe = true }
        c.pont.demarrer()
        #expect(c.pont.peutIdentifier(ieee: Self.lampe), "le bouton est la avant la premiere lecture")
        await c.pont.tacheLecture?.value

        // Fusion avec Maison : le nom change, l'identifiant reste.
        let maison = ReleveMaison(date: NomsPontTests.date, domicile: "Maison inventée",
                                  accessoires: [AccessoireReleve(nom: "Lampe du bureau", piece: "Bureau",
                                                                 fabricant: "Signify Netherlands B.V.", modele: "Hue color lamp")])
        let fusion = try #require(FusionNoms.fusionner(pont: garde, maison: maison).noms)
        let fusionnee = try #require(fusion.accessoire(ieee: Self.lampe))
        #expect(fusionnee.origine == .maison && fusionnee.idHue == "d2")
        #expect(fusion.accessoires.compactMap(\.idHue).sorted() == garde.accessoires.compactMap(\.idHue).sorted())
    }

    /// Un releve garde par une version sans `idHue` se relit (le champ est facultatif) ; un identifiant ecrit se relit.
    @Test func ancienReleveSansIdentifiant() throws {
        let ancien = #"""
            {"version":1,"date":"2027-01-15T08:00:00Z","accessoires":[{"nom":"Lampe","ieee":"A000000000000015"}]}
            """#
        let n = try NomsMaison.lire(Data(ancien.utf8))
        #expect(n.accessoires.first?.idHue == nil)
        var avec = n
        avec.accessoires[0].idHue = "d2"
        #expect(try NomsMaison.lire(avec.donnees()).accessoires.first?.idHue == "d2")
    }
}
