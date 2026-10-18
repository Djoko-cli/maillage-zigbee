import Foundation
import MaillageCoeur
import ServiceManagement
import Testing
@testable import MaillageZigbee

/// « Exporter pour Maillage IoT… » : ce qui se decide sans panneau ni fenetre (le nom propose, la proposition de ne plus
/// ouvrir l'app a la connexion, le bilan), et l'ecriture d'un export sur un dossier temporaire du bac a sable. Les
/// valeurs sont inventees.
@MainActor
@Suite("Export pour Maillage IoT : l'app")
struct ExporteurRepriseTests {
    @Test func leNomProposeCarreLeJourDeLExport() {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "UTC")!
        let jour = Date(timeIntervalSince1970: 1_792_000_000)  // 2026-10-14 17:46 UTC
        #expect(ExporteurReprise.nomParDefaut(date: jour, calendrier: calendrier).hasSuffix(" 2026-10-14"))
        #expect(ExporteurReprise.nomParDefaut(date: jour, calendrier: calendrier).contains("Maillage Zigbee"))
    }

    /// Seulement si l'app s'ouvre a la connexion : sinon, rien a retirer.
    @Test func laPropositionDeNePlusOuvrir() {
        #expect(ExporteurReprise.proposerDeDesactiver(.enabled))
        #expect(!ExporteurReprise.proposerDeDesactiver(.requiresApproval), "inscrite mais pas approuvee : elle ne s'ouvre pas")
        #expect(!ExporteurReprise.proposerDeDesactiver(.notRegistered))
        #expect(!ExporteurReprise.proposerDeDesactiver(.notFound))
    }

    @Test func leLienDeTelechargementEstUneConstanteUnique() {
        // La derniere version publiee de Maillage IoT, comme dans Maillage Thread.
        #expect(AnnonceMaillageIoT.adresseTelechargement == "https://github.com/Djoko-cli/maillage-iot/releases/latest")
        #expect(AnnonceMaillageIoT.url?.host == "github.com")
    }

    @Test func lesErreursSeDisentEnMots() {
        // Le texte est localise : on ne compare pas ses mots, seulement qu'il dit la cause.
        let emplacement = ExporteurReprise.texteErreur(ExportReprise.Erreur.destinationDansLesDonnees)
        let relecture = ExporteurReprise.texteErreur(ExportReprise.Erreur.relecture(.tailleFausse("surnoms.json")))
        #expect(!emplacement.isEmpty && emplacement != relecture)
        #expect(relecture.contains("surnoms.json"), "le fichier de la relecture est cite")
        #expect(!relecture.contains("tailleFausse"), "pas le nom du cas Swift")
    }

    /// Chaque erreur du contrat, levee avant ou pendant la relecture, se dit en mots : le fichier quand il est connu, jamais
    /// le texte generique du systeme ni le nom du cas.
    @Test func chaqueErreurDuContratSeDitEnMots() {
        let f = "surnoms.json"
        let cas: [(ContratExport.Erreur, String?)] = [
            (.formatInconnu(7), "7"), (.appInconnue("zzz"), "zzz"), (.illisible("champ manquant : versionApp"), "versionApp"),
            (.cheminInvalide(f), f), (.lienSymbolique(f), f), (.empreinteInvalide(f), f), (.tailleInvalide(f), f),
            (.cheminEnDouble(f), f), (.nomReserve(f), f), (.valeurInconnue(cle: "sondeNom", type: "date"), "sondeNom"),
            (.cleInvalide, nil), (.cleEnDouble("sondeNom"), "sondeNom"), (.manifesteAbsent, nil), (.reglagesAbsents, nil),
            (.fichierManquant(f), f), (.fichierEnTrop(f), f), (.fichierInconnu(f), f), (.tailleFausse(f), f),
            (.empreinteFausse(f), f), (.appDifferente, nil),
        ]
        var vus = Set<String>()
        for (erreur, mot) in cas {
            let nu = ExporteurReprise.texteErreur(erreur)
            let avant = ExporteurReprise.texteErreur(ExportReprise.Erreur.assemblage(erreur))
            let apres = ExporteurReprise.texteErreur(ExportReprise.Erreur.relecture(erreur))
            for texte in [nu, avant, apres] {
                #expect(!texte.isEmpty)
                #expect(!texte.contains("operation couldn"), "pas le texte generique du systeme : \(erreur)")
                #expect(!texte.contains("ContratExport"), "\(erreur)")
                #expect(!texte.contains("Erreur"), "pas le nom du type : \(erreur)")
                if let mot { #expect(texte.contains(mot), "la cause nomme son objet : \(erreur)") }
            }
            #expect(avant != apres, "l'avant et l'apres relecture ne se disent pas pareil")
            vus.insert(nu)
        }
        #expect(vus.count == cas.count, "chaque cause a son texte")
    }

    /// Un nom de fichier avec un caractere de controle ou trop long est montre sans le caractere ni la demesure.
    @Test func unNomInvalideSAfficheLisiblement() {
        let texte = ExporteurReprise.texteErreur(ExportReprise.Erreur.assemblage(.cheminInvalide("parasite\u{01}\u{07}.json")))
        #expect(texte.contains("parasite") && texte.contains(".json"))
        #expect(!texte.unicodeScalars.contains { $0.properties.generalCategory == .control })
        let long = ExporteurReprise.texteErreur(ExportReprise.Erreur.assemblage(.cheminInvalide(String(repeating: "a", count: 600))))
        #expect(long.count < 300)
    }

    @Test func lAncienDossierNonRestaureDitOuIlEstConserve() {
        let texte = ExporteurReprise.texteErreur(ExportReprise.Erreur.ancienNonRestaure(URL(fileURLWithPath: "/tmp/ancien-export")))
        #expect(texte.contains("/tmp/ancien-export"))
    }

    /// La relecture ratee dit que la destination est restee comme avant (l'ancien dossier, s'il y en avait un, est intact).
    @Test func uneRelectureRateeDitQueLaDestinationEstIntacte() {
        let texte = ExporteurReprise.texteErreur(ExportReprise.Erreur.relecture(.tailleFausse("surnoms.json")))
        let sans = ExporteurReprise.texteErreur(ExportReprise.Erreur.assemblage(.tailleFausse("surnoms.json")))
        #expect(texte != sans)
    }

    /// Le retrait de l'ouverture de session a echoue : une erreur du systeme, ou un etat toujours actif.
    @Test func leRetraitDeLOuvertureEchoue() {
        #expect(ExporteurReprise.retraitEchoue(erreur: "boom", etat: .notRegistered))
        #expect(ExporteurReprise.retraitEchoue(erreur: nil, etat: .enabled), "toujours active malgre l'absence d'erreur")
        #expect(!ExporteurReprise.retraitEchoue(erreur: nil, etat: .notRegistered))
        let avec = ExporteurReprise.texteRetraitEchoue(erreur: "boom")
        #expect(avec.contains("boom"))
        #expect(!ExporteurReprise.texteRetraitEchoue(erreur: nil).isEmpty)
    }

    /// L'export de bout en bout : les fichiers de l'app, les reglages de SON domaine (pas ceux du Mac), le bilan.
    @Test func ecritUnExportRelisible() async throws {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("exporteur-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: racine) }
        let source = racine.appendingPathComponent("Maillage Zigbee")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Journal"), withIntermediateDirectories: true)
        try Data("{\"0000000000000001\":\"Lampe\"}\n".utf8).write(to: source.appendingPathComponent("surnoms.json"))
        try Data("{\"type\":\"veille\"}\n".utf8).write(to: source.appendingPathComponent("Journal/journal-2026-10.jsonl"))
        try Data("x".utf8).write(to: source.appendingPathComponent(".DS_Store"))

        let domaine = "fr.djoko.maillage.zigbee.tests.exporteur-" + UUID().uuidString
        UserDefaults.standard.setPersistentDomain(["sondeNom": "SONDE-Z1", "SUHasLaunchedBefore": true], forName: domaine)
        defer { UserDefaults.standard.removePersistentDomain(forName: domaine) }

        let exporteur = ExporteurReprise(ouverture: OuvertureSession(), source: source, domaine: domaine)
        let destination = racine.appendingPathComponent("Export")
        let r = try await exporteur.ecrire(vers: destination)
        #expect(!exporteur.enCours)
        let (manifeste, reglages) = try ContratExport.verifierDossier(destination)
        #expect(manifeste.versionApp == ExporteurReprise.versionApp)
        #expect(manifeste.fichiers.map(\.chemin) == ["Journal/journal-2026-10.jsonl", "surnoms.json", "reglages.json"])
        #expect(reglages.valeurs == ["sondeNom": .texte("SONDE-Z1")])
        #expect(reglages.nonRepris == ["SUHasLaunchedBefore": .horsContrat])
        #expect(r.manifeste == manifeste)
        #expect(ExporteurReprise.bilan(r).contains("2"), "deux fichiers copies")
        // L'app n'est pas modifiee.
        #expect(try Data(contentsOf: source.appendingPathComponent("surnoms.json")) == Data("{\"0000000000000001\":\"Lampe\"}\n".utf8))
    }
}
