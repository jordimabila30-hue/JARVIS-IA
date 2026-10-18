import 'package:flutter/material.dart';

import '../models/voice_state.dart';
import '../services/voice_session.dart';
import '../theme/gabarit_jarvis.dart';
import '../theme/theme_jarvis.dart';

/// Textes du mode vocal sous PIM, du plus discret au plus lisible :
///
/// 1. statut (« Écoute… »), petit, avec un point de couleur ;
/// 2. phrase entendue, en citation secondaire ;
/// 3. réponse de JARVIS, texte principal de la conversation.
///
/// Même la réponse reste mesurée : les particules restent l'élément
/// principal de l'écran. Un problème (micro refusé…) s'affiche comme un
/// libellé court, avec le détail en petit et l'action qui le règle.
class VoiceStatus extends StatelessWidget {
  const VoiceStatus({super.key, required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final g = GabaritJarvis.of(context);
    // Calque propre : les textes ne sont repeints que quand la session
    // change (statut, phrase, réponse), jamais au rythme des particules.
    return RepaintBoundary(
      child: Padding(
        // Respiration entre la sphère (et son ombre) et le texte.
        padding: EdgeInsets.only(top: g.compact ? 6 : 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: g.compact ? 56 : 72,
            maxWidth: g.largeurTexte,
          ),
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              final probleme = session.probleme;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: probleme != null
                    ? _Probleme(
                        key: const ValueKey('probleme'),
                        probleme: probleme,
                        session: session,
                        gabarit: g,
                      )
                    : _Conversation(
                        key: const ValueKey('conversation'),
                        session: session,
                        gabarit: g,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    super.key,
    required this.session,
    required this.gabarit,
  });

  final VoiceSession session;
  final GabaritJarvis gabarit;

  @override
  Widget build(BuildContext context) {
    final g = gabarit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            _Statut(session: session, taille: g.tailleStatut),
            // Seulement l'état réel « aucun son » : jamais après une phrase
            // reconnue (le micro fonctionne alors forcément).
            if (session.etatMicro == EtatMicro.aucunSon)
              _Indicateur(
                icone: Icons.mic_off_outlined,
                texte: 'Aucun son détecté',
                taille: g.tailleStatut,
                infobulle:
                    'Le micro est disponible mais je n’entends rien. '
                    'Parle un peu plus près ou plus fort.',
              ),
            if (session.erreurVoix != null)
              _Indicateur(
                icone: Icons.volume_off_outlined,
                texte: 'Voix indisponible',
                taille: g.tailleStatut,
                infobulle: session.erreurVoix,
              ),
          ],
        ),
        // Bouton contextuel, zone de hauteur fixe : rien ne bouge quand il
        // apparaît (« Arrêter la parole » pendant la parole, « Parler »
        // après un arrêt, rien sinon).
        SizedBox(height: 52, child: Center(child: _BoutonParole(session: session))),
        // Ce que l'utilisateur a dit.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: session.transcription.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '« ${session.transcription} »',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: g.tailleCitation,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
        ),
        // Réponse automatique désactivée : la phrase attend d'être envoyée.
        if (session.phraseEnAttente != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: session.ignorerPhrase,
                  style: TextButton.styleFrom(
                    foregroundColor: CouleursJarvis.texteSecondaire,
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Réécouter'),
                ),
                FilledButton.icon(
                  onPressed: session.envoyerPhrase,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  label: const Text('Envoyer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CouleursJarvis.signal,
                    foregroundColor: CouleursJarvis.ivoire,
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        // Ce que JARVIS répond.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: session.reponse.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    session.reponse,
                    textAlign: TextAlign.center,
                    maxLines: g.lignesReponse,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: g.tailleReponse,
                      height: 1.5,
                      letterSpacing: 0.1,
                      color: CouleursJarvis.texte.withValues(alpha: 0.86),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Arrêter la parole (JARVIS parle) ou Parler (après un arrêt) : un seul
/// bouton, fondu court, jamais affiché dans un état qui ne lui correspond pas.
class _BoutonParole extends StatelessWidget {
  const _BoutonParole({required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final parle = session.actif && session.etat == VoiceState.speaking;
    final reprendre = session.actif && session.paroleInterrompue;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: parle
          ? FilledButton.icon(
              key: const ValueKey('arreter'),
              onPressed: session.arreterParole,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Arrêter la parole'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9473F),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            )
          : reprendre
          ? FilledButton.icon(
              key: const ValueKey('parler'),
              onPressed: session.parler,
              icon: const Icon(Icons.mic_none_rounded, size: 18),
              label: const Text('Parler'),
              style: FilledButton.styleFrom(
                backgroundColor: CouleursJarvis.signal,
                foregroundColor: CouleursJarvis.ivoire,
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('rien')),
    );
  }
}

/// « À l'écoute… », « JARVIS réfléchit… », « JARVIS parle… » : petit, avec un point
/// de couleur qui indique l'état.
class _Statut extends StatelessWidget {
  const _Statut({required this.session, required this.taille});

  final VoiceSession session;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (session.etat) {
      VoiceState.listening => CouleursJarvis.signal,
      VoiceState.thinking => CouleursJarvis.violet,
      VoiceState.speaking => CouleursJarvis.signal,
      VoiceState.idle => CouleursJarvis.trait,
    };
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(
          key: ValueKey(session.statut),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.statut.isNotEmpty) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              session.statut,
              style: TextStyle(
                fontSize: taille,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petite pastille d'information (micro non détecté…).
class _Indicateur extends StatelessWidget {
  const _Indicateur({
    required this.icone,
    required this.texte,
    required this.taille,
    this.infobulle,
  });

  final IconData icone;
  final String texte;
  final double taille;
  final String? infobulle;

  @override
  Widget build(BuildContext context) {
    final pastille = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursJarvis.trait),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: taille + 1, color: CouleursJarvis.texteSecondaire),
          const SizedBox(width: 6),
          Text(
            texte,
            style: TextStyle(
              fontSize: taille - 0.5,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ),
    );
    final message = infobulle;
    return message == null
        ? pastille
        : Tooltip(message: message, child: pastille);
  }
}

/// Problème du mode vocal : libellé court, détail en petit, actions.
class _Probleme extends StatelessWidget {
  const _Probleme({
    super.key,
    required this.probleme,
    required this.session,
    required this.gabarit,
  });

  final ProblemeVocal probleme;
  final VoiceSession session;
  final GabaritJarvis gabarit;

  @override
  Widget build(BuildContext context) {
    final g = gabarit;
    const bouton = Size(0, 40);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: _Indicateur(
            icone: Icons.mic_off_outlined,
            texte: probleme.titre,
            taille: g.tailleStatut + 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          probleme.message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: g.tailleCitation,
            height: 1.45,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            if (probleme.reglages)
              TextButton(
                onPressed: session.ouvrirReglages,
                style: TextButton.styleFrom(
                  foregroundColor: CouleursJarvis.signal,
                  minimumSize: bouton,
                ),
                child: const Text('Ouvrir les réglages'),
              ),
            FilledButton(
              onPressed: session.demarrer,
              style: FilledButton.styleFrom(
                backgroundColor: CouleursJarvis.signal,
                foregroundColor: CouleursJarvis.ivoire,
                minimumSize: bouton,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: const TextStyle(fontSize: 13.5),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ],
    );
  }
}
