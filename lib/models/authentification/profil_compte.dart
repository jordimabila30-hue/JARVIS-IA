/// Profil du compte, tel qu'enregistré par le serveur (table
/// `public.users` de Supabase, créée à l'inscription par le déclencheur
/// `handle_new_user`).
///
/// Seuls [nom], et plus tard l'avatar et les préférences, sont modifiables
/// par l'utilisateur ; l'offre et les limites sont décidées par le serveur.
class ProfilCompte {
  const ProfilCompte({
    required this.identifiant,
    required this.email,
    this.nom,
    this.avatarUrl,
    this.offre = OffreCompte.gratuite,
    this.limiteMessagesJour,
    this.limiteTokensJour,
    this.creeLe,
  });

  /// Lit une ligne de `public.users`. Les colonnes absentes gardent leur
  /// valeur par défaut (aucune valeur inventée).
  factory ProfilCompte.depuisLigne(Map<String, dynamic> ligne) {
    int? entier(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    final creation = ligne['created_at'];
    return ProfilCompte(
      identifiant: '${ligne['id']}',
      email: '${ligne['email'] ?? ''}',
      nom: switch (ligne['display_name']) {
        final String n when n.trim().isNotEmpty => n.trim(),
        _ => null,
      },
      avatarUrl: ligne['avatar_url'] as String?,
      offre: ligne['plan'] == 'pro' ? OffreCompte.pro : OffreCompte.gratuite,
      limiteMessagesJour: ligne['daily_message_limit'] == null
          ? null
          : entier(ligne['daily_message_limit']),
      limiteTokensJour: ligne['daily_token_limit'] == null
          ? null
          : entier(ligne['daily_token_limit']),
      creeLe: creation is String
          ? DateTime.tryParse(creation)?.toLocal()
          : null,
    );
  }

  final String identifiant;
  final String email;

  /// Nom ou pseudonyme affiché (null : pas encore choisi).
  final String? nom;
  final String? avatarUrl;
  final OffreCompte offre;

  /// Limites quotidiennes ; null : illimité.
  final int? limiteMessagesJour;
  final int? limiteTokensJour;
  final DateTime? creeLe;

  ProfilCompte avecNom(String? nouveau) => ProfilCompte(
    identifiant: identifiant,
    email: email,
    nom: nouveau,
    avatarUrl: avatarUrl,
    offre: offre,
    limiteMessagesJour: limiteMessagesJour,
    limiteTokensJour: limiteTokensJour,
    creeLe: creeLe,
  );
}

/// Offre du compte (colonne `plan`).
enum OffreCompte {
  gratuite('Offre gratuite'),
  pro('Offre Pro');

  const OffreCompte(this.libelle);
  final String libelle;
}
