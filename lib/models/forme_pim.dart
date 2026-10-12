/// Les quatre formes des particules PIM.
///
/// L'une est la forme principale (choisie dans les Paramètres, la sphère
/// par défaut) : PIM la garde au repos comme pendant l'écoute, la réflexion
/// et la parole. Les trois autres peuvent apparaître rarement, quelques
/// secondes, avant le retour à la forme principale.
///
/// Chaque forme définit sa part dans le tirage des apparitions, ses durées
/// (s) quand elle apparaît, et l'inclinaison supplémentaire de la vue qui
/// la met en valeur.
enum FormePim {
  sphere(
    libelle: 'Sphère',
    poids: 50,
    preparation: 0.8,
    formation: 2.4,
    tenue: 5.0,
    retour: 2.6,
    inclinaison: 0,
  ),

  /// Cube : durées d'origine, inchangées.
  cube(
    libelle: 'Cube 3D',
    poids: 50,
    preparation: 1.0,
    formation: 3.0,
    tenue: 5.5,
    retour: 3.2,
    inclinaison: 0.28,
  ),

  /// Tétraèdre régulier : 4 sommets, 6 arêtes, 4 faces, rotation lente.
  tetraedre(
    libelle: 'Tétraèdre 3D',
    poids: 35,
    preparation: 0.8,
    formation: 2.4,
    tenue: 5.0,
    retour: 2.6,
    // Vue légèrement par-dessous : le sommet avant de la base descend,
    // deux faces se présentent.
    inclinaison: -0.6,
  ),

  /// Réacteur Arc : anneau, triangle, noyau ; tourné vers l'utilisateur,
  /// avec un léger mouvement 3D.
  reacteur(
    libelle: 'Réacteur Arc',
    poids: 15,
    preparation: 0.8,
    formation: 2.4,
    tenue: 5.0,
    retour: 2.6,
    inclinaison: 0,
  );

  const FormePim({
    required this.libelle,
    required this.poids,
    required this.preparation,
    required this.formation,
    required this.tenue,
    required this.retour,
    required this.inclinaison,
  });

  final String libelle;

  /// Part dans le tirage d'une apparition (relative aux autres formes).
  final int poids;
  final double preparation, formation, tenue, retour;
  final double inclinaison;

  /// Forme qui apparaît pour [u] uniforme dans [0, 1[, parmi toutes sauf
  /// [principale] (jamais tirée). Sphère principale : 50 % cube, 35 %
  /// tétraèdre, 15 % réacteur, comme à l'origine.
  static FormePim tirer(double u, {FormePim principale = FormePim.sphere}) {
    final candidates = [
      for (final f in values)
        if (f != principale) f,
    ];
    final total = candidates.fold<int>(0, (s, f) => s + f.poids);
    var cumul = 0.0;
    for (final f in candidates) {
      cumul += f.poids / total;
      if (u < cumul) return f;
    }
    return candidates.last;
  }
}
