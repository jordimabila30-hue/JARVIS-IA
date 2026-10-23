import 'package:flutter/material.dart';

import '../../models/voice_state.dart';
import '../../services/apprentissage/dialogue_situation.dart';
import '../../services/apprentissage/espace_apprentissage.dart';
import '../../theme/theme_jarvis.dart';
import '../../widgets/apprentissage/elements_apprentissage.dart';
import '../../widgets/apprentissage/tuteur_kelasi.dart';

/// Ouvre l'oral d'une situation (le dialogue écrit est gardé).
Future<void> ouvrirOral(
  BuildContext context,
  EspaceApprentissage espace,
  DialogueSituation dialogue,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => OralPage(espace: espace, dialogue: dialogue),
  ),
);

/// Entraînement oral : JARVIS joue un rôle, avec la voix et le micro de
/// JARVIS (même session que le chat vocal). Transcription visible, réponse
/// écrite aussi, arrêt de la parole en un toucher, micro coupé pendant la
/// saisie, bilan à la fin. Rien n'est ajouté à l'historique du chat.
class OralPage extends StatefulWidget {
  const OralPage({super.key, required this.espace, required this.dialogue});

  final EspaceApprentissage espace;
  final DialogueSituation dialogue;

  @override
  State<OralPage> createState() => _OralPageState();
}

class _OralPageState extends State<OralPage> {
  late final _oral = OralSituation(widget.espace.voix!, widget.dialogue);
  final _saisie = TextEditingController();
  final _focus = FocusNode();
  final _defilement = ScrollController();

  @override
  void initState() {
    super.initState();
    // Saisie écrite : le micro ne reste pas ouvert pendant qu'on tape.
    _focus.addListener(() {
      if (_focus.hasFocus && widget.espace.voix!.actif) _oral.pause();
    });
    widget.dialogue.addListener(_enBas);
    WidgetsBinding.instance.addPostFrameCallback((_) => _oral.ouvrir());
  }

  @override
  void dispose() {
    widget.dialogue.removeListener(_enBas);
    _oral.fermer();
    _saisie.dispose();
    _focus.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _enBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.jumpTo(_defilement.position.maxScrollExtent);
      }
    });
  }

  Future<void> _envoyerEcrit() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty) return;
    _saisie.clear();
    final reponse = await widget.dialogue.repondre(texte);
    // Réponse écrite : dite aussi (voix seule, micro fermé).
    if (reponse != null && mounted && !widget.espace.voix!.actif) {
      await widget.espace.voix!.lireReponse(reponse);
    }
  }

  Future<void> _terminer() async {
    await _oral.fermer();
    if (!mounted) return;
    final session = widget.espace.session();
    await afficherTuteur(
      context,
      session: session,
      demande: widget.dialogue.demandeBilan(),
      titre: 'Bilan',
    );
    session.dispose();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final voix = widget.espace.voix!;
    final d = widget.dialogue;
    final p = PaletteJarvis.of(context);
    return PageApprentissage(
      enTete: EnTeteApprentissage(
        titre: 'À l’oral',
        iconeRetour: Icons.close_rounded,
        libelleRetour: 'Quitter l’oral',
        actions: [
          ListenableBuilder(
            listenable: d,
            builder: (context, _) => TextButton(
              key: const ValueKey('oral-terminer'),
              onPressed: d.bilanPossible ? _terminer : null,
              child: const Text('Terminer'),
            ),
          ),
        ],
      ),
      corps: ListenableBuilder(
        listenable: Listenable.merge([voix, d]),
        builder: (context, _) {
          final ecoute = voix.actif && voix.etat == VoiceState.listening;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'JARVIS joue : ${d.situation.role}',
                  style: styleDiscret(context, taille: 13),
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('oral-fil'),
                  controller: _defilement,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    for (final r in d.repliques)
                      _Bulle(texte: r.texte, deJarvis: r.deJarvis),
                    if (d.attente && d.enCours.isNotEmpty)
                      _Bulle(texte: d.enCours, deJarvis: true),
                    if (ecoute && voix.transcription.isNotEmpty)
                      _Bulle(texte: voix.transcription, deJarvis: false, provisoire: true),
                  ],
                ),
              ),
              if (d.erreur != null || voix.probleme != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    voix.probleme?.message ?? d.erreur!,
                    key: const ValueKey('oral-erreur'),
                    style: TextStyle(color: CouleursJarvis.lisible(p.erreur)),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        voix.statut.isEmpty ? ' ' : voix.statut,
                        key: const ValueKey('oral-statut'),
                        style: styleDiscret(context, taille: 12.5),
                      ),
                      const SizedBox(height: 6),
                      if (voix.phraseEnAttente != null)
                        Row(
                          children: [
                            Expanded(
                              child: BoutonApprentissage(
                                libelle: 'Ignorer',
                                secondaire: true,
                                surAppui: voix.ignorerPhrase,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: BoutonApprentissage(
                                libelle: 'Envoyer',
                                surAppui: voix.envoyerPhrase,
                              ),
                            ),
                          ],
                        )
                      else
                        _Commande(
                          parle: voix.parle,
                          actif: voix.actif,
                          surArreterParole: voix.arreterParole,
                          surPause: _oral.pause,
                          surParler: () {
                            _focus.unfocus();
                            _oral.ouvert ? _oral.reprendre() : _oral.ouvrir();
                          },
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('oral-saisie'),
                              controller: _saisie,
                              focusNode: _focus,
                              maxLength: 1000,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _envoyerEcrit(),
                              decoration: const InputDecoration(
                                hintText: 'Ou écrivez votre réponse…',
                                counterText: '',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('oral-envoyer'),
                            tooltip: 'Envoyer',
                            onPressed: d.attente ? null : _envoyerEcrit,
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Une commande principale à la fois : arrêter la parole, couper le
/// micro, ou parler.
class _Commande extends StatelessWidget {
  const _Commande({
    required this.parle,
    required this.actif,
    required this.surArreterParole,
    required this.surPause,
    required this.surParler,
  });

  final bool parle;
  final bool actif;
  final VoidCallback surArreterParole;
  final VoidCallback surPause;
  final VoidCallback surParler;

  @override
  Widget build(BuildContext context) {
    if (parle) {
      return BoutonApprentissage(
        key: const ValueKey('oral-arreter-parole'),
        libelle: 'Arrêter la parole',
        icone: Icons.stop_rounded,
        surAppui: surArreterParole,
      );
    }
    if (actif) {
      return BoutonApprentissage(
        key: const ValueKey('oral-pause'),
        libelle: 'Couper le micro',
        icone: Icons.mic_off_rounded,
        secondaire: true,
        surAppui: surPause,
      );
    }
    return BoutonApprentissage(
      key: const ValueKey('oral-parler'),
      libelle: 'Parler',
      icone: Icons.mic_rounded,
      surAppui: surParler,
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.texte, required this.deJarvis, this.provisoire = false});

  final String texte;
  final bool deJarvis;
  final bool provisoire;

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    return Align(
      alignment: deJarvis ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: deJarvis
                ? p.coque
                : Color.alphaBlend(p.signal.withValues(alpha: 0.14), p.coque),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.trait),
          ),
          child: Text(
            texte,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: provisoire ? p.texteSecondaire : p.texte,
              fontStyle: provisoire ? FontStyle.italic : null,
            ),
          ),
        ),
      ),
    );
  }
}
