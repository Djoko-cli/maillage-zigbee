import Foundation
import Synchronization
import MaillageCoeur
import Testing
@testable import MaillageZigbee

/// Valeurs inventees : la sonde « SONDE-01 », adresse longue A000000000000001, port USB de serie A0:00:00:00:00:01.
@MainActor
@Suite("Sonde par le reseau : choix du chemin, connexion, bascule", .timeLimit(.minutes(1)))
struct SondeParReseauTests {
    nonisolated static let bonjourReseau = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false,"reseau":true}"#
    nonisolated static let bonjourAutre = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"B000000000000002","membre":true,"role":"final","suspendue":false,"reseau":true}"#
    nonisolated static let cle = String(repeating: "AB", count: 32)

    nonisolated static func sondeReseau(_ ligne: String) -> [String] {
        switch ligne {
        case "bonjour\n": [bonjourReseau]
        case "etat\n": [CanalRejoue.etatAttache]
        default: []
        }
    }

    /// Une sonde retenue (serie, nom, adresse longue), la cle dans un trousseau en memoire.
    static func faire(_ p: UserDefaults, cle: Bool = true, reponses: @escaping @Sendable (String) -> [String] = sondeReseau,
                      muette: Bool = false, ouvertures: Compteur = Compteur(),
                      periodeEntretien: Duration = SondeMaillage.periodeEntretien,
                      delaiCommandeReseau: Duration = SondeMaillage.delaiCommandeReseau) -> SondeMaillage {
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        p.set("A000000000000001", forKey: SondeMaillage.cleIeee)
        let t = TrousseauMemoire(cle ? ["A000000000000001": Self.cle] : [:])
        return SondeMaillage(preferences: p, actif: true, trousseau: t,
                             ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } },
                             ouvrirReseau: { nom, _ in
                                 ouvertures.ajouter(nom)
                                 return muette ? CanalFerme() : CanalRejoue(repondre: reponses)
                             },
                             delaiReessaiReseau: .milliseconds(100),
                             delaiCommandeReseau: delaiCommandeReseau,
                             periodeEntretien: periodeEntretien,
                             delaiPremiereTournee: .seconds(3600))
    }

    @Test func reseauQuandDebranchee() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        guard case .connectee = s.etat else { Issue.record("etat \(s.etat)"); return }
        #expect(o.noms == ["SONDE-01"])
        await s.oublier()
    }

    @Test func usbPrioritaire() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        s.portsChanges([SondeMaillageTests.port])
        #expect(await SondeMaillageTests.sonder { s.acces == .usb })
        await s.oublier()
    }

    @Test func reglageUsbSeulement() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.reglageChemin = .usb
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(o.noms.isEmpty && s.etat == .absente)
        await s.oublier()
    }

    @Test func reglageReseauSeulement() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p)
        s.reglageChemin = .reseau
        s.annoncesChangees(["SONDE-01"])
        s.portsChanges([SondeMaillageTests.port])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        await s.oublier()
    }

    @Test func sansCle() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, cle: false, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(o.noms.isEmpty && s.etat == .absente && !s.cleReseauConnue)
        await s.oublier()
    }

    @Test func autreSondeRefusee() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p, reponses: { $0 == "bonjour\n" ? [SondeParReseauTests.bonjourAutre] : [] })
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { if case .refusee = s.etat { true } else { false } })
        #expect(s.acces == nil)
        await s.oublier()
    }

    @Test func injoignablePuisReessai() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, muette: true, ouvertures: o)  // connexion fermee aussitot : bonjour echoue
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.etat == .injoignable })
        #expect(await SondeMaillageTests.sonder { o.noms.count >= 2 }, "nouvel essai")
        await s.oublier()
    }

    /// La carte a oublie la session (Mac en veille) sans fermer la connexion : la sonde se tait. Une requete sans
    /// reponse dans son delai ferme la liaison, et l'app se reconnecte (constat 3 de la relecture finale).
    @Test func liaisonMuetteRouverte() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let muette = Interrupteur()
        let s = Self.faire(p, reponses: { muette.leve ? [] : SondeParReseauTests.sondeReseau($0) }, ouvertures: o,
                           periodeEntretien: .milliseconds(100), delaiCommandeReseau: .milliseconds(200))
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        muette.lever()
        #expect(await SondeMaillageTests.sonder { o.noms.count >= 2 }, "liaison fermee puis rouverte")
        await s.oublier()
    }

    @Test func reconnexionApresCoupure() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        s.annoncesChangees([])
        #expect(await SondeMaillageTests.sonder { s.etat == .absente && s.acces == nil })
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau && o.noms.count == 2 })
        await s.oublier()
    }
}

/// Un canal qui se ferme des son ouverture (sonde injoignable).
struct CanalFerme: CanalSonde {
    func ouvrir() throws -> AsyncStream<Data> { AsyncStream { $0.finish() } }
    func envoyer(_ ligne: String) {}
    func fermer() {}
}

/// Un drapeau partage entre le test et un canal rejoue.
final class Interrupteur: Sendable {
    private let etat = Mutex(false)
    func lever() { etat.withLock { $0 = true } }
    var leve: Bool { etat.withLock { $0 } }
}

/// Noms des services ouverts par le reseau, dans l'ordre.
final class Compteur: @unchecked Sendable {
    private var valeurs: [String] = []
    private let verrou = NSLock()
    func ajouter(_ n: String) { verrou.withLock { valeurs.append(n) } }
    var noms: [String] { verrou.withLock { valeurs } }
}
