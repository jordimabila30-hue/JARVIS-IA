import 'package:flutter/material.dart';

import '../../models/authentification/profil_compte.dart';
import '../../models/authentification/resultat_auth.dart';
import '../../services/api_jarvis.dart';
import '../../services/authentification/auth_service.dart';
import '../../services/authentification/validation_auth.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/local_date_time.dart';
import 'elements_parametres.dart';

/// Section « Compte » des Paramètres : profil réel (Supabase,
/// `public.users`), nom affiché modifiable, vérification du compte par le
/// serveur JARVIS (`GET /me`), déconnexion. Sans compte : le dit, et
/// propose de se connecter.
class PanneauCompte extends StatefulWidget {
  const PanneauCompte({
    super.key,
    required this.compte,
    this.api,
    this.surConnexion,
  });

  final AuthService? compte;
  final ApiJarvis? api;
  final VoidCallback? surConnexion;

  static const sansCompte = 'Aucun compte connecté';
  static const deconnexion = 'Se déconnecter';
  static const serveurOk = 'Compte reconnu par le serveur JARVIS';
  static const serveurDifferent =
      'Le serveur JARVIS reconnaît un autre compte que celui-ci.';

  /// Longueur maximale du nom (contrainte de `public.users`).
  static const longueurMaxNom = 80;

  @override
  State<PanneauCompte> createState() => _PanneauCompteState();
}

class _PanneauCompteState extends State<PanneauCompte> {
  final _nom = TextEditingController();
  final _formulaire = GlobalKey<FormState>();
  String? _erreurProfil;
  String? _messageNom;
  bool _nomEnregistre = false;

  // Vérification par le backend : null tant qu'elle n'a pas répondu.
  bool _verification = false;
  ResultatApi<CompteServeur>? _serveur;

  AuthService? get _compte => widget.compte;

  @override
  void initState() {
    super.initState();
    final c = _compte;
    if (c != null && c.connecte) {
      _nom.text = c.profil?.nom ?? c.utilisateur?.nom ?? '';
      _chargerProfil();
      _verifierServeur();
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    final r = await _compte!.chargerProfil();
    if (!mounted) return;
    setState(() {
      switch (r) {
        case SuccesAuth(:final valeur):
          _erreurProfil = null;
          _nom.text = valeur.nom ?? _nom.text;
        case EchecAuth(:final erreur):
          _erreurProfil = erreur.message;
      }
    });
  }

  Future<void> _verifierServeur() async {
    final api = widget.api;
    if (api == null) return;
    setState(() => _verification = true);
    final r = await api.moi();
    if (!mounted) return;
    setState(() {
      _verification = false;
      _serveur = r;
    });
  }

  Future<void> _enregistrerNom() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _messageNom = null;
      _nomEnregistre = false;
    });
    final r = await _compte!.modifierNom(_nom.text);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case SuccesAuth(:final valeur):
          _nom.text = valeur.nom ?? '';
          _nomEnregistre = true;
        case EchecAuth(:final erreur):
          if (erreur.type != TypeErreurAuth.operationEnCours) {
            _messageNom = erreur.message;
          }
      }
    });
  }

  String? _validerNom(String? v) {
    final erreur = const ValidationAuth().nom(v);
    if (erreur != null) return erreur;
    if (ValidationAuth.nettoyerNom(v!).length > PanneauCompte.longueurMaxNom) {
      return '${PanneauCompte.longueurMaxNom} caractères au maximum.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = _compte;
    if (c == null) return _sansCompte(serveur: false);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final u = c.utilisateur;
        if (u == null) return _sansCompte(serveur: true);
        final p = c.profil;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EnTeteCompte(
              nom: p?.nom ?? u.nom ?? u.email,
              email: p?.email ?? u.email,
              offre: p?.offre,
            ),
            const SizedBox(height: 22),
            if (_erreurProfil case final e?) ...[
              NoteReglage(e),
              const SizedBox(height: 16),
            ],
            CarteReglages(
              titre: 'Profil',
              enfants: [
                Form(
                  key: _formulaire,
                  child: LigneReglage(
                    titre: 'Nom affiché',
                    description: 'Comment JARVIS vous appelle.',
                    largeurControle: 320,
                    controle: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nom,
                            validator: _validerNom,
                            maxLength: PanneauCompte.longueurMaxNom,
                            textCapitalization: TextCapitalization.words,
                            onFieldSubmitted: (_) => _enregistrerNom(),
                            onChanged: (_) {
                              if (_nomEnregistre) {
                                setState(() => _nomEnregistre = false);
                              }
                            },
                            style: const TextStyle(
                              fontSize: 14,
                              color: CouleursJarvis.texte,
                            ),
                            decoration: _decoration(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: c.enCours
                              ? const SizedBox.square(
                                  dimension: 40,
                                  child: Padding(
                                    padding: EdgeInsets.all(11),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CouleursJarvis.signal,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Enregistrer le nom',
                                  onPressed: _enregistrerNom,
                                  icon: Icon(
                                    _nomEnregistre
                                        ? Icons.check_circle_rounded
                                        : Icons.check_rounded,
                                  ),
                                  style: IconButton.styleFrom(
                                    foregroundColor: CouleursJarvis.signal,
                                    minimumSize: const Size(40, 40),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    note: _messageNom,
                  ),
                ),
                _Info(titre: 'Adresse e-mail', valeur: p?.email ?? u.email),
                if (p != null) ...[
                  _Info(titre: 'Offre', valeur: p.offre.libelle),
                  _Info(titre: 'Limite quotidienne', valeur: _limites(p)),
                  if (p.creeLe case final d?)
                    _Info(
                      titre: 'Membre depuis',
                      valeur: '${d.day} ${moisEnFrancais(d)} ${d.year}',
                    ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            if (widget.api != null) ...[
              CarteReglages(
                titre: 'Serveur JARVIS',
                enfants: [_ligneServeur(u.identifiant)],
              ),
              const SizedBox(height: 24),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: c.enCours ? null : c.deconnecter,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(PanneauCompte.deconnexion),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB0444F),
                  side: BorderSide(
                    color: const Color(0xFFB0444F).withValues(alpha: 0.35),
                  ),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ligneServeur(String identifiant) {
    final (icone, couleur, texte) = switch (_serveur) {
      null => (
        Icons.sync_rounded,
        CouleursJarvis.texteSecondaire,
        'Vérification…',
      ),
      SuccesApi(:final valeur) when valeur.identifiant == identifiant => (
        Icons.verified_outlined,
        CouleursJarvis.signal,
        PanneauCompte.serveurOk,
      ),
      SuccesApi() => (
        Icons.error_outline_rounded,
        const Color(0xFFB0444F),
        PanneauCompte.serveurDifferent,
      ),
      EchecApi(:final type, :final detail) => (
        Icons.cloud_off_rounded,
        const Color(0xFFB0444F),
        detail == null ? type.message : '${type.message} ($detail)',
      ),
    };
    return LigneReglage(
      titre: 'Connexion au serveur',
      description: widget.api!.adresse.toString(),
      largeurControle: 280,
      controle: Row(
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _verification && _serveur == null ? 'Vérification…' : texte,
              style: TextStyle(fontSize: 13, height: 1.35, color: couleur),
            ),
          ),
          IconButton(
            tooltip: 'Vérifier à nouveau',
            onPressed: _verification ? null : _verifierServeur,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ),
    );
  }

  static String _limites(ProfilCompte p) {
    final m = p.limiteMessagesJour;
    return m == null ? 'Illimitée' : '$m messages';
  }

  Widget _sansCompte({required bool serveur}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteReglages(
          enfants: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TexteReglage(
                titre: PanneauCompte.sansCompte,
                description: serveur
                    ? 'JARVIS est ouvert sans compte (accès de '
                          'développement). Connectez-vous pour retrouver '
                          'votre profil.'
                    : 'Aucun serveur de comptes n’est configuré dans cette '
                          'version de JARVIS.',
              ),
            ),
          ],
        ),
        if (serveur && widget.surConnexion != null) ...[
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.surConnexion,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Se connecter'),
              style: FilledButton.styleFrom(
                backgroundColor: CouleursJarvis.signal,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static InputDecoration _decoration() {
    OutlineInputBorder bord(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: CouleursJarvis.ivoire,
      counterText: '',
      helperText: ' ',
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: bord(CouleursJarvis.trait),
      enabledBorder: bord(CouleursJarvis.trait),
      focusedBorder: bord(CouleursJarvis.signal.withValues(alpha: 0.6)),
    );
  }
}

/// Avatar (initiale), nom, adresse e-mail et offre.
class _EnTeteCompte extends StatelessWidget {
  const _EnTeteCompte({required this.nom, required this.email, this.offre});

  final String nom;
  final String email;
  final OffreCompte? offre;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: CouleursJarvis.signal.withValues(alpha: 0.14),
          child: Text(
            nom.isEmpty ? '?' : nom.characters.first.toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: CouleursJarvis.signal,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CouleursJarvis.texte,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
            ],
          ),
        ),
        if (offre case final o?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: CouleursJarvis.violet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              o == OffreCompte.pro ? 'Pro' : 'Gratuit',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CouleursJarvis.signal,
              ),
            ),
          ),
      ],
    );
  }
}

/// Information en lecture seule (titre à gauche, valeur à droite).
class _Info extends StatelessWidget {
  const _Info({required this.titre, required this.valeur});

  final String titre;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titre,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
