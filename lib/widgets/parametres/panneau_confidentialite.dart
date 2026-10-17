import 'package:flutter/material.dart';

import '../../services/conversation/consentement_analyse.dart';
import '../../theme/theme_jarvis.dart';
import 'elements_parametres.dart';

/// Paramètres › Confidentialité : où vont les données, et l'accord pour
/// l'analyse distante des conversations WhatsApp jointes (révocable).
class PanneauConfidentialite extends StatelessWidget {
  const PanneauConfidentialite({super.key, this.consentement});

  /// Null : JARVIS ouvert sans compte (aucune analyse distante possible).
  final ConsentementAnalyse? consentement;

  @override
  Widget build(BuildContext context) {
    final c = consentement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteReglages(
          titre: 'Conversations WhatsApp',
          enfants: [
            if (c == null)
              const LigneReglage(
                titre: 'Analyse par l’IA',
                description:
                    'Connectez-vous pour enregistrer et faire analyser les '
                    'conversations WhatsApp jointes.',
                controle: SizedBox.shrink(),
                largeurControle: 0,
              )
            else
              ListenableBuilder(
                listenable: c,
                builder: (context, _) => LigneReglage(
                  titre: 'Analyse par l’IA',
                  description: switch (c.etat) {
                    EtatConsentement.accorde =>
                      'Autorisée : les extraits utiles des conversations '
                          'jointes partent vers GroqCloud avec vos questions.',
                    EtatConsentement.refuse =>
                      'Refusée : rien n’est envoyé à l’IA. Les conversations '
                          'restent enregistrées et consultables.',
                    EtatConsentement.inconnu =>
                      'Pas encore demandée : JARVIS vous posera la question '
                          'à la première analyse.',
                  },
                  largeurControle: 60,
                  controle: Align(
                    alignment: Alignment.centerRight,
                    child: Switch(
                      value: c.etat == EtatConsentement.accorde,
                      activeThumbColor: Colors.white,
                      activeTrackColor: CouleursJarvis.signal,
                      onChanged: (oui) => oui ? c.accorder() : c.refuser(),
                    ),
                  ),
                  note:
                      'Seuls les messages que vous avez choisis à l’import, '
                      'et seulement les passages utiles à la question, sont '
                      'envoyés : auteurs, dates et textes, jamais de fichiers '
                      'ni de médias. GroqCloud est le service d’intelligence '
                      'artificielle externe utilisé par JARVIS. Accord '
                      'enregistré sur cet appareil, pour ce compte.',
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const CarteReglages(
          titre: 'Où sont vos données',
          enfants: [
            LigneReglage(
              titre: 'Compte et conversations',
              description:
                  'Enregistrés par le serveur JARVIS dans votre compte : '
                  'vous les retrouvez sur vos autres appareils.',
              controle: SizedBox.shrink(),
              largeurControle: 0,
            ),
            LigneReglage(
              titre: 'Réglages',
              description:
                  'Voix, particules et accord ci-dessus : enregistrés sur '
                  'cet appareil.',
              controle: SizedBox.shrink(),
              largeurControle: 0,
            ),
            LigneReglage(
              titre: 'Reconnaissance vocale',
              description:
                  'Celle du navigateur ou du système peut utiliser son '
                  'propre service en ligne.',
              controle: SizedBox.shrink(),
              largeurControle: 0,
            ),
          ],
        ),
      ],
    );
  }
}
