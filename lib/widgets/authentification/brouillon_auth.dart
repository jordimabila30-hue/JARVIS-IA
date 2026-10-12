import 'package:flutter/widgets.dart';

/// Saisies des pages d'authentification, gardées en mémoire tant que le
/// parcours est affiché : passer de la connexion à l'inscription (et
/// retour) n'efface rien. L'adresse e-mail est commune aux trois pages.
///
/// Rien n'est écrit sur l'appareil. Les mots de passe sont effacés dès
/// que le parcours se termine ([effacerMotsDePasse], puis [dispose]).
class BrouillonAuth {
  final email = TextEditingController();
  final motDePasseConnexion = TextEditingController();
  final nom = TextEditingController();
  final motDePasseInscription = TextEditingController();
  final confirmation = TextEditingController();

  void effacerMotsDePasse() {
    motDePasseConnexion.clear();
    motDePasseInscription.clear();
    confirmation.clear();
  }

  void dispose() {
    effacerMotsDePasse();
    for (final c in [
      email,
      motDePasseConnexion,
      nom,
      motDePasseInscription,
      confirmation,
    ]) {
      c.dispose();
    }
  }
}
