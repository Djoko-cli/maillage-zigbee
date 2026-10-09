import Foundation

/// La maison du mode demo : un faux reseau Hue, entierement invente (noms, pieces, adresses longues en
/// `A0000000000000xx`). Le pont, douze lampes et prises qui routent, sept appareils finaux, la sonde, et un routeur
/// que le pont ne connait pas. Le pont Hue n'a pas d'etages : ses noms seuls (`maison`) n'ont qu'un plateau. Ses pieces
/// sont celles des maquettes de la vue par pieces ; `zones` les range sur quatre etages, pour les essais de la vue
/// (`maisonEtagee`). Le releve de Maison de la demo (`releveMaison`) a ces etages : l'app de demo montre la fusion
/// (`maisonFusionnee`).
public enum NomsDemo {
    public static let domicile = "Maison (démo)"

    /// Adresses longues de la demo.
    public enum Ieee {
        public static let pont = "A000000000000001"
        public static let plafonnierSalon = "A000000000000010"
        public static let lampadaireSalon = "A000000000000011"
        public static let suspensionCuisine = "A000000000000012"
        public static let rubanCuisine = "A000000000000013"
        public static let ampouleEntree = "A000000000000014"
        public static let lampeBureau = "A000000000000015"
        public static let lampeChambre = "A000000000000016"
        public static let lampeChambreAmis = "A000000000000017"
        /// Connue du pont, absente du maillage : disparue.
        public static let priseSalon = "A000000000000018"
        public static let lampeSalleDeBain = "A000000000000019"
        public static let lampeArcade = "A00000000000001A"
        public static let priseTerrasse = "A00000000000001B"
        public static let lampeGrenier = "A00000000000001C"
        public static let interrupteurSalon = "A000000000000020"
        public static let detecteurEntree = "A000000000000021"
        public static let interrupteurCuisine = "A000000000000022"
        public static let detecteurAbri = "A000000000000023"
        public static let telecommandeChambre = "A000000000000024"
        public static let capteurGrenier = "A000000000000025"
        public static let fuiteBuanderie = "A000000000000026"
        /// Un routeur que la sonde voit, et que le pont ne connait pas (celui d'un voisin).
        public static let inconnu = "A0000000000000FD"
        public static let sonde = "A0000000000000FE"
    }

    /// Adresse longue -> (nom, piece, fabricant, modele, categorie).
    static let table: [String: (String, String, String, String, String)] = [
        Ieee.pont: ("Pont Hue", "Salon", "Signify", "Hue Bridge", "Pont"),
        Ieee.plafonnierSalon: ("Plafonnier salon", "Salon", "Signify", "Hue White Ambiance", "Lampe"),
        Ieee.lampadaireSalon: ("Lampadaire salon", "Salon", "Signify", "Hue Signe", "Lampe"),
        Ieee.suspensionCuisine: ("Suspension cuisine", "Cuisine", "Signify", "Hue White", "Lampe"),
        Ieee.rubanCuisine: ("Ruban cuisine", "Cuisine", "Signify", "Hue Lightstrip", "Lampe"),
        Ieee.ampouleEntree: ("Ampoule entrée", "Entrée", "Signify", "Hue White", "Lampe"),
        Ieee.lampeBureau: ("Lampe bureau", "Bureau", "Signify", "Hue Go", "Lampe"),
        Ieee.lampeChambre: ("Lampe chambre", "Chambre", "Signify", "Hue White Ambiance", "Lampe"),
        Ieee.lampeChambreAmis: ("Lampe chambre d'amis", "Chambre d'amis", "Signify", "Hue White", "Lampe"),
        Ieee.priseSalon: ("Prise salon", "Salon", "Signify", "Hue Smart Plug", "Prise"),
        Ieee.lampeSalleDeBain: ("Lampe salle de bain", "Salle de bain", "Signify", "Hue White", "Lampe"),
        Ieee.lampeArcade: ("Lampe arcade", "Salle de jeux", "Signify", "Hue Play", "Lampe"),
        Ieee.priseTerrasse: ("Prise terrasse", "Terrasse", "Signify", "Hue Outdoor Smart Plug", "Prise"),
        Ieee.lampeGrenier: ("Lampe grenier", "Grenier", "Signify", "Hue White", "Lampe"),
        Ieee.interrupteurSalon: ("Interrupteur salon", "Salon", "Signify", "Hue Dimmer Switch", "Interrupteur"),
        Ieee.detecteurEntree: ("Détecteur entrée", "Entrée", "Signify", "Hue Motion Sensor", "Capteur"),
        Ieee.interrupteurCuisine: ("Interrupteur cuisine", "Cuisine", "Signify", "Hue Tap Dial", "Interrupteur"),
        Ieee.detecteurAbri: ("Détecteur abri", "Abri", "Signify", "Hue Outdoor Motion Sensor", "Capteur"),
        Ieee.telecommandeChambre: ("Télécommande chambre", "Chambre", "Signify", "Hue Smart Button", "Interrupteur"),
        Ieee.capteurGrenier: ("Capteur grenier", "Grenier", "Signify", "Hue Motion Sensor", "Capteur"),
        Ieee.fuiteBuanderie: ("Capteur de fuite", "Buanderie", "Aqara", "Water Leak Sensor", "Capteur"),
    ]

    /// Adresse longue -> batterie : une faible par son niveau, une par l'alerte seule ; les lampes et les prises sont
    /// sur secteur.
    static let batteries: [String: BatterieMaison] = [
        Ieee.interrupteurSalon: BatterieMaison(niveau: 76, charge: .nonRechargeable, alerte: false),
        Ieee.detecteurEntree: BatterieMaison(niveau: 58, charge: .nonRechargeable, alerte: false),
        Ieee.interrupteurCuisine: BatterieMaison(niveau: 91, charge: .nonRechargeable, alerte: false),
        Ieee.detecteurAbri: BatterieMaison(niveau: 33, charge: .nonRechargeable, alerte: false),
        Ieee.telecommandeChambre: BatterieMaison(niveau: 12, charge: .nonRechargeable, alerte: false),
        Ieee.capteurGrenier: BatterieMaison(alerte: true),
        Ieee.fuiteBuanderie: BatterieMaison(niveau: 100, charge: .nonRechargeable, alerte: false),
    ]

    /// Quatre etages pour les essais de la vue (le pont n'en donne pas) : le rez-de-chaussee, le jardin, l'etage, les
    /// combles.
    public static let zones = [
        ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Cuisine", "Entrée", "Buanderie"]),
        ZoneMaison(nom: "Jardin", pieces: ["Terrasse", "Abri"]),
        ZoneMaison(nom: "Étage", pieces: ["Chambre", "Bureau", "Salle de bain", "Chambre d'amis"]),
        ZoneMaison(nom: "Combles", pieces: ["Grenier", "Salle de jeux"]),
    ]

    /// Les appareils du pont, sans zones (un seul plateau), releves cinq minutes avant la fin de la demo.
    public static let maison: NomsMaison = {
        let accessoires = table.map { ieee, e in
            AccessoireMaison(nom: e.0, piece: e.1, fabricant: e.2, modele: e.3, categorie: e.4, ieee: ieee,
                             batterie: batteries[ieee])
        }
        return NomsMaison(date: MaillageDemo.fin.addingTimeInterval(-5 * 60), domicile: domicile,
                          accessoires: accessoires.sorted { $0.nom < $1.nom })
    }()

    /// La meme maison sur quatre etages (`zones`) : pour les essais de la vue par pieces.
    public static var maisonEtagee: NomsMaison {
        var m = maison
        m.zones = zones
        return m
    }

    /// Le releve de Maison de la demo (par le Passeur), invente : le meme domicile, les quatre etages de `zones`, les
    /// appareils du pont sous leurs noms de Maison, et deux accessoires d'une autre marque. Pour essayer la fusion
    /// (`FusionNoms`) : la suspension et l'interrupteur de la cuisine ont un autre nom dans Maison (retrouves par la piece
    /// et le modele), la lampe de la salle de bain un nom a la casse pres (normalisation), et le capteur de fuite, d'une
    /// autre marque, n'est pas un candidat : il garde le nom de l'app Hue.
    public static let releveMaison: ReleveMaison = {
        let autresNoms: [String: String] = [
            Ieee.suspensionCuisine: "Suspension de l'îlot",
            Ieee.interrupteurCuisine: "Variateur cuisine",
            Ieee.lampeSalleDeBain: "Lampe Salle de Bain",
        ]
        var accessoires = table.filter { $0.key != Ieee.fuiteBuanderie }.map { ieee, e in
            AccessoireReleve(nom: autresNoms[ieee] ?? e.0, piece: e.1, fabricant: "Signify Netherlands B.V.",
                             modele: e.3, categorie: e.4, pont: ieee == Ieee.pont ? true : nil,
                             batterie: batteries[ieee])
        }
        accessoires += [
            AccessoireReleve(nom: "Fuite buanderie", piece: "Buanderie", fabricant: "Aqara", modele: "Water Leak Sensor",
                             categorie: "Capteur", batterie: batteries[Ieee.fuiteBuanderie]),
            AccessoireReleve(nom: "Thermostat", piece: "Salon", fabricant: "Fabricant inventé", modele: "T1",
                             categorie: "Thermostat"),
        ]
        return ReleveMaison(date: MaillageDemo.fin.addingTimeInterval(-2 * 3600), domicile: domicile,
                            accessoires: accessoires.sorted { $0.nom < $1.nom }, zones: zones)
    }()

    /// Les noms de la demo : les appareils du pont nommes par Maison, sur les quatre etages de Maison (`FusionNoms`).
    public static var maisonFusionnee: NomsMaison {
        FusionNoms.fusionner(pont: maison, maison: releveMaison).noms ?? maison
    }

    /// Places de la demo : aucune, la demo n'ecrivant rien. Avec `zones` (`etagee`, pour `maisonEtagee`) : le jardin au
    /// niveau du rez-de-chaussee, hors de la maison (`dehors` faux : dans la maison).
    public static func places(etagee: Bool = false, dehors: Bool = true) -> PlacesGardees {
        var p = PlacesGardees()
        guard etagee else { return p }
        p.ranger(Rangement(ordre: zones.map { "zone:" + $0.nom },
                           aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: dehors)]),
                 domicile: domicile)
        return p
    }
}

/// Le maillage de la demo : deux tournees, la seconde a la fin de la demo. Entre les deux, la prise du salon (un
/// routeur) quitte le maillage, le detecteur de l'abri change de parent, et la telecommande de la chambre, absente de
/// la derniere table de sa lampe, garde son parent d'avant.
public enum MaillageDemo {
    /// La fin de la demo (08/10/2026, 9 h UTC) : la reference de ses durees (« vu il y a... »), toujours la meme.
    public static let fin = Date(timeIntervalSince1970: 1_791_450_000)
    /// La tournee d'avant, 15 minutes plus tot.
    public static var debut: Date { fin.addingTimeInterval(-15 * 60) }

    private typealias I = NomsDemo.Ieee

    /// Routeurs et adresses courtes inventees.
    private static let routeurs: [(String, UInt16)] = [
        (I.plafonnierSalon, 0x1A2B), (I.lampadaireSalon, 0x2B3C), (I.suspensionCuisine, 0x3C4D),
        (I.rubanCuisine, 0x4D5E), (I.ampouleEntree, 0x5E6F), (I.lampeBureau, 0x6F70), (I.lampeChambre, 0x7081),
        (I.lampeChambreAmis, 0x8192), (I.lampeSalleDeBain, 0x92A3), (I.lampeArcade, 0xA3B4), (I.priseTerrasse, 0xB4C5),
        (I.lampeGrenier, 0xC5D6), (I.inconnu, 0xD6E7),
    ]

    /// Appareils finaux, leur adresse courte, leur parent et le LQI que le parent en donne.
    private static let finaux: [(String, UInt16, String, Int)] = [
        (I.interrupteurSalon, 0x0A11, I.lampeChambre, 112),
        (I.detecteurEntree, 0x0A12, I.pont, 158),
        (I.interrupteurCuisine, 0x0A13, I.suspensionCuisine, 204),
        (I.detecteurAbri, 0x0A14, I.priseTerrasse, 72),
        (I.telecommandeChambre, 0x0A15, I.lampeChambre, 181),
        (I.capteurGrenier, 0x0A16, I.lampeGrenier, 120),
        (I.fuiteBuanderie, 0x0A17, I.rubanCuisine, 44),
        (I.sonde, 0x0A18, I.lampeBureau, 188),
    ]

    /// Liens radio : (x, y, LQI mesure par x, LQI mesure par y) ; quelques-uns faibles, un dont un seul sens est connu
    /// (le routeur inconnu, muet, ne donne pas sa table).
    private static let liens: [(String, String, Int?, Int?)] = [
        (I.pont, I.plafonnierSalon, 230, 224),
        (I.pont, I.lampadaireSalon, 210, 198),
        (I.pont, I.suspensionCuisine, 176, 181),
        (I.pont, I.lampeBureau, 142, 150),
        (I.plafonnierSalon, I.lampadaireSalon, 240, 236),
        (I.plafonnierSalon, I.ampouleEntree, 164, 171),
        (I.suspensionCuisine, I.rubanCuisine, 220, 215),
        (I.rubanCuisine, I.priseTerrasse, 88, 61),
        (I.lampadaireSalon, I.lampeBureau, 131, 126),
        (I.lampeBureau, I.lampeChambre, 190, 185),
        (I.lampeChambre, I.lampeChambreAmis, 178, 172),
        (I.lampeChambre, I.lampeSalleDeBain, 104, 97),
        (I.lampeChambreAmis, I.lampeArcade, 93, 108),
        (I.lampeArcade, I.lampeGrenier, 150, 146),
        (I.lampeSalleDeBain, I.lampeGrenier, 46, 52),
        (I.ampouleEntree, I.inconnu, 66, nil),
    ]

    /// Chemins vers le pont lus (routes actives, inventees) : directs, ou par une lampe. La prise de la terrasse n'a
    /// qu'une route inactive, et le routeur inconnu, muet, ne donne pas ses routes : leurs chemins sont supposes. La
    /// lampe du bureau passait par le pont a la tournee d'avant, puis par le lampadaire du salon.
    private static func cheminsLus(avant: Bool) -> [(String, String)] {
        [(I.plafonnierSalon, I.pont), (I.lampadaireSalon, I.pont), (I.suspensionCuisine, I.pont),
         (I.lampeBureau, avant ? I.pont : I.lampadaireSalon), (I.ampouleEntree, I.plafonnierSalon),
         (I.rubanCuisine, I.suspensionCuisine), (I.lampeChambre, I.lampeBureau), (I.lampeChambreAmis, I.lampeChambre),
         (I.lampeSalleDeBain, I.lampeChambre), (I.lampeArcade, I.lampeChambreAmis), (I.lampeGrenier, I.lampeArcade)]
            + (avant ? [(I.priseSalon, I.plafonnierSalon)] : [])
    }

    /// Le maillage a la fin de la demo.
    public static var maillage: MaillageZigbee { maillage(date: fin, avant: false) }

    /// La tournee d'avant : la prise du salon y est encore, et le detecteur de l'abri est sous le ruban de la cuisine.
    public static var maillageAvant: MaillageZigbee { maillage(date: debut, avant: true) }

    static func maillage(date: Date, avant: Bool) -> MaillageZigbee {
        var noeuds = [NoeudZigbee(ieee: I.pont, court: 0x0000, type: .coordinateur)]
        noeuds += routeurs.map { NoeudZigbee(ieee: $0.0, court: $0.1, type: .routeur, muet: $0.0 == I.inconnu) }
        // Les appareils finaux a pile dorment au repos (`ecoute` faux) ; la sonde ecoute.
        noeuds += finaux.map { NoeudZigbee(ieee: $0.0, court: $0.1, type: .final, ecoute: $0.0 == I.sonde) }
        var radio: [LienRadio] = liens.map { x, y, lx, ly in
            var l = LienRadio(mesurePar: x, de: y, lqi: lx, date: lx == nil ? nil : date)
            l = l.fusionner(LienRadio(mesurePar: y, de: x, lqi: ly, date: ly == nil ? nil : date))
            return l
        }
        var parents = finaux.map { LienParent(enfant: $0.0, parent: $0.2, lqi: $0.3, date: date) }
        // La telecommande de la chambre, endormie, manque a la table de sa lampe a la derniere tournee : elle garde
        // son parent d'avant (`ParentsConnus`), lu a la tournee d'avant, trace en pointilles.
        if !avant, let i = parents.firstIndex(where: { $0.enfant == I.telecommandeChambre }) {
            parents[i] = LienParent(enfant: I.telecommandeChambre, parent: I.lampeChambre, lqi: parents[i].lqi,
                                    date: debut, dAvant: true)
        }
        if avant {
            noeuds.append(NoeudZigbee(ieee: I.priseSalon, court: 0xE7F8, type: .routeur))
            radio.append(LienRadio(mesurePar: I.priseSalon, de: I.plafonnierSalon, lqi: 200, date: date))
            if let i = parents.firstIndex(where: { $0.enfant == I.detecteurAbri }) {
                parents[i] = LienParent(enfant: I.detecteurAbri, parent: I.rubanCuisine, lqi: 58, date: date)
            }
        }
        let routes = routeurs.filter { $0.0 != I.inconnu }.map { r in
            RouteZigbee(destination: r.1, prochain: prochain(vers: r.0), etat: "active")
        }
        let court = Dictionary(noeuds.compactMap { n in n.court.map { (n.ieee, $0) } }, uniquingKeysWith: { a, _ in a })
        var routesVersPont: [String: RouteVersPont] = [:]
        for (r, p) in cheminsLus(avant: avant) {
            routesVersPont[r] = RouteVersPont(prochain: court[p] ?? 0, actif: true, plusieursVersUn: true, date: date)
        }
        routesVersPont[I.priseTerrasse] = RouteVersPont(prochain: 0, actif: false, plusieursVersUn: false, date: date)
        return MaillageZigbee(date: date, noeuds: noeuds, liens: radio, parents: parents, routesPont: routes,
                              sonde: I.sonde,
                              signaux: [SignalSonde(ieee: I.lampeBureau, lqi: 188), SignalSonde(ieee: I.lampeChambre, lqi: 142),
                                        SignalSonde(ieee: I.lampadaireSalon, lqi: 97)],
                              chemins: CheminsPont.calculer(noeuds: noeuds, liens: MaillageZigbee.reunir(radio),
                                                            routes: routesVersPont),
                              dateTables: date)
    }

    /// Un historique invente de 24 h, un releve toutes les 15 min jusqu'a la fin de la demo (captures de la fiche, etape
    /// 5) : les liens de la tournee d'avant, puis de la derniere, leurs LQI qui ondulent ; la lampe du bureau hesite entre
    /// le pont et le lampadaire du salon (`prochainDuBureau`), puis passe au lampadaire il y a 10 h ; le detecteur de
    /// l'abri passe du ruban de la cuisine a la prise de la terrasse il y a 6 h ; une heure sans releve (la sonde
    /// debranchee) il y a 16 h. Valeurs inventees.
    public static var historique: [ReleveMaillage] {
        let n = 96
        return (0...n).compactMap { i -> ReleveMaillage? in
            // Une heure sans releve.
            guard !(30..<34).contains(i) else { return nil }
            let date = fin.addingTimeInterval(Double(i - n) * 15 * 60)
            let r = ReleveMaillage(maillage(date: date, avant: i < n - 1))
            func onde(_ lqi: Int?, _ cle: String) -> Int? {
                guard let lqi else { return nil }
                let graine = Double(cle.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 1000 })
                return min(255, max(0, lqi + Int((18 * sin(Double(i) * 0.21 + graine)).rounded())))
            }
            let liens = r.liens.map { l in
                LienRadio(a: l.a, b: l.b, lqiA: onde(l.lqiA, l.a + l.b), lqiB: onde(l.lqiB, l.b + l.a))
            }
            let parents = r.parents.map { p -> LienParent in
                let parent = p.enfant == I.detecteurAbri ? (i >= n - 24 ? I.priseTerrasse : I.rubanCuisine) : p.parent
                return LienParent(enfant: p.enfant, parent: parent, lqi: onde(p.lqi, p.enfant))
            }
            let chemins = r.chemins.map { c in
                c.routeur == I.lampeBureau
                    ? ReleveMaillage.Chemin(routeur: c.routeur, prochain: prochainDuBureau(i, sur: n))
                    : c
            }
            return ReleveMaillage(date: date, noeuds: r.noeuds, liens: liens, parents: parents,
                                  signaux: r.signaux.map { SignalSonde(ieee: $0.ieee, lqi: onde($0.lqi, $0.ieee) ?? $0.lqi) },
                                  sonde: r.sonde, chemins: chemins)
        }
    }

    /// Le prochain saut de la lampe du bureau au releve `i` (sur `n`) de l'historique : le pont ; un releve sur deux le
    /// lampadaire du salon entre 14 h 30 et 12 h 15 avant la fin (dix changements a 15 min l'un de l'autre, qui se fondent
    /// en un repere quand ils sont proches a l'echelle affichee) ; puis le lampadaire des 10 h avant la fin, onze
    /// changements en tout.
    static func prochainDuBureau(_ i: Int, sur n: Int) -> String {
        if i >= n - 40 { return I.lampadaireSalon }
        if (n - 58 ... n - 49).contains(i) { return (i - (n - 58)) % 2 == 0 ? I.lampadaireSalon : I.pont }
        return I.pont
    }

    /// Le prochain saut du pont vers un routeur de la demo : lui-meme s'il est son voisin, sinon le premier voisin du
    /// pont relie a lui, sinon le plafonnier du salon.
    private static func prochain(vers ieee: String) -> UInt16 {
        let voisins = liens.filter { $0.0 == I.pont }.map(\.1)
        let court = Dictionary(uniqueKeysWithValues: routeurs.map { ($0.0, $0.1) })
        if voisins.contains(ieee) { return court[ieee] ?? 0 }
        let relie = voisins.first { v in liens.contains { ($0.0 == v && $0.1 == ieee) || ($0.1 == v && $0.0 == ieee) } }
        return court[relie ?? I.plafonnierSalon] ?? 0
    }
}
