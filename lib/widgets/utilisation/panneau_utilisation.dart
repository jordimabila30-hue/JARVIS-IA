import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/utilisation/utilisation.dart';
import '../../pages/utilisation_page.dart';
import '../../services/api_jarvis.dart';
import '../../services/utilisation/service_utilisation.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/format_utilisation.dart';
import '../parametres/elements_parametres.dart';
import 'jauge_utilisation.dart';

/// « Réinitialisation dans 2 h 14 min » ou, sans session en cours,
/// « Commence au prochain message · 5 h ».
String texteSession(Utilisation u, DateTime maintenant) {
  final s = u.session;
  final fin = s.fin;
  if (s.active && fin != null) {
    final reste = fin.difference(maintenant);
    return reste.isNegative
        ? 'Session terminée : la suivante commence au prochain message.'
        : 'Réinitialisation dans ${dureeRestante(reste)} (${momentLocal(fin, maintenant)})';
  }
  final duree = s.dureeMinutes;
  return duree == null
      ? 'Aucune session en cours.'
      : 'Aucune session en cours : elle commencera au prochain message '
            'et durera ${dureeRestante(Duration(minutes: duree))}.';
}

/// « Remise à zéro demain à 02:00 ».
String texteJour(Utilisation u, DateTime maintenant) {
  final fin = u.finJour;
  return fin == null ? 'Remise à zéro chaque jour.' : 'Remise à zéro ${momentLocal(fin, maintenant)}';
}

/// « Claude · Anthropic — claude-opus-5-5 ».
String texteFournisseur(FournisseurIA f) => [
  f.libelle ?? 'Fournisseur inconnu',
  if (f.modele != null) f.modele!,
].join(' — ');

/// Explication quand l'offre prévoit un autre fournisseur que celui qui
/// sert vraiment (routage par abonnement pas encore activé).
String? texteFournisseurActif(Utilisation u) {
  final actif = u.actif;
  if (actif == null || !u.fournisseurDifferent) return null;
  return 'Actuellement servi par ${texteFournisseur(actif)} : '
      'l’attribution du fournisseur selon l’abonnement n’est pas encore activée.';
}

/// Message d'une lecture impossible.
String texteIndisponible(ErreurApi? e) => switch (e) {
  ErreurApi.nonConnecte || ErreurApi.sessionExpiree =>
    'Connectez-vous pour consulter votre utilisation.',
  ErreurApi.injoignable => 'Le serveur JARVIS est injoignable : utilisation indisponible pour le moment.',
  _ => 'Utilisation indisponible pour le moment.',
};

/// Section « Utilisation » des Paramètres : synthèse (offre, session,
/// jour) et accès aux détails. Ne montre que ce que le serveur envoie.
class PanneauUtilisation extends StatefulWidget {
  const PanneauUtilisation({super.key, required this.service, this.horloge});

  /// null : JARVIS ouvert sans compte.
  final ServiceUtilisation? service;
  final DateTime Function()? horloge;

  @override
  State<PanneauUtilisation> createState() => _PanneauUtilisationState();
}

class _PanneauUtilisationState extends State<PanneauUtilisation> {
  Timer? _minute;
  bool _detailsSession = false;

  DateTime get _maintenant => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.service?.suivre();
    // Compte à rebours de la session (aucun appel réseau) ; fin constatée
    // → nouvelle lecture du serveur.
    _minute = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final u = widget.service?.donnees;
      if (u != null && u.session.termineeA(_maintenant)) {
        widget.service?.actualiser(force: true);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    widget.service?.cesserDeSuivre();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (service == null) {
      return const CarteReglages(enfants: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: NoteReglage('Connectez-vous pour consulter votre utilisation de JARVIS.'),
        ),
      ]);
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final u = service.donnees;
        if (u == null) return _Attente(service: service);
        final maintenant = _maintenant;
        final s = u.session;
        final principale = s.principale;
        final actif = texteFournisseurActif(u);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CarteReglages(
              enfants: [
                _EnTete(utilisation: u),
                JaugeUtilisation(
                  key: const ValueKey('jauge-session'),
                  titre: 'Limite de session',
                  jauge: principale,
                  unite: identical(principale, s.tokens) ? 'tokens' : 'messages',
                  sousTitre: texteSession(u, maintenant),
                ),
                if (_detailsSession) ...[
                  JaugeUtilisation(
                    key: const ValueKey('jauge-session-messages'),
                    titre: 'Messages de la session',
                    jauge: s.messages,
                    unite: 'messages',
                    compacte: true,
                  ),
                  JaugeUtilisation(
                    key: const ValueKey('jauge-session-tokens'),
                    titre: 'Tokens de la session',
                    jauge: s.tokens,
                    unite: 'tokens',
                    compacte: true,
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _detailsSession = !_detailsSession),
                    icon: Icon(_detailsSession ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                    label: Text(_detailsSession ? 'Masquer le détail de la session' : 'Détail de la session'),
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursJarvis.signal,
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                ),
                JaugeUtilisation(
                  key: const ValueKey('jauge-messages-jour'),
                  titre: 'Messages aujourd’hui',
                  jauge: u.messagesJour,
                  unite: 'messages',
                  sousTitre: texteJour(u, maintenant),
                ),
                JaugeUtilisation(
                  key: const ValueKey('jauge-tokens-jour'),
                  titre: 'Tokens aujourd’hui',
                  jauge: u.tokensJour,
                  unite: 'tokens',
                  sousTitre: u.exception ? 'Limites personnelles de votre compte.' : null,
                ),
              ],
            ),
            if (actif != null) ...[
              const SizedBox(height: 12),
              NoteReglage(actif),
            ],
            const SizedBox(height: 12),
            _Pied(service: service, maintenant: maintenant),
          ],
        );
      },
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.utilisation});

  final Utilisation utilisation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: CouleursJarvis.violetPoudre,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.data_usage_rounded, color: CouleursJarvis.signal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Utilisation',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: CouleursJarvis.texte),
                    ),
                    _Pastille(utilisation.nomOffre),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  texteFournisseur(utilisation.offre),
                  style: const TextStyle(fontSize: 12.5, color: CouleursJarvis.texteSecondaire),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CouleursJarvis.signal.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursJarvis.signal.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          texte,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CouleursJarvis.signal),
        ),
      ),
    );
  }
}

/// Mise à jour, actualisation manuelle, « Voir les détails ».
class _Pied extends StatelessWidget {
  const _Pied({required this.service, required this.maintenant});

  final ServiceUtilisation service;
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final maj = service.miseAJour;
    final erreur = service.erreur;
    final etat = erreur != null
        ? 'Actualisation impossible — ${texteIndisponible(erreur).toLowerCase()}'
        : maj == null
        ? ''
        : 'Mis à jour ${maintenant.difference(maj).inMinutes < 1 ? 'à l’instant' : 'il y a ${dureeRestante(maintenant.difference(maj))}'}';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: service.chargement ? null : () => service.actualiser(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: CouleursJarvis.texteSecondaire,
            ),
            Flexible(
              child: Text(etat, style: const TextStyle(fontSize: 12, color: CouleursJarvis.texteSecondaire)),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () => ouvrirPageUtilisation(context, service),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Voir les détails'),
          style: FilledButton.styleFrom(
            backgroundColor: CouleursJarvis.signal,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

/// Première lecture en cours, ou impossible (avec « Réessayer »).
class _Attente extends StatelessWidget {
  const _Attente({required this.service});

  final ServiceUtilisation service;

  @override
  Widget build(BuildContext context) {
    final erreur = service.erreur;
    return CarteReglages(
      enfants: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: erreur == null
              ? const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: CouleursJarvis.signal),
                    ),
                    SizedBox(width: 14),
                    Text('Lecture de votre utilisation…', style: TextStyle(color: CouleursJarvis.texteSecondaire)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoteReglage(texteIndisponible(erreur)),
                    if (erreur != ErreurApi.nonConnecte && erreur != ErreurApi.sessionExpiree)
                      TextButton.icon(
                        onPressed: service.chargement ? null : () => service.actualiser(force: true),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Réessayer'),
                        style: TextButton.styleFrom(foregroundColor: CouleursJarvis.signal),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
