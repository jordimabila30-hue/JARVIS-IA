import 'package:flutter/material.dart';

import '../../models/authentification/resultat_auth.dart';
import '../../theme/theme_jarvis.dart';

/// Nature du message sous le formulaire.
enum TypeBandeau {
  /// Information neutre (fonctionnalité pas encore disponible…).
  information,

  /// Erreur renvoyée par le serveur.
  erreur,
}

/// Message sous le formulaire, annoncé par les lecteurs d'écran.
class BandeauAuth extends StatelessWidget {
  const BandeauAuth({
    super.key,
    required this.message,
    this.type = TypeBandeau.information,
  });

  /// Bandeau d'un échec : « pas encore disponible » (information, texte
  /// propre à la page) si aucun serveur n'est configuré ; information aussi
  /// quand le compte est créé mais attend la confirmation de l'e-mail ;
  /// erreur sinon.
  factory BandeauAuth.echec(
    ErreurAuth erreur, {
    required String siNonConfigure,
  }) => switch (erreur.type) {
    TypeErreurAuth.serveurNonConfigure => BandeauAuth(message: siNonConfigure),
    TypeErreurAuth.confirmationEnvoyee => BandeauAuth(message: erreur.message),
    _ => BandeauAuth(message: erreur.message, type: TypeBandeau.erreur),
  };

  final String message;
  final TypeBandeau type;

  @override
  Widget build(BuildContext context) {
    final erreur = type == TypeBandeau.erreur;
    final couleur = erreur
        ? CouleursJarvis.lisible(const Color(0xFFB0444F))
        : CouleursJarvis.signal;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: couleur.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                erreur ? Icons.error_outline_rounded : Icons.info_outline,
                size: 18,
                color: couleur,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: CouleursJarvis.texte,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
