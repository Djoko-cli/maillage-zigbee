import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Protocole USB de la sonde Zigbee")
struct ProtocoleSondeTests {
    /// Ligne JSON `erreur` de `octets` octets exactement (ASCII) : le message est complete par des `x`.
    static func jsonErreur(octets: Int) -> (json: String, message: String) {
        let debut = #"{"v":1,"t":"erreur","erreur":""#, fin = #""}"#
        let message = String(repeating: "x", count: octets - debut.utf8.count - fin.utf8.count)
        return (debut + message + fin, message)
    }

    /// `bonjour` de la sonde Zigbee (spec de la sonde, section 2) : produit, version, nom, adresse longue, adhesion,
    /// role, suspension ; au demarrage, `ieee` et `role` peuvent valoir null.
    @Test func bonjour() throws {
        let json = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":"SONDE-Z1","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false}"#
        guard case .bonjour(let b)? = MessageSonde.lire(Data(json.utf8)) else {
            Issue.record("bonjour illisible")
            return
        }
        #expect(b == Bonjour(produit: "sonde-zigbee", version: "1.0.0", nom: "SONDE-Z1", ieee: "A000000000000001",
                             membre: true, role: "final", suspendue: false))
        #expect(b.estSonde)
        let demarrage = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":"SONDE-Z1","ieee":null,"membre":false,"role":null,"suspendue":false}"#
        guard case .bonjour(let d)? = MessageSonde.lire(Data(demarrage.utf8)) else {
            Issue.record("bonjour de demarrage illisible")
            return
        }
        #expect(d.ieee == nil && d.role == nil && d.membre == false && d.estSonde)
    }

    /// `estSonde` : seul le produit exact est une sonde Zigbee. La sonde de Maillage Thread (`sonde-maillage`), le pont
    /// Halo, une autre casse, un espace de trop ou un produit vide se lisent, mais ne sont pas une sonde : l'app refuse
    /// alors le port. Sans `produit`, la ligne est illisible.
    @Test func estSondeNegatif() {
        func bonjour(produit: String) -> Bonjour? {
            let json = #"{"v":1,"t":"bonjour","produit":"\#(produit)","version":"1.0.0"}"#
            guard case .bonjour(let b)? = MessageSonde.lire(Data(json.utf8)) else { return nil }
            return b
        }
        #expect(ProtocoleSonde.produit == "sonde-zigbee")
        #expect(bonjour(produit: ProtocoleSonde.produit)?.estSonde == true, "le produit attendu")
        for autre in ["sonde-maillage", "halo", "Sonde-Zigbee", "sonde-zigbee ", "sonde", ""] {
            let lu = bonjour(produit: autre)
            #expect(lu != nil, "\(autre) : bonjour lisible")
            #expect(lu?.estSonde == false, "\(autre) : pas une sonde")
        }
        let sansProduit = #"{"v":1,"t":"bonjour","version":"1.0.0"}"#
        #expect(MessageSonde.lire(Data(sansProduit.utf8)) == nil, "sans produit : illisible")
    }

    /// `etat` : membre, adresses, parent avec son LQI, reseau, suspension, pile ; hors adhesion, les champs du reseau
    /// valent null ; `suspendue` absent vaut faux.
    @Test func etat() throws {
        let json = #"{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":{"court":"1A2B","ieee":"A000000000000002","lqi":180,"rssi":-71},"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":false,"refus_cadence":0,"rattachements_echoues":0,"pile":"1.6.8"}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(json.utf8)) else {
            Issue.record("etat illisible")
            return
        }
        #expect(e.membre && e.court == "5E6F" && e.canal == 25 && e.pan == "1234" && !e.suspendue && e.pile == "1.6.8")
        #expect(e.parent == ParentSonde(court: "1A2B", ieee: "A000000000000002", lqi: 180, rssi: -71))
        let hors = #"{"v":1,"t":"etat","membre":false,"recherche":true,"court":null,"ieee":"A000000000000001","role":null,"parent":null,"pan":null,"epid":null,"canal":null}"#
        guard case .etat(let h)? = MessageSonde.lire(Data(hors.utf8)) else {
            Issue.record("etat hors adhesion illisible")
            return
        }
        #expect(!h.membre && h.parent == nil && h.canal == nil && !h.suspendue)
    }

    /// `etat` refuse (verrou de la pile pris) : la commande et l'erreur, pour que l'app le dise tout de suite.
    @Test func refusees() {
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"etat","erreur":"occupee"}"#.utf8))
                == .refusee(commande: "etat", erreur: "occupee"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"etat","role":"final"}"#.utf8)) == nil, "ni etat lisible, ni erreur")
    }

    /// Le reste : une erreur generale, `oubli`, un type que l'app ne lit pas, une autre version, du texte.
    @Test func autres() {
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"erreur","erreur":"inconnue"}"#.utf8)) == .erreur("inconnue"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"erreur","erreur":"syntaxe"}"#.utf8)) == .erreur("syntaxe"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"oubli","ok":true}"#.utf8)) == .oubli(true))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"echecs","id":3}"#.utf8)) == .inconnu("echecs"))
        #expect(MessageSonde.lire(Data(#"{"v":2,"t":"etat"}"#.utf8)) == nil, "autre version")
        #expect(MessageSonde.lire(Data("pas du json".utf8)) == nil)
    }

    /// `etat` complet : extended PAN ID, refus de cadence et rattachements echoues.
    @Test func etatComplet() throws {
        let json = #"{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":null,"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":true,"refus_cadence":3,"rattachements_echoues":2,"pile":"1.6.8"}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(json.utf8)) else {
            Issue.record("etat illisible")
            return
        }
        #expect(e.epid == "A0000000000000FF" && e.refusCadence == 3 && e.rattachementsEchoues == 2 && e.suspendue)
        #expect(e.parent == nil, "pendant un rattachement")
    }

    /// `voisins` : la table de la sonde ; refusee (`occupee`) sans liste.
    @Test func voisins() throws {
        let json = #"{"v":1,"t":"voisins","liste":[{"court":"1A2B","ieee":"A000000000000002","type":"routeur","relation":"parent","lqi":180,"rssi":-71,"cout_sortant":1,"age":0}],"suite":false}"#
        guard case .voisins(let l)? = MessageSonde.lire(Data(json.utf8)) else {
            Issue.record("voisins illisible")
            return
        }
        #expect(l.liste == [VoisinDeLaSonde(court: "1A2B", ieee: "A000000000000002", type: "routeur", relation: "parent",
                                            lqi: 180, rssi: -71, coutSortant: 1, age: 0)])
        #expect(l.suite == false)
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"voisins","erreur":"occupee"}"#.utf8))
                == .refusee(commande: "voisins", erreur: "occupee"))
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"voisins","suite":false}"#.utf8)) == nil, "ni liste ni erreur")
    }

    /// `table` sur trois lignes de meme id (`suite`), reunies : l'en-tete de la premiere, les entrees bout a bout ;
    /// une entree illisible est ignoree (la table n'a plus son total : a redemander).
    @Test func tableSurPlusieursLignes() throws {
        let entete = #""v":1,"t":"table","id":7,"cible":"1A2B","ok":true,"ms":840,"pages":2,"total":3,"partielle":false"#
        let e1 = #"{"court":"0000","ieee":"A000000000000003","type":"coordinateur","relation":"aucune","ecoute":true,"profondeur":0,"admission":false,"lqi":212}"#
        let e2 = #"{"court":"0A11","ieee":"A000000000000007","type":"final","relation":"enfant","ecoute":false,"profondeur":2,"admission":null,"lqi":120}"#
        let e3 = #"{"court":"3C4D","ieee":"A000000000000005","type":"routeur","relation":"frere","ecoute":null,"profondeur":15,"admission":false,"lqi":60}"#
        let lignes = ["{\(entete),\"liste\":[\(e1)],\"suite\":true}", "{\(entete),\"liste\":[\(e2)],\"suite\":true}",
                      "{\(entete),\"liste\":[\(e3)],\"suite\":false}"]
        var fusion = FusionLignes<EntreeTable>()
        var reponses: [ReponseListe<EntreeTable>] = []
        for l in lignes {
            guard case .table(let t)? = MessageSonde.lire(Data(l.utf8)) else {
                Issue.record("ligne illisible : \(l)")
                return
            }
            if let r = fusion.ajouter(t) { reponses.append(r) }
        }
        try #require(reponses.count == 1)
        let r = reponses[0]
        #expect(r.ok && r.id == 7 && r.cible == "1A2B" && r.total == 3 && r.pages == 2 && r.ms == 840 && !r.partielle)
        #expect(r.liste.map(\.court) == ["0000", "0A11", "3C4D"] && r.complete && fusion.vide)
        #expect(r.liste[0].typeNoeud == .coordinateur && r.liste[1].ecoute == false && r.liste[2].ecoute == nil)
        #expect(r.liste[1].relation == "enfant" && r.liste[1].lqi == 120)
        // `pages` demesure ou negatif (relecture finale, M3) : ramene entre 0 et `pagesMax`, sans debordement.
        for (texte, attendu) in [("9223372036854775807", ProtocoleSonde.pagesMax), ("-3", 0), ("1000", 1000)] {
            let l = #"{"v":1,"t":"table","id":8,"cible":"1A2B","ok":true,"pages":\#(texte),"total":0,"liste":[],"suite":false}"#
            guard case .table(let t)? = MessageSonde.lire(Data(l.utf8)) else {
                Issue.record("ligne illisible : \(l)")
                continue
            }
            #expect(t.pages == attendu)
        }
        // Une entree illisible (sans `court`) : ignoree, et la table n'est plus complete.
        let abimee = "{\(entete),\"liste\":[\(e1),{\"ieee\":\"A000000000000009\"},\(e3)],\"suite\":false}"
        var f2 = FusionLignes<EntreeTable>()
        guard case .table(let t)? = MessageSonde.lire(Data(abimee.utf8)), let r2 = f2.ajouter(t) else {
            Issue.record("ligne abimee illisible")
            return
        }
        #expect(r2.liste.count == 2 && !r2.complete)
        #expect(ReponseListe<EntreeTable>(ok: true, total: 3, partielle: true, liste: []).complete, "partielle")
        #expect(ReponseListe<EntreeTable>.echec("delai").complete, "un echec n'est pas a redemander")
    }

    /// Echecs de `table` : une ligne, `ok` faux, l'erreur (et le code ZDO pour `statut`) ; une ligne sans id, sans
    /// cible ou sans `ok` est illisible.
    @Test func tableEnEchec() throws {
        let json = #"{"v":1,"t":"table","id":9,"cible":"3C4D","ok":false,"erreur":"statut","statut":"0x84"}"#
        var f = FusionLignes<EntreeTable>()
        guard case .table(let t)? = MessageSonde.lire(Data(json.utf8)), let r = f.ajouter(t) else {
            Issue.record("echec illisible")
            return
        }
        #expect(!r.ok && r.erreur == "statut" && r.statut == "0x84" && r.id == 9 && r.cible == "3C4D")
        for erreur in ["delai", "suspendue", "occupee", "non_membre", "cadence", "envoi"] {
            let l = #"{"v":1,"t":"table","id":1,"cible":"1A2B","ok":false,"erreur":"\#(erreur)"}"#
            guard case .table(let t)? = MessageSonde.lire(Data(l.utf8)) else {
                Issue.record("\(erreur) illisible")
                continue
            }
            #expect(t.erreur == erreur && t.ok == false)
        }
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"table","cible":"1A2B","ok":false,"erreur":"delai"}"#.utf8)) == nil)
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"table","id":1,"ok":true,"liste":[]}"#.utf8)) == nil)
        #expect(MessageSonde.lire(Data(#"{"v":1,"t":"table","id":1,"cible":"1A2B","ok":true}"#.utf8)) == nil,
                "reussie sans liste")
    }

    /// `routes` : meme enveloppe ; une entree de la table de routage.
    @Test func routes() throws {
        let json = #"{"v":1,"t":"routes","id":12,"cible":"0000","ok":true,"ms":2600,"pages":22,"total":2,"partielle":false,"liste":[{"destination":"3C4D","etat":"active","prochain":"1A2B","memoire_limitee":false,"plusieurs_vers_un":true,"enregistrement":false},{"destination":"FFFF","etat":"inactive","prochain":"0000","memoire_limitee":false,"plusieurs_vers_un":false,"enregistrement":false}],"suite":false}"#
        var f = FusionLignes<EntreeRoute>()
        guard case .routes(let l)? = MessageSonde.lire(Data(json.utf8)), let r = f.ajouter(l) else {
            Issue.record("routes illisibles")
            return
        }
        #expect(r.ok && r.total == 2 && r.complete)
        #expect(r.liste[0] == EntreeRoute(destination: "3C4D", etat: "active", prochain: "1A2B", memoireLimitee: false,
                                          plusieursVersUn: true, enregistrement: false))
    }

    /// `signal` : decode, pour un compteur ; le parent perdu (statut NWK 9).
    @Test func signal() {
        let json = #"{"v":1,"t":"signal","signal":"0x32","nom":"NLME_STATUS_INDICATION","ok":true,"detail":9}"#
        guard case .signal(let s)? = MessageSonde.lire(Data(json.utf8)) else {
            Issue.record("signal illisible")
            return
        }
        #expect(s.parentPerdu && s.signal == "0x32")
        #expect(SignalPile(signal: "0x01", nom: "ZDO_SIGNAL_DEFAULT_START", ok: true, detail: 0).parentPerdu == false)
    }

    /// Commandes : cible en 4 hexa majuscules, id decimal, delai borne a 500..5000 ms.
    @Test func commandes() {
        #expect(CommandeSonde.bonjour.ligne == "bonjour\n")
        #expect(CommandeSonde.etat.ligne == "etat\n")
        #expect(CommandeSonde.voisins.ligne == "voisins\n")
        #expect(CommandeSonde.table(cible: 0x1A2B, id: 7).ligne == "table 1A2B 7\n")
        #expect(CommandeSonde.table(cible: 0, id: 12, delaiMs: 3000).ligne == "table 0000 12 3000\n")
        #expect(CommandeSonde.routes(cible: 0x0A, id: 1, delaiMs: 9000).ligne == "routes 000A 1 5000\n")
        #expect(CommandeSonde.table(cible: 0xFFF7, id: 2, delaiMs: 10).ligne == "table FFF7 2 500\n")
        #expect(ProtocoleSonde.court("1a2b") == 0x1A2B && ProtocoleSonde.court("1A2") == nil)
        #expect(ProtocoleSonde.court("1A2G") == nil && ProtocoleSonde.texte(court: 0x0A) == "000A")
    }

    /// Lignes machine seulement, meme coupees en morceaux ; lignes humaines et trop longues ignorees.
    @Test func decoupage() {
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data("I (123) chip: log\n\u{1E}{\"v\":1,".utf8)).isEmpty)
        let l = d.ajouter(Data("\"t\":\"etat\"}\r\n\u{1E}{}\n".utf8))
        #expect(l == [Data(#"{"v":1,"t":"etat"}"#.utf8), Data("{}".utf8)])
        var long = Data([ProtocoleSonde.separateur]) + Data(repeating: 0x41, count: 5000)
        long.append(0x0A)
        #expect(d.ajouter(long + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)])
    }

    // Une ligne machine commence au dernier RS de la ligne, comme dans le pont Halo (le JSON est de
    // l'ASCII imprimable : jamais de RS dedans) ; ce qui precede le RS sur la ligne est abandonne.

    /// Du texte sans fin de ligne juste avant le RS (queue d'un log coupe, invite d'une session humaine) :
    /// la ligne machine intacte est retrouvee, dans le meme morceau ou dans le suivant.
    @Test func decoupageTexteAvantLeRS() {
        let json = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data("E (48213) chip[DL]: fin d'un log\u{1E}\(json)\n".utf8)) == [Data(json.utf8)],
                "queue de log et ligne machine dans le meme morceau")
        #expect(d.ajouter(Data("> ".utf8)).isEmpty)
        #expect(d.ajouter(Data("\u{1E}\(json)\r\n".utf8)) == [Data(json.utf8)], "invite, puis la ligne dans le morceau suivant")
    }

    /// Ligne machine coupee (RS et debut du JSON) suivie d'une ligne complete : seule la complete sort,
    /// et non les deux collees en une ligne que `lire` refuserait, la bonne perdue avec elle.
    @Test func decoupageLigneCoupee() {
        let coupee = #"{"v":1,"t":"diag","id":11,"cible":"5000","ok":true,"ms":73,"code":"2.04","tlv":"0E08"#
        let complete = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        let l = d.ajouter(Data("\u{1E}\(coupee)\u{1E}\(complete)\n".utf8))
        #expect(l == [Data(complete.utf8)], "la coupee et la complete dans le meme morceau")
        #expect(l.compactMap { MessageSonde.lire($0) } == [.erreur("occupee")])
        #expect(d.ajouter(Data("\u{1E}\(coupee)".utf8)).isEmpty)
        #expect(d.ajouter(Data("\u{1E}\(complete)\n".utf8)) == [Data(complete.utf8)], "la complete dans le morceau suivant")
    }

    /// Un RS remet a zero l'etat "ligne trop longue" : la ligne machine qui le suit est retrouvee.
    @Test func decoupageRSApresUneLigneTropLongue() {
        let trop = Data(repeating: 0x41, count: 5000)
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data([ProtocoleSonde.separateur]) + trop + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)],
                "ligne machine trop longue, coupee")
        #expect(d.ajouter(trop + Data("\u{1E}{}\n".utf8)) == [Data("{}".utf8)], "texte trop long, sans fin de ligne")
    }

    /// RS suivi aussitot de LF : une ligne machine vide. Elle sort vide (le RS est retire), `lire`
    /// la refuse, et la suite n'en souffre pas ; meme coupee entre deux morceaux, ou avec un CR.
    @Test func decoupageRSLF() {
        let json = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        #expect(d.ajouter(Data([ProtocoleSonde.separateur, 0x0A])) == [Data()], "RS LF")
        #expect(MessageSonde.lire(Data()) == nil, "une ligne vide est illisible : ignoree")
        #expect(d.ajouter(Data([ProtocoleSonde.separateur])).isEmpty)
        #expect(d.ajouter(Data([0x0A])) == [Data()], "RS et LF dans deux morceaux")
        #expect(d.ajouter(Data([ProtocoleSonde.separateur, 0x0D, 0x0A])) == [Data()], "RS CR LF")
        #expect(d.ajouter(Data("\u{1E}\(json)\n".utf8)) == [Data(json.utf8)], "la ligne suivante est intacte")
    }

    /// Frontiere de la longueur : la limite (`longueurMax`, 4096) porte sur la ligne machine, RS
    /// compris et LF non compris. A 4096 octets la ligne passe, et `lire` la comprend ; a 4097
    /// elle est ecartee en entier, sans ligne coupee. (Le firmware n'en emet jamais plus de
    /// 4095, RS et LF compris : aucune ligne valide n'est perdue.)
    @Test func decoupageFrontiereDeLongueur() {
        #expect(ProtocoleSonde.longueurMax == 4096)
        let juste = Self.jsonErreur(octets: ProtocoleSonde.longueurMax - 1)  // avec le RS : 4096
        let trop = Self.jsonErreur(octets: ProtocoleSonde.longueurMax)  // avec le RS : 4097
        let suivante = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        var d = DecoupeurLignes()
        let lignes = d.ajouter(Data("\u{1E}\(juste.json)\n".utf8))
        #expect(lignes == [Data(juste.json.utf8)], "4096 octets, RS compris : la ligne passe")
        #expect(lignes.compactMap { MessageSonde.lire($0) } == [.erreur(juste.message)], "et elle se lit")
        #expect(d.ajouter(Data("\u{1E}\(trop.json)\n".utf8)).isEmpty, "4097 octets : ecartee")
        #expect(d.ajouter(Data("\u{1E}\(suivante)\n".utf8)) == [Data(suivante.utf8)], "la ligne suivante est retrouvee")
    }

    /// Ligne trop longue coupee entre deux `ajouter` : l'etat "trop longue" passe d'un appel a
    /// l'autre. Ni la fin de la ligne, seule dans le morceau suivant, ni un reste qui ressemble a
    /// une ligne complete, ne sortent (surtout pas la ligne coupee a la limite) ; la limite
    /// franchie dans le second morceau, ou pile entre les deux, se traite comme dans un seul.
    @Test func decoupageTropLongueEntreDeuxMorceaux() {
        let limite = ProtocoleSonde.longueurMax
        let rs = Data([ProtocoleSonde.separateur]), lf = Data([0x0A])
        func remplissage(_ n: Int) -> Data { Data(repeating: 0x41, count: n) }
        let suivante = #"{"v":1,"t":"erreur","erreur":"occupee"}"#
        let ressemble = Data("\(suivante)\n".utf8)
        let cas: [(nom: String, morceaux: [Data], lignes: [Data])] = [
            ("limite franchie dans le premier morceau, LF seul ensuite",
             [rs + remplissage(5000), lf], []),
            ("idem, puis un reste qui ressemble a une ligne complete",
             [rs + remplissage(5000), ressemble], []),
            ("limite franchie dans le second morceau",
             [rs + remplissage(3000), remplissage(3000) + lf], []),
            ("pile a la limite, LF dans le second morceau",
             [rs + remplissage(limite - 1), lf], [remplissage(limite - 1)]),
            ("un octet de plus dans le second morceau",
             [rs + remplissage(limite - 1), remplissage(1) + lf], []),
        ]
        for (nom, morceaux, attendues) in cas {
            var d = DecoupeurLignes()
            var lignes: [Data] = []
            for m in morceaux { lignes += d.ajouter(m) }
            #expect(lignes == attendues, "\(nom)")
            #expect(d.ajouter(rs + ressemble) == [Data(suivante.utf8)], "\(nom) : la ligne suivante est retrouvee")
        }
    }
}
