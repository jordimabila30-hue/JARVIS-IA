import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/voice_command_service.dart';
import 'package:ia_jarvis/utils/calcul_vocal.dart';
import 'package:ia_jarvis/utils/local_date_time.dart';

void main() {
  // Dimanche 4 octobre 2026, 19 h 24.
  final soir = DateTime(2026, 10, 4, 19, 24);
  late VoiceCommandService service;
  setUp(() => service = VoiceCommandService(horloge: () => soir));

  String repondre(String phrase) => service.reponseLocale(phrase)!.texte;

  group('Normalisation', () {
    test('casse, accents et ponctuation sont ignorés', () {
      expect(
        VoiceCommandService.normaliser('  BONJOUR,  Jarvis !! '),
        'bonjour jarvis',
      );
      expect(
        VoiceCommandService.normaliser('Qu’est-ce que tu peux faire ?'),
        'qu est ce que tu peux faire',
      );
      expect(VoiceCommandService.normaliser('Ça va ?'), 'ca va');
    });
  });

  group('Réponses de base', () {
    test('bonjour, quelle que soit la casse', () {
      for (final p in ['Bonjour Jarvis', 'bonjour jarvis', 'BONJOUR JARVIS']) {
        // Nouvelle conversation à chaque fois : c'est la première salutation.
        final neuf = VoiceCommandService(horloge: () => soir);
        expect(
          neuf.reponseLocale(p)!.texte,
          'Bonjour. Comment puis-je vous aider ?',
        );
      }
    });
    test('salutation selon l’heure si l’utilisateur dit « salut »', () {
      expect(repondre('Salut'), 'Bonsoir. Comment puis-je vous aider ?');
    });
    test('qui es-tu', () {
      expect(repondre('Qui es-tu ?'), 'Je suis JARVIS, votre assistant.');
    });
    test('que peux-tu faire liste les capacités réelles', () {
      expect(repondre('Que peux-tu faire ?'), contains('calculs'));
    });
    test('comment tu fonctionnes', () {
      expect(
        repondre('Comment tu fonctionnes ?'),
        startsWith('Je suis JARVIS'),
      );
    });
    test('au revoir termine la session', () {
      final r = service.reponseLocale('Au revoir JARVIS')!;
      expect(r.texte, 'À bientôt.');
      expect(r.terminerSession, isTrue);
    });
    test('demandes impossibles : réponse honnête', () {
      expect(repondre('Quel temps fait-il ?'), contains('pas encore accès'));
    });
  });

  group('Heure et date de l’appareil', () {
    test('plusieurs formulations de l’heure', () {
      for (final p in [
        'Quelle heure est-il ?',
        'Donne-moi l’heure',
        'Il est quelle heure ?',
      ]) {
        expect(repondre(p), 'Il est 19 heures 24.');
      }
    });
    test('l’heure passe avant la salutation', () {
      expect(
        repondre('Bonjour Jarvis, quelle heure est-il ?'),
        'Il est 19 heures 24.',
      );
    });
    test('date, demain, hier, mois, année', () {
      for (final p in [
        'Quelle est la date ?',
        'Quel jour sommes-nous ?',
        'On est quel jour ?',
      ]) {
        expect(repondre(p), 'Nous sommes le dimanche 4 octobre 2026.');
      }
      expect(
        repondre('On sera quel jour demain ?'),
        'Demain, nous serons le lundi 5 octobre 2026.',
      );
      expect(
        repondre('Quel jour étions-nous hier ?'),
        'Hier, nous étions le samedi 3 octobre 2026.',
      );
      expect(repondre('On est en quel mois ?'), 'Nous sommes en octobre.');
      expect(repondre('En quelle année ?'), 'Nous sommes en 2026.');
    });
    test('cas particuliers de formulation', () {
      expect(heureEnFrancais(DateTime(2026, 1, 1, 0, 0)), 'Il est minuit.');
      expect(heureEnFrancais(DateTime(2026, 1, 1, 12, 5)), 'Il est midi 05.');
      expect(
        heureEnFrancais(DateTime(2026, 1, 1, 1, 30)),
        'Il est 1 heure 30.',
      );
      expect(
        dateEnFrancais(DateTime(2026, 11, 1)),
        'Nous sommes le dimanche 1er novembre 2026.',
      );
      expect(salutation(DateTime(2026, 1, 1, 9)), 'Bonjour');
      expect(salutation(DateTime(2026, 1, 1, 21)), 'Bonsoir');
    });
  });

  group('Calculs', () {
    test('chiffres et symboles', () {
      expect(repondre('Combien font 12 fois 7 ?'), '12 fois 7 égale 84.');
      expect(repondre('12 x 7'), '12 fois 7 égale 84.');
      expect(repondre('15 + 27'), '15 plus 27 égale 42.');
      expect(repondre('Calcule 100 moins 58'), '100 moins 58 égale 42.');
      expect(repondre('125 divisé par 4'), '125 divisé par 4 égale 31,25.');
    });
    test('priorités opératoires', () {
      expect(repondre('2 plus 3 fois 4'), '2 plus 3 fois 4 égale 14.');
    });
    test('nombres en lettres', () {
      expect(repondre('combien font douze fois sept'), '12 fois 7 égale 84.');
      expect(
        repondre('quatre-vingt-dix-sept plus trois'),
        '97 plus 3 égale 100.',
      );
      expect(
        repondre('deux mille vingt-six moins vingt et un'),
        '2026 moins 21 égale 2 005.',
      );
    });
    test('racine, carré, puissance, pourcentage', () {
      expect(
        repondre('Racine carrée de 144'),
        'racine carrée de 144 égale 12.',
      );
      expect(repondre('5 au carré'), '5 au carré égale 25.');
      expect(repondre('2 puissance 10'), '2 puissance 10 égale 1 024.');
      expect(repondre('20 % de 150'), '20 pour cent de 150 égale 30.');
    });
    test('division par zéro', () {
      expect(repondre('8 divisé par 0'), 'Je ne peux pas diviser par zéro.');
    });
    test('phrases parlées', () {
      expect(repondre('fais un calcul 3 plus 4'), '3 plus 4 égale 7.');
      expect(CalculVocal.calculer('moins 5 plus 3')?.valeur, -2);
    });
    test('salutations mal tapées : réponse locale, jamais l’IA', () {
      final ia = VoiceCommandService();
      for (final (phrase, debut) in [
        ('bonjours', 'Bonjour'),
        ('Bonjours Jarvis !', 'Bonjour'),
        ('bjr', 'Bonjour'),
        ('bonsoirs', 'Bonsoir'),
        ('slt', ''),
      ]) {
        final r = ia.reponseLocale(phrase, avecIA: true);
        expect(r, isNotNull, reason: phrase);
        expect(r!.texte, startsWith(debut), reason: phrase);
      }
      // Une vraie question qui commence par une salutation reste à l'IA.
      expect(
        ia.reponseLocale(
          'bonjours, explique-moi la photosynthèse en détail',
          avecIA: true,
        ),
        isNull,
      );
    });

    test('pas de faux calcul', () {
      expect(CalculVocal.calculer('ca va et toi'), isNull);
      expect(CalculVocal.calculer('il est 3 heures'), isNull);
      // Opérateur jamais pris hors d'une expression (session IJ) : ces
      // demandes vont à l'IA.
      for (final phrase in [
        'donne un json de 3 cles indente et une fonction dart de 3 lignes',
        'il y a 3 cles et 2 portes',
        'resume 3 mails sur 10 recus',
        'ecris 2 phrases plus courtes',
        'un tableau de 3 colonnes et 2 lignes',
      ]) {
        expect(CalculVocal.calculer(phrase), isNull, reason: phrase);
      }
      expect(CalculVocal.calculer('3 et 4')?.valeur, 7);
      expect(CalculVocal.calculer('12 sur 4')?.valeur, 3);
    });
  });

  group('Notions techniques', () {
    test('question puis « dis-m’en plus »', () {
      expect(
        repondre('C’est quoi l’intelligence artificielle ?'),
        startsWith('L’intelligence artificielle'),
      );
      expect(repondre('Dis-m’en plus'), startsWith('La plupart des IA'));
    });
    test('le nom le plus précis l’emporte', () {
      expect(
        repondre('Explique-moi un modèle de langage'),
        startsWith('Un grand modèle de langage'),
      );
    });
    test('nom seul', () {
      expect(repondre('Flutter ?'), startsWith('Flutter est'));
    });
    test('« dis-m’en plus » sans sujet', () {
      expect(repondre('Développe'), startsWith('De quel sujet'));
    });
  });

  group('Conversations courantes', () {
    test('enchaînement sans répéter « JARVIS » (test 8)', () {
      final midi = VoiceCommandService(
        horloge: () => DateTime(2026, 10, 5, 14, 7),
      );
      String dire(String p) => midi.reponseLocale(p)!.texte;
      expect(dire('Bonjour JARVIS'), 'Bonjour. Comment puis-je vous aider ?');
      expect(
        dire('Comment vas-tu ?'),
        startsWith('Je fonctionne parfaitement.'),
      );
      expect(dire('Quelle heure est-il ?'), contains('14'));
    });
    test('salutations suivantes plus brèves', () {
      repondre('Bonsoir Jarvis');
      expect(repondre('Coucou Jarvis'), 'Bonsoir. Je vous écoute.');
    });
    test('nom, identité, capacités, système', () {
      expect(repondre('Comment tu t’appelles ?'), 'Je m’appelle JARVIS.');
      expect(repondre('Quel est ton nom ?'), 'Je m’appelle JARVIS.');
      expect(
        repondre('C’est quoi Jarvis ?'),
        'Je suis JARVIS, votre assistant.',
      );
      expect(repondre('Tu es qui ?'), 'Je suis JARVIS, votre assistant.');
      for (final p in [
        'Quelles sont tes capacités ?',
        'À quoi tu sers ?',
        'Tu sais faire quoi ?',
      ]) {
        expect(repondre(p), startsWith('Mes fonctionnalités'));
      }
      for (final p in [
        'Statut système',
        'Est-ce que tout fonctionne ?',
        'Comment va le système ?',
      ]) {
        expect(
          repondre(p),
          'Tous les systèmes disponibles sont opérationnels.',
        );
      }
    });
    test('merci et au revoir', () {
      expect(repondre('Je te remercie'), isNotEmpty);
      final nuit = service.reponseLocale('Bonne nuit Jarvis')!;
      expect(nuit.texte, 'Bonne nuit.');
      expect(nuit.terminerSession, isTrue);
      expect(service.reponseLocale('Bye Jarvis')!.texte, 'Bonne soirée.');
      expect(service.reponseLocale('À bientôt')!.texte, 'À bientôt.');
    });
    test('phrase inconnue : aucune réponse inventée', () async {
      final r = await service.traiter('Réserve-moi un billet de train');
      expect(r.texte, VoiceCommandService.reponseInconnue);
    });
  });

  group('Conversation suivie', () {
    test('du bonjour à l’au revoir, comme entre deux personnes', () {
      expect(
        repondre('Bonsoir Jarvis'),
        'Bonsoir. Comment puis-je vous aider ?',
      );
      expect(
        repondre('Comment ça va ?'),
        'Je fonctionne parfaitement. Merci. Et vous, comment allez-vous ?',
      );
      expect(repondre('Très bien et toi ?'), startsWith('Ravi de l’entendre.'));
      expect(
        repondre('Tu connais mon prénom ?'),
        contains('Comment vous appelez-vous'),
      );
      expect(
        repondre('Jordi'),
        'Enchanté, Jordi. Que puis-je faire pour vous ?',
      );
      expect(repondre('Combien font 6 fois 7 ?'), '6 fois 7 égale 42.');
      expect(repondre('Tu peux répéter ?'), 'Je disais : 6 fois 7 égale 42.');
      expect(repondre('Comment je m’appelle ?'), 'Vous vous appelez Jordi.');
      expect(repondre('Merci'), isNotEmpty);
      final fin = service.reponseLocale('Au revoir')!;
      expect(fin.texte, 'À bientôt, Jordi.');
      expect(fin.terminerSession, isTrue);
    });
    test('prénom donné spontanément, avec accents', () {
      expect(
        repondre('Je m’appelle Héloïse'),
        startsWith('Enchanté, Héloïse.'),
      );
      expect(
        repondre('Salut'),
        'Bonsoir Héloïse. Comment puis-je vous aider ?',
      );
    });
    test('humeur négative', () {
      repondre('Ça va ?');
      expect(
        repondre('Pas très bien, je suis fatigué'),
        startsWith('Je suis désolé'),
      );
    });
    test('« pas mal » est positif', () {
      repondre('Comment vas-tu ?');
      expect(repondre('Pas mal'), startsWith('Ravi'));
    });
  });

  group('Commande inconnue', () {
    test('aucune réponse inventée', () async {
      expect(service.reponseLocale('Commande une pizza'), isNull);
      expect(service.reponseLocale('savane'), isNull);
      final r = await service.traiter('Commande une pizza');
      expect(r.texte, VoiceCommandService.reponseInconnue);
      expect(r.source, SourceReponse.inconnue);
    });
    test(
      'une future IA prend le relais seulement si rien n’est local',
      () async {
        final avecIa = VoiceCommandService(
          horloge: () => soir,
          assistantDistant: _IaFactice(),
        );
        expect(
          (await avecIa.traiter('Commande une pizza')).source,
          SourceReponse.distante,
        );
        expect(
          (await avecIa.traiter('Quelle heure est-il')).source,
          SourceReponse.locale,
        );
      },
    );
  });
}

class _IaFactice implements AssistantDistant {
  @override
  Future<String> repondre(String phrase) async => 'Réponse de l’IA';
}
