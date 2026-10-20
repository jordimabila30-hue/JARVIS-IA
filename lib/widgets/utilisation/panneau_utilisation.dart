import 'package:flutter/material.dart';

import '../../models/utilisation/utilisation.dart';
import '../../pages/utilisation_page.dart';
import '../../services/api_jarvis.dart';
import '../../services/utilisation/service_utilisation.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/format_utilisation.dart';
import '../parametres/elements_parametres.dart';
import 'jauge_utilisation.dart';

/// « Remise à zéro demain à 02:00 ».
String texteJour(Utilisation u, DateTime maintenant) {
  final fin = u.finJour;
  return fin == null
      ? 'Remise à zéro chaque jour.'
      : 'Remise à zéro ${momentLocal(fin, maintenant)}';
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

/// Dernière lecture échouée alors que des valeurs sont affichées : elles
/// restent, signalées discrètement avec l'heure de leur lecture (null : à
/// jour, ou relecture silencieuse en cours).
String? texteDonneesAnciennes(
  ServiceUtilisation service, [
  DateTime? maintenant,
]) {
  if (service.erreur == null || service.donnees == null) return null;
  final lu = service.miseAJour;
  final quand = lu == null
      ? ''
      : ' (lues ${momentLocal(lu, maintenant ?? DateTime.now())})';
  return 'Dernières valeurs connues$quand : elles peuvent ne plus être à jour.';
}

/// Copie locale d'une journée terminée : la consommation du jour n'est pas
/// encore connue (jamais celle de la veille présentée comme celle du jour).
const texteNouvelleJournee =
    'Nouvelle journée : la consommation d’aujourd’hui s’affichera à la prochaine synchronisation.';

/// Message d'une lecture impossible.
String texteIndisponible(ErreurApi? e) => switch (e) {
  ErreurApi.nonConnecte || ErreurApi.sessionExpiree =>
    'Connectez-vous pour consulter votre utilisation.',
  ErreurApi.injoignable =>
    'Le serveur JARVIS est injoignable : utilisation indisponible pour le moment.',
  _ => 'Utilisation indisponible pour le moment.',
};

/// Section « Utilisation » des Paramètres : offre, deux jauges
/// quotidiennes (messages, tokens) et accès aux détails. Affichée aussitôt
/// (dernières valeurs gardées sur l'appareil, sinon structure avec « — »),
/// actualisée automatiquement et en silence : aucun bouton, aucun
/// chargement. Ne montre que ce que le serveur a envoyé.
class PanneauUtilisation extends StatefulWidget {
  const PanneauUtilisation({super.key, required this.service, this.horloge});

  /// null : JARVIS ouvert sans compte.
  final ServiceUtilisation? service;
  final DateTime Function()? horloge;

  @override
  State<PanneauUtilisation> createState() => _PanneauUtilisationState();
}

class _PanneauUtilisationState extends State<PanneauUtilisation> {
  DateTime get _maintenant => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Lecture immédiate puis toutes les 30 s tant que le panneau est
    // affiché ; tout le reste (après l'IA, premier plan, compte) est géré
    // par le service.
    widget.service?.suivre();
  }

  @override
  void dispose() {
    widget.service?.cesserDeSuivre();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (service == null) {
      return const CarteReglages(
        enfants: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: NoteReglage(
              'Connectez-vous pour consulter votre utilisation de JARVIS.',
            ),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final u = service.donnees;
        final maintenant = _maintenant;
        // Copie d'une journée terminée : consommation du jour inconnue.
        final terminee = service.journeeTerminee;
        final jour = terminee ? null : u;
        final actif = u == null ? null : texteFournisseurActif(u);
        // Première lecture impossible : explication discrète, la structure
        // reste affichée.
        final note = u == null && service.erreur != null
            ? texteIndisponible(service.erreur)
            : texteDonneesAnciennes(service, maintenant);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CarteReglages(
              enfants: [
                _EnTete(utilisation: u),
                JaugeUtilisation(
                  key: const ValueKey('jauge-messages-jour'),
                  titre: 'Messages aujourd’hui',
                  jauge: jour?.messagesJour,
                  unite: 'messages',
                  sousTitre: terminee
                      ? texteNouvelleJournee
                      : jour == null
                      ? null
                      : texteJour(jour, maintenant),
                ),
                JaugeUtilisation(
                  key: const ValueKey('jauge-tokens-jour'),
                  titre: 'Tokens aujourd’hui',
                  jauge: jour?.tokensJour,
                  unite: 'tokens',
                  sousTitre: u?.exception == true
                      ? 'Limites personnelles de votre compte.'
                      : null,
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              _NoteDiscrete(
                note,
                horsLigne: service.erreur == ErreurApi.injoignable,
                key: const ValueKey('donnees-anciennes'),
              ),
            ],
            if (actif != null) ...[
              const SizedBox(height: 12),
              NoteReglage(actif),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _VoirDetails(service: service),
            ),
          ],
        );
      },
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.utilisation});

  /// null : offre pas encore connue.
  final Utilisation? utilisation;

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
            child: Icon(
              Icons.data_usage_rounded,
              color: CouleursJarvis.signal,
              size: 22,
            ),
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
                    Text(
                      'Utilisation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    if (utilisation != null) _Pastille(utilisation!.nomOffre),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  utilisation == null
                      ? '—'
                      : texteFournisseur(utilisation!.offre),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: CouleursJarvis.texteSecondaire,
                  ),
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
        border: Border.all(
          color: CouleursJarvis.signal.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          texte,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: CouleursJarvis.signal,
          ),
        ),
      ),
    );
  }
}

class _VoirDetails extends StatelessWidget {
  const _VoirDetails({required this.service});

  final ServiceUtilisation service;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => ouvrirPageUtilisation(context, service),
      icon: const Icon(Icons.insights_rounded, size: 18),
      label: const Text('Voir les détails'),
      style: FilledButton.styleFrom(
        backgroundColor: CouleursJarvis.signal,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Petite ligne grise avec une icône (données peut-être anciennes,
/// utilisation indisponible).
class _NoteDiscrete extends StatelessWidget {
  const _NoteDiscrete(this.texte, {this.horsLigne = false, super.key});

  final String texte;

  /// Serveur injoignable : nuage barré ; sinon simple information.
  final bool horsLigne;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            horsLigne ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
            size: 15,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(
              fontSize: 12,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
      ],
    );
  }
}
