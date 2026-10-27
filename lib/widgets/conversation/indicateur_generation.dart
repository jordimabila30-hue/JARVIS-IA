import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';
import '../../utils/chrono_perf.dart';

/// Génération en cours : petit cercle qui tourne + libellé court
/// (« Préparation… », « Rédaction… »). Seul le cercle se repeint
/// (RepaintBoundary) ; rien n'est reconstruit à chaque image. Réduction des
/// animations (système) : point fixe. Attente anormalement longue : après
/// [delaiLong], [libelleLong] remplace le libellé (aucune fausse progression).
class IndicateurGeneration extends StatefulWidget {
  const IndicateurGeneration({
    super.key,
    required this.libelle,
    this.libelleLong,
    this.delaiLong = const Duration(seconds: 15),
  });

  static const preparation = 'Préparation…';
  static const redaction = 'Rédaction…';
  static const propositions = 'Préparation des réponses…';
  static const longue = 'Toujours en cours…';

  final String libelle;
  final String? libelleLong;
  final Duration delaiLong;

  @override
  State<IndicateurGeneration> createState() => _IndicateurGenerationState();
}

class _IndicateurGenerationState extends State<IndicateurGeneration> {
  Timer? _minuteur;
  bool _long = false;

  @override
  void initState() {
    super.initState();
    if (widget.libelleLong != null) {
      _minuteur = Timer(widget.delaiLong, () {
        if (mounted) setState(() => _long = true);
      });
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = CouleursJarvis.violet;
    final fixe =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        ChronoPerf.sans('indicateur');
    final libelle = _long ? widget.libelleLong! : widget.libelle;
    return Semantics(
      liveRegion: true,
      label: libelle,
      excludeSemantics: true,
      child: Row(
        key: const Key('indicateur-generation'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 11,
            child: fixe
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: couleur.withValues(alpha: 0.6),
                    ),
                  )
                : RepaintBoundary(
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: couleur,
                      backgroundColor: couleur.withValues(alpha: 0.15),
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
