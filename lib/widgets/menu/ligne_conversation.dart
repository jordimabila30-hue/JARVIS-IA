import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/local_date_time.dart';
import 'confirmation_suppression.dart';

enum _Action { epingler, supprimer }

/// Une conversation dans la liste du menu : titre, aperçu du dernier
/// message (une ligne), date courte, épingle discrète.
///
/// Toucher : ouvre la conversation. Deux actions, « Épingler /
/// Désépingler » et « Supprimer » (toujours confirmée) :
/// - téléphone : balayage (vers la droite : épingler ; vers la gauche :
///   supprimer). Le geste révèle seulement le bouton, il n'agit jamais
///   seul ; ou appui prolongé (menu) ;
/// - ordinateur : clic droit ou bouton ⋯ au survol ;
/// - clavier : touche Menu ou Maj+F10.
class LigneConversation extends StatefulWidget {
  const LigneConversation({
    super.key,
    required this.conversation,
    required this.epinglee,
    required this.maintenant,
    required this.surOuvrir,
    required this.surEpingler,
    required this.surSupprimer,
  });

  final ApercuConversation conversation;
  final bool epinglee;
  final DateTime maintenant;
  final VoidCallback surOuvrir;
  final VoidCallback surEpingler;

  /// Appelé seulement après la confirmation.
  final VoidCallback surSupprimer;

  /// Hauteur d'une ligne à la taille de texte normale.
  static const hauteur = 62.0;

  /// Hauteur réelle, la même pour toutes les lignes (liste rapide, même
  /// très longue) : grandit avec la police choisie dans les réglages du
  /// téléphone, pour que titre et aperçu tiennent toujours.
  static double hauteurPour(TextScaler echelle) {
    // Titre (14) et aperçu (12,5), interligne hérité 1,45, plus les marges.
    final texte = (echelle.scale(14) + echelle.scale(12.5)) * 1.45 + 3;
    return math.max(hauteur, texte + 22);
  }

  static const epingler = 'Épingler la conversation';
  static const desepingler = 'Désépingler la conversation';
  static const supprimer = 'Supprimer la conversation';

  /// Libellés des boutons révélés par le balayage.
  static const boutonEpingler = 'Épingler';
  static const boutonDesepingler = 'Désépingler';
  static const boutonSupprimer = 'Supprimer';

  /// Violet de l'épinglage (bouton révélé).
  static const violetEpingle = Color(0xFF7463BE);

  // Une seule ligne ouverte à la fois.
  static final _ouverte = ValueNotifier<Object?>(null);

  /// Referme la ligne ouverte (défilement de la liste, autre action…).
  static void fermerToutes() => _ouverte.value = null;

  @override
  State<LigneConversation> createState() => _LigneConversationState();
}

class _LigneConversationState extends State<LigneConversation>
    with SingleTickerProviderStateMixin {
  bool _survol = false;
  bool _focus = false;

  // Décalage horizontal de la ligne, en pixels (> 0 : épingler révélé à
  // gauche ; < 0 : supprimer révélé à droite).
  late final _decalage = AnimationController.unbounded(vsync: this);
  double _largeurAction = 88;
  bool _seuilFranchi = false;

  bool get _ouverte => _decalage.value.abs() > 0.5;

  @override
  void initState() {
    super.initState();
    LigneConversation._ouverte.addListener(_surAutreOuverte);
  }

  @override
  void dispose() {
    LigneConversation._ouverte.removeListener(_surAutreOuverte);
    if (LigneConversation._ouverte.value == this) {
      LigneConversation._ouverte.value = null;
    }
    _decalage.dispose();
    super.dispose();
  }

  void _surAutreOuverte() {
    if (LigneConversation._ouverte.value != this && _ouverte) _fermer();
  }

  // --- Balayage --------------------------------------------------------------

  void _debutGlisse(DragStartDetails _) {
    _decalage.stop();
    _seuilFranchi = _ouverte;
    LigneConversation._ouverte.value = this;
  }

  void _glisse(DragUpdateDetails d) {
    final max = _largeurAction;
    var x = _decalage.value + d.primaryDelta!;
    // Au-delà du bouton : résistance (la ligne ralentit, sans bloquer).
    if (x.abs() > max) {
      final exces = x.abs() - max;
      x = x.sign * (max + exces * 0.25);
    }
    _decalage.value = x.clamp(-max * 1.4, max * 1.4);
    // Léger retour haptique quand le bouton est entièrement révélé.
    final franchi = _decalage.value.abs() >= max * 0.6;
    if (franchi && !_seuilFranchi) HapticFeedback.selectionClick();
    _seuilFranchi = franchi;
  }

  void _finGlisse(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final x = _decalage.value;
    final max = _largeurAction;
    double cible;
    if (v.abs() > 350) {
      // Lancer : ouvre dans le sens du geste, ou referme s'il revient.
      cible = (v.sign == x.sign || x.abs() < 1) ? v.sign * max : 0;
    } else {
      cible = x.abs() >= max * 0.45 ? x.sign * max : 0;
    }
    _aller(cible);
  }

  Future<void> _aller(double cible) {
    if (cible == 0 && LigneConversation._ouverte.value == this) {
      LigneConversation._ouverte.value = null;
    }
    return _decalage.animateTo(
      cible,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _fermer() => _aller(0);

  /// « Épingler » (bouton révélé) : la ligne se referme, puis l'épingle
  /// change (la ligne rejoint sa place dans la liste).
  Future<void> _epinglerDepuisBalayage() async {
    await _fermer();
    if (mounted) widget.surEpingler();
  }

  /// « Supprimer » (bouton révélé ou menu) : confirmation d'abord ; si
  /// l'utilisateur annule, la ligne se referme et rien ne change.
  Future<void> _supprimer() async {
    final confirme = await confirmerSuppression(context);
    if (!mounted) return;
    if (confirme) {
      widget.surSupprimer();
    } else {
      _fermer();
    }
  }

  // --- Menu (appui prolongé, clic droit, ⋯, clavier) -------------------------

  Future<void> _menu(Offset position) async {
    LigneConversation.fermerToutes();
    final ecran = Overlay.of(context).context.findRenderObject()! as RenderBox;
    PopupMenuItem<_Action> entree(
      _Action action,
      IconData icone,
      String libelle,
      Color couleur,
    ) => PopupMenuItem(
      value: action,
      height: 44,
      child: Row(
        children: [
          Icon(icone, size: 17, color: couleur),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              libelle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: action == _Action.supprimer
                    ? rougeSuppression
                    : CouleursJarvis.texte,
              ),
            ),
          ),
        ],
      ),
    );
    final choix = await showMenu<_Action>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & ecran.size,
      ),
      color: CouleursJarvis.coque,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CouleursJarvis.trait),
      ),
      items: [
        entree(
          _Action.epingler,
          widget.epinglee ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          widget.epinglee
              ? LigneConversation.desepingler
              : LigneConversation.epingler,
          CouleursJarvis.texteSecondaire,
        ),
        entree(
          _Action.supprimer,
          Icons.delete_outline_rounded,
          LigneConversation.supprimer,
          rougeSuppression,
        ),
      ],
    );
    if (!mounted) return;
    switch (choix) {
      case _Action.epingler:
        widget.surEpingler();
      case _Action.supprimer:
        _supprimer();
      case null:
        break;
    }
  }

  /// Menu sous la ligne (bouton ⋯, clavier, appui prolongé).
  void _menuSousLaLigne() {
    final boite = context.findRenderObject()! as RenderBox;
    _menu(
      boite.localToGlobal(Offset(boite.size.width - 12, boite.size.height)),
    );
  }

  void _toucher() {
    // Ligne ouverte : le toucher la referme seulement.
    if (_ouverte) {
      _fermer();
      return;
    }
    widget.surOuvrir();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final echelle = MediaQuery.textScalerOf(context);
    _largeurAction = math.max(88, echelle.scale(80));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _menuSousLaLigne,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _menuSousLaLigne,
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: Semantics(
          button: true,
          label: [
            c.titre,
            if (widget.epinglee) 'épinglée',
            c.apercu,
          ].join(', '),
          excludeSemantics: true,
          customSemanticsActions: {
            CustomSemanticsAction(
              label: widget.epinglee
                  ? LigneConversation.desepingler
                  : LigneConversation.epingler,
            ): widget.surEpingler,
            const CustomSemanticsAction(label: LigneConversation.supprimer):
                _supprimer,
          },
          // Balayage au doigt (ou au stylet) seulement : à la souris, le
          // clic droit et le bouton ⋯ suffisent.
          child: GestureDetector(
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
            },
            onHorizontalDragStart: _debutGlisse,
            onHorizontalDragUpdate: _glisse,
            onHorizontalDragEnd: _finGlisse,
            onHorizontalDragCancel: _fermer,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AnimatedBuilder(
                animation: _decalage,
                builder: (context, ligne) {
                  final x = _decalage.value;
                  return Stack(
                    children: [
                      if (x > 0.5)
                        _BoutonRevele(
                          cote: _Cote.gauche,
                          largeur: x,
                          largeurPleine: _largeurAction,
                          couleur: LigneConversation.violetEpingle,
                          icone: widget.epinglee
                              ? Icons.push_pin_outlined
                              : Icons.push_pin_rounded,
                          libelle: widget.epinglee
                              ? LigneConversation.boutonDesepingler
                              : LigneConversation.boutonEpingler,
                          surAppui: _epinglerDepuisBalayage,
                        ),
                      if (x < -0.5)
                        _BoutonRevele(
                          cote: _Cote.droite,
                          largeur: -x,
                          largeurPleine: _largeurAction,
                          couleur: rougeSuppression,
                          icone: Icons.delete_outline_rounded,
                          libelle: LigneConversation.boutonSupprimer,
                          surAppui: _supprimer,
                        ),
                      Transform.translate(offset: Offset(x, 0), child: ligne),
                    ],
                  );
                },
                child: _contenu(c, echelle),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenu(ApercuConversation c, TextScaler echelle) {
    final actions = _survol || _focus;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: c.disponible ? _toucher : null,
        onLongPress: _menuSousLaLigne,
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        onFocusChange: (f) => setState(() => _focus = f),
        borderRadius: BorderRadius.circular(14),
        hoverColor: CouleursJarvis.signal.withValues(alpha: 0.04),
        focusColor: CouleursJarvis.signal.withValues(alpha: 0.1),
        child: Ink(
          height: LigneConversation.hauteurPour(echelle),
          decoration: BoxDecoration(
            color: c.ouverte
                ? CouleursJarvis.signal.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.disponible
                            ? CouleursJarvis.texte
                            : CouleursJarvis.texteSecondaire,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      c.apercu,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: CouleursJarvis.texteSecondaire,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                // Assez large pour « 12/09/25 », même en grande police.
                width: math.max(46, echelle.scale(46)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dateCourte(c.derniereActivite, widget.maintenant),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 11,
                        color: CouleursJarvis.texteSecondaire,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 14,
                      child: widget.epinglee
                          ? const Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              semanticLabel: 'Épinglée',
                              color: CouleursJarvis.violet,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              // Bouton ⋯ : visible au survol ou au focus (ordinateur,
              // clavier) ; la place est réservée pour que rien ne bouge.
              SizedBox(
                width: 32,
                child: actions
                    ? IconButton(
                        tooltip: 'Options de la conversation',
                        onPressed: _menuSousLaLigne,
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        style: IconButton.styleFrom(
                          foregroundColor: CouleursJarvis.texteSecondaire,
                          minimumSize: const Size(32, 32),
                        ),
                        icon: const Icon(Icons.more_horiz_rounded),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Cote { gauche, droite }

/// Bouton derrière la ligne, révélé progressivement par le balayage :
/// il occupe la place libérée, son contenu apparaît en fondu.
class _BoutonRevele extends StatelessWidget {
  const _BoutonRevele({
    required this.cote,
    required this.largeur,
    required this.largeurPleine,
    required this.couleur,
    required this.icone,
    required this.libelle,
    required this.surAppui,
  });

  final _Cote cote;
  final double largeur;
  final double largeurPleine;
  final Color couleur;
  final IconData icone;
  final String libelle;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final t = (largeur / largeurPleine).clamp(0.0, 1.0);
    return Positioned(
      top: 0,
      bottom: 0,
      left: cote == _Cote.gauche ? 0 : null,
      right: cote == _Cote.droite ? 0 : null,
      width: largeur,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
        child: Material(
          color: couleur,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: surAppui,
            borderRadius: BorderRadius.circular(12),
            child: Opacity(
              opacity: Curves.easeOut.transform(t),
              child: Transform.scale(
                scale: 0.85 + 0.15 * t,
                child: OverflowBox(
                  // Contenu à sa taille finale, centré : rien ne se
                  // tasse pendant l'apparition.
                  maxWidth: largeurPleine,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icone, size: 19, color: Colors.white),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            libelle,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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
    );
  }
}
