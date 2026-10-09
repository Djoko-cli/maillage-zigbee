import AppKit
import Foundation
@testable import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Vue par pieces : la fenetre")
struct FenetrePiecesTests {
    /// Ce qui est entre les chevrons de la premiere `nom<…>` d'un type imprime, chevrons imbriques
    /// compris ; nil sans `nom<` ni chevron fermant.
    static func entreChevrons(_ nom: String, dans type: String) -> Substring? {
        guard let ouverture = type.range(of: nom + "<") else { return nil }
        var profondeur = 1
        var i = ouverture.upperBound
        while i < type.endIndex {
            switch type[i] {
            case "<": profondeur += 1
            case ">":
                profondeur -= 1
                if profondeur == 0 { return type[ouverture.upperBound..<i] }
            default: break
            }
            i = type.index(after: i)
        }
        return nil
    }

    /// La scene de la fenetre, comme la construit `FenetrePieces` a chaque rendu ; nil sans reseau.
    static func entree(_ s: Surveillance) -> EntreeScene? {
        s.aUnReseau ? EntreeScene(surveillance: s, places: PlacesGardees()) : nil
    }

    /// La vraie fenetre de la vue par pieces, hors ecran, de `taille` pt, sur la surveillance `s`, avec les
    /// preferences `p` (jamais celles de l'app) et « Reduire les animations » impose ; et son moteur (l'etat
    /// `moteur` de la vue). La vue couvre toute la fenetre, de `taille` pt comme dans l'app (`setContentSize`
    /// ajouterait la barre de titre), faite comme celle de l'app (`sansBarreDeTitre`). `sonde` : la sonde de la vue
    /// (sinon une sonde inactive, sans sonde retenue). A retirer par `fermer`.
    static func fenetre(_ s: Surveillance, taille: CGSize, preferences p: UserDefaults,
                        reduire: Bool = false, sonde: SondeMaillage? = nil) throws -> (NSWindow, MoteurPieces) {
        let vue = FenetrePieces(fichierPlaces: nil)
        let etat = try #require(Mirror(reflecting: vue).children.first { $0.label == "_moteur" }?.value)
        let moteur = try #require(Mirror(reflecting: etat).descendant("_value") as? MoteurPieces)
        let fenetre = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: taille.width, height: taille.height),
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
                               defer: false)
        fenetre.isReleasedWhenClosed = false
        Self.sansBarreDeTitre(fenetre)
        fenetre.contentView = NSHostingView(rootView: vue
            .environment(s)
            .environment(NomsPont())
            .environment(sonde ?? SondeMaillage(preferences: p, actif: false))
            .environment(\._accessibilityReduceMotion, reduire)
            .defaultAppStorage(p))
        fenetre.setFrame(NSRect(origin: fenetre.frame.origin, size: taille), display: false)
        fenetre.orderFrontRegardless()
        return (fenetre, moteur)
    }

    static func fermer(_ fenetre: NSWindow) {
        fenetre.orderOut(nil)
        fenetre.contentView = nil
    }

    /// Un clic de la souris sur le point `p` de la vue (en points, depuis le haut), envoye a la fenetre : le vrai
    /// chemin d'un clic, par `sendEvent`, jusqu'au geste ou au bouton de SwiftUI.
    static func cliquer(_ fenetre: NSWindow, en p: CGPoint) async throws {
        let dansFenetre = NSPoint(x: p.x, y: fenetre.frame.height - p.y)
        for (genre, pression) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            let evenement = try #require(NSEvent.mouseEvent(with: genre, location: dansFenetre, modifierFlags: [],
                                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                                            windowNumber: fenetre.windowNumber, context: nil,
                                                            eventNumber: 0, clickCount: 1, pressure: pression))
            fenetre.sendEvent(evenement)
            if genre == .leftMouseDown { try await Task.sleep(for: .milliseconds(10)) }
        }
    }

    /// Duree du recadrage de la vue (les marges en route, `margesEnRoute`) : du premier echantillon ou elles le sont au
    /// premier ou elles ne le sont plus ; nil si elles ne partent pas, ou ne s'arretent pas, en 2 s.
    static func dureeDuRecadrage(_ moteur: MoteurPieces) async throws -> Double? {
        let t0 = ProcessInfo.processInfo.systemUptime
        var debut: Double?
        while ProcessInfo.processInfo.systemUptime - t0 < 2 {
            let t = ProcessInfo.processInfo.systemUptime - t0
            if moteur.margesEnRoute {
                if debut == nil { debut = t }
            } else if let debut {
                return t - debut
            }
            try await Task.sleep(for: .milliseconds(3))
        }
        return nil
    }

    /// Le premier clic sur une piece agit aussi dans une fenetre inactive (verification du 02/10) : sans
    /// `allowsWindowActivationEvents`, AppKit le gardait pour activer la fenetre, et la piece ne s'isolait pas (le
    /// diagnostic l'a reproduit : 0 fois sur 4). Un clic envoye a la vraie fenetre, hors ecran et jamais cle, au
    /// milieu du salon.
    @Test(.timeLimit(.minutes(1))) func premierClicDansUneFenetreInactive() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p)
        defer { Self.fermer(fenetre) }
        // La vue en place : la disposition posee, la legende mesuree, les marges arrivees.
        try await MoteurPiecesTests.attendre {
            moteur.pret && moteur.projetee != nil && moteur.cadresInterface["legende"] != nil && !moteur.margesEnRoute
        }
        try await Task.sleep(for: .milliseconds(500))
        let salon = try MoteurPiecesTests.indice(try #require(moteur.entree), "Salon")
        // Un point du salon ou un clic l'isole : sur sa boite, loin des pastilles, des noms et de l'interface.
        let ancre = try #require(moteur.projetee?.ancresPieces[salon])
        let points = stride(from: 0.9, through: 0.1, by: -0.1).flatMap { fy in
            stride(from: 0.9, through: 0.1, by: -0.1).map { fx in
                CGPoint(x: ancre.minX + ancre.width * fx, y: ancre.minY + ancre.height * fy)
            }
        }
        let point = try #require(points.first { p in
            moteur.pieceSous(p) == salon && moteur.noeudSous(p) == nil
                && !moteur.cadresInterface.values.contains { $0.insetBy(dx: -4, dy: -4).contains(p) }
        })
        #expect(moteur.focus == nil && !fenetre.isKeyWindow, "une fenetre inactive, sans piece isolee")
        try await Self.cliquer(fenetre, en: point)
        try await MoteurPiecesTests.attendre { moteur.focus != nil }
        #expect(moteur.focus == salon && moteur.estIsolee, "le premier clic isole la piece (focus \(String(describing: moteur.focus)))")
    }

    /// « Ancien » (6 min) et « perime » (15 min) ne dependent que de l'heure, que rien n'observe : la
    /// fenetre est une `TimelineView` qui se redessine chaque minute (`FenetrePieces.horloge`), avec
    /// dedans tout ce qui lit l'heure (le haut de la fenetre et sa pastille d'un releve ancien, la scene,
    /// la fiche).
    @Test func redessinChaqueMinute() throws {
        let horloge = String(reflecting: type(of: FenetrePieces.horloge))
        let corps = String(reflecting: FenetrePieces.Body.self)
        let dedans = try #require(Self.entreChevrons("TimelineView", dans: corps), "le corps est une TimelineView")
        #expect(dedans.hasPrefix(horloge), "sur l'horloge")
        for vue in ["HautPieces", "LigneDuBas", "VuePieces", "FicheNoeud"] {
            #expect(dedans.contains(vue), "\(vue) est dans la TimelineView, pas a cote")
        }
        let recu = Date(timeIntervalSince1970: 1_790_000_000)
        let redessins = FenetrePieces.horloge.entries(from: recu, mode: .normal).prefix(20).filter { $0 >= recu }
        #expect(zip(redessins, redessins.dropFirst()).allSatisfy { $1.timeIntervalSince($0) <= 60 })
    }

    /// La marge du haut de la vue d'ensemble suit la hauteur mesuree du haut de la fenetre (la ligne des
    /// capsules, la tournee, les bandeaux, le fil, la ligne de niveau) : son bas, arrondi, et l'espacement ; un
    /// bandeau ou la ligne de la tournee la font grandir. Celle du bas, mesuree elle aussi : `margeDuBasMesuree`.
    @Test(.timeLimit(.minutes(1))) func marges() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let sonde = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } })
        let noms = NomsPont()
        let demo = NomsSceneTests.surveillanceDemo()
        let sansReseau = Surveillance(mode: .direct, dossier: nil)
        func haut(_ s: Surveillance, sansPieces: Bool) -> CGFloat {
            let vue = HautPieces(moteur: MoteurPieces(), troisD: .constant(true), sansPieces: sansPieces)
            return NSHostingView(rootView: vue.environment(s).environment(sonde).environment(noms)).fittingSize.height
        }
        #expect(FenetrePieces.margeHaut(bas: 57.2) == 58 + FenetrePieces.espacement, "le bas arrondi, et l'espacement")
        let seul = haut(sansReseau, sansPieces: false)
        let scinde = haut(demo, sansPieces: false)
        #expect(seul > 2 * CadreFeux.defaut.milieu + RangeeNiveau.hauteur, "la ligne des capsules, le fil, la ligne de niveau")
        // La premiere estimation (avant toute mesure : la ligne des capsules, le fil, la ligne de niveau) n'est pas
        // au-dessus de la mesure, sans bandeau ni tournee : la vue ne se recadre pas vers le haut a la premiere mesure.
        #expect(FenetrePieces.margeHautInitiale <= FenetrePieces.margeHaut(bas: seul), "la premiere estimation : \(FenetrePieces.margeHautInitiale)")
        #expect(scinde == seul, "pas de bandeau de scission en Zigbee")
        #expect(haut(demo, sansPieces: true) > scinde, "le bandeau d'une maison sans pieces")
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        sonde.debuterTournee()
        sonde.avancer(AvancementTournee(etape: .tables, fait: 1, total: 3))
        #expect(haut(demo, sansPieces: false) > scinde, "la ligne de la tournee")
        #expect(FenetrePieces.margeHaut(bas: haut(demo, sansPieces: false)) > FenetrePieces.margeHaut(bas: scinde))
        await sonde.oublier()
    }

    /// Ce qui est pose en bas de la vraie fenetre : la pile, de haut en bas la legende, puis la fiche ; son haut, le
    /// plus haut des cadres de ses elements (nil avant qu'ils soient poses).
    static func hautDeLaPile(_ moteur: MoteurPieces) -> CGFloat? {
        ["legende", "fiche"].compactMap { moteur.cadresInterface[$0] }.map(\.minY).min()
    }

    /// Le bas du haut de la vraie fenetre, mesure sur ses cadres : la rangee de la ligne de niveau, la derniere de la
    /// colonne (nil avant qu'elle soit posee). La marge du haut le compte, avec la place de la tournee absente.
    static func basDuHaut(_ moteur: MoteurPieces) -> CGFloat? {
        moteur.cadresInterface["niveau"].map { $0.midY + RangeeNiveau.hauteur / 2 }
    }

    /// La marge du bas suit la hauteur mesuree de tout ce qui est pose en bas (verification du 02/10, comme la marge
    /// du haut suit le bandeau ; elle remplace les 190 et 360 pt fixes de la fiche) : dans la vraie fenetre, fiche
    /// fermee ou ouverte, legende ouverte ou repliee, la vue d'ensemble se cadre juste au-dessus de la pile (a
    /// l'espacement pres), la legende seule ou avec la fiche (la ligne de niveau est en haut), sauf la legende repliee
    /// sans fiche, qui deborde un peu sur la vue (30 pt, la marge d'avant). La fiche la plus haute de la demo, et une
    /// fiche avec les courbes de l'historique, y tiennent aussi.
    @Test(.timeLimit(.minutes(2))) func margeDuBasMesuree() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        let taille = CGSize(width: 1100, height: 760)
        // La vue se cadre juste au-dessus de la pile (le bas de son cadre, a l'espacement pres).
        func auDessusDeLaPile(_ moteur: MoteurPieces, _ taille: CGSize, _ cas: String) async throws {
            try await MoteurPiecesTests.attendre {
                Self.hautDeLaPile(moteur).map { abs((taille.height - moteur.marges.bas) - ($0 - FenetrePieces.espacement)) < 1 } == true
            }
            let haut = try #require(Self.hautDeLaPile(moteur), "\(cas) : la pile du bas")
            #expect(abs((taille.height - moteur.marges.bas) - (haut - FenetrePieces.espacement)) < 1,
                    "\(cas) : la vue finit a \(taille.height - moteur.marges.bas), la pile commence a \(haut)")
        }
        for repliee in [false, true] {
            // La preference, avant la fenetre : `@AppStorage` la lit a l'ouverture.
            p.set(repliee, forKey: LegendePieces.cleRepliee)
            let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p)
            defer { Self.fermer(fenetre) }
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil && moteur.pret }
            if repliee {
                try await MoteurPiecesTests.attendre { moteur.marges.bas == 30 && moteur.cadresInterface["fiche"] == nil }
                #expect(moteur.marges.bas == 30, "legende repliee, sans fiche : la marge d'avant")
            } else {
                try await auDessusDeLaPile(moteur, taille, "legende ouverte, sans fiche")
            }
            for id in [NomsDemo.Ieee.pont, NomsDemo.Ieee.telecommandeChambre] {
                moteur.selection = id
                try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] != nil }
                try await auDessusDeLaPile(moteur, taille, "legende \(repliee ? "repliee" : "ouverte"), fiche de \(id)")
            }
        }
        // Une fiche avec les courbes de l'historique, dans une grande fenetre (la legende y reste ouverte).
        p.set(false, forKey: LegendePieces.cleRepliee)
        let historique = try CourbesFicheTests.surveillance()
        #expect(FicheNoeud.courbesVisibles(dans: historique))
        let grande = CGSize(width: 1400, height: 1100)
        let (autre, m) = try Self.fenetre(historique, taille: grande, preferences: p)
        defer { Self.fermer(autre) }
        try await MoteurPiecesTests.attendre { m.cadresInterface["legende"] != nil && m.pret }
        m.selection = JournalMaillageTests.appareil
        try await MoteurPiecesTests.attendre { m.cadresInterface["fiche"].map { $0.height > 250 } == true }
        let fiche = try #require(m.cadresInterface["fiche"])
        #expect(fiche.height > 250, "la fiche et ses courbes : \(fiche.height) pt")
        try await auDessusDeLaPile(m, grande, "fiche avec courbes")
    }

    /// Une fenetre ou la legende ouverte tient au-dessus de la fiche d'un appareil de la demo : depuis la fiche en quatre
    /// colonnes (etape 5), plus haute, plus celle par defaut (1100 x 760), ou elle se replie faute de place.
    static let hauteAssez = CGSize(width: 1100, height: 880)

    /// La legende reste visible quand une fiche est ouverte (verification du 02/10) : elle monte au-dessus de la fiche
    /// au lieu de disparaitre. De haut en bas : la legende, puis la fiche ; la vue d'ensemble se cadre au-dessus de
    /// tout cela. A la fermeture, la fiche part et la legende redescend.
    @Test(.timeLimit(.minutes(1))) func legendeAuDessusDeLaFiche() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        let taille = Self.hauteAssez
        let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil }
        let ouverte = try #require(moteur.cadresInterface["legende"])
        moteur.selection = NomsDemo.Ieee.detecteurEntree
        // La fiche arrivee : son cadre suit son glissement, puis s'arrete au bas de la vue.
        try await MoteurPiecesTests.attendre {
            moteur.cadresInterface["fiche"].map { abs($0.maxY - (taille.height - FenetrePieces.bord)) < 0.5 } == true
        }
        let legende = try #require(moteur.cadresInterface["legende"], "la legende reste")
        let fiche = try #require(moteur.cadresInterface["fiche"])
        #expect(legende.size == ouverte.size, "ouverte, comme sans fiche : \(legende.size), \(ouverte.size)")
        #expect(legende.maxY <= fiche.minY - FenetrePieces.espacement + 0.5,
                "la legende au-dessus de la fiche : \(legende), \(fiche)")
        #expect(abs(fiche.maxY - (taille.height - FenetrePieces.bord)) < 0.5, "la fiche en bas : \(fiche)")
        try await MoteurPiecesTests.attendre { !moteur.margesEnRoute && taille.height - moteur.marges.bas <= legende.minY }
        #expect(moteur.cadre.maxY <= legende.minY, "la vue au-dessus de la legende : \(moteur.cadre)")
        moteur.selection = nil
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] == nil }
        let revenue = try #require(moteur.cadresInterface["legende"])
        #expect(abs(revenue.maxY - (taille.height - FenetrePieces.bord)) < 0.5, "la legende redescendue : \(revenue)")
    }

    /// Dans une petite fenetre, la legende se replie d'elle-meme tant qu'une fiche est ouverte, si, ouverte, elle ne
    /// laissait a la scene que moins de 230 pt (`FenetrePieces.sceneMinimale`) ; elle se rouvre a la fermeture de la
    /// fiche. Elle ne se replie que si c'est necessaire : pas dans une fenetre assez haute avec une fiche de la demo.
    /// Son repli garde (la preference) ne change pas, et une legende repliee par Djoko reste repliee. La plus petite
    /// fenetre (`tailleMinimale`) : la vue y fait 732 pt de haut, barre de titre de 52 pt comprise. La zone visible de la
    /// grille (`basGrille`, polissage C, section 3.3) garde la legende telle que Djoko l'a laissee : ni la fiche, ni le
    /// repli de la legende sous elle n'y changent rien.
    @Test(.timeLimit(.minutes(2))) func repliDeLaLegendeFauteDePlace() async throws {
        // Le seuil.
        let m = FenetrePieces.sceneMinimale
        #expect(m == 230)
        let marge = FenetrePieces.margeBas(pile: 220 + FenetrePieces.espacement + 150)
        #expect(!FenetrePieces.repliDePlace(hauteur: 98 + marge + m, margeHaut: 98, legende: 220, fiche: 150), "230 pt : assez")
        #expect(FenetrePieces.repliDePlace(hauteur: 98 + marge + m - 1, margeHaut: 98, legende: 220, fiche: 150), "229 pt : repliee")
        #expect(!FenetrePieces.repliDePlace(hauteur: 300, margeHaut: 98, legende: nil, fiche: 150), "legende jamais mesuree ouverte")
        #expect(!FenetrePieces.repliDePlace(hauteur: 300, margeHaut: 98, legende: 220, fiche: nil), "fiche pas encore mesuree")
        // Dans la vraie fenetre.
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        func essai(_ s: Surveillance, _ taille: CGSize, _ id: String, repliee: Bool) async throws -> (ficheOuverte: CGFloat, apres: CGFloat) {
            p.set(repliee, forKey: LegendePieces.cleRepliee)
            let (fenetre, moteur) = try Self.fenetre(s, taille: taille, preferences: p)
            defer { Self.fermer(fenetre) }
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil && moteur.pret }
            try await Task.sleep(for: .milliseconds(200))
            // La zone de la grille : la legende telle que Djoko l'a laissee, ouverte (sa hauteur mesuree) ou repliee (30 pt).
            let zone = FenetrePieces.margeBas(pile: repliee ? nil : moteur.cadresInterface["legende"]?.height)
            #expect(moteur.basGrille == zone, "\(id), \(taille) : la legende, sans fiche")
            moteur.selection = id
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] != nil }
            try await Task.sleep(for: .milliseconds(400))
            let ouverte = try #require(moteur.cadresInterface["legende"], "la legende reste, repliee ou non").height
            // Sous la fiche, la marge du cadre compte la fiche ; celle de la grille, non (decision de Djoko du 03/10).
            #expect(moteur.basGrille == zone && moteur.marges.bas != zone, "\(id), \(taille) : la fiche ne compte pas dans la zone de la grille")
            moteur.selection = nil
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] == nil }
            try await Task.sleep(for: .milliseconds(400))
            let apres = try #require(moteur.cadresInterface["legende"]).height
            #expect(moteur.basGrille == zone, "\(id), \(taille) : la fiche fermee")
            #expect(p.bool(forKey: LegendePieces.cleRepliee) == repliee, "\(id), \(taille) : le repli garde ne change pas")
            return (ouverte, apres)
        }
        let petite = FenetrePieces.tailleMinimale
        let defaut = CGSize(width: 1100, height: 760)
        let haute = Self.hauteAssez
        // Petite fenetre, fiche de la demo : repliee faute de place, puis rouverte.
        let (sousPetite, apresPetite) = try await essai(demo, petite, NomsDemo.Ieee.pont, repliee: false)
        #expect(sousPetite < 40 && apresPetite > 150, "820 x 680 : repliee sous la fiche (\(sousPetite)), rouverte ensuite (\(apresPetite))")
        // Fenetre assez haute, fiche d'un appareil de la demo : la place suffit, elle reste ouverte (dans la fenetre par
        // defaut, la fiche en quatre colonnes de l'etape 5 la fait replier).
        let (sousHaute, _) = try await essai(demo, haute, NomsDemo.Ieee.detecteurEntree, repliee: false)
        #expect(sousHaute > 150, "1100 x 880 : ouverte au-dessus de la fiche (\(sousHaute))")
        // Fenetre par defaut, fiche avec ses courbes : repliee.
        let historique = try CourbesFicheTests.surveillance()
        let (sousCourbes, apresCourbes) = try await essai(historique, defaut, JournalMaillageTests.appareil, repliee: false)
        #expect(sousCourbes < 40 && apresCourbes > 100, "fiche avec courbes : repliee (\(sousCourbes)), rouverte (\(apresCourbes))")
        // Repliee par Djoko : elle le reste.
        let (sousGardee, apresGardee) = try await essai(demo, petite, NomsDemo.Ieee.pont, repliee: true)
        #expect(sousGardee < 40 && apresGardee < 40, "repliee par Djoko : elle le reste (\(sousGardee), \(apresGardee))")
    }

    /// Une legende que Djoko ouvre a la main, sans fiche, n'empeche pas son repli faute de place sous la fiche qui
    /// parait ensuite : seul compte un « rouvert » fait sous une fiche (`FenetrePieces.legendeRouverte`), et la fiche
    /// qui parait efface le drapeau. Dans la plus petite fenetre, la legende, repliee par la preference, est ouverte
    /// d'un vrai clic sur son etiquette ; la fiche de l'Apple TV 4K ouverte, elle se replie quand meme. La zone visible de
    /// la grille garde alors la legende ouverte, le repli faute de place n'y comptant pas ; si Djoko la replie sous la
    /// fiche (le repli garde), elle suit son choix : 30 pt.
    @Test(.timeLimit(.minutes(2))) func ouvertureManuelleSansFicheLaisseLeRepliAutomatique() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(true, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: FenetrePieces.tailleMinimale, preferences: p)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil && moteur.pret }
        try await Task.sleep(for: .milliseconds(500))
        let etiquette = try #require(moteur.cadresInterface["legende"])
        try await Self.cliquer(fenetre, en: CGPoint(x: etiquette.midX, y: etiquette.midY))
        try await MoteurPiecesTests.attendre { (moteur.cadresInterface["legende"]?.height ?? 0) > 150 }
        #expect((moteur.cadresInterface["legende"]?.height ?? 0) > 150, "ouverte d'un clic")
        let ouverte = try #require(moteur.cadresInterface["legende"]).height
        moteur.selection = NomsDemo.Ieee.pont
        try await Task.sleep(for: .milliseconds(1000))
        #expect((moteur.cadresInterface["legende"]?.height ?? 999) < 40,
                "sous la fiche, dans la plus petite fenetre, la legende se replie : scene de \(moteur.cadre.height) pt")
        #expect(moteur.basGrille == FenetrePieces.margeBas(pile: ouverte), "repli de place : la zone de la grille ne bouge pas")
        p.set(true, forKey: LegendePieces.cleRepliee)
        try await MoteurPiecesTests.attendre { moteur.basGrille == 30 }
        #expect(moteur.basGrille == 30, "repli garde par Djoko, sous la fiche : 30 pt")
    }

    /// Taille minimale du contenu de la fenetre : 820 x 680 pt, sous la barre de titre cachee (la fenetre, elle, fait
    /// 732 pt de haut au moins, avec la barre d'outils invisible).
    @Test func tailleMinimale() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let s = Surveillance(mode: .direct, dossier: nil)
        let vue = FenetrePieces(fichierPlaces: nil)
            .environment(s)
            .environment(NomsPont())
            .environment(SondeMaillage(preferences: p, actif: false))
        #expect(FenetrePieces.tailleMinimale == CGSize(width: 820, height: 680))
        #expect(NSHostingView(rootView: vue).fittingSize == FenetrePieces.tailleMinimale)
    }

    /// La legende, seule en bas (la ligne de niveau et la pastille d'un releve ancien sont montees en haut), est en bas a
    /// gauche de la vraie fenetre, au bord (polissage B, section 2), et non au milieu : a la taille par defaut (1100 pt
    /// de large) comme a la taille minimale. Sous une fiche, elle reste au bord, au-dessus de la fiche (verification
    /// du 02/10), ouverte ou repliee faute de place ; la fiche fermee, elle revient a sa place. La marge du bas suit
    /// la hauteur mesuree de la legende seule, puis de la legende et de la fiche : la ligne de niveau n'y compte plus.
    /// Les images de demo ne le montrent pas : `VueCapture` refait sa mise en page, alignee a gauche.
    @Test(.timeLimit(.minutes(1)), arguments: [CGSize(width: 1100, height: 760), CGSize(width: 820, height: 680)])
    func rangeeDuBasAGauche(_ taille: CGSize) async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        // Un releve de la sonde ancien (plus de 6 min) : sa pastille est en haut, et ne compte pas en bas.
        demo.recevoir(try #require(demo.maillage), a: demo.maintenant.addingTimeInterval(-17 * 60))
        #expect(demo.maillageAncien)
        // La vraie fenetre, hors ecran, avec son moteur (l'etat `moteur` de la vue) et des preferences a part.
        let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p)
        defer { Self.fermer(fenetre) }
        func cadre(_ cle: String) throws -> CGRect { try #require(moteur.cadresInterface[cle], "le cadre « \(cle) »") }
        let cas = "fenetre de \(Int(taille.width)) pt"

        // Fiche fermee : la legende au bord.
        try await MoteurPiecesTests.attendre { ["legende", "niveau", "ancien"].allSatisfy { moteur.cadresInterface[$0] != nil } }
        // La hauteur de la vue, mise en page : la fenetre ne descend pas sous sa taille minimale, 680 pt sous la barre
        // de titre, soit 732 pt en tout.
        let hauteur = fenetre.frame.height
        #expect(hauteur >= taille.height)
        let legende = try cadre("legende")
        #expect(legende.minX == FenetrePieces.bord, "\(cas) : la legende est au bord gauche (x = \(legende.minX))")
        #expect(abs(legende.maxY - (hauteur - FenetrePieces.bord)) < 0.5, "\(cas) : la legende est en bas : \(legende)")
        let niveau = try cadre("niveau")
        #expect(niveau.maxY < legende.minY, "\(cas) : la ligne de niveau n'est plus en bas, avec la legende")
        // La marge du bas : la pile mesuree (son haut, le plus haut des cadres), le bord et l'espacement, a l'arrondi pres ;
        // la legende seule, sans la ligne de niveau.
        func margeDeLaPile() throws -> CGFloat {
            FenetrePieces.margeBas(pile: hauteur - FenetrePieces.bord - (try #require(Self.hautDeLaPile(moteur))))
        }
        let ouverte = try margeDeLaPile()
        #expect(abs(ouverte - FenetrePieces.margeBas(pile: legende.height)) <= 1, "\(cas) : la legende seule : \(ouverte)")
        try await MoteurPiecesTests.attendre { abs(moteur.marges.bas - ouverte) <= 1 }
        #expect(abs(moteur.marges.bas - ouverte) <= 1, "\(cas) : la marge du bas suit la legende ouverte (\(moteur.marges.bas), \(ouverte), \(moteur.cadresInterface))")

        // Fiche ouverte : la legende reste au bord, au-dessus de la fiche.
        moteur.selection = NomsDemo.Ieee.pont
        try await MoteurPiecesTests.attendre {
            moteur.cadresInterface["fiche"].map { f in moteur.cadresInterface["legende"].map { $0.maxY <= f.minY } == true } == true
        }
        let fiche = try cadre("fiche")
        let legendeSurFiche = try cadre("legende")
        #expect(legendeSurFiche.minX == FenetrePieces.bord, "\(cas) : la legende reste au bord (x = \(legendeSurFiche.minX))")
        #expect(legendeSurFiche.maxY <= fiche.minY, "\(cas) : la legende au-dessus de la fiche")
        #expect(fiche.minX == FenetrePieces.bord && fiche.width == taille.width - 2 * FenetrePieces.bord, "\(cas) : la fiche, \(fiche)")
        let surFiche = try margeDeLaPile()
        try await MoteurPiecesTests.attendre { abs(moteur.marges.bas - surFiche) <= 1 }
        #expect(abs(moteur.marges.bas - surFiche) <= 1, "\(cas) : la marge du bas suit la legende et la fiche (\(moteur.marges.bas), \(surFiche))")

        // Fiche fermee : la legende revient a sa place, et la marge.
        moteur.selection = nil
        try await MoteurPiecesTests.attendre {
            moteur.cadresInterface["fiche"] == nil && moteur.cadresInterface["legende"]?.size == legende.size
        }
        let legendeRevenue = try cadre("legende")
        #expect(legendeRevenue == legende, "\(cas) : la legende est revenue a sa place (\(legendeRevenue))")
        try await MoteurPiecesTests.attendre { abs(moteur.marges.bas - ouverte) <= 1 }
        #expect(abs(moteur.marges.bas - ouverte) <= 1, "\(cas) : la marge du bas est revenue a celle de la legende ouverte")
    }

    /// La ligne de niveau est en haut a gauche (decision de Djoko du 02/10), dans la colonne de gauche, juste sous le
    /// fil « Maison », contre le bord gauche ; la pastille d'un releve de la sonde ancien est a cote d'elle, dans la
    /// meme colonne. Les noms de la scene evitent ces nouvelles places (`cadresInterface`). Et la marge du haut de la
    /// vue d'ensemble compte la ligne de niveau, qui est toujours la : elle ne change ni quand la ligne change de
    /// texte (le zoom, une piece isolee, dont le texte est le plus long), ni quand la pastille parait ou repart.
    @Test(.timeLimit(.minutes(1)), arguments: [CGSize(width: 1100, height: 760), CGSize(width: 820, height: 680)])
    func ligneDeNiveauSousLeFil(_ taille: CGSize) async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        let maillage = try #require(demo.maillage)
        let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p)
        defer { Self.fermer(fenetre) }
        func cadre(_ cle: String) throws -> CGRect { try #require(moteur.cadresInterface[cle], "le cadre « \(cle) »") }
        func stable() async throws {
            try await MoteurPiecesTests.attendre { moteur.pret && moteur.cadresInterface["niveau"] != nil && !moteur.margesEnRoute }
            try await Task.sleep(for: .milliseconds(400))
        }
        let cas = "fenetre de \(Int(taille.width)) pt"
        try await stable()
        // Sous le fil, contre le bord gauche, au-dessus de la scene : le haut de la fenetre, pas le bas.
        let colonne = try cadre("colonne")
        var niveau = try cadre("niveau")
        let legende = try cadre("legende")
        #expect(niveau.minX == FenetrePieces.bord, "\(cas) : la ligne de niveau au bord gauche : \(niveau)")
        #expect(abs(niveau.midY - (colonne.maxY + FenetrePieces.espacementNiveau + RangeeNiveau.hauteur / 2)) < 0.5,
                "\(cas) : juste sous le fil (le bas de la colonne), \(colonne), \(niveau)")
        #expect(niveau.maxY < legende.minY, "\(cas) : en haut, pas en bas avec la legende")
        #expect(niveau.height <= RangeeNiveau.hauteur, "\(cas) : une seule ligne : \(niveau.height) pt")
        let marge = moteur.marges.haut
        let bas = try #require(Self.basDuHaut(moteur))
        #expect(abs(marge - FenetrePieces.margeHaut(bas: bas)) < 1, "\(cas) : la marge compte la ligne de niveau : \(marge), \(bas)")
        #expect(moteur.cadresInterface["ancien"] == nil, "\(cas) : pas de pastille d'un releve recent")

        // Le texte de la ligne change au fil des zooms et d'une piece isolee, dont la ligne est la plus longue : la marge
        // du haut ne bouge pas, ni la colonne.
        var marges: Set<CGFloat> = []
        var textes: Set<String> = [LigneNiveauVue.texte(moteur.ligneNiveau)]
        var largeurs: Set<CGFloat> = [niveau.width]
        func echantillonner(_ duree: Double) async throws {
            let t0 = ProcessInfo.processInfo.systemUptime
            while ProcessInfo.processInfo.systemUptime - t0 < duree {
                marges.insert(moteur.marges.haut)
                textes.insert(LigneNiveauVue.texte(moteur.ligneNiveau))
                if let n = moteur.cadresInterface["niveau"] {
                    largeurs.insert(n.width)
                    #expect(n.minY == niveau.minY && n.minX == niveau.minX, "\(cas) : la ligne de niveau ne bouge pas : \(n)")
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        for dy in [-40.0, -40.0, 80.0, 80.0, 80.0] {
            moteur.molette(dy, precis: false)
            moteur.reveiller()
            try await echantillonner(0.3)
        }
        moteur.isoler(0)
        moteur.reveiller()
        try await echantillonner(0.5)
        #expect(textes.count >= 2, "\(cas) : la ligne a change de texte : \(textes)")
        #expect(largeurs.count >= 2, "\(cas) : et de largeur : \(largeurs)")
        #expect(marges == [marge], "\(cas) : la marge du haut ne change pas avec le texte de la ligne : \(marges)")
        niveau = try cadre("niveau")
        #expect(niveau.maxX <= taille.width - HautPieces.bordDroit, "\(cas) : coupee a la fenetre : \(niveau)")
        let isolee = try cadre("colonne")
        #expect(isolee.minX == colonne.minX && isolee.minY == colonne.minY && isolee.height == colonne.height,
                "\(cas) : la colonne ne bouge pas, hors sa largeur (le fil de la piece isolee) : \(isolee)")

        // La pastille d'un releve ancien : a cote de la ligne de niveau, dans la colonne ; la marge ne bouge pas.
        demo.recevoir(maillage, a: demo.maintenant.addingTimeInterval(-17 * 60))
        #expect(demo.maillageAncien)
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["ancien"] != nil }
        try await stable()
        let ancien = try cadre("ancien")
        niveau = try cadre("niveau")
        #expect(ancien.minX >= niveau.maxX && abs(ancien.midY - niveau.midY) < 0.5,
                "\(cas) : la pastille a cote de la ligne de niveau : \(ancien), \(niveau)")
        let basAvecPastille = try #require(Self.basDuHaut(moteur))
        #expect(ancien.minY >= colonne.maxY && ancien.maxY <= basAvecPastille + 0.5,
                "\(cas) : dans la colonne, sous le fil : \(ancien)")
        #expect(niveau.minX == FenetrePieces.bord, "\(cas) : la ligne de niveau ne bouge pas avec la pastille")
        #expect(moteur.marges.haut == marge, "\(cas) : la marge du haut ne change pas avec la pastille : \(moteur.marges.haut)")
        #expect(try cadre("colonne").height == colonne.height, "\(cas) : la colonne ne bouge pas, avec la pastille")
        demo.recevoir(maillage, a: demo.maintenant)
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["ancien"] == nil }
        try await stable()
        #expect(moteur.marges.haut == marge, "\(cas) : ni quand elle repart : \(moteur.marges.haut)")
    }

    /// La fiche et les bandeaux du haut glissent avec un fondu, en 0,3 s, sur la courbe de la maquette
    /// (`cubic-bezier(.2, .8, .2, 1)`) : la fiche depuis le bas, un bandeau depuis le haut ; avec
    /// « Reduire les animations », un fondu simple.
    @Test func apparitions() {
        #expect(Apparition.pour(.bottom, reduire: false) == .glisse(.bottom))
        #expect(Apparition.pour(.top, reduire: false) == .glisse(.top))
        #expect(Apparition.pour(.bottom, reduire: true) == .fondu)
        #expect(Apparition.pour(.top, reduire: true) == .fondu)
        #expect(Apparition.duree == 0.3)
        #expect(Apparition.courbe(0) == 0 && Apparition.courbe(1) == 1)
        #expect(abs(Apparition.courbe(0.5) - 0.946) < 0.002, "\(Apparition.courbe(0.5))")
        let points = stride(from: 0.0, through: 1, by: 0.05).map(Apparition.courbe)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0 < $1 }, "croissante")
    }

    /// Avec « Reduire les animations », rien ne glisse (spec de B, sections 1 et 3 : « un simple fondu ») : la fiche
    /// et les bandeaux se fondent, chacun par sa transition, qui porte son propre fondu (`transitionAnimee`) ; ce
    /// qui se decale autour d'eux (la rangee du bas, qui monte au-dessus de la fiche, le fil sous un bandeau) prend
    /// sa place sans animation : celle du conteneur est nulle. Sans le reglage, rien ne change : cela glisse avec
    /// l'element, sur la courbe de la maquette.
    @Test func reduireLesAnimationsSansGlissement() {
        let courbe = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)
        let fondu = Animation.easeInOut(duration: 0.3)
        #expect(courbe != fondu, "les deux se distinguent")
        for bord in [Edge.bottom, .top] {
            #expect(Apparition.animationDuConteneur(bord, reduire: false) == courbe, "\(bord) : sans le reglage, la courbe de la maquette")
            #expect(Apparition.pour(bord, reduire: false).animation == courbe, "\(bord) : l'element glisse sur la meme courbe")
            #expect(Apparition.animationDuConteneur(bord, reduire: true) == nil, "\(bord) : avec le reglage, rien ne se decale en glissant")
            #expect(Apparition.pour(bord, reduire: true).animation == fondu, "\(bord) : l'element se fond")
        }
    }

    /// L'ouverture et le repli de la legende sont un peu plus lents que la fiche (verification du 02/10 : Djoko
    /// trouvait l'ouverture « un poil trop fugace ») : 0,45 s au lieu de 0,3 s, sur la meme courbe, pour la legende
    /// et sa rangee ; avec « Reduire les animations », un fondu de 0,45 s, et rien ne glisse. La fiche et les bandeaux restent a 0,3 s. Le recadrage qui accompagne la
    /// legende prend sa duree (`MoteurPiecesTests.margesQuiGlissentAvecLaLegende`) ; apres un vrai clic dans la
    /// vraie fenetre, `recadrageDeLaLegendeApresUnClic` le mesure.
    @Test func dureeDeLaLegende() {
        let courbe = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)
        #expect(Apparition.dureeLegende == 0.45)
        #expect(Apparition.duree == 0.3, "la fiche et les bandeaux")
        #expect(Apparition.animationLegende(reduire: false) == courbe)
        #expect(Apparition.animationLegende(reduire: true) == .easeInOut(duration: 0.45))
        #expect(Apparition.animationDuConteneurLegende(reduire: false) == courbe)
        #expect(Apparition.animationDuConteneurLegende(reduire: true) == nil, "avec le reglage, rien ne se decale en glissant")
    }

    /// Un vrai clic sur l'etiquette de la legende (son en-tete, ouverte), dans la vraie fenetre, recadre la vue en
    /// 0,45 s (`Apparition.dureeLegende`), pour son repli comme pour son ouverture, avec le reglage (un fondu de cette
    /// duree) comme sans ; la fiche, elle, la recadre en 0,3 s. `dureeDeLaLegende` ne garde que les fonctions : ici,
    /// le clic passe par la legende (`LigneDuBas`), qui annonce sa duree au moteur (`legendeBasculee`), puis par le
    /// recadrage lui-meme. La transition de la legende (`Apparition.transitionLegende`) ne s'observe pas par la
    /// geometrie : ce test ne la garde pas.
    @Test(.timeLimit(.minutes(2)), arguments: [false, true])
    func recadrageDeLaLegendeApresUnClic(reduire: Bool) async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p,
                                                 reduire: reduire)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["legende"] != nil && moteur.pret && !moteur.margesEnRoute }
        try await Task.sleep(for: .milliseconds(600))
        // Ouverte : un clic sur son en-tete la replie.
        var legende = try #require(moteur.cadresInterface["legende"])
        try await Self.cliquer(fenetre, en: CGPoint(x: legende.minX + 40, y: legende.minY + 16))
        let repli = try #require(try await Self.dureeDuRecadrage(moteur))
        #expect(abs(repli - Apparition.dureeLegende) < 0.07, "repli par clic : \(repli) s")
        try await Task.sleep(for: .milliseconds(600))
        // Repliee : un clic sur son etiquette l'ouvre.
        legende = try #require(moteur.cadresInterface["legende"])
        try await Self.cliquer(fenetre, en: CGPoint(x: legende.midX, y: legende.midY))
        let ouverture = try #require(try await Self.dureeDuRecadrage(moteur))
        #expect(abs(ouverture - Apparition.dureeLegende) < 0.07, "ouverture par clic : \(ouverture) s")
        try await Task.sleep(for: .milliseconds(600))
        // La fiche, elle, garde ses 0,3 s.
        moteur.selection = NomsDemo.Ieee.pont
        let fiche = try #require(try await Self.dureeDuRecadrage(moteur))
        #expect(abs(fiche - Apparition.duree) < 0.07, "fiche : \(fiche) s")
    }

    /// Avec « Reduire les animations », rien ne glisse ni ne s'attarde en haut non plus (spec de B, sections 1 et 3 :
    /// « un simple fondu ») : l'animation du conteneur de la colonne de gauche, ou est la pastille d'un releve ancien
    /// (a cote de la ligne de niveau, montee du bas le 02/10), est nulle, et la pastille qui repart part sans delai ;
    /// sans le reglage, elle part apres l'animation du conteneur (0,3 s). Cela se voit de l'exterieur : un element
    /// retire reste dans l'arbre le temps de son animation de retrait, et son `onDisappear` (qui vide son cadre dans
    /// `cadresInterface`) en donne la duree. Ici, le releve suivant rend le releve non ancien. La ligne de niveau, elle,
    /// ne bouge pas : la rangee garde la hauteur de la pastille.
    @Test(.timeLimit(.minutes(2)), arguments: [true, false])
    func pastilleDuHautPrendSaPlaceAvecReduire(reduire: Bool) async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        let maillage = try #require(demo.maillage)
        demo.recevoir(maillage, a: demo.maintenant.addingTimeInterval(-17 * 60))
        #expect(demo.maillageAncien)
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p,
                                                 reduire: reduire)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre {
            ["legende", "niveau", "ancien"].allSatisfy { moteur.cadresInterface[$0] != nil } && moteur.pret && !moteur.margesEnRoute
        }
        try await Task.sleep(for: .milliseconds(400))
        let niveau = try #require(moteur.cadresInterface["niveau"])
        // Le releve n'est plus ancien : sa pastille part.
        let t0 = ProcessInfo.processInfo.systemUptime
        demo.recevoir(maillage, a: demo.maintenant)
        var delai = 1.5
        while ProcessInfo.processInfo.systemUptime - t0 < 1.5 {
            if moteur.cadresInterface["ancien"] == nil {
                delai = ProcessInfo.processInfo.systemUptime - t0
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        if reduire {
            #expect(delai < 0.15, "avec le reglage, la pastille part d'un coup (\(delai) s)")
        } else {
            #expect(delai > 0.25, "sans le reglage, elle part avec l'animation du conteneur (\(delai) s)")
        }
        #expect(moteur.cadresInterface["niveau"] == niveau, "la ligne de niveau ne bouge pas : \(String(describing: moteur.cadresInterface["niveau"]))")
    }

    /// Dans la vraie fenetre, avec « Reduire les animations », la legende reste a sa place, au-dessus de la fiche,
    /// quand celle-ci parait, et la vue se recadre par un fondu (le moteur), pas en glissant. Avant la verification du
    /// 02/10, la legende se retirait sous la fiche, et son depart, d'un coup, montrait que la pile du bas n'avait pas
    /// d'animation de conteneur ; elle reste desormais, et son depart ne dit donc plus rien de ce cablage. Que rien ne
    /// glisse en haut est garde par `pastilleDuHautPrendSaPlaceAvecReduire`, qui mesure le depart de la pastille d'un
    /// releve ancien ; les fonctions, par `reduireLesAnimationsSansGlissement` et `dureeDeLaLegende`.
    @Test(.timeLimit(.minutes(1)))
    func legendeResteAuDessusDeLaFicheAvecReduire() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set(false, forKey: LegendePieces.cleRepliee)
        let demo = NomsSceneTests.surveillanceDemo()
        demo.recevoir(try #require(demo.maillage), a: demo.maintenant.addingTimeInterval(-17 * 60))
        let taille = Self.hauteAssez
        let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p, reduire: true)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre {
            ["legende", "niveau", "ancien"].allSatisfy { moteur.cadresInterface[$0] != nil } && moteur.pret && !moteur.margesEnRoute
        }
        #expect(moteur.reduire, "le reglage atteint la fenetre")
        let legende = try #require(moteur.cadresInterface["legende"], "la legende est ouverte")

        // La fiche parait : la legende reste, au-dessus d'elle, et la vue se recadre par un fondu.
        moteur.selection = NomsDemo.Ieee.detecteurEntree
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["fiche"] != nil && moteur.margesEnRoute }
        #expect(moteur.margesEnRoute && moteur.margesEnFondu, "la vue se recadre par un fondu")
        let fiche = try #require(moteur.cadresInterface["fiche"])
        let reste = try #require(moteur.cadresInterface["legende"], "la legende reste")
        #expect(reste.size == legende.size && reste.minX == legende.minX && reste.maxY <= fiche.minY,
                "la legende, ouverte, au-dessus de la fiche : \(reste), \(fiche)")
    }

    /// La pastille du coordinateur : sur la fiche du noeud couronne, et seulement lui, le meme que la scene
    /// (`EntreeScene.chefs`) : le pont. La fiche du pont a la pastille en plus : elle est plus haute ou plus large que sans
    /// couronne ; celle d'un autre noeud ne change pas.
    @Test func pastilleDuChef() throws {
        let (_, e) = try NomsSceneTests.demo()
        for n in e.scene.noeuds {
            #expect(FicheNoeud.couronne(n.id, entree: e) == n.chef, "\(n.id)")
        }
        #expect(FicheNoeud.couronne(NomsDemo.Ieee.pont, entree: e))
        #expect(!FicheNoeud.couronne(NomsDemo.Ieee.pont, entree: nil))
        #expect(e.chefs == [NomsDemo.Ieee.pont])
        // Le pont, sans voisins dans ce maillage mais avec une pile : sa colonne, celle de la couronne, est la plus haute.
        let s = try Self.pontAPile()
        let avecPile = try #require(Self.entree(s))
        func taille(_ id: String, _ e: EntreeScene) -> CGSize {
            let fiche = FicheNoeud(id: id, entree: e, instant: Date(), aRenommer: .constant(nil)) {}
            return NSHostingView(rootView: fiche.environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize
        }
        var sansCouronne = avecPile
        sansCouronne.chefs = []
        let avec = taille(NomsDemo.Ieee.pont, avecPile)
        let sans = taille(NomsDemo.Ieee.pont, sansCouronne)
        #expect(avec != sans && avec.width >= sans.width && avec.height >= sans.height, "\(avec), \(sans)")
        #expect(taille(JournalMaillageTests.appareil, avecPile) == taille(JournalMaillageTests.appareil, sansCouronne))
    }

    /// Deux tournees (`CourbesFicheTests`), et une pile au pont : la colonne de la couronne est la plus haute de sa fiche.
    static func pontAPile() throws -> Surveillance {
        let s = try CourbesFicheTests.surveillance()
        var maison = try #require(s.noms.maison)
        let k = try #require(maison.accessoires.firstIndex { $0.ieee == NomsDemo.Ieee.pont })
        maison.accessoires[k].batterie = BatterieMaison(niveau: 80, charge: .enCharge)
        s.noms.maison = maison
        return s
    }

    /// La pastille du coordinateur tient sur une ligne dans la fiche du pont couronne, a la largeur par defaut de la
    /// fenetre (1100 pt, `MaillageZigbeeApp`) comme a sa largeur minimale : les colonnes de la fiche se serrent, et une
    /// pastille qui prend la largeur qu'on lui laisse passait a la ligne. Mesure sur la fiche du pont, a pile, avec les
    /// courbes de l'historique (comme avec une sonde), ou la colonne
    /// de la couronne est la plus haute : la couronne y ajoute sa pastille et son espacement, `uneLigne`
    /// dans une fenetre assez large pour que tout tienne sur une ligne ; une deuxieme ligne en ajouterait
    /// davantage.
    @Test func pastilleDuChefSurUneLigne() throws {
        let s = try Self.pontAPile()
        let id = NomsDemo.Ieee.pont
        let avec = try #require(Self.entree(s))
        #expect(avec.graphe.noeud(id)?.genre == .centre && FicheNoeud.couronne(id, entree: avec), "le coordinateur couronne")
        var sans = avec
        sans.chefs = []
        // Ce que la couronne ajoute a la hauteur de la fiche dans une fenetre de `fenetre` pt de large : la fiche
        // est posee avec le bord de chaque cote (`FenetrePieces`).
        func ajout(fenetre: CGFloat) -> CGFloat {
            func hauteur(_ e: EntreeScene) -> CGFloat {
                let fiche = FicheNoeud(id: id, entree: e, instant: Date(), aRenommer: .constant(nil)) {}
                return NSHostingView(rootView: fiche.frame(width: fenetre - 2 * FenetrePieces.bord)
                    .environment(s).environment(PiecesChoisies(fichier: nil))).fittingSize.height
            }
            return hauteur(avec) - hauteur(sans)
        }
        let pastille = NSHostingView(rootView: PastilleChef()).fittingSize.height
        let uneLigne = ajout(fenetre: 3000)
        #expect(uneLigne >= pastille && uneLigne < 2 * pastille, "sur une ligne : \(uneLigne) pt pour une pastille de \(pastille)")
        for fenetre in [1100, FenetrePieces.tailleMinimale.width] {
            let plus = ajout(fenetre: fenetre)
            #expect(plus > 0, "fenetre de \(Int(fenetre)) pt : la couronne agrandit la fiche, dont sa colonne est la plus haute")
            #expect(plus <= uneLigne + 0.5, "fenetre de \(Int(fenetre)) pt : la couronne ajoute \(plus) pt, plus que \(uneLigne) : la pastille passe a la ligne")
        }
    }

    /// Ligne de niveau : pieces seules, routeurs, noms masques (un, plusieurs), piece isolee, etage isole.
    @Test func ligneDeNiveau() {
        #expect(LigneNiveauVue.texte(.pieces) == String(localized: "Vue d'ensemble : les pièces"))
        #expect(LigneNiveauVue.texte(.routeurs) == String(localized: "Mi-distance : les pièces et les routeurs"))
        #expect(LigneNiveauVue.texte(.masques(1)) == String(localized: "1 nom masqué faute de place : rapprochez-vous (molette)"))
        #expect(LigneNiveauVue.texte(.masques(3))
                == String(localized: "\(3) noms masqués faute de place : rapprochez-vous (molette)"))
        #expect(LigneNiveauVue.texte(.isolee("Salon")).contains("Salon"))
        #expect(LigneNiveauVue.texte(.etageIsole("Étage")).contains("Étage"))
        #expect(LigneNiveauVue.texte(.lisibles) == String(localized: "Tous les noms sont lisibles"))
    }

    /// Une fenetre faite comme celle de l'app (releves dans l'app, en demo, les 02/10) : le contenu sous la barre de
    /// titre, la barre transparente, le titre masque (`.windowStyle(.hiddenTitleBar)`) ; et une barre d'outils vide,
    /// du style automatique que choisit SwiftUI (releve : `toolbarStyle` 0), sans fond (le `.toolbar` de
    /// `FenetrePieces`), qui abaisse les trois boutons. Les tests montent leur fenetre a la main, sans la scene de
    /// l'app : SwiftUI n'y pose pas la barre d'outils.
    static func sansBarreDeTitre(_ fenetre: NSWindow) {
        fenetre.styleMask.insert(.fullSizeContentView)
        fenetre.titlebarAppearsTransparent = true
        fenetre.titleVisibility = .hidden
        fenetre.toolbar = NSToolbar(identifier: "graphe-test")
        fenetre.toolbarStyle = .automatic
    }

    /// Sans barre de titre (polissage B, section 1) : la scene du graphe, et elle seule, porte le style
    /// `.hiddenTitleBar`. SwiftUI pose alors lui-meme la barre de titre transparente et le titre masque, et les
    /// garde a chaque mise a jour de la fenetre ; le crochet d'AppKit d'avant, pose une fois, etait defait par
    /// SwiftUI (diagnostic du 02/10 : barre opaque des 0,285 s). Le titre « Maillage Zigbee » reste celui de la
    /// fenetre (Mission Control, menu Fenetre). Les trois boutons restent : la capsule de gauche commence apres
    /// eux, centree sur eux. La vue pose une barre d'outils vide et invisible (reverification du 02/10 : de l'air en
    /// haut, comme dans Plans), qui abaisse les boutons : dans une fenetre ainsi faite, sous macOS 27, a leur place
    /// de `CadreFeux.defaut`, le milieu a 26 pt du haut.
    @Test func fenetreSansBarreDeTitre() throws {
        let scenes = String(reflecting: MaillageZigbeeApp.Body.self)
        let graphe = try #require(scenes.range(of: "FenetrePieces"), "la scene du graphe")
        let journal = try #require(scenes.range(of: "FenetreJournal"), "la scene du journal")
        #expect(scenes[graphe.upperBound..<journal.lowerBound].contains("HiddenTitleBarWindowStyle"),
                "le graphe sans barre de titre")
        #expect(!scenes[journal.upperBound...].contains("HiddenTitleBarWindowStyle"), "le journal garde la sienne")
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                               defer: false)
        fenetre.isReleasedWhenClosed = false
        fenetre.title = "Maillage Zigbee"
        Self.sansBarreDeTitre(fenetre)
        #expect(fenetre.title == "Maillage Zigbee")
        let feux = try #require(CadreFeux(fenetre: fenetre))
        let agrandir = try #require(fenetre.standardWindowButton(.zoomButton))
        #expect(feux.droite == agrandir.convert(agrandir.bounds, to: nil).maxX)
        #expect(feux == CadreFeux.defaut)
        #expect(CadreFeux.defaut == CadreFeux(droite: 79, milieu: 26), "les boutons abaisses : \(CadreFeux.defaut)")
        // La vue pose la barre d'outils : vide, un espace souple seul, sans fond, et cachee en plein ecran (sauf au
        // survol du haut) ; la scene la porte, et SwiftUI la garde.
        let corps = String(reflecting: FenetrePieces.Body.self)
        let barre = try #require(corps.range(of: "ToolbarSpacer"), "une barre d'outils vide")
        #expect(corps[barre.upperBound...].components(separatedBy: "ToolbarAppearanceModifier").count - 1 == 2,
                "sans fond, et au survol seulement en plein ecran")
        #expect(corps.contains("SuiviFenetre"), "les boutons suivis, et le plein ecran")
    }

    /// De l'air en haut (reverification du 02/10) : dans la vraie fenetre, faite comme celle de l'app, la ligne des
    /// capsules suit les trois boutons abaisses par la barre d'outils invisible : centree sur eux, a 26 pt du haut,
    /// la capsule de gauche juste apres eux, le haut des capsules a 12 pt environ du bord. La marge du haut mesuree
    /// suit la nouvelle hauteur : le bas de la colonne, ligne de niveau comprise, et l'espacement.
    @Test(.timeLimit(.minutes(1))) func deLAirEnHaut() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre {
            moteur.pret && moteur.cadresInterface["ligne"] != nil && moteur.cadresInterface["colonne"] != nil
                && moteur.cadresInterface["niveau"] != nil && !moteur.margesEnRoute
        }
        try await Task.sleep(for: .milliseconds(300))
        let feux = try #require(CadreFeux(fenetre: fenetre))
        #expect(feux == CadreFeux.defaut, "les boutons abaisses : \(feux)")
        let ligne = try #require(moteur.cadresInterface["ligne"])
        let colonne = try #require(moteur.cadresInterface["colonne"])
        #expect(abs(ligne.midY - feux.milieu) < 0.5 && ligne.minY == 0, "la ligne centree sur les boutons : \(ligne)")
        #expect(ligne.minX == feux.droite + HautPieces.ecartFeux, "la capsule de gauche apres les boutons : \(ligne)")
        let capsule = NSHostingView(rootView: BarreOutils().capsuleDeVerre()
            .environment(demo)
            .environment(SondeMaillage(preferences: p, actif: false))
            .environment(NomsPont())).fittingSize.height
        let hautDesCapsules = feux.milieu - capsule / 2
        #expect(hautDesCapsules >= 10 && hautDesCapsules <= 13, "le haut des capsules : \(hautDesCapsules) pt")
        let bas = try #require(Self.basDuHaut(moteur))
        #expect(abs(bas - (colonne.maxY + FenetrePieces.espacementNiveau + RangeeNiveau.hauteur)) < 0.5, "la ligne de niveau sous le fil")
        #expect(abs(moteur.marges.haut - FenetrePieces.margeHaut(bas: bas)) <= 1, "la marge du haut : \(moteur.marges.haut)")
        #expect(FenetrePieces.margeHautInitiale == FenetrePieces.margeHaut(bas: 2 * 26 + FenetrePieces.espacement + 16
                                                                           + FenetrePieces.espacementNiveau + RangeeNiveau.hauteur))
    }

    /// La colonne de gauche au bord, et la tournee sans place reservee (ronde finale du 02/10). Sous la ligne des
    /// capsules, la ligne de la tournee, le bandeau de scission et le fil « Maison » vont contre le bord gauche de la
    /// fenetre, a la marge de la legende et de la ligne de niveau, que la tournee soit la ou non. Quand la tournee
    /// finit, sa ligne disparait, et le bandeau et le fil remontent (la colonne, dont le haut ne bouge pas, perd la
    /// hauteur de la ligne et un espacement). La scene, elle, ne bouge pas : la marge du haut compte toujours la place
    /// d'une ligne de tournee tant qu'une sonde est retenue, et ne change ni a la fin de la tournee, ni pendant que la
    /// colonne se reajuste (sinon, la vue d'ensemble se recadrerait a chaque tournee, toutes les 5 minutes).
    @Test(.timeLimit(.minutes(1))) func tourneeSansPlaceReservee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue { CanalRejoue.sondeMinimale($0) }
        let sonde = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p,
                                                 sonde: sonde)
        defer { Self.fermer(fenetre) }
        func colonne() throws -> CGRect { try #require(moteur.cadresInterface["colonne"], "la colonne") }
        func stable() async throws {
            try await MoteurPiecesTests.attendre { moteur.pret && moteur.cadresInterface["colonne"] != nil && !moteur.margesEnRoute }
            try await Task.sleep(for: .milliseconds(400))
        }
        try await stable()
        let sansSonde = try colonne()
        #expect(sansSonde.minX == FenetrePieces.bord, "sans sonde, au bord : \(sansSonde)")
        // Une sonde retenue, en tournee : la ligne de la tournee parait en haut de la colonne.
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        sonde.debuterTournee()
        sonde.avancer(AvancementTournee(etape: .tables, fait: 1, total: 3))
        try await stable()
        let pendant = try colonne()
        let margePendant = moteur.marges.haut
        #expect(pendant.minX == FenetrePieces.bord, "pendant la tournee, au bord : \(pendant)")
        #expect(abs(margePendant - FenetrePieces.margeHaut(bas: try #require(Self.basDuHaut(moteur)))) <= 1, "la marge : le bas de la colonne")
        // La tournee finit : la marge ne bouge a aucun moment, et la vue d'ensemble ne se recadre pas.
        sonde.finirTournee(nil)
        var marges: Set<CGFloat> = []
        var recadree = false
        let t0 = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - t0 < 0.8 {
            marges.insert(moteur.marges.haut)
            recadree = recadree || moteur.margesEnRoute
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(marges == [margePendant], "la marge du haut, stable : \(marges)")
        #expect(!recadree, "la scene ne se recadre pas")
        let apres = try colonne()
        let ligne = NSHostingView(rootView: IndicateurTournee(avancement: AvancementTournee(etape: .etatSonde, fait: 0, total: 1),
                                                             debut: nil)).fittingSize.height
        #expect(apres.minX == FenetrePieces.bord, "apres la tournee, au bord : \(apres)")
        #expect(apres.minY == pendant.minY, "le haut de la colonne ne bouge pas")
        #expect(abs(pendant.height - apres.height - (ligne + FenetrePieces.espacement)) < 0.5,
                "le bandeau et le fil remontent de la ligne de la tournee : \(pendant.height) -> \(apres.height)")
        // La sonde oubliee : la marge ne compte plus de ligne de tournee.
        await sonde.oublier()
        try await MoteurPiecesTests.attendre { moteur.marges.haut < margePendant && !moteur.margesEnRoute }
        let oubliee = try colonne()
        #expect(oubliee.minX == FenetrePieces.bord)
        #expect(abs(moteur.marges.haut - FenetrePieces.margeHaut(bas: try #require(Self.basDuHaut(moteur)))) <= 1, "sans sonde : \(moteur.marges.haut)")
    }

    /// L'apparition de la tournee, une sonde deja retenue (le cas de toutes les 5 minutes, l'autre moitie de
    /// `tourneeSansPlaceReservee`) : la ligne parait en haut de la colonne, le bandeau et le fil descendent de sa hauteur
    /// et d'un espacement, et la marge du haut ne change pas (la place de la ligne etait deja comptee), a aucun moment :
    /// la vue d'ensemble ne se recadre pas.
    @Test(.timeLimit(.minutes(1))) func tourneeQuiParaitSansBouger() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue { CanalRejoue.sondeMinimale($0) }
        let sonde = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p,
                                                 sonde: sonde)
        defer { Self.fermer(fenetre) }
        func colonne() throws -> CGRect { try #require(moteur.cadresInterface["colonne"], "la colonne") }
        func stable() async throws {
            try await MoteurPiecesTests.attendre { moteur.pret && moteur.cadresInterface["colonne"] != nil && !moteur.margesEnRoute }
            try await Task.sleep(for: .milliseconds(400))
        }
        // Une sonde retenue, dont la premiere tournee est finie : la ligne de la tournee a disparu, sa place est comptee.
        await sonde.connecter(SondeMaillageTests.port, choisi: true)
        sonde.debuterTournee()
        sonde.finirTournee(nil)
        try await stable()
        let avant = try colonne()
        let margeAvant = moteur.marges.haut
        let ligne = NSHostingView(rootView: IndicateurTournee(avancement: LigneTournee.premierPas, debut: nil)).fittingSize.height
        let basAvant = try #require(Self.basDuHaut(moteur))
        #expect(abs(margeAvant - FenetrePieces.margeHaut(bas: basAvant + ligne + FenetrePieces.espacement)) < 0.5,
                "la marge compte la place de la ligne : \(margeAvant)")
        // Une nouvelle tournee commence : la marge ne bouge a aucun moment, et la vue d'ensemble ne se recadre pas.
        sonde.debuterTournee()
        var marges: Set<CGFloat> = [moteur.marges.haut]
        var recadree = moteur.margesEnRoute
        let t0 = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - t0 < 0.8 {
            marges.insert(moteur.marges.haut)
            recadree = recadree || moteur.margesEnRoute
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(marges == [margeAvant], "la marge du haut, stable a l'apparition de la tournee : \(marges)")
        #expect(!recadree, "la scene ne se recadre pas")
        // La ligne a bien paru : le bandeau et le fil ont descendu, le haut de la colonne est le meme.
        let pendant = try colonne()
        #expect(pendant.minX == FenetrePieces.bord, "pendant la tournee, au bord : \(pendant)")
        #expect(pendant.minY == avant.minY, "le haut de la colonne ne bouge pas")
        #expect(abs(pendant.height - avant.height - (ligne + FenetrePieces.espacement)) < 0.5,
                "le bandeau et le fil descendent de la ligne de la tournee : \(avant.height) -> \(pendant.height)")
        await sonde.oublier()
    }

    /// Le vrai plein ecran (reverification du 02/10 : le bouton vert ne faisait qu'agrandir la fenetre) : SwiftUI pose
    /// a la fenetre d'une app de la barre des menus `fullScreenAuxiliary` ou `fullScreenNone` (releve dans l'app, en
    /// demo), et la vue le remplace par `fullScreenPrimary`, a chaque fois. En plein ecran (ronde finale du 02/10), la
    /// barre d'outils invisible se retire : revelee au survol du haut, elle faisait une bande claire sur les capsules.
    /// Elle revient a la sortie, et les boutons avec elle. La capsule de gauche prend la place des boutons (decision de
    /// Djoko, 02/10) : contre le bord gauche, a la meme marge que la capsule de droite contre le bord droit, au lieu de
    /// garder le vide qu'ils laissent ; la barre que le survol du haut fait paraitre la couvre le temps du survol.
    @Test(.timeLimit(.minutes(1))) func pleinEcran() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.pret && moteur.cadresInterface["ligne"] != nil }
        func primaire() -> Bool {
            let c = fenetre.collectionBehavior
            return c.contains(.fullScreenPrimary) && !c.contains(.fullScreenAuxiliary) && !c.contains(.fullScreenNone)
        }
        try await MoteurPiecesTests.attendre { primaire() }
        #expect(primaire(), "le plein ecran : 0x\(String(fenetre.collectionBehavior.rawValue, radix: 16))")
        // Ce que fait SwiftUI a chaque mise a jour des tailles de la fenetre : la vue le defait aussitot.
        for autre in [NSWindow.CollectionBehavior.fullScreenAuxiliary, .fullScreenNone] {
            fenetre.collectionBehavior = fenetre.collectionBehavior.subtracting(.fullScreenPrimary).union(autre)
            try await MoteurPiecesTests.attendre { primaire() }
            #expect(primaire(), "remis apres \(autre.rawValue) : 0x\(String(fenetre.collectionBehavior.rawValue, radix: 16))")
        }
        let apres = CadreFeux.defaut.droite + HautPieces.ecartFeux
        let bord = HautPieces.bordDroit
        let barre = try #require(fenetre.toolbar)
        #expect(moteur.cadresInterface["ligne"]?.minX == apres)
        #expect(barre.isVisible, "hors plein ecran, la barre d'outils invisible abaisse les boutons")
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fenetre)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!barre.isVisible, "en plein ecran, la barre d'outils se retire")
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["ligne"]?.minX == bord }
        #expect(moteur.cadresInterface["ligne"]?.minX == bord, "en plein ecran, la capsule prend la place des boutons")
        #expect(moteur.cadresInterface["colonne"]?.minX == FenetrePieces.bord, "la colonne ne bouge pas")
        #expect(moteur.cadresInterface["ligne"]?.midY == CadreFeux.defaut.milieu, "a la meme hauteur")
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fenetre)
        try await MoteurPiecesTests.attendre { barre.isVisible }
        #expect(barre.isVisible, "a la sortie, la barre d'outils revient")
        try await Task.sleep(for: .milliseconds(300))
        #expect(CadreFeux(fenetre: fenetre) == CadreFeux.defaut, "et les boutons abaisses avec elle")
        try await MoteurPiecesTests.attendre { moteur.cadresInterface["ligne"]?.minX == apres }
        #expect(moteur.cadresInterface["ligne"]?.minX == apres, "a la sortie, de nouveau apres les boutons")
        #expect(moteur.cadresInterface["ligne"]?.midY == CadreFeux.defaut.milieu)
    }

    /// La sortie du plein ecran, quand la lecture des boutons de la fenetre echoue (ils ne sont pas encore revenus
    /// dans la fenetre) ou rend une valeur de passage : la capsule de gauche ne reste pas sur eux, au bord, ou elle
    /// les couvrirait. Elle retrouve le dernier cadre des boutons mesure hors plein ecran (ici, une mesure a part,
    /// pour la distinguer du cadre par defaut), et une seconde lecture, un peu plus tard, corrige la valeur de passage.
    @Test(.timeLimit(.minutes(1))) func pleinEcranLectureRatee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        let (fenetre, moteur) = try Self.fenetre(demo, taille: CGSize(width: 1100, height: 760), preferences: p)
        defer { Self.fermer(fenetre) }
        try await MoteurPiecesTests.attendre { moteur.pret && moteur.cadresInterface["ligne"] != nil }
        let cadreFenetre = try #require(fenetre.contentView?.superview)
        let suivi = try #require(Self.sousVue(SuiviFenetre.Vue.self, dans: cadreFenetre))
        let bord = HautPieces.bordDroit
        func ligneEn(_ x: CGFloat) async throws -> Bool {
            try await MoteurPiecesTests.attendre { moteur.cadresInterface["ligne"]?.minX == x }
            return moteur.cadresInterface["ligne"]?.minX == x
        }
        // Une mesure hors plein ecran, autre que le cadre par defaut : une sortie du plein ecran la lit.
        let mesure = CadreFeux(droite: 100, milieu: 30)
        let apres = mesure.droite + HautPieces.ecartFeux
        suivi.lecture = { _ in mesure }
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fenetre)
        #expect(try await ligneEn(apres), "la mesure, hors plein ecran")
        // Le plein ecran : la capsule au bord, a la hauteur des boutons mesures.
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fenetre)
        #expect(try await ligneEn(bord), "en plein ecran, au bord")
        #expect(moteur.cadresInterface["ligne"]?.midY == mesure.milieu, "a la hauteur des boutons mesures")
        // La sortie, la lecture ratee : la capsule retrouve la derniere mesure, et ne reste pas sur les boutons.
        suivi.lecture = { _ in nil }
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fenetre)
        #expect(try await ligneEn(apres), "lecture ratee : la derniere mesure, pas le bord : \(String(describing: moteur.cadresInterface["ligne"]))")
        #expect(moteur.cadresInterface["ligne"]?.midY == mesure.milieu)
        // Une valeur de passage a la sortie, la bonne un peu plus tard : la seconde lecture la corrige.
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fenetre)
        #expect(try await ligneEn(bord), "de nouveau en plein ecran")
        var lectures = 0
        suivi.lecture = { _ in
            lectures += 1
            return lectures == 1 ? CadreFeux(droite: 7, milieu: 9) : mesure
        }
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fenetre)
        #expect(try await ligneEn(apres), "la valeur de passage est corrigee par la seconde lecture")
        #expect(lectures >= 2, "deux lectures : \(lectures)")
    }

    /// La bande du haut : un clic, glisse, deplace la fenetre ; un double-clic fait ce que dit le reglage
    /// du Mac (agrandir, reduire ou rien ; « Remplir », sans API publique, agrandit). Elle agit aussi dans
    /// une fenetre inactive, et seule : AppKit ne deplace pas la fenetre a sa place.
    @Test func bandeDeLaFenetre() throws {
        #expect(ActionDoubleClic.cle == "AppleActionOnDoubleClick")
        #expect(ActionDoubleClic(reglage: "Maximize") == .agrandir)
        #expect(ActionDoubleClic(reglage: "Fill") == .agrandir)
        #expect(ActionDoubleClic(reglage: nil) == .agrandir)
        #expect(ActionDoubleClic(reglage: "Minimize") == .reduire)
        #expect(ActionDoubleClic(reglage: "None") == .rien)
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                               backing: .buffered, defer: false)
        fenetre.isReleasedWhenClosed = false
        let bande = BandeFenetre.Vue(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        fenetre.contentView?.addSubview(bande)
        var glissers = 0
        var doubles = 0
        bande.glisser = { f, _ in if f === fenetre { glissers += 1 } }
        bande.doubleCliquer = { f in if f === fenetre { doubles += 1 } }
        func clic(_ n: Int) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 10), modifierFlags: [],
                                            timestamp: 0, windowNumber: fenetre.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: n, pressure: 1))
        }
        bande.mouseDown(with: try clic(1))
        #expect(glissers == 1 && doubles == 0, "un clic : la fenetre suit le glisser")
        bande.mouseDown(with: try clic(2))
        #expect(glissers == 1 && doubles == 1, "le second clic : le double-clic")
        #expect(bande.acceptsFirstMouse(for: nil))
        #expect(!bande.mouseDownCanMoveWindow)
    }

    /// Sur la ligne des trois boutons, la bande, et elle seule, recoit les clics entre les deux capsules :
    /// ni les capsules, ni la scene dessous.
    @Test func bandeEntreLesCapsules() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let sonde = SondeMaillage(preferences: p, actif: false)
        let noms = NomsPont()
        let s = NomsSceneTests.surveillanceDemo()
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                               defer: false)
        fenetre.isReleasedWhenClosed = false
        let vue = ZStack(alignment: .topLeading) {
            Color.black.onTapGesture {}
            HautPieces(moteur: MoteurPieces(), troisD: .constant(true))
        }
        let hote = NSHostingView(rootView: vue.ignoresSafeArea().environment(s).environment(sonde).environment(noms))
        fenetre.contentView = hote
        Self.sansBarreDeTitre(fenetre)
        hote.layoutSubtreeIfNeeded()
        fenetre.layoutIfNeeded()
        let cadre = try #require(hote.superview)
        func sous(_ x: CGFloat, _ y: CGFloat) -> NSView? { cadre.hitTest(NSPoint(x: x, y: fenetre.frame.height - y)) }
        let milieu = CadreFeux.defaut.milieu
        #expect(sous(500, milieu) is BandeFenetre.Vue, "entre les capsules")
        #expect(sous(500, 2) !== hote, "au bord du haut : le cadre de la fenetre")
        #expect(!(sous(CadreFeux.defaut.droite + HautPieces.ecartFeux + 20, milieu) is BandeFenetre.Vue), "la capsule de gauche")
        #expect(!(sous(1000 - HautPieces.bordDroit - 20, milieu) is BandeFenetre.Vue), "la capsule de droite")
        #expect(!(sous(500, 200) is BandeFenetre.Vue), "la scene")
    }

    /// La premiere sous-vue de ce type, dans `racine` ou plus bas.
    static func sousVue<T: NSView>(_ type: T.Type, dans racine: NSView) -> T? {
        if let trouvee = racine as? T { return trouvee }
        for sous in racine.subviews {
            if let trouvee = sousVue(type, dans: sous) { return trouvee }
        }
        return nil
    }

    /// Chaque capsule du haut garde la largeur de son contenu (spec de B, section 1 : « Chaque capsule prend la
    /// taille de son contenu ») : la bande vide entre elles prend la place qui reste, meme a la taille minimale de
    /// la fenetre, en 2D comme en 3D (ou « Rotation lente » s'ajoute a la capsule de droite). Sans cela, les deux
    /// capsules et la bande se partageaient la place, et la capsule du reseau tronquait ses boutons (« Appareil… »,
    /// « A… »). Tout tient : la bande commence au bord de la capsule de gauche, finit au bord de celle de droite, et
    /// n'est pas vide.
    @Test(arguments: [false, true])
    func capsulesALeurLargeurIdeale(troisD: Bool) throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let sonde = SondeMaillage(preferences: p, actif: false)
        let noms = NomsPont()
        let s = NomsSceneTests.surveillanceDemo()
        let moteur = MoteurPieces(troisD: troisD)
        func hote(_ vue: some View) -> NSHostingView<AnyView> {
            NSHostingView(rootView: AnyView(vue.environment(s).environment(sonde).environment(noms)))
        }
        // La largeur de chaque capsule seule : celle de son contenu.
        let gauche = hote(BarreOutils().capsuleDeVerre()).fittingSize.width
        let droite = hote(CommandesVue(moteur: moteur, troisD: .constant(troisD)).capsuleDeVerre()).fittingSize.width
        // Le haut de la fenetre a sa taille minimale, comme `FenetrePieces` le pose.
        let largeur = FenetrePieces.tailleMinimale.width
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: largeur, height: 200),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                               defer: false)
        fenetre.isReleasedWhenClosed = false
        defer { fenetre.contentView = nil }
        let haut = hote(HautPieces(moteur: moteur, troisD: .constant(troisD))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        fenetre.contentView = haut
        Self.sansBarreDeTitre(fenetre)
        haut.layoutSubtreeIfNeeded()
        fenetre.layoutIfNeeded()
        let bande = try #require(Self.sousVue(BandeFenetre.Vue.self, dans: haut), "la bande")
        let cadre = bande.convert(bande.bounds, to: haut)
        let cas = "3D : \(troisD), fenetre de \(Int(largeur)) pt, capsules de \(gauche) et \(droite) pt"
        #expect(abs(cadre.minX - (CadreFeux.defaut.droite + HautPieces.ecartFeux + gauche)) < 1,
                "\(cas) : la bande commence au bord de la capsule du reseau (x = \(cadre.minX))")
        #expect(abs(cadre.maxX - (largeur - HautPieces.bordDroit - droite)) < 1,
                "\(cas) : la bande finit au bord de la capsule de la vue (x = \(cadre.maxX))")
        #expect(cadre.width > 0, "\(cas) : la bande n'est pas vide (\(cadre.width) pt)")
    }

    /// La fenetre reste sombre, meme quand le Mac est en clair : sa barre, ses menus, sa fiche et ses feuilles, et en
    /// plein ecran la barre de titre que le survol du haut fait paraitre (ronde finale du 02/10 : une bande blanche sur
    /// un Mac en clair). SwiftUI pose l'apparence de la fenetre a chaque mise a jour, d'apres la preference de la vue :
    /// l'apparence sombre posee par AppKit etait aussitot defaite (releve dans l'app, en demo). La vue demande donc
    /// l'apparence sombre a SwiftUI (`preferredColorScheme`).
    @Test func fenetreToujoursSombre() {
        let corps = String(reflecting: FenetrePieces.Body.self)
        #expect(corps.contains("PreferredColorSchemeKey"), "la vue demande l'apparence sombre a SwiftUI")
    }

    /// « Placer dans une piece… » : pour un noeud que le pont ne place pas seulement (la sonde, le routeur inconnu), les
    /// pieces de la maison, par nom ; le choix se garde sur disque, sous son adresse longue, ou en memoire sans fichier
    /// (demo).
    @Test func placerUnNoeud() throws {
        let (s, e) = try NomsSceneTests.demo()
        typealias I = NomsDemo.Ieee
        let pieces = ["Abri", "Buanderie", "Bureau", "Chambre", "Chambre d'amis", "Cuisine", "Entrée", "Grenier",
                      "Salle de bain", "Salle de jeux", "Salon", "Terrasse"]
        #expect(PiecesChoisies.placement(I.lampeBureau, dans: s, entree: e) == nil, "le pont la place au bureau")
        let sonde = try #require(PiecesChoisies.placement(I.sonde, dans: s, entree: e))
        #expect(sonde == PiecesChoisies.Placement(cle: I.sonde, pieces: pieces))
        #expect(PiecesChoisies.placement(I.inconnu, dans: s, entree: e)?.cle == I.inconnu)
        #expect(PiecesChoisies.placement("A0000000000000EE", dans: s, entree: e) == nil, "absent du graphe")
        #expect(MenuPlacer.articles(sonde).first == MenuPlacer.Article(texte: String(localized: "Sans pièce"), piece: nil))
        #expect(Array(MenuPlacer.articles(sonde).dropFirst()) == pieces.map { MenuPlacer.Article(texte: $0, piece: $0) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-routeurs.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let choisies = PiecesChoisies(fichier: url)
        choisies.choisir("Bureau", I.sonde, domicile: "Maison (démo)")
        #expect(PiecesChoisies(fichier: url).pieceChoisie(I.sonde, domicile: "Maison (démo)") == "Bureau")
        #expect(PiecesChoisies(fichier: url).choix.choix(appareil: I.sonde, domicile: "Maison (démo)") == "Bureau")
        choisies.choisir(nil, I.sonde, domicile: "Maison (démo)")
        #expect(PiecesChoisies(fichier: url).pieceChoisie(I.sonde, domicile: "Maison (démo)") == nil, "Sans piece")
        let memoire = PiecesChoisies(fichier: nil)
        memoire.choisir("Salon", I.inconnu, domicile: "")
        #expect(memoire.choix.choix(appareil: I.inconnu, domicile: "") == "Salon")
        #expect(PiecesChoisies.fichier(demo: true, sousTests: false) == nil)
        #expect(PiecesChoisies.fichier(demo: false, sousTests: true) == nil)
        #expect(PiecesChoisies.fichier(demo: false, sousTests: false)
                == Surveillance.dossierParDefaut.appendingPathComponent("pieces-routeurs.json"))
        // Dans une maison sans pieces (ni d'appareil, ni de zone), aucun noeud n'a de menu.
        s.noms.maison?.zones = nil
        for k in s.noms.maison?.accessoires.indices ?? 0..<0 { s.noms.maison?.accessoires[k].piece = nil }
        let sansPieces = try #require(Self.entree(s))
        for id in [I.sonde, I.inconnu, I.lampeBureau] {
            #expect(PiecesChoisies.placement(id, dans: s, entree: sansPieces) == nil, "\(id)")
        }
    }



    /// « Placer dans une piece… » lit le graphe de la scene du meme rendu (`EntreeScene`), et n'en reconstruit pas :
    /// apres l'oubli de la sonde, la scene deja construite garde le routeur inconnu, que la sonde seule connait, et son
    /// menu ; la scene suivante ne l'a plus, ni le menu.
    @Test func menuDeLaScene() throws {
        let (s, e) = try NomsSceneTests.demo()
        s.oublierMaillage()
        #expect(PiecesChoisies.placement(NomsDemo.Ieee.inconnu, dans: s, entree: e)?.cle == NomsDemo.Ieee.inconnu)
        let suivante = try #require(Self.entree(s))
        #expect(suivante.maillage == nil && suivante.graphe.noeud(NomsDemo.Ieee.inconnu) == nil)
        #expect(PiecesChoisies.placement(NomsDemo.Ieee.inconnu, dans: s, entree: suivante) == nil)
    }

    /// Un choix perime (sa piece n'est plus une piece de la maison) ne compte plus : la scene l'ignore, et la selection du
    /// menu rend nil, « Sans piece », au lieu d'une piece que le menu n'a pas et qui ne cocherait rien. Le choix reste
    /// dans le fichier : il compte de nouveau si la piece revient.
    @Test func choixPerimeNonCoche() throws {
        let (s, _) = try NomsSceneTests.demo()
        let e = try #require(Self.entree(s))
        let domicile = "Maison (démo)"
        let choisies = PiecesChoisies(fichier: nil)
        for id in [NomsDemo.Ieee.inconnu, NomsDemo.Ieee.sonde] {
            let placement = try #require(PiecesChoisies.placement(id, dans: s, entree: e), "\(id)")
            let menu = MenuPlacer(placement: placement, domicile: domicile, choisies: choisies)
            #expect(menu.selection.wrappedValue == nil, "\(id) : aucun choix")
            menu.selection.wrappedValue = "Cuisine"
            #expect(choisies.pieceChoisie(placement.cle, domicile: domicile) == "Cuisine", "\(id) : le choix est garde")
            #expect(menu.selection.wrappedValue == "Cuisine", "\(id) : une piece du menu est cochee")
            // La cuisine n'est plus une piece de la maison.
            let sansCuisine = PiecesChoisies.Placement(cle: placement.cle, pieces: placement.pieces.filter { $0 != "Cuisine" })
            let perime = MenuPlacer(placement: sansCuisine, domicile: domicile, choisies: choisies)
            #expect(perime.selection.wrappedValue == nil, "\(id) : choix perime")
            #expect(choisies.pieceChoisie(placement.cle, domicile: domicile) == "Cuisine", "\(id) : le choix reste")
            #expect(menu.selection.wrappedValue == "Cuisine", "\(id) : la piece revient, le choix compte de nouveau")
        }
    }

    /// Les images de la demo : les douze de la vue par pieces, puis la fiche du pont, avec sa pastille, et
    /// la legende repliee ; puis les six des etages (polissage C, section 7) ; puis la vingt et unieme, un appareil a
    /// mi-chemin de son glissement vers la cuisine (polissage D, section 6) ; puis la fiche de la telecommande, avec son
    /// parent d'avant ; enfin le mode focus en 2D et en 3D, la fiche d'un routeur, ses voisins deplies (etape 5), et la meme sur 7 j, ses
    /// reperes de changement de chemin fondus ; puis trois de son journal regroupe (etape 5, journal regroupe). La
    /// fiche du pont est celle d'un noeud couronne de la demo. (Les images des Reglages, `23-reglages-pont` et
    /// `24-reglages-maison`, sont rendues a part.)
    @Test func imagesDeDemo() throws {
        #expect(CapturesPieces.cas.map(\.nom) == [
            "01-2d", "02-envol-30", "03-envol-55", "04-envol-80", "05-3d", "06-3d-tournee", "07-2d-zoom-salon",
            "08-2d-mi-distance", "09-2d-loin", "10-3d-isolee-salon", "11-2d-isolee-chambre", "12-2d-survol",
            "13-2d-fiche-du-pont", "14-2d-legende-repliee", "15-2d-carree-2x2", "16-2d-carree-en-rangee",
            "17-3d-jardin-dedans", "18-2d-etage-isole", "19-3d-etage-isole", "20-3d-terrasse-depuis-le-jardin",
            "21-2d-appareil-en-route", "22-2d-fiche-telecommande", "25-2d-focus-lampe-chambre",
            "26-3d-focus-lampe-chambre", "27-2d-fiche-lampe-bureau", "28-2d-fiche-lampe-bureau-7j",
            "5c-fiche-lampe-bureau-journal-replie", "5c-fiche-lampe-bureau-journal-deplie",
            "5c-fiche-detecteur-abri-journal-deplie",
        ])
        #expect(CapturesPieces.cas.filter(\.changementsDeplies).map(\.nom)
                == ["5c-fiche-lampe-bureau-journal-deplie", "5c-fiche-detecteur-abri-journal-deplie"])
        #expect(CapturesPieces.cas.filter { $0.periode != nil }.map(\.nom) == ["28-2d-fiche-lampe-bureau-7j"])
        #expect(CapturesPieces.cas.filter(\.listeVoisins).map(\.nom) == ["27-2d-fiche-lampe-bureau"])
        #expect(CapturesPieces.cas.filter { $0.deplacer != nil }.map(\.nom) == ["21-2d-appareil-en-route"])
        #expect(CapturesPieces.cas.filter(\.legendeRepliee).map(\.nom) == ["14-2d-legende-repliee"])
        let (_, e) = try NomsSceneTests.demo()
        let m = MoteurPieces()
        try #require(CapturesPieces.cas.first { $0.nom == "13-2d-fiche-du-pont" }).poser(m, e.scene)
        let choisi = try #require(m.selection)
        #expect(FicheNoeud.couronne(choisi, entree: e))
        try #require(CapturesPieces.cas.first { $0.nom == "22-2d-fiche-telecommande" }).poser(m, e.scene)
        #expect(m.selection == NomsDemo.Ieee.telecommandeChambre)
        #expect(e.maillage?.parent(de: NomsDemo.Ieee.telecommandeChambre)?.dAvant == true)
    }

    /// L'image du glissement (polissage D, section 6) : la scene de la demo, puis celle ou le routeur inconnu du pont,
    /// sans piece, est place dans la cuisine. Le moteur est prepare par `CapturesPieces.preparer`, comme dans la boucle
    /// des images ; le cas est pose a trois points de son glissement, sous la meme camera (celle de son zoom) : au
    /// depart, a mi-chemin (le cas lui-meme), a l'arrivee. A mi-chemin, la pastille est en route, loin de ses deux
    /// places ; la vue est zoomee a l'echelle 1 vers « Sans pièce », dont le centre ne bouge pas sur l'ecran.
    @Test func imageDuGlissement() throws {
        let (s, e) = try NomsSceneTests.demo()
        let cas = try #require(CapturesPieces.cas.first { $0.nom == "21-2d-appareil-en-route" })
        let choix = try #require(cas.deplacer)
        let e2 = EntreeScene(surveillance: s, places: PlacesGardees(), choix: choix)
        let id = NomsDemo.Ieee.inconnu
        #expect(e.scene.noeud(id).map { e.scene.pieces[$0.piece].nom } == .sansPiece)
        #expect(e2.scene.noeud(id).map { e2.scene.pieces[$0.piece].nom } == .maison("Cuisine"))
        let marges: (haut: CGFloat, bas: CGFloat) = (84, 50)
        // Le cas, pose en plus a `q` de son glissement (le cas seul : a mi-chemin) ; son moteur et le centre de la pastille.
        func rendre(_ q: Double?) throws -> (m: MoteurPieces, centre: SIMD3<Double>) {
            var c = cas
            if let q {
                let poser = cas.poser
                c.poser = { m, sc in
                    poser(m, sc)
                    m.poserTransition(q)
                }
            }
            let (m, _) = CapturesPieces.preparer(c, surveillance: s, marges: marges)
            MoteurPiecesTests.dessiner(m, taille: c.taille)
            return (m, try #require(m.projetee?.centresNoeuds[id]))
        }
        let (mAvant, avant) = try rendre(0)
        let (mApres, apres) = try rendre(1)
        let (mMi, mi) = try rendre(nil)
        #expect(mAvant.orbite == mMi.orbite && mApres.orbite == mMi.orbite, "les trois points se mesurent sous la meme camera")
        let d = simd_distance(avant, apres)
        #expect(d > 1 && simd_distance(mi, avant) > 0.25 * d && simd_distance(mi, apres) > 0.25 * d)
        // Le zoom : l'echelle 1, vers « Sans pièce », dont le centre garde sa place a l'ecran.
        let sc = try #require(mMi.scene)
        let sansPiece = try #require(sc.pieces.firstIndex { $0.nom == .sansPiece })
        let echelle = ProjectionScene(mMi.orbite, cadre: mMi.cadre).pxParUnite(mMi.orbite.cible) / CartesPieces.px
        #expect(abs(echelle - 1) < 1e-6)
        var sansZoom = cas
        sansZoom.poser = { m, _ in m.poserTransition(0.5) }
        let (mSans, _) = CapturesPieces.preparer(sansZoom, surveillance: s, marges: marges)
        #expect(abs(ProjectionScene(mSans.orbite, cadre: mSans.cadre).pxParUnite(mSans.orbite.cible) / CartesPieces.px - 1) > 0.1,
                "le zoom change l'echelle")
        let centre = try #require(mMi.centrePiece(sansPiece))
        let avantZoom = try #require(ProjectionScene(mSans.orbite, cadre: mSans.cadre).ecran(centre))
        let apresZoom = try #require(ProjectionScene(mMi.orbite, cadre: mMi.cadre).ecran(centre))
        #expect(hypot(avantZoom.x - apresZoom.x, avantZoom.y - apresZoom.y) < 1)
    }

    /// La marge du bas de la zone visible ou se choisit la grille (polissage C, section 3.3, decision de Djoko du
    /// 03/10) : celle de la legende telle que Djoko l'a laissee, sans la fiche ; ouverte, sa hauteur mesuree ; repliee,
    /// 30 pt. Une fiche ouverte n'y change rien, ni le repli de la legende faute de place sous elle.
    @Test func margeDeLaGrille() {
        let ouverte = FenetrePieces.margeBas(pile: 223)
        #expect(FenetrePieces.margeBasGrille(fiche: false, repliee: false, legende: 223, legendeOuverte: 223) == ouverte)
        #expect(FenetrePieces.margeBasGrille(fiche: false, repliee: true, legende: nil, legendeOuverte: 223) == 30)
        #expect(FenetrePieces.margeBasGrille(fiche: true, repliee: false, legende: nil, legendeOuverte: 223) == ouverte,
                "la legende repliee faute de place sous la fiche")
        #expect(FenetrePieces.margeBasGrille(fiche: true, repliee: false, legende: 223, legendeOuverte: 223) == ouverte)
        #expect(FenetrePieces.margeBasGrille(fiche: true, repliee: true, legende: nil, legendeOuverte: 223) == 30)
    }

    /// Le reglage « Etages en 2D » (polissage C, section 3.1) : en grille par defaut ; change dans les preferences
    /// (Reglages › General), il s'applique tout de suite a la vue ouverte. Le test ne depend pas du mode 2D ou 3D garde de
    /// l'app et ne le touche pas : la fenetre le lit dans `UserDefaults.standard` a sa creation, sans qu'un autre domaine
    /// puisse s'y mettre ; le test pose donc la 2D sur le moteur de la fenetre (`basculer`, qui n'ecrit aucune preference
    /// et ne fait rien si elle y est deja), et les preferences de la fenetre vont a un domaine a lui. En 3D, la rangee
    /// attend la 2D : voir `reglageDeLaGrille` (`MoteurPiecesTests`).
    /// Il ne depend pas non plus de la hauteur de l'ecran : AppKit plafonne la fenetre a la hauteur visible de l'ecran, et
    /// la grille ne differe de la rangee que dans une fenetre assez haute (a T4, la pile des deux plateaux de la demo, a
    /// partir d'environ 1 340 pt). Le test affirme donc toujours le cablage (`moteur.grille` apres chaque changement, en
    /// attendant ce qu'il affirme), et ne compare les colonnes de la grille et de la rangee que si la fenetre obtenue les
    /// departage, d'apres `GeometrieMaison.colonnes` sur sa zone visible. Deux fenetres : 820 x 1500, qui les departage
    /// sur un grand ecran, et 820 x 1000, celle d'un portable, qui ne le fait pas : le chemin des petits ecrans tourne
    /// aussi sur un grand.
    @Test(.timeLimit(.minutes(1))) func reglageEtagesEn2D() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let demo = NomsSceneTests.surveillanceDemo()
        for hauteur in [CGFloat(1500), 1000] {
            let taille = CGSize(width: 820, height: hauteur)
            p.removeObject(forKey: FenetrePieces.cleGrille)
            let (fenetre, moteur) = try Self.fenetre(demo, taille: taille, preferences: p, reduire: true)
            defer { Self.fermer(fenetre) }
            try await MoteurPiecesTests.attendre { moteur.pret }
            // La 2D, quel que soit le mode garde : en 3D, un fondu de 0,3 s (« Reduire les animations »).
            moteur.basculer(troisD: false)
            try await Task.sleep(for: .milliseconds(100))
            try await MoteurPiecesTests.attendre { !moteur.enMouvement }
            // La vue en place : la grille posee sur la premiere vraie taille, la legende mesuree, les marges arrivees.
            try await MoteurPiecesTests.attendre {
                moteur.colonnes != nil && moteur.cadresInterface["legende"] != nil && !moteur.margesEnRoute
            }
            try await Task.sleep(for: .milliseconds(500))
            // Ce que la fenetre obtenue permet d'affirmer des colonnes : celles de la grille sur sa zone visible, si elles
            // different de la rangee (une colonne par plateau) ; nil : la grille et la rangee y sont la meme chose.
            let rayons = moteur.geometrieVisee.rayons
            let plateaux = rayons.count
            let colonnesDeLaGrille = GeometrieMaison.colonnes(rayons: rayons, taille: moteur.zoneVisible)
                .flatMap { $0 != plateaux ? $0 : nil }
            try await MoteurPiecesTests.attendre { moteur.grille }
            #expect(FenetrePieces.cleGrille == "etagesEnGrille" && moteur.grille, "\(taille) : en grille par defaut")
            if let pile = colonnesDeLaGrille {
                try await MoteurPiecesTests.attendre { moteur.geometrieVisee.colonnes < plateaux }
                #expect(moteur.geometrieVisee.colonnes < plateaux, "\(taille) : en grille, \(pile) colonne(s) pour \(plateaux) plateaux")
            }
            // « En rangee » : le moteur suit la preference ; une colonne par plateau.
            p.set(false, forKey: FenetrePieces.cleGrille)
            try await MoteurPiecesTests.attendre { !moteur.grille }
            #expect(!moteur.grille, "\(taille) : « En rangee » arrive jusqu'au moteur")
            if colonnesDeLaGrille != nil {
                try await MoteurPiecesTests.attendre { moteur.geometrieVisee.colonnes == plateaux }
                #expect(moteur.geometrieVisee.colonnes == plateaux, "\(taille) : en rangee, une colonne par plateau")
            }
            // De nouveau « En grille » : le choix de la zone visible.
            p.set(true, forKey: FenetrePieces.cleGrille)
            try await MoteurPiecesTests.attendre { moteur.grille }
            #expect(moteur.grille, "\(taille) : « En grille » arrive jusqu'au moteur")
            if let pile = colonnesDeLaGrille {
                try await MoteurPiecesTests.attendre { moteur.geometrieVisee.colonnes == pile }
                #expect(moteur.geometrieVisee.colonnes == pile, "\(taille) : de nouveau en grille, \(pile) colonne(s)")
            }
        }
    }

    /// Places des pieces : dans le dossier de l'app, ni en demo ni sous les tests.
    @Test func fichierDesPlaces() {
        #expect(FenetrePieces.fichierPlaces(demo: true, sousTests: false) == nil)
        #expect(FenetrePieces.fichierPlaces(demo: false, sousTests: true) == nil)
        #expect(FenetrePieces.fichierPlaces(demo: false, sousTests: false)?.lastPathComponent == "positions-pieces.json")
        #expect(FenetrePieces.fichierPlaces(demo: false, sousTests: false)?.deletingLastPathComponent().standardizedFileURL.path
                == Surveillance.dossierParDefaut.standardizedFileURL.path)
    }

    /// Les liens montres, gardes sous `liensMontres` : « chemins » par defaut et pour une valeur inconnue.
    @Test func preferenceDesLiens() {
        #expect(FenetrePieces.modeLiens(nil) == .chemins && FenetrePieces.modeLiens("tous") == .tous)
        #expect(FenetrePieces.modeLiens("chemins") == .chemins && FenetrePieces.modeLiens("autre") == .chemins)
        #expect(MoteurPieces().liens == .chemins)
    }

    /// Les voisins entendus a la selection, gardes sous `voisinsALaSelection` : montres par defaut, et pour une valeur qui
    /// n'est pas un booleen. L'aide du bouton dit ce qu'il fait, ou pourquoi il est grise en mode « tous ».
    @Test func preferenceDesVoisins() {
        #expect(FenetrePieces.cleVoisins == "voisinsALaSelection")
        #expect(FenetrePieces.voisinsMontres(nil) && FenetrePieces.voisinsMontres(true) && FenetrePieces.voisinsMontres("non"))
        #expect(!FenetrePieces.voisinsMontres(false))
        let montres = FenetrePieces.aideVoisins(montres: true, mode: .chemins)
        let masques = FenetrePieces.aideVoisins(montres: false, mode: .chemins)
        let tous = FenetrePieces.aideVoisins(montres: true, mode: .tous)
        #expect(Set([montres, masques, tous]).count == 3)
        #expect(montres == String(localized: "Voisins entendus montrés à la sélection d'un nœud : cliquer pour les masquer"))
        #expect(tous == FenetrePieces.aideVoisins(montres: false, mode: .tous), "grise : le choix ne change rien")
    }
}
