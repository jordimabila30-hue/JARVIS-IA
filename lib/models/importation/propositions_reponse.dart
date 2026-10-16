/// Propositions de messages à envoyer, préparées par JARVIS quand
/// l'utilisateur lui demande de l'aider à répondre ou à relancer une
/// conversation WhatsApp jointe (phases 3 et 5.1).
///
/// Reçues du serveur (événement `propositions`, ou relues avec la réponse
/// enregistrée) : le serveur prépare TOUTES les combinaisons ton × longueur
/// (par lots) avant de les rendre disponibles, donc changer de ton ou de
/// longueur n'appelle jamais l'IA. Chaque combinaison porte exactement
/// [parTon] propositions distinctes ; jamais d'ensemble à moitié affiché :
/// une génération interrompue (quota, erreur) arrive [incomplet], sans
/// propositions, et l'interface propose « Reprendre ».
/// Anciennes propositions (avant les longueurs) : [longueurs] vide.
class PropositionsReponse {
  const PropositionsReponse({
    required this.mode,
    required this.tons,
    this.longueurs = const [],
    this.ensemble,
    this.incomplets = const [],
    this.etat = EtatPropositions.complet,
    this.raison,
  });

  static const parTon = 3;

  /// Complet (affichable) ou génération interrompue (à reprendre).
  final EtatPropositions etat;

  /// Génération incomplète : `quota`, `erreur` ou `invalide`.
  final String? raison;

  bool get incomplet => etat == EtatPropositions.incomplet;

  final ModeProposition mode;
  final List<TonPropose> tons;

  /// Longueurs disponibles (court, moyen, long), dans cet ordre ; vide pour
  /// les anciennes propositions.
  final List<LongueurProposition> longueurs;

  /// Identifiant de l'ensemble (réponse de JARVIS qui le porte).
  final String? ensemble;

  /// Tons que le serveur n'a pas pu préparer entièrement (signalés).
  final List<String> incomplets;

  /// La proposition déclarée envoyée de cet ensemble (une seule, règle du
  /// serveur), ou null.
  PropositionReponse? get choisie {
    for (final t in tons) {
      for (final p in t.propositions) {
        if (p.envoyee != null) return p;
      }
    }
    return null;
  }

  TonPropose? tonDe(PropositionReponse p) {
    for (final t in tons) {
      if (t.propositions.any((x) => x.id == p.id)) return t;
    }
    return null;
  }

  /// Longueur affichée par défaut : Moyen s'il existe.
  LongueurProposition? get longueurParDefaut => longueurs.isEmpty
      ? null
      : longueurs.contains(LongueurProposition.moyen)
      ? LongueurProposition.moyen
      : longueurs.first;

  /// Les trois propositions du ton [ton] et de la longueur [longueur].
  List<PropositionReponse> affichees(
    TonPropose ton,
    LongueurProposition? longueur,
  ) {
    final lo = longueurs.contains(longueur) ? longueur : longueurParDefaut;
    return [
      for (final p in ton.propositions)
        if (p.longueur == lo) p,
    ];
  }

  /// Les mêmes propositions, celle d'identifiant [id] déclarée envoyée le
  /// [date] (null : déclaration annulée).
  PropositionsReponse avecEnvoyee(String id, DateTime? date) =>
      PropositionsReponse(
        mode: mode,
        longueurs: longueurs,
        ensemble: ensemble,
        incomplets: incomplets,
        etat: etat,
        raison: raison,
        tons: [
          for (final t in tons)
            TonPropose(
              nom: t.nom,
              propositions: [
                for (final p in t.propositions)
                  p.id == id ? p.avecEnvoyee(date) : p,
              ],
            ),
        ],
      );

  /// Signature des statuts (comparaison après actualisation).
  String get statuts => [
    etat.name,
    for (final t in tons)
      for (final p in t.propositions) '${p.id}:${p.envoyee}',
  ].join('|');

  /// Null si rien d'exploitable (jamais de propositions bancales).
  static PropositionsReponse? depuisJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final mode = j['mode'] == 'relance'
        ? ModeProposition.relance
        : ModeProposition.reponse;
    if (j['statut'] == 'incomplet') {
      return PropositionsReponse(
        mode: mode,
        tons: const [],
        ensemble: j['ensemble'] as String?,
        etat: EtatPropositions.incomplet,
        raison: j['raison'] as String?,
      );
    }
    final tons = [
      if (j['tons'] case final List liste)
        for (final t in liste) ?TonPropose.depuisJson(t),
    ];
    if (tons.isEmpty) return null;
    return PropositionsReponse(
      mode: mode,
      tons: tons,
      longueurs: [
        for (final l in LongueurProposition.values)
          if ((j['longueurs'] as List?)?.contains(l.name) ?? false) l,
      ],
      ensemble: j['ensemble'] as String?,
      incomplets: [
        if (j['incomplets'] case final List l)
          for (final n in l)
            if (n is String) n,
      ],
    );
  }
}

/// Ensemble prêt, ou génération interrompue à reprendre.
enum EtatPropositions { complet, incomplet }

enum ModeProposition {
  /// L'interlocuteur attend une réponse.
  reponse('Idées de réponse'),

  /// Reprendre une discussion restée sans suite.
  relance('Idées de relance');

  const ModeProposition(this.titre);
  final String titre;
}

/// Longueur d'une proposition (phase 5.1).
enum LongueurProposition {
  court('Court'),
  moyen('Moyen'),
  long('Long');

  const LongueurProposition(this.libelle);
  final String libelle;

  static LongueurProposition? depuis(Object? nom) {
    for (final l in values) {
      if (l.name == nom) return l;
    }
    return null;
  }
}

/// Un ton (« Naturel », « Professionnel »…) et ses propositions (trois par
/// longueur).
class TonPropose {
  const TonPropose({required this.nom, required this.propositions});

  final String nom;
  final List<PropositionReponse> propositions;

  static TonPropose? depuisJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final nom = j['nom'];
    if (nom is! String || nom.trim().isEmpty) return null;
    final propositions = [
      if (j['propositions'] case final List liste)
        for (final p in liste) ?PropositionReponse.depuisJson(p),
    ];
    // Trois par longueur, les trois longueurs toujours présentes (une seule
    // « longueur » nulle pour l'ancien format) : jamais un ton à moitié.
    final parLongueur = <LongueurProposition?, int>{};
    for (final p in propositions) {
      parLongueur[p.longueur] = (parLongueur[p.longueur] ?? 0) + 1;
    }
    final nouveau = parLongueur.keys.any((l) => l != null);
    final valide =
        parLongueur.isNotEmpty &&
        parLongueur.values.every((n) => n == PropositionsReponse.parTon) &&
        (!nouveau ||
            LongueurProposition.values.every(parLongueur.containsKey));
    if (!valide) return null;
    return TonPropose(nom: nom.trim(), propositions: propositions);
  }
}

/// Un message prêt à envoyer, et l'approche qu'il suit (« rebondir sur la
/// blague »).
class PropositionReponse {
  const PropositionReponse({
    required this.texte,
    this.id = '',
    this.approche,
    this.appuis = const [],
    this.envoyee,
    this.longueur,
    this.rang = 0,
  });

  /// Identifiant unique et stable donné par le serveur (vide : ancienne
  /// donnée sans identifiant, jamais déclarable).
  final String id;
  final String texte;
  final String? approche;

  /// Rangs des messages WhatsApp sur lesquels elle s'appuie (vérifiés par
  /// le serveur) : servent à justifier la proposition.
  final List<int> appuis;

  /// Date à laquelle l'utilisateur a DÉCLARÉ l'avoir envoyée (appui long),
  /// confirmée par le serveur ; null : pas déclarée. Jamais une livraison
  /// vérifiée par WhatsApp.
  final DateTime? envoyee;

  /// Longueur (null : ancienne proposition) et rang parmi les trois.
  final LongueurProposition? longueur;
  final int rang;

  PropositionReponse avecEnvoyee(DateTime? date) => PropositionReponse(
    texte: texte,
    id: id,
    approche: approche,
    appuis: appuis,
    envoyee: date,
    longueur: longueur,
    rang: rang,
  );

  static PropositionReponse? depuisJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final texte = j['texte'];
    if (texte is! String || texte.trim().isEmpty) return null;
    final approche = j['approche'];
    final envoyee = j['envoyee'];
    return PropositionReponse(
      texte: texte.trim(),
      id: j['id'] is String ? j['id'] as String : '',
      approche: approche is String && approche.trim().isNotEmpty
          ? approche.trim()
          : null,
      appuis: [
        if (j['appuis'] case final List liste)
          for (final a in liste)
            if (a case {'message_order': final num ordre}) ordre.toInt(),
      ],
      envoyee: envoyee is String ? DateTime.tryParse(envoyee)?.toLocal() : null,
      longueur: LongueurProposition.depuis(j['longueur']),
      rang: (j['rang'] as num?)?.toInt() ?? 0,
    );
  }
}
