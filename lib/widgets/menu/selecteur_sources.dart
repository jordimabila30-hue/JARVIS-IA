import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/conversations/source_conversation.dart';
import '../../theme/theme_jarvis.dart';
import '../conversation/signature_jarvis.dart';

/// Logo d'une messagerie, proportions d'origine, dans un carré de
/// [taille] px. Ressources locales uniquement (jamais chargées depuis
/// Internet).
class LogoSource extends StatelessWidget {
  const LogoSource({super.key, required this.source, this.taille = 24});

  final SourceConversation source;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final logo = source.logo;
    return SizedBox.square(
      dimension: taille,
      child: logo == null
          // Logo JARVIS pas encore fourni : la perle JARVIS.
          ? PerleJarvis(taille: taille)
          : logo.endsWith('.svg')
          ? SvgPicture.asset(logo, fit: BoxFit.contain)
          : Image.asset(
              logo,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => PerleJarvis(taille: taille),
            ),
    );
  }
}

/// Rangée de logos des messageries : un toucher choisit la source (contour
/// et fond violet léger, libellé plus marqué). Défile horizontalement si
/// tout ne tient pas.
///
/// Aucune hauteur ni largeur figée : la rangée prend la hauteur réelle du
/// logo et de son nom, et chaque onglet s'élargit si le nom l'exige (police
/// agrandie dans les réglages du téléphone). Rien n'est coupé.
class SelecteurSources extends StatelessWidget {
  const SelecteurSources({
    super.key,
    required this.sources,
    required this.selection,
    required this.surChoix,
  });

  final List<SourceConversation> sources;
  final ValueNotifier<SourceConversation> selection;
  final ValueChanged<SourceConversation> surChoix;

  /// Zone du logo (carré arrondi) et largeur minimale d'un onglet.
  static const tailleZone = 44.0;
  static const largeurOnglet = 58.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SourceConversation>(
      valueListenable: selection,
      builder: (context, choisie, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in sources)
              _Onglet(
                source: s,
                choisie: s == choisie,
                surChoix: () => surChoix(s),
              ),
          ],
        ),
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
    required this.source,
    required this.choisie,
    required this.surChoix,
  });

  final SourceConversation source;
  final bool choisie;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    const duree = Duration(milliseconds: 140);
    return Semantics(
      button: true,
      selected: choisie,
      label: source.libelle,
      excludeSemantics: true,
      child: Tooltip(
        message: source.libelle,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: surChoix,
          borderRadius: BorderRadius.circular(14),
          hoverColor: CouleursJarvis.signal.withValues(alpha: 0.04),
          focusColor: CouleursJarvis.signal.withValues(alpha: 0.1),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: SelecteurSources.largeurOnglet,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: duree,
                    curve: Curves.easeOut,
                    width: SelecteurSources.tailleZone,
                    height: SelecteurSources.tailleZone,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: choisie
                          ? CouleursJarvis.signal.withValues(alpha: 0.08)
                          : CouleursJarvis.coque,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: choisie
                            ? CouleursJarvis.signal.withValues(alpha: 0.65)
                            : CouleursJarvis.trait.withValues(alpha: 0.7),
                        width: choisie ? 1.4 : 1,
                      ),
                    ),
                    child: LogoSource(source: source, taille: 24),
                  ),
                  const SizedBox(height: 5),
                  AnimatedDefaultTextStyle(
                    duration: duree,
                    // Sur la base du style hérité : même police que le reste.
                    style: DefaultTextStyle.of(context).style.copyWith(
                      fontSize: 10.5,
                      // Interligne propre au libellé (l'hérité, 1,45, le
                      // gonflait sans raison).
                      height: 1.3,
                      letterSpacing: 0.1,
                      fontWeight: choisie ? FontWeight.w600 : FontWeight.w400,
                      color: choisie
                          ? CouleursJarvis.signal
                          : CouleursJarvis.texteSecondaire,
                    ),
                    // Nom entier, sur une ligne : l'onglet (58 px) ne
                    // s'élargit que si le nom l'exige, avec un petit écart.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(source.libelle, maxLines: 1, softWrap: false),
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
