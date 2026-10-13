// Durée de vie des jetons indépendante de l'heure de l'appareil : heure de
// l'appareil avancée, retardée, autre fuseau horaire. Horloges injectées :
// l'horloge réelle n'est jamais modifiée.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/authentification/horloge_jetons.dart';
import 'package:ia_jarvis/widgets/parametres/panneau_compte.dart';

/// Heure « réelle » du serveur pendant le test.
final _serveur = DateTime.utc(2026, 10, 13, 12);

String _jeton({int duree = 3600, DateTime? emis}) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final iat = (emis ?? _serveur).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'ES256'})}.'
      '${b64({'sub': 'u', 'iat': iat, 'exp': iat + duree})}.signature';
}

/// Chronomètre monotone simulé.
class _Chrono implements Stopwatch {
  Duration ecoule = Duration.zero;
  @override
  Duration get elapsed => ecoule;
  @override
  void start() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Chrono chrono;

  HorlogeJetons horloge(Duration decalageAppareil) {
    chrono = _Chrono();
    return HorlogeJetons(
      maintenant: () => _serveur.add(decalageAppareil),
      chrono: () => chrono,
    );
  }

  for (final (nom, decalage) in const [
    ('à l’heure', Duration.zero),
    ('avancé de 2 h', Duration(hours: 2)),
    ('retardé de 3 h', Duration(hours: -3)),
    ('retardé de 202 s', Duration(seconds: -202)),
  ]) {
    test('appareil $nom : durée de vie intacte (exp − iat, chronomètre)', () {
      final h = horloge(decalage);
      final j = _jeton();
      h.observer(j);
      expect(h.resteValide(j), const Duration(hours: 1));
      chrono.ecoule = const Duration(minutes: 59, seconds: 30);
      expect(h.resteValide(j), const Duration(seconds: 30));
      // Écart mesuré : serveur − appareil.
      expect(h.decalage, -decalage);
    });
  }

  test('fuseau horaire : aucun effet (même instant, autre fuseau)', () {
    final utc = HorlogeJetons(maintenant: () => _serveur);
    final local = HorlogeJetons(maintenant: () => _serveur.toLocal());
    final j = _jeton();
    utc.observer(j);
    local.observer(j);
    expect(utc.decalage, Duration.zero);
    expect(local.decalage, Duration.zero);
    expect(local.decalageImportant, isFalse);
  });

  test('décalage important signalé, petit décalage ignoré', () {
    var h = horloge(const Duration(seconds: -202));
    h.observer(_jeton());
    expect(h.decalageImportant, isTrue);
    expect(
      PanneauCompte.messageDecalage(h.decalage),
      contains('retarde d’environ 3 min'),
    );
    h = horloge(const Duration(seconds: 40));
    h.observer(_jeton());
    expect(h.decalageImportant, isFalse);
    expect(PanneauCompte.messageDecalage(h.decalage), isNull);
    expect(
      PanneauCompte.messageDecalage(const Duration(minutes: -90)),
      contains('avance d’environ 90 min'),
    );
  });

  test('jeton inconnu (session restaurée) : durée inconnue', () {
    final h = horloge(Duration.zero);
    h.observer(_jeton());
    expect(h.resteValide(_jeton(duree: 1800)), isNull);
    h.oublier();
    expect(h.resteValide(_jeton()), isNull);
  });

  test('jeton illisible : rien n’est supposé', () {
    final h = horloge(Duration.zero);
    h.observer('pas-un-jwt');
    expect(h.resteValide('pas-un-jwt'), isNull);
    expect(h.decalage, isNull);
  });
}
