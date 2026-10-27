import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Réglages d'une idée de réponse : deux menus côte à côte, « Ton ▾ » et
/// « Longueur ▾ » (WhatsApp, Messenger, Mail, messages rapportés, chat).
/// Même hauteur, même largeur ; l'un sous l'autre si l'écran est trop
/// étroit ou le texte très agrandi. Les choix viennent des propositions
/// (rien d'inventé) ; [surTon] / [surLongueur] gardent la logique actuelle.
class SelecteursReponse extends StatelessWidget {
  const SelecteursReponse({
    super.key,
    required this.tons,
    required this.ton,
    required this.surTon,
    this.longueurs = const [],
    this.longueur,
    this.surLongueur,
  });

  final List<String> tons;
  final int ton;
  final ValueChanged<int> surTon;

  /// Libellés des longueurs (vide : pas de menu Longueur).
  final List<String> longueurs;
  final int? longueur;
  final ValueChanged<int>? surLongueur;

  static const cleTon = Key('menu-ton');
  static const cleLongueur = Key('menu-longueur');

  /// Clés des choix dans les menus ouverts (tests, accessibilité).
  static Key choixTon(String nom) => Key('ton-propose-$nom');
  static Key choixLongueur(String nom) => Key('longueur-$nom');

  @override
  Widget build(BuildContext context) {
    final menus = <Widget>[
      _Menu(
        key: cleTon,
        titre: 'Ton',
        choix: tons,
        choisi: ton,
        cle: (i) => choixTon(tons[i]),
        surChoix: surTon,
      ),
      if (longueurs.isNotEmpty && surLongueur != null)
        _Menu(
          key: cleLongueur,
          titre: 'Longueur',
          choix: longueurs,
          choisi: longueur ?? 0,
          cle: (i) => choixLongueur(longueurs[i].toLowerCase()),
          surChoix: surLongueur!,
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final grand = MediaQuery.textScalerOf(context).scale(14) > 20;
        if (menus.length == 1) {
          return Align(alignment: Alignment.centerLeft, child: menus.first);
        }
        if (c.maxWidth < 240 || grand) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [menus[0], const SizedBox(height: 6), menus[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: menus[0]),
            const SizedBox(width: 8),
            Expanded(child: menus[1]),
          ],
        );
      },
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    super.key,
    required this.titre,
    required this.choix,
    required this.choisi,
    required this.cle,
    required this.surChoix,
  });

  final String titre;
  final List<String> choix;
  final int choisi;
  final Key Function(int) cle;
  final ValueChanged<int> surChoix;

  @override
  Widget build(BuildContext context) {
    final valeur = choix.isEmpty
        ? ''
        : choix[choisi.clamp(0, choix.length - 1)];
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(CouleursJarvis.coque),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: const WidgetStatePropertyAll(Color(0x403A3350)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: CouleursJarvis.trait),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      menuChildren: [
        for (final (i, nom) in choix.indexed)
          MenuItemButton(
            key: cle(i),
            onPressed: () => surChoix(i),
            leadingIcon: SizedBox(
              width: 18,
              child: i == choisi
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: CouleursJarvis.signal,
                    )
                  : null,
            ),
            child: Text(
              nom,
              style: TextStyle(
                fontWeight: i == choisi ? FontWeight.w600 : FontWeight.w400,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        label: '$titre : $valeur',
        excludeSemantics: true,
        child: Material(
          color: CouleursJarvis.coque.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: CouleursJarvis.lavande),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            titre,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: CouleursJarvis.texteSecondaire,
                            ),
                          ),
                          Text(
                            valeur,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: CouleursJarvis.signal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: CouleursJarvis.texteSecondaire,
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
