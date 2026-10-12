import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';
import '../conversation/signature_jarvis.dart';

/// Logo de JARVIS sur les pages d'authentification. Provisoire : la perle
/// JARVIS. Pour changer le logo des trois pages, il suffit de modifier ce
/// widget.
class LogoAuth extends StatelessWidget {
  const LogoAuth({super.key, this.taille = 72});

  final double taille;

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: PerleJarvis(taille: taille));
}

/// En-tête commun : logo, titre (police d'affichage) et sous-titre.
class EnteteAuth extends StatelessWidget {
  const EnteteAuth({super.key, required this.titre, required this.sousTitre});

  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 360;
    return Column(
      children: [
        LogoAuth(taille: etroit ? 60 : 72),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            titre,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: policeAffichage,
              fontSize: etroit ? 26 : 30,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
              height: 1.15,
              color: CouleursJarvis.texte,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sousTitre,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
      ],
    );
  }
}
