import 'package:flutter_test/flutter_test.dart';

import 'package:ia_jarvis/main.dart';
import 'package:ia_jarvis/pages/ecran_de_lancement.dart';

void main() {
  testWidgets('L\'app démarre sur l\'écran de lancement', (tester) async {
    await tester.pumpWidget(const JarvisApp());
    expect(find.byType(EcranDeLancement), findsOneWidget);
  });
}
