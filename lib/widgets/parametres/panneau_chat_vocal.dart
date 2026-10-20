import 'package:flutter/material.dart';

import '../../models/voice_settings.dart';
import '../../services/voice_session.dart';
import '../../services/voice_settings_service.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/noms_locales.dart';
import '../../utils/noms_voix.dart';
import 'carte_apercu_voix.dart';
import 'elements_parametres.dart';

/// Section « Chat vocal » des Paramètres, reliée au système vocal réel :
/// chaque réglage modifie [VoiceSettingsService] (appliqué à la prochaine
/// prise de parole et enregistré automatiquement).
class PanneauChatVocal extends StatelessWidget {
  const PanneauChatVocal({super.key, required this.session});

  final VoiceSession session;

  VoiceSettingsService get _service => session.reglages;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final r = _service.reglages;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CarteReglages(
              titre: 'Voix',
              enfants: [
                _profil(r),
                _langue(r),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _voix(r),
                    EtatApercuVoix(session: session),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            CarteReglages(titre: 'Expression', enfants: _diction(r)),
            const SizedBox(height: 20),
            CarteReglages(
              titre: 'Écoute',
              enfants: [_micro(r), _reponseAuto(r)],
            ),
            const SizedBox(height: 20),
            // Réglages secondaires, repliés : rien n'est perdu, l'écran
            // reste court.
            CarteReglages(
              enfants: [
                _Repliable(titre: 'Options avancées', enfant: _interruption(r)),
              ],
            ),
          ],
        );
      },
    );
  }

  // --- Profil, langue, voix ---------------------------------------------------

  /// Profils en grille régulière (2 colonnes sur téléphone, 4 au-delà).
  Widget _profil(VoiceSettings r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TexteReglage(titre: 'Profil vocal'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              const ecart = 8.0;
              final colonnes = c.maxWidth >= 480 ? 4 : 2;
              final largeur = (c.maxWidth - ecart * (colonnes - 1)) / colonnes;
              return Wrap(
                spacing: ecart,
                runSpacing: ecart,
                children: [
                  for (final p in ProfilVocal.predefinis)
                    SizedBox(
                      width: largeur,
                      child: _Choix(
                        libelle: p.libelle,
                        choisi: r.profil == p,
                        surChoix: () => _service.choisirProfil(p),
                      ),
                    ),
                  if (r.profil == ProfilVocal.personnalise)
                    SizedBox(
                      width: largeur,
                      child: const _Choix(
                        libelle: 'Personnalisé',
                        choisi: true,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Langues de JARVIS seulement : français, anglais, allemand, espagnol.
  Widget _langue(VoiceSettings r) {
    final langues = _service.langues;
    final langue = _service.langue;
    return LigneReglage(
      titre: 'Langue',
      largeurControle: 260,
      controle: ListeReglage<String>(
        libelle: 'Langue',
        valeur: langues.contains(langue) ? langue : langues.first,
        options: [for (final l in langues) (l, nomLangue(l))],
        surChoix: _service.choisirLangue,
      ),
    );
  }

  /// Voix de la langue choisie, avec des noms simples (« Denise ·
  /// Naturelle »).
  Widget _voix(VoiceSettings r) {
    final voix = _service.voixDeLaLangue;
    if (voix.isEmpty) {
      return LigneReglage(
        titre: 'Voix',
        largeurControle: 320,
        controle: _avecApercu(
          ListeReglage<String?>(
            libelle: 'Voix',
            valeur: null,
            options: [
              (
                null,
                _service.capacitesChargees ? 'Voix du système' : 'Recherche…',
              ),
            ],
            surChoix: null,
          ),
        ),
      );
    }
    final libelles = libellesVoix(voix);
    final effective = _service.voixEffective;
    final choisie = voix.firstWhere(
      (v) => v.nom == r.voix && v.locale == r.locale,
      orElse: () => voix.firstWhere(
        (v) => effective != null && v.nom == effective.nom,
        orElse: () => voix.first,
      ),
    );
    return LigneReglage(
      titre: 'Voix',
      largeurControle: 320,
      controle: _avecApercu(
        ListeReglage<String>(
          libelle: 'Voix',
          valeur: idVoix(choisie),
          options: [for (final v in voix) (idVoix(v), libelles[idVoix(v)]!)],
          surChoix: (id) => _service.choisirVoixDisponible(
            voix.firstWhere((v) => idVoix(v) == id),
          ),
        ),
      ),
    );
  }

  /// Liste des voix et, juste à côté, l'aperçu vocal.
  Widget _avecApercu(Widget liste) => Row(
    children: [
      Expanded(child: liste),
      const SizedBox(width: 10),
      BoutonApercuVoix(session: session),
    ],
  );

  // --- Vitesse, hauteur, volume -------------------------------------------------

  /// Nombre à la française, sans zéros inutiles (1.25 → « 1,25 »).
  static String _decimal(double v) => v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');

  List<Widget> _diction(VoiceSettings r) {
    final hauteur = (r.hauteur * 100).round();
    return [
      CurseurReglage(
        titre: 'Vitesse',
        valeurAffichee: (r.vitesse - 1).abs() < 0.001
            ? 'Normale'
            : '×${_decimal(r.vitesse)}',
        valeur: r.vitesse,
        min: VoiceSettings.vitesseMin,
        max: VoiceSettings.vitesseMax,
        divisions: 12,
        icones: (Icons.directions_walk_rounded, Icons.directions_run_rounded),
        surChangement: _service.choisirVitesse,
      ),
      CurseurReglage(
        titre: 'Hauteur',
        valeurAffichee: hauteur == 0
            ? 'Normale'
            : '${hauteur > 0 ? '+' : '−'}${hauteur.abs()} %',
        valeur: r.hauteur,
        min: VoiceSettings.hauteurMin,
        max: VoiceSettings.hauteurMax,
        divisions: 6,
        icones: (
          Icons.keyboard_double_arrow_down_rounded,
          Icons.keyboard_double_arrow_up_rounded,
        ),
        surChangement: _service.choisirHauteur,
      ),
      CurseurReglage(
        titre: 'Volume',
        valeurAffichee: '${(r.volume * 100).round()} %',
        valeur: r.volume,
        min: 0,
        max: 1,
        divisions: 20,
        icones: (Icons.volume_mute_rounded, Icons.volume_up_rounded),
        surChangement: _service.choisirVolume,
      ),
    ];
  }

  // --- Micro et réponse automatique -------------------------------------------

  Widget _micro(VoiceSettings r) {
    final micros = _service.micros;
    final possible = _service.choixMicroPossible;
    final sansNoms = possible && micros.any((m) => !m.nomConnu);
    return LigneReglage(
      titre: 'Microphone',
      largeurControle: 260,
      controle: ListeReglage<String?>(
        libelle: 'Microphone',
        valeur: micros.any((m) => m.id == r.microphoneId)
            ? r.microphoneId
            : null,
        options: [
          (null, 'Microphone par défaut'),
          for (final m in micros) (m.id, m.nom),
        ],
        surChoix: possible ? _service.choisirMicro : null,
      ),
      action: sansNoms
          ? TextButton.icon(
              onPressed: _service.autoriserMicros,
              icon: const Icon(Icons.mic_none, size: 18),
              label: const Text('Afficher le nom des micros'),
              style: TextButton.styleFrom(
                foregroundColor: CouleursJarvis.signal,
                minimumSize: const Size(0, 40),
              ),
            )
          : null,
    );
  }

  /// Interruption de la parole : réglage commun au vocal principal et à
  /// JARVIS Touch. « Automatique » n'est pas encore disponible : affiché
  /// tel quel, jamais choisissable.
  Widget _interruption(VoiceSettings r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TexteReglage(titre: 'Interruption de la parole'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in ModeInterruption.values)
              PastilleReglage(
                libelle: m.disponible ? m.libelle : '${m.libelle} · bientôt',
                choisie: r.interruption == m,
                surChoix: m.disponible
                    ? () => _service.choisirInterruption(m)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _reponseAuto(VoiceSettings r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: MergeSemantics(
        child: Row(
          children: [
            const Expanded(child: TexteReglage(titre: 'Réponse automatique')),
            const SizedBox(width: 16),
            Switch(
              value: r.reponseAutomatique,
              onChanged: _service.choisirReponseAutomatique,
              activeThumbColor: CouleursJarvis.ivoire,
              activeTrackColor: CouleursJarvis.signal,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton de choix d'une grille (profil vocal) : hauteur régulière, nom
/// centré ; choisi : fond et contour de l'accent, coche.
class _Choix extends StatelessWidget {
  const _Choix({required this.libelle, required this.choisi, this.surChoix});

  final String libelle;
  final bool choisi;
  final VoidCallback? surChoix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: surChoix != null,
      selected: choisi,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: choisi
              ? CouleursJarvis.signal.withValues(alpha: 0.1)
              : CouleursJarvis.ivoire,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: choisi
                ? CouleursJarvis.signal.withValues(alpha: 0.55)
                : CouleursJarvis.trait,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: surChoix,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (choisi) ...[
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: CouleursJarvis.signal,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          libelle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: choisi
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: choisi
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
        ),
      ),
    );
  }
}

/// Section repliable : titre et chevron ; le contenu se déplie en douceur.
class _Repliable extends StatefulWidget {
  const _Repliable({required this.titre, required this.enfant});

  final String titre;
  final Widget enfant;

  @override
  State<_Repliable> createState() => _RepliableState();
}

class _RepliableState extends State<_Repliable> {
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _ouvert,
          child: InkWell(
            onTap: () => setState(() => _ouvert = !_ouvert),
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titre,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _ouvert ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _ouvert
              ? Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 16),
                  child: widget.enfant,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
