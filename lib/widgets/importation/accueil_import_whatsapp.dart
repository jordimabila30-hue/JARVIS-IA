import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';
import 'logo_whatsapp.dart';

/// Carte principale quand aucun fichier n'est là : logo, « Importer depuis
/// WhatsApp » et une courte description. L'action principale est posée
/// sous la carte, par la page ([BoutonPrincipalImport]) : le partage se
/// lance dans WhatsApp (pas dans JARVIS), jamais un faux « recevoir ».
class CarteImporterWhatsApp extends StatelessWidget {
  const CarteImporterWhatsApp({
    super.key,
    required this.sousTitre,
    this.survolDepot = false,
  });

  static const titre = 'Importer depuis WhatsApp';
  static const partager = 'Partagez un export avec JARVIS';
  static const ouvrirWhatsApp = 'Ouvrir WhatsApp';

  /// Hauteur commune aux cartes de l'import (celle-ci, et la carte du
  /// fichier reçu) : l'écran garde les mêmes proportions d'un état à
  /// l'autre. Elles grandissent si le texte l'exige.
  static const hauteurMin = 292.0;

  final String sousTitre;

  /// Un fichier est glissé au-dessus de la page (ordinateur, navigateur).
  final bool survolDepot;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: hauteurMin),
      alignment: Alignment.center,
      // Marges égales en haut et en bas : le logo et son auréole tombent
      // au centre optique de la carte.
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: survolDepot
            ? Color.alphaBlend(
                CouleursJarvis.violetPoudre.withValues(alpha: 0.35),
                CouleursJarvis.coque,
              )
            : CouleursJarvis.coque,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: survolDepot
              ? CouleursJarvis.signal.withValues(alpha: 0.45)
              : CouleursJarvis.trait.withValues(alpha: 0.8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D3A3350),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _LogoAureole()),
          const SizedBox(height: 16),
          const Text(
            titre,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: policeAffichage,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: CouleursJarvis.texte,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sousTitre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo WhatsApp sur une tuile claire, auréolé de lavande (immobile).
class _LogoAureole extends StatelessWidget {
  const _LogoAureole();

  @override
  Widget build(BuildContext context) {
    Widget anneau(double d, double alpha) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CouleursJarvis.lavande.withValues(alpha: alpha),
        ),
      ),
    );
    return SizedBox.square(
      dimension: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo lavande diffus, puis deux anneaux très fins.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  CouleursJarvis.lavande.withValues(alpha: 0.9),
                  CouleursJarvis.violetPoudre.withValues(alpha: 0.45),
                  CouleursJarvis.violetPoudre.withValues(alpha: 0),
                ],
                stops: const [0.3, 0.6, 1],
              ),
            ),
          ),
          anneau(146, 0.55),
          anneau(118, 0.8),
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CouleursJarvis.coque,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x225559B8),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const LogoWhatsApp(taille: 48),
          ),
        ],
      ),
    );
  }
}

/// Bouton violet de l'import (action principale).
class BoutonPrincipalImport extends StatelessWidget {
  const BoutonPrincipalImport({
    super.key,
    required this.libelle,
    required this.icone,
    required this.surAppui,
    this.enCours = false,
  });

  final String libelle;
  final IconData icone;
  final VoidCallback? surAppui;
  final bool enCours;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: surAppui,
      icon: enCours
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CouleursJarvis.ivoire,
              ),
            )
          : Icon(icone, size: 20),
      label: Text(libelle),
      style: FilledButton.styleFrom(
        backgroundColor: CouleursJarvis.signal,
        foregroundColor: CouleursJarvis.ivoire,
        disabledBackgroundColor: CouleursJarvis.signal.withValues(alpha: 0.14),
        disabledForegroundColor: CouleursJarvis.signal.withValues(alpha: 0.55),
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

/// Option secondaire : « Parcourir les fichiers · ZIP, TXT ».
class CarteParcourir extends StatelessWidget {
  const CarteParcourir({super.key, required this.surAppui});

  static const titre = 'Parcourir les fichiers';
  static const formats = 'ZIP, TXT';

  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CouleursJarvis.coque,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: surAppui,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CouleursJarvis.lavande.withValues(alpha: 0.9),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CouleursJarvis.violetPoudre.withValues(alpha: 0.6),
                ),
                child: const Icon(
                  Icons.folder_open_outlined,
                  size: 22,
                  color: CouleursJarvis.signal,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      formats,
                      style: TextStyle(
                        fontSize: 13,
                        color: CouleursJarvis.texteSecondaire,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: CouleursJarvis.texteSecondaire,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lien discret « Comment importer ? ».
class BoutonCommentImporter extends StatelessWidget {
  const BoutonCommentImporter({super.key, required this.etapes});

  static const libelle = 'Comment importer ?';

  final List<String> etapes;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => afficherCommentImporter(context, etapes),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text(libelle),
        style: TextButton.styleFrom(
          foregroundColor: CouleursJarvis.signal.withValues(alpha: 0.85),
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13.5),
        ),
      ),
    );
  }
}

/// Les étapes, dans une feuille en bas de l'écran.
Future<void> afficherCommentImporter(
  BuildContext context,
  List<String> etapes,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: CouleursJarvis.texte.withValues(alpha: 0.16),
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: CouleursJarvis.coque,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        22 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: CouleursJarvis.trait,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              LogoWhatsApp(taille: 22),
              SizedBox(width: 10),
              Text(
                BoutonCommentImporter.libelle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CouleursJarvis.texte,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < etapes.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CouleursJarvis.signal.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CouleursJarvis.signal,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      etapes[i],
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (i < etapes.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    ),
  );
}
