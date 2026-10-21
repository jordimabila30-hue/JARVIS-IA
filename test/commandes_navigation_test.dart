// Commandes de navigation locales (sans IA) : plusieurs formulations, et
// aucune activation accidentelle sur une vraie question.

import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/applications_externes.dart';
import 'package:ia_jarvis/services/conversation/commandes_navigation.dart';

void main() {
  test('formulations naturelles reconnues', () {
    const attendu = {
      'Ouvre les paramètres': CommandeNavigation.ouvrirParametres,
      'JARVIS, ouvre les réglages s’il te plaît':
          CommandeNavigation.ouvrirParametres,
      'Affiche les outils': CommandeNavigation.ouvrirOutils,
      'Ouvre l’agenda': CommandeNavigation.ouvrirAgenda,
      'Montre-moi mes conversations': CommandeNavigation.afficherConversations,
      'Nouvelle conversation': CommandeNavigation.nouvelleConversation,
      'Tu peux ouvrir Instagram ?': CommandeNavigation.ouvrirInstagram,
      'Lance Messenger': CommandeNavigation.ouvrirMessenger,
      'ouvre WhatsApp': CommandeNavigation.ouvrirWhatsApp,
      'Ouvre mes mails': CommandeNavigation.ouvrirMail,
      'Retour au chat écrit': CommandeNavigation.retourChatEcrit,
      'Arrête de parler': CommandeNavigation.arreterParole,
    };
    attendu.forEach((phrase, commande) {
      expect(CommandesNavigation.detecter(phrase), commande, reason: phrase);
    });
  });

  test('jamais sur une vraie question ou une demande plus longue', () {
    for (final phrase in [
      'Comment ouvrir Instagram sur ordinateur ?',
      'Résume mes mails',
      'Parle-moi des paramètres de confidentialité de WhatsApp',
      'Pourquoi mon agenda est vide ?',
      'Elle m’a dit que j’étais drôle, je réponds quoi ?',
      'Ouvre les paramètres de mon téléphone et active le Bluetooth',
      '',
    ]) {
      expect(CommandesNavigation.detecter(phrase), isNull, reason: phrase);
    }
  });

  test('ouvrir une application : aucune promesse d’accès aux messages', () {
    expect(
      CommandeNavigation.ouvrirMail.application,
      ApplicationExterne.mail,
    );
    expect(ApplicationExterne.instagram.web, startsWith('https://'));
    expect(ApplicationExterne.messenger.web, startsWith('https://'));
    expect(ApplicationExterne.mail.web, 'mailto:');
  });
}
