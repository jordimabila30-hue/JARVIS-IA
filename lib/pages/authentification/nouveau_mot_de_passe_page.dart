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

/// Dernière étape de « Mot de passe oublié » : JARVIS a été ouvert par le
/// lien reçu par e-mail ; l'utilisateur choisit un nouveau mot de passe.
/// Seule une réponse réussie du serveur ouvre JARVIS ([surTermine]).
class NouveauMotDePassePage extends StatefulWidget {
  const NouveauMotDePassePage({
    super.key,
    required this.service,
    required this.brouillon,
    required this.surTermine,
    required this.surConnexion,
    this.validation = const ValidationAuth(),
  });

  final AuthService service;
  final BrouillonAuth brouillon;
  final VoidCallback surTermine;
  final VoidCallback surConnexion;
  final ValidationAuth validation;

  @override
  State<NouveauMotDePassePage> createState() => _NouveauMotDePassePageState();
}

class _NouveauMotDePassePageState extends State<NouveauMotDePassePage> {
  final _formulaire = GlobalKey<FormState>();
  final _focusConfirmation = FocusNode();
  BandeauAuth? _bandeau;
  bool _soumis = false;

  @override
  void dispose() {
    _focusConfirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (widget.service.enCours) return;
    setState(() {
      _soumis = true;
      _bandeau = null;
    });
    if (!_formulaire.currentState!.validate()) return;
    final r = await widget.service.changerMotDePasse(
      widget.brouillon.motDePasseInscription.text,
    );
    if (!mounted) return;
    switch (r) {
      case SuccesAuth():
        widget.surTermine();
      case EchecAuth(:final erreur):
        if (erreur.type == TypeErreurAuth.operationEnCours) return;
        setState(
          () => _bandeau = BandeauAuth(
            message: erreur.message,
            type: TypeBandeau.erreur,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.validation;
    final b = widget.brouillon;
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
              titre: 'Nouveau mot de passe',
              sousTitre: 'Choisissez le mot de passe de votre compte JARVIS.',
            ),
            const SizedBox(height: 32),
            ChampAuth(
              libelle: 'Nouveau mot de passe',
              controleur: b.motDePasseInscription,
              motDePasse: true,
              autofill: const [AutofillHints.newPassword],
              validateur: v.nouveauMotDePasse,
              surValidation: (_) => _focusConfirmation.requestFocus(),
            ),
            const SizedBox(height: 18),
            ChampAuth(
              libelle: 'Confirmer le mot de passe',
              controleur: b.confirmation,
              focus: _focusConfirmation,
              motDePasse: true,
              action: TextInputAction.done,
              validateur: (valeur) =>
                  v.confirmation(valeur, b.motDePasseInscription.text),
              surValidation: (_) => _valider(),
            ),
            const SizedBox(height: 26),
            ListenableBuilder(
              listenable: widget.service,
              builder: (context, _) => BoutonAuth(
                libelle: 'Enregistrer le mot de passe',
                chargement: widget.service.enCours,
                surAppui: _valider,
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
