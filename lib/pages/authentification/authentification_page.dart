import 'package:flutter/material.dart';

import '../../models/authentification/utilisateur_auth.dart';
import '../../services/authentification/auth_service.dart';
import '../../services/authentification/validation_auth.dart';
import '../../widgets/authentification/brouillon_auth.dart';
import 'connexion_page.dart';
import 'inscription_page.dart';
import 'mot_de_passe_oublie_page.dart';
import 'nouveau_mot_de_passe_page.dart';

/// Écrans du parcours d'authentification.
enum EcranAuth { connexion, inscription, recuperation, nouveauMotDePasse }

/// Parcours d'authentification : connexion, inscription, mot de passe
/// oublié, nouveau mot de passe (ouvert par le lien reçu par e-mail). Passage d'un écran à l'autre par un fondu léger, sans perdre les
/// saisies ([BrouillonAuth]). Retour (Android, navigateur) : revient à la
/// connexion.
class AuthentificationPage extends StatefulWidget {
  const AuthentificationPage({
    super.key,
    required this.service,
    required this.surConnecte,
    this.surAccesDeveloppement,
    this.validation = const ValidationAuth(),
    this.ecranInitial = EcranAuth.connexion,
    this.messageConnexion,
  });

  final AuthService service;

  /// Session ouverte par le serveur (connexion ou inscription réussie).
  final ValueChanged<UtilisateurAuth> surConnecte;

  /// Accès de développement ; null : absent (production).
  final VoidCallback? surAccesDeveloppement;
  final ValidationAuth validation;
  final EcranAuth ecranInitial;

  /// Message affiché d'emblée sur la connexion (session expirée…).
  final String? messageConnexion;

  @override
  State<AuthentificationPage> createState() => _AuthentificationPageState();
}

class _AuthentificationPageState extends State<AuthentificationPage> {
  final _brouillon = BrouillonAuth();
  late EcranAuth _ecran = widget.ecranInitial;

  @override
  void dispose() {
    _brouillon.dispose();
    super.dispose();
  }

  void _aller(EcranAuth e) {
    if (e == _ecran) return;
    // Le focus du champ quitté ne doit pas rouvrir le clavier ailleurs.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _ecran = e);
  }

  void _quitter(VoidCallback suite) {
    _brouillon.effacerMotsDePasse();
    suite();
  }

  Widget _page() {
    final service = widget.service;
    final v = widget.validation;
    return switch (_ecran) {
      EcranAuth.connexion => ConnexionPage(
        key: const ValueKey(EcranAuth.connexion),
        service: service,
        brouillon: _brouillon,
        validation: v,
        surInscription: () => _aller(EcranAuth.inscription),
        surRecuperation: () => _aller(EcranAuth.recuperation),
        messageInitial: widget.messageConnexion,
        surConnecte: (u) => _quitter(() => widget.surConnecte(u)),
        surAccesDeveloppement: switch (widget.surAccesDeveloppement) {
          final acces? => () => _quitter(acces),
          null => null,
        },
      ),
      EcranAuth.inscription => InscriptionPage(
        key: const ValueKey(EcranAuth.inscription),
        service: service,
        brouillon: _brouillon,
        validation: v,
        surConnexion: () => _aller(EcranAuth.connexion),
        surInscrit: (u) => _quitter(() => widget.surConnecte(u)),
      ),
      EcranAuth.recuperation => MotDePasseOubliePage(
        key: const ValueKey(EcranAuth.recuperation),
        service: service,
        brouillon: _brouillon,
        validation: v,
        surConnexion: () => _aller(EcranAuth.connexion),
      ),
      EcranAuth.nouveauMotDePasse => NouveauMotDePassePage(
        key: const ValueKey(EcranAuth.nouveauMotDePasse),
        service: service,
        brouillon: _brouillon,
        validation: v,
        surConnexion: () => _aller(EcranAuth.connexion),
        surTermine: () {
          final u = service.utilisateur;
          if (u != null) _quitter(() => widget.surConnecte(u));
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _ecran == EcranAuth.connexion,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _aller(EcranAuth.connexion);
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _page(),
        ),
      ),
    );
  }
}
