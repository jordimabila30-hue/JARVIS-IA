import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/voice_command_service.dart';

/// K1-13 : commandes locales courantes, sans IA, réponses justes.
void main() {
  final s = VoiceCommandService(horloge: () => DateTime(2026, 10, 24, 19, 30));
  String? local(String p) => s.reponseLocale(p, avecIA: true)?.texte;

  test('heure et date, y compris demain et hier', () {
    for (final p in [
      'Quelle heure est-il ?',
      'il est quelle heure',
      'tu as l\'heure ?',
    ]) {
      expect(local(p), 'Il est 19 heures 30.', reason: p);
    }
    for (final p in [
      'On est quel jour ?',
      'quel jour sommes-nous ?',
      'on est le combien ?',
      'c\'est quoi la date aujourd\'hui',
    ]) {
      expect(local(p), contains('samedi 24 octobre 2026'), reason: p);
    }
    expect(
      local('quelle est la date de demain ?'),
      contains('dimanche 25 octobre'),
    );
    expect(
      local('quelle date on était hier ?'),
      contains('vendredi 23 octobre'),
    );
    expect(local('quel mois on est ?'), contains('octobre'));
    expect(local('quelle année on est ?'), contains('2026'));
  });

  test('calculs', () {
    expect(local('combien font 12 fois 8 ?'), contains('96'));
    expect(local('combien fait 15 % de 80'), contains('12'));
    expect(local('125 divisé par 5'), contains('25'));
    expect(local('racine carrée de 81'), contains('9'));
  });

  test('« à quelle heure ouvre la poste ? » reste pour l’IA', () {
    expect(local('à quelle heure ouvre la poste ?'), isNull);
  });
}
