import MaillageCoeur
import SwiftUI

/// Ce que la vue par pieces montre du reseau, tire de la surveillance (spec de la vue par pieces, section 2) : la
/// scene, le libelle et l'apparence de chaque noeud, et la maison de ses places gardees ; avec ce dont la scene est
/// faite, construit une fois avec elle a chaque rendu (le graphe, le maillage, le coordinateur couronne, les appareils),
/// que la fiche et « Placer dans une piece… » lisent ici, sans rien reconstruire : ils voient les memes noeuds, les
/// memes cles et la meme couronne que la scene.
struct EntreeScene: Equatable {
    var scene: ScenePieces
    var libelles: [String: LibellesNoeuds.Libelle]
    var apparences: [String: DessinNoeud.Apparence]
    /// Domicile du pont ("" sans nom) : la cle de ses places gardees.
    var domicile: String
    /// Noeuds et liens du reseau.
    var graphe: GrapheReseau
    /// Maillage de la sonde ; nil sans sonde, ou s'il est perime.
    var maillage: MaillageZigbee?
    /// Noeuds couronnes : le coordinateur ; la couronne le suit partout ou elle parait.
    var chefs: Set<String>
    /// Appareils affiches, par id (adresse longue).
    var appareils: [String: AppareilAffiche]

    /// `places` : les places gardees, dont l'ordre des etages de la maison et ses choix de niveau ; `choix` : les pieces
    /// choisies pour les noeuds que le pont ne place pas (sous leur adresse longue).
    @MainActor
    init(surveillance: Surveillance, places: PlacesGardees, choix: PiecesRouteurs = PiecesRouteurs()) {
        let affiches = surveillance.appareilsAffiches
        let maillage = surveillance.maillageAffiche
        let graphe = GrapheReseau(maillage: maillage, appareils: affiches)
        let parId = Dictionary(affiches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let chefs = LibellesNoeuds.chefs(graphe)
        let libelles = LibellesNoeuds.libelles(graphe: graphe, appareils: parId, nom: surveillance.nom, chefs: chefs)
        let maison = surveillance.noms.maison
        let domicile = maison?.domicile ?? ""
        let pieces = LibellesNoeuds.pieces(appareils: affiches, maison: maison, choix: choix, graphe: graphe)
        // La scene voit les noms sans leurs badges : un badge qui change ne la change pas (polissage D, section 2).
        let scene = ScenePieces(graphe: graphe, libelles: libelles.mapValues(\.nom), piecesNoeuds: pieces,
                                zones: maison?.zones, chefs: chefs,
                                piecesMaison: maison?.accessoires.contains { $0.piece?.isEmpty == false } == true,
                                ordreEtages: places.maison(domicile).ordreEtages, aCote: places.maison(domicile).aCote,
                                piles: Set(parId.filter { $0.value.batterie != nil }.keys))
        self.scene = scene
        self.libelles = libelles
        self.domicile = domicile
        self.graphe = graphe
        self.maillage = maillage
        self.chefs = chefs
        appareils = parId
        apparences = Dictionary(scene.noeuds.map { n in
            (n.id, DessinNoeud.apparence(n, etat: parId[n.id]?.etat))
        }, uniquingKeysWith: { a, _ in a })
    }

    /// Egalite de ce que la vue dessine : la scene, les libelles, les apparences et le domicile. Ce dont
    /// la scene est faite n'y entre pas : un maillage recu plus tard, qui ne change rien a la scene, ne
    /// la fait pas reposer par le moteur (`MoteurPieces.recevoir`).
    static func == (a: EntreeScene, b: EntreeScene) -> Bool {
        a.scene == b.scene && a.libelles == b.libelles && a.apparences == b.apparences && a.domicile == b.domicile
    }

    /// Mode focus du graphe (etape 5, section 1) : ce qui reste net a la selection du noeud `id`, calcule par la fonction
    /// propre a Zigbee (`FocusZigbee`) sur le graphe de cette scene ; `voisins` : ses voisins entendus aussi. Le moteur,
    /// generique, ne fait que l'appeler (`MoteurPieces.majMiseEnAvant`).
    func miseEnAvant(de id: String, voisins: Bool) -> MiseEnAvant? {
        FocusZigbee.miseEnAvant(de: id, graphe: graphe, voisins: voisins)
    }

    /// Ce qui oblige a recalculer la disposition : celle de la scene, sans les badges des noms (polissage D, section 2).
    typealias CleDisposition = ScenePieces.CleDisposition

    var cleDisposition: CleDisposition { scene.cleDisposition }
}
