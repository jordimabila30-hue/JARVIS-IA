/// Formulations françaises de l'utilisation (jauges, réinitialisations).
/// Les heures sont données dans le fuseau de l'appareil, à partir des
/// instants fournis par le serveur.
library;

import 'local_date_time.dart';

/// « 33 000 », « 1 250 000 » (espace fine insécable).
String nombreGroupe(int n) {
  final signe = n < 0 ? '-' : '';
  final chiffres = n.abs().toString();
  final groupes = <String>[];
  for (var fin = chiffres.length; fin > 0; fin -= 3) {
    groupes.insert(0, chiffres.substring(fin - 3 < 0 ? 0 : fin - 3, fin));
  }
  return '$signe${groupes.join(' ')}';
}

/// « 2 h 14 min », « 45 min », « moins d'une minute ».
String dureeRestante(Duration d) {
  if (d.inMinutes < 1) return 'moins d’une minute';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  if (h >= 24) {
    final j = d.inDays;
    final hr = h % 24;
    return hr == 0 ? '$j j' : '$j j $hr h';
  }
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// « aujourd'hui à 15:00 », « demain à 02:00 », « jeudi 19 octobre à 02:00 »
/// (heure locale de l'appareil).
String momentLocal(DateTime instant, DateTime maintenant) {
  final l = instant.toLocal();
  final m = maintenant.toLocal();
  final jour = DateTime(l.year, l.month, l.day);
  final aujourdhui = DateTime(m.year, m.month, m.day);
  final ecart = jour.difference(aujourdhui).inDays;
  final heure = heureCourte(l);
  return switch (ecart) {
    0 => 'aujourd’hui à $heure',
    1 => 'demain à $heure',
    _ => '${jourDeLaSemaine(l)} ${l.day} ${moisEnFrancais(l)} à $heure',
  };
}

/// « Réinitialisation aujourd'hui à 15:00 (dans 2 h 14 min). »
String repriseLimite(DateTime instant, DateTime maintenant) {
  final reste = instant.difference(maintenant);
  if (reste.isNegative) return 'La limite est déjà réinitialisée.';
  return 'Réinitialisation ${momentLocal(instant, maintenant)} '
      '(dans ${dureeRestante(reste)}).';
}
