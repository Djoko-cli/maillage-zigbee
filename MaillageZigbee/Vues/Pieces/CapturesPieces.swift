import AppKit
import ImageIO
import MaillageCoeur
import SwiftUI
import UniformTypeIdentifiers

/// Images de la vue par pieces rendues par l'app elle-meme, en mode demo (`--args -demo -captures
/// <dossier>`), pour la relecture (spec de la vue par pieces, section 10) : 2D, envol, 3D, zooms,
/// pieces isolees, survol, la fiche du pont, la legende repliee ; puis les etages (polissage C, section 7) :
/// la grille 2 x 2 dans une fenetre carree, la meme fenetre en rangee, le jardin dans la maison, un etage isole en 2D
/// et en 3D, une piece isolee depuis son etage. Les images prennent la maison de demo nommee par son releve de Maison,
/// sur ses quatre etages (`NomsDemo.maisonFusionnee`), son jardin au niveau du rez-de-chaussee, hors de la maison
/// (`NomsDemo.places(etagee:)`) ; dans la fenetre des images, la legende ouverte ou repliee, sa grille est la
/// rangee (la zone visible, section 3.3). Puis un appareil a mi-chemin de son glissement vers une autre piece
/// (polissage D, section 6), et la fiche d'un appareil final qui garde son parent d'avant ; le mode focus en 2D et en 3D,
/// et la fiche d'un routeur, ses voisins deplies (etape 5) : les fiches montrent l'historique invente de la demo
/// (`MaillageDemo.historique`). Enfin, a part, la page
/// Reglages › Pont Hue, liee a un pont invente (`ecrireReglagesPont`). Sans fenetre montree ni capture d'ecran ;
/// l'app quitte ensuite. `ImageRenderer` ne rend ni la fenetre ni le verre : le haut de la fenetre et la
/// fiche y sont dessines comme dans les maquettes (`capturePieces`), avec les trois boutons de la
/// fenetre a leur place (`FeuxDeCapture`).
@MainActor
enum CapturesPieces {
    /// Contenu d'une fenetre de 1440 x 900, en 2x.
    nonisolated static let taille = CGSize(width: 1440, height: 900)
    /// Une fenetre carree, ou la grille de la demo est 2 x 2, la legende ouverte (polissage C, sections 3.3 et 7).
    nonisolated static let carree = CGSize(width: 1000, height: 1000)

    /// Une image : son nom, l'etat a poser sur le moteur, et la legende repliee ; la taille de la fenetre, les etages
    /// en grille ou en rangee, et les places gardees, dont le choix de niveau du jardin ; `deplacer` : apres la scene
    /// de la demo, celle des pieces choisies (« Placer dans une piece… »), posee a mi-chemin de son glissement.
    struct Cas {
        var nom: String
        var poser: (MoteurPieces, ScenePieces) -> Void
        var legendeRepliee = false
        var taille = CapturesPieces.taille
        var grille = true
        var places = NomsDemo.places(etagee: true)
        var deplacer: PiecesRouteurs?
        /// La fiche montre la liste de ses voisins entendus, depliee (etape 5).
        var listeVoisins = false
        /// Les lignes de changements regroupes du journal de la fiche depliees (etape 5, journal regroupe).
        var changementsDeplies = false
        /// La periode des courbes de la fiche ; nil, 24 h.
        var periode: PeriodeCourbes?
    }

    /// Le routeur inconnu de la demo, que le pont ne connait pas (sans piece), place dans la cuisine.
    static var appareilDansLaCuisine: PiecesRouteurs {
        var p = PiecesRouteurs()
        p.choisir("Cuisine", appareil: NomsDemo.Ieee.inconnu, domicile: NomsDemo.domicile)
        return p
    }

    /// Indice d'une piece de la scene (la premiere, sans elle).
    static func piece(_ scene: ScenePieces, _ nom: String) -> Int {
        scene.pieces.firstIndex { $0.nom == .maison(nom) } ?? 0
    }

    /// Indice d'un etage, une zone, de la scene (le premier, sans elle).
    static func etage(_ scene: ScenePieces, _ nom: String) -> Int {
        scene.etages.firstIndex { $0.nom == .zone(nom) } ?? 0
    }

    /// Les images, dans l'ordre : 2D, envol, 3D, zooms, pieces isolees, survol ; puis la fiche du pont de la demo, avec
    /// sa pastille, la vue relevee au-dessus d'elle ; et la legende repliee.
    static let cas: [Cas] = [
        Cas(nom: "01-2d") { _, _ in },
        Cas(nom: "02-envol-30") { m, _ in m.poserBascule(0.3) },
        Cas(nom: "03-envol-55") { m, _ in m.poserBascule(0.55) },
        Cas(nom: "04-envol-80") { m, _ in m.poserBascule(0.8) },
        Cas(nom: "05-3d") { m, _ in m.poserBascule(1) },
        Cas(nom: "06-3d-tournee") { m, _ in
            m.poserBascule(1)
            m.poserAzimut(-1.9)
        },
        Cas(nom: "07-2d-zoom-salon") { m, sc in m.poserZoom(echelle: 2.2, vers: m.centrePiece(piece(sc, "Salon"))) },
        Cas(nom: "08-2d-mi-distance") { m, _ in m.poserZoom(echelle: 0.5, vers: nil) },
        Cas(nom: "09-2d-loin") { m, _ in m.poserZoom(echelle: 0.36, vers: nil) },
        Cas(nom: "10-3d-isolee-salon") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Salon"))
        },
        Cas(nom: "11-2d-isolee-chambre") { m, sc in m.poserIsolement(piece(sc, "Chambre")) },
        Cas(nom: "12-2d-survol") { m, _ in m.poserSurvol(NomsDemo.Ieee.lampeChambreAmis) },
        Cas(nom: "13-2d-fiche-du-pont") { m, _ in m.selection = NomsDemo.Ieee.pont },
        Cas(nom: "14-2d-legende-repliee", poser: { _, _ in }, legendeRepliee: true),
        Cas(nom: "15-2d-carree-2x2", poser: { _, _ in }, taille: CapturesPieces.carree),
        Cas(nom: "16-2d-carree-en-rangee", poser: { _, _ in }, taille: CapturesPieces.carree, grille: false),
        Cas(nom: "17-3d-jardin-dedans", poser: { m, _ in m.poserBascule(1) }, places: NomsDemo.places(etagee: true, dehors: false)),
        Cas(nom: "18-2d-etage-isole") { m, sc in m.poserEtageIsole(etage(sc, "Étage")) },
        Cas(nom: "19-3d-etage-isole") { m, sc in
            m.poserBascule(1)
            m.poserEtageIsole(etage(sc, "Étage"))
        },
        Cas(nom: "20-3d-terrasse-depuis-le-jardin") { m, sc in
            m.poserBascule(1)
            m.poserIsolement(piece(sc, "Terrasse"), depuisEtage: true)
        },
        Cas(nom: "21-2d-appareil-en-route", poser: { m, sc in
            m.poserTransition(0.5)
            let sansPiece = sc.pieces.firstIndex { $0.nom == .sansPiece } ?? 0
            m.poserZoom(echelle: 1, vers: m.centrePiece(sansPiece))
        }, deplacer: appareilDansLaCuisine),
        // La fiche d'un appareil final endormi, avec son parent d'avant (pointille).
        Cas(nom: "22-2d-fiche-telecommande") { m, _ in m.selection = NomsDemo.Ieee.telecommandeChambre },
        // Le mode focus (etape 5) : la lampe de la chambre, son chemin jusqu'au pont, ses dependants et ses voisins
        // restent nets, le reste s'estompe ; en 2D puis en 3D.
        Cas(nom: "25-2d-focus-lampe-chambre") { m, _ in m.selection = NomsDemo.Ieee.lampeChambre },
        Cas(nom: "26-3d-focus-lampe-chambre") { m, _ in
            m.poserBascule(1)
            m.selection = NomsDemo.Ieee.lampeChambre
        },
        // La fiche d'un routeur, la liste de ses voisins depliee, et son historique : le changement de chemin marque.
        Cas(nom: "27-2d-fiche-lampe-bureau", poser: { m, _ in m.selection = NomsDemo.Ieee.lampeBureau },
            listeVoisins: true),
        // La meme fiche sur 7 j : les changements de chemin proches se fondent en un repere marque de leur nombre.
        Cas(nom: "28-2d-fiche-lampe-bureau-7j", poser: { m, _ in m.selection = NomsDemo.Ieee.lampeBureau },
            periode: .semaine),
        // Le journal de la fiche, ses changements de chemin d'une meme heure en une ligne : repliee, puis depliee ; et
        // l'alternance de deux relais, celle du detecteur de l'abri (journal regroupe).
        Cas(nom: "5c-fiche-lampe-bureau-journal-replie", poser: { m, _ in m.selection = NomsDemo.Ieee.lampeBureau }),
        Cas(nom: "5c-fiche-lampe-bureau-journal-deplie", poser: { m, _ in m.selection = NomsDemo.Ieee.lampeBureau },
            changementsDeplies: true),
        Cas(nom: "5c-fiche-detecteur-abri-journal-deplie", poser: { m, _ in m.selection = NomsDemo.Ieee.detecteurAbri },
            changementsDeplies: true),
    ]

    /// Evenements inventes des captures du journal regroupe : la lampe du bureau hesite entre plusieurs relais, le
    /// detecteur de l'abri entre deux parents, dans l'heure qui precede la fin de la demo (le changement de la demo
    /// s'y ajoute).
    static var evenementsHesitants: [Evenement] {
        func changement(_ type: TypeEvenement, _ ieee: String, _ nom: String, _ minutes: Double, _ avant: String,
                        _ apres: String) -> Evenement {
            Evenement(date: MaillageDemo.fin.addingTimeInterval(-minutes * 60), type: type, sujet: Sujet(id: ieee, nom: nom),
                      avant: avant, apres: apres, details: ["ieee": ieee])
        }
        let b = NomsDemo.Ieee.lampeBureau, d = NomsDemo.Ieee.detecteurAbri
        return [changement(.cheminChange, b, "Lampe bureau", 48, "Lampadaire salon", "Lampe chambre"),
                changement(.cheminChange, b, "Lampe bureau", 31, "Lampe chambre", "Plafonnier salon"),
                changement(.cheminChange, b, "Lampe bureau", 14, "Plafonnier salon", "Pont Hue"),
                changement(.parentChange, d, "Détecteur abri", 44, "Prise terrasse", "Ruban cuisine"),
                changement(.parentChange, d, "Détecteur abri", 29, "Ruban cuisine", "Prise terrasse"),
                changement(.parentChange, d, "Détecteur abri", 12, "Prise terrasse", "Ruban cuisine")]
    }

    /// Le pont invente de l'image des Reglages : adresse de documentation, identifiant et modele inventes.
    static let pontDeCapture = PontRetenu(adresse: "192.0.2.10", identifiant: "C0FFEEFFFE012345", modele: "Hue Bridge",
                                          manuel: false)

    /// L'image de Reglages › Pont Hue, lie au pont invente, avec les noms de la demo (`23-reglages-pont`). Rend son nom,
    /// ou nil si le rendu a echoue.
    static func ecrireReglagesPont(dans dossier: String, noms: NomsMaison) -> String? {
        let pont = NomsPont(capture: pontDeCapture, noms: noms)
        return ecrireReglages(Section { ReglagesPont() }.environment(pont), nom: "23-reglages-pont", dans: dossier)
    }

    /// L'image de Reglages › Maison, avec le releve de Maison de la demo et le bilan de sa fusion (`24-reglages-maison`).
    /// Rend son nom, ou nil si le rendu a echoue.
    static func ecrireReglagesMaison(dans dossier: String, surveillance s: Surveillance) -> String? {
        let passeur = NomsPasseur(demo: NomsDemo.releveMaison)
        return ecrireReglages(Section { ReglagesMaison() }.environment(s).environment(passeur),
                              nom: "24-reglages-maison", dans: dossier)
    }

    /// Une page des Reglages rendue hors ecran par AppKit (`cacheDisplay`, dans une fenetre jamais montree), en sombre, a
    /// la largeur des Reglages, ecrite sous `nom`.png ; rend son nom, ou nil si le rendu a echoue.
    static func ecrireReglages(_ page: some View, nom: String, dans dossier: String) -> String? {
        let vue = Form { page }
            .formStyle(.grouped)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
        return ecrireHote(vue, nom: nom, dans: dossier)
    }

    /// Une vue rendue hors ecran par AppKit (`cacheDisplay`, dans une fenetre jamais montree), en sombre, a la taille que
    /// la vue demande, ecrite sous `nom`.png en 2x ; rend son nom, ou nil si le rendu a echoue.
    static func ecrireHote(_ vue: some View, nom: String, dans dossier: String) -> String? {
        let hote = NSHostingView(rootView: vue)
        hote.appearance = NSAppearance(named: .darkAqua)
        hote.frame = CGRect(origin: .zero, size: hote.fittingSize)
        let fenetre = NSWindow(contentRect: hote.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        fenetre.appearance = NSAppearance(named: .darkAqua)
        fenetre.isReleasedWhenClosed = false
        fenetre.contentView = hote
        hote.layoutSubtreeIfNeeded()
        defer { fenetre.contentView = nil }
        // En 2x, comme les autres images, quel que soit l'ecran.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(hote.bounds.width * 2),
                                         pixelsHigh: Int(hote.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = hote.bounds.size
        hote.cacheDisplay(in: hote.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        ecrire(image, vers: (dossier as NSString).appendingPathComponent(nom + ".png"))
        return nom
    }

    /// Le moteur d'un cas, prepare comme dans la boucle des images : la taille, la scene de la demo (`e`), puis, pour
    /// `deplacer`, celle des pieces choisies, avec sa transition, enfin l'etat du cas, pose sur la scene que porte le
    /// moteur. Un cas `deplacer` sans transition (la scene choisie ne change rien) est une erreur : l'image sortirait
    /// sans appareil en route.
    static func preparer(_ c: Cas, surveillance s: Surveillance,
                         marges: (haut: CGFloat, bas: CGFloat)) -> (m: MoteurPieces, e: EntreeScene) {
        let m = MoteurPieces(places: c.places)
        m.fige = true
        m.reglerGrille(c.grille)
        let e = EntreeScene(surveillance: s, places: m.places)
        m.marges = marges
        m.basGrille = marges.bas
        m.poserTaille(c.taille)
        m.installerMaintenant(e)
        m.poserTaille(c.taille)
        if let choix = c.deplacer {
            m.installerMaintenant(EntreeScene(surveillance: s, places: m.places, choix: choix))
        }
        precondition(c.deplacer == nil || m.transition != nil,
                     "\(c.nom) : la scene des pieces choisies ne change aucune disposition")
        guard let scene = m.scene else { preconditionFailure("\(c.nom) : le moteur n'a pas de scene") }
        c.poser(m, scene)
        return (m, e)
    }

    /// Ecrit les images dans `dossier`, la maison de demo nommee par Maison, sur quatre etages ; rend leurs noms.
    @discardableResult
    static func ecrire(dans dossier: String, surveillance s: Surveillance, sonde: SondeMaillage,
                       nomsPont: NomsPont) -> [String] {
        try? FileManager.default.createDirectory(atPath: dossier, withIntermediateDirectories: true)
        s.noms.maison = NomsDemo.maisonFusionnee
        s.historiqueDeCapture(MaillageDemo.historique)
        s.evenementsDeCapture(evenementsHesitants)
        guard s.aUnReseau else { return [] }
        let palette = Palette(sombre: true)
        // Hauteur d'une vue de la fenetre, rendue pour une capture, a la largeur `largeur` (sinon la sienne).
        func hauteur(_ vue: some View, largeur: CGFloat? = nil) -> CGFloat {
            NSHostingView(rootView: vue.frame(width: largeur).pourCapture(s, sonde, nomsPont)).fittingSize.height
        }
        // Marge du haut : la hauteur du haut de la fenetre, mesuree comme dans la fenetre.
        let haut = hauteur(HautPieces(moteur: MoteurPieces(), troisD: .constant(false)))
        let marges = (FenetrePieces.margeHaut(bas: haut), FenetrePieces.margeBas(pile: nil))
        var noms: [String] = []
        for c in cas {
            let taille = c.taille
            // La vue d'ensemble se cadre au-dessus de la legende ouverte : la hauteur mesuree de la rangee du bas,
            // comme dans la fenetre ; repliee, la marge d'avant. La grille se choisit sur cette zone visible, sans la
            // fiche (polissage C, section 3.3). La mesure se fait sur la scene de la demo, celle du cas sans son
            // deplacement.
            let mesure = EntreeScene(surveillance: s, places: c.places)
            let ouverte = hauteur(LigneDuBas(moteur: MoteurPieces(), entree: mesure, legendeForcee: false))
            let (m, e) = preparer(c, surveillance: s,
                                  marges: (marges.0, c.legendeRepliee ? marges.1 : FenetrePieces.margeBas(pile: ouverte)))
            // La fiche : la legende reste au-dessus d'elle (repliee si la place manque, comme dans la fenetre), et la
            // vue se cadre au-dessus de la pile mesuree.
            var repliee = c.legendeRepliee
            if let id = m.selection {
                let largeur = taille.width - 2 * FenetrePieces.bord
                let fiche = hauteur(FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil),
                                               listeDepliee: c.listeVoisins, changementsDeplies: c.changementsDeplies) {},
                                    largeur: largeur)
                repliee = repliee || FenetrePieces.repliDePlace(hauteur: taille.height, margeHaut: m.marges.haut,
                                                                legende: ouverte, fiche: fiche)
                let pile = hauteur(VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                    LigneDuBas(moteur: MoteurPieces(), entree: e, legendeForcee: repliee)
                    FicheNoeud(id: id, entree: e, instant: s.maintenant, aRenommer: .constant(nil),
                               listeDepliee: c.listeVoisins, changementsDeplies: c.changementsDeplies) {}
                }, largeur: largeur)
                m.marges.bas = FenetrePieces.margeBas(pile: pile)
                m.poserTaille(taille)
            }
            // Deux passages : le premier pose les noms, le second les dessine a leur place.
            var image: CGImage?
            for _ in 0..<2 {
                let rendu = ImageRenderer(content: VueCapture(moteur: m, palette: palette, legendeRepliee: repliee,
                                                              listeVoisins: c.listeVoisins,
                                                              changementsDeplies: c.changementsDeplies)
                    .environment(\.periodeCapture, c.periode)
                    .frame(width: taille.width, height: taille.height)
                    .pourCapture(s, sonde, nomsPont))
                rendu.scale = 2
                image = rendu.cgImage
            }
            guard let image else { continue }
            ecrire(image, vers: (dossier as NSString).appendingPathComponent(c.nom + ".png"))
            noms.append(c.nom)
        }
        noms += ecrireJournal(dans: dossier, surveillance: s, sonde: sonde, nomsPont: nomsPont)
        if let nom = ecrireReglagesPont(dans: dossier, noms: NomsDemo.maison) { noms.append(nom) }
        if let nom = ecrireReglagesMaison(dans: dossier, surveillance: s) { noms.append(nom) }
        return noms
    }

    /// L'image de la fenetre du journal, avec les evenements de la demo et ceux des captures, les changements regroupes
    /// replies puis deplies (`5c-journal-replie`, `5c-journal-deplie`). Les lignes seules, dans une liste : ni barre
    /// d'outils ni recherche, que `cacheDisplay` ne rend pas hors d'une vraie fenetre.
    static func ecrireJournal(dans dossier: String, surveillance s: Surveillance, sonde: SondeMaillage,
                              nomsPont: NomsPont) -> [String] {
        [false, true].compactMap { deplie in
            let lignes = s.lignesJournal
            let vue = VStack(alignment: .leading, spacing: 10) {
                ForEach(lignes) { LigneJournalVue(ligne: $0, deplie: deplie) }
            }
            .padding(16)
            .frame(width: 600, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .pourCapture(s, sonde, nomsPont)
            return ecrireHote(vue, nom: deplie ? "5c-journal-deplie" : "5c-journal-replie", dans: dossier)
        }
    }

    static func ecrire(_ image: CGImage, vers chemin: String) {
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: chemin) as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

/// La vue d'une capture : le fond, la scene, le haut de la fenetre (avec ses trois boutons, et la ligne de niveau
/// sous le fil), la legende (ouverte, ou repliee), puis, dessous, la fiche du noeud choisi ; sans horloge ni geste.
struct VueCapture: View {
    @Environment(Surveillance.self) private var surveillance
    let moteur: MoteurPieces
    let palette: Palette
    var legendeRepliee = false
    var listeVoisins = false
    var changementsDeplies = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(gradient: palette.fond, center: UnitPoint(x: 0.3, y: 0.35), startRadius: 0, endRadius: 900)
            Canvas { ctx, taille in moteur.image(&ctx, taille: taille, echelle: 2, palette: palette) }
            HautPieces(moteur: moteur, troisD: .constant(moteur.troisD))
            FeuxDeCapture()
            VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                Spacer()
                LigneDuBas(moteur: moteur, entree: moteur.entree, legendeForcee: legendeRepliee)
                if let id = moteur.selection {
                    FicheNoeud(id: id, entree: moteur.entree, instant: surveillance.maintenant,
                               aRenommer: .constant(nil), listeDepliee: listeVoisins,
                               changementsDeplies: changementsDeplies) {}
                }
            }
            .padding(FenetrePieces.bord)
        }
        .coordinateSpace(.named(VuePieces.espace))
    }
}

extension View {
    /// Ce qu'une vue de la fenetre lit dans une capture : la surveillance, la sonde et les noms de la
    /// demo, l'apparence sombre, et le rendu de capture.
    func pourCapture(_ s: Surveillance, _ sonde: SondeMaillage, _ noms: NomsPont) -> some View {
        environment(\.capturePieces, true)
            .environment(\.colorScheme, .dark)
            .environment(s)
            .environment(sonde)
            .environment(noms)
    }
}
