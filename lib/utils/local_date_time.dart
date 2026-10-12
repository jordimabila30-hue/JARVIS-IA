/// Formulations françaises de l'heure et de la date, à partir de l'horloge
/// de l'appareil. Aucune dépendance (pas de package intl).
library;

const _jours = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// « Bonjour » de 5 h à 18 h, « Bonsoir » sinon.
String salutation(DateTime moment) =>
    moment.hour >= 5 && moment.hour < 18 ? 'Bonjour' : 'Bonsoir';

/// Exemple : « Il est 19 heures 24. », « Il est midi. », « Il est 1 heure 05. »
String heureEnFrancais(DateTime moment) {
  final h = moment.hour;
  final m = moment.minute;
  final String heures;
  if (h == 0) {
    heures = 'minuit';
  } else if (h == 12) {
    heures = 'midi';
  } else {
    heures = '$h ${h == 1 ? 'heure' : 'heures'}';
  }
  if (m == 0) return 'Il est $heures.';
  return 'Il est $heures ${m.toString().padLeft(2, '0')}.';
}

/// Exemple : « Nous sommes le dimanche 4 octobre 2026. »
String dateEnFrancais(DateTime moment) {
  final jour = _jours[moment.weekday - 1];
  final numero = moment.day == 1 ? '1er' : '${moment.day}';
  final mois = _mois[moment.month - 1];
  return 'Nous sommes le $jour $numero $mois ${moment.year}.';
}

/// Exemple : « octobre ».
String moisEnFrancais(DateTime moment) => _mois[moment.month - 1];

/// Exemple : « dimanche ».
String jourDeLaSemaine(DateTime moment) => _jours[moment.weekday - 1];

/// Heure d'un message : « 13:08 », « 09:05 » (heure locale, 24 h).
String heureCourte(DateTime moment) {
  final local = moment.toLocal();
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${deux(local.hour)}:${deux(local.minute)}';
}

const _joursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

/// Date courte d'une liste de conversations : heure aujourd'hui, « Hier »,
/// jour de la semaine (moins d'une semaine), sinon « 12/09 » (« 12/09/25 »
/// une autre année).
String dateCourte(DateTime moment, DateTime maintenant) {
  final m = moment.toLocal();
  final n = maintenant.toLocal();
  final jour = DateTime(m.year, m.month, m.day);
  final aujourdhui = DateTime(n.year, n.month, n.day);
  final ecart = aujourdhui.difference(jour).inDays;
  String deux(int v) => v.toString().padLeft(2, '0');
  if (ecart <= 0) return heureCourte(m);
  if (ecart == 1) return 'Hier';
  if (ecart < 7) return _joursCourts[m.weekday - 1];
  final base = '${deux(m.day)}/${deux(m.month)}';
  return m.year == n.year ? base : '$base/${deux(m.year % 100)}';
}
