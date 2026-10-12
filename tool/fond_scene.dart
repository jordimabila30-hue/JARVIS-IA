import 'package:flutter/material.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';

/// Fond seul, zone des particules de côté [zone] centrée un peu au-dessus
/// du milieu : la zone est mesurée après la mise en page et transmise au
/// fond, comme le fait le moteur PIM.
Widget sceneFond(double zone) => _SceneFond(zone);

class _SceneFond extends StatefulWidget {
  const _SceneFond(this.zone);
  final double zone;
  @override
  State<_SceneFond> createState() => _SceneFondState();
}

class _SceneFondState extends State<_SceneFond> {
  final _cle = GlobalKey();
  final _rect = ValueNotifier<Rect?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final b = _cle.currentContext!.findRenderObject()! as RenderBox;
      _rect.value = b.localToGlobal(Offset.zero) & b.size;
    });
  }

  @override
  Widget build(BuildContext context) => FondJarvisAnime(
    zoneParticules: _rect,
    child: Align(
      alignment: const Alignment(0, -0.25),
      child: SizedBox.square(key: _cle, dimension: widget.zone),
    ),
  );
}
