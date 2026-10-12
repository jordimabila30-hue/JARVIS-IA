/// Import WhatsApp — étape 2 : la conversation reconstruite à partir d'un
/// export (TXT, ou TXT trouvé dans un ZIP). Tout vient du fichier lu :
/// rien n'est inventé, rien n'est envoyé hors de l'appareil.
library;

/// Nature d'un message.
enum TypeMessageWhatsApp {
  /// Message écrit par un participant.
  texte,

  /// Pièce jointe (photo, vocal…) : seule sa trace textuelle est gardée.
  media,

  /// « Ce message a été supprimé ».
  supprime,

  /// Événement de WhatsApp (chiffrement, ajout au groupe…) : sans auteur.
  systeme,
}

/// Type d'un média, quand l'export permet de le savoir.
enum TypeMediaWhatsApp {
  image('Photo'),
  video('Vidéo'),
  audio('Audio'),
  vocal('Message vocal'),
  autocollant('Autocollant'),
  gif('GIF'),
  document('Document'),
  contact('Contact'),
  inconnu('Média');

  const TypeMediaWhatsApp(this.libelle);
  final String libelle;
}

/// Ordre des nombres dans les dates de l'export (« 11/10/2026 »).
enum OrdreDate { jourMoisAnnee, moisJourAnnee, anneeMoisJour }

/// Un message de l'export, dans l'ordre d'origine.
class MessageWhatsApp {
  const MessageWhatsApp({
    required this.ordre,
    required this.auteur,
    required this.date,
    required this.dateBrute,
    required this.texte,
    required this.type,
    this.typeMedia,
    this.nomFichierMedia,
  });

  /// Position dans l'export (0, 1, 2…) : l'ordre d'origine.
  final int ordre;

  /// Identifiant, stable pour un même export.
  String get id => 'm$ordre';

  /// Nom tel qu'écrit dans l'export ; null pour un message système.
  final String? auteur;

  /// Date et heure interprétées ; null si l'interprétation est impossible.
  final DateTime? date;

  /// Date et heure telles qu'écrites dans l'export (jamais perdues).
  final String dateBrute;

  /// Texte exact, lignes suivantes comprises.
  final String texte;

  final TypeMessageWhatsApp type;
  final TypeMediaWhatsApp? typeMedia;

  /// Nom du fichier joint quand l'export le donne (« IMG-…jpg »).
  final String? nomFichierMedia;

  /// Empreinte pour repérer un même message dans un futur réimport
  /// (étape 8) : date brute, auteur et texte.
  String get empreinte {
    final cle = '$dateBrute\u0000${auteur ?? ''}\u0000$texte';
    return '${_fnv1a(cle, 0x811c9dc5)}${_fnv1a(cle, 0x01000193)}';
  }

  /// FNV-1a 32 bits, exact aussi sur le Web (entiers JavaScript).
  static String _fnv1a(String s, int graine) {
    var h = graine;
    for (final c in s.codeUnits) {
      h = (h ^ c) & 0xFFFFFFFF;
      // h × 16777619 = h × 403 + (h << 24), sans dépasser 2^53.
      h = (h * 403 + ((h << 24) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

/// Un auteur de la conversation et son nombre de messages.
class ParticipantWhatsApp {
  const ParticipantWhatsApp({required this.nom, required this.messages});
  final String nom;
  final int messages;
}

/// La conversation reconstruite.
class ConversationWhatsApp {
  const ConversationWhatsApp({
    required this.titre,
    required this.messages,
    required this.participants,
    required this.ordreDate,
    required this.dateIncertaine,
    required this.lignesNonRattachees,
    required this.nombreLignesNonRattachees,
    required this.nomFichier,
  });

  /// Nom du contact ou du groupe (d'après le nom du fichier, sinon les
  /// participants).
  final String titre;

  final List<MessageWhatsApp> messages;

  /// Auteurs réels, du plus actif au moins actif.
  final List<ParticipantWhatsApp> participants;

  final OrdreDate ordreDate;

  /// Jour et mois indiscernables dans tout l'export (aucun nombre > 12,
  /// ordre chronologique identique) : l'ordre retenu est une supposition.
  final bool dateIncertaine;

  /// Lignes situées avant le premier message reconnu (jamais rattachées
  /// à un message, mais comptées : rien n'est perdu en silence).
  /// (Les 100 premières ; [nombreLignesNonRattachees] les compte toutes.)
  final List<String> lignesNonRattachees;
  final int nombreLignesNonRattachees;

  /// Fichier lu (le TXT, ou le TXT dans l'archive).
  final String nomFichier;

  int get nombreMedias =>
      messages.where((m) => m.type == TypeMessageWhatsApp.media).length;

  DateTime? get debut {
    for (final m in messages) {
      if (m.date != null) return m.date;
    }
    return null;
  }

  DateTime? get fin {
    for (final m in messages.reversed) {
      if (m.date != null) return m.date;
    }
    return null;
  }

  /// Plus de deux auteurs : conversation de groupe.
  bool get estGroupe => participants.length > 2;
}
