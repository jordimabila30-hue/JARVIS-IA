import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/lecture_en_flux.dart';
import 'package:ia_jarvis/services/tts_service.dart';

/// Voix factice : chaque segment dure jusqu'à [finir] (ou immédiat).
class _Voix {
  _Voix({this.immediate = true});
  final bool immediate;
  final dits = <String>[];
  Completer<ResultatParole>? _c;

  Future<ResultatParole> dire(String t) {
    dits.add(t);
    if (immediate) return Future.value(ResultatParole.lue);
    return (_c = Completer<ResultatParole>()).future;
  }

  void finir() => _c?.complete(ResultatParole.lue);
}

Future<void> _laisser([int ms = 10]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('réponse courte reçue d’un coup : lue entière, une fois', () async {
    final v = _Voix();
    final l = LectureEnFlux(dire: v.dire);
    l.ajouter('Il est 14 h 05.');
    l.terminer();
    await l.fin;
    expect(v.dits, ['Il est 14 h 05.']);
  });

  test('flux : jamais un fragment incomplet, jamais de répétition', () async {
    final v = _Voix();
    final l = LectureEnFlux(dire: v.dire, attenteMax: const Duration(seconds: 5));
    for (final f in ['Le rot', 'or est la partie ', 'qui tourne. Le sta', 'tor reste fixe. Ent', 're les deux']) {
      l.ajouter(f);
      await _laisser();
    }
    // Deux phrases complètes : la lecture a commencé, sans le bout inachevé.
    expect(v.dits, ['Le rotor est la partie qui tourne.', 'Le stator reste fixe.']);
    l.ajouter(', le champ magnétique agit.');
    l.terminer();
    await l.fin;
    expect(v.dits, [
      'Le rotor est la partie qui tourne.',
      'Le stator reste fixe.',
      'Entre les deux, le champ magnétique agit.',
    ]);
  });

  test('nombres décimaux et listes : jamais coupés au point', () async {
    final v = _Voix();
    final l = LectureEnFlux(dire: v.dire);
    l.ajouter('Il mesure 3.5 mètres.\n1. Première étape.\n2. Deuxième étape.');
    l.terminer();
    await l.fin;
    expect(v.dits.join(' '), contains('3.5 mètres'));
    expect(v.dits.join(' '), isNot(contains(RegExp(r'\b[12]\.'))));
  });

  test('une seule phrase : démarre après attenteMax, pas avant', () async {
    final v = _Voix();
    final l = LectureEnFlux(dire: v.dire, attenteMax: const Duration(milliseconds: 80));
    l.ajouter('Une première phrase assez courte. Et la su');
    await _laisser(20);
    expect(v.dits, isEmpty);
    await _laisser(120);
    expect(v.dits, ['Une première phrase assez courte.']);
    l.terminer();
    await l.fin;
  });

  test('réseau lent : réserve épuisée → attente, puis suite dans l’ordre', () async {
    final v = _Voix(immediate: false);
    final l = LectureEnFlux(dire: v.dire);
    l.ajouter('Phrase un ici. Phrase deux ici. ');
    await _laisser();
    expect(v.dits, ['Phrase un ici.']);
    v.finir();
    await _laisser();
    v.finir();
    await _laisser();
    expect(l.enAttente, isTrue); // rien d'inventé
    l.ajouter('Phrase trois ici. ');
    await _laisser();
    expect(v.dits.last, 'Phrase trois ici.');
    v.finir();
    l.terminer();
    await l.fin;
    expect(v.dits, hasLength(3));
  });

  test('coupure réseau : phrases complètes lues, bout inachevé jamais lu', () async {
    final v = _Voix();
    final l = LectureEnFlux(dire: v.dire);
    l.ajouter('Première phrase complète. Deuxième phrase complète. Et la troisi');
    l.terminer(coupee: true);
    await l.fin;
    expect(v.dits, ['Première phrase complète.', 'Deuxième phrase complète.']);
    expect(l.coupee, isTrue);
  });

  test('annuler : plus rien n’est dit, entendu = phrases dites + en cours', () async {
    final v = _Voix(immediate: false);
    final l = LectureEnFlux(dire: v.dire);
    l.ajouter('Un moteur électrique transforme l’énergie. Il comporte un rotor. Et un stator. ');
    await _laisser();
    v.finir();
    await _laisser();
    l.annuler();
    l.ajouter('Encore une phrase tardive. ');
    v.finir();
    await l.fin;
    expect(v.dits, hasLength(2));
    expect(l.entendu, startsWith('Un moteur électrique transforme l’énergie.'));
    expect(l.entendu, contains('Il comporte un rotor.'));
  });
}
