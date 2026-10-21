import 'package:flutter/material.dart';

import '../../models/authentification/resultat_auth.dart';
import '../../models/authentification/utilisateur_auth.dart';
import '../../services/authentification/auth_service.dart';
import '../../services/authentification/validation_auth.dart';
import '../../widgets/authentification/bandeau_auth.dart';
import '../../widgets/authentification/bouton_auth.dart';
import '../../widgets/authentification/brouillon_auth.dart';
import '../../widgets/authentification/champ_auth.dart';
import '../../widgets/authentification/conteneur_auth.dart';
import '../../widgets/authentification/entete_auth.dart';

/// Création de compte : nom ou pseudonyme, adresse e-mail, mot de passe et
/// confirmation. Validation locale, puis demande à [AuthService] ; seul le
/// serveur crée réellement le compte.
class InscriptionPage extends StatefulWidget {
  const InscriptionPage({
    super.key,
    required this.service,
    required this.brouillon,
    required this.surConnexion,
    required this.surInscrit,
    this.validation = const ValidationAuth(),
  });

  final AuthService service;
  final BrouillonAuth brouillon;
  final VoidCallback surConnexion;
  final ValueChanged<UtilisateurAuth> surInscrit;
  final ValidationAuth validation;

  static const nonDisponible =
      'La création de compte sera disponible après l’intégration du '
      'serveur JARVIS. Aucun compte n’a été créé.';

  static const confirmation =
      'Compte créé. Ouvrez le lien de confirmation reçu par e-mail, puis '
      'revenez ici : JARVIS vous connectera directement.';
  static const toujoursNonConfirme =
      'Adresse pas encore confirmée. Ouvrez le lien reçu par e-mail, puis '
      'réessayez.';

  @override
  State<InscriptionPage> createState() => _InscriptionPageState();
}

class _InscriptionPageState extends State<InscriptionPage> {
  final _formulaire = GlobalKey<FormState>();
  final _focusEmail = FocusNode();
  final _focusMotDePasse = FocusNode();
  final _focusConfirmation = FocusNode();
  BandeauAuth? _bandeau;
  bool _soumis = false;

  /// Compte créé, mais Supabase exige la confirmation de l'adresse avant
  /// toute session : « J'ai confirmé » ouvre la session avec les saisies
  /// encore en mémoire (rien n'est écrit sur l'appareil), sans repasser
  /// par la page de connexion. La sécurité n'est jamais contournée : tant
  /// que l'adresse n'est pas confirmée, le serveur refuse la session.
  bool _attenteConfirmation = false;

  @override
  void dispose() {
    _focusEmail.dispose();
    _focusMotDePasse.dispose();
    _focusConfirmation.dispose();
    super.dispose();
  }

  Future<void> _inscrire() async {
    if (widget.service.enCours) return;
    // Nouvel envoi : l'ancien message disparaît, même si la validation
    // locale échoue.
    setState(() {
      _soumis = true;
      _bandeau = null;
    });
    if (!_formulaire.currentState!.validate()) return;
    final b = widget.brouillon;
    final r = await widget.service.inscrire(
      nom: b.nom.text,
      email: b.email.text,
      motDePasse: b.motDePasseInscription.text,
    );
    if (!mounted) return;
    switch (r) {
      case SuccesAuth(:final valeur):
        widget.surInscrit(valeur);
      case EchecAuth(:final erreur):
        if (erreur.type == TypeErreurAuth.operationEnCours) return;
        setState(() {
          _attenteConfirmation =
              erreur.type == TypeErreurAuth.confirmationEnvoyee;
          _bandeau = _attenteConfirmation
              ? const BandeauAuth(message: InscriptionPage.confirmation)
              : BandeauAuth.echec(
                  erreur,
                  siNonConfigure: InscriptionPage.nonDisponible,
                );
        });
    }
  }

  /// Adresse confirmée (lien ouvert) : session ouverte directement.
  Future<void> _continuerApresConfirmation() async {
    if (widget.service.enCours) return;
    final b = widget.brouillon;
    setState(() => _bandeau = null);
    final r = await widget.service.connecter(
      email: b.email.text,
      motDePasse: b.motDePasseInscription.text,
    );
    if (!mounted) return;
    switch (r) {
      case SuccesAuth(:final valeur):
        widget.surInscrit(valeur);
      case EchecAuth(:final erreur):
        if (erreur.type == TypeErreurAuth.operationEnCours) return;
        setState(
          () => _bandeau = erreur.type == TypeErreurAuth.emailNonConfirme
              ? const BandeauAuth(
                  message: InscriptionPage.toujoursNonConfirme,
                  type: TypeBandeau.erreur,
                )
              : BandeauAuth.echec(
                  erreur,
                  siNonConfigure: InscriptionPage.nonDisponible,
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.validation;
    final b = widget.brouillon;
    return ConteneurAuth(
      child: AutofillGroup(
        child: Form(
          key: _formulaire,
          autovalidateMode: _soumis
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnteteAuth(
                titre: 'Rejoindre JARVIS',
                sousTitre: 'Créez votre espace personnel',
              ),
              const SizedBox(height: 32),
              ChampAuth(
                libelle: 'Nom ou pseudonyme',
                indice: 'Comment JARVIS vous appellera',
                controleur: b.nom,
                majuscules: TextCapitalization.words,
                autofill: const [AutofillHints.nickname],
                validateur: v.nom,
                surValidation: (_) => _focusEmail.requestFocus(),
              ),
              const SizedBox(height: 16),
              ChampAuth(
                libelle: 'Adresse e-mail',
                indice: 'vous@exemple.com',
                controleur: b.email,
                focus: _focusEmail,
                clavier: TextInputType.emailAddress,
                autofill: const [AutofillHints.email],
                validateur: v.email,
                surValidation: (_) => _focusMotDePasse.requestFocus(),
              ),
              const SizedBox(height: 16),
              ChampAuth(
                libelle: 'Mot de passe',
                indice: 'Au moins ${v.regles.longueurMinMotDePasse} caractères',
                controleur: b.motDePasseInscription,
                focus: _focusMotDePasse,
                motDePasse: true,
                autofill: const [AutofillHints.newPassword],
                validateur: v.nouveauMotDePasse,
                surValidation: (_) => _focusConfirmation.requestFocus(),
              ),
              const SizedBox(height: 16),
              ChampAuth(
                libelle: 'Confirmer le mot de passe',
                controleur: b.confirmation,
                focus: _focusConfirmation,
                motDePasse: true,
                action: TextInputAction.done,
                autofill: const [AutofillHints.newPassword],
                validateur: (valeur) =>
                    v.confirmation(valeur, b.motDePasseInscription.text),
                surValidation: (_) => _inscrire(),
              ),
              const SizedBox(height: 26),
              ListenableBuilder(
                listenable: widget.service,
                builder: (context, _) => _attenteConfirmation
                    ? BoutonAuth(
                        libelle: 'J’ai confirmé, continuer',
                        chargement: widget.service.enCours,
                        surAppui: _continuerApresConfirmation,
                      )
                    : BoutonAuth(
                        libelle: 'Créer mon compte',
                        chargement: widget.service.enCours,
                        surAppui: _inscrire,
                      ),
              ),
              if (_bandeau case final bandeau?) ...[
                const SizedBox(height: 16),
                bandeau,
              ],
              const SizedBox(height: 18),
              LigneLienAuth(
                question: 'Déjà un compte ?',
                lien: 'Connexion',
                surAppui: widget.surConnexion,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
