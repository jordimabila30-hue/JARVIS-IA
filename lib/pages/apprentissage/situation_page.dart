import 'package:flutter/material.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/tuteur.dart';
import '../../services/apprentissage/dialogue_situation.dart';
import '../../services/apprentissage/espace_apprentissage.dart';
import '../../services/apprentissage/session_tuteur.dart';
import '../../theme/theme_jarvis.dart';
import '../../widgets/apprentissage/elements_apprentissage.dart';
import '../../widgets/apprentissage/tuteur_kelasi.dart';
import 'oral_page.dart';

/// Ouvre une situation du quotidien.
Future<void> ouvrirSituation(
  BuildContext context,
  EspaceApprentissage espace,
  SituationPratique situation,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SituationPage(espace: espace, situation: situation),
  ),
);

/// Situation du quotidien : objectif, pratique écrite corrigée par le
/// professeur IA, nouvelle tentative, et l'oral (dialogue de rôle) qui
/// partage le même historique.
class SituationPage extends StatefulWidget {
  const SituationPage({super.key, required this.espace, required this.situation});

  final EspaceApprentissage espace;
  final SituationPratique situation;

  @override
  State<SituationPage> createState() => _SituationPageState();
}

class _SituationPageState extends State<SituationPage> {
  final _saisie = TextEditingController();
  late final SessionTuteur _correction = widget.espace.session();
  late final DialogueSituation _dialogue = DialogueSituation(
    situation: widget.situation,
    appel: widget.espace.tuteur,
    niveau: _niveau,
    versionCorpus: widget.espace.catalogue.versionCorpus,
  );
  bool _corrigee = false;

  String? get _niveau {
    final fiche = widget.situation.fiches.first;
    for (final p in widget.espace.catalogue.parcours ?? const []) {
      if (p.contenu?.fiches.containsKey(fiche) == true) {
        return widget.espace.progression.niveau(p.resume.id)?.name;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _saisie.dispose();
    _correction.dispose();
    _dialogue.dispose();
    super.dispose();
  }

  void _corriger() {
    final texte = _saisie.text.trim();
    if (texte.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _corrigee = true);
    _correction.demander(
      DemandeTuteur(
        action: ActionTuteur.situation,
        situation: widget.situation.id,
        texte: texte,
        niveau: _niveau,
        versionCorpus: widget.espace.catalogue.versionCorpus,
      ),
    );
  }

  void _nouvelleTentative() {
    _correction.annuler();
    setState(() => _corrigee = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.situation;
    final p = PaletteJarvis.of(context);
    final empechement = OralSituation.empechement(widget.espace.voix, _dialogue);
    return PageApprentissage(
      enTete: EnTeteApprentissage(titre: s.titre),
      corps: LayoutBuilder(
        builder: (context, c) {
          final marge = margeApprentissage(c.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(marge, 8, marge, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceApprentissage(
                      accent: true,
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, color: p.signal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(s.objectif, style: styleTitre(context, taille: 15)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(s.consigne, style: styleDiscret(context, taille: 14.5)),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('situation-saisie'),
                      controller: _saisie,
                      minLines: 4,
                      maxLines: 10,
                      maxLength: 2000,
                      enabled: !_corrigee,
                      decoration: const InputDecoration(
                        hintText: 'Votre réponse…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_corrigee)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _saisie,
                        builder: (context, v, _) => BoutonApprentissage(
                          key: const ValueKey('situation-corriger'),
                          libelle: 'Corriger',
                          icone: Icons.spellcheck_rounded,
                          surAppui: v.text.trim().isEmpty ? null : _corriger,
                        ),
                      )
                    else ...[
                      SurfaceApprentissage(child: VueTuteur(session: _correction)),
                      const SizedBox(height: 12),
                      BoutonApprentissage(
                        key: const ValueKey('situation-nouvelle'),
                        libelle: 'Nouvelle tentative',
                        icone: Icons.replay_rounded,
                        secondaire: true,
                        surAppui: _nouvelleTentative,
                      ),
                    ],
                    const SizedBox(height: 22),
                    BoutonApprentissage(
                      key: const ValueKey('situation-oral'),
                      libelle: 'S’entraîner à l’oral',
                      icone: Icons.mic_none_rounded,
                      secondaire: true,
                      surAppui: empechement != null
                          ? null
                          : () => ouvrirOral(context, widget.espace, _dialogue),
                    ),
                    if (empechement != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          empechement.message,
                          key: const ValueKey('situation-oral-raison'),
                          textAlign: TextAlign.center,
                          style: styleDiscret(context, taille: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
