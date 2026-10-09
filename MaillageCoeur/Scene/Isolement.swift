import Foundation

/// Ce que montre la vue par pieces (polissage C, section 5) : la maison, un etage isole (sa cle), ou une piece isolee
/// (sa cle), avec sa provenance : l'etage isole d'ou on l'a ouverte, nil depuis la maison. Ses regles sont ici, sorties
/// du moteur (polissage D, section 5) : les transitions (isoler, aller a un etage, remonter), le recalage quand une
/// scene arrive, et la regle des clics sur le nom ou le disque d'un etage, en un seul endroit pour le clic et pour la
/// main du pointeur. Le moteur garde les vols, les fondus et la camera.
public enum Isolement: Hashable, Sendable {
    case maison
    case etage(String)
    case piece(String, provenance: String?)

    /// Ce que fait une remontee (Echap, clic a cote) : aller a un etage (sa cle), revenir a la maison, ou rien.
    public enum Remontee: Hashable, Sendable {
        case etage(String)
        case maison
        case rien
    }

    /// Ce que fait un clic sur le nom ou le disque d'un etage : l'isoler, revenir a la maison, ou rien.
    public enum ClicEtage: Hashable, Sendable {
        case isoler
        case maison
        case rien
    }

    /// Isoler la piece `piece`, de l'etage `etage` (section 5.4) : depuis la maison, sans provenance ; depuis un
    /// etage isole, cet etage ; d'une piece a une autre, la provenance reste, sauf vers une piece d'un autre etage :
    /// la maison.
    public func isoler(piece: String, etage: String) -> Isolement {
        let provenance: String? = switch self {
        case .maison: nil
        case .etage(let k): k
        case .piece(_, let p): p == etage ? p : nil
        }
        return .piece(piece, provenance: provenance)
    }

    /// Echap et le clic a cote remontent d'ou l'on vient (section 5.4) : une piece ouverte depuis un etage isole, a
    /// l'etage de la piece (`etageDeLaPiece`, celui du fil), dans une maison de plusieurs plateaux ; une autre piece,
    /// ou un etage, a la maison. A la maison, Echap (`clavier`) ramene une vue zoomee ou deplacee a la vue d'ensemble ;
    /// le clic a cote ne fait rien.
    public func remonter(etageDeLaPiece: String?, plusieursPlateaux: Bool, clavier: Bool) -> Remontee {
        switch self {
        case .piece(_, let provenance):
            if provenance != nil, plusieursPlateaux, let e = etageDeLaPiece { return .etage(e) }
            return .maison
        case .etage:
            return .maison
        case .maison:
            return clavier ? .maison : .rien
        }
    }

    /// Un clic sur le nom (`disque` faux) ou le disque de l'etage `cle` (section 5.4) : il l'isole ; son propre disque,
    /// l'etage isole, entre les pieces, ne fait rien. Dans une maison d'un seul plateau, seulement depuis une piece
    /// isolee (`pieceIsolee`), pour remonter a la maison. La main du pointeur suit la meme regle (`cliquable`).
    public func clicEtage(_ cle: String, disque: Bool, plusieursPlateaux: Bool, pieceIsolee: Bool) -> ClicEtage {
        guard plusieursPlateaux else { return pieceIsolee ? .maison : .rien }
        if disque, self == .etage(cle) { return .rien }
        return .isoler
    }

    /// Le clic sur ce nom ou ce disque fait quelque chose : la main du pointeur s'y pose.
    public func cliquable(_ cle: String, disque: Bool, plusieursPlateaux: Bool, pieceIsolee: Bool) -> Bool {
        clicEtage(cle, disque: disque, plusieursPlateaux: plusieursPlateaux, pieceIsolee: pieceIsolee) != .rien
    }

    /// Sur une nouvelle scene, de pieces `pieces` et de plateaux `etages` (leurs cles) : une piece isolee ou un etage
    /// isole qui disparait rend la maison ; sinon, rien ne change.
    public func recaler(pieces: Set<String>, etages: Set<String>) -> Isolement {
        switch self {
        case .piece(let p, _) where !pieces.contains(p): .maison
        case .etage(let k) where !etages.contains(k): .maison
        default: self
        }
    }
}
