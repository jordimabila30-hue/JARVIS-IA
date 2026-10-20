import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Bouton principal violet, pleine largeur. En [chargement], il affiche un
/// indicateur et ne répond plus (pas de double envoi).
class BoutonAuth extends StatelessWidget {
  const BoutonAuth({
    super.key,
    required this.libelle,
    required this.surAppui,
    this.chargement = false,
  });

  final String libelle;
  final VoidCallback surAppui;
  final bool chargement;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: chargement ? null : surAppui,
      style: FilledButton.styleFrom(
        backgroundColor: CouleursJarvis.signal,
        foregroundColor: CouleursJarvis.ivoire,
        disabledBackgroundColor: CouleursJarvis.signal.withValues(alpha: 0.7),
        disabledForegroundColor: CouleursJarvis.ivoire,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        elevation: 0,
      ),
      child: chargement
          ? Semantics(
              label: 'Chargement',
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: CouleursJarvis.ivoire,
                ),
              ),
            )
          : Text(libelle),
    );
  }
}

/// Lien discret en bleu-violet (« Mot de passe oublié ? », « Connexion »…).
class LienAuth extends StatelessWidget {
  const LienAuth({super.key, required this.libelle, required this.surAppui});

  final String libelle;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: surAppui,
      style: TextButton.styleFrom(
        foregroundColor: CouleursJarvis.signal,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(libelle),
    );
  }
}

/// Ligne « question + lien », centrée, qui passe à la ligne si besoin.
class LigneLienAuth extends StatelessWidget {
  const LigneLienAuth({
    super.key,
    required this.question,
    required this.lien,
    required this.surAppui,
  });

  final String question;
  final String lien;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          question,
          style: TextStyle(fontSize: 14, color: CouleursJarvis.texteSecondaire),
        ),
        LienAuth(libelle: lien, surAppui: surAppui),
      ],
    );
  }
}

/// Accès de développement : ouvre l'accueil sans compte ni session.
/// Affiché seulement si la configuration l'autorise (jamais en
/// production), et clairement identifié comme tel.
class BoutonAccesDeveloppement extends StatelessWidget {
  const BoutonAccesDeveloppement({super.key, required this.surAppui});

  final VoidCallback surAppui;

  static const libelle = 'Continuer sans compte';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: surAppui,
          icon: const Icon(Icons.code_rounded, size: 18),
          label: const Text(libelle),
          style: OutlinedButton.styleFrom(
            foregroundColor: CouleursJarvis.texteSecondaire,
            minimumSize: const Size.fromHeight(46),
            side: BorderSide(
              color: CouleursJarvis.trait,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Mode développement : accueil sans connexion, aucune session '
          'ouverte. Désactivé en production.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
      ],
    );
  }
}
