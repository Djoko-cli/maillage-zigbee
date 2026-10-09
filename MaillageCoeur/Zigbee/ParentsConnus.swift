import Foundation

/// Le dernier parent connu de chaque appareil final, avec sa date (demande du banc du 08/10) : un appareil final
/// endormi (un bouton) manque parfois a la table de son parent d'une tournee, alors que le pont le dit connecte ; le
/// graphe perdait son parent et la fiche son role. Tant que son dernier parent connu date de moins de 24 h
/// (`duree`), `completer` le remet dans le maillage, comme un parent « d'avant » (`LienParent.dAvant`) : le noeud
/// reste un appareil final (son `ecoute` d'alors), et son lien est trace en pointilles. Au-dela, il n'a plus de parent.
///
/// Gardee par l'app (`Surveillance`), de tournee en tournee ; retrouvee au lancement dans l'historique (`retenir(_:)`
/// d'un releve : la date du releve, le role et le parent seuls).
public struct ParentsConnus: Hashable, Sendable {
    /// Duree pendant laquelle un parent connu tient lieu de parent : 24 h.
    public static let duree: TimeInterval = 24 * 3600

    /// Ce qu'on sait d'un appareil final : son parent, a quelle date il l'avait, et ce que sa table disait de lui.
    struct Connu: Hashable, Sendable {
        var parent: String
        var lqi: Int?
        var date: Date
        var court: UInt16?
        var ecoute: Bool?
    }

    private var parEnfant: [String: Connu] = [:]

    public init() {}

    /// Les appareils finaux dont un parent est retenu.
    public var enfants: Set<String> { Set(parEnfant.keys) }

    /// Le dernier parent retenu d'un appareil final, avec sa date ; nil sans parent retenu.
    public func parent(de enfant: String) -> LienParent? {
        parEnfant[enfant].map { LienParent(enfant: enfant, parent: $0.parent, lqi: $0.lqi, date: $0.date) }
    }

    /// Retient les parents lus dans le maillage (pas ceux d'avant, ni celui de la sonde, ni une cle provisoire), a la
    /// date de leur table ; oublie ceux de plus de 24 h. Un parent plus recent d'un meme appareil l'emporte.
    public mutating func retenir(_ m: MaillageZigbee) {
        for p in m.parents where !p.dAvant && p.enfant != m.sonde && Self.cles(p) {
            let date = p.date ?? m.date
            if let avant = parEnfant[p.enfant], avant.date > date { continue }
            let noeud = m.noeud(p.enfant)
            parEnfant[p.enfant] = Connu(parent: p.parent, lqi: p.lqi, date: date, court: noeud?.court,
                                        ecoute: noeud?.ecoute)
        }
        oublier(avant: m.date.addingTimeInterval(-Self.duree))
    }

    /// Retient les parents d'un releve de l'historique, a la date du releve (il ne garde ni les dates des tables, ni
    /// l'adresse courte, ni `ecoute`) ; les releves se donnent du plus ancien au plus recent. Un parent plus recent, ou
    /// du meme jour que celui retenu, l'emporte ; le meme parent garde ce qu'on sait de son appareil.
    public mutating func retenir(_ r: ReleveMaillage) {
        for p in r.parents where p.enfant != r.sonde && Self.cles(p) {
            let ancien = parEnfant[p.enfant]
            if let ancien, ancien.date > r.date { continue }
            let memes = ancien?.parent == p.parent
            parEnfant[p.enfant] = Connu(parent: p.parent, lqi: p.lqi, date: r.date, court: memes ? ancien?.court : nil,
                                        ecoute: memes ? ancien?.ecoute : nil)
        }
        oublier(avant: r.date.addingTimeInterval(-Self.duree))
    }

    /// Le maillage, avec pour chaque appareil final qui n'a pas de parent dans ses tables (et n'est ni la sonde ni un
    /// routeur) son dernier parent connu, s'il date de moins de 24 h a la date du maillage et qu'il est encore un
    /// routeur (ou le pont) du maillage : un lien `dAvant`, et le noeud (appareil final, `ecoute` d'alors) s'il y
    /// manque. Sans rien a ajouter, le maillage rendu est le meme.
    public func completer(_ m: MaillageZigbee) -> MaillageZigbee {
        let presents = Set(m.parents.map(\.enfant))
        var r = m
        for (enfant, c) in parEnfant.sorted(by: { $0.key < $1.key }) where !presents.contains(enfant) && enfant != m.sonde {
            guard m.date.timeIntervalSince(c.date) <= Self.duree, m.noeud(c.parent)?.route == true else { continue }
            let noeud = m.noeud(enfant)
            guard noeud == nil || noeud?.type == .final || noeud?.type == .inconnu else { continue }
            r.parents.append(LienParent(enfant: enfant, parent: c.parent, lqi: c.lqi, date: c.date, dAvant: true))
            if let i = r.noeuds.firstIndex(where: { $0.ieee == enfant }) {
                r.noeuds[i].type = .final
                if r.noeuds[i].ecoute == nil { r.noeuds[i].ecoute = c.ecoute }
            } else {
                r.noeuds.append(NoeudZigbee(ieee: enfant, court: c.court, type: .final, ecoute: c.ecoute))
            }
        }
        if r.parents.count != m.parents.count {
            r.parents.sort { $0.enfant < $1.enfant }
            r.noeuds.sort { $0.ieee < $1.ieee }
        }
        return r
    }

    /// Les deux bouts sont des adresses longues : une cle provisoire n'est pas gardee.
    private static func cles(_ p: LienParent) -> Bool {
        NoeudZigbee.cleConnue(p.enfant) && NoeudZigbee.cleConnue(p.parent)
    }

    private mutating func oublier(avant limite: Date) {
        parEnfant = parEnfant.filter { $0.value.date >= limite }
    }
}
