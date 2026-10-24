import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/conversations/apercu_conversation.dart';
import '../services/authentification/auth_service.dart';
import '../services/conversations/conversations_multicanal.dart';
import '../theme/theme_jarvis.dart';
import 'conversation/signature_jarvis.dart';
import 'menu/avatar_compte.dart';
import 'menu/section_conversations.dart';

/// Bouton du menu : le symbole lumineux de JARVIS ([PerleJarvis], celui
/// des réponses), un peu plus grand, centré dans une zone tactile de 44 px.
class BoutonMenu extends StatelessWidget {
  const BoutonMenu({super.key, required this.surOuvrir});

  final VoidCallback surOuvrir;

  /// Taille de la perle (13 px dans les signatures des réponses).
  static const taillePerle = 28.0;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      onPressed: surOuvrir,
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      icon: const PerleJarvis(taille: taillePerle),
    );
  }
}

/// Menu latéral de JARVIS : un panneau qui glisse depuis la gauche, au-dessus
/// d'un voile très léger.
///
/// Posé par-dessus l'accueil (Stack) : rien n'est recréé, les particules PIM
/// continuent derrière le voile. Le voile et le panneau ont leur propre
/// calque ; le contenu du panneau est construit une fois puis seulement
/// déplacé pendant l'animation. Fermé, le menu ne dessine rien.
///
/// Fermeture : voile, bouton ×, Échap (le bouton Retour d'Android est géré
/// par la page avec un `PopScope`).
class MenuLateral extends StatefulWidget {
  const MenuLateral({
    super.key,
    required this.ouvert,
    required this.surFermer,
    required this.surNouvelle,
    required this.surChatVocal,
    required this.surAccueil,
    required this.surParametres,
    required this.multicanal,
    required this.surOuvrirConversation,
    this.surSupprimerConversation,
    this.conversationEnCours,
    this.surOuvrir,
    this.compte,
    this.surCompte,
    this.surApprendre,
  });

  final bool ouvert;

  /// Module Apprendre (null : module désactivé, entrée absente).
  final VoidCallback? surApprendre;

  /// Ouverture par le glissement depuis le bord gauche (null : geste
  /// désactivé, seul le bouton ouvre le menu).
  final VoidCallback? surOuvrir;

  /// Compte connecté, pour l'avatar en bas du panneau (null : sans compte).
  final AuthService? compte;

  /// Appui sur l'avatar : section « Compte » des Paramètres.
  final VoidCallback? surCompte;
  final VoidCallback surFermer;
  final VoidCallback surNouvelle;
  final VoidCallback surChatVocal;
  final VoidCallback surAccueil;
  final VoidCallback surParametres;

  /// Titre de la conversation en cours (début du premier message), ou null.
  final String? conversationEnCours;

  /// Conversations des messageries (« MES CONVERSATIONS »).
  final ConversationsMulticanal multicanal;
  final ValueChanged<ApercuConversation> surOuvrirConversation;

  /// Suppression confirmée (null : suppression dans les données de sa
  /// messagerie, sans rien d'autre).
  final ValueChanged<ApercuConversation>? surSupprimerConversation;

  /// Ouverture et fermeture.
  static const dureeOuverture = Duration(milliseconds: 260);
  static const dureeFermeture = Duration(milliseconds: 230);

  /// Geste : largeur de la zone de départ le long du bord gauche (en plus
  /// de la zone du geste Retour d'Android), part de la largeur du panneau
  /// à parcourir pour ouvrir (ou fermer), vitesse d'un lancer (px/s) et
  /// durée de la fin d'animation après le relâchement.
  static const zoneBord = 24.0;
  static const seuilGeste = 0.35;
  static const vitesseLancer = 700.0;
  static const dureeGesteMin = Duration(milliseconds: 180);
  static const dureeGesteMax = Duration(milliseconds: 280);

  /// Opacité maximale du voile (noir lavande) : l'accueil reste lisible.
  static const opaciteVoile = 0.11;

  /// Largeur du panneau pour un écran de [largeur] px.
  static double largeurPour(double largeur) => math.min(320.0, largeur * 0.84);

  @override
  State<MenuLateral> createState() => _MenuLateralState();
}

class _MenuLateralState extends State<MenuLateral>
    with SingleTickerProviderStateMixin {
  // Position du panneau : 0 fermé, 1 ouvert. Linéaire : pendant un geste,
  // le panneau suit exactement le doigt ; la courbe ne sert qu'aux
  // animations ([_animer]).
  late final _anim = AnimationController(
    vsync: this,
    value: widget.ouvert ? 1 : 0,
  );

  /// Position visée par la dernière animation (une confirmation de la page
  /// ne relance pas une animation déjà partie vers le même état).
  double _cible = 0;

  /// Un geste déplace le panneau (la page ne pilote plus l'animation).
  bool _glisse = false;

  /// Le geste en cours a commencé menu fermé (depuis le bord).
  bool _depuisFerme = false;

  double _largeur = 320;

  @override
  void initState() {
    super.initState();
    _cible = _anim.value;
  }

  @override
  void didUpdateWidget(MenuLateral ancien) {
    super.didUpdateWidget(ancien);
    if (_glisse) return;
    final cible = widget.ouvert ? 1.0 : 0.0;
    if (cible != _cible) {
      _animer(
        cible,
        widget.ouvert ? MenuLateral.dureeOuverture : MenuLateral.dureeFermeture,
      );
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _animer(double cible, Duration duree) {
    _cible = cible;
    _anim.animateTo(
      cible,
      // Réduction des animations (réglage du système) : état final aussitôt.
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : duree,
      curve: Curves.easeOutCubic,
    );
  }

  // --- Geste : ouverture depuis le bord, fermeture vers la gauche ------------

  void _debutGeste(DragStartDetails _) {
    _anim.stop();
    _glisse = true;
    _depuisFerme = _anim.value < 0.5;
  }

  void _geste(DragUpdateDetails d) {
    if (!_glisse) return;
    final t = (_anim.value + d.primaryDelta! / _largeur).clamp(0.0, 1.0);
    _anim.value = t;
    // Pour la page, le menu est ouvert dès que le panneau apparaît : clavier
    // refermé, liste actualisée, Retour d'Android le referme.
    if (t > 0 && !widget.ouvert) widget.surOuvrir?.call();
  }

  void _finGeste(DragEndDetails d) {
    if (!_glisse) return;
    _glisse = false;
    final v = d.primaryVelocity ?? 0;
    final lancer = v.abs() >= MenuLateral.vitesseLancer;
    final t = _anim.value;
    final bool ouvrir;
    if (lancer) {
      ouvrir = v > 0; // lancer : le sens du geste décide
    } else if (_depuisFerme) {
      ouvrir = t >= MenuLateral.seuilGeste;
    } else {
      ouvrir = t > 1 - MenuLateral.seuilGeste;
    }
    final cible = ouvrir ? 1.0 : 0.0;
    final reste = (cible - t).abs() * _largeur;
    // Durée selon la distance restante et la vitesse : easeOutCubic démarre
    // trois fois plus vite que sa moyenne, donc à la vitesse du doigt.
    final mini = MenuLateral.dureeGesteMin.inMilliseconds;
    final maxi = MenuLateral.dureeGesteMax.inMilliseconds;
    final ms = lancer ? 3000 * reste / v.abs() : maxi * reste / _largeur;
    _animer(cible, Duration(milliseconds: ms.clamp(mini, maxi).round()));
    if (ouvrir && !widget.ouvert) widget.surOuvrir?.call();
    if (!ouvrir && widget.ouvert) widget.surFermer();
  }

  void _gesteAnnule() => _finGeste(DragEndDetails(primaryVelocity: 0));

  /// Glissement horizontal au doigt ou au stylet seulement : à la souris,
  /// le bouton, le voile, × et Échap suffisent.
  Widget _detecteur(HitTestBehavior comportement, Widget enfant) =>
      GestureDetector(
        behavior: comportement,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        onHorizontalDragStart: _debutGeste,
        onHorizontalDragUpdate: _geste,
        onHorizontalDragEnd: _finGeste,
        onHorizontalDragCancel: _gesteAnnule,
        child: enfant,
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final largeur = MenuLateral.largeurPour(media.size.width);
    _largeur = largeur;
    // Construit une fois : l'animation ne fait que le déplacer.
    final panneau = RepaintBoundary(
      child: _Panneau(
        surFermer: widget.surFermer,
        surNouvelle: widget.surNouvelle,
        surChatVocal: widget.surChatVocal,
        surAccueil: widget.surAccueil,
        surParametres: widget.surParametres,
        conversationEnCours: widget.conversationEnCours,
        multicanal: widget.multicanal,
        surOuvrirConversation: widget.surOuvrirConversation,
        surSupprimerConversation: widget.surSupprimerConversation,
        compte: widget.compte,
        surCompte: widget.surCompte,
        surApprendre: widget.surApprendre,
      ),
    );
    // Bande invisible le long du bord gauche, menu fermé : translucide (les
    // touches passent à l'accueil), elle ne prend que le glissement
    // horizontal. Plus large que la zone du geste Retour d'Android
    // (navigation par gestes), que le système garde pour lui. Même clé
    // pendant tout le geste qui ouvre : il n'est jamais interrompu.
    final avecBande = widget.surOuvrir != null;
    final bande = KeyedSubtree(
      key: const ValueKey('bord'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: MenuLateral.zoneBord + media.systemGestureInsets.left,
          height: double.infinity,
          child: _detecteur(
            HitTestBehavior.translucent,
            const SizedBox.expand(),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _anim,
        child: panneau,
        builder: (context, panneau) {
          final t = _anim.value;
          // Fermé : rien n'est dessiné ; seule la bande du bord écoute.
          if (t == 0 && !_anim.isAnimating && !_glisse) {
            return avecBande
                ? Stack(children: [bande])
                : const SizedBox.shrink();
          }
          return Stack(
            children: [
              KeyedSubtree(
                key: const ValueKey('menu'),
                // Glisser vers la gauche sur le voile ou le panneau le
                // referme (une ligne de conversation garde son propre
                // balayage : le détecteur le plus proche du doigt gagne).
                child: _detecteur(
                  HitTestBehavior.opaque,
                  Stack(
                    children: [
                      // Voile : bloque l'accueil, ferme le menu au toucher.
                      Positioned.fill(
                        child: Semantics(
                          label: 'Fermer le menu',
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.surFermer,
                            child: ColoredBox(
                              color: const Color(
                                0xFF1E1830,
                              ).withValues(alpha: MenuLateral.opaciteVoile * t),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: largeur,
                        child: FractionalTranslation(
                          translation: Offset(t - 1, 0),
                          child: panneau,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (avecBande && _glisse && _depuisFerme) bande,
            ],
          );
        },
      ),
    );
  }
}

/// Contenu du panneau.
class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.surFermer,
    required this.surNouvelle,
    required this.surChatVocal,
    required this.surAccueil,
    required this.surParametres,
    required this.multicanal,
    required this.surOuvrirConversation,
    this.surSupprimerConversation,
    this.conversationEnCours,
    this.compte,
    this.surCompte,
    this.surApprendre,
  });

  final AuthService? compte;
  final VoidCallback? surCompte;
  final VoidCallback? surApprendre;
  final VoidCallback surFermer;
  final VoidCallback surNouvelle;
  final VoidCallback surChatVocal;
  final VoidCallback surAccueil;
  final VoidCallback surParametres;
  final String? conversationEnCours;
  final ConversationsMulticanal multicanal;
  final ValueChanged<ApercuConversation> surOuvrirConversation;

  /// Suppression confirmée (null : suppression dans les données de sa
  /// messagerie, sans rien d'autre).
  final ValueChanged<ApercuConversation>? surSupprimerConversation;

  /// En dessous de cette hauteur (petit téléphone, clavier ouvert), le
  /// haut du panneau défile et la liste garde [hauteurListeMin].
  static const hauteurCompacte = 560.0;
  static const hauteurListeMin = 300.0;

  @override
  Widget build(BuildContext context) {
    final conversation = conversationEnCours;
    return CallbackShortcuts(
      // Échap ferme le menu (ordinateur, Web).
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): surFermer},
      child: FocusScope(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          label: 'Menu',
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: CouleursJarvis.panneauMenu,
              ),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(24),
              ),
              border: Border(
                right: BorderSide(
                  color: CouleursJarvis.trait.withValues(alpha: 0.7),
                ),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A2A2240),
                  blurRadius: 30,
                  offset: Offset(6, 0),
                ),
              ],
            ),
            child: SafeArea(
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 14),
                child: LayoutBuilder(
                  builder: (context, contraintes) {
                    final haut = <Widget>[
                      Row(
                        children: [
                          const SizedBox(width: 10),
                          // Prend la place libre (Fermer reste au bord) ; en
                          // très grande police sur un petit écran, le nom se
                          // réduit au lieu de pousser le bouton Fermer.
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'JARVIS',
                                style: TextStyle(
                                  fontFamily: policeAffichage,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 4.5,
                                  color: CouleursJarvis.signal.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fermer le menu',
                            onPressed: surFermer,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            style: IconButton.styleFrom(
                              foregroundColor: CouleursJarvis.texteSecondaire,
                              minimumSize: const Size(44, 44),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Entree(
                        icone: Icons.edit_square,
                        libelle: 'Nouvelle conversation',
                        surChoix: surNouvelle,
                      ),
                      _Entree(
                        icone: Icons.graphic_eq_rounded,
                        libelle: 'Chat vocal',
                        surChoix: surChatVocal,
                      ),
                      if (surApprendre != null)
                        _Entree(
                          icone: Icons.school_outlined,
                          libelle: 'Apprendre',
                          surChoix: surApprendre!,
                        ),
                      if (conversation != null) ...[
                        const SizedBox(height: 22),
                        Padding(
                          padding: EdgeInsets.only(left: 12, bottom: 6),
                          child: Text(
                            'EN COURS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: CouleursJarvis.texteSecondaire,
                            ),
                          ),
                        ),
                        _Entree(
                          icone: Icons.chat_bubble_outline_rounded,
                          libelle: conversation,
                          surChoix: surAccueil,
                          actif: true,
                        ),
                      ],
                      const SizedBox(height: 22),
                    ];
                    final section = SectionConversations(
                      multicanal: multicanal,
                      surOuvrir: surOuvrirConversation,
                      surSupprimer: surSupprimerConversation,
                    );
                    final compacte = contraintes.maxHeight < hauteurCompacte;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (compacte)
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...haut,
                                  SizedBox(
                                    height: hauteurListeMin,
                                    child: section,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          ...haut,
                          Expanded(child: section),
                        ],
                        Divider(
                          height: 1,
                          color: CouleursJarvis.trait.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Avatar du compte connecté (initiale) : section
                            // « Compte » des Paramètres.
                            AvatarCompte(compte: compte, surAppui: surCompte),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Paramètres',
                              onPressed: surParametres,
                              // Roue dentée classique, contour fin.
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 22,
                              ),
                              style: IconButton.styleFrom(
                                foregroundColor: CouleursJarvis.texteSecondaire,
                                minimumSize: const Size(48, 48),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Entrée du menu : icône fine et libellé sur une ligne.
class _Entree extends StatelessWidget {
  const _Entree({
    required this.icone,
    required this.libelle,
    required this.surChoix,
    this.actif = false,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback surChoix;

  /// Entrée correspondant à l'écran affiché (fond lavande léger).
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: surChoix,
        borderRadius: BorderRadius.circular(14),
        hoverColor: CouleursJarvis.signal.withValues(alpha: 0.05),
        focusColor: CouleursJarvis.signal.withValues(alpha: 0.1),
        child: Ink(
          decoration: BoxDecoration(
            color: actif
                ? CouleursJarvis.signal.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icone, size: 19, color: CouleursJarvis.texteSecondaire),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      libelle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
