import AppKit
import Foundation
import MaillageCoeur
import simd
import SwiftUI
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Vue par pieces : moteur et rendu")
struct MoteurPiecesTests {
    static let taille = CGSize(width: 1200, height: 800)

    /// Un moteur sur la demo, dispose, et une premiere image dessinee (hors fenetre).
    static func moteur(fichier: URL? = nil) throws -> (MoteurPieces, EntreeScene) {
        let (_, e) = try NomsSceneTests.demo()
        return (moteur(e, fichier: fichier), e)
    }

    /// Un moteur sur la scene `e`, dispose, et une premiere image dessinee (hors fenetre).
    static func moteur(_ e: EntreeScene, fichier: URL? = nil, taille: CGSize = MoteurPiecesTests.taille) -> MoteurPieces {
        let m = MoteurPieces(fichierPlaces: fichier)
        m.marges = (84, 50)
        m.poserTaille(taille)
        m.installerMaintenant(e)
        dessiner(m, taille: taille)
        return m
    }

    static func dessiner(_ m: MoteurPieces, taille: CGSize = MoteurPiecesTests.taille) {
        let rendu = ImageRenderer(content: Canvas { ctx, t in
            m.image(&ctx, taille: t, echelle: 1, palette: Palette(sombre: true))
        }.frame(width: taille.width, height: taille.height))
        _ = rendu.cgImage
    }

    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pieces-\(UUID().uuidString)/positions-pieces.json")
    }

    /// Un point d'une piece, hors de ses pastilles et des noms : pres du coin bas droit de son dessus, ou, si un
    /// nom ou une pastille l'y couvre, le plus proche de ce coin ou un clic l'isole et ou un glisser la prend.
    static func pointDePiece(_ m: MoteurPieces, _ i: Int) throws -> CGPoint {
        let a = try #require(m.projetee?.ancresPieces[i])
        let coin = CGPoint(x: a.maxX - 3, y: a.maxY - 3)
        let points = [coin] + stride(from: 0.95, through: 0.05, by: -0.05).flatMap { fy in
            stride(from: 0.95, through: 0.05, by: -0.05).map { fx in CGPoint(x: a.minX + a.width * fx, y: a.minY + a.height * fy) }
        }
        return try #require(points.first { p in
            m.noeudSous(p) == nil && m.pieceSous(p) == i && m.projetee?.piece(sous: p) == i
        })
    }

    static func indice(_ e: EntreeScene, _ nom: String) throws -> Int {
        try #require(e.scene.pieces.firstIndex { $0.nom == .maison(nom) })
    }

    /// Attend, 5 s au plus, que `condition` soit vraie (une disposition calculee hors du fil principal).
    static func attendre(_ condition: () -> Bool) async throws {
        var n = 0
        while !condition() && n < 500 {
            try await Task.sleep(for: .milliseconds(10))
            n += 1
        }
    }

    /// Disposition installee, premiere image : un nom par noeud, etage et piece, et « ⌂ Maison ».
    @Test func installerEtDessiner() throws {
        let (m, e) = try Self.moteur()
        #expect(m.pret)
        #expect(m.positions.count == e.scene.pieces.count && m.geometrie.rayons.count == 4)
        #expect(m.etiquettes.count == e.scene.noeuds.count + e.scene.etages.count + e.scene.pieces.count + 1)
        #expect(m.projetee?.blocs.count == e.scene.pieces.count)
        #expect(m.etiquettes.contains { $0.vu })
    }

    /// Le bouton « Voisins » : en mode « chemins », les voisins entendus du noeud selectionne se dessinent par defaut ;
    /// masques, ils ne le sont plus (les chemins restent), et le remontrer les rend. En mode « tous », sans effet.
    @Test func voisinsALaSelection() throws {
        let (m, _) = try Self.moteur()
        #expect(m.liens == .chemins && m.voisins, "par defaut : chemins, voisins montres")
        m.selection = NomsDemo.Ieee.lampeBureau
        func compte() throws -> (voisins: Int, chemins: Int, radio: Int) {
            Self.dessiner(m)
            let l = try #require(m.projetee).liensRouteurs
            return (l.filter(\.voisin).count, l.filter { $0.genre == .chemin }.count, l.filter { $0.genre == .radio && !$0.voisin }.count)
        }
        let montres = try compte()
        #expect(montres.voisins > 0 && montres.chemins > 0 && montres.radio == 0)
        m.voisins = false
        let masques = try compte()
        #expect(masques.voisins == 0 && masques.chemins == montres.chemins, "seuls les voisins disparaissent")
        m.voisins = true
        #expect(try compte().voisins == montres.voisins)
        m.voisins = false
        m.liens = .tous
        let tous = try compte()
        #expect(tous.voisins == 0 && tous.chemins == 0 && tous.radio > 0, "tous les liens radio, quel que soit le bouton")
        #expect(!MoteurPieces(voisins: false).voisins && MoteurPieces().voisins)
    }

    /// La ligne de niveau suit le zoom (precision 7 du plan 4b) : sous k = 0,42, les pieces seules ;
    /// jusqu'a 0,6, les pieces et les routeurs ; au-dela, les noms masques ou tous lisibles. Une piece
    /// isolee la remplace.
    @Test func ligneDeNiveauSelonLeZoom() throws {
        let (m, e) = try Self.moteur()
        m.fige = true
        func texte(_ k: Double) throws -> String {
            m.poserZoom(echelle: k, vers: nil)
            Self.dessiner(m)
            let p = try #require(m.projetee)
            #expect(abs(p.echelle - k) < 1e-6)
            return LigneNiveauVue.texte(m.ligneNiveau)
        }
        #expect(try texte(0.3) == String(localized: "Vue d'ensemble : les pièces"))
        #expect(try texte(0.4) == String(localized: "Vue d'ensemble : les pièces"))
        #expect(try texte(0.45) == String(localized: "Mi-distance : les pièces et les routeurs"))
        #expect(try texte(0.55) == String(localized: "Mi-distance : les pièces et les routeurs"))
        let loin = try texte(1)
        switch m.ligneNiveau {
        case .lisibles:
            #expect(loin == String(localized: "Tous les noms sont lisibles"))
        case .masques(1):
            #expect(loin == String(localized: "1 nom masqué faute de place : rapprochez-vous (molette)"))
        case .masques(let n):
            #expect(n > 1)
            #expect(loin == String(localized: "\(n) noms masqués faute de place : rapprochez-vous (molette)"))
        default:
            Issue.record("au-dela de 0,6 : les noms masques ou tous lisibles, pas \(m.ligneNiveau)")
        }
        m.poserIsolement(try Self.indice(e, "Salon"))
        Self.dessiner(m)
        let isolee = String(localized: "Pièce isolée : \("Salon") · clic sur une autre pièce pour y aller, clic à côté ou Échap pour revenir")
        #expect(LigneNiveauVue.texte(m.ligneNiveau) == isolee)
    }

    /// Noms de la demo, avec leurs vrais textes mesures et leurs vraies ancres, places par le moteur dans
    /// une fenetre de 820 x 680 (la plus petite) ou de 1400 x 900, en 2D et en 3D, a k = 0,5, 1 et 2,5 vers le salon (la
    /// piece la plus chargee) : aucun nom pose ne chevauche un autre (hors noms d'etage, poses meme s'ils
    /// chevauchent), tous restent dans le cadre, et aucun ne touche une pastille opaque.
    @Test(arguments: [CGSize(width: 820, height: 680), CGSize(width: 1400, height: 900)], [false, true])
    func demoSansChevauchement(_ taille: CGSize, troisD: Bool) throws {
        let (_, e) = try NomsSceneTests.demo()
        let salon = try Self.indice(e, "Salon")
        for k in [0.5, 1, 2.5] {
            let m = MoteurPieces(troisD: troisD)
            m.fige = true
            // Le haut de la fenetre de la demo : la ligne des capsules, le bandeau de scission et le fil.
            m.marges = (FenetrePieces.margeHaut(bas: 90), FenetrePieces.margeBas(pile: nil))
            m.poserTaille(taille)
            m.installerMaintenant(e)
            m.poserZoom(echelle: k, vers: m.centrePiece(salon))
            // Deux images : la premiere pose les noms, la seconde les garde a leur place.
            for _ in 0..<2 { Self.dessiner(m, taille: taille) }
            let p = try #require(m.projetee)
            let poses = m.etiquettes.filter { $0.vu && !$0.fixe }
            let cas = "k = \(k), \(Int(taille.width)) x \(Int(taille.height)), 3D : \(troisD)"
            #expect(poses.contains { if case .noeud = $0.genre { true } else { false } }, "\(cas)")
            let pastilles = p.disques.filter { $0.opacite > 0.5 }.map { d in
                CGRect(x: Double(d.centre.x) - d.rayon, y: Double(d.centre.y) - d.rayon, width: 2 * d.rayon, height: 2 * d.rayon)
            }
            for (a, l) in poses.enumerated() {
                #expect(PlacementNoms.dansCadre(l.rect, taille), "\(l.genre) hors du cadre, \(cas)")
                for q in poses[(a + 1)...] {
                    #expect(!PlacementNoms.chevauche(l.rect, q.rect), "\(l.genre) sur \(q.genre), \(cas)")
                }
                #expect(!pastilles.contains { PlacementNoms.chevauche(l.rect, $0) }, "\(l.genre) sur une pastille, \(cas)")
            }
        }
    }

    /// La vue se releve avec la fiche, au-dessus de la legende ouverte, et descend sous un bandeau : quand
    /// les marges changent, le cadre les rejoint en 0,3 s, sur la courbe de la fiche qui glisse ; l'horloge
    /// tourne jusqu'au bout. Avec « Reduire les animations », par un fondu : la scene s'efface, les marges
    /// sautent a mi-chemin, la scene revient. Tout de suite avant la premiere disposition, et pour une
    /// capture.
    ///
    /// `t` est l'heure de l'horloge du moteur, le temps d'eveil de la machine (`MoteurPieces.maintenant()`) :
    /// donnee en argument, de 17 min a 90 jours d'eveil, pour que le test ne depende pas de l'heure. La fin
    /// d'un glissement est evaluee 0,01 s apres son terme : `(t + 0,3) - t`, arrondi, vaut selon la plage de
    /// `t` un cran de moins que 0,3, et le glissement ne serait pas fini.
    @Test(arguments: [1_020.0, 10_800, 200_000, 1_198_161, 2_592_000, 7_776_000])
    func margesQuiGlissent(eveil t: Double) throws {
        let avant = MoteurPieces()
        avant.marges = (84, 50)
        #expect(avant.margesDuCadre(0).bas == 50)
        avant.marges = (84, 190)
        #expect(avant.margesDuCadre(0).bas == 190 && !avant.margesEnRoute, "avant la premiere disposition")
        let (m, _) = try Self.moteur()
        #expect(m.margesDuCadre(t).haut == 84 && m.margesDuCadre(t).bas == 50)
        m.marges = (84, 190)
        #expect(m.margesDuCadre(t).bas == 50, "le depart")
        #expect(m.margesEnRoute && m.doitContinuer(t + 0.15))
        let mi = m.margesDuCadre(t + 0.15).bas
        #expect(mi > 50 + 0.9 * 140 && mi < 190, "a mi-temps, presque arrivee : la courbe de la fiche (\(mi))")
        #expect(m.margesDuCadre(t + 0.31).bas == 190 && !m.margesEnRoute, "fini, 0,01 s apres son terme")
        m.marges = (84, 50)
        _ = m.margesDuCadre(t + 1)
        let enRoute = m.margesDuCadre(t + 1.1).bas
        #expect(enRoute > 50 && enRoute < 190)
        m.marges = (120, 50)
        let detour = m.margesDuCadre(t + 1.1)
        #expect(detour.haut == 84 && detour.bas == enRoute, "un autre changement repart d'ou il en est")
        #expect(m.margesDuCadre(t + 1.41).haut == 120 && m.margesDuCadre(t + 1.41).bas == 50)
        m.reduire = true
        m.marges = (84, 190)
        #expect(m.margesDuCadre(t + 2).bas == 50 && m.margesEnRoute && m.opaciteMarges == 1,
                "« Reduire les animations » : un fondu")
        #expect(m.margesDuCadre(t + 2.1).bas == 50 && abs(m.opaciteMarges - 1.0 / 3) < 1e-6, "la scene s'efface")
        #expect(m.margesDuCadre(t + 2.2).bas == 190 && abs(m.opaciteMarges - 1.0 / 3) < 1e-6,
                "a mi-chemin, les marges sautent ; la scene revient")
        #expect(m.margesDuCadre(t + 2.31).bas == 190 && m.opaciteMarges == 1 && !m.margesEnRoute)
        m.reduire = false
        m.fige = true
        m.marges = (100, 50)
        #expect(m.margesDuCadre(t + 3).haut == 100 && !m.margesEnRoute, "une capture : tout de suite")
    }

    /// La legende s'ouvre ou se replie (un clic sur son en-tete ou son etiquette) : le recadrage qui l'accompagne prend
    /// sa duree, 0,45 s (verification du 02/10), sur la meme courbe ; avec « Reduire les animations », un fondu de
    /// 0,45 s. Le changement suivant, sans elle (la fiche, un bandeau), reprend les 0,3 s de la fiche. Evalue a des
    /// instants decales de `t`, le temps d'eveil, comme `margesQuiGlissent`.
    @Test(arguments: [1_020.0, 10_800, 200_000, 1_198_161, 2_592_000, 7_776_000])
    func margesQuiGlissentAvecLaLegende(eveil t: Double) throws {
        let (m, _) = try Self.moteur()
        #expect(m.margesDuCadre(t).bas == 50)
        m.legendeBasculee()
        m.marges = (84, 246)
        #expect(m.margesDuCadre(t).bas == 50, "le depart")
        let apres = m.margesDuCadre(t + 0.31).bas
        #expect(m.margesEnRoute && apres > 50 && apres < 246, "encore en route apres 0,3 s : \(apres)")
        #expect(m.margesDuCadre(t + 0.46).bas == 246 && !m.margesEnRoute, "fini, 0,01 s apres 0,45 s")
        m.marges = (84, 50)
        _ = m.margesDuCadre(t + 1)
        #expect(m.margesDuCadre(t + 1.31).bas == 50 && !m.margesEnRoute, "sans la legende : 0,3 s")
        m.reduire = true
        m.legendeBasculee()
        m.marges = (84, 246)
        #expect(m.margesDuCadre(t + 2).bas == 50 && m.margesEnFondu, "« Reduire les animations » : un fondu")
        #expect(m.margesDuCadre(t + 2.2).bas == 50 && m.opaciteMarges < 1, "avant la mi-temps (0,225 s), la scene s'efface")
        #expect(m.margesDuCadre(t + 2.25).bas == 246, "apres la mi-temps, les marges ont saute")
        #expect(m.margesDuCadre(t + 2.46).bas == 246 && m.opaciteMarges == 1 && !m.margesEnRoute)
    }

    /// Clic sur une piece : elle s'isole (le fil la nomme) ; sur un appareil : sa fiche ; a cote : la
    /// fiche se ferme et la vue revient a la maison.
    @Test func clics() throws {
        let (m, e) = try Self.moteur()
        let salon = try Self.indice(e, "Salon")
        m.cliquer(try Self.pointDePiece(m, salon))
        #expect(m.estIsolee && m.focus == salon && m.isolee == "Salon")
        let disque = try #require(m.projetee?.disques.first { $0.noeud == NomsDemo.Ieee.pont })
        m.cliquer(disque.centre)
        #expect(m.selection == NomsDemo.Ieee.pont)
        m.cliquer(CGPoint(x: 5, y: Self.taille.height / 2))
        #expect(m.selection == nil && !m.estIsolee && m.isolee == nil && m.focus == nil)
    }

    /// Un clic sur le nom d'une piece (son nom et le compte de ses appareils) l'isole, comme un clic sur sa carte ou
    /// sa boite (verification du 02/10) : en 3D, les boites sont petites, et l'on clique volontiers sur le nom, pose a
    /// cote. Un clic au centre du nom de chaque piece de la demo isole cette piece, en 2D et en 3D ; le nom, dessine
    /// par-dessus, l'emporte sur la boite d'une autre piece qu'il recouvre. Par le geste entier (appuyer, relacher sans
    /// bouger), et un double-clic sur le nom n'est pas celui du fond (qui ramenerait a la vue d'ensemble). Un clic droit
    /// sur le nom n'est pas sur le fond. Un clic sur le nom d'un appareil ouvre toujours sa fiche.
    @Test(arguments: [false, true]) func clicSurLeNomDUnePiece(troisD: Bool) throws {
        let (_, e) = try NomsSceneTests.demo()
        func moteur() -> MoteurPieces {
            let m = MoteurPieces(troisD: troisD)
            m.marges = (84, 50)
            m.poserTaille(Self.taille)
            m.installerMaintenant(e)
            // La premiere image pose les noms, la seconde les garde a leur place.
            for _ in 0..<2 { Self.dessiner(m) }
            return m
        }
        let m = moteur()
        let projetee = try #require(m.projetee)
        let noms = m.etiquettes.compactMap { l -> (Int, CGPoint)? in
            guard l.vu, case .piece(let i) = l.genre else { return nil }
            return (i, CGPoint(x: l.rect.midX, y: l.rect.midY))
        }
        let cas = "3D : \(troisD)"
        #expect(noms.count == e.scene.pieces.count, "\(cas) : chaque piece montre son nom")
        #expect(noms.allSatisfy { projetee.piece(sous: $0.1) != $0.0 }, "\(cas) : chaque nom est pose hors de sa boite")
        for (i, c) in noms {
            #expect(m.noeudSous(c) == nil && m.cible(en: c) != .fond, "\(cas) : le nom de la piece \(i) n'est pas le fond")
            m.cliquer(c)
            #expect(m.focus == i && m.estIsolee, "\(cas) : un clic sur le nom de la piece \(i) l'isole (focus \(String(describing: m.focus)))")
        }
        // Le geste entier, puis un second clic sur le nom, assez tot pour un double-clic.
        let n = moteur()
        let (i, c) = try #require(noms.first)
        n.glisser(c, depart: c)
        n.relacher(c, a: 100)
        #expect(n.focus == i && n.estIsolee, "\(cas) : appuyer et relacher sur le nom")
        n.glisser(c, depart: c)
        n.relacher(c, a: 100.1)
        #expect(n.focus == i && n.estIsolee, "\(cas) : un double-clic sur le nom n'est pas celui du fond")
        // Le nom d'un appareil, de pres : sa fiche.
        let a = moteur()
        a.poserZoom(echelle: 1.6, vers: a.centrePiece(try Self.indice(e, "Salon")))
        for _ in 0..<2 { Self.dessiner(a) }
        let appareil = a.etiquettes.compactMap { l -> (String, CGPoint)? in
            guard l.vu, case .noeud(let id) = l.genre else { return nil }
            let c = CGPoint(x: l.rect.midX, y: l.rect.midY)
            return a.projetee?.noeud(sous: c) == nil ? (id, c) : nil
        }.first
        let (id, centre) = try #require(appareil, "\(cas) : un nom d'appareil pose, loin des pastilles")
        a.cliquer(centre)
        #expect(a.selection == id && a.focus == nil, "\(cas) : le nom d'un appareil ouvre sa fiche")
    }

    /// Retour lance avant la premiere image de l'isolement (isoler puis sortir, sans image entre les
    /// deux) : rien a defaire, la piece est relachee tout de suite, ses reperes « ailleurs » partent, et
    /// les noms des appareils sont de nouveau voulus.
    @Test func retourAvantLaPremiereImage() throws {
        let (m, e) = try Self.moteur()
        m.poserZoom(echelle: 1, vers: nil)
        let salon = try Self.indice(e, "Salon")
        m.isoler(salon)
        #expect(m.focus == salon && !m.textes.ailleurs.isEmpty)
        m.sortir()
        #expect(m.focus == nil && m.textes.ailleurs.isEmpty && !m.estIsolee && m.isolee == nil)
        Self.dessiner(m)
        #expect(m.etiquettes.contains { l in
            if case .noeud = l.genre { return l.voulu }
            return false
        })
    }

    /// Glisser une piece la deplace dans son etage, sans sortir du plateau ; au relachement, sa place
    /// est gardee sur disque.
    @Test func glisserUnePiece() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(fichier: url)
        let cuisine = try Self.indice(e, "Cuisine")
        let avant = m.positions[cuisine]
        let depart = try Self.pointDePiece(m, cuisine)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 30, y: depart.y), depart: depart)
        m.glisser(CGPoint(x: depart.x + 5000, y: depart.y), depart: depart)
        m.relacher(CGPoint(x: depart.x + 5000, y: depart.y))
        let apres = m.positions[cuisine]
        #expect(apres.x > avant.x)
        let r = m.geometrie.rayons[e.scene.pieces[cuisine].etage]
            - 0.5 * hypot(m.cartes[cuisine].largeur, m.cartes[cuisine].profondeur)
        #expect(simd_length(apres) <= r + 1e-9, "borne au plateau")
        #expect(!m.estIsolee, "un glisser n'isole pas")
        let gardee = PlacesGardees.lire(url).maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
        #expect(gardee == PlacesGardees.Place(x: apres.x, z: apres.y))
    }

    /// Deux zones de Maison du meme nom : un seul etage, et la disposition s'installe sans plantage.
    @Test func zonesHomonymes() throws {
        let (s, _) = try NomsSceneTests.demo()
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Terrasse", "Abri"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis",
                                                          "Grenier", "Salle de jeux"]),
                        ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Entrée", "Buanderie"])]
        s.noms.maison = maison
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(e.scene.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage"])
        let m = Self.moteur(e)
        #expect(m.geometrie.rayons.count == 2 && m.positions.count == e.scene.pieces.count)
    }

    /// Une place demesuree dans `positions-pieces.json` (fichier abime ou edite a la main) : elle est
    /// ignoree, la vue reste finie, et un glisser ecrit de nouveau le fichier.
    @Test func placeDemesureeDansLeFichier() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (_, e) = try NomsSceneTests.demo()
        var abime = PlacesGardees()
        abime.garder(SIMD2(1e308, 0), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: e.domicile)
        try abime.ecrire(dans: url)
        let m = Self.moteur(e, fichier: url)
        #expect(m.geometrie.rayons.allSatisfy(\.isFinite) && m.orbite.distance.isFinite && m.orbite.cible.x.isFinite)
        let cuisine = try Self.indice(e, "Cuisine")
        let depart = try Self.pointDePiece(m, cuisine)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 30, y: depart.y), depart: depart)
        m.relacher(CGPoint(x: depart.x + 30, y: depart.y))
        let fin = m.positions[cuisine]
        let gardee = PlacesGardees.lire(url).maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
        #expect(gardee == PlacesGardees.Place(x: fin.x, z: fin.y))
    }

    /// Un releve recu pendant le glisser d'une piece (meme structure, un etat change) attend le
    /// relachement : la piece ne saute pas a son ancienne place, et la place gardee est celle du geste ;
    /// la scene s'applique ensuite, avec cette place.
    @Test func relevePendantUnGlisser() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(fichier: url)
        var autre = e
        autre.apparences[NomsDemo.Ieee.pont] = DessinNoeud.Apparence(forme: .anneau, couleur: .appareil(.disparu))
        #expect(autre != e && autre.cleDisposition == e.cleDisposition)
        let cuisine = try Self.indice(e, "Cuisine")
        let avant = m.positions[cuisine]
        let depart = try Self.pointDePiece(m, cuisine)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 30, y: depart.y), depart: depart)
        let pendant = m.positions[cuisine]
        #expect(pendant != avant)
        m.recevoir(autre)
        #expect(m.entree == e, "pendant le glisser, la scene attend")
        #expect(m.positions[cuisine] == pendant, "la piece ne revient pas a sa place d'avant le geste")
        m.glisser(CGPoint(x: depart.x + 60, y: depart.y), depart: depart)
        let fin = m.positions[cuisine]
        #expect(fin.x > pendant.x)
        m.relacher(CGPoint(x: depart.x + 60, y: depart.y))
        let gardee = PlacesGardees.lire(url).maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
        #expect(gardee == PlacesGardees.Place(x: fin.x, z: fin.y), "la place gardee est celle du geste")
        #expect(m.entree == autre, "au relachement, la scene en attente s'applique")
        #expect(m.positions[cuisine] == fin, "avec la place du geste")
        // Glisser annule (sans relachement) : le geste suivant, parti d'ailleurs, le clot ; la piece garde
        // sa place, et la scene en attente s'applique a la fin de ce geste.
        let (n, _) = try Self.moteur()
        n.glisser(depart, depart: depart)
        n.glisser(CGPoint(x: depart.x + 30, y: depart.y), depart: depart)
        let annule = n.positions[cuisine]
        n.recevoir(autre)
        let fond = CGPoint(x: 5, y: Self.taille.height / 2)
        n.glisser(fond, depart: fond)
        #expect(n.entree == e && n.places.maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
                == PlacesGardees.Place(x: annule.x, z: annule.y))
        n.relacher(fond)
        #expect(n.entree == autre && n.positions[cuisine] == annule)
    }

    /// Un releve qui change la structure (une piece de moins) pendant le glisser d'une piece : ni
    /// indice perime ni plantage, que sa disposition finisse pendant le geste ou soit lancee apres ; la
    /// scene s'applique au relachement, la piece glissee a la place du geste.
    @Test(.timeLimit(.minutes(1))) func releveQuiChangeLaStructurePendantUnGlisser() async throws {
        let (s, _) = try NomsSceneTests.demo()
        var maison = try #require(s.noms.maison)
        for k in maison.accessoires.indices where maison.accessoires[k].piece == "Chambre d'amis" {
            maison.accessoires[k].piece = "Chambre"
        }
        s.noms.maison = maison
        let autre = EntreeScene(surveillance: s, places: PlacesGardees())
        // Disposition finie pendant le geste (`installerMaintenant` : comme un calcul qui se termine).
        let (m, e) = try Self.moteur()
        #expect(autre.scene.pieces.count == e.scene.pieces.count - 1)
        let jeux = try Self.indice(e, "Salle de jeux")
        #expect(jeux >= autre.scene.pieces.count, "son indice n'existe plus dans la nouvelle scene")
        let depart = try Self.pointDePiece(m, jeux)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 20, y: depart.y), depart: depart)
        m.installerMaintenant(autre)
        #expect(m.entree == e, "pendant le glisser, la scene attend")
        m.glisser(CGPoint(x: depart.x + 40, y: depart.y), depart: depart)
        let fin = m.positions[jeux]
        m.relacher(CGPoint(x: depart.x + 40, y: depart.y))
        #expect(m.entree == autre && m.positions.count == autre.scene.pieces.count)
        #expect(m.positions[try Self.indice(autre, "Salle de jeux")] == fin)
        // Releve recu pendant le geste : sa disposition, lancee au relachement, garde la place du geste.
        let (n, _) = try Self.moteur()
        let depart2 = try Self.pointDePiece(n, jeux)
        n.glisser(depart2, depart: depart2)
        n.glisser(CGPoint(x: depart2.x + 20, y: depart2.y), depart: depart2)
        n.recevoir(autre)
        n.glisser(CGPoint(x: depart2.x + 40, y: depart2.y), depart: depart2)
        let fin2 = n.positions[jeux]
        n.relacher(CGPoint(x: depart2.x + 40, y: depart2.y))
        while n.entree != autre { try await Task.sleep(for: .milliseconds(10)) }
        #expect(n.positions[try Self.indice(autre, "Salle de jeux")] == fin2)
    }

    /// Clics droits : l'ordre des etages change et se garde ; « Replacer les pieces automatiquement »
    /// oublie les places, pas l'ordre.
    @Test func etagesEtReplacement() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(fichier: url)
        #expect(m.peutDeplacerEtage(0, de: 1) && !m.peutDeplacerEtage(3, de: 1) && !m.peutDeplacerEtage(0, de: -1))
        m.deplacerEtage(0, de: 1)
        let ordre = ["zone:Jardin", "zone:Rez-de-chaussée", "zone:Étage", "zone:Combles"]
        #expect(m.places.maison(e.domicile).ordreEtages == ordre)
        let depart = try Self.pointDePiece(m, 0)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 20, y: depart.y), depart: depart)
        m.relacher(CGPoint(x: depart.x + 20, y: depart.y))
        #expect(!m.places.maison(e.domicile).etages.isEmpty)
        m.replacerPieces()
        #expect(m.places.maison(e.domicile).etages.isEmpty)
        #expect(PlacesGardees.lire(url).maison(e.domicile).ordreEtages == ordre)
    }

    /// « Replacer les pieces automatiquement » pendant un geste, un releve en attente de sa fin : c'est
    /// ce releve qui est recalcule, puis pose ; il ne se perd pas.
    @Test(.timeLimit(.minutes(1))) func replacerGardeLeReleveEnAttente() async throws {
        let (s, e) = try NomsSceneTests.demo()
        let m = Self.moteur(e)
        s.renommer(NomsDemo.Ieee.lampeBureau, en: "Pont du bureau, sous la lampe de l'écran")
        let autre = EntreeScene(surveillance: s, places: m.places)
        let fond = CGPoint(x: 5, y: Self.taille.height / 2)
        m.glisser(fond, depart: fond)
        m.glisser(CGPoint(x: fond.x + 30, y: fond.y), depart: fond)
        m.recevoir(autre)
        #expect(m.entree == e, "pendant le geste, le releve attend")
        m.replacerPieces()
        m.relacher(CGPoint(x: fond.x + 30, y: fond.y))
        try await Self.attendre { m.entree == autre }
        #expect(m.entree == autre, "le releve en attente est pose")
    }

    /// Glisser annule (sans relachement : la vue quitte la fenetre, ou le geste est interrompu) :
    /// `abandonnerGeste`, appele quand SwiftUI remet l'etat du geste a zero, le clot. La piece garde
    /// sa place, le releve en attente s'applique, et plus rien ne retient l'horloge ni les releves.
    @Test func glisserAnnule() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (m, e) = try Self.moteur(fichier: url)
        var autre = e
        autre.apparences[NomsDemo.Ieee.pont] = DessinNoeud.Apparence(forme: .anneau, couleur: .appareil(.disparu))
        let cuisine = try Self.indice(e, "Cuisine")
        let depart = try Self.pointDePiece(m, cuisine)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 30, y: depart.y), depart: depart)
        let fin = m.positions[cuisine]
        m.recevoir(autre)
        #expect(m.occupe && m.entree == e && m.doitContinuer(MoteurPieces.maintenant() + 1))
        m.abandonnerGeste()
        #expect(!m.occupe && !m.estIsolee)
        #expect(m.entree == autre && m.positions[cuisine] == fin, "le releve s'applique, la piece garde sa place")
        let gardee = PlacesGardees.lire(url).maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
        #expect(gardee == PlacesGardees.Place(x: fin.x, z: fin.y))
        #expect(!m.doitContinuer(MoteurPieces.maintenant() + 1), "l'horloge peut s'arreter")
        m.recevoir(e)
        #expect(m.entree == e, "le releve suivant s'applique tout de suite")
    }

    /// En 3D, un geste reste ouvert arrete la rotation lente ; clos par `abandonnerGeste`, elle reprend.
    @Test func rotationLenteApresUnGesteAnnule() throws {
        let (_, e) = try NomsSceneTests.demo()
        let m = MoteurPieces(troisD: true)
        m.marges = (84, 50)
        m.poserTaille(Self.taille)
        m.installerMaintenant(e)
        Self.dessiner(m)
        let fond = CGPoint(x: 5, y: Self.taille.height / 2)
        m.glisser(fond, depart: fond)
        let azimut = m.orbite.azimut
        Self.dessiner(m)
        Self.dessiner(m)
        #expect(m.orbite.azimut == azimut, "geste ouvert : pas de rotation lente")
        m.abandonnerGeste()
        Self.dessiner(m)
        Self.dessiner(m)
        #expect(m.orbite.azimut < azimut, "la rotation lente reprend")
    }

    /// `abandonnerGeste` suit aussi un geste fini : SwiftUI remet l'etat du geste a zero quand il se
    /// termine, avant ou apres `onEnded` (relacher). Dans les deux ordres, un glisser reste un glisser
    /// et un clic reste un clic.
    @Test func abandonEtRelachementDansLesDeuxOrdres() throws {
        let (_, e) = try NomsSceneTests.demo()
        let cuisine = try Self.indice(e, "Cuisine")
        for abandonDAbord in [false, true] {
            // Glisser une piece, relachee sur elle-meme : elle garde sa place, rien ne s'isole.
            let m = Self.moteur(e)
            let depart = try Self.pointDePiece(m, cuisine)
            let arrivee = CGPoint(x: depart.x - 30, y: depart.y)
            #expect(m.projetee?.piece(sous: arrivee) == cuisine)
            m.glisser(depart, depart: depart)
            m.glisser(arrivee, depart: depart)
            if abandonDAbord { m.abandonnerGeste() }
            m.relacher(arrivee)
            if !abandonDAbord { m.abandonnerGeste() }
            #expect(!m.occupe && !m.estIsolee && m.focus == nil && m.selection == nil,
                    "glisser, abandon d'abord : \(abandonDAbord)")
            #expect(m.places.maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
                    == PlacesGardees.Place(x: m.positions[cuisine].x, z: m.positions[cuisine].y))
            // Clic sur une piece : elle s'isole.
            let n = Self.moteur(e)
            let point = try Self.pointDePiece(n, cuisine)
            n.glisser(point, depart: point)
            if abandonDAbord { n.abandonnerGeste() }
            n.relacher(point)
            if !abandonDAbord { n.abandonnerGeste() }
            #expect(n.estIsolee && n.focus == cuisine, "clic, abandon d'abord : \(abandonDAbord)")
        }
    }

    /// Bascule : un envol, ou un fondu si « Reduire les animations » ; une piece isolee est relachee.
    /// Une scene recue pendant le mouvement attend sa fin.
    @Test func basculeEtAttente() throws {
        let (m, e) = try Self.moteur()
        m.cliquer(try Self.pointDePiece(m, try Self.indice(e, "Salon")))
        m.basculer(troisD: true)
        #expect(m.troisD && m.enMouvement && m.focus == nil && m.isolee == nil)
        var autre = e
        autre.libelles[NomsDemo.Ieee.lampeBureau] = LibellesNoeuds.Libelle(texte: "Pont Halo")
        m.recevoir(autre)
        #expect(m.entree == e, "pendant l'envol, la scene attend")
        let r = MoteurPieces(troisD: true)
        r.reduire = true
        r.marges = (84, 50)
        r.poserTaille(Self.taille)
        r.installerMaintenant(e)
        #expect(r.t == 1)
        r.basculer(troisD: false)
        #expect(!r.troisD && r.enMouvement)
    }

    /// Une scene qui change de noms : sa disposition se calcule hors du fil principal, et l'ancienne
    /// scene reste affichee pendant ce temps ; la nouvelle vient ensuite, avec ses cartes.
    @Test(.timeLimit(.minutes(1))) func nouvelleDisposition() async throws {
        let (m, e) = try Self.moteur()
        let autre = try GlissementTests.demo("Lampe bureau", nom: "Pont du bureau, sous la lampe de l'écran")
        #expect(autre.cleDisposition != e.cleDisposition)
        m.recevoir(autre)
        #expect(m.entree == e, "l'ancienne disposition reste affichee")
        while m.entree != autre { try await Task.sleep(for: .milliseconds(10)) }
        let bureau = try Self.indice(autre, "Bureau")
        #expect(m.cartes[bureau].largeur > 0 && m.positions.count == autre.scene.pieces.count)
    }

    /// L'ordre des etages change pendant le calcul d'une disposition (la cle de la disposition l'ignore,
    /// la scene suivante range autrement ses pieces) : la disposition, gardee par cles d'apres la scene
    /// pour laquelle elle a ete calculee, ne prete a aucune piece la place ou la carte d'une autre, ni
    /// a un etage le rayon d'un autre. Trois etages : « Sans piece » reste sur celui du bas.
    @Test(.timeLimit(.minutes(1))) func ordreDesEtagesPendantUnCalcul() async throws {
        let (s, _) = try NomsSceneTests.demo()
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie", "Terrasse",
                                                                    "Abri"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Chambre d'amis"]),
                        ZoneMaison(nom: "Combles", pieces: ["Bureau", "Salle de bain", "Grenier", "Salle de jeux"])]
        s.noms.maison = maison
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        let m = Self.moteur(e)
        s.renommer(NomsDemo.Ieee.lampeBureau, en: "Pont du bureau, sous la lampe de l'écran")
        let autre = EntreeScene(surveillance: s, places: m.places)
        #expect(autre.cleDisposition != e.cleDisposition)
        m.recevoir(autre)
        m.deplacerEtage(1, de: 1)
        let inverse = EntreeScene(surveillance: s, places: m.places)
        #expect(inverse.cleDisposition == autre.cleDisposition)
        #expect(inverse.scene.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Combles", "zone:Étage"])
        m.recevoir(inverse)
        #expect(m.entree == e, "l'ancienne disposition reste affichee pendant le calcul")
        while m.entree != inverse { try await Task.sleep(for: .milliseconds(10)) }
        // La meme disposition, calculee sur le fil principal pour la scene du calcul.
        let ref = Self.moteur(autre)
        for (i, p) in inverse.scene.pieces.enumerated() {
            let j = try #require(autre.scene.pieces.firstIndex { $0.id == p.id })
            #expect(m.positions[i] == ref.positions[j] && m.cartes[i] == ref.cartes[j], "\(p.id)")
        }
        for (k, et) in inverse.scene.etages.enumerated() {
            let l = try #require(autre.scene.etages.firstIndex { $0.id == et.id })
            #expect(m.geometrie.rayons[k] == ref.geometrie.rayons[l], "\(et.id)")
        }
    }

    /// Une piece lachee pendant le calcul d'une disposition garde la place du geste : le calcul est
    /// relance avec elle, et elle ne saute pas, a sa fin, a la place qu'il lui donnait.
    @Test(.timeLimit(.minutes(1))) func pieceLacheePendantUnCalcul() async throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (s, e) = try NomsSceneTests.demo()
        let m = Self.moteur(e, fichier: url)
        s.renommer(NomsDemo.Ieee.lampeBureau, en: "Pont du bureau, sous la lampe de l'écran")
        let autre = EntreeScene(surveillance: s, places: m.places)
        m.recevoir(autre)
        let cuisine = try Self.indice(e, "Cuisine")
        let depart = try Self.pointDePiece(m, cuisine)
        m.glisser(depart, depart: depart)
        m.glisser(CGPoint(x: depart.x + 40, y: depart.y), depart: depart)
        m.relacher(CGPoint(x: depart.x + 40, y: depart.y))
        let fin = m.positions[cuisine]
        #expect(m.entree == e, "le calcul n'est pas fini")
        while m.entree != autre { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.positions[try Self.indice(autre, "Cuisine")] == fin, "la piece garde la place du geste")
        let gardee = PlacesGardees.lire(url).maison(e.domicile).etages["zone:Rez-de-chaussée"]?["piece:Cuisine"]
        #expect(gardee == PlacesGardees.Place(x: fin.x, z: fin.y))
    }

    /// Zoom : la vue est touchee, un redimensionnement ne la recadre plus ; Echap y ramene.
    @Test func zoomEtRetour() throws {
        let (m, _) = try Self.moteur()
        let avant = m.orbite
        m.molette(-20, precis: false)
        #expect(m.vueTouchee)
        m.sortir()
        #expect(!m.vueTouchee && m.enMouvement)
        #expect(m.orbite == avant, "le vol part de la vue courante")
    }

    /// Double-clic sur le fond : retour a la vue d'ensemble d'un geste, zoom et deplacement annules, par
    /// le vol ; le premier clic a agi seul (clic a cote). Deux clics trop espaces, dans le temps ou sur
    /// l'ecran, ne sont que deux clics. « Reduire les animations » : un fondu, la camera ne saute qu'a
    /// mi-chemin.
    @Test func doubleClicSurLeFond() throws {
        let fond = CGPoint(x: 5, y: Self.taille.height / 2)
        let (m, e) = try Self.moteur()
        m.molette(-20, precis: false)
        m.relacher(fond, a: 100)
        #expect(m.vueTouchee, "un clic simple a cote ne recadre pas")
        m.relacher(fond, a: 100 + NSEvent.doubleClickInterval + 0.05)
        #expect(m.vueTouchee, "trop tard : un autre clic simple")
        m.relacher(CGPoint(x: fond.x + 8, y: fond.y), a: 100 + NSEvent.doubleClickInterval + 0.1)
        #expect(m.vueTouchee, "trop loin : un autre clic simple")
        m.relacher(CGPoint(x: fond.x + 8, y: fond.y), a: 100 + NSEvent.doubleClickInterval + 0.2)
        #expect(!m.vueTouchee && m.enMouvement, "double-clic : le vol vers la vue d'ensemble")
        // Piece isolee et fiche ouverte : le premier clic les ferme, le second ne relance rien.
        let (n, _) = try Self.moteur()
        n.cliquer(try Self.pointDePiece(n, try Self.indice(e, "Salon")))
        n.selection = NomsDemo.Ieee.pont
        n.relacher(fond, a: 200)
        #expect(n.selection == nil && !n.estIsolee && n.isolee == nil && n.focus == nil)
        n.relacher(fond, a: 200.1)
        #expect(!n.vueTouchee && !n.estIsolee)
        // « Reduire les animations » : un fondu depuis la vue courante.
        let (r, _) = try Self.moteur()
        r.reduire = true
        r.molette(-20, precis: false)
        let zoomee = r.orbite
        r.relacher(fond, a: 300)
        r.relacher(fond, a: 300.1)
        #expect(!r.vueTouchee && r.enMouvement)
        #expect(r.orbite == zoomee, "la camera ne saute qu'a mi-chemin du fondu")
    }

    /// La demo sur quatre plateaux (polissage C) : le rez-de-chaussee, le jardin, l'etage et les combles, chacun sur
    /// son niveau, sans choix ; `places` : les places gardees, dont les choix de niveau. Les zones prennent toutes les
    /// pieces de la demo, celles du jardin et des combles de sa maquette comprises.
    static func quatrePlateaux(_ places: PlacesGardees = PlacesGardees()) throws -> EntreeScene {
        let (s, _) = try NomsSceneTests.demo()
        var maison = try #require(s.noms.maison)
        maison.zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Buanderie"]),
                        ZoneMaison(nom: "Jardin", pieces: ["Entrée", "Terrasse", "Abri"]),
                        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Salle de bain"]),
                        ZoneMaison(nom: "Combles", pieces: ["Bureau", "Chambre d'amis", "Grenier", "Salle de jeux"])]
        s.noms.maison = maison
        return EntreeScene(surveillance: s, places: places)
    }

    /// Une vue large (2,4 : 1).
    static let large = CGSize(width: 1824, height: 760)
    /// Une vue carree : sur sa zone visible (1000 x 866, sous les marges des tests), la grille de quatre plateaux est
    /// 2 x 2.
    static let carree = CGSize(width: 1000, height: 1000)

    /// La grille suit la zone visible de la vue (polissage C, section 3.3) : la vue moins ses marges du haut et du bas,
    /// par la fonction du coeur, sur les rayons de la disposition ; 2 x 2 dans une vue carree, la rangee dans une vue
    /// large ; « En rangee », la rangee. La disposition des pieces, elle, ne depend ni de la taille, ni du reglage
    /// (section 4).
    @Test func grilleSelonLaTaille() throws {
        let e = try Self.quatrePlateaux()
        let m = Self.moteur(e, taille: Self.carree)
        #expect(m.grille && m.colonnes == 2 && m.geometrie.colonnes == 2)
        #expect(m.zoneVisible == CGSize(width: 1000, height: 1000 - 84 - 50))
        #expect(m.colonnes == GeometrieMaison.colonnes(rayons: m.geometrie.rayons, taille: m.zoneVisible))
        let l = MoteurPieces()
        l.marges = (84, 50)
        l.poserTaille(Self.large)
        l.installerMaintenant(e)
        #expect(l.colonnes == 4 && l.geometrie.colonnes == 4)
        let r = MoteurPieces()
        r.reglerGrille(false)
        r.marges = (84, 50)
        r.poserTaille(Self.carree)
        r.installerMaintenant(e)
        #expect(!r.grille && r.geometrie.colonnes == 4)
        for autre in [l, r] {
            #expect(autre.positions == m.positions && autre.cartes == m.cartes && autre.geometrie.rayons == m.geometrie.rayons)
        }
    }

    /// La zone visible change avec les marges sans la fiche (polissage C, section 3.3, decision de Djoko du 03/10) :
    /// ouvrir ou replier la legende recalcule la grille, a la vue d'ensemble, comme au redimensionnement, les plateaux
    /// glissant en 0,4 s ; une fiche ouverte, qui ne change que la marge du cadre, ne la change pas.
    @Test func grilleSurLaZoneVisible() throws {
        let m = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        #expect(m.colonnes == 2 && m.basGrille == nil)
        m.basGrille = 50
        m.marges.bas = 600
        Self.dessiner(m, taille: Self.carree)
        #expect(m.glissementPlateaux == nil && m.geometrieVisee.colonnes == 2, "une fiche ouverte : la grille reste")
        m.basGrille = 600
        Self.dessiner(m, taille: Self.carree)
        let g = try #require(m.glissementPlateaux)
        #expect(g.duree2D == CameraScene.dureeCases && m.geometrieVisee.colonnes == 4 && m.colonnes == 4)
        #expect(m.zoneVisible == CGSize(width: 1000, height: 1000 - 84 - 600))
    }

    /// Les marges de la demo, mesurees comme dans les images : le haut de la fenetre, puis le bas, la legende ouverte ou
    /// repliee.
    static let margesDemo = (haut: CGFloat(139), ouverte: CGFloat(249), repliee: CGFloat(30))

    /// La grille de la demo sur la zone visible (polissage C, sections 3.3 et 7), le jardin au niveau du
    /// rez-de-chaussee, hors de la maison : la rangee dans une fenetre ordinaire (1100 x 760) et dans celle des images
    /// (1440 x 900), la legende ouverte ou repliee, et dans une vue large (2,4 : 1) ; dans une fenetre carree de 900 pt,
    /// la rangee, la legende ouverte, 2 x 2 repliee ; dans une de 1000 pt, la legende ouverte, encore la rangee (la
    /// maison Zigbee de la demo, aux cartes plus petites que celles de Maillage Thread, y tient).
    @Test func grilleDeLaDemo() throws {
        let (s, _) = try NomsSceneTests.demo()
        let e = EntreeScene(surveillance: s, places: NomsDemo.places(etagee: true))
        let ordinaire = CGSize(width: 1100, height: 760), carree = CGSize(width: 900, height: 900)
        let cas: [(CGSize, Bool, Int)] = [(ordinaire, false, 4), (ordinaire, true, 4), (CapturesPieces.taille, false, 4),
                                         (CapturesPieces.taille, true, 4), (Self.large, false, 4), (carree, false, 4),
                                         (carree, true, 2), (CGSize(width: 1000, height: 1000), false, 4)]
        for (taille, repliee, colonnes) in cas {
            let m = MoteurPieces(places: NomsDemo.places(etagee: true))
            m.marges = (Self.margesDemo.haut, repliee ? Self.margesDemo.repliee : Self.margesDemo.ouverte)
            m.poserTaille(taille)
            m.installerMaintenant(e)
            #expect(m.colonnes == colonnes && m.geometrie.colonnes == colonnes, "\(taille), repliee : \(repliee)")
        }
    }

    /// « ⌂ Maison » evite les noms d'etage (polissage C, section 2, decision de Djoko du 03/10) : il se pose apres eux,
    /// a l'une de ses places candidates. Le cas de l'image `05-3d` : la demo en 3D, son jardin hors de la maison, dans
    /// la fenetre des images, la legende ouverte ; la maison y est petite, et son nom tombait sur celui des combles.
    @Test func maisonEviteLesEtages() throws {
        let (s, _) = try NomsSceneTests.demo()
        let e = EntreeScene(surveillance: s, places: NomsDemo.places(etagee: true))
        let m = MoteurPieces(places: NomsDemo.places(etagee: true))
        m.fige = true
        m.marges = (Self.margesDemo.haut, Self.margesDemo.ouverte)
        m.poserTaille(CapturesPieces.taille)
        m.installerMaintenant(e)
        m.poserTaille(CapturesPieces.taille)
        m.poserBascule(1)
        for _ in 0..<2 { Self.dessiner(m, taille: CapturesPieces.taille) }
        let maison = try #require(m.etiquettes.first { $0.genre == .maison && $0.vu })
        let etages = m.etiquettes.filter { if case .etage = $0.genre { $0.vu } else { false } }
        #expect(etages.count == e.scene.etages.count)
        for l in etages {
            #expect(!PlacementNoms.chevauche(l.rect, maison.rect), "\(l.genre) et la maison")
        }
    }

    /// Redimensionnement a la vue d'ensemble (polissage C, section 3.5) : la grille se recalcule, les plateaux glissent
    /// en 0,4 s, en cubique, et la vue se recadre a chaque image ; avec « Reduire les animations », tout de suite, la vue
    /// cadree avec eux. La grille en place reste a moins de 5 % du choix (hysteresis).
    @Test func redimensionnement() throws {
        let m = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        let depart = m.geometrie
        Self.dessiner(m, taille: Self.large)
        let g = try #require(m.glissementPlateaux)
        #expect(g.duree2D == CameraScene.dureeCases && g.duree3D == 0 && CameraScene.dureeCases == 0.4)
        #expect(m.geometrieVisee.colonnes == 4 && m.colonnes == 4)
        // A mi-temps, a mi-chemin (`(debut + 0,2) - debut` n'est pas exactement 0,2 : l'heure est grande).
        let mi = m.geometrie(a: g.debut + 0.2)
        let x0 = depart.centres2D[1].x, x1 = m.geometrieVisee.centres2D[1].x
        #expect(abs(mi.centres2D[1].x - (x0 + (x1 - x0) * 0.5)) < 1e-6 && abs(x1 - x0) > 1)
        // Au quart du temps, a 6,25 % du chemin : la rampe est cubique (4 k^3), et non lineaire, ni une autre rampe
        // symetrique, qui valent toutes 0,5 a mi-temps.
        let quart = m.geometrie(a: g.debut + 0.1)
        #expect(abs(quart.centres2D[1].x - (x0 + (x1 - x0) * 0.0625)) < 1e-6, "cubique entree-sortie : 6,25 % au quart du temps")
        #expect(m.geometrie(a: g.debut + 0.41) == m.geometrieVisee)
        #expect(m.orbite == CameraScene.canonique(m.geometrie, aspect: m.aspect, u: 0), "la vue se recadre a chaque image")
        // A la premiere image, le glissement vient de naitre et la vue vient d'etre cadree sur la geometrie de depart ; une
        // image plus tard, les plateaux ont avance, et la vue d'ensemble avec eux.
        Thread.sleep(forTimeInterval: 0.1)
        Self.dessiner(m, taille: Self.large)
        #expect(m.glissementPlateaux != nil && m.geometrie != m.geometrieVisee, "les plateaux sont en route")
        #expect(m.orbite == CameraScene.canonique(m.geometrie, aspect: m.aspect, u: 0), "la vue suit les plateaux en route")
        let r = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        r.reduire = true
        Self.dessiner(r, taille: Self.large)
        #expect(r.glissementPlateaux == nil && r.geometrie == r.geometrieVisee && r.geometrie.colonnes == 4)
        #expect(r.orbite == CameraScene.canonique(r.geometrie, aspect: r.aspect, u: 0), "« Reduire » : la vue d'ensemble suit la grille")
        // L'hysteresis : une taille ou le choix, sans la grille en place, serait autre, mais ou elle reste a moins de 5 % du
        // choix, est cherchee sur les rayons de la scene ; le moteur la garde, sans glissement.
        let h = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        let enPlace = try #require(h.colonnes)
        let rayons = h.geometrie.rayons
        let hauteur: CGFloat = 760
        let largeur = try #require(stride(from: 900.0, through: 2400, by: 10).first { l in
            let zone = CGSize(width: l, height: hauteur - 84 - 50)
            return GeometrieMaison.colonnes(rayons: rayons, taille: zone) != enPlace
                && GeometrieMaison.colonnes(rayons: rayons, taille: zone, enPlace: enPlace) == enPlace
        }, "une taille ou l'hysteresis garde la grille en place")
        Self.dessiner(h, taille: CGSize(width: largeur, height: hauteur))
        #expect(h.colonnes == enPlace && h.glissementPlateaux == nil, "l'hysteresis garde la grille en place")
        h.poserTaille(CGSize(width: largeur, height: hauteur))
        #expect(h.colonnes == enPlace, "la taille posee a la main la garde aussi")
    }

    /// Zoomee ou isolee, la grille attend le retour a la vue d'ensemble (polissage C, section 3.5) ; elle s'y pose
    /// ensuite, avec l'hysteresis du redimensionnement.
    @Test func grilleQuiAttend() throws {
        let m = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        m.reduire = true
        m.molette(-20, precis: false)
        Self.dessiner(m, taille: Self.large)
        #expect(m.vueTouchee && m.geometrieVisee.colonnes == 2)
        #expect(m.grilleEnAttente == MoteurPieces.GrilleEnAttente(duree: CameraScene.dureeCases, hysteresis: true))
        m.sortir()
        Self.dessiner(m, taille: Self.large)
        #expect(m.grilleEnAttente == nil && m.geometrieVisee.colonnes == 4 && m.geometrie == m.geometrieVisee)
        #expect(m.orbite == CameraScene.canonique(m.geometrie, aspect: m.aspect, u: 0), "« Reduire » : la vue d'ensemble suit la grille")
        let i = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        i.isoler(try Self.indice(try #require(i.entree), "Salon"))
        Self.dessiner(i, taille: Self.large)
        #expect(i.grilleEnAttente != nil && i.geometrieVisee.colonnes == 2, "isolee, la grille attend")
    }

    /// Le reglage « Etages en 2D » (polissage C, section 3.1) s'applique tout de suite a la vue ouverte : les plateaux
    /// glissent en 2,6 s, comme l'envol ; avec « Reduire les animations », tout de suite, la vue d'ensemble cadree avec
    /// eux. En 3D, il attend la 2D : l'envol vers la 2D se pose sur la grille de la zone visible du moment. Un vol
    /// commence pendant le glissement arrive la ou les plateaux arrivent : la vue isolee rejoint la piece.
    @Test func reglageDeLaGrille() throws {
        let m = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        m.reglerGrille(false)
        let g = try #require(m.glissementPlateaux)
        #expect(!m.grille && g.duree2D == CameraScene.dureeEnvol && g.duree3D == 0 && m.geometrieVisee.colonnes == 4)
        m.reglerGrille(true)
        #expect(m.geometrieVisee.colonnes == 2)
        let r = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        r.reduire = true
        r.reglerGrille(false)
        #expect(r.glissementPlateaux == nil && r.geometrie.colonnes == 4)
        #expect(r.orbite == CameraScene.canonique(r.geometrie, aspect: r.aspect, u: 0), "« Reduire » : la vue d'ensemble suit la grille")
        let trois = MoteurPieces(troisD: true)
        trois.marges = (84, 50)
        trois.poserTaille(Self.carree)
        trois.installerMaintenant(try Self.quatrePlateaux())
        trois.reglerGrille(false)
        #expect(trois.glissementPlateaux == nil && trois.grilleEnAttente != nil && trois.geometrieVisee.colonnes == 2)
        trois.basculer(troisD: false)
        #expect(trois.grilleEnAttente == nil && trois.geometrieVisee.colonnes == 4 && trois.enMouvement)
        // Le salon isole pendant le glissement : le vol de 1,3 s vise sa place d'arrivee, que `suivre` remet a jour a chaque
        // image. A 1,4 s, le vol est fini, les plateaux glissent encore, et la cible est le salon la ou il est.
        let v = Self.moteur(try Self.quatrePlateaux(), taille: Self.carree)
        let salon = try Self.indice(try #require(v.entree), "Salon")
        let avant = try #require(v.centrePiece(salon))
        v.reglerGrille(false)
        v.isoler(salon)
        Thread.sleep(forTimeInterval: 1.4)
        Self.dessiner(v, taille: Self.carree)
        #expect(v.glissementPlateaux != nil && !v.enMouvement, "le vol est fini, les plateaux glissent encore")
        let c = try #require(v.centrePiece(salon))
        #expect(abs(c.x - avant.x) > 1, "le salon s'est deplace avec sa grille")
        #expect(abs(v.orbite.cible.x - c.x) < 1e-6 && abs(v.orbite.cible.z - c.z) < 1e-6, "le vol arrive sur le salon la ou il est")
    }

    /// Une taille nulle ne choisit rien (polissage C, section 3.3) : la rangee en attendant ; la premiere vraie taille
    /// pose la grille et cadre la vue d'ensemble, sans autre condition.
    @Test func premiereVraieTaille() throws {
        let m = MoteurPieces()
        m.marges = (84, 50)
        m.poserTaille(.zero)
        m.installerMaintenant(try Self.quatrePlateaux())
        #expect(m.pret && m.colonnes == nil && m.geometrie.colonnes == 4)
        Self.dessiner(m, taille: Self.carree)
        #expect(m.colonnes == 2 && m.geometrie.colonnes == 2 && m.glissementPlateaux == nil)
        #expect(m.orbite == CameraScene.canonique(m.geometrie, aspect: m.aspect, u: 0))
    }

    /// Des niveaux changes (une zone mise a cote d'un etage) : les plateaux glissent vers leur nouvelle place, en 0,4 s
    /// en 2D et en 0,9 s en 3D (polissage C, section 1.3) ; avec « Reduire les animations », tout de suite. Chaque plateau
    /// part de sa place d'avant, retrouvee par sa cle, meme si leur ordre change ; un glissement en cours repart de
    /// l'image, avec le temps qui lui restait ; zoomee, la vue attend la grille.
    @Test func glissementApresUnChangementDeNiveau() throws {
        let e = try Self.quatrePlateaux()
        var places = PlacesGardees()
        places.ranger(Rangement(ordre: [], aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée")]),
                      domicile: e.domicile)
        let aCote = try Self.quatrePlateaux(places)
        for reduire in [false, true] {
            let m = Self.moteur(e)
            m.reduire = reduire
            m.installerMaintenant(aCote)
            #expect(m.geometrieVisee.colonnes == m.colonnes)
            if reduire {
                #expect(m.glissementPlateaux == nil && m.geometrie == m.geometrieVisee)
            } else {
                let g = try #require(m.glissementPlateaux)
                #expect(g.duree2D == CameraScene.dureeCases && g.duree3D == CameraScene.dureeNiveaux && CameraScene.dureeNiveaux == 0.9)
            }
        }
        // Le reglage glisse en 2,6 s ; des niveaux changes en cours de route : le glissement repart de l'image, avec le
        // temps qui lui restait en 2D (presque 2,6 s : plus que la moitie, et non les 0,4 s des niveaux), et les 0,9 s des
        // niveaux en 3D.
        let enCours = Self.moteur(e, taille: Self.carree)
        enCours.reglerGrille(false)
        let reglage = try #require(enCours.glissementPlateaux)
        #expect(reglage.duree2D == CameraScene.dureeEnvol)
        enCours.installerMaintenant(aCote)
        let reste = try #require(enCours.glissementPlateaux)
        #expect(reste.duree2D > CameraScene.dureeEnvol / 2 && reste.duree2D <= CameraScene.dureeEnvol
                && reste.duree3D == CameraScene.dureeNiveaux, "le temps qui restait : \(reste.duree2D) s")
        // Zoomee, la vue d'ensemble n'est pas la : la grille des niveaux changes attend, sans hysteresis.
        let zoomee = Self.moteur(e, taille: Self.carree)
        zoomee.reduire = true
        zoomee.molette(-20, precis: false)
        #expect(zoomee.vueTouchee && zoomee.grilleEnAttente == nil)
        zoomee.installerMaintenant(aCote)
        #expect(zoomee.grilleEnAttente == MoteurPieces.GrilleEnAttente(duree: CameraScene.dureeCases, hysteresis: false))
        // Le jardin a cote de l'etage change l'ordre des plateaux : le depart de chacun est sa place d'avant, retrouvee par
        // sa cle et non par sa position ; la boite, le pas, la sphere et le cadrage partent de l'image.
        var autres = PlacesGardees()
        autres.ranger(Rangement(ordre: [], aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Étage")]),
                      domicile: e.domicile)
        let reordonne = Self.moteur(e, taille: Self.carree)
        let avant = reordonne.geometrie
        let anciens = e.scene.etages.map(\.id)
        reordonne.installerMaintenant(try Self.quatrePlateaux(autres))
        let nouveaux = try #require(reordonne.scene).etages.map(\.id)
        #expect(nouveaux != anciens, "l'ordre des plateaux a change")
        let glissement = try #require(reordonne.glissementPlateaux)
        let depart = reordonne.geometrie(a: glissement.debut)
        for (i, cle) in nouveaux.enumerated() {
            let j = try #require(anciens.firstIndex(of: cle))
            #expect(depart.centres2D[i] == avant.centres2D[j] && depart.centres3D[i] == avant.centres3D[j], "depart de \(cle)")
        }
        #expect(depart.boite == avant.boite && depart.pasEtage == avant.pasEtage, "la boite et le pas partent de l'image")
        #expect(depart.centreSphere == avant.centreSphere && depart.rayonSphere == avant.rayonSphere
                && depart.rayonCadre == avant.rayonCadre, "la sphere et le cadrage partent de l'image")
    }

    /// ⌥ + glisser en 3D (polissage C, section 6) : le mode se fixe a l'appui ; ⌥ passe avant le glisser d'une piece,
    /// qui ne bouge pas ; la vue suit le pointeur a 0,7 fois sa vitesse, depuis l'orbite de l'appui ; relacher ⌥ en
    /// route ne change rien. La main ouverte tant que ⌥ est tenue, fermee pendant le geste ; la rotation lente s'arrete
    /// pendant le geste et reprend apres ; le double-clic ramene a la vue d'ensemble. En 2D, ⌥ ne change rien. Pendant le
    /// geste, la camera n'obeit qu'au pointeur (la maquette coupe ses controles) : l'inertie d'une rotation relachee, la
    /// molette et le pincement n'y touchent pas ; au relachement, ils reprennent.
    @Test func optionGlisser() throws {
        let (_, e) = try NomsSceneTests.demo()
        let m = MoteurPieces(troisD: true)
        m.marges = (84, 50)
        m.poserTaille(Self.taille)
        m.installerMaintenant(e)
        for _ in 0..<2 { Self.dessiner(m) }
        let salon = try Self.indice(e, "Salon")
        let d = try Self.pointDePiece(m, salon)
        let avant = m.positions[salon], depart = m.orbite
        m.survoler(d, option: true)
        #expect(m.curseurForme == .mainOuverte)
        m.glisser(d, depart: d, option: true)
        #expect(m.curseurForme == .mainFermee)
        m.glisser(CGPoint(x: d.x + 60, y: d.y + 20), depart: d, option: false)
        #expect(m.positions[salon] == avant, "la piece ne bouge pas")
        #expect(m.orbite == CameraScene.deplacerDansLEcran(depart, glisse: CGSize(width: 60, height: 20), cadre: m.cadre))
        #expect(m.vueTouchee)
        for _ in 0..<2 { Self.dessiner(m) }
        #expect(m.orbite.azimut == depart.azimut, "pas de rotation lente pendant le geste")
        m.relacher(CGPoint(x: d.x + 60, y: d.y + 20))
        #expect(m.curseurForme == .mainOuverte, "⌥ toujours tenue")
        m.changerOption(false)
        #expect(m.curseurForme != .mainOuverte && m.curseurForme != .mainFermee)
        for _ in 0..<2 { Self.dessiner(m) }
        #expect(m.orbite.azimut < depart.azimut, "la rotation lente reprend")
        let fond = CGPoint(x: 5, y: Self.taille.height / 2)
        m.relacher(fond, a: 100)
        m.relacher(fond, a: 100.1)
        #expect(!m.vueTouchee && m.enMouvement, "le double-clic : la vue d'ensemble, deplacement compris")
        let (n, e2) = try Self.moteur()
        let s2 = try Self.indice(e2, "Salon")
        let p2 = try Self.pointDePiece(n, s2)
        let avant2 = n.positions[s2]
        n.survoler(p2, option: true)
        #expect(n.curseurForme == .main, "en 2D, la main sur la piece")
        n.glisser(p2, depart: p2, option: true)
        n.glisser(CGPoint(x: p2.x + 30, y: p2.y), depart: p2, option: true)
        n.relacher(CGPoint(x: p2.x + 30, y: p2.y))
        #expect(n.positions[s2] != avant2, "en 2D, la piece glisse")
        // La camera n'obeit qu'au pointeur : ce qui attendait (le reste d'une rotation au glisser, le zoom d'un coup de
        // molette) attend et reprend au relachement ; la molette et le pincement du geste sont ignores, non differes, et
        // agissent de nouveau apres. Un moteur par cas, sans rotation lente : rien d'autre ne tourne ni ne zoome.
        let arrivee = CGPoint(x: fond.x + 60, y: fond.y)
        for cas in ["rotation amortie", "zoom amorti", "molette", "pincement"] {
            let k = MoteurPieces(troisD: true)
            k.rotation = false
            k.marges = (84, 50)
            k.poserTaille(Self.taille)
            k.installerMaintenant(e)
            for _ in 0..<2 { Self.dessiner(k) }
            if cas == "rotation amortie" {
                k.glisser(fond, depart: fond)
                k.glisser(CGPoint(x: fond.x + 300, y: fond.y), depart: fond)
                k.relacher(CGPoint(x: fond.x + 300, y: fond.y))
            } else if cas == "zoom amorti" {
                k.molette(20, precis: false)
            }
            let appui = k.orbite
            k.glisser(fond, depart: fond, option: true)
            k.glisser(arrivee, depart: fond, option: true)
            let attendue = CameraScene.deplacerDansLEcran(appui, glisse: CGSize(width: 60, height: 0), cadre: k.cadre)
            if cas == "molette" {
                k.molette(20, precis: false)
            } else if cas == "pincement" {
                k.pincer(1, en: fond)
                k.pincer(1.5, en: fond)
            }
            for _ in 0..<3 { Self.dessiner(k) }
            #expect(k.orbite == attendue, "\(cas) : pendant le geste, la camera ne suit que le pointeur")
            k.relacher(arrivee)
            for _ in 0..<2 { Self.dessiner(k) }
            if cas == "rotation amortie" || cas == "zoom amorti" {
                #expect(k.orbite != attendue, "\(cas) : au relachement, ce qui attendait reprend")
                continue
            }
            #expect(k.orbite == attendue, "\(cas) : ignore pendant le geste, non differe")
            if cas == "molette" {
                k.molette(20, precis: false)
                for _ in 0..<2 { Self.dessiner(k) }
                #expect(k.orbite.distance < attendue.distance, "apres le geste, la molette zoome de nouveau")
            } else {
                // Le pincement continue apres le geste : il n'agit que de son increment (0,03 %), sans sauter de ce qu'il
                // a fait pendant.
                k.pincer(1.5005, en: fond)
                Self.dessiner(k)
                #expect(abs(k.orbite.distance / attendue.distance - 1.5 / 1.5005) < 1e-9, "le pincement qui continue ne saute pas")
            }
        }
    }

    /// Ordre des couches : plateaux et equateur, blocs, liens enfant -> parent, liens entre routeurs,
    /// pastilles, lisere de la sphere, traits, noms.
    @Test func ordreDesCouches() {
        #expect(RenduCanvas.couches == [.plateaux, .blocs, .liensEnfants, .liensRouteurs, .pastilles, .sphere, .traits, .noms])
        #expect(Set(RenduCanvas.couches) == Set(RenduCanvas.Couche.allCases))
    }
}
