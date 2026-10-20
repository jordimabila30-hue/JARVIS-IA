import 'package:flutter/material.dart';

import '../../../models/apprentissage/exercice.dart';
import '../../../services/apprentissage/espace_apprentissage.dart';
import '../../../services/apprentissage/seance_lecon.dart';
import '../../../theme/theme_jarvis.dart';
import '../elements_apprentissage.dart';

/// Affiche un exercice, quel que soit son type, et rend la réponse par
/// [surReponse]. Après correction ([correction] non nulle), l'exercice
/// est figé et montre ce qui était juste. Un nouvel essai recrée le
/// widget (clé avec la tentative).
class VueExercice extends StatelessWidget {
  const VueExercice({
    super.key,
    required this.exercice,
    required this.correction,
    required this.surReponse,
    this.lecteur,
  });

  final Exercice exercice;
  final Correction? correction;
  final ValueChanged<ReponseExercice> surReponse;
  final LecteurEcoute? lecteur;

  @override
  Widget build(BuildContext context) {
    final e = exercice;
    final r = correction?.reponse;
    final corps = switch (e) {
      ExerciceChoix() => _Choix(
        exercice: e,
        reponse: r,
        surReponse: surReponse,
        lecteur: lecteur,
      ),
      ExerciceVraiFaux() => _VraiFaux(
        exercice: e,
        reponse: r,
        surReponse: surReponse,
      ),
      ExerciceTrous() => _Trous(
        exercice: e,
        reponse: r,
        surReponse: surReponse,
      ),
      ExerciceOrdre() => _Ordre(
        exercice: e,
        reponse: r,
        surReponse: surReponse,
      ),
      ExerciceAssociation() => _Association(
        exercice: e,
        reponse: r,
        surReponse: surReponse,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          e.consigne,
          style: styleTitre(context, taille: 18).copyWith(height: 1.3),
        ),
        const SizedBox(height: 18),
        corps,
      ],
    );
  }
}

/// État visuel d'un élément de réponse.
enum _Marque { neutre, choisi, juste, faux }

/// Élément touchable (option, mot, carte) aux couleurs de la palette.
class _Tuile extends StatelessWidget {
  const _Tuile({
    super.key,
    required this.texte,
    this.marque = _Marque.neutre,
    this.surAppui,
    this.prefixe,
    this.compacte = false,
  });

  final String texte;
  final _Marque marque;
  final VoidCallback? surAppui;
  final Widget? prefixe;
  final bool compacte;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final succes = CouleursJarvis.lisible(p.succes);
    final erreur = CouleursJarvis.lisible(p.erreur);
    final (Color bord, Color fond) = switch (marque) {
      _Marque.neutre => (p.trait, p.coque.withValues(alpha: 0.9)),
      _Marque.choisi => (
        p.signal,
        Color.alphaBlend(p.signal.withValues(alpha: 0.12), p.coque),
      ),
      _Marque.juste => (
        succes,
        Color.alphaBlend(succes.withValues(alpha: 0.14), p.coque),
      ),
      _Marque.faux => (
        erreur,
        Color.alphaBlend(erreur.withValues(alpha: 0.12), p.coque),
      ),
    };
    final icone = switch (marque) {
      _Marque.juste => Icon(Icons.check_rounded, size: 18, color: succes),
      _Marque.faux => Icon(Icons.close_rounded, size: 18, color: erreur),
      _ => null,
    };
    final forme = BorderRadius.circular(compacte ? 12 : 14);
    return Semantics(
      button: surAppui != null,
      selected: marque == _Marque.choisi,
      child: Material(
        color: fond,
        shape: RoundedRectangleBorder(
          borderRadius: forme,
          side: BorderSide(
            color: bord,
            width: marque == _Marque.neutre ? 1 : 1.6,
          ),
        ),
        child: InkWell(
          onTap: surAppui,
          borderRadius: forme,
          child: Padding(
            padding: compacte
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: compacte ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (prefixe != null) ...[prefixe!, const SizedBox(width: 10)],
                Flexible(
                  fit: compacte ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    texte,
                    style: TextStyle(
                      fontSize: compacte ? 14 : 15,
                      height: 1.35,
                      color: p.texte,
                    ),
                  ),
                ),
                if (icone != null) ...[const SizedBox(width: 8), icone],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille numérotée (ordre, association).
class _Numero extends StatelessWidget {
  const _Numero(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: 24,
        child: Center(
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.surSignal,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _bouton(String libelle, VoidCallback? surAppui) => Padding(
  padding: const EdgeInsets.only(top: 20),
  child: BoutonApprentissage(libelle: libelle, surAppui: surAppui),
);

// --- Choix multiple, meilleur message, écoute --------------------------------

class _Choix extends StatelessWidget {
  const _Choix({
    required this.exercice,
    required this.reponse,
    required this.surReponse,
    this.lecteur,
  });

  final ExerciceChoix exercice;
  final ReponseExercice? reponse;
  final ValueChanged<ReponseExercice> surReponse;
  final LecteurEcoute? lecteur;

  @override
  Widget build(BuildContext context) {
    final e = exercice;
    final choisi = reponse is ReponseChoix
        ? (reponse as ReponseChoix).index
        : null;
    final corrige = reponse != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.audio != null) ...[
          _Ecoute(texte: e.audio!, lecteur: lecteur),
          const SizedBox(height: 16),
        ],
        if (e.contexte != null) ...[
          SurfaceApprentissage(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: PaletteJarvis.of(context).texteSecondaire,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.contexte!,
                    style: styleDiscret(
                      context,
                      taille: 14.5,
                    ).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        for (var i = 0; i < e.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _Tuile(
            key: ValueKey('option-$i'),
            texte: e.options[i],
            marque: !corrige
                ? _Marque.neutre
                : i == e.bonne
                ? _Marque.juste
                : i == choisi
                ? _Marque.faux
                : _Marque.neutre,
            surAppui: corrige ? null : () => surReponse(ReponseChoix(i)),
          ),
        ],
      ],
    );
  }
}

/// Lecture du texte d'écoute ; le texte reste toujours accessible.
class _Ecoute extends StatefulWidget {
  const _Ecoute({required this.texte, this.lecteur});

  final String texte;
  final LecteurEcoute? lecteur;

  @override
  State<_Ecoute> createState() => _EcouteState();
}

class _EcouteState extends State<_Ecoute> {
  bool _lecture = false;
  late bool _texteVisible = !_vocalPossible;
  late String? _note = _vocalPossibleInitial
      ? null
      : 'Lecture vocale indisponible : lisez le texte.';

  bool get _vocalPossible => widget.lecteur?.disponible ?? false;
  late final bool _vocalPossibleInitial = _vocalPossible;

  Future<void> _lire() async {
    final lecteur = widget.lecteur;
    if (lecteur == null || _lecture) return;
    setState(() => _lecture = true);
    final ok = await lecteur.lire(widget.texte);
    if (!mounted) return;
    setState(() {
      _lecture = false;
      if (!ok) {
        _texteVisible = true;
        _note = 'La voix n’a pas pu lire le texte : le voici.';
      }
    });
  }

  @override
  void dispose() {
    if (_lecture) widget.lecteur?.arreter();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    return SurfaceApprentissage(
      accent: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_vocalPossibleInitial)
                IconButton.filled(
                  key: const ValueKey('ecouter'),
                  tooltip: 'Écouter',
                  onPressed: _lecture ? widget.lecteur?.arreter : _lire,
                  style: IconButton.styleFrom(
                    backgroundColor: p.signal,
                    foregroundColor: p.surSignal,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: Icon(
                    _lecture ? Icons.stop_rounded : Icons.volume_up_rounded,
                  ),
                )
              else
                Icon(Icons.volume_off_rounded, color: p.texteSecondaire),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _vocalPossibleInitial
                      ? (_lecture ? 'Lecture…' : 'Écouter le message')
                      : 'Message à lire',
                  style: styleTitre(context, taille: 14.5),
                ),
              ),
              if (!_texteVisible)
                TextButton(
                  onPressed: () => setState(() => _texteVisible = true),
                  child: const Text('Voir le texte'),
                ),
            ],
          ),
          if (_texteVisible) ...[
            const SizedBox(height: 10),
            Text(
              '« ${widget.texte} »',
              style: TextStyle(fontSize: 15, height: 1.4, color: p.texte),
            ),
          ],
          if (_note != null) ...[
            const SizedBox(height: 6),
            Text(_note!, style: styleDiscret(context, taille: 12)),
          ],
        ],
      ),
    );
  }
}

// --- Vrai ou faux ------------------------------------------------------------

class _VraiFaux extends StatelessWidget {
  const _VraiFaux({
    required this.exercice,
    required this.reponse,
    required this.surReponse,
  });

  final ExerciceVraiFaux exercice;
  final ReponseExercice? reponse;
  final ValueChanged<ReponseExercice> surReponse;

  @override
  Widget build(BuildContext context) {
    final choisi = reponse is ReponseVraiFaux
        ? (reponse as ReponseVraiFaux).valeur
        : null;
    final corrige = reponse != null;
    _Marque marque(bool v) => !corrige
        ? _Marque.neutre
        : v == exercice.reponse
        ? _Marque.juste
        : v == choisi
        ? _Marque.faux
        : _Marque.neutre;
    Widget bouton(bool v) => Expanded(
      child: _Tuile(
        key: ValueKey(v ? 'vrai' : 'faux'),
        texte: v ? 'Vrai' : 'Faux',
        prefixe: Icon(
          v ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
          size: 20,
          color: PaletteJarvis.of(context).texteSecondaire,
        ),
        marque: marque(v),
        surAppui: corrige ? null : () => surReponse(ReponseVraiFaux(v)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceApprentissage(
          accent: true,
          child: Text(
            exercice.affirmation,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              color: PaletteJarvis.of(context).texte,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [bouton(true), const SizedBox(width: 12), bouton(false)]),
      ],
    );
  }
}

// --- Texte à compléter -------------------------------------------------------

class _Trous extends StatefulWidget {
  const _Trous({
    required this.exercice,
    required this.reponse,
    required this.surReponse,
  });

  final ExerciceTrous exercice;
  final ReponseExercice? reponse;
  final ValueChanged<ReponseExercice> surReponse;

  @override
  State<_Trous> createState() => _TrousState();
}

/// Mots d'un morceau de texte ; la ponctuation haute française (« ? »,
/// « ! », « : », « ; », « » ») reste collée au mot qui la précède
/// (espace insécable) : jamais seule en début de ligne.
List<String> _mots(String texte) {
  final mots = <String>[];
  for (final m in texte.split(' ')) {
    if (m.isEmpty) continue;
    if (mots.isNotEmpty && RegExp(r'^[?!:;»]+$').hasMatch(m)) {
      mots.last = '${mots.last} $m';
    } else {
      mots.add(m);
    }
  }
  return mots;
}

class _TrousState extends State<_Trous> {
  late final List<int?> _choix = List.filled(
    widget.exercice.trous.length,
    null,
  );
  int _actif = 0;

  bool get _corrige => widget.reponse != null;

  void _choisir(int option) {
    setState(() {
      _choix[_actif] = option;
      final vide = _choix.indexWhere((c) => c == null);
      if (vide >= 0) _actif = vide;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final e = widget.exercice;
    final morceaux = e.morceaux;
    final style = TextStyle(fontSize: 16.5, height: 1.5, color: p.texte);
    final elements = <Widget>[];
    for (var i = 0; i < morceaux.length; i++) {
      for (final mot in _mots(morceaux[i])) {
        elements.add(Text(mot, style: style));
      }
      if (i < e.trous.length) {
        final c = _choix[i];
        final juste = c == e.trous[i].bonne;
        elements.add(
          _Tuile(
            key: ValueKey('trou-$i'),
            compacte: true,
            texte: c == null ? '        ' : e.trous[i].options[c],
            marque: _corrige
                ? (juste ? _Marque.juste : _Marque.faux)
                : i == _actif
                ? _Marque.choisi
                : _Marque.neutre,
            surAppui: _corrige ? null : () => setState(() => _actif = i),
          ),
        );
      }
    }
    final trou = e.trous[_actif];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceApprentissage(
          child: Wrap(
            spacing: 5,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: elements,
          ),
        ),
        if (!_corrige) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var k = 0; k < trou.options.length; k++)
                _Tuile(
                  key: ValueKey('mot-$k'),
                  compacte: true,
                  texte: trou.options[k],
                  marque: _choix[_actif] == k ? _Marque.choisi : _Marque.neutre,
                  surAppui: () => _choisir(k),
                ),
            ],
          ),
          _bouton(
            'Vérifier',
            _choix.contains(null)
                ? null
                : () => widget.surReponse(ReponseTrous(_choix.cast<int>())),
          ),
        ],
      ],
    );
  }
}

// --- Remettre dans l'ordre ---------------------------------------------------

class _Ordre extends StatefulWidget {
  const _Ordre({
    required this.exercice,
    required this.reponse,
    required this.surReponse,
  });

  final ExerciceOrdre exercice;
  final ReponseExercice? reponse;
  final ValueChanged<ReponseExercice> surReponse;

  @override
  State<_Ordre> createState() => _OrdreState();
}

class _OrdreState extends State<_Ordre> {
  final _places = <int>[];

  @override
  Widget build(BuildContext context) {
    final e = widget.exercice;
    final corrige = widget.reponse != null;
    final places = corrige && widget.reponse is ReponseOrdre
        ? (widget.reponse as ReponseOrdre).ordre
        : _places;
    final restants = [
      for (final i in e.melange)
        if (!places.contains(i)) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var n = 0; n < places.length; n++) ...[
          _Tuile(
            key: ValueKey('place-${places[n]}'),
            texte: e.elements[places[n]],
            prefixe: _Numero(n + 1),
            marque: corrige
                ? (places[n] == n ? _Marque.juste : _Marque.faux)
                : _Marque.choisi,
            surAppui: corrige
                ? null
                : () => setState(() => _places.removeAt(n)),
          ),
          const SizedBox(height: 8),
        ],
        if (restants.isNotEmpty) ...[
          if (places.isNotEmpty) const SizedBox(height: 8),
          Text(
            'Touchez les éléments dans l’ordre',
            style: styleDiscret(context, taille: 12.5),
          ),
          const SizedBox(height: 10),
          for (final i in restants) ...[
            _Tuile(
              key: ValueKey('element-$i'),
              texte: e.elements[i],
              surAppui: corrige ? null : () => setState(() => _places.add(i)),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (!corrige)
          _bouton(
            'Vérifier',
            _places.length == e.elements.length
                ? () => widget.surReponse(ReponseOrdre(List.of(_places)))
                : null,
          ),
      ],
    );
  }
}

// --- Associer ----------------------------------------------------------------

class _Association extends StatefulWidget {
  const _Association({
    required this.exercice,
    required this.reponse,
    required this.surReponse,
  });

  final ExerciceAssociation exercice;
  final ReponseExercice? reponse;
  final ValueChanged<ReponseExercice> surReponse;

  @override
  State<_Association> createState() => _AssociationState();
}

class _AssociationState extends State<_Association> {
  final _paires = <int, int>{};
  int? _gauche;

  void _toucherGauche(int g) => setState(() {
    if (_paires.containsKey(g)) {
      _paires.remove(g);
      _gauche = g;
    } else {
      // Toujours sélectionné (le suivant l'est déjà d'office).
      _gauche = g;
    }
  });

  void _toucherDroite(int d) => setState(() {
    final g = _gauche;
    _paires.removeWhere((_, v) => v == d);
    if (g == null) return;
    _paires[g] = d;
    _gauche = null;
    for (var i = 0; i < widget.exercice.paires.length; i++) {
      if (!_paires.containsKey(i)) {
        _gauche = i;
        break;
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final e = widget.exercice;
    final corrige = widget.reponse != null;
    final paires = corrige && widget.reponse is ReponseAssociation
        ? (widget.reponse as ReponseAssociation).paires
        : _paires;
    int? numeroDroite(int d) {
      for (final p in paires.entries) {
        if (p.value == d) return p.key + 1;
      }
      return null;
    }

    final gauche = [
      for (var g = 0; g < e.paires.length; g++)
        _Tuile(
          key: ValueKey('gauche-$g'),
          compacte: true,
          texte: e.paires[g].$1,
          prefixe: paires.containsKey(g) ? _Numero(g + 1) : null,
          marque: corrige
              ? (paires[g] == g ? _Marque.juste : _Marque.faux)
              : _gauche == g
              ? _Marque.choisi
              : _Marque.neutre,
          surAppui: corrige ? null : () => _toucherGauche(g),
        ),
    ];
    final droite = [
      for (final d in e.melangeDroite)
        _Tuile(
          key: ValueKey('droite-$d'),
          compacte: true,
          texte: e.paires[d].$2,
          prefixe: numeroDroite(d) == null ? null : _Numero(numeroDroite(d)!),
          surAppui: corrige ? null : () => _toucherDroite(d),
        ),
    ];
    Widget colonne(List<Widget> t) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < t.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          t[i],
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!corrige)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Touchez à gauche, puis la réponse à droite',
              style: styleDiscret(context, taille: 12.5),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colonne(gauche)),
            const SizedBox(width: 10),
            Expanded(child: colonne(droite)),
          ],
        ),
        if (!corrige)
          _bouton(
            'Vérifier',
            _paires.length == e.paires.length
                ? () => widget.surReponse(ReponseAssociation(Map.of(_paires)))
                : null,
          ),
      ],
    );
  }
}
