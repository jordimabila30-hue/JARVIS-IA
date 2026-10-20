import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/apparence/service_apparence.dart';

/// Propage un changement de palette à toute l'interface, sans redémarrage
/// ni perte d'état (conversation, voix, particules) : chaque élément est
/// reconstruit et repeint UNE fois (beaucoup de widgets lisent la palette
/// par `CouleursJarvis`, sans dépendre du thème). Le changement se fait en
/// fondu : l'image de l'ancien style s'efface (320 ms) au-dessus du
/// nouveau. Un changement de motif seul ne passe pas par ici (le fond
/// dépend directement du service).
class TransitionApparence extends StatefulWidget {
  const TransitionApparence({
    super.key,
    required this.service,
    required this.child,
  });

  final ServiceApparence service;
  final Widget child;

  @override
  State<TransitionApparence> createState() => _TransitionApparenceState();
}

class _TransitionApparenceState extends State<TransitionApparence>
    with SingleTickerProviderStateMixin {
  final _cle = GlobalKey();
  late final _fondu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addStatusListener(_surFondu);
  late int _version = widget.service.versionPalette;
  ui.Image? _ancienne;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_surApparence);
  }

  @override
  void didUpdateWidget(TransitionApparence ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.service != widget.service) {
      ancien.service.removeListener(_surApparence);
      widget.service.addListener(_surApparence);
      _version = widget.service.versionPalette;
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_surApparence);
    _fondu.dispose();
    _ancienne?.dispose();
    super.dispose();
  }

  void _surApparence() {
    final v = widget.service.versionPalette;
    if (v == _version || !mounted) return;
    _version = v;
    _capturer();
    _toutReconstruire();
  }

  /// Image de l'écran actuel (ancien style), pour le fondu.
  void _capturer() {
    final objet = _cle.currentContext?.findRenderObject();
    if (objet is! RenderRepaintBoundary || !objet.hasSize) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    try {
      final image = objet.toImageSync(
        pixelRatio: View.of(context).devicePixelRatio,
      );
      _ancienne?.dispose();
      setState(() => _ancienne = image);
      _fondu.forward(from: 0);
    } catch (_) {
      // Capture impossible (plateforme, écran en cours de peinture) :
      // changement direct, sans fondu.
    }
  }

  void _toutReconstruire() {
    void visiter(Element e) {
      e.markNeedsBuild();
      if (e is RenderObjectElement) e.renderObject.markNeedsPaint();
      e.visitChildren(visiter);
    }

    (context as Element).visitChildren(visiter);
  }

  void _surFondu(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted) return;
    final image = _ancienne;
    setState(() => _ancienne = null);
    // Libérée après l'image qui ne l'affiche plus.
    WidgetsBinding.instance.addPostFrameCallback((_) => image?.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final image = _ancienne;
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(key: _cle, child: widget.child),
        if (image != null)
          IgnorePointer(
            child: FadeTransition(
              opacity: ReverseAnimation(
                CurvedAnimation(parent: _fondu, curve: Curves.easeOutCubic),
              ),
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
      ],
    );
  }
}
