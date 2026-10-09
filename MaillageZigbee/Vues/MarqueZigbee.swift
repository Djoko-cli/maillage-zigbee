import CoreGraphics

/// Le logo Zigbee (marque de la Connectivity Standards Alliance), badge de l'icone de la barre des menus.
/// Trace de SVG Repo (« Zigbee icon », d'apres Simple Icons, CC0), ses arcs convertis en courbes ; normalise a une
/// hauteur de 1, y vers le bas. Rempli tel quel : le Z est le vide entre les deux morceaux du disque.
enum MarqueZigbee {
    /// Largeur du trace pour une hauteur de 1.
    static let proportion: CGFloat = 0.9953

    /// Propriete calculee, pas `static let` : un `CGPath` statique partage n'est pas `Sendable`.
    static var trace: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.4971, y: 0.0002))
        p.addCurve(to: CGPoint(x: 0.1381, y: 0.1542), control1: CGPoint(x: 0.3614, y: 0.0000), control2: CGPoint(x: 0.2315, y: 0.0557))
        p.addCurve(to: CGPoint(x: 0.6917, y: 0.1400), control1: CGPoint(x: 0.4306, y: 0.1177), control2: CGPoint(x: 0.6131, y: 0.1299))
        p.addCurve(to: CGPoint(x: 0.8399, y: 0.2818), control1: CGPoint(x: 0.8480, y: 0.1643), control2: CGPoint(x: 0.8399, y: 0.2818))
        p.addLine(to: CGPoint(x: 0.3408, y: 0.7964))
        p.addCurve(to: CGPoint(x: 0.9156, y: 0.7701), control1: CGPoint(x: 0.4366, y: 0.8055), control2: CGPoint(x: 0.6282, y: 0.8116))
        p.addCurve(to: CGPoint(x: 0.9952, y: 0.5006), control1: CGPoint(x: 0.9676, y: 0.6899), control2: CGPoint(x: 0.9953, y: 0.5962))
        p.addCurve(to: CGPoint(x: 0.4971, y: 0.0002), control1: CGPoint(x: 0.9952, y: 0.2241), control2: CGPoint(x: 0.7723, y: 0.0002))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.5068, y: 0.1798))
        p.addCurve(to: CGPoint(x: 0.0917, y: 0.2099), control1: CGPoint(x: 0.4047, y: 0.1792), control2: CGPoint(x: 0.2663, y: 0.1858))
        p.addCurve(to: CGPoint(x: 0.0000, y: 0.5006), control1: CGPoint(x: 0.0333, y: 0.2919), control2: CGPoint(x: 0.0000, y: 0.3922))
        p.addCurve(to: CGPoint(x: 0.4971, y: 1.0000), control1: CGPoint(x: 0.0000, y: 0.7761), control2: CGPoint(x: 0.2218, y: 1.0000))
        p.addCurve(to: CGPoint(x: 0.8742, y: 0.8258), control1: CGPoint(x: 0.6483, y: 1.0000), control2: CGPoint(x: 0.7825, y: 0.9321))
        p.addCurve(to: CGPoint(x: 0.3014, y: 0.8420), control1: CGPoint(x: 0.5707, y: 0.8653), control2: CGPoint(x: 0.3821, y: 0.8521))
        p.addCurve(to: CGPoint(x: 0.1533, y: 0.7001), control1: CGPoint(x: 0.1442, y: 0.8186), control2: CGPoint(x: 0.1533, y: 0.7001))
        p.addLine(to: CGPoint(x: 0.6514, y: 0.1866))
        p.addCurve(to: CGPoint(x: 0.5068, y: 0.1798), control1: CGPoint(x: 0.6033, y: 0.1822), control2: CGPoint(x: 0.5550, y: 0.1799))
        p.closeSubpath()
        return p
    }
}
