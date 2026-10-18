/// État de la connexion Gmail du compte, tel que le donne le serveur
/// (`GET /api/v1/integrations/gmail`). Jamais de jeton : l'application ne
/// voit que l'adresse du compte Google autorisé et la portée.
library;

enum StatutGmail {
  /// Le serveur JARVIS n'a pas d'identifiants Google.
  nonConfigure,
  nonConnecte,
  connecte,

  /// Autorisation expirée ou retirée chez Google : reconnecter.
  aRenouveler,
}

class EtatGmail {
  const EtatGmail({
    required this.statut,
    this.email,
    this.lectureSeule = false,
    this.connecteLe,
  });

  final StatutGmail statut;
  final String? email;
  final bool lectureSeule;
  final DateTime? connecteLe;

  factory EtatGmail.depuisJson(Map<String, dynamic> j) {
    final configure = j['configure'] != false;
    final statut = switch (j['statut']) {
      'connecte' => StatutGmail.connecte,
      'a_renouveler' => StatutGmail.aRenouveler,
      _ => configure ? StatutGmail.nonConnecte : StatutGmail.nonConfigure,
    };
    final le = j['connecte_le'];
    return EtatGmail(
      statut: statut,
      email: j['email'] as String?,
      lectureSeule: j['portee'] == 'lecture_seule',
      connecteLe: le is String ? DateTime.tryParse(le) : null,
    );
  }
}
