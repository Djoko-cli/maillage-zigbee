import Foundation
import Testing
@testable import MaillageCoeur

/// Contrat de l'abonnement au passeur (spec du 12/10, section 2). Sans type propre a Maillage Thread : ce fichier se
/// recopie tel quel dans Maillage Zigbee, avec `ProtocolePasseur.swift`.
@Suite("Protocole du passeur : URL, messages, trames")
struct ProtocolePasseurTests {
    static let jeton = String(repeating: "5a", count: 32)
    static let etat = EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)

    static func objet(_ json: Data) -> NSDictionary? {
        (try? JSONSerialization.jsonObject(with: json)) as? NSDictionary
    }

    /// L'URL `abonner` : texte exact, aller-retour, hote sans tenir compte de la casse ; `releve` reste la demande par
    /// defaut ; un autre hote est refuse.
    @Test func urlAbonner() throws {
        let c = EnvoiPasseur.Cible(port: 54_321, jeton: Self.jeton, demande: .abonner)
        #expect(c.url.absoluteString == "maillage-passeur://abonner?port=54321&jeton=\(Self.jeton)")
        #expect(EnvoiPasseur.Cible(url: c.url) == c)
        let majuscules = try #require(URL(string: "MAILLAGE-PASSEUR://ABONNER?port=54321&jeton=\(Self.jeton)"))
        #expect(EnvoiPasseur.Cible(url: majuscules)?.demande == .abonner)
        #expect(EnvoiPasseur.Cible(port: 1, jeton: Self.jeton).demande == .releve, "releve par defaut")
        let abonne = try #require(URL(string: "maillage-passeur://abonne?port=54321&jeton=\(Self.jeton)"))
        #expect(EnvoiPasseur.Cible(url: abonne) == nil, "autre hote")
    }

    /// Les schemas : celui des URL, et celui que seul le nouveau demon declare (les apps le cherchent par lui).
    @Test func schemas() {
        #expect(EnvoiPasseur.schema == "maillage-passeur")
        #expect(EnvoiPasseur.schemaProtocole == "maillage-passeur-1")
    }

    /// Chaque message se relit tel quel.
    @Test(arguments: [
        MessagePasseur.etat(ProtocolePasseurTests.etat),
        .etat(EtatPasseur(version: "2.1", acces: .refuse, ouvertureSession: .aApprouver,
                          profilExpire: Date(timeIntervalSince1970: 1_820_000_000))),
        .identifie(ReponseIdentifier(demande: 3, ok: true)),
        .identifie(ReponseIdentifier(demande: 4, ok: false, erreur: ReponseIdentifier.nonIdentifiable)),
        .relire,
        .identifier(demande: 7, accessoire: "8D3C2A10-0000-4000-8000-000000000001"),
        .ouvertureSession(actif: true),
        .ouvertureSession(actif: false),
    ])
    func allerRetour(_ m: MessagePasseur) {
        #expect(MessagePasseur.lire(m.json()) == .message(m))
    }

    /// Le releve voyage en JSON brut : le meme objet a l'arrivee, quel que soit son type dans l'app.
    @Test func releveBrut() throws {
        let noms = Data(#"{"accessoires":[{"nom":"Halo","pont":true}],"date":"2026-10-12T12:00:00.000Z","statut":"ok","version":2}"#.utf8)
        guard case .message(.releve(let lu)) = MessagePasseur.lire(MessagePasseur.releve(noms).json()) else {
            Issue.record("releve non relu")
            return
        }
        #expect(Self.objet(lu) == Self.objet(noms))
    }

    /// Le texte exact de quelques messages : cles triees, `v` et `t`, `null` explicite pour un profil illisible.
    @Test func texteExact() {
        #expect(String(decoding: MessagePasseur.relire.json(), as: UTF8.self) == #"{"t":"relire","v":1}"#)
        #expect(String(decoding: MessagePasseur.identifier(demande: 7, accessoire: "X").json(), as: UTF8.self)
                == #"{"accessoire":"X","demande":7,"t":"identifier","v":1}"#)
        #expect(String(decoding: MessagePasseur.etat(Self.etat).json(), as: UTF8.self)
                == #"{"acces":"autorise","ouvertureSession":"inactive","profilExpire":null,"t":"etat","v":1,"version":"2.0"}"#)
    }

    /// Type inconnu, ou type connu aux champs illisibles : ignore, avec son type (une version suivante ne casse pas une
    /// ancienne).
    @Test(arguments: [
        (#"{"t":"allumer","v":1}"#, "allumer"),
        (#"{"t":"etat","v":1,"version":"2.0","acces":"peutEtre","ouvertureSession":"active","profilExpire":null}"#, "etat"),
        (#"{"t":"etat","v":1,"version":"2.0","acces":"autorise","ouvertureSession":"active","profilExpire":"demain"}"#, "etat"),
        (#"{"t":"identifier","v":1,"demande":1}"#, "identifier"),
        (#"{"t":"identifier","v":1,"demande":1.5,"accessoire":"X"}"#, "identifier"),
        (#"{"t":"ouvertureSession","v":1,"actif":1}"#, "ouvertureSession"),
        (#"{"t":"identifie","v":1,"demande":true,"ok":true}"#, "identifie"),
        (#"{"t":"releve","v":1,"noms":[1,2]}"#, "releve"),
    ])
    func ignore(_ texte: String, _ type: String) {
        #expect(MessagePasseur.lire(Data(texte.utf8)) == .ignore(type))
    }

    /// Pas un objet JSON, ou pas de type : illisible (la connexion se ferme).
    @Test(arguments: [#"[]"#, #""x""#, #"{"v":1}"#, #"{"t":3,"v":1}"#, "{", ""])
    func illisible(_ texte: String) {
        #expect(MessagePasseur.lire(Data(texte.utf8)) == .illisible)
    }

    /// Lit des octets arrives en paquets de `taille` ; rend toutes les trames et la premiere erreur.
    static func lireTrames(_ octets: Data, par taille: Int) -> EnvoiPasseur.IssueFlux {
        var l = EnvoiPasseur.LectureTrames()
        var tout = EnvoiPasseur.IssueFlux(trames: [], erreur: nil)
        var i = octets.startIndex
        while i < octets.endIndex {
            let j = min(i + taille, octets.endIndex)
            let issue = l.ajouter(octets[i..<j])
            tout.trames += issue.trames
            if let e = issue.erreur { tout.erreur = e; break }
            i = j
        }
        return tout
    }

    @Test func trameDUnMessage() {
        let json = MessagePasseur.relire.json()
        #expect(EnvoiPasseur.trame(.relire) == Data("\(json.count)\n".utf8) + json)
        #expect(EnvoiPasseur.ligneJeton(Self.jeton) == Data("\(Self.jeton)\n".utf8))
    }

    /// Plusieurs trames dans un meme paquet : toutes, dans l'ordre.
    @Test func plusieursTramesDUnCoup() {
        let octets = EnvoiPasseur.trame(.etat(Self.etat)) + EnvoiPasseur.trame(.relire)
            + EnvoiPasseur.trame(.ouvertureSession(actif: true))
        let issue = Self.lireTrames(octets, par: octets.count)
        #expect(issue.erreur == nil)
        #expect(issue.trames.map(MessagePasseur.lire) == [.message(.etat(Self.etat)), .message(.relire),
                                                          .message(.ouvertureSession(actif: true))])
    }

    /// Une trame octet par octet, puis en paquets de 7 : la meme lecture.
    @Test(arguments: [1, 7])
    func trameOctetParOctet(_ taille: Int) {
        let octets = EnvoiPasseur.trame(.etat(Self.etat)) + EnvoiPasseur.trame(.relire)
        let issue = Self.lireTrames(octets, par: taille)
        #expect(issue.erreur == nil)
        #expect(issue.trames.count == 2)
    }

    /// Longueur nulle, trop grande, illisible, ou ligne de longueur sans fin au-dela de 16 chiffres : trame fausse,
    /// puis plus rien ne se lit.
    @Test(arguments: ["0\n{}", "\(EnvoiPasseur.tailleMax + 1)\n", "+5\n", "5 \n", "x\n", "12345678901234567"])
    func trameFausse(_ texte: String) {
        var l = EnvoiPasseur.LectureTrames()
        #expect(l.ajouter(Data(texte.utf8)).erreur == .trameFausse)
        #expect(l.ajouter(EnvoiPasseur.trame(.relire)) == EnvoiPasseur.IssueFlux(trames: [], erreur: .trameFausse))
    }

    /// Les trames completes avant une trame fausse sont rendues avec l'erreur.
    @Test func tramesAvantLErreur() {
        var l = EnvoiPasseur.LectureTrames()
        let issue = l.ajouter(EnvoiPasseur.trame(.relire) + Data("x\n".utf8))
        #expect(issue.trames.count == 1)
        #expect(issue.erreur == .trameFausse)
    }

    /// Cote app : le jeton d'abord (meme coupe en deux), puis les trames du meme paquet.
    @Test func fluxAvecJeton() {
        var l = EnvoiPasseur.LectureFlux(jeton: Self.jeton)
        let octets = EnvoiPasseur.ligneJeton(Self.jeton) + EnvoiPasseur.trame(.etat(Self.etat))
        #expect(l.ajouter(octets.prefix(10)) == EnvoiPasseur.IssueFlux(trames: [], erreur: nil))
        #expect(!l.jetonAccepte)
        let issue = l.ajouter(octets.dropFirst(10))
        #expect(l.jetonAccepte)
        #expect(issue.erreur == nil)
        #expect(issue.trames.map(MessagePasseur.lire) == [.message(.etat(Self.etat))])
    }

    /// Mauvais jeton, ou premiere ligne trop longue sans fin : jeton faux, et plus rien ensuite.
    @Test func fluxJetonFaux() {
        var l = EnvoiPasseur.LectureFlux(jeton: Self.jeton)
        #expect(l.ajouter(EnvoiPasseur.ligneJeton(String(repeating: "00", count: 32))).erreur == .jetonFaux)
        #expect(l.ajouter(EnvoiPasseur.ligneJeton(Self.jeton)).erreur == .jetonFaux)
        var long = EnvoiPasseur.LectureFlux(jeton: Self.jeton)
        #expect(long.ajouter(Data(String(repeating: "a", count: 65).utf8)).erreur == .jetonFaux)
        var vide = EnvoiPasseur.LectureFlux(jeton: "")
        #expect(vide.ajouter(Data("\n".utf8)).erreur == .jetonFaux, "un jeton attendu vide ne laisse rien passer")
    }
}
