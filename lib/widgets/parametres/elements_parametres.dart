import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Éléments visuels communs du panneau Paramètres : cartes claires aux
/// contours fins, lignes de réglage, listes déroulantes et curseurs.

/// Carte qui regroupe des réglages liés.
class CarteReglages extends StatelessWidget {
  const CarteReglages({super.key, required this.enfants, this.titre});

  final String? titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titre != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              titre!.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: CouleursJarvis.coque.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: CouleursJarvis.trait.withValues(alpha: 0.7),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < enfants.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: CouleursJarvis.trait.withValues(alpha: 0.45),
                    ),
                  enfants[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Titre et description d'un réglage.
class TexteReglage extends StatelessWidget {
  const TexteReglage({super.key, required this.titre, this.description});

  final String titre;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titre,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: CouleursJarvis.texte,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 3),
          Text(
            description!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne de réglage : texte à gauche et contrôle à droite quand la place le
/// permet, l'un sous l'autre sinon.
class LigneReglage extends StatelessWidget {
  const LigneReglage({
    super.key,
    required this.titre,
    this.description,
    required this.controle,
    this.largeurControle = 300,
    this.note,
    this.action,
  });

  final String titre;
  final String? description;
  final Widget controle;
  final double largeurControle;

  /// Remarque discrète sous la ligne (limite de la plateforme…).
  final String? note;

  /// Action secondaire sous la ligne.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final texte = TexteReglage(titre: titre, description: description);
          final cote = c.maxWidth >= largeurControle + 220;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cote)
                Row(
                  children: [
                    Expanded(child: texte),
                    const SizedBox(width: 24),
                    SizedBox(width: largeurControle, child: controle),
                  ],
                )
              else ...[
                texte,
                const SizedBox(height: 12),
                controle,
              ],
              if (note != null) ...[
                const SizedBox(height: 10),
                NoteReglage(note!),
              ],
              if (action != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Petite remarque (gris chaud, icône info).
class NoteReglage extends StatelessWidget {
  const NoteReglage(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline,
            size: 15,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
      ],
    );
  }
}

/// Liste déroulante sobre (contour fin, fond clair).
class ListeReglage<T> extends StatelessWidget {
  const ListeReglage({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.options,
    required this.surChoix,
  });

  /// Nom accessible de la liste.
  final String libelle;
  final T valeur;
  final List<(T, String)> options;

  /// Null : liste désactivée.
  final ValueChanged<T>? surChoix;

  @override
  Widget build(BuildContext context) {
    final actif = surChoix != null && options.length > 1;
    // Même police que le reste de l'interface.
    final base = Theme.of(context).textTheme.bodyLarge!;
    return Semantics(
      label: libelle,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(
          color: actif
              ? CouleursJarvis.ivoire
              : CouleursJarvis.creme.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CouleursJarvis.trait),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: valeur,
            isExpanded: true,
            borderRadius: BorderRadius.circular(14),
            dropdownColor: CouleursJarvis.coque,
            focusColor: CouleursJarvis.signal.withValues(alpha: 0.08),
            icon: Icon(
              Icons.expand_more,
              color: CouleursJarvis.texteSecondaire,
            ),
            style: base.copyWith(fontSize: 14, color: CouleursJarvis.texte),
            onChanged: actif ? (v) => surChoix!(v as T) : null,
            disabledHint: Text(
              options
                  .firstWhere(
                    (o) => o.$1 == valeur,
                    orElse: () => options.first,
                  )
                  .$2,
              overflow: TextOverflow.ellipsis,
              style: base.copyWith(
                fontSize: 14,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
            items: [
              for (final o in options)
                DropdownMenuItem<T>(
                  value: o.$1,
                  child: Text(o.$2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Curseur avec titre, valeur affichée et, de chaque côté, une petite
/// icône qui indique le sens (lent / rapide…). Utilisable au clavier.
class CurseurReglage extends StatelessWidget {
  const CurseurReglage({
    super.key,
    required this.titre,
    required this.valeurAffichee,
    required this.valeur,
    required this.min,
    required this.max,
    required this.divisions,
    required this.surChangement,
    this.icones,
    this.surFin,
    this.description,
  });

  final String titre;
  final String? description;
  final String valeurAffichee;
  final double valeur;
  final double min, max;
  final int divisions;
  final ValueChanged<double>? surChangement;

  /// Fin du geste (valeur à enregistrer) ; null : rien de plus.
  final ValueChanged<double>? surFin;

  /// Icônes du minimum et du maximum.
  final (IconData, IconData)? icones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TexteReglage(titre: titre, description: description),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: CouleursJarvis.signal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  valeurAffichee,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CouleursJarvis.signal,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (icones case (final bas, _)) _icone(bas),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: CouleursJarvis.signal,
                    inactiveTrackColor: CouleursJarvis.trait.withValues(
                      alpha: 0.8,
                    ),
                    thumbColor: CouleursJarvis.signal,
                    overlayColor: CouleursJarvis.signal.withValues(alpha: 0.1),
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                      elevation: 1.5,
                    ),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    value: valeur.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    semanticFormatterCallback: (_) =>
                        '$titre : $valeurAffichee',
                    onChanged: surChangement,
                    onChangeEnd: surFin,
                  ),
                ),
              ),
              if (icones case (_, final haut)) _icone(haut),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _icone(IconData icone) => ExcludeSemantics(
    child: Icon(icone, size: 18, color: CouleursJarvis.texteSecondaire),
  );
}

/// Pastille de choix (profil vocal, forme à prévisualiser…) : coche et
/// contour bleu-violet quand elle est choisie.
class PastilleReglage extends StatelessWidget {
  const PastilleReglage({
    super.key,
    required this.libelle,
    required this.choisie,
    this.surChoix,
  });

  final String libelle;
  final bool choisie;
  final VoidCallback? surChoix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: choisie,
      button: surChoix != null,
      child: Material(
        color: choisie
            ? CouleursJarvis.signal.withValues(alpha: 0.1)
            : CouleursJarvis.ivoire,
        shape: StadiumBorder(
          side: BorderSide(
            color: choisie
                ? CouleursJarvis.signal.withValues(alpha: 0.55)
                : CouleursJarvis.trait,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: surChoix,
          focusColor: CouleursJarvis.signal.withValues(alpha: 0.14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choisie) ...[
                    Icon(Icons.check, size: 16, color: CouleursJarvis.signal),
                    const SizedBox(width: 6),
                  ],
                  // Écran étroit : le libellé passe à la ligne plutôt que
                  // de déborder.
                  Flexible(
                    child: Text(
                      libelle,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: choisie ? FontWeight.w600 : FontWeight.w400,
                        color: choisie
                            ? CouleursJarvis.signal
                            : CouleursJarvis.texte,
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

/// Tuile de choix visuelle (forme de JARVIS…) : visuel et nom ; contour et
/// fond bleu-violet quand elle est choisie. Le visuel reçoit la couleur à
/// utiliser (icône Material ou dessin).
class TuileChoix extends StatelessWidget {
  const TuileChoix({
    super.key,
    required this.icone,
    required this.libelle,
    required this.choisie,
    required this.surChoix,
  });

  final Widget Function(Color couleur) icone;
  final String libelle;
  final bool choisie;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    final couleur = choisie ? CouleursJarvis.signal : CouleursJarvis.texte;
    return Semantics(
      selected: choisie,
      button: true,
      child: Material(
        color: choisie
            ? CouleursJarvis.signal.withValues(alpha: 0.08)
            : CouleursJarvis.ivoire,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: choisie
                ? CouleursJarvis.signal.withValues(alpha: 0.6)
                : CouleursJarvis.trait,
            width: choisie ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: surChoix,
          focusColor: CouleursJarvis.signal.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 36, child: Center(child: icone(couleur))),
                const SizedBox(height: 12),
                Text(
                  libelle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: choisie ? FontWeight.w600 : FontWeight.w500,
                    color: couleur,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
