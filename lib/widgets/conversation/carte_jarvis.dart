import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/importation/reference_whatsapp.dart';
import '../../models/message_conversation.dart';
import '../../services/ecriture/ecriture_progressive.dart';
import '../../theme/gabarit_jarvis.dart';
import '../../theme/theme_jarvis.dart';
import '../ecriture/texte_progressif.dart';
import 'choix_ton.dart';
import 'heure_message.dart';
import '../../models/importation/propositions_reponse.dart';
import 'propositions_jarvis.dart';
import 'references_jarvis.dart';
import 'signature_jarvis.dart';
import 'reponse_proposee.dart';

/// Habillage commun des messages de JARVIS : carte claire ivoire nuancée
/// de lavande, signature « • JARVIS » ([SignatureJarvis]), heure en bas à
/// droite.
class _CadreJarvis extends StatelessWidget {
  const _CadreJarvis({required this.child, this.heure, this.ecriture});

  final Widget child;

  /// Heure de la réponse ; aucune pendant la réflexion.
  final DateTime? heure;

  /// Écriture en cours : « Tout afficher » discret, à gauche de l'heure
  /// (posé par-dessus la ligne : la carte ne change pas de hauteur).
  final EcritureProgressive? ecriture;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(18, 14, 16, heure == null ? 16 : 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Fond très légèrement translucide (94 %) : les particules qui
            // passent derrière restent devinables, le texte reste net.
            colors: [Color(0xF0FFFDF9), Color(0xF0F7F3FD)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: CouleursJarvis.trait.withValues(alpha: 0.6),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A3A3350),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Même signature pour toutes les réponses de JARVIS.
            SignatureJarvis(compacte: GabaritJarvis.of(context).compact),
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
        ),
      ),
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
            Text(message.texte, style: style),
            ..._suite(),
          ],
        ),
      );
    }
    return _CadreJarvis(
      heure: message.heure,
      ecriture: ecriture,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
        const Padding(
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
            style: const TextStyle(
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
        backgroundColor: Colors.white.withValues(alpha: 0.5),
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
      foregroundColor: principal ? Colors.white : CouleursJarvis.signal,
      backgroundColor: principal
          ? CouleursJarvis.signal
          : Colors.white.withValues(alpha: 0.5),
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

/// Propositions en préparation : les mêmes trois points, sans cadre, et
/// une courte légende.
class PreparationPropositions extends StatelessWidget {
  const PreparationPropositions({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: Key('preparation-propositions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ReflexionJarvis(cadre: false),
        SizedBox(width: 4),
        Text(
          'Je prépare les propositions',
          style: TextStyle(fontSize: 13, color: CouleursJarvis.texteSecondaire),
        ),
      ],
    );
  }
}

/// JARVIS prépare sa réponse : trois points qui respirent doucement.
class ReflexionJarvis extends StatefulWidget {
  const ReflexionJarvis({super.key, this.cadre = true});

  /// Faux : les points seuls (sous un texte déjà affiché).
  final bool cadre;

  @override
  State<ReflexionJarvis> createState() => _ReflexionJarvisState();
}

class _ReflexionJarvisState extends State<ReflexionJarvis>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = SizedBox(
      height: 18,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CouleursJarvis.violet.withValues(
                      alpha:
                          0.25 +
                          0.55 *
                              (0.5 +
                                  0.5 *
                                      math.sin(
                                        (_anim.value - i * 0.18) * 2 * math.pi,
                                      )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      label: widget.cadre ? 'JARVIS réfléchit' : 'JARVIS prépare les propositions',
      child: widget.cadre ? _CadreJarvis(child: points) : points,
    );
  }
}
