import 'dart:async';

import 'package:flutter/material.dart';

import '../models/utilisation/utilisation.dart';
import '../services/utilisation/service_utilisation.dart';
import '../theme/theme_jarvis.dart';
import '../utils/format_utilisation.dart';
import '../utils/local_date_time.dart';
import '../widgets/parametres/elements_parametres.dart';
import '../widgets/utilisation/jauge_utilisation.dart';
import '../widgets/utilisation/panneau_utilisation.dart';

/// Ouvre la page détaillée par-dessus l'écran courant (Paramètres).
Future<void> ouvrirPageUtilisation(BuildContext context, ServiceUtilisation service) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UtilisationPage(service: service)),
    );

/// Détail de l'utilisation : offre et fournisseur, session, journée,
/// restants, fin de session et prochaine remise à zéro. Toutes les valeurs
/// viennent du serveur (`/me/quota`).
class UtilisationPage extends StatefulWidget {
  const UtilisationPage({super.key, required this.service, this.horloge});

  final ServiceUtilisation service;
  final DateTime Function()? horloge;

  @override
  State<UtilisationPage> createState() => _UtilisationPageState();
}

class _UtilisationPageState extends State<UtilisationPage> {
  Timer? _minute;

  DateTime get _maintenant => (widget.horloge ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.service.suivre();
    _minute = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final u = widget.service.donnees;
      if (u != null && u.session.termineeA(_maintenant)) widget.service.actualiser(force: true);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
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
                      SliverToBoxAdapter(child: _Barre(service: widget.service)),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(marge, 4, marge, 32),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: u == null
                                  ? NoteReglage(
                                      widget.service.erreur == null
                                          ? 'Lecture de votre utilisation…'
                                          : texteIndisponible(widget.service.erreur),
                                    )
                                  : _Contenu(utilisation: u, maintenant: maintenant, service: widget.service),
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
  const _Barre({required this.service});

  final ServiceUtilisation service;

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
          const Expanded(
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
          IconButton(
            tooltip: 'Actualiser',
            onPressed: service.chargement ? null : () => service.actualiser(force: true),
            icon: const Icon(Icons.refresh_rounded),
            color: CouleursJarvis.texteSecondaire,
          ),
        ],
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.utilisation, required this.maintenant, required this.service});

  final Utilisation utilisation;
  final DateTime maintenant;
  final ServiceUtilisation service;

  String _instant(DateTime? t) => t == null ? '—' : momentLocal(t, maintenant);

  String _reste(Jauge j, String unite) =>
      j.illimitee ? 'illimité' : '${nombreGroupe(j.reste!)} $unite';

  @override
  Widget build(BuildContext context) {
    final u = utilisation;
    final s = u.session;
    final actif = u.actif;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteReglages(
          titre: 'Offre',
          enfants: [
            _Ligne('Abonnement', u.nomOffre),
            _Ligne('Fournisseur de l’offre', u.offre.libelle ?? '—'),
            _Ligne('Modèle associé', u.offre.modele ?? '—'),
            if (actif != null)
              _Ligne(
                'Fournisseur utilisé',
                texteFournisseur(actif),
                note: u.fournisseurDifferent ? texteFournisseurActif(u) : null,
              ),
            if (u.exception)
              const _Ligne('Limites quotidiennes', 'personnelles (exception de votre compte)'),
            if (u.seuilCritique != null)
              _Ligne('Seuil d’alerte des jauges', '${u.seuilCritique} %'),
          ],
        ),
        const SizedBox(height: 22),
        CarteReglages(
          titre: 'Session',
          enfants: [
            _Ligne('État', s.active && !s.termineeA(maintenant) ? 'En cours' : 'Aucune session en cours'),
            if (s.active) ...[
              _Ligne('Début', _instant(s.debut)),
              _Ligne('Fin de session', _instant(s.fin)),
            ],
            if (s.dureeMinutes != null) _Ligne('Durée d’une session', dureeRestante(Duration(minutes: s.dureeMinutes!))),
            JaugeUtilisation(
              key: const ValueKey('detail-session-messages'),
              titre: 'Messages de la session',
              jauge: s.messages,
              unite: 'messages',
              sousTitre: 'Restants : ${_reste(s.messages, 'messages')}',
            ),
            JaugeUtilisation(
              key: const ValueKey('detail-session-tokens'),
              titre: 'Tokens de la session',
              jauge: s.tokens,
              unite: 'tokens',
              sousTitre: 'Restants : ${_reste(s.tokens, 'tokens')}',
            ),
            NoteReglage(texteSession(u, maintenant)),
            const SizedBox(height: 12),
          ],
        ),
        const SizedBox(height: 22),
        CarteReglages(
          titre: 'Aujourd’hui',
          enfants: [
            JaugeUtilisation(
              key: const ValueKey('detail-jour-messages'),
              titre: 'Messages',
              jauge: u.messagesJour,
              unite: 'messages',
              sousTitre: 'Restants : ${_reste(u.messagesJour, 'messages')}',
            ),
            JaugeUtilisation(
              key: const ValueKey('detail-jour-tokens'),
              titre: 'Tokens',
              jauge: u.tokensJour,
              unite: 'tokens',
              sousTitre: 'Restants : ${_reste(u.tokensJour, 'tokens')}',
            ),
            _Ligne('Prochaine remise à zéro', _instant(u.finJour)),
          ],
        ),
        const SizedBox(height: 18),
        NoteReglage(
          'Valeurs calculées par le serveur JARVIS d’après votre abonnement'
          '${service.miseAJour == null ? '' : ' — mises à jour à ${heureCourte(service.miseAJour!)}'}.',
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
              Text(libelle, style: const TextStyle(fontSize: 14, color: CouleursJarvis.texteSecondaire)),
              Text(
                valeur,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: CouleursJarvis.texte),
              ),
            ],
          ),
          if (note != null) ...[const SizedBox(height: 8), NoteReglage(note!)],
        ],
      ),
    );
  }
}
