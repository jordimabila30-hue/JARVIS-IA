import '../../models/message_conversation.dart';

/// Ce que contient un message de l'utilisateur : une éventuelle
/// conversation externe et sa demande (le texte hors conversation).
class MessageAnalyse {
  const MessageAnalyse(this.demande, this.conversation);

  /// Ce que l'utilisateur dit à JARVIS (« Tu peux me dire quoi
  /// répondre ? »), sans la conversation collée. Peut être vide.
  final String demande;
  final ConversationExterne? conversation;
}

/// Repère, par heuristique locale, une conversation collée ou écrite dans
/// un message : lignes « Nom : message », plusieurs locuteurs, horodatages
/// d'export (WhatsApp…), lignes de suite.
///
/// Prudent : un seul « Nom : message » n'est une conversation que si
/// l'utilisateur demande quelque chose à son sujet ([avecDemande]).
class DetecteurConversation {
  const DetecteurConversation();

  // « [14:32, 12/05/2024] », « 12/05/2024, 14:32 - », « 14h32 - »…
  static final _horodatage = RegExp(
    r'^\s*\[?(?:\d{1,2}[/.]\d{1,2}[/.]\d{2,4},?\s*(?:à\s*)?)?'
    r'(\d{1,2}[:h]\d{2})(?::\d{2})?'
    r'(?:,\s*\d{1,2}[/.]\d{1,2}[/.]\d{2,4})?\]?\s*[-–]?\s*',
  );

  // « Sarah : message », « Jean-Marc: message », « Moi : … ».
  static final _ligne = RegExp(
    r"^([A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'’.\- ]{0,28}?)\s*:\s*(\S.*)$",
  );

  // Mots qui précèdent souvent « : » sans être un locuteur.
  static const _pasUnLocuteur = {
    'note',
    'remarque',
    'ps',
    'exemple',
    'question',
    'reponse',
    'réponse',
    'attention',
    'info',
    'rappel',
    'objet',
    'sujet',
    'http',
    'https',
    'total',
    'prix',
    'date',
    'heure',
    'adresse',
    'tel',
    'tél',
    'email',
    'mail',
    'resultat',
    'résultat',
    'conclusion',
    'titre',
    'etape',
    'étape',
    'astuce',
    'important',
    'nb',
    'source',
    'lien',
  };

  static const _pronoms = {'moi', 'elle', 'lui', 'il', 'toi', 'me', 'je'};

  /// Découpe [texte]. [avecDemande] : la demande contient une intention
  /// liée à une conversation (répondre, résumer…), ce qui autorise une
  /// conversation d'un seul message.
  MessageAnalyse analyser(
    String texte, {
    bool Function(String demande)? avecDemande,
  }) {
    final lignes = texte.replaceAll('\r\n', '\n').split('\n');
    final messages = <_Message>[];
    final avant = <String>[];
    final apres = <String>[];
    var videDepuisDernier = false;

    for (final brute in lignes) {
      final ligne = brute.trim();
      if (ligne.isEmpty) {
        if (messages.isNotEmpty) videDepuisDernier = true;
        continue;
      }
      final m = _lireLigne(ligne);
      if (m != null) {
        // Une demande glissée entre deux blocs reste dans la demande.
        messages.add(m);
        videDepuisDernier = false;
        continue;
      }
      if (messages.isEmpty) {
        avant.add(ligne);
      } else if (!videDepuisDernier &&
          apres.isEmpty &&
          !(avecDemande?.call(ligne) ?? false)) {
        // Suite du message précédent (message sur plusieurs lignes), sauf
        // une demande adressée à JARVIS juste après la conversation.
        messages.last.texte.write(' $ligne');
      } else {
        apres.add(ligne);
      }
    }

    final demande = [...avant, ...apres].join('\n').trim();
    final locuteurs = {for (final m in messages) m.locuteur.toLowerCase()};
    final moi = messages.any((m) => LigneConversation(m.locuteur, '').estMoi);
    final probable =
        (messages.length >= 2 && (locuteurs.length >= 2 || moi)) ||
        (messages.length == 1 && (avecDemande?.call(demande) ?? false));
    if (!probable) return MessageAnalyse(texte.trim(), null);

    return MessageAnalyse(
      demande,
      ConversationExterne([
        for (final m in messages)
          LigneConversation(
            m.locuteur,
            m.texte.toString().trim(),
            heure: m.heure,
          ),
      ]),
    );
  }

  _Message? _lireLigne(String ligne) {
    String? heure;
    var reste = ligne;
    final h = _horodatage.firstMatch(ligne);
    // Un horodatage n'est retenu que s'il précède « Nom : … ».
    if (h != null && h.end < ligne.length) {
      final suite = ligne.substring(h.end);
      if (_ligne.hasMatch(suite)) {
        heure = h.group(1);
        reste = suite;
      }
    }
    final m = _ligne.firstMatch(reste);
    if (m == null) return null;
    final nom = m.group(1)!.trim();
    final message = m.group(2)!.trim();
    final bas = nom.toLowerCase();
    if (_pasUnLocuteur.contains(bas)) return null;
    if (nom.split(RegExp(r'\s+')).length > 3) return null;
    // Un nom propre commence par une majuscule ; sinon, un pronom.
    final majuscule = nom[0] == nom[0].toUpperCase();
    if (!majuscule && !_pronoms.contains(bas)) return null;
    // « Il est 14:30 » ou une URL ne sont pas des messages.
    if (message.startsWith('//')) return null;
    return _Message(nom, message, heure);
  }
}

class _Message {
  _Message(this.locuteur, String texte, this.heure)
    : texte = StringBuffer(texte);

  final String locuteur;
  final StringBuffer texte;
  final String? heure;
}
