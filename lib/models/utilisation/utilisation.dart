/// Utilisation de l'IA par le compte, telle que la calcule le SERVEUR
/// (`GET /me/quota`) : offre (Supabase `plan_config`, sauf exception),
/// consommation du jour et de la session, réinitialisations, seuil critique.
///
/// Aucune limite n'est connue de l'application : tout vient de cette
/// réponse. Une limite `null` = illimitée ; une information absente reste
/// absente (jamais inventée).
library;

/// Une jauge en lecture seule : consommé / autorisé.
class Jauge {
  const Jauge({required this.utilise, this.limite, this.seuilCritique});

  final int utilise;

  /// null : illimité.
  final int? limite;

  /// Pourcentage à partir duquel la jauge passe en « critique » (serveur).
  final int? seuilCritique;

  bool get illimitee => limite == null;

  /// Restant (null : illimité).
  int? get reste => limite == null ? null : (limite! - utilise).clamp(0, limite!);

  /// 0 → 1 (bornée ; limite 0 = pleine).
  double get fraction {
    final l = limite;
    if (l == null) return 0;
    if (l <= 0) return 1;
    return (utilise / l).clamp(0.0, 1.0);
  }

  /// Pourcentage affiché (entier, 0 → 100).
  int get pourcentage => (fraction * 100).floor();

  bool get atteinte => limite != null && utilise >= limite!;

  /// Critique dès le seuil du serveur (ex. 80 % : 79 % bleu, 80 % orange).
  bool get critique {
    final l = limite;
    final seuil = seuilCritique;
    if (l == null || seuil == null) return atteinte;
    if (l <= 0) return true;
    return utilise * 100 >= seuil * l;
  }
}

/// Session d'utilisation (fenêtre ouverte au premier appel IA).
class SessionUtilisation {
  const SessionUtilisation({
    required this.active,
    required this.messages,
    required this.tokens,
    this.debut,
    this.fin,
    this.dureeMinutes,
  });

  /// false : aucune session en cours (la prochaine commencera au prochain
  /// appel IA) ; les limites et la durée sont celles de l'offre.
  final bool active;
  final DateTime? debut;
  final DateTime? fin;
  final int? dureeMinutes;
  final Jauge messages;
  final Jauge tokens;

  /// Jauge de la session : la ressource la plus consommée (messages ou
  /// tokens), comme une limite unique de session.
  Jauge get principale =>
      tokens.fraction > messages.fraction ? tokens : messages;

  /// Terminée d'après l'heure de fin donnée par le serveur.
  bool termineeA(DateTime maintenant) =>
      active && fin != null && !maintenant.isBefore(fin!);
}

/// Fournisseur IA (nom technique du serveur, modèle).
class FournisseurIA {
  const FournisseurIA({this.nom, this.modele});

  final String? nom;
  final String? modele;

  /// Libellé lisible du fournisseur (nom inconnu : tel quel).
  String? get libelle => switch (nom) {
    'anthropic' => 'Claude · Anthropic',
    'groq' => 'GroqCloud',
    null => null,
    final autre => autre,
  };

  bool memeQue(FournisseurIA autre) => nom == autre.nom && modele == autre.modele;
}

class Utilisation {
  const Utilisation({
    required this.plan,
    required this.offre,
    required this.messagesJour,
    required this.tokensJour,
    required this.session,
    this.finJour,
    this.actif,
    this.routageAbonnement,
    this.seuilCritique,
    this.exception = false,
  });

  /// `free`, `pro` (valeur du serveur).
  final String plan;

  /// Fournisseur et modèle de l'offre (plan_config).
  final FournisseurIA offre;

  /// Fournisseur qui sert RÉELLEMENT les demandes (peut différer de l'offre
  /// tant que le routage par abonnement est désactivé). null : inconnu.
  final FournisseurIA? actif;
  final bool? routageAbonnement;

  final Jauge messagesJour;
  final Jauge tokensJour;

  /// Prochaine remise à zéro quotidienne (heure du serveur).
  final DateTime? finJour;
  final SessionUtilisation session;
  final int? seuilCritique;

  /// Limites quotidiennes personnelles (exception) au lieu de l'offre.
  final bool exception;

  /// « JARVIS Free », « JARVIS Pro ».
  String get nomOffre => switch (plan) {
    'free' => 'JARVIS Free',
    'pro' => 'JARVIS Pro',
    final autre => 'JARVIS ${autre.isEmpty ? '?' : autre[0].toUpperCase() + autre.substring(1)}',
  };

  /// L'offre prévoit un autre fournisseur que celui qui sert vraiment.
  bool get fournisseurDifferent => actif != null && !actif!.memeQue(offre);

  static int? _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  /// Lit la réponse de `GET /me/quota`. Lève [FormatException] si le
  /// plan ou les compteurs du jour manquent.
  factory Utilisation.depuisJson(Map<String, dynamic> j) {
    final plan = j['plan'];
    final utilises = _entier(j['messages_used']);
    final tokens = _entier(j['tokens_used']);
    if (plan is! String || utilises == null || tokens == null) {
      throw const FormatException('réponse /me/quota incomplète');
    }
    final seuil = _entier(j['critical_threshold_percent']);
    final s = j['session'] is Map<String, dynamic>
        ? j['session'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final actif = j['fournisseur_actif'] is Map<String, dynamic>
        ? j['fournisseur_actif'] as Map<String, dynamic>
        : null;
    return Utilisation(
      plan: plan,
      offre: FournisseurIA(
        nom: j['llm_provider'] as String?,
        modele: j['llm_model'] as String?,
      ),
      actif: actif == null
          ? null
          : FournisseurIA(
              nom: actif['llm_provider'] as String?,
              modele: actif['llm_model'] as String?,
            ),
      routageAbonnement: actif?['routage_abonnement'] as bool?,
      messagesJour: Jauge(utilise: utilises, limite: _entier(j['messages_limit']), seuilCritique: seuil),
      tokensJour: Jauge(utilise: tokens, limite: _entier(j['tokens_limit']), seuilCritique: seuil),
      finJour: _date(j['resets_at']),
      seuilCritique: seuil,
      exception: j['exception'] == true,
      session: SessionUtilisation(
        active: s['active'] == true,
        debut: _date(s['started_at']),
        fin: _date(s['ends_at']),
        dureeMinutes: _entier(s['duration_minutes']),
        messages: Jauge(
          utilise: _entier(s['messages_used']) ?? 0,
          limite: _entier(s['messages_limit']),
          seuilCritique: seuil,
        ),
        tokens: Jauge(
          utilise: _entier(s['tokens_used']) ?? 0,
          limite: _entier(s['tokens_limit']),
          seuilCritique: seuil,
        ),
      ),
    );
  }
}
