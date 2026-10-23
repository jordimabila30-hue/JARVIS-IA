import 'package:flutter/material.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/exercice.dart';
import '../../models/apprentissage/progression.dart';
import '../../models/apprentissage/tuteur.dart';
import '../../services/apprentissage/adaptation.dart';
import '../../services/apprentissage/catalogue_apprentissage.dart';
import '../../services/apprentissage/espace_apprentissage.dart';
import '../../services/apprentissage/seance_lecon.dart';
import '../../services/apprentissage/selection_exercices.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/chrono_perf.dart';
import '../../widgets/apprentissage/elements_apprentissage.dart';
import '../../widgets/apprentissage/exercices/vue_exercice.dart';
import '../../widgets/apprentissage/fiche_et_correction.dart';
import '../../widgets/apprentissage/resultat_seance.dart';
import '../../widgets/apprentissage/tuteur_kelasi.dart';

/// Ouvre une leçon : reprise de la séance en cours s'il y en a une, sinon
/// début (introduction puis exercices). [recommencer] repart de zéro.
Future<void> ouvrirLecon(
  BuildContext context,
  EspaceApprentissage espace,
  ParcoursCharge parcours,
  Lecon lecon, {
  bool recommencer = false,
  bool consultation = false,
  bool remplacer = false,
}) {
  // Progression notée avant l'ouverture (jamais pendant la construction
  // de la nouvelle page : les pages ouvertes en dessous l'écoutent).
  final progression = espace.progression;
  if (recommencer) progression.oublierSeance(lecon.id);
  progression.ouvrirLecon(parcours.resume.id, lecon.id);
  final route = MaterialPageRoute<void>(
    builder: (_) => LeconPage(
      espace: espace,
      parcours: parcours,
      lecon: lecon,
      consultation: consultation,
    ),
  );
  final nav = Navigator.of(context);
  return remplacer ? nav.pushReplacement(route) : nav.push(route);
}

/// Séance libre (Pratiquer, Réviser) : exercices sans introduction.
Future<void> ouvrirEntrainement(
  BuildContext context,
  EspaceApprentissage espace, {
  required String titre,
  required List<ExerciceSitue> exercices,
  bool remplacer = false,
  String? titreResultat,
  String? Function(BilanSeance)? surBilan,
}) {
  final route = MaterialPageRoute<void>(
    builder: (_) => LeconPage.libre(
      espace: espace,
      titre: titre,
      exercices: exercices,
      titreResultat: titreResultat,
      surBilan: surBilan,
    ),
  );
  final nav = Navigator.of(context);
  return remplacer ? nav.pushReplacement(route) : nav.push(route);
}

/// Une leçon (introduction, exercices, résultat), sa consultation, ou une
/// séance libre. Toute la logique est dans [SeanceLecon] ; la page
/// l'affiche et relaie vers la progression (écritures regroupées, forcées
/// en quittant).
class LeconPage extends StatefulWidget {
  const LeconPage({
    super.key,
    required this.espace,
    required ParcoursCharge this.parcours,
    required Lecon this.lecon,
    this.consultation = false,
  }) : titre = null,
       titreResultat = null,
       surBilan = null,
       exercices = null;

  const LeconPage.libre({
    super.key,
    required this.espace,
    required String this.titre,
    required List<ExerciceSitue> this.exercices,
    this.titreResultat,
    this.surBilan,
  }) : parcours = null,
       lecon = null,
       consultation = false;

  final EspaceApprentissage espace;
  final ParcoursCharge? parcours;
  final Lecon? lecon;

  /// Relire une leçon (fiches seulement), sans séance.
  final bool consultation;

  /// Séance libre.
  final String? titre;
  final List<ExerciceSitue>? exercices;

  /// Séance libre : titre du résultat (« Séance terminée » sinon) et rappel
  /// de fin, qui peut rendre un message affiché sous le titre (niveau…).
  final String? titreResultat;
  final String? Function(BilanSeance)? surBilan;

  @override
  State<LeconPage> createState() => _LeconPageState();
}

class _LeconPageState extends State<LeconPage> {
  late final _progression = widget.espace.progression;
  late final _catalogue = widget.espace.catalogue;
  final _defilement = ScrollController();
  SeanceLecon? _seance;

  /// Exercice → leçon (séance libre).
  late final Map<String, String> _leconDe = {
    for (final e in widget.exercices ?? const <ExerciceSitue>[])
      e.exercice.id: e.lecon,
  };

  bool get _libre => widget.lecon == null;

  @override
  void initState() {
    super.initState();
    if (ChronoPerf.actif) {
      final debut = ChronoPerf.debut();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ChronoPerf.fin('lecon.affiche', debut),
      );
    }
    final lecon = widget.lecon;
    if (lecon != null) {
      if (widget.consultation) return;
      _seance = SeanceLecon(
        exercices: lecon.exercices,
        reprise: _progression.etat(lecon.id)?.seance,
        surSeance: (s) => _progression.enregistrerSeance(lecon.id, s),
        surReponse: (ex, juste) => _progression.noterExercice(
          lecon.id,
          ex.id,
          juste: juste,
          fiche: ex.fiche,
        ),
        surFin: (b) => _terminer(lecon, b),
      );
    } else {
      _seance = SeanceLecon(
        exercices: [for (final e in widget.exercices!) e.exercice],
        introduction: false,
        surReponse: (ex, juste) => _progression.noterExercice(
          _leconDe[ex.id]!,
          ex.id,
          juste: juste,
          fiche: ex.fiche,
        ),
        surFin: (b) {
          _messageResultat = widget.surBilan?.call(b);
          _progression.enregistrerMaintenant();
        },
      );
    }
    _seance!.addListener(_surSeance);
  }

  /// Niveau du parcours de l'exercice / de la fiche (pour le tuteur).
  String? _niveau(String fiche) {
    for (final p in _catalogue.parcours ?? const <ParcoursCharge>[]) {
      if (p.contenu?.fiches.containsKey(fiche) == true) {
        return _progression.niveau(p.resume.id)?.name;
      }
    }
    return null;
  }

  /// Professeur IA (backend unifié) pour la fiche [fiche].
  Future<void> _tuteur(
    ActionTuteur action,
    String fiche, {
    Correction? correction,
  }) {
    final session = widget.espace.session();
    return afficherTuteur(
      context,
      session: session,
      titre: action.libelle,
      demande: DemandeTuteur(
        action: action,
        fiches: [fiche],
        exercice: correction?.exercice.id,
        reponse: correction == null
            ? null
            : texteReponse(correction.exercice, correction.reponse),
        niveau: _niveau(fiche),
        versionCorpus: _catalogue.versionCorpus,
      ),
    ).whenComplete(session.dispose);
  }

  /// M'entraîner : d'abord d'autres exercices LOCAUX de la même notion
  /// (hors ligne, sans IA), ordonnés selon le niveau ; sinon un exercice
  /// proposé par le professeur IA.
  Future<void> _entrainer(String fiche, {String? sauf}) {
    final locaux = <ExerciceSitue>[
      for (final p in _catalogue.parcours ?? const <ParcoursCharge>[])
        for (final l in p.leconsVisibles(apercu: _catalogue.apercu.value))
          for (final e in l.exercices)
            if (e.fiche == fiche && e.id != sauf) ExerciceSitue(e, l.id),
    ];
    if (locaux.isEmpty) return _tuteur(ActionTuteur.entrainer, fiche);
    return ouvrirEntrainement(
      context,
      widget.espace,
      titre: ActionTuteur.entrainer.libelle,
      exercices: AdaptationKelasi.ordonner(
        locaux,
        exercice: (e) => e.exercice,
        maitrise: (f) => _progression.maitriseDe(f) ?? 0.5,
        niveau: _niveau(fiche) == null
            ? null
            : NiveauApprenant.depuis(_niveau(fiche)),
      ).take(4).toList(),
    );
  }

  /// Message sous le titre du résultat (séance libre : niveau estimé…).
  String? _messageResultat;

  /// Fin de leçon : enregistrée, puis niveau du parcours ajusté d'après
  /// les premiers essais et la maîtrise des notions de la leçon.
  Future<void> _terminer(Lecon lecon, BilanSeance b) async {
    await _progression.terminerLecon(
      lecon.id,
      justes: b.justes,
      total: b.total,
    );
    final parcours = widget.parcours!.resume.id;
    final avant = _progression.niveau(parcours);
    final apres = AdaptationKelasi.ajuster(
      avant,
      justes: b.justes,
      total: b.total,
      maitrises: [for (final f in lecon.fiches) ?_progression.maitriseDe(f)],
    );
    if (apres != avant) {
      await _progression.fixerNiveau(parcours, apres);
      if (mounted) {
        setState(() => _messageResultat = 'Niveau ajusté : ${apres.libelle}');
      }
    }
  }

  @override
  void dispose() {
    _seance?.removeListener(_surSeance);
    _seance?.dispose();
    _defilement.dispose();
    // Quitter en cours de route : rien n'est perdu.
    _progression.enregistrerMaintenant();
    super.dispose();
  }

  Correction? _derniere;

  void _surSeance() {
    final c = _seance!.correction;
    final nouvelle = c != null && !identical(c, _derniere);
    _derniere = c;
    setState(() {});
    if (nouvelle) {
      // La correction apparaît sous l'exercice : on la montre.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_defilement.hasClients) return;
        _defilement.animateTo(
          _defilement.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    } else if (c == null && _defilement.hasClients) {
      _defilement.jumpTo(0);
    }
  }

  FichePedagogique? _fiche(Exercice ex) {
    final parcours =
        widget.parcours ?? _catalogue.lecon(_leconDe[ex.id] ?? '')?.$1;
    return parcours?.contenu?.fiches[ex.fiche];
  }

  Map<String, String> get _titresFiches => {
    for (final p in _catalogue.parcours ?? const <ParcoursCharge>[])
      for (final f in p.contenu?.fiches.values ?? const <FichePedagogique>[])
        f.id: f.titre,
  };

  @override
  Widget build(BuildContext context) {
    final seance = _seance;
    final phase = seance?.phase ?? PhaseSeance.introduction;
    final titre = widget.lecon?.titre ?? widget.titre!;
    return PageApprentissage(
      enTete: phase == PhaseSeance.exercice
          ? _BarreSeance(seance: seance!)
          : EnTeteApprentissage(
              titre: titre,
              iconeRetour: Icons.close_rounded,
              libelleRetour: 'Fermer',
            ),
      corps: LayoutBuilder(
        builder: (context, c) {
          final marge = margeApprentissage(c.maxWidth);
          final contenu = switch (phase) {
            PhaseSeance.introduction => _Introduction(
              lecon: widget.lecon!,
              parcours: widget.parcours!,
              consultation: widget.consultation,
              actionsFiche: (f) => ActionsTuteur(
                surSimplifier: () => _tuteur(ActionTuteur.simplifier, f.id),
                surExemple: () => _tuteur(ActionTuteur.exemple, f.id),
                surEntrainer: () => _entrainer(f.id),
              ),
              surCommencer: widget.consultation
                  ? () => ouvrirLecon(
                      context,
                      widget.espace,
                      widget.parcours!,
                      widget.lecon!,
                      recommencer: true,
                      remplacer: true,
                    )
                  : seance!.commencer,
            ),
            PhaseSeance.exercice => _Exercice(
              key: ValueKey('${seance!.position}-${seance.tentative}'),
              seance: seance,
              fiche: _fiche(seance.exerciceCourant!),
              lecteur: widget.espace.lecteur,
              actions: (c) => ActionsTuteur(
                surSimplifier: () =>
                    _tuteur(ActionTuteur.simplifier, c.exercice.fiche),
                surExemple: () =>
                    _tuteur(ActionTuteur.exemple, c.exercice.fiche),
                surErreur: c.juste
                    ? null
                    : () => _tuteur(
                        ActionTuteur.erreur,
                        c.exercice.fiche,
                        correction: c,
                      ),
                surEntrainer: () =>
                    _entrainer(c.exercice.fiche, sauf: c.exercice.id),
              ),
            ),
            PhaseSeance.resultat => ResultatSeance(
              titre: _libre
                  ? (widget.titreResultat ?? 'Séance terminée')
                  : 'Leçon terminée',
              message: _messageResultat,
              bilan: seance!.bilan!,
              titresFiches: _titresFiches,
              surContinuer: () => Navigator.of(context).maybePop(),
              surReviser: seance.bilan!.rates.isEmpty
                  ? null
                  : () => ouvrirEntrainement(
                      context,
                      widget.espace,
                      titre: 'Réviser',
                      remplacer: true,
                      exercices: [
                        for (final ex in seance.bilan!.rates)
                          ExerciceSitue(
                            ex,
                            widget.lecon?.id ?? _leconDe[ex.id]!,
                          ),
                      ],
                    ),
            ),
          };
          return SingleChildScrollView(
            controller: _defilement,
            padding: EdgeInsets.fromLTRB(marge, 8, marge, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  child: KeyedSubtree(
                    key: ValueKey(
                      phase == PhaseSeance.exercice
                          ? 'ex-${seance!.position}'
                          : phase.name,
                    ),
                    child: contenu,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Barre pendant les exercices : quitter, avancement, compteur.
class _BarreSeance extends StatelessWidget {
  const _BarreSeance({required this.seance});

  final SeanceLecon seance;

  @override
  Widget build(BuildContext context) {
    final fait = seance.position + (seance.correction == null ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Quitter (progression gardée)',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
            color: PaletteJarvis.of(context).texte,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: BarreProgression(valeur: seance.avancement, hauteur: 8),
          ),
          const SizedBox(width: 12),
          Text('$fait / ${seance.longueur}', style: styleDiscret(context)),
        ],
      ),
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction({
    required this.lecon,
    required this.parcours,
    required this.surCommencer,
    required this.consultation,
    this.actionsFiche,
  });

  final Lecon lecon;
  final ParcoursCharge parcours;
  final VoidCallback surCommencer;
  final bool consultation;

  /// Actions du professeur IA sous chaque fiche.
  final Widget Function(FichePedagogique fiche)? actionsFiche;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final fiches = [
      for (final id in lecon.fiches) ?parcours.contenu?.fiches[id],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceApprentissage(
          accent: true,
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: p.signal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lecon.objectif,
                      style: styleTitre(context, taille: 15.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '≈ ${lecon.dureeMinutes} min · ${lecon.exercices.length} exercices',
                      style: styleDiscret(context, taille: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final f in fiches) ...[
          const SizedBox(height: 12),
          SurfaceApprentissage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!f.validee)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: EtiquetteBrouillon(),
                    ),
                  ),
                ContenuFiche(fiche: f),
                if (actionsFiche != null) ...[
                  const SizedBox(height: 10),
                  actionsFiche!(f),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => afficherFiche(context, f),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(
                      f.sources.length > 1
                          ? '${f.sources.length} sources'
                          : 'Source',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        BoutonApprentissage(
          key: const ValueKey('commencer'),
          libelle: consultation ? 'Refaire la leçon' : 'Commencer',
          icone: consultation ? Icons.replay_rounded : Icons.play_arrow_rounded,
          surAppui: surCommencer,
        ),
      ],
    );
  }
}

class _Exercice extends StatelessWidget {
  const _Exercice({
    super.key,
    required this.seance,
    required this.fiche,
    this.lecteur,
    this.actions,
  });

  final SeanceLecon seance;
  final FichePedagogique? fiche;
  final LecteurEcoute? lecteur;

  /// Actions du professeur IA sous la correction.
  final Widget Function(Correction correction)? actions;

  @override
  Widget build(BuildContext context) {
    final correction = seance.correction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seance.estUnRetour)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: PaletteJarvis.of(context).texteSecondaire,
                ),
                const SizedBox(width: 6),
                Text(
                  'On le retravaille',
                  style: styleDiscret(context, taille: 12.5),
                ),
              ],
            ),
          ),
        VueExercice(
          exercice: seance.exerciceCourant!,
          correction: correction,
          surReponse: seance.repondre,
          lecteur: lecteur,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: correction == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: PanneauCorrection(
                    correction: correction,
                    fiche: fiche,
                    actions: actions?.call(correction),
                    surContinuer: seance.continuer,
                    surReessayer: seance.reessayer,
                  ),
                ),
        ),
      ],
    );
  }
}
