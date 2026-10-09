import SwiftUI

/// Apparition d'un element pose sur la vue (polissage B ; maquette de la fiche, carte A) : la fiche
/// glisse depuis le bas, un bandeau du haut depuis le haut, avec un fondu, en 0,3 s, sur la courbe de
/// la maquette (`cubic-bezier(.2, .8, .2, 1)`) ; ils repartent de meme. Avec « Reduire les
/// animations », un fondu simple, et rien d'autre ne glisse (`animationDuConteneur`). La legende s'ouvre
/// et se replie sur la meme courbe, en 0,45 s (`transitionLegende`).
enum Apparition: Equatable {
    /// Glisse depuis ce bord, de 110 % de sa hauteur, avec un fondu.
    case glisse(Edge)
    case fondu

    static let duree = 0.3

    static func pour(_ bord: Edge, reduire: Bool) -> Apparition {
        reduire ? .fondu : .glisse(bord)
    }

    var transition: AnyTransition {
        switch self {
        case .glisse(let bord): AnyTransition(Glisse(bord: bord))
        case .fondu: .opacity
        }
    }

    var animation: Animation {
        switch self {
        case .glisse: .timingCurve(0.2, 0.8, 0.2, 1, duration: Self.duree)
        case .fondu: .easeInOut(duration: Self.duree)
        }
    }

    /// La transition, avec son animation : elle se joue meme quand le conteneur n'en a pas (voir
    /// `animationDuConteneur`).
    var transitionAnimee: AnyTransition { transition.animation(animation) }

    /// L'animation de ce qui se decale autour d'un element qui parait ou repart (le fil et la ligne de niveau sous
    /// un bandeau ou la ligne de la tournee, la legende au-dessus de la fiche) : cela glisse avec lui, sur sa
    /// courbe. Avec « Reduire les animations », aucune : cela prend sa place d'un coup, et seul l'element se fond
    /// (`transitionAnimee`).
    static func animationDuConteneur(_ bord: Edge, reduire: Bool) -> Animation? {
        reduire ? nil : Apparition.glisse(bord).animation
    }

    // MARK: La legende

    /// L'ouverture et le repli de la legende (verification du 02/10) : un peu plus lents que la fiche et les
    /// bandeaux, Djoko trouvant l'ouverture « un poil trop fugace » a 0,3 s. Le recadrage qui l'accompagne prend la
    /// meme duree (`MoteurPieces.legendeBasculee`).
    static let dureeLegende = 0.45

    /// Sur la courbe de la maquette, en 0,45 s ; avec « Reduire les animations », un fondu.
    static func animationLegende(reduire: Bool) -> Animation {
        reduire ? .easeInOut(duration: dureeLegende) : .timingCurve(0.2, 0.8, 0.2, 1, duration: dureeLegende)
    }

    /// Le panneau parait depuis l'etiquette « Legende », en bas a gauche, et s'y replie : un fondu et un leger
    /// grossissement depuis ce coin ; l'etiquette fait de meme. Avec « Reduire les animations », un fondu seul.
    /// L'animation est portee par la transition : elle se joue meme quand le conteneur n'en a pas.
    static func transitionLegende(reduire: Bool) -> AnyTransition {
        let t: AnyTransition = reduire ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading))
        return t.animation(animationLegende(reduire: reduire))
    }

    /// La rangee du bas, qui ne garde que la legende : son contenu glisse avec elle quand elle s'ouvre ou se replie ;
    /// avec « Reduire les animations », rien : il prend sa place d'un coup.
    static func animationDuConteneurLegende(reduire: Bool) -> Animation? {
        reduire ? nil : animationLegende(reduire: false)
    }

    /// La courbe de la maquette, `cubic-bezier(.2, .8, .2, 1)` : l'avancement en fonction du temps, de 0
    /// a 1. Le moteur y fait glisser les marges de la vue avec la fiche, les bandeaux et la legende.
    static func courbe(_ temps: Double) -> Double {
        if temps <= 0 { return 0 }
        if temps >= 1 { return 1 }
        let x = temps
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        // L'abscisse croit avec t : on la resout par dichotomie.
        var bas = 0.0
        var haut = 1.0
        for _ in 0..<40 {
            let t = (bas + haut) / 2
            if bezier(t, 0.2, 0.2) < x { bas = t } else { haut = t }
        }
        return bezier((bas + haut) / 2, 0.8, 1)
    }
}

/// Glisse depuis un bord, de 110 % de sa hauteur, avec un fondu (maquette : `translateY(110%)`). Le
/// decalage ne touche que le dessin : la place de l'element, et l'obstacle qu'il fait aux noms, sont
/// ceux d'arrivee.
struct Glisse: Transition {
    let bord: Edge

    func body(content: Content, phase: TransitionPhase) -> some View {
        let hors = !phase.isIdentity
        let sens: CGFloat = bord == .top ? -1 : 1
        content
            .visualEffect { c, g in c.offset(y: hors ? sens * 1.1 * g.size.height : 0) }
            .opacity(hors ? 0 : 1)
    }
}
