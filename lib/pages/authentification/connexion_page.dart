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

/// Connexion : adresse e-mail et mot de passe, validés localement puis
/// transmis à [AuthService]. Seul un succès renvoyé par le serveur ouvre
/// JARVIS ([surConnecte]).
class ConnexionPage extends StatefulWidget {
  const ConnexionPage({
    super.key,
    required this.service,
    required this.brouillon,
    required this.surInscription,
    required this.surRecuperation,
    required this.surConnecte,
    this.surAccesDeveloppement,
    this.validation = const ValidationAuth(),
  });

  final AuthService service;
  final BrouillonAuth brouillon;
  final VoidCallback surInscription;
  final VoidCallback surRecuperation;
  final ValueChanged<UtilisateurAuth> surConnecte;

  /// Accès de développement (null : bouton absent, comme en production).
  final VoidCallback? surAccesDeveloppement;
  final ValidationAuth validation;

  static const nonDisponible =
      'La connexion sera disponible après l’intégration du serveur JARVIS. '
      'Aucune session n’a été ouverte.';

  @override
  State<ConnexionPage> createState() => _ConnexionPageState();
}

class _ConnexionPageState extends State<ConnexionPage> {
  final _formulaire = GlobalKey<FormState>();
  final _focusMotDePasse = FocusNode();
  BandeauAuth? _bandeau;
  bool _soumis = false;

  @override
  void dispose() {
    _focusMotDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    if (widget.service.enCours) return;
    // Nouvel envoi : l'ancien message disparaît, même si la validation
    // locale échoue.
    setState(() {
      _soumis = true;
      _bandeau = null;
    });
    if (!_formulaire.currentState!.validate()) return;
    final b = widget.brouillon;
    final r = await widget.service.connecter(
      email: b.email.text,
      motDePasse: b.motDePasseConnexion.text,
    );
    if (!mounted) return;
    switch (r) {
      case SuccesAuth(:final valeur):
        widget.surConnecte(valeur);
      case EchecAuth(:final erreur):
        if (erreur.type == TypeErreurAuth.operationEnCours) return;
        setState(
          () => _bandeau = BandeauAuth.echec(
            erreur,
            siNonConfigure: ConnexionPage.nonDisponible,
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
                titre: 'JARVIS',
                sousTitre: 'Heureux de vous revoir',
              ),
              const SizedBox(height: 36),
              ChampAuth(
                libelle: 'Adresse e-mail',
                indice: 'vous@exemple.com',
                controleur: b.email,
                clavier: TextInputType.emailAddress,
                autofill: const [AutofillHints.email],
                validateur: v.email,
                surValidation: (_) => _focusMotDePasse.requestFocus(),
              ),
              const SizedBox(height: 18),
              ChampAuth(
                libelle: 'Mot de passe',
                controleur: b.motDePasseConnexion,
                focus: _focusMotDePasse,
                motDePasse: true,
                action: TextInputAction.done,
                autofill: const [AutofillHints.password],
                validateur: v.motDePasse,
                surValidation: (_) => _connecter(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LienAuth(
                    libelle: 'Mot de passe oublié ?',
                    surAppui: widget.surRecuperation,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: widget.service,
                builder: (context, _) => BoutonAuth(
                  libelle: 'Se connecter',
                  chargement: widget.service.enCours,
                  surAppui: _connecter,
                ),
              ),
              if (_bandeau case final bandeau?) ...[
                const SizedBox(height: 16),
                bandeau,
              ],
              const SizedBox(height: 18),
              LigneLienAuth(
                question: 'Pas encore de compte ?',
                lien: 'Créer un compte',
                surAppui: widget.surInscription,
              ),
              if (widget.surAccesDeveloppement case final acces?) ...[
                const SizedBox(height: 28),
                BoutonAccesDeveloppement(surAppui: acces),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
