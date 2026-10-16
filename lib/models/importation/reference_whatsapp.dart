import '../../utils/local_date_time.dart';
import 'propositions_reponse.dart';

/// Message WhatsApp original sur lequel s'appuie une réponse de JARVIS.
///
/// Reçu du serveur, jamais construit sur l'appareil à partir du texte de
/// l'IA : le serveur a vérifié que le message existe, appartient au compte
/// et correspond à ce que la réponse en dit ; auteur, date et texte sont
/// ceux enregistrés dans Supabase (`context_messages`).
class ReferenceWhatsApp {
  const ReferenceWhatsApp({
    required this.contexte,
    required this.idMessage,
    required this.ordre,
    required this.auteur,
    required this.estMoi,
    required this.extrait,
    required this.date,
    required this.dateBrute,
    required this.libelleDate,
    required this.datesIncertaines,
    required this.contact,
    required this.moi,
    required this.rang,
    required this.position,
    this.ajoute = false,
  });

  /// Phase 5 : message collé par l'utilisateur (non vérifié sur WhatsApp).
  final bool ajoute;

  /// Pièce jointe (contexte WhatsApp) du message.
  final String contexte;

  /// `context_messages.id`.
  final String? idMessage;

  /// Rang du message dans la pièce jointe (0, 1, 2…) : sert à ouvrir la
  /// bonne page de « Voir les messages ».
  final int ordre;

  /// Auteur enregistré ; null : événement WhatsApp.
  final String? auteur;

  /// Message de l'utilisateur (« Vous êtes : » confirmé).
  final bool estMoi;
  final String extrait;

  /// Heure locale de l'export (sans fuseau) ; null si illisible.
  final DateTime? date;
  final String dateBrute;

  /// Date telle que le serveur l'a donnée au modèle (« 12/10/2026 18:42 »).
  final String libelleDate;
  final bool datesIncertaines;

  /// Nom de la discussion et utilisateur confirmé (en-tête de « Voir les
  /// messages » quand la carte de la pièce jointe n'est pas chargée).
  final String contact;
  final String? moi;

  /// Ordre d'affichage sous la réponse.
  final int rang;

  /// Position dans le texte de la réponse (fin de la phrase concernée).
  final int position;

  /// « 12 octobre 2026 · 18:42 » ; date incertaine ou illisible : telle
  /// qu'écrite dans l'export, sans réinterprétation.
  String get dateAffichee {
    final d = date;
    if (d == null || datesIncertaines) {
      return dateBrute.isNotEmpty ? dateBrute : 'Date inconnue';
    }
    final h =
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final jour = d.day == 1 ? '1er' : '${d.day}';
    return '$jour ${moisEnFrancais(d)} ${d.year} · $h';
  }

  /// Null si les données sont incomplètes (jamais une référence approximative).
  static ReferenceWhatsApp? depuisJson(Map<String, dynamic> j) {
    final contexte = j['context_id'];
    final ordre = j['message_order'];
    if (contexte is! String || ordre is! num) return null;
    final date = j['sent_at'];
    return ReferenceWhatsApp(
      contexte: contexte,
      idMessage: j['context_message_id'] as String?,
      ordre: ordre.toInt(),
      auteur: j['author'] as String?,
      estMoi: j['is_me'] == true,
      extrait: j['excerpt'] as String? ?? '',
      date: date is String ? DateTime.tryParse(date.replaceAll('Z', '')) : null,
      dateBrute: j['sent_at_raw'] as String? ?? '',
      libelleDate: j['date_label'] as String? ?? '',
      datesIncertaines: j['dates_uncertain'] == true,
      contact: j['contact_name'] as String? ?? 'WhatsApp',
      moi: j['current_user_name'] as String?,
      rang: (j['rang'] as num?)?.toInt() ?? 0,
      position: (j['position'] as num?)?.toInt() ?? 0,
      ajoute: j['origin'] is String && j['origin'] != 'export',
    );
  }

  static List<ReferenceWhatsApp> listeDepuisJson(Object? liste) => [
    if (liste is List)
      for (final e in liste)
        if (e is Map<String, dynamic>) ?depuisJson(e),
  ];
}

/// Ce que le serveur joint à une réponse de JARVIS dans un chat WhatsApp :
/// références vérifiées, avertissement éventuel (attribution rectifiée,
/// référence refusée…) et propositions de réponse (phase 3).
class ReferencesReponse {
  const ReferencesReponse(this.references, {this.note, this.propositions});

  final List<ReferenceWhatsApp> references;
  final String? note;
  final PropositionsReponse? propositions;

  static const vide = ReferencesReponse([]);

  bool get estVide =>
      references.isEmpty && note == null && propositions == null;

  ReferencesReponse avecPropositions(PropositionsReponse? p) =>
      ReferencesReponse(references, note: note, propositions: p);
}
