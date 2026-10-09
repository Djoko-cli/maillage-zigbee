import Foundation

/// Etat d'un appareil tel que la vue le montre.
public enum EtatAffiche: String, Hashable, Sendable {
    /// `connected` selon le pont ; sans cet etat, sur le maillage.
    case joignable
    /// Le pont le dit injoignable (`connectivity_issue`, `disconnected`, `unidirectional_incoming`).
    case injoignable
    /// Connu du pont, absent du maillage (sans etat de connexion du pont).
    case disparu
    case inconnu
}

/// Appareil a dessiner : nom deja choisi ; `id` : son adresse longue (IEEE), celle du noeud du graphe.
public struct AppareilAffiche: Hashable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var piece: String?
    public var etat: EtatAffiche
    public var endormi: Bool
    /// Batterie selon le pont, pour un appareil qui en a une.
    public var batterie: BatterieMaison?

    public init(id: String, nom: String, piece: String? = nil, etat: EtatAffiche, endormi: Bool = false,
                batterie: BatterieMaison? = nil) {
        self.id = id
        self.nom = nom
        self.piece = piece
        self.etat = etat
        self.endormi = endormi
        self.batterie = batterie
    }
}

/// Noeuds et liens du reseau Zigbee, tels que la vue les montre, sans geometrie (spec de la vue par pieces,
/// section 2.3 ; spec de l'app, section 4). Un noeud par adresse longue : le coordinateur (le pont) au centre, les
/// routeurs, les appareils finaux ; un noeud du maillage que le pont ne connait pas est « inconnu » (la sonde exceptee) ;
/// un appareil du pont absent du maillage est dessine sans lien. Les liens : radio entre routeurs (la moins bonne des
/// deux qualites mesurees), le chemin de chaque routeur vers le pont (vers son prochain saut, de la qualite du lien
/// radio entre les deux), et de chaque appareil final vers son parent. La vue choisit ce qu'elle en montre
/// (`SceneProjetee.trace`).
///
/// Ordre des noeuds : le coordinateur, les routeurs, les appareils finaux, les noeuds de type inconnu (chacun par
/// adresse longue), puis les appareils du pont absents du maillage (par id).
public struct GrapheReseau: Hashable, Sendable {
    public enum Genre: String, Hashable, Sendable {
        /// Le coordinateur : le pont.
        case centre
        /// Un routeur.
        case routeur
        /// Un appareil final, ou un noeud de role inconnu.
        case appareil
    }

    /// La partition de tous les noeuds : Zigbee n'en a pas, la scene garde le champ.
    public static let partitionUnique = "zigbee"

    public struct Noeud: Hashable, Sendable, Identifiable {
        /// Son adresse longue.
        public var id: String
        public var genre: Genre
        /// Toujours `GrapheReseau.partitionUnique`.
        public var partition: String
        /// Route : le coordinateur ou un routeur.
        public var routeur: Bool
        /// Toujours faux en Zigbee (il n'y a pas de routeur de bordure) ; la scene garde le champ.
        public var bordure: Bool
        /// Vu par la sonde, inconnu du pont.
        public var inconnu: Bool
        /// Son adresse longue (16 hexa majuscules) : la cle de son choix de piece.
        public var extMac: String?

        public init(id: String, genre: Genre, partition: String = GrapheReseau.partitionUnique, routeur: Bool,
                    bordure: Bool = false, inconnu: Bool, extMac: String? = nil) {
            self.id = id
            self.genre = genre
            self.partition = partition
            self.routeur = routeur
            self.bordure = bordure
            self.inconnu = inconnu
            self.extMac = extMac
        }
    }

    public struct Lien: Hashable, Sendable {
        public enum Genre: String, Hashable, Sendable {
            /// Rattachement suppose, pas un lien radio : Zigbee n'en trace pas, la scene garde le cas.
            case rattachement
            /// Lien radio entre deux routeurs, vu par la sonde.
            case radio
            /// De l'appareil final vers son parent, vu par la sonde (`suppose` : le parent d'avant).
            case parent
            /// D'un routeur vers son prochain saut vers le pont (sa route « plusieurs vers un »).
            case chemin
        }

        public var de: String
        public var vers: String
        public var genre: Genre
        /// De 0 a 3 (`QualiteLien`) ; nil : inconnue.
        public var qualite: Int?
        /// Chemin suppose, faute de route active (`CheminPont.suppose`) ; ou lien vers le parent d'avant d'un appareil
        /// final absent des dernieres tables (`LienParent.dAvant`). Le trace est en pointilles.
        public var suppose: Bool

        public init(de: String, vers: String, genre: Genre = .rattachement, qualite: Int? = nil, suppose: Bool = false) {
            self.de = de
            self.vers = vers
            self.genre = genre
            self.qualite = qualite
            self.suppose = suppose
        }
    }

    public private(set) var noeuds: [Noeud] = []
    public private(set) var liens: [Lien] = []

    /// Des noeuds et des liens deja faits (tests, scenes inventees). Un lien dont un bout manque est ignore.
    public init(noeuds: [Noeud], liens: [Lien] = []) {
        self.noeuds = noeuds
        let ids = Set(noeuds.map(\.id))
        self.liens = liens.filter { ids.contains($0.de) && ids.contains($0.vers) }
    }

    /// Le graphe d'un maillage (nil : pas de maillage, ou perime) et des appareils du pont (`id` : adresse longue).
    public init(maillage m: MaillageZigbee?, appareils: [AppareilAffiche]) {
        let connus = Set(appareils.map { $0.id.uppercased() })
        func rang(_ t: TypeNoeud) -> Int {
            switch t {
            case .coordinateur: 0
            case .routeur: 1
            case .final: 2
            case .inconnu: 3
            }
        }
        var presents = Set<String>()
        for n in (m?.noeuds ?? []).sorted(by: { (rang($0.type), $0.ieee) < (rang($1.type), $1.ieee) })
        where presents.insert(n.ieee).inserted {
            let genre: Genre = switch n.type {
            case .coordinateur: .centre
            case .routeur: .routeur
            case .final, .inconnu: .appareil
            }
            // Une cle provisoire (sans adresse longue) n'est pas une adresse longue : ni choix de piece, ni menu.
            noeuds.append(Noeud(id: n.ieee, genre: genre, routeur: n.route,
                                inconnu: !connus.contains(n.ieee.uppercased()) && n.ieee != m?.sonde,
                                extMac: n.ieeeConnue ? n.ieee : nil))
        }
        for a in appareils.sorted(by: { $0.id < $1.id }) where presents.insert(a.id).inserted {
            noeuds.append(Noeud(id: a.id, genre: .appareil, routeur: false, inconnu: false,
                                extMac: a.id.uppercased()))
        }
        guard let m else { return }
        for l in MaillageZigbee.reunir(m.liens) where presents.contains(l.a) && presents.contains(l.b) {
            liens.append(Lien(de: l.a, vers: l.b, genre: .radio, qualite: l.qualite))
        }
        for p in m.parents.sorted(by: { $0.enfant < $1.enfant })
        where presents.contains(p.enfant) && presents.contains(p.parent) {
            liens.append(Lien(de: p.enfant, vers: p.parent, genre: .parent, qualite: p.qualite, suppose: p.dAvant))
        }
        for c in m.chemins where presents.contains(c.routeur) && presents.contains(c.prochain) {
            liens.append(Lien(de: c.routeur, vers: c.prochain, genre: .chemin,
                              qualite: m.lien(entre: c.routeur, et: c.prochain)?.qualite, suppose: c.suppose))
        }
    }

    /// Le chemin d'un routeur vers le pont : son prochain saut ; nil sans chemin.
    public func chemin(de id: String) -> Lien? {
        liens.first { $0.genre == .chemin && $0.de == id }
    }

    public func noeud(_ id: String) -> Noeud? { noeuds.first { $0.id == id } }

    /// Parent d'un noeud vu par la sonde (lien enfant-parent) ; nil sinon.
    public func parent(de id: String) -> String? {
        liens.first { $0.genre == .parent && $0.de == id }?.vers
    }
}
