import Foundation
import Testing
@testable import MaillageCoeur

/// Enregistrement TXT brut : chaque chaine precedee de sa longueur.
func txtBrut(_ chaines: [[UInt8]]) -> Data {
    Data(chaines.flatMap { [UInt8($0.count)] + $0 })
}

@Suite("Champs TXT et codage JSON")
struct AnnoncesTests {
    @Test func lectureDuBrut() throws {
        let xp: [UInt8] = [0x4B, 0x36, 0xA2, 0xB7, 0xFE, 0xFB, 0x20, 0x0B]
        let brut = txtBrut([
            Array("vn=Apple".utf8),
            Array("xp=".utf8) + xp,
            Array("Tv=1.4.0".utf8),       // cle en majuscules : gardee en minuscules
            Array("vn=Autre".utf8),       // doublon : la premiere occurrence compte
            Array("drapeau".utf8),        // cle sans "=" : valeur vide
            [],                           // chaine vide : ignoree
            Array("=sanscle".utf8),       // pas de cle : ignoree
        ])
        let t = ChampsTXT(brut: brut)
        #expect(t.texte("vn") == "Apple")
        #expect(t["xp"] == Data(xp))
        #expect(t["XP"] == Data(xp), "cles insensibles a la casse")
        #expect(t.texte("tv") == "1.4.0")
        #expect(t["drapeau"] == Data())
        #expect(t.valeurs.count == 4)
        #expect(ChampsTXT(brut: Data([5, 0x61])).estVide, "longueur qui deborde : lecture arretee")
        #expect(ChampsTXT(brut: txtBrut([Array("SII=6000".utf8)])).entier("sii") == 6000)
    }

    @Test func formatDesCaptures() throws {
        let t = ChampsTXT(["vn": Data("Apple".utf8),
                           "xp": Data([0x4B, 0x36, 0x00]),
                           "piege": Data("hex:41".utf8)])
        let json = try CodageJSON.encodeur().encode(t)
        #expect(String(decoding: json, as: UTF8.self)
                == #"{"piege":"hex:6865783A3431","vn":"Apple","xp":"hex:4B3600"}"#)
        #expect(try CodageJSON.decodeur().decode(ChampsTXT.self, from: json) == t)
        #expect(throws: DecodingError.self) {
            try CodageJSON.decodeur().decode(ChampsTXT.self, from: Data(#"{"xp":"hex:4B5"}"#.utf8))
        }
        #expect(Data(hexa: "4b36") == Data([0x4B, 0x36]))
        #expect(Data(hexa: "zz") == nil)
    }

    /// Les dates du codage JSON : en UTC, a la milliseconde ; une date sans millisecondes se lit aussi.
    @Test func datesALaMilliseconde() throws {
        struct Releve: Codable, Equatable {
            var date: Date
        }
        let date = try Date("2026-09-27T20:42:09Z", strategy: .iso8601).addingTimeInterval(0.5)
        let json = try CodageJSON.encodeur(lisible: true).encode(Releve(date: date))
        #expect(String(decoding: json, as: UTF8.self).contains(#""date" : "2026-09-27T20:42:09.500Z""#), "UTC, millisecondes")
        #expect(try CodageJSON.decodeur().decode(Releve.self, from: json) == Releve(date: date))
        let sansMs = Data(#"{"date":"2026-09-27T20:42:09Z"}"#.utf8)
        #expect(try CodageJSON.decodeur().decode(Releve.self, from: sansMs).date == date.addingTimeInterval(-0.5))
    }
}
