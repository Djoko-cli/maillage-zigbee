import Foundation
import Security

/// Les deux racines publiques de Signify qui signent les certificats des ponts Hue (spec de l'app, section 5), en DER
/// encode en base64. Recoupees dans trois sources independantes (meme empreinte SHA-256 du DER) ; le test
/// `CertificatPontTests.empreintesDesRacines` les verifie :
/// - `root-bridge` (C=NL, O=Philips Hue, CN=root-bridge, valable jusqu'en 2038),
///   `F0BD8E6509E82F774D63BC009D5388C969FE3DCF7D6D541D6351B72B898D8ACF` ;
/// - `Hue Root CA 01` (C=NL, O=Signify Hue, CN=Hue Root CA 01, valable jusqu'en 2050),
///   `D8B89448B2AF8E1676185AC07219EE9DCBC8F01C122A026A2A4B7B5CFE0328B8`.
/// Ce sont les seules ancres de confiance du client du pont : aucune racine du systeme n'est acceptee.
public enum RacinesSignify {
    public static let rootBridge = Data(base64Encoded: """
        MIICMjCCAdigAwIBAgIUO7FSLbaxikuXAljzVaurLXWmFw4wCgYIKoZIzj0EAwIwOTELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1BoaWxpcHMgSHVl\
        MRQwEgYDVQQDDAtyb290LWJyaWRnZTAiGA8yMDE3MDEwMTAwMDAwMFoYDzIwMzgwMTE5MDMxNDA3WjA5MQswCQYDVQQGEwJOTDEUMBIGA1UECgwL\
        UGhpbGlwcyBIdWUxFDASBgNVBAMMC3Jvb3QtYnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjNw2tx2AplOf9x86aTdvEcL1FU65QDxz\
        iKvBpW9XXSIcibAeQiKxegpq8Exbr9v6LBnYbna2VcaK0G22jOKkTqOBuTCBtjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNV\
        HQ4EFgQUZ2ONTFrDT6o8ItRnKfqWKnHFGmQwdAYDVR0jBG0wa4AUZ2ONTFrDT6o8ItRnKfqWKnHFGmShPaQ7MDkxCzAJBgNVBAYTAk5MMRQwEgYD\
        VQQKDAtQaGlsaXBzIEh1ZTEUMBIGA1UEAwwLcm9vdC1icmlkZ2WCFDuxUi22sYpLlwJY81Wrqy11phcOMAoGCCqGSM49BAMCA0gAMEUCIEBYYEOs\
        a07TH7E5MJnGw557lVkORgit2Rm1h3B2sFgDAiEA1Fj/C3AN5psFMjo0//mrQebo0eKd3aWRx+pQY08mk48=
        """)!

    public static let hueRootCA01 = Data(base64Encoded: """
        MIIBzDCCAXOgAwIBAgICEAAwCgYIKoZIzj0EAwIwPDELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYDVQQDDA5IdWUgUm9v\
        dCBDQSAwMTAgFw0yNTAyMjUwMDAwMDBaGA8yMDUwMTIzMTIzNTk1OVowPDELMAkGA1UEBhMCTkwxFDASBgNVBAoMC1NpZ25pZnkgSHVlMRcwFQYD\
        VQQDDA5IdWUgUm9vdCBDQSAwMTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABFfOO0jfSAUXGQ9kjEDzyBrcMQ3ItyA5krE+cyvb1Y3xFti7KlAa\
        d8UOnAx0FBLn7HZrlmIwm1QnX0fK3LPM13mjYzBhMB0GA1UdDgQWBBTF1pSpsCASX/z0VHLigxU2CAaqoTAfBgNVHSMEGDAWgBTF1pSpsCASX/z0\
        VHLigxU2CAaqoTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAgNHADBEAiAk7duT+IHbOGO4UUuGLAEpyYejGZK9\
        Z7V9oSfnvuQ5BQIgIYSgwwxHXm73/JgcU9lAM6c8Bmu3UE3kBIUwBs1qXFw=
        """)!

    /// Les deux racines, en DER.
    public static let der: [Data] = [rootBridge, hueRootCA01]

    /// Les deux racines, en certificats (cree a chaque appel : `SecCertificate` n'est pas `Sendable`).
    public static func certificats() -> [SecCertificate] {
        der.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }
}
