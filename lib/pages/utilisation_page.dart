import 'package:flutter/material.dart';

import '../models/utilisation/utilisation.dart';
import '../services/utilisation/service_utilisation.dart';
import '../theme/theme_jarvis.dart';
import '../utils/format_utilisation.dart';
import '../widgets/parametres/elements_parametres.dart';
import '../widgets/utilisation/jauge_utilisation.dart';
import '../widgets/utilisation/panneau_utilisation.dart';

/// Ouvre la page détaillée par-dessus l'écran courant (Paramètres).
Future<void> ouvrirPageUtilisation(
  BuildContext context,
  ServiceUtilisation service,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => UtilisationPage(service: service)),
);

/// Détail de l'utilisation : offre et fournisseur, consommation du jour,
/// restants et prochaine remise à zéro (quotas quotidiens seulement).
/// Affichée aussitôt (dernières valeurs gardées sur l'appareil, sinon
/// « — »), actualisée automatiquement et en silence, sans bouton. Toutes
/// les valeurs viennent du serveur (`/me/quota`).
class UtilisationPage extends StatefulWidget {
  const UtilisationPage({super.key, required this.service, this.horloge});

  final ServiceUtilisation service;
  final DateTime Function()? horloge;

  @override
  State<UtilisationPage> createState() => _UtilisationPageState();
}

class _UtilisationPageState extends State<UtilisationPage> {
  DateTime get _maintenant => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.service.suivre();
  }

  @override
  void dispose() {
    widget.service.cesserDeSuivre();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursJarvis.ivoirePrincipal,
      body: FondJarvis(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.service,
            builder: (context, _) {
              final u = widget.service.donnees;
              final maintenant = _maintenant;
              return LayoutBuilder(
                builder: (context, c) {
                  final marge = c.maxWidth < 600 ? 16.0 : 32.0;
                  return CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: _Barre()),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(marge, 4, marge, 32),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: _Contenu(
                                utilisation: u,
                                maintenant: maintenant,
                                service: widget.service,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Barre extends StatelessWidget {
  const _Barre();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: CouleursJarvis.texte,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Utilisation',
              style: TextStyle(
                fontFamily: policeAffichage,
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.utilisation,
    required this.maintenant,
    required this.service,
  });

  /// null : pas encore lue (structure affichée avec « — »).
  final Utilisation? utilisation;
  final DateTime maintenant;
  final ServiceUtilisation service;

  String _instant(DateTime? t) => t == null ? '—' : momentLocal(t, maintenant);

  String _reste(Jauge? j, String unite) => j == null
      ? '—'
      : j.illimitee
      ? 'illimité'
      : '${nombreGroupe(j.reste!)} $unite';

  @override
  Widget build(BuildContext context) {
    final u = utilisation;
    final actif = u?.actif;
    // Copie d'une journée terminée : consommation du jour inconnue.
    final terminee = service.journeeTerminee;
    final jour = terminee ? null : u;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteReglages(
          titre: 'Offre',
          enfants: [
            _Ligne('Abonnement', u?.nomOffre ?? '—'),
            _Ligne('Fournisseur de l’offre', u?.offre.libelle ?? '—'),
            _Ligne('Modèle associé', u?.offre.modele ?? '—'),
            if (u != null && actif != null)
              _Ligne(
                'Fournisseur utilisé',
                texteFournisseur(actif),
                note: u.fournisseurDifferent ? texteFournisseurActif(u) : null,
              ),
            if (u?.exception == true)
              const _Ligne(
                'Limites quotidiennes',
                'personnelles (exception de votre compte)',
              ),
            if (u?.seuilCritique != null)
              _Ligne('Seuil d’alerte des jauges', '${u!.seuilCritique} %'),
          ],
        ),
        const SizedBox(height: 22),
        CarteReglages(
          titre: 'Aujourd’hui',
          enfants: [
            JaugeUtilisation(
              key: const ValueKey('detail-jour-messages'),
              titre: 'Messages',
              jauge: jour?.messagesJour,
              unite: 'messages',
              sousTitre: terminee
                  ? texteNouvelleJournee
                  : 'Restants : ${_reste(jour?.messagesJour, 'messages')}',
            ),
            JaugeUtilisation(
              key: const ValueKey('detail-jour-tokens'),
              titre: 'Tokens',
              jauge: jour?.tokensJour,
              unite: 'tokens',
              sousTitre: 'Restants : ${_reste(jour?.tokensJour, 'tokens')}',
            ),
            _Ligne('Prochaine remise à zéro', _instant(jour?.finJour)),
          ],
        ),
        const SizedBox(height: 18),
        NoteReglage(
          (u == null && service.erreur != null
                  ? texteIndisponible(service.erreur)
                  : null) ??
              texteDonneesAnciennes(service, maintenant) ??
              'Valeurs calculées par le serveur JARVIS d’après votre abonnement, actualisées automatiquement.',
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.libelle, this.valeur, {this.note});

  final String libelle;
  final String valeur;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                libelle,
                style: TextStyle(
                  fontSize: 14,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              Text(
                valeur,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: CouleursJarvis.texte,
                ),
              ),
            ],
          ),
          if (note != null) ...[const SizedBox(height: 8), NoteReglage(note!)],
        ],
      ),
    );
  }
}
