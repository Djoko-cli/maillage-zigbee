import Foundation
import MaillageCoeur

/// Textes de la vue par pieces : le libelle de chaque noeud (nom, couronne, lune, alerte) et la
/// pastille de sa batterie faible ; les noms des pieces et des etages ; le compte d'une piece ; le
/// texte d'un repere « ailleurs ».
enum LibellesNoeuds {
    /// La couronne du coordinateur et la lune d'un endormi, a la suite du nom ; la legende les reprend.
    static let couronne = CartesPieces.couronne
    static let lune = CartesPieces.lune

    /// Libelle d'un noeud : son texte, et la pastille de sa batterie faible ; son nom, sans ses badges (polissage D,
    /// section 2) : la scene et sa carte ne voient que lui.
    struct Libelle: Hashable {
        var texte: String
        var pastille: String?
        var nom: String

        /// Le nom est toujours donne : la scene ne voit que lui, et un oubli lui montrerait les badges.
        init(texte: String, pastille: String? = nil, nom: String) {
            self.texte = texte
            self.pastille = pastille
            self.nom = nom
        }

        /// Un texte pur, sans badge : mesures, reperes, noeud sans libelle ; son nom est le texte.
        init(texte: String) {
            self.init(texte: texte, nom: texte)
        }
    }

    /// Texte de la pastille d'une batterie faible : son niveau, sinon « faible » ; nil si elle ne
    /// l'est pas.
    static func pastilleBatterie(_ b: BatterieMaison?) -> String? {
        guard let b, b.faible else { return nil }
        return b.niveau.map { String(localized: "\($0)\u{202F}%") } ?? String(localized: "faible")
    }

    /// Noeuds couronnes : le coordinateur (le pont).
    static func chefs(_ graphe: GrapheReseau) -> Set<String> {
        Set(graphe.noeuds.filter { $0.genre == .centre }.map(\.id))
    }

    /// Un noeud endormi, qui porte ☾ : un appareil dont le recepteur dort au repos, sauf s'il route. Un routeur n'est
    /// jamais endormi ; la legende suit cette regle.
    static func endormi(_ a: AppareilAffiche?, routeur: Bool) -> Bool {
        a?.endormi == true && !routeur
    }

    /// Libelle de chaque noeud : son nom (`nom`, par adresse longue ; coupe a 40 caracteres), la couronne du
    /// coordinateur, ☾ endormi (pas pour un noeud qui route), ⚠︎ injoignable ou disparu ; la pastille d'une batterie
    /// faible.
    static func libelles(graphe: GrapheReseau, appareils: [String: AppareilAffiche], nom: (String) -> String,
                         chefs: Set<String>) -> [String: Libelle] {
        var libelles: [String: Libelle] = [:]
        for n in graphe.noeuds {
            let a = appareils[n.id]
            let coupe = CartesPieces.couper(a?.nom ?? nom(n.id))
            let texte = CartesPieces.texte(coupe, chef: chefs.contains(n.id), endormi: endormi(a, routeur: n.routeur),
                                           alerte: a?.etat == .injoignable || a?.etat == .disparu)
            libelles[n.id] = Libelle(texte: texte, pastille: pastilleBatterie(a?.batterie), nom: coupe)
        }
        return libelles
    }

    /// Piece de chaque noeud : celle que le pont donne a son appareil ; pour un noeud que le pont ne place pas, la piece
    /// choisie pour son adresse longue (`PiecesRouteurs`).
    static func pieces(appareils: [AppareilAffiche], maison: NomsMaison?, choix: PiecesRouteurs = PiecesRouteurs(),
                       graphe: GrapheReseau) -> [String: String] {
        var pieces: [String: String] = [:]
        for a in appareils {
            if let p = a.piece, !p.isEmpty { pieces[a.id] = p }
        }
        return choix.piecesNoeuds(graphe, deMaison: pieces, parmi: PiecesRouteurs.pieces(de: maison),
                                  domicile: maison?.domicile ?? "")
    }

    static func nom(_ e: ScenePieces.NomEtage) -> String {
        switch e {
        case .zone(let n): n
        case .autresPieces: String(localized: "Autres pièces")
        case .maison: String(localized: "Maison")
        }
    }

    static func nom(_ p: ScenePieces.NomPiece, libelles: [String: Libelle]) -> String {
        switch p {
        case .maison(let n): n
        case .routeur(let id): libelles[id]?.texte ?? id
        case .sansPiece: String(localized: "Sans pièce")
        }
    }

    /// « 1 appareil », « 6 appareils ».
    static func compte(_ n: Int) -> String {
        n == 1 ? String(localized: "1 appareil") : String(localized: "\(n) appareils")
    }

    /// Repere « ailleurs » (polissage C, section 5.2) : « ↗ Plafonnier salon · Salon » pour un parent du meme
    /// plateau, « ↗ … · Terrasse, Jardin » pour un parent au meme niveau, dans une autre zone ; « ↓ … · Salon,
    /// Rez-de-chaussee » ou ↑ pour un parent a un autre niveau, avec le nom de son plateau (sans la couronne du
    /// coordinateur).
    static func ailleurs(_ a: Ailleurs, scene: ScenePieces, libelles: [String: Libelle]) -> String {
        let fleche = switch a.sens {
        case .memeNiveau: "↗"
        case .dessous: "↓"
        case .dessus: "↑"
        }
        let parent = (libelles[a.parent]?.texte ?? a.parent).replacingOccurrences(of: " " + couronne, with: "")
        let piece = nom(scene.pieces[a.piece].nom, libelles: libelles)
        let ici = scene.noeud(a.enfant).map { scene.pieces[$0.piece].etage }
        guard a.etage != ici else { return "\(fleche) \(parent) · \(piece)" }
        return "\(fleche) \(parent) · \(piece), \(nom(scene.etages[a.etage].nom))"
    }
}
