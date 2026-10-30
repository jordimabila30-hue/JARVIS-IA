import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/importation/reference_whatsapp.dart';
import '../../models/message_conversation.dart';
import '../../services/ecriture/ecriture_progressive.dart';
import '../../theme/gabarit_jarvis.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/chrono_perf.dart';
import '../apparence/frise_kuba.dart';
import '../ecriture/texte_progressif.dart';
import 'choix_ton.dart';
import 'heure_message.dart';
import 'indicateur_generation.dart';
import '../../models/importation/propositions_reponse.dart';
import 'propositions_jarvis.dart';
import 'references_jarvis.dart';
import 'signature_jarvis.dart';
import 'texte_riche.dart';
import 'reponse_proposee.dart';

/// Habillage commun des messages de JARVIS : carte du style (ivoire nuancée
/// de lavande pour JARVIS ; frise et ombre pleine pour les styles importés),
/// signature « • JARVIS » ([SignatureJarvis]), heure en bas à
/// droite.
class _CadreJarvis extends StatelessWidget {
  const _CadreJarvis({
    required this.child,
    this.heure,
    this.ecriture,
    this.indicateur,
  });

  final Widget child;

  /// Réception en cours (« Rédaction… ») : à droite de la signature, posé
  /// par-dessus la ligne (la carte ne change pas de hauteur à la fin).
  final Widget? indicateur;

  /// Heure de la réponse ; aucune pendant la réflexion.
  final DateTime? heure;

  /// Écriture en cours : « Tout afficher » discret, à gauche de l'heure
  /// (posé par-dessus la ligne : la carte ne change pas de hauteur).
  final EcritureProgressive? ecriture;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final id = p.identite;
    final marges = EdgeInsets.fromLTRB(18, 14, 16, heure == null ? 16 : 10);
    final frise = id.frise;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        padding: frise == null ? marges : null,
        // Styles importés : la frise kuba suit l'arrondi de la carte.
        clipBehavior: frise == null ? Clip.none : Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Fond très légèrement translucide (94 %) : les particules qui
            // passent derrière restent devinables, le texte reste net.
            colors: p.carteJarvis,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          // Styles importés : contour marqué (texte à 35 %) et ombre pleine
          // décalée de 5 px, comme les cartes de la source.
          border: Border.all(
            color: id.marquee
                ? p.texte.withValues(alpha: 0.35)
                : p.trait.withValues(alpha: 0.6),
            width: id.marquee ? id.contour : 1,
          ),
          // Mesure seulement (JARVIS_PERF) : coût des ombres.
          boxShadow: ChronoPerf.sans('bulle.ombre')
              ? null
              : [
                  if (id.ombreCarte case final ombre?)
                    BoxShadow(color: ombre, offset: const Offset(5, 5))
                  else
                    BoxShadow(
                      color: p.ombre.withAlpha(0x0A),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                ],
        ),
        child: frise == null
            ? _contenu(context)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FriseKuba(couleurs: frise, fond: p.creme),
                  Padding(padding: marges, child: _contenu(context)),
                ],
              ),
      ),
    );
  }

  Widget _contenu(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Même signature pour toutes les réponses de JARVIS.
        SizedBox(
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SignatureJarvis(compacte: GabaritJarvis.of(context).compact),
              if (indicateur case final i?)
                Positioned(
                  right: 0,
                  top: -2,
                  left: 90,
                  child: Align(alignment: Alignment.centerRight, child: i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        child,
        if (heure != null) ...[
          const SizedBox(height: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: HeureMessage(heure!),
              ),
              if (ecriture case final e?)
                Positioned(
                  left: -6,
                  top: -6,
                  bottom: -6,
                  child: Center(child: ActionToutAfficher(ecriture: e)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Message de JARVIS : texte, et selon le cas raccourcis discrets ou
/// « Quel ton ? » puis « Réponse proposée ».
class CarteJarvis extends StatelessWidget {
  const CarteJarvis({
    super.key,
    required this.message,
    required this.surTon,
    required this.surAction,
    this.surChoix,
    this.surReference,
    this.surTonPropositions,
    this.surStatutProposition,
    this.tonPropositions,
    this.longueurPropositions,
    this.contactPropositions,
    this.surReprendrePropositions,
    this.repriseEnCours = false,
    this.preparation = false,
    this.taille = 15,
  });

  final MessageConversation message;
  final ValueChanged<TonReponse> surTon;
  final ValueChanged<ActionRapide> surAction;

  /// Décision sous la réponse (accord pour l'analyse, nouvel essai).
  final ValueChanged<ChoixJarvis>? surChoix;

  /// Appui sur un message d'origine (ouvre « Voir les messages » dessus).
  final ValueChanged<ReferenceWhatsApp>? surReference;

  /// Ton et longueur affichés dans les propositions (aide à répondre).
  final SurReglagePropositions? surTonPropositions;

  /// Appui long sur une proposition : déclarée envoyée / annulée.
  final SurStatutProposition? surStatutProposition;

  /// Ton affiché d'emblée dans les propositions (mémorisé par la session).
  final String? tonPropositions;
  final LongueurProposition? longueurPropositions;

  /// Destinataire des propositions (bulle de la réponse retenue).
  final String? contactPropositions;

  /// Génération incomplète : « Reprendre » (et reprise en cours).
  final Future<bool> Function()? surReprendrePropositions;
  final bool repriseEnCours;

  /// Le serveur prépare les propositions (texte déjà écrit) : trois points
  /// animés sous le texte, jusqu'à leur arrivée.
  final bool preparation;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: taille,
      height: 1.55,
      letterSpacing: 0.1,
      color: CouleursJarvis.texte,
    );
    final ecriture = message.ecriture;
    if (ecriture == null) {
      return _CadreJarvis(
        heure: message.heure,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TexteRiche.utile(message.texte)
                ? TexteRiche(texte: message.texte, style: style)
                : Text(message.texte, style: style),
            ..._suite(),
          ],
        ),
      );
    }
    return _CadreJarvis(
      heure: message.heure,
      ecriture: ecriture,
      // Seulement pendant la réception réelle (fragments du serveur) :
      // disparaît à la fin, la bulle retrouve exactement son aspect.
      indicateur: message.redaction && !preparation
          ? const IndicateurGeneration(
              libelle: IndicateurGeneration.redaction,
              libelleLong: IndicateurGeneration.longue,
              delaiLong: Duration(seconds: 25),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Code ou tableau : mis en forme une fois la réponse terminée
          // (pendant l'écriture, le texte se prolonge sans changer de forme).
          if (TexteRiche.utile(message.texte))
            ValueListenableBuilder<bool>(
              valueListenable: ecriture.finie,
              builder: (context, finie, _) => finie && !message.redaction
                  ? TexteRiche(texte: message.texte, style: style)
                  : TexteProgressif(ecriture: ecriture, style: style),
            )
          else
            TexteProgressif(ecriture: ecriture, style: style),
          if (preparation && message.redaction)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: PreparationPropositions(),
            ),
          // Choix du ton, raccourcis, explication d'une interruption :
          // une fois le texte entièrement écrit (rien ne bouge sous un
          // texte qui s'écrit encore).
          ValueListenableBuilder<bool>(
            valueListenable: ecriture.finie,
            builder: (context, finie, _) {
              final suite = finie && !message.redaction ? _suite() : null;
              if (suite == null || suite.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: suite,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Ce qui suit le texte : interruption, choix du ton, réponse proposée,
  /// raccourcis.
  List<Widget> _suite() {
    final reponse = message.reponseProposee;
    final incident = message.incident;
    return [
      if (incident != null) ...[
        const SizedBox(height: 12),
        _Incident(texte: incident),
      ],
      if (message.propositions case final propositions?) ...[
        const SizedBox(height: 16),
        PropositionsJarvis(
          propositions: propositions,
          surTon: surTonPropositions,
          surStatut: surStatutProposition,
          tonInitial: tonPropositions,
          longueurInitiale: longueurPropositions,
          contact: contactPropositions,
          surReprendre: surReprendrePropositions,
          repriseEnCours: repriseEnCours,
          taille: taille,
        ),
      ],
      if (message.references.isNotEmpty || message.noteReferences != null) ...[
        const SizedBox(height: 14),
        ReferencesJarvis(
          references: message.references,
          note: message.noteReferences,
          surReference: surReference,
        ),
      ],
      if (message.choixTon) ...[
        const SizedBox(height: 18),
        ChoixTon(ton: message.ton, surChoix: surTon),
      ],
      if (reponse != null) ...[
        const SizedBox(height: 18),
        ReponseProposee(texte: reponse, taille: taille),
      ],
      if (message.actions.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in message.actions)
              _Raccourci(action: a, surAction: () => surAction(a)),
          ],
        ),
      ],
      if (message.choix.isNotEmpty && surChoix != null) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, c) in message.choix.indexed)
              _BoutonChoix(
                libelle: c.libelle,
                principal: i == 0,
                surAppui: () => surChoix!(c),
              ),
          ],
        ),
      ],
    ];
  }
}

/// Réponse interrompue : pourquoi le texte s'arrête (discret, sous le
/// texte reçu).
class _Incident extends StatelessWidget {
  const _Incident({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1, right: 6),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
      ],
    );
  }
}

/// Raccourci discret (« Comprendre », « Résumer »…).
class _Raccourci extends StatelessWidget {
  const _Raccourci({required this.action, required this.surAction});

  final ActionRapide action;
  final VoidCallback surAction;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: surAction,
      style: OutlinedButton.styleFrom(
        foregroundColor: CouleursJarvis.signal,
        backgroundColor: CouleursJarvis.voile.withValues(alpha: 0.5),
        side: BorderSide(color: CouleursJarvis.signal.withValues(alpha: 0.25)),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(action.libelle),
    );
  }
}

/// Décision sous une réponse (« Autoriser l'analyse », « Pas maintenant »,
/// « Réessayer ») : le premier choix est mis en avant, discrètement.
class _BoutonChoix extends StatelessWidget {
  const _BoutonChoix({
    required this.libelle,
    required this.principal,
    required this.surAppui,
  });

  final String libelle;
  final bool principal;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: principal
          ? CouleursJarvis.surSignal
          : CouleursJarvis.signal,
      backgroundColor: principal
          ? CouleursJarvis.signal
          : CouleursJarvis.voile.withValues(alpha: 0.5),
      side: BorderSide(
        color: CouleursJarvis.signal.withValues(alpha: principal ? 1 : 0.25),
      ),
      shape: const StadiumBorder(),
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );
    return OutlinedButton(
      onPressed: surAppui,
      style: style,
      child: Text(libelle),
    );
  }
}

/// Propositions en préparation (événement `preparation` du serveur) :
/// cercle et courte légende sous le texte, jusqu'à leur arrivée.
class PreparationPropositions extends StatelessWidget {
  const PreparationPropositions({super.key});

  @override
  Widget build(BuildContext context) {
    return const KeyedSubtree(
      key: Key('preparation-propositions'),
      child: IndicateurGeneration(
        libelle: IndicateurGeneration.propositions,
        libelleLong: IndicateurGeneration.longue,
        delaiLong: Duration(seconds: 30),
      ),
    );
  }
}

/// JARVIS prépare sa réponse (aucun fragment reçu) : cercle qui tourne et
/// « Préparation… », ou « Connexion au serveur JARVIS… » pendant le réveil
/// du serveur hébergé (état réel, signalé par l'API).
class ReflexionJarvis extends StatelessWidget {
  const ReflexionJarvis({super.key, this.cadre = true, this.reveilServeur});

  /// Faux : l'indicateur seul (sous un texte déjà affiché).
  final bool cadre;

  /// Vrai pendant le réveil du serveur hébergé.
  final ValueListenable<bool>? reveilServeur;

  static const connexion = 'Connexion au serveur JARVIS…';

  @override
  Widget build(BuildContext context) {
    const preparation = IndicateurGeneration(
      libelle: IndicateurGeneration.preparation,
      libelleLong: IndicateurGeneration.longue,
    );
    final reveil = reveilServeur;
    final contenu = reveil == null
        ? preparation
        : ValueListenableBuilder<bool>(
            valueListenable: reveil,
            builder: (context, enCours, _) => enCours
                ? const IndicateurGeneration(libelle: connexion)
                : preparation,
          );
    return Semantics(
      label: cadre ? 'JARVIS réfléchit' : 'JARVIS prépare les propositions',
      child: cadre ? _CadreJarvis(child: contenu) : contenu,
    );
  }
}
