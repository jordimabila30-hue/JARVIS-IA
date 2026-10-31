// Données locales abîmées (session KL, opt. 91) : chaque réglage illisible
// redonne sa valeur par défaut, sans exception ni effacement d'autre chose.

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/conversation/consentement_analyse.dart';
import 'package:ia_jarvis/services/conversations/epingles_conversations.dart';
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/preferences_pim_service.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';

const _abimees = [
  '{pas du json',
  '[1, 2,',
  '{"version": 999, "inconnu": true}',
  '"texte"',
  '42',
  '',
  '\u0000\u0001',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brut in _abimees) {
    test(
      'valeur abîmée ${brut.codeUnits.take(6)} : défauts, rien ne plante',
      () async {
        final defauts = VoiceSettingsService(stockage: StockageMemoire());
        final voix = VoiceSettingsService(stockage: StockageMemoire(brut));
        await voix.charger();
        expect(voix.reglages.toJson(), defauts.reglages.toJson());

        final epingles = EpinglesConversations(stockage: StockageMemoire(brut));
        await epingles.charger();

        final pim = PreferencesPimService(stockage: StockageMemoire(brut));
        final formeDefaut = pim.forme;
        await pim.charger();
        expect(pim.forme, formeDefaut);
        expect(pim.charge, isTrue);

        await IdentiteWhatsApp(stockage: StockageMemoire(brut)).charger();

        final consentement = ConsentementAnalyse(
          stockage: StockageMemoire(brut),
        );
        final etatDefaut = consentement.etat;
        await consentement.charger();
        expect(consentement.etat, etatDefaut);
        expect(consentement.charge, isTrue);
      },
    );
  }
}
