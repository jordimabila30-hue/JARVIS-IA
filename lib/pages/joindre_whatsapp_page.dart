import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/importation/conversation_whatsapp.dart';
import '../models/importation/filtre_whatsapp.dart';
import '../models/importation/piece_jointe_whatsapp.dart';
import '../services/importation/identite_whatsapp.dart';
import '../theme/theme_jarvis.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/importation/accueil_import_whatsapp.dart';
import '../widgets/importation/filtrage/selecteur_mode_filtrage.dart';
import '../widgets/importation/lecture_whatsapp_widgets.dart';
import '../widgets/importation/logo_whatsapp.dart';
import 'resume_whatsapp_page.dart';

/// Import WhatsApp — interface 3 : joindre les messages choisis à un
/// message de JARVIS. L'essentiel seulement (nom, nombre de messages,
/// période, participants), puis « Vous êtes : » (jamais deviné ; un nom
/// déjà confirmé lors d'un import précédent est proposé, modifiable).
/// « Joindre la conversation » renvoie la [PieceJointeWhatsApp] : rien
/// n'est envoyé ni enregistré ici.
class JoindreWhatsAppPage extends StatefulWidget {
  const JoindreWhatsAppPage({
    super.key,
    required this.conversation,
    required this.choisis,
    required this.identite,
    this.moiConnu,
    this.horloge,
  });

  static const titre = 'Joindre la conversation';
  static const vousEtes = 'Vous êtes :';
  static const choisirIdentite =
      'Indiquez qui vous êtes dans cette conversation.';

  final ConversationWhatsApp conversation;
  final MessagesChoisisWhatsApp choisis;
  final IdentiteWhatsApp identite;

  /// Nom déjà confirmé comme « moi » lors d'un import précédent.
  final String? moiConnu;
  final DateTime Function()? horloge;

  @override
  State<JoindreWhatsAppPage> createState() => _JoindreWhatsAppPageState();
}

class _JoindreWhatsAppPageState extends State<JoindreWhatsAppPage> {
  late String? _moi = _participants.contains(widget.moiConnu)
      ? widget.moiConnu
      : null;
  bool _enCours = false;

  List<String> get _participants => [
    for (final p in widget.conversation.participants) p.nom,
  ];

  Future<void> _joindre() async {
    final moi = _moi;
    if (moi == null || _enCours) return;
    setState(() => _enCours = true);
    // Retenu sur l'appareil pour les prochains imports (comme avant).
    await widget.identite.confirmer(moi, ancien: widget.moiConnu);
    if (!mounted) return;
    Navigator.of(context).pop(
      PieceJointeWhatsApp.depuis(
        conversation: widget.conversation,
        choisis: widget.choisis,
        moi: moi,
        maintenant: widget.horloge?.call(),
      ),
    );
  }

  void _retour() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final messages = widget.choisis.messages;
    final n = messages.length;
    DateTime? debut, fin;
    for (final m in messages) {
      final d = m.date;
      if (d == null) continue;
      debut ??= d;
      fin = d;
    }
    final participants = _participants;
    final marge = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 28.0;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _retour},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: CouleursJarvis.ivoire,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: degradeFondJarvis),
            child: SizedBox.expand(
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: const DefilementSansBarre(),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(marge, 6, marge, 16),
                          child: _Colonne(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Entete(surRetour: _retour),
                                const SizedBox(height: 22),
                                _CarteResume(
                                  // Le contact suit « Vous êtes : ».
                                  nom: PieceJointeWhatsApp.titreContact(
                                    c,
                                    _moi,
                                  ),
                                  ampleur:
                                      '${nombreEnFrancais(n)} message'
                                      '${n > 1 ? 's' : ''} sélectionné'
                                      '${n > 1 ? 's' : ''}',
                                  periode: debut == null || fin == null
                                      ? null
                                      : ResumeWhatsAppPage.periode(debut, fin),
                                  participants: participants,
                                ),
                                const SizedBox(height: 18),
                                _ChoixMoi(
                                  participants: participants,
                                  moi: _moi,
                                  surChoix: _enCours
                                      ? null
                                      : (p) => setState(() => _moi = p),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(marge, 8, marge, 12),
                      child: _Colonne(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BoutonPrincipalImport(
                              libelle: JoindreWhatsAppPage.titre,
                              icone: Icons.attach_file_rounded,
                              enCours: _enCours,
                              surAppui: _moi == null || _enCours
                                  ? null
                                  : _joindre,
                            ),
                            if (_moi == null) ...[
                              const SizedBox(height: 6),
                              const Text(
                                JoindreWhatsAppPage.choisirIdentite,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CouleursJarvis.texteSecondaire,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colonne centrée, 560 px au plus (ordinateur, tablette).
class _Colonne extends StatelessWidget {
  const _Colonne({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: child,
    ),
  );
}

class _Entete extends StatelessWidget {
  const _Entete({required this.surRetour});

  final VoidCallback surRetour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: surRetour,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: CouleursJarvis.texte,
            minimumSize: const Size(44, 44),
            side: BorderSide(
              color: CouleursJarvis.trait.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            child: const Text(
              JoindreWhatsAppPage.titre,
              style: TextStyle(
                fontFamily: policeAffichage,
                fontSize: 19,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le nom, le nombre de messages, la période, les participants.
class _CarteResume extends StatelessWidget {
  const _CarteResume({
    required this.nom,
    required this.ampleur,
    required this.periode,
    required this.participants,
  });

  final String nom;
  final String ampleur;
  final String? periode;
  final List<String> participants;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: CouleursJarvis.texte.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LogoWhatsApp(taille: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: policeAffichage,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: CouleursJarvis.texte,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Ligne(icone: Icons.chat_bubble_outline_rounded, texte: ampleur),
          if (periode case final p?) ...[
            const SizedBox(height: 8),
            _Ligne(icone: Icons.calendar_today_outlined, texte: p),
          ],
          const SizedBox(height: 8),
          _Ligne(
            icone: participants.length > 2
                ? Icons.groups_outlined
                : Icons.people_outline_rounded,
            texte: participants.join(', '),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icone, size: 17, color: CouleursJarvis.signal),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              color: CouleursJarvis.texte,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// « Vous êtes : » puis les participants réels (deux ou davantage).
class _ChoixMoi extends StatelessWidget {
  const _ChoixMoi({
    required this.participants,
    required this.moi,
    required this.surChoix,
  });

  final List<String> participants;
  final String? moi;
  final ValueChanged<String>? surChoix;

  @override
  Widget build(BuildContext context) {
    final choix = surChoix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          JoindreWhatsAppPage.vousEtes,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in participants)
              CapsuleChoix(
                libelle: p,
                icone: p == moi ? Icons.check_rounded : null,
                actif: p == moi,
                souple: true,
                surAppui: choix == null ? null : () => choix(p),
              ),
          ],
        ),
      ],
    );
  }
}
