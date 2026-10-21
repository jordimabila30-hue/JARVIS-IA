import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'importation/pont_android_importation.dart';

/// Applications que JARVIS sait OUVRIR (bouton « + », commandes locales).
/// Ouvrir seulement : aucun accès aux messages, aucune connexion.
enum ApplicationExterne {
  whatsapp('WhatsApp', [
    'com.whatsapp',
    'com.whatsapp.w4b',
  ], 'https://web.whatsapp.com/'),
  instagram('Instagram', [
    'com.instagram.android',
  ], 'https://www.instagram.com/direct/inbox/'),
  messenger('Messenger', [
    'com.facebook.orca',
    'com.facebook.mlite',
  ], 'https://www.messenger.com/'),
  // Mail : l'application de messagerie choisie par le système (`mailto:`),
  // Gmail en premier sur Android s'il est installé.
  mail('Mail', ['com.google.android.gm'], 'mailto:');

  const ApplicationExterne(this.nom, this.paquets, this.web);

  final String nom;

  /// Paquets Android, par ordre de préférence.
  final List<String> paquets;

  /// Destination de secours (version Web officielle, ou composeur d'e-mail).
  final String web;

  /// Message affiché si rien n'a pu s'ouvrir.
  String get echec => 'Impossible d’ouvrir $nom sur cet appareil.';
}

/// Ouvre une [ApplicationExterne] : l'application installée (Android),
/// sinon sa destination Web (ou le composeur d'e-mail). Faux si rien n'a
/// pu s'ouvrir. Remplaçable dans les tests.
typedef OuvrirApplication = Future<bool> Function(ApplicationExterne app);

Future<bool> ouvrirApplicationExterne(ApplicationExterne app) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (await PontAndroidImportation.instance.ouvrirApplication(app.paquets)) {
      return true;
    }
  }
  try {
    return await launchUrl(
      Uri.parse(app.web),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    return false;
  }
}
