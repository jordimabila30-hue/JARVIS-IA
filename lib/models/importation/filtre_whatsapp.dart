/// Import WhatsApp — étape 3 : les filtres de la conversation lue, et les
/// messages choisis remis à l'enregistrement (interface 3). Tout reste sur
/// l'appareil.
library;

import 'conversation_whatsapp.dart';

/// Les deux façons de choisir.
enum ModeFiltrage { periode, messages }

/// Un filtre : il donne les messages « correspondants », que la sélection
/// coche ensuite (l'utilisateur peut en décocher).
sealed class FiltreWhatsApp {
  const FiltreWhatsApp();
}

/// Jours relatifs à la date locale de l'appareil.
enum JourRelatif {
  aujourdhui('Aujourd’hui'),
  hier('Hier'),
  septDerniersJours('7 derniers jours');

  const JourRelatif(this.libelle);
  final String libelle;
}

/// Aujourd'hui, hier, ou les 7 derniers jours (aujourd'hui compris).
final class FiltreJourRelatif extends FiltreWhatsApp {
  const FiltreJourRelatif(this.jour);
  final JourRelatif jour;

  @override
  bool operator ==(Object other) =>
      other is FiltreJourRelatif && other.jour == jour;
  @override
  int get hashCode => jour.hashCode;
}

/// Les [nombre] derniers messages de l'export (ordre d'origine).
final class FiltreDerniers extends FiltreWhatsApp {
  const FiltreDerniers(this.nombre);
  final int nombre;

  static const choix = [10, 25, 50, 100];

  @override
  bool operator ==(Object other) =>
      other is FiltreDerniers && other.nombre == nombre;
  @override
  int get hashCode => nombre.hashCode;
}

/// Période personnalisée, à la minute près, bornes comprises : un message
/// de 14:30:45 appartient à une période qui finit à 14:30 (les secondes
/// n'excluent rien).
final class FiltrePeriode extends FiltreWhatsApp {
  FiltrePeriode(DateTime debut, DateTime fin)
    : debut = aLaMinute(debut),
      fin = aLaMinute(fin);

  /// Un jour entier (00:00 – 23:59).
  factory FiltrePeriode.jour(DateTime jour) => FiltrePeriode(
    DateTime(jour.year, jour.month, jour.day),
    DateTime(jour.year, jour.month, jour.day, 23, 59),
  );

  /// Des jours entiers, du premier au dernier.
  factory FiltrePeriode.jours(DateTime a, DateTime b) {
    final (debut, fin) = a.isAfter(b) ? (b, a) : (a, b);
    return FiltrePeriode(
      DateTime(debut.year, debut.month, debut.day),
      DateTime(fin.year, fin.month, fin.day, 23, 59),
    );
  }

  final DateTime debut;
  final DateTime fin;

  /// La fin n'est pas avant le début.
  bool get valide => !fin.isBefore(debut);

  /// Borne exclue : la minute qui suit la fin.
  DateTime get finExclue =>
      DateTime(fin.year, fin.month, fin.day, fin.hour, fin.minute + 1);

  bool contient(DateTime d) => !d.isBefore(debut) && d.isBefore(finExclue);

  /// Exactement un jour entier ?
  bool get estJourEntier =>
      debut.year == fin.year &&
      debut.month == fin.month &&
      debut.day == fin.day &&
      debut.hour == 0 &&
      debut.minute == 0 &&
      fin.hour == 23 &&
      fin.minute == 59;

  static DateTime aLaMinute(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute);

  @override
  bool operator ==(Object other) =>
      other is FiltrePeriode && other.debut == debut && other.fin == fin;
  @override
  int get hashCode => Object.hash(debut, fin);
}

/// Mode « Par messages » : du premier au dernier message désignés, selon
/// l'ordre réel de l'export (bornes comprises, dans un sens ou l'autre).
final class FiltrePlage extends FiltreWhatsApp {
  const FiltrePlage(this.premierId, this.dernierId);
  final String premierId;
  final String dernierId;

  @override
  bool operator ==(Object other) =>
      other is FiltrePlage &&
      other.premierId == premierId &&
      other.dernierId == dernierId;
  @override
  int get hashCode => Object.hash(premierId, dernierId);
}

/// Messages choisis, prêts pour l'enregistrement (interface 3) : rien
/// n'est encore enregistré. Les messages gardent l'ordre de l'export et
/// tout ce que la lecture en a tiré (auteur, date réelle et brute, texte,
/// type, média).
class MessagesChoisisWhatsApp {
  const MessagesChoisisWhatsApp({
    required this.conversationSource,
    required this.titre,
    required this.nomFichier,
    required this.messages,
    required this.dateIncertaine,
  });

  /// [ConversationWhatsApp.identifiant] de la conversation lue.
  final String conversationSource;
  final String titre;
  final String nomFichier;

  /// Dans l'ordre d'origine.
  final List<MessageWhatsApp> messages;

  /// Jour et mois des dates supposés (voir [ConversationWhatsApp]).
  final bool dateIncertaine;

  /// Identifiants stables (`m<ordre>`), dans l'ordre.
  List<String> get ids => [for (final m in messages) m.id];

  /// Auteurs présents, dans l'ordre d'apparition.
  List<String> get auteurs => {for (final m in messages) ?m.auteur}.toList();

  int get nombreSansDate => messages.where((m) => m.date == null).length;
}
