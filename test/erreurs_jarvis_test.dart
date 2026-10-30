import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/utils/erreurs_jarvis.dart';

void main() {
  test('hors debug : module et type seulement, jamais le message', () {
    final avant = FlutterError.onError;
    final avantPlateforme = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = avant;
      PlatformDispatcher.instance.onError = avantPlateforme;
    });
    ErreursJarvis.signalees.clear();
    ErreursJarvis.installer(complet: false);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: const FormatException('texte privé : rendez-vous à 18 h'),
        library: 'widgets library',
      ),
    );
    final gere = PlatformDispatcher.instance.onError!(
      StateError('adresse@exemple.com'),
      StackTrace.empty,
    );

    expect(gere, isTrue);
    expect(ErreursJarvis.signalees, [
      'widgets library : FormatException',
      'asynchrone : StateError',
    ]);
    expect(
      ErreursJarvis.signalees.join(),
      isNot(anyOf(contains('privé'), contains('@'))),
    );
  });

  testWidgets('un widget en erreur ne remplace que lui-même', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Text('Conversation intacte'),
            SizedBox(
              height: 40,
              child: Builder(
                builder: (_) => throw StateError('module en panne'),
              ),
            ),
          ],
        ),
      ),
    );
    expect(t.takeException(), isA<StateError>());
    expect(find.text('Conversation intacte'), findsOneWidget);
  });
}
