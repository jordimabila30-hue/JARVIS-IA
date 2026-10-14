import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/ecriture/ecriture_progressive.dart';
import '../../theme/theme_jarvis.dart';

/// Texte qui s'écrit progressivement ([EcritureProgressive]), avec un
/// curseur discret tant que l'écriture n'est pas terminée.
///
/// Un `Ticker` tourne seulement quand du texte reçu attend d'être révélé ;
/// il s'arrête dès que l'écriture a rattrapé le texte reçu, et repart à
/// l'arrivée du fragment suivant. Seul ce widget est reconstruit, jamais
/// la page. Préférence « réduire les animations » : texte affiché aussitôt,
/// curseur fixe.
///
/// Une fois l'écriture terminée, c'est un simple [Text] : rendu identique
/// à celui d'un message affiché d'un coup.
class TexteProgressif extends StatefulWidget {
  const TexteProgressif({
    super.key,
    required this.ecriture,
    required this.style,
    this.curseur = true,
  });

  final EcritureProgressive ecriture;
  final TextStyle style;

  /// Curseur d'écriture pendant l'écriture.
  final bool curseur;

  /// Curseur d'écriture (pour les tests).
  static const cleCurseur = Key('curseur-ecriture');

  @override
  State<TexteProgressif> createState() => _TexteProgressifState();
}

class _TexteProgressifState extends State<TexteProgressif>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_surImage);
  Duration _precedente = Duration.zero;
  String _affiche = '';
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    _affiche = widget.ecriture.visible;
    _termine = widget.ecriture.termine;
    widget.ecriture.addListener(_surEcriture);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appliquerPreference();
    _relancer();
  }

  /// « Réduire les animations » : appliqué après l'image (changer
  /// l'écriture prévient d'autres widgets, jamais pendant une construction).
  void _appliquerPreference() {
    final reduit = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduit == widget.ecriture.immediat) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.ecriture.immediat = reduit;
    });
  }

  @override
  void didUpdateWidget(TexteProgressif ancien) {
    super.didUpdateWidget(ancien);
    if (!identical(ancien.ecriture, widget.ecriture)) {
      ancien.ecriture.removeListener(_surEcriture);
      widget.ecriture.addListener(_surEcriture);
      _appliquerPreference();
      _ticker.stop();
      _surEcriture();
    }
  }

  @override
  void dispose() {
    widget.ecriture.removeListener(_surEcriture);
    _ticker.dispose();
    super.dispose();
  }

  void _relancer() {
    if (widget.ecriture.enMouvement && !_ticker.isActive) {
      _precedente = Duration.zero;
      _ticker.start();
    }
  }

  void _surImage(Duration ecoule) {
    final pas = ecoule - _precedente;
    _precedente = ecoule;
    widget.ecriture.avancer(pas);
    if (!widget.ecriture.enMouvement) _ticker.stop();
  }

  void _surEcriture() {
    _relancer();
    final e = widget.ecriture;
    final visible = e.visible;
    final termine = e.termine;
    // Reconstruit seulement si ce qui est affiché change (un fragment reçu
    // mais pas encore révélé ne coûte rien).
    if (visible == _affiche && termine == _termine) return;
    if (!mounted) return;
    setState(() {
      _affiche = visible;
      _termine = termine;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_termine || !widget.curseur) {
      return Text(_affiche, style: widget.style);
    }
    final hauteur = (widget.style.fontSize ?? 15) * 1.15;
    return Text.rich(
      TextSpan(
        text: _affiche,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: _affiche.isEmpty ? 0 : 2),
              child: CurseurEcriture(
                key: TexteProgressif.cleCurseur,
                hauteur: hauteur,
              ),
            ),
          ),
        ],
      ),
      style: widget.style,
    );
  }
}

/// Curseur d'écriture : fine barre lavande qui respire doucement (fixe si
/// les animations sont réduites). Dessiné dans sa propre couche : son
/// animation ne repeint pas le texte.
class CurseurEcriture extends StatefulWidget {
  const CurseurEcriture({super.key, required this.hauteur});

  final double hauteur;

  @override
  State<CurseurEcriture> createState() => _CurseurEcritureState();
}

class _CurseurEcritureState extends State<CurseurEcriture>
    with SingleTickerProviderStateMixin {
  late final _respiration = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    lowerBound: 0.3,
    value: 0.9,
  );
  late final _opacite = CurvedAnimation(
    parent: _respiration,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduit = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduit) {
      _respiration
        ..stop()
        ..value = 0.7;
    } else if (!_respiration.isAnimating) {
      _respiration.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _opacite.dispose();
    _respiration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: _opacite,
          child: Container(
            width: 2,
            height: widget.hauteur,
            decoration: BoxDecoration(
              color: CouleursJarvis.violet,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Tout afficher » : action discrète, visible seulement quand assez de
/// texte reçu attend d'être révélé ([EcritureProgressive.rattrapable]).
/// N'interrompt jamais la réception.
class ActionToutAfficher extends StatelessWidget {
  const ActionToutAfficher({super.key, required this.ecriture});

  final EcritureProgressive ecriture;

  static const libelle = 'Tout afficher';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ecriture.rattrapable,
      builder: (context, visible, _) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !visible,
          child: TextButton(
            onPressed: ecriture.toutAfficher,
            style: TextButton.styleFrom(
              foregroundColor: CouleursJarvis.signal,
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            child: const Text(libelle),
          ),
        ),
      ),
    );
  }
}
