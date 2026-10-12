import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/voice_state.dart';
import '../theme/theme_jarvis.dart';

/// Capsule sombre avec une pastille bleue ronde : le bouton vocal de JARVIS,
/// sans libellé visible (le libellé reste accessible : infobulle et
/// lecteur d'écran).
///
/// États : repos (respiration très lente), survol (contraste et halo
/// légers), appui (légère compression), écoute (pulsation autour de la
/// pastille), parole (petite onde animée). En mode [envoi], la pastille
/// montre une flèche : la même capsule envoie le message saisi.
class BoutonVocal extends StatefulWidget {
  const BoutonVocal({
    super.key,
    required this.onPressed,
    required this.libelle,
    this.etat,
    this.envoi = false,
    this.chatEnArrierePlan = false,
    this.largeur = 60,
    this.hauteur = 44,
  });

  final VoidCallback onPressed;

  /// Libellé accessible (infobulle, lecteur d'écran).
  final String libelle;

  /// État vocal à montrer ; null hors du mode vocal.
  final VoiceState? etat;

  /// Vrai : la capsule envoie le texte saisi (flèche).
  final bool envoi;

  /// Chat vocal reprenable en arrière-plan (micro coupé) : la capsule passe
  /// du graphite à un dégradé bleu-violet, quel que soit son contenu
  /// (onde vocale ou flèche d'envoi).
  final bool chatEnArrierePlan;

  /// Capsule « chat vocal en arrière-plan » : bleu doux vers violet.
  static const degradeArrierePlan = [Color(0xFF5E68CF), Color(0xFF8569CF)];
  static const degradeArrierePlanEclaire = [
    Color(0xFF6871D8),
    Color(0xFF8F74D8),
  ];

  final double largeur, hauteur;

  @override
  State<BoutonVocal> createState() => _BoutonVocalState();
}

class _BoutonVocalState extends State<BoutonVocal>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _survol = false, _appui = false, _focus = false;

  bool get _ecoute =>
      widget.etat == VoiceState.listening || widget.etat == VoiceState.thinking;
  bool get _parole => widget.etat == VoiceState.speaking;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchroniser();
  }

  @override
  void didUpdateWidget(BoutonVocal ancien) {
    super.didUpdateWidget(ancien);
    _synchroniser();
  }

  /// L'animation ne tourne que si elle sert (et jamais en mouvement réduit).
  void _synchroniser() {
    final reduit = MediaQuery.disableAnimationsOf(context);
    final utile = !reduit && !widget.envoi;
    if (utile && !_anim.isAnimating) {
      _anim.repeat();
    } else if (!utile && _anim.isAnimating) {
      _anim.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actif = _ecoute || _parole;
    final eclaire = _survol || _focus || actif;
    // En mode vocal (état présent), la capsule garde son aspect actuel.
    final arrierePlan = widget.chatEnArrierePlan && widget.etat == null;
    final rayon = BorderRadius.circular(widget.hauteur / 2);
    return Semantics(
      button: true,
      label: widget.libelle,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.libelle,
        waitDuration: const Duration(milliseconds: 500),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _survol = v),
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTapDown: (_) => setState(() => _appui = true),
            onTapUp: (_) => setState(() => _appui = false),
            onTapCancel: () => setState(() => _appui = false),
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: _appui ? 0.94 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: widget.largeur,
                height: widget.hauteur,
                decoration: BoxDecoration(
                  borderRadius: rayon,
                  gradient: arrierePlan
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: eclaire
                              ? BoutonVocal.degradeArrierePlanEclaire
                              : BoutonVocal.degradeArrierePlan,
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: actif
                              ? const [Color(0xFF3A3E54), Color(0xFF2A2D3D)]
                              : eclaire
                              ? const [Color(0xFF363944), Color(0xFF26282F)]
                              : const [Color(0xFF2E3039), Color(0xFF1F2128)],
                        ),
                  border: Border.all(
                    color: _focus
                        ? CouleursJarvis.signal.withValues(alpha: 0.7)
                        : Colors.white.withValues(
                            alpha: arrierePlan ? 0.22 : 0.06,
                          ),
                    width: _focus ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: eclaire
                          ? CouleursJarvis.signal.withValues(alpha: 0.24)
                          : arrierePlan
                          ? CouleursJarvis.violet.withValues(alpha: 0.22)
                          : const Color(0x22000000),
                      blurRadius: eclaire ? 16 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  // La pastille s'anime à chaque image : isolée, elle ne
                  // fait pas repeindre la barre ni le reste de la page.
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (context, _) => _pastille(_anim.value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pastille bleue ronde et son animation.
  Widget _pastille(double t) {
    final diametre = widget.hauteur * 0.64;
    final onde = math.sin(t * 2 * math.pi);
    // Repos : respiration à peine visible. Écoute : pulsation qui
    // s'éloigne. Parole : pas de halo, l'onde est dans la pastille.
    final halo = _ecoute
        ? t
        : _parole || widget.envoi
        ? 0.0
        : 0.5 + 0.5 * onde;
    return SizedBox.square(
      dimension: diametre * 1.7,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_ecoute)
            Container(
              width: diametre * (1 + 0.7 * halo),
              height: diametre * (1 + 0.7 * halo),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(
                    0xFF8EA2FF,
                  ).withValues(alpha: 0.55 * (1 - halo)),
                  width: 1.5,
                ),
              ),
            ),
          Container(
            width: diametre,
            height: diametre,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7D8DF5), Color(0xFF4C55C4)],
              ),
              // Sur la capsule bleu-violet, un fin anneau clair détache la
              // pastille.
              border: widget.chatEnArrierePlan && widget.etat == null
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF6E7EF2,
                  ).withValues(alpha: _ecoute ? 0.5 : 0.18 + 0.14 * halo),
                  blurRadius: 10,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (enfant, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: a, child: enfant),
              ),
              child: widget.envoi
                  ? Icon(
                      Icons.arrow_upward_rounded,
                      key: const ValueKey('envoi'),
                      size: diametre * 0.6,
                      color: CouleursJarvis.ivoire,
                    )
                  : _parole
                  ? _Onde(key: const ValueKey('onde'), t: t, taille: diametre)
                  : Icon(
                      Icons.graphic_eq_rounded,
                      key: const ValueKey('voix'),
                      size: diametre * 0.58,
                      color: CouleursJarvis.ivoire,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quatre barres qui ondulent pendant que JARVIS parle.
class _Onde extends StatelessWidget {
  const _Onde({super.key, required this.t, required this.taille});

  final double t;
  final double taille;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: taille * 0.08,
            height:
                taille *
                (0.18 +
                    0.3 * (0.5 + 0.5 * math.sin(t * 4 * math.pi + i * 1.3))),
            margin: EdgeInsets.symmetric(horizontal: taille * 0.035),
            decoration: BoxDecoration(
              color: CouleursJarvis.ivoire,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
