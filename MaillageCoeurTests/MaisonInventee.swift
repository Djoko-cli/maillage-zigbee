import Foundation
@testable import MaillageCoeur

/// Maison inventee pour les tests de la scene : `pieces` pieces reparties sur deux etages (ou sur un seul
/// plateau, `unSeulPlateau`), `routeurs` routeurs relies en chaine (le premier est le coordinateur, couronne), le
/// routeur k dans la piece k ; `appareils` appareils finaux, l'appareil j dans la piece j modulo `pieces`, enfant du
/// routeur de numero (sa piece) modulo `routeurs`. Noms : 7 px par caractere, plus 10 px de marges.
enum MaisonInventee {
    static func routeur(_ k: Int) -> String { String(format: "Routeur %02d", k) }
    static func appareil(_ j: Int) -> String { String(format: "E2%014X", j) }

    static func graphe(pieces: Int, routeurs: Int, appareils: Int) -> GrapheReseau {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var noeuds = (0..<routeurs).map { k in
            NoeudZigbee(ieee: routeur(k), court: UInt16(k), type: k == 0 ? .coordinateur : .routeur)
        }
        noeuds += (0..<appareils).map { NoeudZigbee(ieee: appareil($0), court: UInt16(0x1000 + $0), type: .final) }
        // Chaque lien : qualite 3 d'un cote, 2 de l'autre (la moins bonne, 2, est affichee).
        let liens = (1..<max(routeurs, 1)).map { k in
            LienRadio(mesurePar: routeur(k - 1), de: routeur(k), lqi: 200, date: date)
                .fusionner(LienRadio(mesurePar: routeur(k), de: routeur(k - 1), lqi: 120, date: date))
        }
        let parents = (0..<appareils).map { j in
            LienParent(enfant: appareil(j), parent: routeur((j % pieces) % routeurs), lqi: 120, date: date)
        }
        let m = MaillageZigbee(date: date, noeuds: noeuds, liens: liens, parents: parents)
        let apps = (0..<routeurs).map { AppareilAffiche(id: routeur($0), nom: routeur($0), etat: .joignable) }
            + (0..<appareils).map { AppareilAffiche(id: appareil($0), nom: appareil($0), etat: .joignable) }
        return GrapheReseau(maillage: m, appareils: apps)
    }

    /// La scene et ses cartes.
    static func scene(pieces: Int, appareils: Int, routeurs: Int,
                      unSeulPlateau: Bool = false) -> (scene: ScenePieces, cartes: [CartesPieces.Carte]) {
        let g = graphe(pieces: pieces, routeurs: routeurs, appareils: appareils)
        func nomPiece(_ p: Int) -> String { String(format: "Pièce %02d", p) }
        var piecesNoeuds: [String: String] = [:]
        var libelles: [String: String] = [:]
        for k in 0..<routeurs {
            piecesNoeuds[routeur(k)] = nomPiece(k % pieces)
            libelles[routeur(k)] = routeur(k)
        }
        for j in 0..<appareils {
            piecesNoeuds[appareil(j)] = nomPiece(j % pieces)
            libelles[appareil(j)] = "Appareil \(j)"
        }
        let bas = (0..<pieces / 2).map(nomPiece)
        let haut = (pieces / 2..<pieces).map(nomPiece)
        let s = ScenePieces(graphe: g, libelles: libelles, piecesNoeuds: piecesNoeuds,
                            zones: unSeulPlateau ? nil : [ZoneMaison(nom: "Bas", pieces: bas), ZoneMaison(nom: "Haut", pieces: haut)],
                            chefs: [routeur(0)], piecesMaison: true)
        let largeurs = libelles.mapValues { Double($0.count) * 7 + 10 }
        return (s, CartesPieces.cartes(s, largeurs: largeurs))
    }
}
