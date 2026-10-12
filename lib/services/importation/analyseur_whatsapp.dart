import '../../models/importation/conversation_whatsapp.dart';

/// Lecture des lignes d'un export WhatsApp (Android ou iOS, plusieurs
/// langues), ligne par ligne : la mémoire ne contient que les messages.
///
/// Déterministe et local : aucune IA ne reconstruit les messages.
/// Formats reconnus (exemples) :
///   11/10/2026, 14:30 - Tony Stark: Bonjour !          (Android)
///   11/10/2026 14:30 - Tony Stark: Bonjour !           (Android, fr)
///   10/11/26, 2:30 PM - Tony Stark: Hi!                (Android, en-US)
///   [11/10/2026, 14:30:12] Tony Stark: Bonjour !       (iOS)
///   [10/11/26, 2:30:12 PM] Tony Stark: Hi!             (iOS, en-US)
///   11.10.26, 14:30 - Tony Stark: Hallo                (Android, de)
///   2026-10-11, 14:30 - Tony Stark: Hello              (ISO)
/// Une ligne sans en-tête prolonge le message précédent (message sur
/// plusieurs lignes).
class AnalyseurWhatsApp {
  final _bruts = <_Brut>[];
  _Brut? _courant;
  final _avantPremier = <String>[];
  int _nombreAvantPremier = 0;

  /// Lignes ajoutées jusqu'ici (pour la progression).
  int get lignes => _lignes;
  int _lignes = 0;

  /// Messages reconnus jusqu'ici.
  int get messages => _bruts.length;

  static const _maxLignesGardees = 100;

  void ajouterLigne(String ligne) {
    _lignes++;
    final entete = _lireEntete(ligne);
    if (entete == null) {
      final courant = _courant;
      if (courant != null) {
        courant.texte.write('\n');
        courant.texte.write(ligne);
      } else if (ligne.trim().isNotEmpty) {
        _nombreAvantPremier++;
        if (_avantPremier.length < _maxLignesGardees) _avantPremier.add(ligne);
      }
      return;
    }
    final brut = entete;
    _bruts.add(brut);
    _courant = brut;
  }

  /// Fin de lecture : dates interprétées, types reconnus, participants.
  ConversationWhatsApp terminer({
    required String nomFichier,
    String? nomExport,
  }) {
    final (ordre, incertaine) = _ordreDesDates();
    final messages = <MessageWhatsApp>[];
    final compteurs = <String, int>{};
    for (var i = 0; i < _bruts.length; i++) {
      final b = _bruts[i];
      final contenu = b.texte.toString();
      final m = _construire(i, b, contenu, ordre);
      messages.add(m);
      final auteur = m.auteur;
      if (auteur != null) compteurs[auteur] = (compteurs[auteur] ?? 0) + 1;
    }
    final participants =
        [
          for (final e in compteurs.entries)
            ParticipantWhatsApp(nom: e.key, messages: e.value),
        ]..sort((a, b) {
          final n = b.messages.compareTo(a.messages);
          return n != 0 ? n : a.nom.compareTo(b.nom);
        });
    return ConversationWhatsApp(
      titre:
          titreDepuisNom(nomExport ?? nomFichier) ??
          titreDepuisNom(nomFichier) ??
          _titreParDefaut(participants),
      messages: messages,
      participants: participants,
      ordreDate: ordre,
      dateIncertaine: incertaine,
      lignesNonRattachees: List.unmodifiable(_avantPremier),
      nombreLignesNonRattachees: _nombreAvantPremier,
      nomFichier: nomFichier,
    );
  }

  // --- En-têtes ------------------------------------------------------------

  // Marques invisibles (direction du texte, BOM) en tête de ligne.
  static final _invisibles = RegExp(
    '^[\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]+',
  );

  static const _motifDate = r'(\d{1,4})([./-])(\d{1,2})\2(\d{1,4})\.?';
  static const _heure =
      r'(\d{1,2})[:.h](\d{2})(?:[:.](\d{2}))?(?:\s?([AaPp])\.?\s?[Mm]\.?)?';
  // Entre la date et l'heure : « , », « à », « um », « a las »… ou rien.
  static const _entre = r'(?:,|\s+(?:à|um|a las|às|alle|om))?\s+';

  static final _android = RegExp('^$_motifDate$_entre$_heure\\s[-–]\\s');
  static final _ios = RegExp('^\\[$_motifDate$_entre$_heure\\]\\s?');

  _Brut? _lireEntete(String ligne) {
    // Espaces insécables (iOS 17 : « 2:30\u202fPM ») : même longueur, pour
    // retrouver le texte exact dans la ligne d'origine.
    final debut = _invisibles.firstMatch(ligne)?.end ?? 0;
    final normale = ligne
        .substring(debut)
        .replaceAll('\u202f', ' ')
        .replaceAll('\u00a0', ' ');
    final ios = normale.startsWith('[');
    final m = (ios ? _ios : _android).firstMatch(normale);
    if (m == null) return null;
    final reste = ligne.substring(debut + m.end);
    final brut = _Brut(
      a: int.parse(m[1]!),
      b: int.parse(m[3]!),
      c: int.parse(m[4]!),
      chiffresA: m[1]!.length,
      chiffresC: m[4]!.length,
      h: int.parse(m[5]!),
      mi: int.parse(m[6]!),
      s: m[7] == null ? 0 : int.parse(m[7]!),
      apresMidi: m[8] == null ? null : m[8]!.toLowerCase() == 'p',
      dateBrute: normale.substring(0, m.end).trim(),
    );
    final auteur = _separerAuteur(reste);
    if (auteur != null) {
      brut.auteur = auteur.$1;
      brut.texte.write(auteur.$2);
    } else {
      brut.texte.write(reste);
    }
    return brut;
  }

  /// « Tony Stark: Bonjour » → (Tony Stark, Bonjour) ; null sans auteur
  /// (message système Android : « Les messages sont chiffrés… »).
  static (String, String)? _separerAuteur(String reste) {
    final i = reste.indexOf(': ');
    if (i <= 0 || i > 80) {
      // « Tony Stark: » suivi d'une ligne vide (message multiligne).
      if (reste.endsWith(':') && reste.length <= 81 && !reste.contains(': ')) {
        return (reste.substring(0, reste.length - 1).trim(), '');
      }
      return null;
    }
    final auteur = reste.substring(0, i).replaceAll(_invisibles, '').trim();
    if (auteur.isEmpty) return null;
    return (auteur, reste.substring(i + 2));
  }

  // --- Dates ---------------------------------------------------------------

  /// Ordre jour/mois : d'abord les nombres impossibles (> 12), puis l'ordre
  /// chronologique (un export est chronologique) ; sinon supposition
  /// signalée comme incertaine.
  (OrdreDate, bool) _ordreDesDates() {
    if (_bruts.isEmpty) return (OrdreDate.jourMoisAnnee, false);
    if (_bruts.any((b) => b.chiffresA == 4)) {
      return (OrdreDate.anneeMoisJour, false);
    }
    final jourEnPremier = _bruts.any((b) => b.a > 12);
    final moisEnPremier = _bruts.any((b) => b.b > 12);
    if (jourEnPremier && !moisEnPremier) {
      return (OrdreDate.jourMoisAnnee, false);
    }
    if (moisEnPremier && !jourEnPremier) {
      return (OrdreDate.moisJourAnnee, false);
    }
    final reculsJM = _reculs(OrdreDate.jourMoisAnnee);
    final reculsMJ = _reculs(OrdreDate.moisJourAnnee);
    if (reculsJM < reculsMJ) return (OrdreDate.jourMoisAnnee, false);
    if (reculsMJ < reculsJM) return (OrdreDate.moisJourAnnee, false);
    // Indiscernable (signalé) : « 2:30 PM » est l'usage américain (mois
    // d'abord) ; « 2:30 p. m. » (espagnol…) et l'heure sur 24 h mettent
    // le jour d'abord.
    final amPmAmericain = _bruts.any(
      (b) => b.apresMidi != null && !_amPmPointe.hasMatch(b.dateBrute),
    );
    return (
      amPmAmericain ? OrdreDate.moisJourAnnee : OrdreDate.jourMoisAnnee,
      true,
    );
  }

  static final _amPmPointe = RegExp(r'[ap]\.\s?m', caseSensitive: false);

  int _reculs(OrdreDate ordre) {
    var reculs = 0;
    DateTime? precedente;
    for (final b in _bruts) {
      final d = _date(b, ordre);
      if (d == null) {
        reculs++;
        continue;
      }
      if (precedente != null && d.isBefore(precedente)) reculs++;
      precedente = d;
    }
    return reculs;
  }

  static DateTime? _date(_Brut b, OrdreDate ordre) {
    final (annee, mois, jour) = switch (ordre) {
      OrdreDate.jourMoisAnnee => (b.c, b.b, b.a),
      OrdreDate.moisJourAnnee => (b.c, b.a, b.b),
      OrdreDate.anneeMoisJour => (b.a, b.b, b.c),
    };
    final chiffresAnnee = ordre == OrdreDate.anneeMoisJour
        ? b.chiffresA
        : b.chiffresC;
    final a = chiffresAnnee <= 2 ? 2000 + annee : annee;
    var h = b.h;
    final pm = b.apresMidi;
    if (pm != null) {
      if (h < 1 || h > 12) return null;
      h = h % 12 + (pm ? 12 : 0);
    }
    if (mois < 1 || mois > 12 || jour < 1 || jour > 31) return null;
    if (h > 23 || b.mi > 59 || b.s > 59) return null;
    final d = DateTime(a, mois, jour, h, b.mi, b.s);
    // 31/02 → 03/03 : refusé plutôt que corrigé en silence.
    if (d.month != mois || d.day != jour) return null;
    return d;
  }

  // --- Contenu -------------------------------------------------------------

  static MessageWhatsApp _construire(
    int ordre,
    _Brut b,
    String contenu,
    OrdreDate ordreDate,
  ) {
    final texte = contenu.replaceFirst(_invisibles, '');
    var auteur = b.auteur;
    var type = TypeMessageWhatsApp.texte;
    TypeMediaWhatsApp? media;
    String? fichier;

    final premiereLigne = texte.split('\n').first.trim();
    final bas = premiereLigne.toLowerCase();
    final joint = _fichierJoint(premiereLigne);
    if (auteur == null) {
      type = TypeMessageWhatsApp.systeme;
    } else if (joint != null) {
      type = TypeMessageWhatsApp.media;
      fichier = joint;
      media = typeMediaDuFichier(joint);
    } else if (_omis(bas) case final omis?) {
      type = TypeMessageWhatsApp.media;
      media = omis;
    } else if (_supprimes.contains(bas.replaceAll(RegExp(r'[.\s]+$'), ''))) {
      type = TypeMessageWhatsApp.supprime;
    } else if (contenu.startsWith('\u200e')) {
      // iOS : les événements portent le nom de la discussion et
      // commencent par une marque invisible.
      type = TypeMessageWhatsApp.systeme;
      auteur = null;
    }
    return MessageWhatsApp(
      ordre: ordre,
      auteur: auteur,
      date: _date(b, ordreDate),
      dateBrute: b.dateBrute,
      texte: texte,
      type: type,
      typeMedia: media,
      nomFichierMedia: fichier,
    );
  }

  static const _supprimes = {
    'ce message a été supprimé',
    'vous avez supprimé ce message',
    'this message was deleted',
    'you deleted this message',
    'se eliminó este mensaje',
    'eliminaste este mensaje',
    'diese nachricht wurde gelöscht',
    'du hast diese nachricht gelöscht',
    'essa mensagem foi apagada',
    'você apagou esta mensagem',
    'questo messaggio è stato eliminato',
    'hai eliminato questo messaggio',
  };

  // « <Médias omis> » (Android) ; « image absente », « audio omis »…
  // (iOS) dans plusieurs langues.
  static final _omisAndroid = RegExp(
    r'^<(médias omis|media omitted|multimedia omitido|medien ausgeschlossen|'
    r'mídia oculta|media omessi)>$',
  );
  static final _omisIos = RegExp(
    r'^(image|photo|vidéo|video|audio|autocollant|sticker|gif|document|'
    r'carte de contact|contact card|imagen|imagem|bild|immagine|documento|'
    r'contacto|kontakt)\b.*\b(absente?|omise?|omitted|omitida|omitido|'
    r'ausgeschlossen|weggelassen|ocultad[oa]|omess[oa])$',
  );

  static TypeMediaWhatsApp? _omis(String bas) {
    if (_omisAndroid.hasMatch(bas)) return TypeMediaWhatsApp.inconnu;
    final m = _omisIos.firstMatch(bas);
    if (m == null) return null;
    final mot = m[1]!;
    if (mot.startsWith('vid')) return TypeMediaWhatsApp.video;
    if (mot == 'audio') return TypeMediaWhatsApp.audio;
    if (mot == 'autocollant' || mot == 'sticker') {
      return TypeMediaWhatsApp.autocollant;
    }
    if (mot == 'gif') return TypeMediaWhatsApp.gif;
    if (mot.startsWith('doc')) return TypeMediaWhatsApp.document;
    if (mot.contains('contact') || mot == 'kontakt') {
      return TypeMediaWhatsApp.contact;
    }
    return TypeMediaWhatsApp.image;
  }

  // « IMG-20261011-WA0001.jpg (fichier joint) » (Android) ;
  // « <attached: 00000012-PHOTO-….jpg> » (iOS).
  static final _jointAndroid = RegExp(
    r'^(.+\.[A-Za-z0-9]{2,5}) \((fichier joint|file attached|archivo adjunto|'
    r'datei angehängt|arquivo anexado|file allegato)\)',
    caseSensitive: false,
  );
  static final _jointIos = RegExp(
    r'^<(?:attached|pièce jointe|adjunto|anhang|anexado|allegato)\s?:\s?([^>]+)>',
    caseSensitive: false,
  );

  static String? _fichierJoint(String ligne) =>
      _jointAndroid.firstMatch(ligne)?[1]?.trim() ??
      _jointIos.firstMatch(ligne)?[1]?.trim();

  /// Type d'un média d'après son nom (préfixes WhatsApp, extension).
  static TypeMediaWhatsApp typeMediaDuFichier(String nom) {
    final n = nom.toUpperCase();
    if (n.startsWith('PTT-') || n.contains('-AUDIO-') && n.endsWith('.OPUS')) {
      return TypeMediaWhatsApp.vocal;
    }
    if (n.startsWith('STK-') || n.contains('-STICKER-')) {
      return TypeMediaWhatsApp.autocollant;
    }
    if (n.contains('-GIF-')) return TypeMediaWhatsApp.gif;
    final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
    return switch (ext) {
      'JPG' || 'JPEG' || 'PNG' || 'HEIC' || 'WEBP' => TypeMediaWhatsApp.image,
      'MP4' || '3GP' || 'MOV' || 'MKV' => TypeMediaWhatsApp.video,
      'OPUS' => TypeMediaWhatsApp.vocal,
      'OGG' || 'M4A' || 'AAC' || 'MP3' || 'WAV' => TypeMediaWhatsApp.audio,
      'GIF' => TypeMediaWhatsApp.gif,
      'VCF' => TypeMediaWhatsApp.contact,
      'PDF' ||
      'DOC' ||
      'DOCX' ||
      'XLS' ||
      'XLSX' ||
      'PPT' ||
      'PPTX' ||
      'TXT' ||
      'ZIP' => TypeMediaWhatsApp.document,
      _ => TypeMediaWhatsApp.inconnu,
    };
  }

  // --- Titre ---------------------------------------------------------------

  static final _titres = [
    RegExp(r'^discussion whatsapp avec (.+)$', caseSensitive: false),
    RegExp(r'^whatsapp chat (?:with|-) (.+)$', caseSensitive: false),
    RegExp(r'^chat de whatsapp con (.+)$', caseSensitive: false),
    RegExp(r'^whatsapp-chat mit (.+)$', caseSensitive: false),
    RegExp(r'^conversa do whatsapp com (.+)$', caseSensitive: false),
    RegExp(r'^chat whatsapp con (.+)$', caseSensitive: false),
  ];

  /// « Discussion WhatsApp avec Tony Stark.zip » → « Tony Stark ».
  static String? titreDepuisNom(String nom) {
    var base = nom.split(RegExp(r'[/\\]')).last;
    base = base.replaceFirst(RegExp(r'\.(txt|zip)$', caseSensitive: false), '');
    base = base.replaceFirst(RegExp(r'\s*\(\d+\)$'), '').trim();
    for (final r in _titres) {
      final m = r.firstMatch(base);
      if (m != null && m[1]!.trim().isNotEmpty) return m[1]!.trim();
    }
    return null;
  }

  static String _titreParDefaut(List<ParticipantWhatsApp> participants) {
    if (participants.isEmpty) return 'Conversation WhatsApp';
    if (participants.length <= 2) {
      return participants.map((p) => p.nom).join(' et ');
    }
    return 'Groupe de ${participants.length} participants';
  }
}

class _Brut {
  _Brut({
    required this.a,
    required this.b,
    required this.c,
    required this.chiffresA,
    required this.chiffresC,
    required this.h,
    required this.mi,
    required this.s,
    required this.apresMidi,
    required this.dateBrute,
  });

  final int a, b, c, chiffresA, chiffresC, h, mi, s;
  final bool? apresMidi;
  final String dateBrute;
  String? auteur;
  final texte = StringBuffer();
}
