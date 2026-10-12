import 'package:flutter/material.dart';

import '../../models/authentification/resultat_auth.dart';
import '../../services/authentification/auth_service.dart';
import '../../services/authentification/validation_auth.dart';
import '../../widgets/authentification/bandeau_auth.dart';
import '../../widgets/authentification/bouton_auth.dart';
import '../../widgets/authentification/brouillon_auth.dart';
import '../../widgets/authentification/champ_auth.dart';
import '../../widgets/authentification/conteneur_auth.dart';
import '../../widgets/authentification/entete_auth.dart';

/// Mot de passe oublié : adresse e-mail validée localement, puis demande
/// de récupération à [AuthService]. Aucun envoi n'est annoncé sans
/// réponse réelle du serveur.
class MotDePasseOubliePage extends StatefulWidget {
  const MotDePasseOubliePage({
    super.key,
    required this.service,
    required this.brouillon,
    required this.surConnexion,
    this.validation = const ValidationAuth(),
  });

  final AuthService service;
  final BrouillonAuth brouillon;
  final VoidCallback surConnexion;
  final ValidationAuth validation;

  static const nonDisponible =
      'L’envoi du lien de récupération sera disponible après l’intégration '
      'du serveur JARVIS. Aucun e-mail n’a été envoyé.';

  /// Après une réponse réelle du serveur : formulation neutre, qui ne
  /// révèle pas si un compte existe.
  static const demandeTransmise =
      'Si un compte correspond à cette adresse, vous recevrez un lien de '
      'récupération.';

  @override
  State<MotDePasseOubliePage> createState() => _MotDePasseOubliePageState();
}

class _MotDePasseOubliePageState extends State<MotDePasseOubliePage> {
  final _formulaire = GlobalKey<FormState>();
  BandeauAuth? _bandeau;
  bool _soumis = false;

  Future<void> _envoyer() async {
    if (widget.service.enCours) return;
    // Nouvel envoi : l'ancien message disparaît, même si la validation
    // locale échoue.
    setState(() {
      _soumis = true;
      _bandeau = null;
    });
    if (!_formulaire.currentState!.validate()) return;
    final r = await widget.service.demanderRecuperation(
      widget.brouillon.email.text,
    );
    if (!mounted) return;
    switch (r) {
      case SuccesAuth():
        setState(
          () => _bandeau = const BandeauAuth(
            message: MotDePasseOubliePage.demandeTransmise,
          ),
        );
      case EchecAuth(:final erreur):
        if (erreur.type == TypeErreurAuth.operationEnCours) return;
        setState(
          () => _bandeau = BandeauAuth.echec(
            erreur,
            siNonConfigure: MotDePasseOubliePage.nonDisponible,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConteneurAuth(
      child: Form(
        key: _formulaire,
        autovalidateMode: _soumis
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EnteteAuth(
              titre: 'Mot de passe oublié ?',
              sousTitre:
                  'Indiquez l’adresse e-mail de votre compte : vous recevrez '
                  'un lien pour choisir un nouveau mot de passe.',
            ),
            const SizedBox(height: 32),
            ChampAuth(
              libelle: 'Adresse e-mail',
              indice: 'vous@exemple.com',
              controleur: widget.brouillon.email,
              clavier: TextInputType.emailAddress,
              action: TextInputAction.done,
              autofill: const [AutofillHints.email],
              validateur: widget.validation.email,
              surValidation: (_) => _envoyer(),
            ),
            const SizedBox(height: 26),
            ListenableBuilder(
              listenable: widget.service,
              builder: (context, _) => BoutonAuth(
                libelle: 'Envoyer le lien',
                chargement: widget.service.enCours,
                surAppui: _envoyer,
              ),
            ),
            if (_bandeau case final bandeau?) ...[
              const SizedBox(height: 16),
              bandeau,
            ],
            const SizedBox(height: 18),
            Center(
              child: LienAuth(
                libelle: 'Retour à la connexion',
                surAppui: widget.surConnexion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
