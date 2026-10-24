import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/theme_jarvis.dart';
import '../models/conversations/source_conversation.dart';
import '../services/ouverture_messageries.dart';
import 'importation/logo_whatsapp.dart';

/// Ce que l'utilisateur a choisi dans la feuille « Ajouter à JARVIS ».
enum ChoixAjout {
  coller,
  importerWhatsApp,
  ajouterMessageWhatsApp,
  aiderARepondre,
  instagram,
  messenger,
  mail;

  /// Messagerie à ouvrir (application ou site) ; null : action de JARVIS.
  Messagerie? get messagerie => switch (this) {
    instagram => Messagerie.instagram,
    messenger => Messagerie.messenger,
    mail => Messagerie.mail,
    _ => null,
  };
}

/// Feuille « Ajouter à JARVIS » (téléphone) : remplace le petit menu du
/// bouton « + », qui pouvait passer sous le clavier. Renvoie le choix, ou
/// null si la feuille est fermée sans choix.
Future<ChoixAjout?> afficherFeuilleAjout(
  BuildContext context, {
  bool actualisation = false,
}) {
  return showModalBottomSheet<ChoixAjout>(
    context: context,
    useSafeArea: true,
    // Petit écran (paysage, grande police) : la feuille défile au lieu de
    // déborder.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: CouleursJarvis.texte.withValues(alpha: 0.16),
    elevation: 0,
    builder: (context) => FeuilleAjout(actualisation: actualisation),
  );
}

class FeuilleAjout extends StatelessWidget {
  const FeuilleAjout({super.key, this.actualisation = false});

  static const titre = 'Ajouter à JARVIS';

  static const ouvrirDetail = 'Ouvrir l’application';
  static const aiderTitre = 'Répondre à un message reçu';
  static const aiderDetail = 'Instagram, Messenger, e-mail, SMS…';

  /// Messageries ouvertes depuis la feuille (application, sinon site).
  static const messageries = [
    (
      ChoixAjout.instagram,
      LogoSource(SourceConversation.instagram, taille: 30),
    ),
    (
      ChoixAjout.messenger,
      LogoSource(SourceConversation.messenger, taille: 30),
    ),
    (ChoixAjout.mail, Icon(Icons.mail_outline_rounded, size: 26)),
  ];

  /// Phase 5 : « Ajouter une réponse reçue » disponible (compte connecté),
  /// révélé en glissant « Importer une conversation » vers la gauche.
  final bool actualisation;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: CouleursJarvis.trait)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A3A3350),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      // La barre de navigation du système ne doit pas couvrir le bas de
      // la feuille (Android en navigation par boutons ou gestes).
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: CouleursJarvis.trait,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: CouleursJarvis.texte,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Choix(
              icone: Icons.content_paste_rounded,
              titre: 'Coller une conversation',
              detail: 'Depuis le presse-papiers',
              surChoix: () => Navigator.of(context).pop(ChoixAjout.coller),
            ),
            const SizedBox(height: 6),
            LigneImportGlissante(
              surImporter: () =>
                  Navigator.of(context).pop(ChoixAjout.importerWhatsApp),
              surAjouterMessage: actualisation
                  ? () => Navigator.of(
                      context,
                    ).pop(ChoixAjout.ajouterMessageWhatsApp)
                  : null,
            ),
            const SizedBox(height: 6),
            _Choix(
              icone: Icons.reply_rounded,
              titre: FeuilleAjout.aiderTitre,
              detail: FeuilleAjout.aiderDetail,
              surChoix: () =>
                  Navigator.of(context).pop(ChoixAjout.aiderARepondre),
            ),
            for (final (choix, visuel) in FeuilleAjout.messageries) ...[
              const SizedBox(height: 6),
              _Choix(
                visuel: visuel,
                titre: choix.messagerie!.libelle,
                detail: FeuilleAjout.ouvrirDetail,
                surChoix: () => Navigator.of(context).pop(choix),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Une ligne de la feuille : pastille à icône (ou [visuel], un logo),
/// titre, détail facultatif, flèche facultative. Sans [surChoix], elle est
/// volontairement indisponible (estompée, non cliquable).
class _Choix extends StatelessWidget {
  const _Choix({
    this.icone,
    this.visuel,
    required this.titre,
    this.detail,
    this.fleche = false,
    this.surChoix,
    this.suite,
  });

  final IconData? icone;
  final Widget? visuel;
  final String titre;
  final String? detail;
  final bool fleche;
  final VoidCallback? surChoix;

  /// Petite action à droite (souris / clavier), avant la flèche.
  final Widget? suite;

  @override
  Widget build(BuildContext context) {
    final actif = surChoix != null;
    return Semantics(
      button: true,
      enabled: actif,
      child: Opacity(
        opacity: actif ? 1 : 0.55,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: surChoix,
            borderRadius: BorderRadius.circular(16),
            hoverColor: CouleursJarvis.texte.withValues(alpha: 0.03),
            splashColor: CouleursJarvis.signal.withValues(alpha: 0.08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    if (visuel case final visuel?)
                      SizedBox.square(
                        dimension: 42,
                        child: Center(child: visuel),
                      )
                    else
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: actif
                              ? CouleursJarvis.signal.withValues(alpha: 0.1)
                              : CouleursJarvis.creme,
                        ),
                        child: Icon(
                          icone,
                          size: 20,
                          color: actif
                              ? CouleursJarvis.signal
                              : CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            titre,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: CouleursJarvis.texte,
                            ),
                          ),
                          if (detail case final detail?) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: TextStyle(
                                fontSize: 13,
                                color: CouleursJarvis.texteSecondaire,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?suite,
                    if (fleche)
                      Padding(
                        padding: EdgeInsets.only(left: 8, right: 2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: CouleursJarvis.texteSecondaire,
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

/// « Importer une conversation » (phases 5 et 5.1) :
///   - appui : l'import WhatsApp classique, inchangé ;
///   - petit glissement vers la gauche : « Ajouter une réponse reçue »
///     apparaît (à toucher) ;
///   - grand glissement (au-delà de [seuilOuverture] de la largeur, le
///     bouton se remplit, légère vibration) puis relâcher : le volet
///     s'ouvre directement, la ligne revient d'elle-même.
/// Le geste n'est reconnu qu'à l'horizontale : un défilement vertical ne le
/// déclenche jamais, et le glissement ne lance jamais l'import.
/// Souris / clavier (Web, ordinateur) : petite action au survol ou au focus ;
/// lecteurs d'écran : action personnalisée.
class LigneImportGlissante extends StatefulWidget {
  const LigneImportGlissante({
    super.key,
    required this.surImporter,
    this.surAjouterMessage,
  });

  final VoidCallback surImporter;
  final VoidCallback? surAjouterMessage;

  static const action = 'Ajouter une réponse reçue';
  static const largeurAction = 176.0;

  /// Part de la largeur à dépasser pour ouvrir directement le volet.
  static const seuilOuverture = 0.6;

  @override
  State<LigneImportGlissante> createState() => _LigneImportGlissanteState();
}

class _LigneImportGlissanteState extends State<LigneImportGlissante>
    with SingleTickerProviderStateMixin {
  // Décalage en pixels (0 : ligne au repos).
  late final _decalage = AnimationController.unbounded(vsync: this);
  double _largeur = 360;
  bool _arme = false;
  bool _survol = false;
  bool _focus = false;

  bool get _souris =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  double get _seuil => _largeur * LigneImportGlissante.seuilOuverture;

  @override
  void dispose() {
    _decalage.dispose();
    super.dispose();
  }

  void _aller(double cible) => _decalage.animateTo(
    cible,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  );

  void _glisser(DragUpdateDetails d) {
    _decalage.value = (_decalage.value - d.delta.dx).clamp(0, _largeur * 0.92);
    final arme = _decalage.value >= _seuil;
    if (arme != _arme) {
      if (arme) HapticFeedback.selectionClick();
      setState(() => _arme = arme);
    }
  }

  void _relacher(DragEndDetails d) {
    final vitesse = d.primaryVelocity ?? 0;
    if (_arme) {
      // Grand glissement : le volet s'ouvre, la ligne revient seule.
      setState(() => _arme = false);
      _aller(0);
      widget.surAjouterMessage?.call();
      return;
    }
    final ouvrir =
        vitesse < -400 ||
        (vitesse <= 400 &&
            _decalage.value > LigneImportGlissante.largeurAction / 2);
    _aller(ouvrir ? LigneImportGlissante.largeurAction : 0);
  }

  void _appui() {
    // Ligne ouverte : un appui la referme (jamais d'import par erreur).
    if (_decalage.value > 0) {
      _aller(0);
      return;
    }
    widget.surImporter();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.surAjouterMessage;
    final ligne = _Choix(
      visuel: const LogoWhatsApp(taille: 36),
      titre: 'Importer une conversation',
      fleche: true,
      surChoix: _appui,
      suite: action != null && _souris && (_survol || _focus)
          ? IconButton(
              key: const Key('action-ajouter-message'),
              tooltip: LigneImportGlissante.action,
              onPressed: action,
              icon: Icon(
                Icons.add_comment_outlined,
                size: 20,
                color: CouleursJarvis.signal,
              ),
            )
          : null,
    );
    if (action == null) return ligne;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: LigneImportGlissante.action): action,
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) => setState(() => _focus = f),
          child: LayoutBuilder(
            builder: (context, contraintes) {
              _largeur = contraintes.maxWidth;
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedBuilder(
                  animation: _decalage,
                  builder: (context, _) {
                    final dx = _decalage.value;
                    // Progression du geste : le bouton grandit avec la
                    // ligne, se remplit au-delà du seuil.
                    final largeurBouton = dx
                        .clamp(LigneImportGlissante.largeurAction, _largeur)
                        .toDouble();
                    return Stack(
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: largeurBouton,
                          child: Opacity(
                            opacity: (dx / LigneImportGlissante.largeurAction)
                                .clamp(0.0, 1.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  color: _arme
                                      ? CouleursJarvis.violet.withValues(
                                          alpha: 0.85,
                                        )
                                      : CouleursJarvis.lavande,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: const Key(
                                      'action-glissee-ajouter-message',
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      _decalage.value = 0;
                                      action();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_comment_outlined,
                                            size: 18,
                                            color: _arme
                                                ? CouleursJarvis.surSignal
                                                : CouleursJarvis.signal,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              LigneImportGlissante.action,
                                              maxLines: 2,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.2,
                                                fontWeight: FontWeight.w600,
                                                color: _arme
                                                    ? CouleursJarvis.surSignal
                                                    : CouleursJarvis.signal,
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
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(-dx, 0),
                          child: GestureDetector(
                            key: const Key('ligne-importer'),
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: _glisser,
                            onHorizontalDragEnd: _relacher,
                            onHorizontalDragCancel: () {
                              setState(() => _arme = false);
                              _aller(0);
                            },
                            child: ColoredBox(
                              color: CouleursJarvis.coque,
                              child: ligne,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
