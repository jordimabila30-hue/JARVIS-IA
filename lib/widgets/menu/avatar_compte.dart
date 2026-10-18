import 'package:flutter/material.dart';

import '../../services/authentification/auth_service.dart';
import '../../theme/theme_jarvis.dart';

/// Initiale affichée dans l'avatar : première lettre du nom affiché, sinon
/// de l'adresse e-mail (l'adresse elle-même n'est jamais montrée) ; null
/// si rien n'est utilisable.
String? initialeCompte({String? nom, String? email}) {
  for (final source in [nom, email]) {
    final texte = source?.trim() ?? '';
    if (texte.isEmpty) continue;
    // Première lettre ou chiffre (ignore « @ », espaces, ponctuation…).
    for (final c in texte.characters) {
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c)) {
        return c.toUpperCase();
      }
    }
  }
  return null;
}

/// Avatar du compte connecté, en bas à gauche du panneau latéral : une
/// boule au dégradé bleu-violet discret, avec l'initiale du nom affiché.
/// Suit le compte ([AuthService]) : l'initiale change avec le compte ou le
/// nom. Sans compte : silhouette neutre. Appui : section « Compte » des
/// Paramètres (l'interface de compte existante).
class AvatarCompte extends StatelessWidget {
  const AvatarCompte({super.key, required this.compte, this.surAppui});

  final AuthService? compte;
  final VoidCallback? surAppui;

  /// Diamètre de la boule ; zone tactile de 48 px.
  static const taille = 34.0;

  @override
  Widget build(BuildContext context) {
    final c = compte;
    if (c == null) return _avatar(null, null);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final u = c.utilisateur;
        if (u == null) return _avatar(null, null);
        final nom = c.profil?.nom ?? u.nom;
        return _avatar(initialeCompte(nom: nom, email: u.email), nom);
      },
    );
  }

  Widget _avatar(String? initiale, String? nom) {
    final libelle = nom == null ? 'Compte' : 'Compte de $nom';
    return Tooltip(
      message: libelle,
      child: Semantics(
        button: true,
        label: libelle,
        excludeSemantics: true,
        child: InkResponse(
          onTap: surAppui,
          radius: 26,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                key: const ValueKey('avatar-compte'),
                width: taille,
                height: taille,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [CouleursJarvis.signal, CouleursJarvis.violet],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CouleursJarvis.signal.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: initiale == null
                    ? const Icon(
                        Icons.person_outline_rounded,
                        size: 19,
                        color: Colors.white,
                      )
                    : Text(
                        initiale,
                        // L'initiale garde sa taille : la boule est fixe.
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
