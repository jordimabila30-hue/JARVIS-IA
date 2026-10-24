import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'importation/pont_android_importation.dart';

/// Messageries ouvertes depuis le bouton « + » : l'application si elle est
/// installée (Android), sinon son site. Rien n'est lu ni envoyé.
enum Messagerie {
  instagram(
    'Instagram',
    'com.instagram.android',
    'https://www.instagram.com/direct/inbox/',
  ),
  messenger('Messenger', 'com.facebook.orca', 'https://www.messenger.com/'),
  mail('Mail', 'mail', 'https://mail.google.com/');

  const Messagerie(this.libelle, this.cibleAndroid, this.site);

  final String libelle;

  /// Nom du paquet Android (ou `mail` : l'appli e-mail par défaut).
  final String cibleAndroid;

  /// Repli sur le Web, Windows ou sans l'application.
  final String site;
}

class OuvertureMessageries {
  OuvertureMessageries({
    Future<bool> Function(String cible)? application,
    Future<bool> Function(Uri site)? navigateur,
    bool? android,
  }) : _application =
           application ?? PontAndroidImportation.instance.ouvrirApplication,
       _navigateur =
           navigateur ??
           ((site) => launchUrl(
             site,
             mode: LaunchMode.externalApplication,
             webOnlyWindowName: '_blank',
           )),
       _android =
           android ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final Future<bool> Function(String cible) _application;
  final Future<bool> Function(Uri site) _navigateur;
  final bool _android;

  /// true : l'application ou le site s'est ouvert.
  Future<bool> ouvrir(Messagerie m) async {
    if (_android && await _application(m.cibleAndroid)) return true;
    try {
      return await _navigateur(Uri.parse(m.site));
    } catch (_) {
      return false;
    }
  }
}
