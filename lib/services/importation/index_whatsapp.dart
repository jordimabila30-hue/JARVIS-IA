import 'dart:typed_data';

import '../../models/importation/conversation_whatsapp.dart';
import '../../models/importation/filtre_whatsapp.dart';

/// Index d'une conversation lue, construit une fois : il répond aux
/// filtres sans parcourir toute la conversation (recherche dichotomique
/// dans l'ordre chronologique) et donne au calendrier le nombre de
/// messages de chaque jour.
///
/// Seuls les messages des participants sont sélectionnables : les
/// événements de WhatsApp (chiffrement, ajouts au groupe…) n'en sont pas.
/// Une « position » est le rang d'un message sélectionnable dans l'ordre
/// d'origine ; elle ne dépend jamais de l'affichage.
class IndexWhatsApp {
  IndexWhatsApp(this.conversation)
    : messages = [
        for (final m in conversation.messages)
          if (m.type != TypeMessageWhatsApp.systeme) m,
      ] {
    final n = messages.length;
    var dates = 0;
    for (var p = 0; p < n; p++) {
      final m = messages[p];
      _positions[m.id] = p;
      final d = m.date;
      if (d == null) continue;
      dates++;
      final cle = cleJour(d);
      _parJour[cle] = (_parJour[cle] ?? 0) + 1;
    }
    nombreSansDate = n - dates;
    // Ordre chronologique (à égalité, ordre d'origine). Un export est
    // presque toujours déjà dans l'ordre : le tri n'est fait que sinon.
    final chrono = Int32List(dates);
    var k = 0;
    var trie = true;
    int? precedent;
    for (var p = 0; p < n; p++) {
      final d = messages[p].date;
      if (d == null) continue;
      final t = d.microsecondsSinceEpoch;
      if (precedent != null && t < precedent) trie = false;
      precedent = t;
      chrono[k++] = p;
    }
    if (!trie) {
      final liste = chrono.toList()
        ..sort((a, b) {
          final c = _temps(a).compareTo(_temps(b));
          return c != 0 ? c : a.compareTo(b);
        });
      chrono.setAll(0, liste);
    }
    _chrono = chrono;
    _instants = Float64List(dates);
    for (var i = 0; i < dates; i++) {
      _instants[i] = _temps(chrono[i]).toDouble();
    }
    final jours = _parJour.keys.toList()..sort();
    joursAvecMessages = jours;
  }

  final ConversationWhatsApp conversation;

  /// Messages sélectionnables, dans l'ordre d'origine.
  final List<MessageWhatsApp> messages;

  final _positions = <String, int>{};
  final _parJour = <int, int>{};
  late final Int32List _chrono;
  late final Float64List _instants;

  /// Messages sans date reconnue : jamais rattachés à un jour, choisis à
  /// la main seulement.
  late final int nombreSansDate;

  /// Jours ayant des messages (clés `aaaammjj`), croissants.
  late final List<int> joursAvecMessages;

  int get nombre => messages.length;

  int _temps(int position) => messages[position].date!.microsecondsSinceEpoch;

  /// Position d'un message (null : inconnu ou non sélectionnable).
  int? position(String id) => _positions[id];

  static int cleJour(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
  static DateTime jourDeCle(int cle) =>
      DateTime(cle ~/ 10000, cle ~/ 100 % 100, cle % 100);

  /// Nombre de messages datés de ce jour.
  int nombreLeJour(DateTime jour) => _parJour[cleJour(jour)] ?? 0;

  DateTime? get premierJour =>
      joursAvecMessages.isEmpty ? null : jourDeCle(joursAvecMessages.first);
  DateTime? get dernierJour =>
      joursAvecMessages.isEmpty ? null : jourDeCle(joursAvecMessages.last);

  /// Années ayant des messages, croissantes.
  List<int> get annees =>
      <int>{for (final c in joursAvecMessages) c ~/ 10000}.toList();

  /// Nombre de messages de chaque jour d'un mois (jour → nombre).
  Map<int, int> joursDuMois(int annee, int mois) {
    final debut = annee * 10000 + mois * 100;
    final r = <int, int>{};
    var i = _premierIndexCle(debut);
    while (i < joursAvecMessages.length && joursAvecMessages[i] < debut + 100) {
      final c = joursAvecMessages[i];
      r[c % 100] = _parJour[c]!;
      i++;
    }
    return r;
  }

  /// Le mois a-t-il au moins un message ?
  bool moisAvecMessages(int annee, int mois) {
    final debut = annee * 10000 + mois * 100;
    final i = _premierIndexCle(debut);
    return i < joursAvecMessages.length && joursAvecMessages[i] < debut + 100;
  }

  int _premierIndexCle(int cle) {
    var bas = 0, haut = joursAvecMessages.length;
    while (bas < haut) {
      final m = (bas + haut) >> 1;
      if (joursAvecMessages[m] < cle) {
        bas = m + 1;
      } else {
        haut = m;
      }
    }
    return bas;
  }

  /// Premier rang chronologique dont l'instant est ≥ [t].
  int _premierRangDes(DateTime t) {
    final v = t.microsecondsSinceEpoch.toDouble();
    var bas = 0, haut = _instants.length;
    while (bas < haut) {
      final m = (bas + haut) >> 1;
      if (_instants[m] < v) {
        bas = m + 1;
      } else {
        haut = m;
      }
    }
    return bas;
  }

  /// Positions des messages datés dans [debut, finExclue[, dans l'ordre
  /// d'origine.
  List<int> entre(DateTime debut, DateTime finExclue) {
    if (!finExclue.isAfter(debut)) return const [];
    final a = _premierRangDes(debut), b = _premierRangDes(finExclue);
    return Int32List.sublistView(_chrono, a, b).toList()..sort();
  }

  /// Les messages correspondant à [filtre] (positions croissantes).
  /// [maintenant] : date locale de l'appareil (jours relatifs).
  List<int> resultat(FiltreWhatsApp filtre, DateTime maintenant) {
    switch (filtre) {
      case FiltreJourRelatif(:final jour):
        final n = maintenant;
        final (debut, finExclue) = switch (jour) {
          JourRelatif.aujourdhui => (
            DateTime(n.year, n.month, n.day),
            DateTime(n.year, n.month, n.day + 1),
          ),
          JourRelatif.hier => (
            DateTime(n.year, n.month, n.day - 1),
            DateTime(n.year, n.month, n.day),
          ),
          JourRelatif.septDerniersJours => (
            DateTime(n.year, n.month, n.day - 6),
            DateTime(n.year, n.month, n.day + 1),
          ),
        };
        return entre(debut, finExclue);
      case FiltreDerniers(:final nombre):
        final debut = (messages.length - nombre).clamp(0, messages.length);
        return [for (var p = debut; p < messages.length; p++) p];
      case FiltrePeriode():
        if (!filtre.valide) return const [];
        return entre(filtre.debut, filtre.finExclue);
      case FiltrePlage(:final premierId, :final dernierId):
        final a = _positions[premierId], b = _positions[dernierId];
        if (a == null || b == null) return const [];
        final (bas, haut) = a <= b ? (a, b) : (b, a);
        return [for (var p = bas; p <= haut; p++) p];
    }
  }

  /// Nombre de messages d'une période (sans construire la liste).
  int nombreEntre(DateTime debut, DateTime finExclue) {
    if (!finExclue.isAfter(debut)) return 0;
    return _premierRangDes(finExclue) - _premierRangDes(debut);
  }
}
