// Inscription et liens reçus par e-mail : adresse mal formée arrêtée avant
// l'envoi, refus du serveur expliqué, retour des liens dans l'application.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/authentification/resultat_auth.dart';
import 'package:ia_jarvis/services/authentification/auth_repository_supabase.dart';
import 'package:ia_jarvis/services/authentification/config_auth.dart';
import 'package:ia_jarvis/services/authentification/validation_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const v = ValidationAuth();

  test('adresse e-mail : point final ou « .. » refusés avant l\'envoi', () {
    for (final mauvaise in [
      'messie@gmail.com.',
      'messie@gmail..com',
      'messie@.gmail.com',
      'messie@gmail',
    ]) {
      expect(v.email(mauvaise), 'Adresse e-mail invalide.', reason: mauvaise);
    }
    for (final bonne in [
      'messie@gmail.com',
      'jordi.mabila@2031.icam.fr',
      '  ada@exemple.co.uk ',
    ]) {
      expect(v.email(bonne), isNull, reason: bonne);
    }
  });

  test('adresse refusée par Supabase : message précis', () {
    final e = AuthRepositorySupabase.erreurDe(
      const AuthException(
        'Email address is invalid',
        statusCode: '400',
        code: 'email_address_invalid',
      ),
    );
    expect(e.type, TypeErreurAuth.donneesRefusees);
    expect(e.message, contains('adresse e-mail est refusée'));
  });

  test('liens des e-mails : jarvis://auth sur téléphone, rien sur Windows', () {
    const c = ConfigAuth();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(c.redirectionEmails, 'jarvis://auth');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(c.redirectionEmails, 'jarvis://auth');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(c.redirectionEmails, isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
