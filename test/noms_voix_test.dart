// Noms de voix lisibles dans les Paramètres.

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_settings.dart';
import 'package:ia_jarvis/utils/noms_voix.dart';

void main() {
  test('voix Microsoft, Google, Apple : nom court', () {
    expect(
      nomCourtVoix('Microsoft Denise Online (Natural) - French (France)'),
      'Denise',
    );
    expect(
      nomCourtVoix(
        'Microsoft Rémy Multilingual Online (Natural) - French (France)',
      ),
      'Rémy',
    );
    expect(nomCourtVoix('Microsoft Hortense - French (France)'), 'Hortense');
    expect(nomCourtVoix('Amélie'), 'Amélie');
    // Sans l'éditeur, il ne resterait que la langue : on le garde.
    expect(nomCourtVoix('Google français'), 'Google français');
    // Identifiants système Android : pas de nom.
    expect(nomCourtVoix('fr-fr-x-frd-local'), '');
    expect(nomCourtVoix('fr-FR-language'), '');
  });

  test('libellés : région seulement hors région principale, « Naturelle », '
      'aucun doublon', () {
    const denise = VoixDisponible(
      nom: 'Microsoft Denise Online (Natural) - French (France)',
      locale: 'fr-FR',
    );
    const paul = VoixDisponible(
      nom: 'Microsoft Paul - French (France)',
      locale: 'fr-FR',
    );
    const sylvie = VoixDisponible(
      nom: 'Microsoft Sylvie Online (Natural) - French (Canada)',
      locale: 'fr-CA',
    );
    const a = VoixDisponible(nom: 'fr-fr-x-fra-local', locale: 'fr-FR');
    const b = VoixDisponible(nom: 'fr-fr-x-frb-network', locale: 'fr-FR');

    expect(libellesVoix(const [denise, paul]).values, [
      'Denise · Naturelle',
      'Paul',
    ]);
    expect(libellesVoix(const [denise, sylvie]).values, [
      'Denise · Naturelle',
      'Sylvie · Canada · Naturelle',
    ]);
    expect(libellesVoix(const [a, b]).values, ['Voix 1', 'Voix 2']);
    // Même nom court pour deux voix : numéroté.
    const paulBis = VoixDisponible(nom: 'Paul', locale: 'fr-FR');
    expect(libellesVoix(const [paul, paulBis]).values, ['Paul', 'Paul (2)']);
  });
}
