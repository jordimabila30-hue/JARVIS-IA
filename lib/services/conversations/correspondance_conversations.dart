/// Lien entre une conversation du fil (identifiant local) et la
/// conversation enregistrée sur le serveur (UUID), partagé par le moteur
/// IA (qui l'établit dès la première réponse) et la synchronisation (qui
/// s'en sert pour ne jamais lister deux fois la même conversation).
///
/// Une conversation ouverte depuis le serveur garde son UUID comme
/// identifiant local : elle est associée à elle-même.
class CorrespondanceConversations {
  final _serveur = <String, String>{};

  /// UUID serveur de la conversation locale [local], s'il existe.
  String? serveur(String local) => _serveur[local];

  /// Conversation locale associée à l'UUID [serveur], s'il y en a une.
  String? local(String serveur) {
    for (final e in _serveur.entries) {
      if (e.value == serveur) return e.key;
    }
    return null;
  }

  void associer(String local, String serveur) => _serveur[local] = serveur;

  void oublier(String local) => _serveur.remove(local);
}
