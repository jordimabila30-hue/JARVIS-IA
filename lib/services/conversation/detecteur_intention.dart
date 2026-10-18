/// Ce que l'utilisateur attend de JARVIS.
enum IntentionMessage {
  /// Discussion normale avec JARVIS.
  discussion,

  /// « Tu peux me dire quoi répondre ? » : choix du ton, réponse proposée.
  reponse,

  /// « Résume cette conversation ».
  resume,

  /// « Explique-moi cette conversation », « qu'est-ce qui se passe ».
  comprendre,

  /// Question libre sur une conversation (« tu trouves que j'ai mal
  /// répondu ? », « pourquoi elle réagit comme ça ? »).
  analyse,
}

/// Détection locale de l'intention (mots-clés, sans IA).
///
/// Certaines formulations ne sont lues comme liées à une conversation que
/// si une conversation est présente ou récente ([conversationConnue]) :
/// « réponds » seul, ou « tu comprends ? », restent sinon une discussion.
class DetecteurIntention {
  const DetecteurIntention();

  static const _reponse = [
    'que repondre',
    'quoi repondre',
    'je dis quoi',
    'je reponds quoi',
    'je lui dis quoi',
    'je lui reponds quoi',
    'je lui repond quoi',
    'je reponds comment',
    'comment repondre',
    'comment lui repondre',
    'qu est ce que je peux repondre',
    'qu est ce que je peux lui repondre',
    'qu est ce que je dois repondre',
    'qu est ce que je dois lui repondre',
    'qu est ce que je reponds',
    'qu est ce que je lui reponds',
    'reponds lui',
    'repond lui',
    'reponds pour moi',
    'reponds a ma place',
    'aide moi a repondre',
    'propose une reponse',
    'propose moi une reponse',
    'ecris une reponse',
    'ecris moi une reponse',
    'redige une reponse',
    'formule une reponse',
    'une reponse a envoyer',
  ];

  static const _resume = [
    'resume',
    'resumer',
    'resumes',
    'en bref',
    'synthese',
    'recap',
    'recapitule',
  ];

  static const _comprendre = [
    'comprends cette',
    'comprendre cette',
    'explique moi cette',
    'explique cette',
    'explique moi la conversation',
    'explique moi ce qui se passe',
    'qu est ce qui se passe',
    'que se passe t il',
    'de quoi ca parle',
    'de quoi parle',
    'le contexte',
  ];

  static const _analyse = [
    'tu en penses quoi',
    'qu est ce que tu en penses',
    't en penses quoi',
    'ton avis',
    'pourquoi il',
    'pourquoi elle',
    'pourquoi ils',
    'pourquoi elles',
    'mal repondu',
    'bien repondu',
    'j ai mal',
    'j ai bien',
    'j aurais du',
    'veut dire',
    'veulent dire',
    'tendu',
    'tendue',
    'fache',
    'fachee',
    'enerve',
    'enervee',
    'vexe',
    'vexee',
    'en colere',
    'c est grave',
    'est ce normal',
    'c est normal',
    'qu est ce qu il veut',
    'qu est ce qu elle veut',
    'il m en veut',
    'elle m en veut',
  ];

  // Seulement avec une conversation connue.
  static const _reponseContexte = ['reponds', 'repond', 'repondre'];
  static const _comprendreContexte = ['comprends', 'explique', 'analyse'];

  /// Minuscules, sans accents, apostrophes et tirets en espaces.
  static String normaliser(String texte) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'œ': 'oe',
      'æ': 'ae',
    };
    final b = StringBuffer();
    for (final c in texte.toLowerCase().split('')) {
      b.write(accents[c] ?? c);
    }
    return b
        .toString()
        .replaceAll(RegExp(r"[’'\-]"), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  IntentionMessage detecter(
    String demande, {
    required bool conversationConnue,
  }) {
    final t = ' ${normaliser(demande)} ';
    if (t.trim().isEmpty) return IntentionMessage.discussion;
    bool contient(List<String> mots) => mots.any((m) => t.contains(' $m '));

    if (contient(_reponse)) return IntentionMessage.reponse;
    if (contient(_resume)) return IntentionMessage.resume;
    if (contient(_comprendre)) return IntentionMessage.comprendre;
    if (contient(_analyse)) return IntentionMessage.analyse;
    if (conversationConnue) {
      if (contient(_reponseContexte)) return IntentionMessage.reponse;
      if (contient(_comprendreContexte)) return IntentionMessage.comprendre;
    }
    return IntentionMessage.discussion;
  }

  static const _motsEmail = [
    'mail', 'mails', 'email', 'emails', 'e mail', 'e mails', 'courriel', 'courriels', 'mel', 'mels',
  ];
  static const _personnel = [
    'mes', 'mon', 'ma', 'j ai recu', 'j ai recus', 'recu', 'recus', 'dernier', 'derniers', 'derniere',
    'dernieres', 'important', 'importants', 'non lu', 'non lus', 'aujourd hui', 'hier', 'cette semaine',
    'ce matin', 'ce soir', 'boite',
  ];

  /// Vrai si [demande] porte sur les e-mails PERSONNELS de l'utilisateur
  /// (sa boîte Gmail) : « résume mes mails », « regarde si j'ai reçu des
  /// mails importants », « le dernier mail de mon prof ». Ces demandes vont
  /// au serveur (compétence Gmail d'ODO) au lieu de demander de coller une
  /// conversation. « Résume ce mail » (sans repère personnel) reste local.
  static bool concerneMesEmails(String demande) {
    final t = ' ${normaliser(demande)} ';
    bool a(String m) => t.contains(' $m ');
    if (a('gmail') || a('boite mail') || a('boite mails') || a('boite de reception')) return true;
    return _motsEmail.any(a) && _personnel.any(a);
  }

  /// Vrai si [demande] concerne visiblement une conversation (sert à
  /// accepter une conversation d'un seul message).
  bool concerneUneConversation(String demande) =>
      detecter(demande, conversationConnue: true) !=
      IntentionMessage.discussion;
}
