import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_jarvis.dart';

/// Morceau d'une réponse de JARVIS.
sealed class BlocTexte {
  const BlocTexte();
}

class Paragraphe extends BlocTexte {
  const Paragraphe(this.texte);
  final String texte;
}

/// Bloc de code (« ``` »), recopié tel quel (espaces, indentation).
class BlocCode extends BlocTexte {
  const BlocCode(this.code, {this.langage = ''});
  final String code;
  final String langage;
}

/// Tableau Markdown : première ligne = en-tête ; toutes les lignes ont le
/// même nombre de cellules.
class Tableau extends BlocTexte {
  const Tableau(this.lignes);
  final List<List<String>> lignes;
}

/// Réponse terminée contenant du code ou un tableau : ces blocs défilent
/// horizontalement dans la carte (jamais la conversation entière), le code
/// garde sa police à chasse fixe et un bouton « Copier le code ». Le reste
/// du texte s'affiche exactement comme avant.
class TexteRiche extends StatelessWidget {
  const TexteRiche({super.key, required this.texte, required this.style});

  final String texte;
  final TextStyle style;

  static final _ligneTableau = RegExp(r'^\s*\|.*\|\s*$', multiLine: true);
  static final _separateur = RegExp(
    r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$',
  );

  /// Lien Markdown « [texte](https://…) » ou adresse web nue.
  static final lien = RegExp(
    // Parenthèses équilibrées admises dans l'adresse (« …/x_(y) »).
    r'\[([^\]\n]+)\]\((https?://(?:[^\s()]|\([^\s()]*\))+)\)'
    r'|https?://[^\s<>"]+',
  );

  /// Ponctuation collée à la fin d'une adresse nue (pas dans le lien).
  static final _finAdresse = RegExp(r'[.,;:!?»)\]]+$');

  /// Seules les adresses web s'ouvrent (jamais javascript:, file:, intent:…).
  static Uri? destination(String adresse) {
    final uri = Uri.tryParse(adresse);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return uri.host.isEmpty ? null : uri;
  }

  /// Ouverture d'un lien (remplaçable dans les tests).
  static Future<bool> Function(Uri) ouvrir = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Vrai si [texte] contient un lien ou un bloc que le texte simple
  /// affiche mal.
  static bool utile(String texte) =>
      texte.contains('http') && lien.hasMatch(texte) ||
      texte.contains('```') ||
      (_ligneTableau.hasMatch(texte) &&
          texte.split('\n').any(_separateur.hasMatch));

  /// Découpe [texte] en paragraphes, blocs de code et tableaux.
  static List<BlocTexte> decouper(String texte) {
    final lignes = texte.split('\n');
    final blocs = <BlocTexte>[];
    final paragraphe = <String>[];

    void fermerParagraphe() {
      final t = paragraphe.join('\n').trim();
      if (t.isNotEmpty) blocs.add(Paragraphe(t));
      paragraphe.clear();
    }

    var i = 0;
    while (i < lignes.length) {
      final ligne = lignes[i];
      if (ligne.trimLeft().startsWith('```')) {
        fermerParagraphe();
        final langage = ligne.trimLeft().substring(3).trim();
        final code = <String>[];
        i++;
        while (i < lignes.length && !lignes[i].trimLeft().startsWith('```')) {
          code.add(lignes[i]);
          i++;
        }
        i++; // fermeture (ou fin du texte)
        blocs.add(BlocCode(code.join('\n'), langage: langage));
        continue;
      }
      if (_ligneTableau.hasMatch(ligne) &&
          i + 1 < lignes.length &&
          _separateur.hasMatch(lignes[i + 1])) {
        fermerParagraphe();
        final rangs = <List<String>>[_cellules(ligne)];
        i += 2;
        while (i < lignes.length && _ligneTableau.hasMatch(lignes[i])) {
          rangs.add(_cellules(lignes[i]));
          i++;
        }
        final largeur = rangs.fold(0, (n, r) => r.length > n ? r.length : n);
        blocs.add(
          Tableau([
            for (final r in rangs)
              [...r, for (var k = r.length; k < largeur; k++) ''],
          ]),
        );
        continue;
      }
      paragraphe.add(ligne);
      i++;
    }
    fermerParagraphe();
    return blocs;
  }

  /// Cellules d'une ligne « | a | b | » (« \| » garde une barre).
  static List<String> _cellules(String ligne) {
    var t = ligne.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|') && !t.endsWith(r'\|')) t = t.substring(0, t.length - 1);
    return [
      for (final c in t.split(RegExp(r'(?<!\\)\|')))
        c.trim().replaceAll(r'\|', '|'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final blocs = decouper(texte);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in blocs.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: switch (b) {
              Paragraphe(:final texte) => _Paragraphe(
                texte: texte,
                style: style,
              ),
              BlocCode() => _VueCode(bloc: b, style: style),
              Tableau(:final lignes) => _VueTableau(
                lignes: lignes,
                style: style,
              ),
            },
          ),
      ],
    );
  }
}

class _VueCode extends StatefulWidget {
  const _VueCode({required this.bloc, required this.style});

  final BlocCode bloc;
  final TextStyle style;

  @override
  State<_VueCode> createState() => _VueCodeState();
}

class _VueCodeState extends State<_VueCode> {
  bool _copie = false;
  Timer? _retour;

  @override
  void dispose() {
    _retour?.cancel();
    super.dispose();
  }

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.bloc.code));
    if (!mounted) return;
    setState(() => _copie = true);
    _retour?.cancel();
    _retour = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copie = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final taille = widget.style.fontSize ?? 15;
    final secondaire = TextStyle(
      fontSize: 12,
      color: CouleursJarvis.texteSecondaire,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CouleursJarvis.texte.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.bloc.langage.isEmpty ? 'Code' : widget.bloc.langage,
                    style: secondaire,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: _copie ? 'Code copié' : 'Copier le code',
                  onPressed: _copier,
                  iconSize: 16,
                  color: CouleursJarvis.texteSecondaire,
                  icon: Icon(
                    _copie ? Icons.check_rounded : Icons.content_copy_rounded,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              widget.bloc.code,
              softWrap: false,
              style: widget.style.copyWith(
                // Embarquée (le Web n'a pas les polices du système).
                fontFamily: 'RobotoMono',
                fontFamilyFallback: const ['monospace', 'Consolas', 'Menlo'],
                fontSize: taille * 0.88,
                height: 1.45,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VueTableau extends StatelessWidget {
  const _VueTableau({required this.lignes, required this.style});

  final List<List<String>> lignes;
  final TextStyle style;

  /// Largeur maximale d'une colonne : un texte long passe à la ligne dans
  /// sa cellule au lieu d'élargir le tableau à l'infini.
  static const largeurMaxColonne = 260.0;

  @override
  Widget build(BuildContext context) {
    final trait = CouleursJarvis.trait.withValues(alpha: 0.8);
    final petit = style.copyWith(fontSize: (style.fontSize ?? 15) * 0.93);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder.all(
          color: trait,
          borderRadius: BorderRadius.circular(8),
        ),
        children: [
          for (final (i, ligne) in lignes.indexed)
            TableRow(
              decoration: i == 0
                  ? BoxDecoration(
                      color: CouleursJarvis.texte.withValues(alpha: 0.05),
                    )
                  : null,
              children: [
                for (final cellule in ligne)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: largeurMaxColonne,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        cellule,
                        style: i == 0
                            ? petit.copyWith(fontWeight: FontWeight.w600)
                            : petit,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Paragraphe : liens web soulignés et cliquables, le reste à l'identique.
class _Paragraphe extends StatefulWidget {
  const _Paragraphe({required this.texte, required this.style});

  final String texte;
  final TextStyle style;

  @override
  State<_Paragraphe> createState() => _ParagrapheState();
}

class _ParagrapheState extends State<_Paragraphe> {
  final _gestes = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final g in _gestes) {
      g.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _morceaux() {
    for (final g in _gestes) {
      g.dispose();
    }
    _gestes.clear();
    final t = widget.texte;
    final morceaux = <InlineSpan>[];
    var debut = 0;
    for (final m in TexteRiche.lien.allMatches(t)) {
      var fin = m.end;
      var affiche = m.group(1);
      var adresse = m.group(2);
      if (adresse == null) {
        // Adresse nue : la ponctuation finale reste du texte.
        final brute = m.group(0)!;
        final ponctuation = TexteRiche._finAdresse.firstMatch(brute);
        adresse = ponctuation == null
            ? brute
            : brute.substring(0, ponctuation.start);
        fin = m.start + adresse.length;
        affiche = adresse;
      }
      final uri = TexteRiche.destination(adresse);
      if (uri == null) continue;
      if (m.start > debut) {
        morceaux.add(TextSpan(text: t.substring(debut, m.start)));
      }
      final geste = TapGestureRecognizer()
        ..onTap = () => TexteRiche.ouvrir(uri);
      _gestes.add(geste);
      morceaux.add(
        TextSpan(
          text: affiche,
          recognizer: geste,
          mouseCursor: SystemMouseCursors.click,
          semanticsLabel: 'Lien : $affiche',
          style: TextStyle(
            color: CouleursJarvis.signal,
            decoration: TextDecoration.underline,
            decorationColor: CouleursJarvis.signal.withValues(alpha: 0.5),
          ),
        ),
      );
      debut = fin;
    }
    if (debut < t.length) morceaux.add(TextSpan(text: t.substring(debut)));
    return morceaux;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.texte.contains('http')) {
      return Text(widget.texte, style: widget.style);
    }
    return Text.rich(TextSpan(children: _morceaux()), style: widget.style);
  }
}
