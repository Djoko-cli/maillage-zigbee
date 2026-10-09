/// Configuration de la compilation des tests : les temps de calcul de la scene ne se mesurent
/// qu'optimises (Release, `outils/mesurer.sh`) ; en Debug, ces tests sont sautes.
enum Compilation {
    static var optimisee: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}
