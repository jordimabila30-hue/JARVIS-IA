import 'package:flutter/material.dart';

import '../../services/jarvis_touch_service.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_parametres.dart';

/// Sous-pages de Paramètres › Général (comme Outils › Gmail) :
/// JARVIS Touch, puis Capture d'écran ou Personnalisation.
enum PageGenerale {
  touch('JARVIS Touch', null),
  capture('Capture d’écran', PageGenerale.touch),
  personnalisation('Personnalisation', PageGenerale.touch);

  const PageGenerale(this.libelle, this.parent);

  final String libelle;

  /// Page d'où l'on vient (null : Général).
  final PageGenerale? parent;
}

/// Ligne qui ouvre une sous-page : icône, titre, sous-titre, chevron.
class LigneSousPage extends StatelessWidget {
  const LigneSousPage({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.surAppui,
    this.statut,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback surAppui;
  final String? statut;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: surAppui,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: CouleursJarvis.signal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icone, size: 20, color: CouleursJarvis.signal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: CouleursJarvis.texte,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sousTitre,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
            if (statut != null) ...[
              const SizedBox(width: 10),
              Text(
                statut!,
                style: const TextStyle(
                  fontSize: 13,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
            ],
            const SizedBox(width: 4),
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

/// Général › JARVIS Touch : l'interrupteur existant, puis les sous-pages.
class PageJarvisTouch extends StatelessWidget {
  const PageJarvisTouch({super.key, required this.touch, required this.surPage});

  final JarvisTouchService touch;
  final ValueChanged<PageGenerale> surPage;

  @override
  Widget build(BuildContext context) {
    final t = touch;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CarteReglages(
            enfants: [
              LigneReglage(
                titre: 'Activer JARVIS Touch',
                description: 'La bulle reste au-dessus des autres applications.',
                largeurControle: 60,
                controle: Align(
                  alignment: Alignment.centerRight,
                  child: t.occupe
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CouleursJarvis.signal,
                            ),
                          ),
                        )
                      : Switch(
                          value: t.actif,
                          activeThumbColor: Colors.white,
                          activeTrackColor: CouleursJarvis.signal,
                          onChanged: t.choisir,
                        ),
                ),
                note:
                    t.message ??
                    (t.etat == EtatJarvisTouch.attenteAutorisation
                        ? 'Autorisez « Afficher par-dessus les autres '
                              'applis » pour JARVIS, puis revenez ici.'
                        : null),
              ),
            ],
          ),
          const SizedBox(height: 24),
          CarteReglages(
            enfants: [
              LigneSousPage(
                icone: Icons.screenshot_outlined,
                titre: 'Capture d’écran',
                sousTitre: 'Autorisation de capture',
                statut: libelleCapture(t.capture),
                surAppui: () => surPage(PageGenerale.capture),
              ),
              LigneSousPage(
                icone: Icons.tune_rounded,
                titre: 'Personnalisation',
                sousTitre: 'Apparence et comportement de la bulle',
                surAppui: () => surPage(PageGenerale.personnalisation),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Autorisé » seulement si la capture directe (service d'accessibilité)
/// est réellement active ; l'accord Android ponctuel n'est jamais présenté
/// comme une autorisation permanente.
String? libelleCapture(CaptureEcranTouch? c) => switch (c) {
  null => null,
  CaptureEcranTouch(sansAutorisation: true) => 'Autorisé',
  CaptureEcranTouch(sansAutorisationPossible: false) => 'À chaque capture',
  _ => 'Non autorisé',
};

/// Général › JARVIS Touch › Capture d'écran.
class PageCaptureTouch extends StatelessWidget {
  const PageCaptureTouch({super.key, required this.touch});

  final JarvisTouchService touch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: touch,
    builder: (context, _) {
      final c = touch.capture;
      final possible = c?.sansAutorisationPossible ?? true;
      return CarteReglages(
        enfants: [
          LigneReglage(
            titre: 'Capture directe',
            description: possible
                ? 'Service d’accessibilité « JARVIS Touch · capture d’écran » : '
                      'une image seulement quand vous touchez Capturer.'
                : 'Cette version d’Android demande votre accord à chaque '
                      'capture.',
            largeurControle: 130,
            controle: Text(
              libelleCapture(c) ?? '…',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c?.sansAutorisation == true
                    ? CouleursJarvis.signal
                    : CouleursJarvis.texteSecondaire,
              ),
            ),
            note: c != null && possible && !c.sansAutorisation
                ? 'Sans elle, Android demande votre accord à chaque capture.'
                : null,
            action: possible
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: touch.ouvrirReglagesCapture,
                      child: const Text('Gérer l’autorisation'),
                    ),
                  )
                : null,
          ),
        ],
      );
    },
  );
}

/// Général › JARVIS Touch › Personnalisation : structure seulement.
class PagePersonnalisationTouch extends StatelessWidget {
  const PagePersonnalisationTouch({super.key});

  @override
  Widget build(BuildContext context) => const CarteReglages(
    enfants: [
      Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: NoteReglage(
          'Bientôt : taille, transparence et comportement de la bulle.',
        ),
      ),
    ],
  );
}
