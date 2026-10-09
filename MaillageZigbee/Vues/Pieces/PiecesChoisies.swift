import Foundation
import MaillageCoeur
import SwiftUI

/// Pieces choisies pour les noeuds que le pont ne place pas (« Placer dans une piece… », dans leur fiche), sous leur
/// adresse longue ; par maison, dans `pieces-routeurs.json`, a cote des places des pieces ; en memoire seulement en
/// demo et sous les tests. Le calcul est dans le coeur (`PiecesRouteurs`).
@MainActor
@Observable
final class PiecesChoisies {
    /// « Placer dans une piece… » d'un noeud : son adresse longue (16 hexa majuscules), et les pieces de la maison, par
    /// nom.
    struct Placement: Equatable {
        var cle: String
        var pieces: [String]
    }

    private(set) var choix: PiecesRouteurs
    @ObservationIgnored private let fichier: URL?

    /// `fichier` : `pieces-routeurs.json` (`fichier(demo:sousTests:)`) ; nil : ni lu ni ecrit.
    init(fichier: URL?) {
        self.fichier = fichier
        choix = fichier.map(PiecesRouteurs.lire) ?? PiecesRouteurs()
    }

    /// A cote des places des pieces ; ni en demo ni sous les tests.
    static func fichier(demo: Bool, sousTests: Bool) -> URL? {
        demo || sousTests ? nil : Surveillance.dossierParDefaut.appendingPathComponent("pieces-routeurs.json")
    }

    /// Piece choisie pour un noeud (son adresse longue) ; nil : « Sans piece ».
    func pieceChoisie(_ cle: String, domicile: String) -> String? {
        choix.choix(appareil: cle, domicile: domicile)
    }

    /// Place un noeud (son adresse longue) dans une piece de la maison ; nil : « Sans piece » (son choix s'efface).
    func choisir(_ piece: String?, _ cle: String, domicile: String) {
        choix.choisir(piece, appareil: cle, domicile: domicile)
        guard let fichier else { return }
        do {
            try choix.ecrire(dans: fichier)
        } catch {
            MoteurPieces.journal.error("pieces choisies non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension PiecesChoisies {
    /// « Placer dans une piece… » pour un noeud, dans une maison qui a des pieces : un noeud sans piece sur le pont dont
    /// l'adresse longue est connue. Nil pour un noeud que le pont place. `entree` : la scene du meme rendu, dont le graphe
    /// et les appareils servent tels quels.
    static func placement(_ id: String, dans surveillance: Surveillance, entree: EntreeScene) -> Placement? {
        let pieces = PiecesRouteurs.pieces(de: surveillance.noms.maison)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !pieces.isEmpty else { return nil }
        if let p = entree.appareils[id]?.piece, !p.isEmpty { return nil }
        guard let n = entree.graphe.noeud(id), let cle = PiecesRouteurs.cle(n) else { return nil }
        return Placement(cle: cle, pieces: pieces)
    }
}

/// « Placer dans une piece… », dans la fiche d'un noeud que le pont ne place pas : « Sans piece », puis les pieces de
/// la maison ; le choix en cours est coche.
struct MenuPlacer: View {
    /// Un article du menu : son texte, et la piece qu'il choisit (nil : le premier article).
    struct Article: Hashable {
        var texte: String
        var piece: String?
    }

    let placement: PiecesChoisies.Placement
    let domicile: String
    let choisies: PiecesChoisies

    /// Les articles, dans l'ordre : « Sans piece » (le choix efface), puis les pieces.
    static func articles(_ p: PiecesChoisies.Placement) -> [Article] {
        [Article(texte: String(localized: "Sans pièce"), piece: nil)] + p.pieces.map { Article(texte: $0, piece: $0) }
    }

    /// Le choix en cours, que le menu coche : nil (le premier article) quand la piece choisie n'est plus
    /// une piece du menu. Un choix perime ne compte plus, la scene l'ignore ; sans cela, le menu ne
    /// cocherait aucun article. Il reste dans le fichier.
    var selection: Binding<String?> {
        Binding(
            get: {
                guard let c = choisies.pieceChoisie(placement.cle, domicile: domicile),
                      placement.pieces.contains(c) else { return nil }
                return c
            },
            set: { choisies.choisir($0, placement.cle, domicile: domicile) })
    }

    var body: some View {
        Menu("Placer dans une pièce…") {
            Picker("Placer dans une pièce…", selection: selection) {
                ForEach(Self.articles(placement), id: \.piece) { Text(verbatim: $0.texte).tag($0.piece) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
    }
}
