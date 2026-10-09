import CryptoKit
import Foundation
import Security
import Testing
@testable import MaillageCoeur

/// Faux certificats des tests, generes une fois avec openssl (ECDSA P-256, SHA-256, valables cent ans), sans aucune cle
/// privee gardee : une fausse autorite (CN=Fausse autorite), une autre (CN=Autre autorite), et un faux pont dont le
/// sujet a pour nom commun un identifiant invente, en majuscules (`C0FFEEFFFE012345`), sans subjectAltName, signe par
/// la premiere, par la seconde, ou par lui-meme.
enum FauxCertificats {
    static let identifiant = "C0FFEEFFFE012345"

    static let autorite = certificat("""
        MIIB1jCCAXygAwIBAgIULjj/GlpJcTIKKNsd79oKqniJC28wCgYIKoZIzj0EAwIwSDELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTAgFw0yNjEwMDgwNjIxMzRaGA8yMTI2MDkxNDA2MjEzNFowSDELMAkGA1UEBhMC\
        RlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTBZMBMGByqGSM49AgEGCCqGSM49AwEH\
        A0IABGBT9Pe1LAtVQg4EKMhK3ukqjk+AJ+S5gRZ8gZVhlcTTz5+GI6uW2aXEcUNUUOCGUDfvDkHDqKu9hKzc2rQrmIajQjBAMA8GA1UdEwEB/wQF\
        MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSQPrCsYvcasV78JTWSCXz6P2N3dDAKBggqhkjOPQQDAgNIADBFAiB00+jNSAlpnKXWGJsC\
        13KJKBfbhzcmN2zxi/zosjpYGAIhAPXqUURQ9B3Tb+S2lmox1EhwETy1gc/RKkzG3aY3EhQO
        """)

    static let autreAutorite = certificat("""
        MIIB1TCCAXqgAwIBAgIUN5iMFQIAV29B0joS0ixx8423NqQwCgYIKoZIzj0EAwIwRzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxFzAVBgNVBAMMDkF1dHJlIGF1dG9yaXRlMCAXDTI2MTAwODA2MjEzNFoYDzIxMjYwOTE0MDYyMTM0WjBHMQswCQYDVQQGEwJG\
        UjEfMB0GA1UECgwWTWFpbGxhZ2UgWmlnYmVlIGVzc2FpczEXMBUGA1UEAwwOQXV0cmUgYXV0b3JpdGUwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNC\
        AAQruKqDKAvmWfWZ9+THngUCz9rXcV8rlCVWM3bErWHQBvaPEXhxhumphJ6gYtV14jNQd1XZNapcTPKnmmpiGoreo0IwQDAPBgNVHRMBAf8EBTAD\
        AQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUTTaLyqfVtTNhh5ptRMrAVIA8MrEwCgYIKoZIzj0EAwIDSQAwRgIhAOhWUi0s4wE2eB7L5jtv\
        ntjQyA6QHQeCe4UXaHg4cCmzAiEAmctDKk6jFtOyexBQ0X6n4hMjCjEYudwCISeXAxkSO3k=
        """)

    /// Signe par `autorite`.
    static let pont = certificat("""
        MIICADCCAaagAwIBAgIUfroxklfE3Xddk+Txi42cx/7B0CkwCgYIKoZIzj0EAwIwSDELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxGDAWBgNVBAMMD0ZhdXNzZSBhdXRvcml0ZTAgFw0yNjEwMDgwNjIxNDJaGA8yMTI2MDkxNDA2MjE0MlowPzELMAkGA1UEBhMC\
        RlIxFTATBgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABGlourwn\
        rPz1fTJ1HbF7+H+mx8Je1yAJcSwzRDRyQYjoaajBwFROiVc6fJEFI1IHGxKk4VXF3e/ZpU1geWmAfmujdTBzMAwGA1UdEwEB/wQCMAAwDgYDVR0P\
        AQH/BAQDAgOIMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBRM4/cv+4OaJuARiT0MHjQ4qLQPWDAfBgNVHSMEGDAWgBSQPrCsYvcasV78\
        JTWSCXz6P2N3dDAKBggqhkjOPQQDAgNIADBFAiB3iV5plyGWKWpd6rvMcMd2aKDx6vTYl4vKVsugerjTNQIhAJg0UBXC/P5afe4ThWQE11qV+PEh\
        MhasnW4KCC5FCmxV
        """)

    /// Le meme sujet, signe par `autreAutorite`.
    static let pontAutreAutorite = certificat("""
        MIIB/jCCAaWgAwIBAgIUJQXnJDlmurV9uJ7QIZK5TOTHRDEwCgYIKoZIzj0EAwIwRzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFpp\
        Z2JlZSBlc3NhaXMxFzAVBgNVBAMMDkF1dHJlIGF1dG9yaXRlMCAXDTI2MTAwODA2MjE0MloYDzIxMjYwOTE0MDYyMTQyWjA/MQswCQYDVQQGEwJG\
        UjEVMBMGA1UECgwMUG9udCBpbnZlbnRlMRkwFwYDVQQDDBBDMEZGRUVGRkZFMDEyMzQ1MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaWi6vCes\
        /PV9MnUdsXv4f6bHwl7XIAlxLDNENHJBiOhpqMHAVE6JVzp8kQUjUgcbEqThVcXd79mlTWB5aYB+a6N1MHMwDAYDVR0TAQH/BAIwADAOBgNVHQ8B\
        Af8EBAMCA4gwEwYDVR0lBAwwCgYIKwYBBQUHAwEwHQYDVR0OBBYEFEzj9y/7g5om4BGJPQweNDiotA9YMB8GA1UdIwQYMBaAFE02i8qn1bUzYYea\
        bUTKwFSAPDKxMAoGCCqGSM49BAMCA0cAMEQCIAcONmkrn+6W4YdVsNSHAGu6jGf4vaEXkulK8FJS0uAiAiAcpaJWWTTjEZ/ITYkoIPEr80zbiJhT\
        rXfNyUqrVTeZUw==
        """)

    /// Le meme sujet, auto-signe (un ancien pont).
    static let pontAutoSigne = certificat("""
        MIIBwjCCAWegAwIBAgIUOoK9kz24pbzmiE8hV6PrKOcC+VkwCgYIKoZIzj0EAwIwPzELMAkGA1UEBhMCRlIxFTATBgNVBAoMDFBvbnQgaW52ZW50\
        ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTAgFw0yNjEwMDgwNjIxNDJaGA8yMTI2MDkxNDA2MjE0MlowPzELMAkGA1UEBhMCRlIxFTATBgNV\
        BAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABGlourwnrPz1fTJ1HbF7\
        +H+mx8Je1yAJcSwzRDRyQYjoaajBwFROiVc6fJEFI1IHGxKk4VXF3e/ZpU1geWmAfmujPzA9MAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgOI\
        MB0GA1UdDgQWBBRM4/cv+4OaJuARiT0MHjQ4qLQPWDAKBggqhkjOPQQDAgNJADBGAiEAn6dB5sSeEz9H86dAGMvKjrx8DV0RQHkkCSD+Uz5hzxcC\
        IQC0NRqM9bdme+37A9ivWycgsH0Ydmiw4/gjLJkfYVVW6g==
        """)

    // Une seconde famille, generee a l'etape 3 (relecture de securite de l'etape 2, M7), cles privees effacees aussi :
    // une chaine feuille -> intermediaire -> racine, et une feuille qui en signe une autre.

    /// Racine des essais suivants (CN=Racine des essais), CA.
    static let racineEssais = certificat("""
        MIIB2jCCAYCgAwIBAgIUDU2lMrPX2iVZMIm17Ngaqxh/He0wCgYIKoZIzj0EAwIwSjELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGjAYBgNVBAMMEVJhY2luZSBkZXMgZXNzYWlzMCAXDTI2MTAwODA3NTAwMFoYDzIxMjYwOTE0MDc1MDAwWjBKMQswCQYDVQQGEwJG\
        UjEfMB0GA1UECgwWTWFpbGxhZ2UgWmlnYmVlIGVzc2FpczEaMBgGA1UEAwwRUmFjaW5lIGRlcyBlc3NhaXMwWTATBgcqhkjOPQIBBggqhkjOPQMBBw\
        NCAATsLpXf/SfoVWE8+raIj+/CRQUKtSr3usPiE+62b8jJcEdCNz1+177VbuXaJlnWhvvHoOA8kGKFP3PZmnDk+qgqo0IwQDAPBgNVHRMBAf8EBTAD\
        AQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUOuPDtdg8UqKWJy/TZ2GXExoRLX0wCgYIKoZIzj0EAwIDSAAwRQIhAOmbgrvTSp7hE4odsVVi/E\
        5c7hVvAIUgBMCAGriKThraAiA9SrwKqroPKMJU4jGqk49vB4dCFQe+zxZcjdVA5dbfXQ==
        """)

    /// Autorite intermediaire (CA, pathlen 0), signee par `racineEssais`.
    static let intermediaire = certificat("""
        MIICAjCCAamgAwIBAgIUE30FIJyF25eUe2J0crPNQDB3lMowCgYIKoZIzj0EAwIwSjELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGjAYBgNVBAMMEVJhY2luZSBkZXMgZXNzYWlzMCAXDTI2MTAwODA3NTAwMFoYDzIxMjYwOTE0MDc1MDAwWjBPMQswCQYDVQQGEwJG\
        UjEfMB0GA1UECgwWTWFpbGxhZ2UgWmlnYmVlIGVzc2FpczEfMB0GA1UEAwwWQXV0b3JpdGUgaW50ZXJtZWRpYWlyZTBZMBMGByqGSM49AgEGCCqGSM\
        49AwEHA0IABBA8hrIjTEcjp/l9MdPFi56r8jptnx1G1GG1d/vK1UVab8VDufbhkghWIXrLw2Dp6L4+jDQ+AhdhmPwaolAsyYCjZjBkMBIGA1UdEwEB\
        /wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSoEJkeNYw//g+J78DmEWvgZmQ2zzAfBgNVHSMEGDAWgBQ648O12DxSopYnL9NnYZ\
        cTGhEtfTAKBggqhkjOPQQDAgNHADBEAiAMH8Ucfg4q0R27JR2QPNjzv/7WKQ9KxO9bo5kbj7LHywIgCXSrZcIAJHqTpPEE7UqsCuKh+h4z1/TSlcne\
        nIgsCts=
        """)

    /// Le faux pont (CN=C0FFEEFFFE012345, non CA, serverAuth), signe par `intermediaire`.
    static let pontViaIntermediaire = certificat("""
        MIICCDCCAa2gAwIBAgIUMulsVVJ4PUhwbcB6zoHM7Qq7nsswCgYIKoZIzj0EAwIwTzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxHzAdBgNVBAMMFkF1dG9yaXRlIGludGVybWVkaWFpcmUwIBcNMjYxMDA4MDc1MDAwWhgPMjEyNjA5MTQwNzUwMDBaMD8xCzAJBgNV\
        BAYTAkZSMRUwEwYDVQQKDAxQb250IGludmVudGUxGTAXBgNVBAMMEEMwRkZFRUZGRkUwMTIzNDUwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAR5uZ\
        4f1Foc/szA/M44vSYDnp8NuqBljXqZp5g1T5HYsufQAUgH+5M7KiQ3UlYoDLl0ZqdrEzgPR0n9vBmrJgnfo3UwczAMBgNVHRMBAf8EAjAAMA4GA1Ud\
        DwEB/wQEAwIDiDATBgNVHSUEDDAKBggrBgEFBQcDATAdBgNVHQ4EFgQUUDsp7lpsXcRKKs9Lq2jZ0p1ZmGswHwYDVR0jBBgwFoAUqBCZHjWMP/4Pie\
        /A5hFr4GZkNs8wCgYIKoZIzj0EAwIDSQAwRgIhAMqbNyKP0/drpgZ7h1hQdsy4IzqHj2olxj4j+YOX56k8AiEA3Lwlh1Joe6pEILhWkC/Nnf+6xSHe\
        WEbOX2iQLhrUM/8=
        """)

    /// Un autre pont (CN=C0FFEEFFFE0BAD00, non CA), signe par `racineEssais` : celui d'un voisin.
    static let autrePont = certificat("""
        MIICCDCCAa6gAwIBAgIUE30FIJyF25eUe2J0crPNQDB3lMswCgYIKoZIzj0EAwIwSjELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGjAYBgNVBAMMEVJhY2luZSBkZXMgZXNzYWlzMCAXDTI2MTAwODA3NTAwMFoYDzIxMjYwOTE0MDc1MDAwWjBFMQswCQYDVQQGEwJG\
        UjEbMBkGA1UECgwSQXV0cmUgcG9udCBpbnZlbnRlMRkwFwYDVQQDDBBDMEZGRUVGRkZFMEJBRDAwMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE6E\
        PMC0ykS3CjwlMx9cimlNQGUXoNhBz5lz8PvArBVE767tgWv4ABIvpyuSjaLsGktZvg5WsHoPBwokD1H8iPlKN1MHMwDAYDVR0TAQH/BAIwADAOBgNV\
        HQ8BAf8EBAMCA4gwEwYDVR0lBAwwCgYIKwYBBQUHAwEwHQYDVR0OBBYEFBAVk7nqy7o+nBOIBMCv5qXRnl4OMB8GA1UdIwQYMBaAFDrjw7XYPFKili\
        cv02dhlxMaES19MAoGCCqGSM49BAMCA0gAMEUCIB06QhLy3i/hwrcuEfBCcrF+fEAgxW8tEZ4Mcl+tDXEWAiEAkVxMu2NA6zE2jOHPAoGuJi2WeSuF\
        wk2FQr+LzkL0e98=
        """)

    /// Le nom commun du faux pont, signe par la cle de `autrePont` (une feuille, pas une autorite).
    static let pontForgeParUnAutrePont = certificat("""
        MIIB/DCCAaOgAwIBAgIUIU0GxvcxUgmi5I0tQC0/8cQZQukwCgYIKoZIzj0EAwIwRTELMAkGA1UEBhMCRlIxGzAZBgNVBAoMEkF1dHJlIHBvbnQgaW\
        52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTBCQUQwMDAgFw0yNjEwMDgwNzUwMDBaGA8yMTI2MDkxNDA3NTAwMFowPzELMAkGA1UEBhMCRlIxFTAT\
        BgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABP5EvLN6PDUPU1HnPy\
        rLTCyqS26FhGKYm3Ro0eUyw90rveB9AYPOTRUpjukJlMMDoWM8Ob9HB0XuTJR7QGcoTB+jdTBzMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgOI\
        MBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBQD86G37+qwvsY8RbuRuihJ3D+E0TAfBgNVHSMEGDAWgBQQFZO56su6PpwTiATAr+al0Z5eDj\
        AKBggqhkjOPQQDAgNHADBEAiAZeji3gsJz6BdwMA0grk6b/CGy7AiPtGQJpkms/0h69wIgZh0vQHgSSLOtIfAuSByY+Ch6XUJ7yNUdR4bFmw0saGA=
        """)

    // Une troisieme famille, generee a la relecture finale (M6 de la relecture de securite), cles privees effacees
    // aussi : une autorite, et trois feuilles au nom commun du faux pont qu'elle signe, qui ne different que par leur
    // role (Basic Constraints, Key Usage, Extended Key Usage).

    /// Autorite des roles (CN=Autorite des roles), CA : keyCertSign, cRLSign.
    static let autoriteRoles = certificat("""
        MIIB2zCCAYKgAwIBAgIUHz14NMALKNYcJClu5f2HgTfcgGkwCgYIKoZIzj0EAwIwSzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGzAZBgNVBAMMEkF1dG9yaXRlIGRlcyByb2xlczAgFw0yNjEwMDgyMDMxMjBaGA8yMTI2MDkxNDIwMzEyMFowSzELMAkGA1UEBhMC\
        RlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2JlZSBlc3NhaXMxGzAZBgNVBAMMEkF1dG9yaXRlIGRlcyByb2xlczBZMBMGByqGSM49AgEGCCqGSM49Aw\
        EHA0IABJ8yF5lL73Uym1fg2cOHTB8Sq7uKsGe9oYl3vbDwelxv4yVzGIP39rdsAb1DCCp+U2nrl7uK8uK7h+7FA82qfPOjQjBAMA8GA1UdEwEB/wQF\
        MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTqdveuRjYXmUmBgVF9Z0+lqZQ3szAKBggqhkjOPQQDAgNHADBEAiBzPwuBZyruzxL5x3JJqE\
        IoLWp/XxD1gvI/s72FPgbjsQIgbCTAUR1ulPwpTuqbcrwtlPwia9Mjjr0LxnNkq8iV8Uo=
        """)

    /// Feuille de serveur TLS, comme le Bridge Pro : CA:FALSE, digitalSignature, serverAuth ; signee par `autoriteRoles`.
    static let pontServeur = certificat("""
        MIICBDCCAamgAwIBAgIUFyPw4GjXtWpVCFbUtKem3fq+vuowCgYIKoZIzj0EAwIwSzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGzAZBgNVBAMMEkF1dG9yaXRlIGRlcyByb2xlczAgFw0yNjEwMDgyMDMxMjBaGA8yMTI2MDkxNDIwMzEyMFowPzELMAkGA1UEBhMC\
        RlIxFTATBgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCTMvTqY+b\
        B5DLY4Y+MVb5jr4p7bAZgQZcCccL9AJ6yCV18iak8QaZcHmdCWwh7hSu7YHQpZ72JJUXnA3YFr0o2jdTBzMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/\
        BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBS6+1J57a/z78Ozj9Gzhm4mvYhbZDAfBgNVHSMEGDAWgBTqdveuRjYXmUmBgVF9Z0\
        +lqZQ3szAKBggqhkjOPQQDAgNJADBGAiEAgVex9ilG4PF/yy1pkz1Pyqxv6w++DLDEWnHdRJd0pMgCIQCYR9W1fO9q2Hm0lSJFgKFYP4YdGnjJMc9J\
        Pi7oMQJ0IQ==
        """)

    /// Feuille marquee autorite : CA:TRUE, digitalSignature et keyCertSign, serverAuth ; signee par `autoriteRoles`.
    static let pontAutorite = certificat("""
        MIICBTCCAaygAwIBAgIUFyPw4GjXtWpVCFbUtKem3fq+vugwCgYIKoZIzj0EAwIwSzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGzAZBgNVBAMMEkF1dG9yaXRlIGRlcyByb2xlczAgFw0yNjEwMDgyMDMxMjBaGA8yMTI2MDkxNDIwMzEyMFowPzELMAkGA1UEBhMC\
        RlIxFTATBgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABLnh6gOjLC\
        FVD6g+cjdWrwwSD4mXKu/z1XUobWIoJzJdOIVVgzkaELPhOAV6oQXeZWoOpTvPwd3Dgkl56+mIWcyjeDB2MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P\
        AQH/BAQDAgKEMBMGA1UdJQQMMAoGCCsGAQUFBwMBMB0GA1UdDgQWBBQoQk8M5XG7EfDPMcKRS0McodSrNzAfBgNVHSMEGDAWgBTqdveuRjYXmUmBgV\
        F9Z0+lqZQ3szAKBggqhkjOPQQDAgNHADBEAiA9svxEpaPX3+hhJ/vb8JuVzCm+wvZvzcPuMiFFBA0jYgIgF/FQ4IqjelAL3Az1D/aVxw0xmw92L0U8\
        io6YOxt8C3w=
        """)

    /// Feuille de client TLS : CA:FALSE, digitalSignature, clientAuth seulement ; signee par `autoriteRoles`.
    static let pontClient = certificat("""
        MIICBDCCAamgAwIBAgIUFyPw4GjXtWpVCFbUtKem3fq+vukwCgYIKoZIzj0EAwIwSzELMAkGA1UEBhMCRlIxHzAdBgNVBAoMFk1haWxsYWdlIFppZ2\
        JlZSBlc3NhaXMxGzAZBgNVBAMMEkF1dG9yaXRlIGRlcyByb2xlczAgFw0yNjEwMDgyMDMxMjBaGA8yMTI2MDkxNDIwMzEyMFowPzELMAkGA1UEBhMC\
        RlIxFTATBgNVBAoMDFBvbnQgaW52ZW50ZTEZMBcGA1UEAwwQQzBGRkVFRkZGRTAxMjM0NTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEWWwtOe0J\
        Doofea2oAMRBFa7S9ryn24S6oMWhOiK09fzW+ub5AYWWNtDn3Hz1j76OUqWElpv/fvOAk0oI19lUqjdTBzMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/\
        BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMCMB0GA1UdDgQWBBQ8ledcftrvCp3AbaLe9Oyb2V+awTAfBgNVHSMEGDAWgBTqdveuRjYXmUmBgVF9Z0\
        +lqZQ3szAKBggqhkjOPQQDAgNJADBGAiEA1LVrLnAxpJfh1QMEiROJsR2W3nRd0bLl6OPVilffSGACIQDwRKQAAQqCjBw6fPWfSphUsFka0bBbhv8s\
        7zUi6di9Uw==
        """)

    static func certificat(_ base64: String) -> SecCertificate {
        SecCertificateCreateWithData(nil, Data(base64Encoded: base64)! as CFData)!
    }
}

@Suite("Certificat du pont Hue : racines de Signify, chaine, nom commun du sujet")
struct CertificatPontTests {
    typealias F = FauxCertificats
    /// Date fixe des verifications (les faux certificats valent de 2026 a 2126).
    static let date = Date(timeIntervalSince1970: 1_900_000_000)

    /// Les deux racines integrees sont bien celles de Signify : leurs empreintes SHA-256 du DER, recoupees dans trois
    /// sources independantes ; et ce sont bien des certificats.
    @Test func empreintesDesRacines() {
        func empreinte(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02X", $0) }.joined() }
        #expect(empreinte(RacinesSignify.rootBridge) == "F0BD8E6509E82F774D63BC009D5388C969FE3DCF7D6D541D6351B72B898D8ACF")
        #expect(empreinte(RacinesSignify.hueRootCA01) == "D8B89448B2AF8E1676185AC07219EE9DCBC8F01C122A026A2A4B7B5CFE0328B8")
        let noms = RacinesSignify.certificats().map { c -> String in
            var n: CFString?
            _ = SecCertificateCopyCommonName(c, &n)
            return n as String? ?? ""
        }
        #expect(noms == ["root-bridge", "Hue Root CA 01"])
    }

    /// Le faux pont, signe par la fausse autorite : accepte, l'identifiant attendu ecrit dans une autre casse (en
    /// minuscules, comme le TXT Bonjour) ; sans identifiant attendu (saisie manuelle), accepte et l'identifiant rendu.
    @Test func accepteSansEgardALaCasse() {
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: "c0ffeefffe012345", racines: [F.autorite],
                                        date: Self.date) == .accepte(identifiant: F.identifiant))
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: F.identifiant, racines: [F.autorite],
                                        date: Self.date) == .accepte(identifiant: F.identifiant))
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: nil, racines: [F.autorite, F.autreAutorite],
                                        date: Self.date) == .accepte(identifiant: F.identifiant))
        // La chaine presentee avec son autorite (comme un serveur qui envoie aussi l'intermediaire).
        #expect(CertificatPont.verifier(chaine: [F.pont, F.autorite], attendu: F.identifiant, racines: [F.autorite],
                                        date: Self.date).accepte)
    }

    /// Une chaine feuille -> intermediaire -> racine (un pont qui presente l'intermediaire de son autorite) : acceptee ;
    /// sans l'intermediaire, refusee (rien n'est telecharge) ; l'intermediaire seul en ancre suffit aussi.
    @Test func chaineAvecIntermediaire() {
        #expect(CertificatPont.verifier(chaine: [F.pontViaIntermediaire, F.intermediaire], attendu: F.identifiant,
                                        racines: [F.racineEssais], date: Self.date) == .accepte(identifiant: F.identifiant))
        #expect(CertificatPont.verifier(chaine: [F.pontViaIntermediaire], attendu: F.identifiant,
                                        racines: [F.racineEssais], date: Self.date) == .nonSigne)
        #expect(CertificatPont.verifier(chaine: [F.pontViaIntermediaire], attendu: nil, racines: [F.intermediaire],
                                        date: Self.date) == .accepte(identifiant: F.identifiant))
    }

    /// Le proprietaire d'un vrai pont (une feuille signee par la racine) forge le nom commun d'un autre pont en signant
    /// avec la cle du sien : refuse, une feuille n'est pas une autorite ; son propre pont reste accepte sous son nom.
    @Test func refuseUneFeuilleCommeAutorite() {
        #expect(CertificatPont.verifier(chaine: [F.pontForgeParUnAutrePont, F.autrePont], attendu: F.identifiant,
                                        racines: [F.racineEssais], date: Self.date) == .nonSigne)
        #expect(CertificatPont.verifier(chaine: [F.pontForgeParUnAutrePont, F.autrePont], attendu: nil,
                                        racines: [F.racineEssais], date: Self.date) == .nonSigne)
        #expect(CertificatPont.verifier(chaine: [F.autrePont], attendu: nil, racines: [F.racineEssais], date: Self.date)
                == .accepte(identifiant: "C0FFEEFFFE0BAD00"))
    }

    /// Un autre identifiant que celui du certificat : refuse.
    @Test func refuseUnAutreNom() {
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: "C0FFEEFFFE012346", racines: [F.autorite],
                                        date: Self.date) == .autrePont(vu: F.identifiant))
        #expect(!CertificatPont.verifier(chaine: [F.pont], attendu: "", racines: [F.autorite], date: Self.date).accepte)
    }

    /// Le meme sujet, signe par une autre autorite : refuse, meme avec le bon identifiant ; et refuse par les vraies
    /// racines de Signify ; et sans racine du tout.
    @Test func refuseUneAutreAutorite() {
        #expect(CertificatPont.verifier(chaine: [F.pontAutreAutorite], attendu: F.identifiant, racines: [F.autorite],
                                        date: Self.date) == .nonSigne)
        // L'autre autorite presentee dans la chaine ne devient pas une ancre.
        #expect(CertificatPont.verifier(chaine: [F.pontAutreAutorite, F.autreAutorite], attendu: F.identifiant,
                                        racines: [F.autorite], date: Self.date) == .nonSigne)
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: F.identifiant, racines: RacinesSignify.certificats(),
                                        date: Self.date) == .nonSigne, "les racines du systeme ne comptent pas non plus")
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: F.identifiant, racines: [], date: Self.date) == .nonSigne)
        #expect(CertificatPont.verifier(chaine: [], attendu: F.identifiant, racines: [F.autorite], date: Self.date) == .nonSigne)
    }

    /// Un certificat auto-signe dont le nom commun est l'identifiant (un ancien pont) : refuse, et reconnu comme tel
    /// (« pont trop ancien »).
    @Test func refuseUnAutoSigne() {
        #expect(CertificatPont.verifier(chaine: [F.pontAutoSigne], attendu: F.identifiant, racines: [F.autorite],
                                        date: Self.date) == .autoSigne)
        #expect(CertificatPont.verifier(chaine: [F.pontAutoSigne], attendu: F.identifiant,
                                        racines: RacinesSignify.certificats(), date: Self.date) == .autoSigne)
    }

    /// Une autorite presentee comme feuille (une racine de Signify elle-meme) : sa chaine est valide, mais son nom
    /// commun n'est pas un identifiant de pont.
    @Test func refuseUneFeuilleSansIdentifiant() {
        let racines = RacinesSignify.certificats()
        #expect(CertificatPont.verifier(chaine: [racines[0]], attendu: nil, racines: racines, date: Self.date)
                == .sansIdentifiant)
        #expect(CertificatPont.verifier(chaine: [F.autorite], attendu: nil, racines: [F.autorite], date: Self.date)
                == .sansIdentifiant)
    }

    /// Relecture finale (M6 de la relecture de securite) : une feuille signee par l'autorite, au bon nom commun, mais qui
    /// n'est pas une feuille de serveur TLS est refusee (`pasUnServeur`) : marquee autorite, ou sans serverAuth. La
    /// feuille de serveur de la meme autorite passe, comme les faux ponts des autres familles (deja serverAuth).
    @Test func refuseUneFeuilleQuiNEstPasUnServeur() {
        #expect(CertificatPont.verifier(chaine: [F.pontServeur], attendu: F.identifiant, racines: [F.autoriteRoles],
                                        date: Self.date) == .accepte(identifiant: F.identifiant))
        for attendu in [F.identifiant, nil] {
            #expect(CertificatPont.verifier(chaine: [F.pontAutorite], attendu: attendu, racines: [F.autoriteRoles],
                                            date: Self.date) == .pasUnServeur, "feuille marquee autorite")
            #expect(CertificatPont.verifier(chaine: [F.pontClient], attendu: attendu, racines: [F.autoriteRoles],
                                            date: Self.date) == .pasUnServeur, "feuille sans serverAuth")
        }
        #expect(CertificatPont.estFeuilleServeur(F.pontServeur) && CertificatPont.estFeuilleServeur(F.pont)
                && CertificatPont.estFeuilleServeur(F.pontViaIntermediaire) && CertificatPont.estFeuilleServeur(F.autrePont))
        #expect(!CertificatPont.estFeuilleServeur(F.pontAutorite) && !CertificatPont.estFeuilleServeur(F.pontClient))
        #expect(!CertificatPont.estFeuilleServeur(F.autoriteRoles) && !CertificatPont.estFeuilleServeur(F.autorite))
    }

    /// Hors de sa periode de validite, la chaine est refusee.
    @Test func refuseHorsValidite() {
        #expect(CertificatPont.verifier(chaine: [F.pont], attendu: F.identifiant, racines: [F.autorite],
                                        date: Date(timeIntervalSince1970: 1_700_000_000)) == .nonSigne)
    }

    /// Un identifiant de pont : 16 hexa, rendu en majuscules.
    @Test func identifiant() {
        #expect(CertificatPont.identifiant("c0ffeefffe012345") == F.identifiant)
        #expect(CertificatPont.identifiant(" C0FFEEFFFE012345 ") == F.identifiant)
        #expect(CertificatPont.identifiant("C0FFEEFFFE01234") == nil)
        #expect(CertificatPont.identifiant("C0FFEEFFFE01234G") == nil)
        #expect(CertificatPont.identifiant("root-bridge") == nil)
        #expect(CertificatPont.identifiant("") == nil)
    }
}
