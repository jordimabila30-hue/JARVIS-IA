import '../utils/calcul_vocal.dart';
import '../utils/local_date_time.dart';
import 'connaissances_techniques.dart';

/// Assistant distant (future API d'IA). Rien ne l'implémente pour l'instant :
/// il suffira de passer une implémentation à [VoiceCommandService].
abstract class AssistantDistant {
  Future<String> repondre(String phrase);
}

/// D'où vient une réponse.
enum SourceReponse { locale, distante, inconnue }

/// Réponse prête à être prononcée.
class ReponseVocale {
  const ReponseVocale(
    this.texte, {
    required this.source,
    this.terminerSession = false,
  });

  final String texte;
  final SourceReponse source;

  /// Vrai quand l'utilisateur prend congé (« Au revoir JARVIS »).
  final bool terminerSession;
}

/// Ce que JARVIS attend après avoir posé une question.
enum AttenteConversation { aucune, humeur, prenom }

/// Mémoire de la conversation en cours : elle permet d'enchaîner les
/// échanges comme entre deux personnes (prénom, « et vous ? », « dis-m'en
/// plus », « répète »).
class ContexteConversation {
  String? prenom;

  /// Dernière notion technique expliquée (pour « dis-m'en plus »).
  Notion? sujet;
  String? derniereReponse;
  AttenteConversation attente = AttenteConversation.aucune;

  /// Nombre de réponses données (sert à varier les formulations).
  int tours = 0;
  int inconnues = 0;

  /// Nombre de salutations déjà échangées pendant la session.
  int salutations = 0;

  /// Copie indépendante (reprise d'une conversation mise de côté).
  ContexteConversation copie() => ContexteConversation()..copierDe(this);

  void copierDe(ContexteConversation autre) {
    prenom = autre.prenom;
    sujet = autre.sujet;
    derniereReponse = autre.derniereReponse;
    attente = autre.attente;
    tours = autre.tours;
    inconnues = autre.inconnues;
    salutations = autre.salutations;
  }

  /// Oublie tout : nouvelle conversation.
  void reinitialiser() {
    prenom = null;
    sujet = null;
    derniereReponse = null;
    attente = AttenteConversation.aucune;
    tours = 0;
    inconnues = 0;
    salutations = 0;
  }
}

/// Analyse une phrase reconnue et choisit la réponse.
///
/// phrase → réponse attendue (après une question de JARVIS) ?
///        → calcul ? → commande locale ? → notion technique ?
///        → sinon assistant distant (s'il existe), sinon « pas encore
///          disponible ».
///
/// Les commandes locales restent prioritaires même quand une IA sera
/// branchée : elles sont instantanées et toujours exactes.
class VoiceCommandService {
  VoiceCommandService({this.assistantDistant, DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final AssistantDistant? assistantDistant;
  final DateTime Function() _horloge;
  final contexte = ContexteConversation();

  static const reponseInconnue = 'Cette commande n’est pas encore disponible.';

  /// Choisit la réponse à une phrase reconnue.
  Future<ReponseVocale> traiter(String phraseReconnue) async {
    final locale = reponseLocale(phraseReconnue);
    if (locale != null) return locale;

    final distant = assistantDistant;
    if (distant != null) {
      final texte = await distant.repondre(phraseReconnue);
      contexte.derniereReponse = texte;
      return ReponseVocale(texte, source: SourceReponse.distante);
    }
    final texte = contexte.inconnues++ == 0
        ? reponseInconnue
        : _varier(const [
            'Je ne peux pas encore répondre à cette demande. Vous pouvez me '
                'demander l’heure, un calcul ou une explication technique.',
            'Je ne connais pas encore la réponse. Essayez par exemple : '
                'combien font 12 fois 8, ou : c’est quoi Flutter.',
            reponseInconnue,
          ]);
    contexte.derniereReponse = texte;
    return ReponseVocale(texte, source: SourceReponse.inconnue);
  }

  /// Réponse locale si une commande correspond, sinon null.
  ReponseVocale? reponseLocale(String phraseReconnue) {
    final phrase = normaliser(phraseReconnue);
    if (phrase.isEmpty) return null;
    final r = _repondre(phrase, phraseReconnue);
    if (r != null) {
      contexte.tours++;
      contexte.derniereReponse = r.texte;
    }
    return r;
  }

  // ---------------------------------------------------------------------------

  ReponseVocale _dire(String texte, {bool terminer = false}) => ReponseVocale(
    texte,
    source: SourceReponse.locale,
    terminerSession: terminer,
  );

  /// Choisit une formulation selon le tour (varié, mais prévisible).
  String _varier(List<String> options) =>
      options[contexte.tours % options.length];

  String get _virgulePrenom =>
      contexte.prenom == null ? '' : ', ${contexte.prenom}';

  ReponseVocale? _repondre(String phrase, String brut) {
    final encadree = ' $phrase ';
    bool dit(List<String> variantes) =>
        variantes.any((v) => encadree.contains(' $v '));
    final maintenant = _horloge();
    final c = contexte;

    // ---- 1. Réponse à une question que JARVIS vient de poser ---------------
    final attente = c.attente;
    c.attente = AttenteConversation.aucune;
    if (attente == AttenteConversation.prenom) {
      final prenom = _extrairePrenom(phrase, brut, direct: true);
      if (prenom != null) {
        c.prenom = prenom;
        return _dire('Enchanté, $prenom. Que puis-je faire pour vous ?');
      }
    }
    if (attente == AttenteConversation.humeur) {
      if (dit(_humeurNegative) && !dit(['pas mal'])) {
        return _dire(
          'Je suis désolé de l’entendre$_virgulePrenom. Prenez soin de vous. '
          'Si je peux vous aider, dites-le-moi.',
        );
      }
      if (dit(_humeurPositive)) {
        final retour = dit(['et toi', 'et vous'])
            ? ' Moi aussi, je fonctionne parfaitement.'
            : '';
        return _dire(
          'Ravi de l’entendre$_virgulePrenom.$retour Que puis-je faire pour '
          'vous ?',
        );
      }
    }

    // ---- 2. Suites de conversation ----------------------------------------
    if (dit([
      'repete',
      'tu peux repeter',
      'peux tu repeter',
      'redis',
      'pardon',
      'j ai pas compris',
      'je n ai pas compris',
    ])) {
      final derniere = c.derniereReponse;
      return _dire(
        derniere == null
            ? 'Je n’ai encore rien dit. Que puis-je faire pour vous ?'
            : 'Je disais : $derniere',
      );
    }
    if (dit([
      'dis m en plus',
      'dis moi en plus',
      'developpe',
      'plus de details',
      'explique plus',
      'explique moi plus',
      'c est a dire',
      'continue',
      'et encore',
      'tu peux developper',
    ])) {
      final sujet = c.sujet;
      if (sujet == null) {
        return _dire(
          'De quel sujet voulez-vous que je parle ? Par exemple : '
          'c’est quoi l’intelligence artificielle.',
        );
      }
      return _dire(sujet.detail);
    }

    // ---- 3. Prénom --------------------------------------------------------
    final prenomDonne = _extrairePrenom(phrase, brut);
    if (prenomDonne != null) {
      c.prenom = prenomDonne;
      return _dire('Enchanté, $prenomDonne. Je m’en souviendrai.');
    }
    if (dit([
      'comment je m appelle',
      'quel est mon nom',
      'quel est mon prenom',
      'tu connais mon nom',
      'tu connais mon prenom',
      'tu sais comment je m appelle',
      'qui suis je',
    ])) {
      if (c.prenom != null) return _dire('Vous vous appelez ${c.prenom}.');
      c.attente = AttenteConversation.prenom;
      return _dire(
        'Je ne connais pas encore votre prénom. Comment vous appelez-vous ?',
      );
    }

    // ---- 4. Calcul --------------------------------------------------------
    final calcul = CalculVocal.calculer(_pourCalcul(brut));
    if (calcul != null) return _dire(calcul.phrase);

    // ---- 5. Heure et date de l'appareil -----------------------------------
    if (dit([
      'quelle heure',
      'quel heure',
      'il est quelle heure',
      'donne moi l heure',
      'donnes moi l heure',
      'dis moi l heure',
      'l heure qu il est',
      'tu as l heure',
    ])) {
      return _dire(heureEnFrancais(maintenant));
    }
    if (dit(['demain'])) {
      final demain = maintenant.add(const Duration(days: 1));
      return _dire(
        'Demain, ${dateEnFrancais(demain).replaceFirst('Nous sommes', 'nous serons')}',
      );
    }
    if (dit(['hier'])) {
      final hier = maintenant.subtract(const Duration(days: 1));
      return _dire(
        'Hier, ${dateEnFrancais(hier).replaceFirst('Nous sommes', 'nous étions')}',
      );
    }
    if (dit([
      'quelle est la date',
      'quelle date',
      'quel jour',
      'on est quel jour',
      'nous sommes quel jour',
      'on est le combien',
      'la date d aujourd hui',
      'date du jour',
    ])) {
      return _dire(dateEnFrancais(maintenant));
    }
    if (dit(['quelle annee', 'en quelle annee', 'on est en quelle annee'])) {
      return _dire('Nous sommes en ${maintenant.year}.');
    }
    if (dit(['quel mois', 'on est en quel mois'])) {
      return _dire('Nous sommes en ${moisEnFrancais(maintenant)}.');
    }

    // ---- 6. Fin de conversation -------------------------------------------
    if (dit(['bonne nuit'])) {
      return _dire('Bonne nuit$_virgulePrenom.', terminer: true);
    }
    if (dit(['a plus tard', 'salut a plus', 'bye', 'bye bye'])) {
      return _dire(
        maintenant.hour >= 18
            ? 'Bonne soirée$_virgulePrenom.'
            : 'À votre prochaine demande$_virgulePrenom.',
        terminer: true,
      );
    }
    if (dit(['au revoir', 'a bientot', 'a la prochaine'])) {
      return _dire('À bientôt$_virgulePrenom.', terminer: true);
    }

    // ---- 7. Échanges courants ---------------------------------------------
    if (dit([
      'statut systeme',
      'statut du systeme',
      'etat du systeme',
      'comment va le systeme',
      'est ce que tout fonctionne',
      'tout fonctionne',
      'tout est operationnel',
      'diagnostic',
    ])) {
      return _dire('Tous les systèmes disponibles sont opérationnels.');
    }
    if (dit([
      'comment tu t appelles',
      'comment t appelles tu',
      'tu t appelles comment',
      'quel est ton nom',
      'c est quoi ton nom',
    ])) {
      return _dire('Je m’appelle JARVIS.');
    }
    if (dit([
      'comment vas tu',
      'comment tu vas',
      'comment ca va',
      'ca va',
      'comment allez vous',
      'tu vas bien',
      'vous allez bien',
    ])) {
      c.attente = AttenteConversation.humeur;
      return _dire(
        'Je fonctionne parfaitement. Merci. Et vous, comment allez-vous ?',
      );
    }
    if (dit([
      'qui es tu',
      'qui est tu',
      'tu es qui',
      't es qui',
      'qui etes vous',
      'presente toi',
      'presentez vous',
      'c est quoi jarvis',
      'qu est ce que jarvis',
      'qui est jarvis',
    ])) {
      return _dire('Je suis JARVIS, votre assistant.');
    }
    if (dit([
      'que peux tu faire',
      'que sais tu faire',
      'tu peux faire quoi',
      'tu sais faire quoi',
      'qu est ce que tu peux faire',
      'qu est ce que tu sais faire',
      'quelles sont tes fonctionnalites',
      'quelles sont tes capacites',
      'a quoi tu sers',
      'a quoi sers tu',
      'aide moi',
      'aide',
    ])) {
      return _dire(
        'Mes fonctionnalités sont encore en cours de développement, mais je '
        'peux déjà interagir avec vous et exécuter certaines commandes '
        'locales : l’heure et la date, des calculs, des explications '
        'techniques comme l’intelligence artificielle ou Flutter, et retenir '
        'votre prénom.',
      );
    }
    if (dit([
      'comment tu fonctionnes',
      'comment fonctionnes tu',
      'comment tu marches',
      'comment ca marche',
      'parle moi de toi',
    ])) {
      c.sujet = _notion('ton fonctionnement');
      return _dire(c.sujet!.courte);
    }
    if (dit([
      'tu es une ia',
      'es tu une ia',
      'tu es un robot',
      'es tu un robot',
      'tu es humain',
      'es tu humain',
      'tu es vivant',
      'tu es intelligent',
    ])) {
      return _dire(
        'Je suis un assistant vocal en cours de développement. Pour l’instant, '
        'je réponds avec des règles écrites dans l’application, sans '
        'intelligence artificielle connectée.',
      );
    }
    if (dit([
      'qui t a cree',
      'qui t a fait',
      'qui t a programme',
      'qui est ton createur',
      'qui t a developpe',
    ])) {
      return _dire(
        'J’ai été créé dans le cadre du projet JARVIS, développé avec Flutter.',
      );
    }
    if (dit(['quel age as tu', 'tu as quel age', 'quel est ton age'])) {
      return _dire(
        'Je suis tout jeune : mon développement vient de commencer.',
      );
    }
    if (dit(['tu m entends', 'tu m ecoutes', 'tu es la', 'jarvis tu es la'])) {
      return _dire('Oui, je vous entends$_virgulePrenom.');
    }
    if (dit(['merci', 'merci beaucoup', 'merci jarvis', 'je te remercie'])) {
      return _dire(
        _varier([
          'Avec plaisir$_virgulePrenom.',
          'Je vous en prie.',
          'Toujours disponible.',
        ]),
      );
    }
    if (dit([
      'blague',
      'une blague',
      'fais moi rire',
      'raconte moi quelque chose de drole',
    ])) {
      return _dire(_varier(_blagues));
    }
    if (dit([
      'bonne journee',
      'bonne soiree',
      'bon week end',
      'bonne semaine',
    ])) {
      return _dire('Merci, à vous aussi$_virgulePrenom.');
    }
    if (dit(['meteo', 'quel temps', 'il fait beau', 'va t il pleuvoir'])) {
      return _dire(
        'Je n’ai pas encore accès à la météo. Cette fonction viendra plus tard.',
      );
    }
    if (dit(['musique', 'chanson', 'mets de la musique'])) {
      return _dire('Je ne peux pas encore lancer de musique.');
    }
    if (dit(['je t aime', 'je t adore'])) {
      return _dire('C’est gentil. Je suis là pour vous aider.');
    }
    if (dit(['tu es nul', 'tu es bete', 'tu ne sers a rien'])) {
      return _dire(
        'Je suis encore en apprentissage. Dites-moi ce que vous attendiez, '
        'cela aidera à m’améliorer.',
      );
    }
    if (dit([
      'd accord',
      'ok',
      'okay',
      'tres bien',
      'parfait',
      'super',
      'cool',
    ])) {
      return _dire(
        _varier(['Très bien.', 'Parfait. Autre chose ?', 'D’accord.']),
      );
    }

    // ---- 8. Notions techniques --------------------------------------------
    final notion = _notionDemandee(phrase);
    if (notion != null) {
      c.sujet = notion;
      return _dire(notion.courte);
    }

    // ---- 9. Salutations (en dernier : « bonjour, quelle heure… » → l'heure)
    if (dit([
      'bonjour',
      'bonsoir',
      'salut',
      'hello',
      'coucou',
      'hey jarvis',
      'hey',
    ])) {
      final mot = phrase.contains('bonsoir')
          ? 'Bonsoir'
          : phrase.contains('bonjour')
          ? 'Bonjour'
          : salutation(maintenant);
      final nom = c.prenom == null ? '' : ' ${c.prenom}';
      // Première salutation : formule complète ; ensuite, plus brève.
      final suite = const [
        'Comment puis-je vous aider ?',
        'Je vous écoute.',
        'Que puis-je faire pour vous ?',
      ][c.salutations++ % 3];
      return _dire('$mot$nom. $suite');
    }
    if (dit(['oui'])) return _dire('Très bien. Que puis-je faire pour vous ?');
    if (dit(['non'])) return _dire('D’accord. Je reste à votre écoute.');

    return null;
  }

  // ---- Notions techniques ---------------------------------------------------

  static const _marqueursQuestion = [
    'c est quoi',
    'c est quoi un',
    'c est quoi une',
    'qu est ce que',
    'qu est ce qu',
    'explique',
    'explique moi',
    'definis',
    'definition',
    'parle moi de',
    'a quoi sert',
    'comment fonctionne',
    'comment marche',
    'que sais tu sur',
    'tu connais',
  ];

  Notion? _notion(String nom) {
    for (final n in connaissancesTechniques) {
      if (n.noms.contains(nom)) return n;
    }
    return null;
  }

  /// Notion citée dans une question (« c'est quoi le cloud ») ou seule
  /// (« Flutter ? »).
  Notion? _notionDemandee(String phrase) {
    final encadree = ' $phrase ';
    final question = _marqueursQuestion.any((m) => encadree.contains(' $m '));
    final mots = phrase.split(' ').length;
    Notion? meilleure;
    var longueur = 0;
    for (final n in connaissancesTechniques) {
      for (final nom in n.noms) {
        // Le nom le plus long l'emporte (« modele de langage » plutôt que
        // « ia »).
        if (encadree.contains(' $nom ') && nom.length > longueur) {
          final seul = mots <= nom.split(' ').length + 2;
          if (question || seul) {
            meilleure = n;
            longueur = nom.length;
          }
        }
      }
    }
    return meilleure;
  }

  // ---- Prénom ---------------------------------------------------------------

  static final _declarationPrenom = RegExp(
    r'(?:^| )(?:je m appelle|mon nom est|mon prenom est|appelle moi|'
    r'tu peux m appeler|moi c est)\s+(.+)$',
  );

  static const _pasUnPrenom = {
    'jarvis',
    'pas',
    'rien',
    'quoi',
    'comment',
    'bien',
    'mal',
    'oui',
    'non',
  };

  /// Prénom donné dans la phrase (« je m'appelle Jordi »), ou phrase entière
  /// quand JARVIS vient de demander le prénom ([direct]).
  String? _extrairePrenom(String phrase, String brut, {bool direct = false}) {
    String? reste;
    final m = _declarationPrenom.firstMatch(phrase);
    if (m != null) {
      reste = m.group(1);
    } else if (direct && phrase.split(' ').length <= 3) {
      reste = phrase.replaceFirst(RegExp(r'^(c est|moi c est|je suis)\s+'), '');
    }
    if (reste == null) return null;
    final mots = reste
        .split(' ')
        .where((w) => w.isNotEmpty && !_pasUnPrenom.contains(w))
        .take(2)
        .toList();
    if (mots.isEmpty) return null;

    // On retrouve l'orthographe d'origine (accents) dans la phrase brute.
    final motsBruts = brut
        .split(RegExp(r"[\s'’,.!?]+"))
        .where((w) => w.isNotEmpty)
        .toList();
    String original(String mot) {
      for (final b in motsBruts) {
        if (normaliser(b) == mot) return b;
      }
      return mot;
    }

    return mots
        .map(original)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ---- Humeur ---------------------------------------------------------------

  static const _humeurNegative = [
    'pas bien',
    'pas tres bien',
    'pas trop',
    'mal',
    'bof',
    'fatigue',
    'fatiguee',
    'creve',
    'triste',
    'stresse',
    'stressee',
    'malade',
    'nul',
    'pas terrible',
    'ca pourrait aller mieux',
  ];

  static const _humeurPositive = [
    'bien',
    'tres bien',
    'ca va',
    'super',
    'genial',
    'en forme',
    'impeccable',
    'parfait',
    'nickel',
    'top',
    'pas mal',
    'tranquille',
    'oui',
  ];

  static const _blagues = [
    'Il y a 10 sortes de personnes : celles qui comprennent le binaire, et '
        'les autres.',
    'Pourquoi les développeurs confondent-ils Halloween et Noël ? Parce que '
        'octobre 31 égale décembre 25.',
    'Un programmeur part faire les courses. On lui dit : prends un pain, et '
        's’il y a des œufs, prends-en six. Il revient avec six pains.',
    'Quel est l’animal préféré des développeurs ? Le bug, même s’ils passent '
        'leurs journées à le chasser.',
  ];

  // ---- Normalisation ----------------------------------------------------------

  static const _accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ç': 'c',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };

  static String _sansAccents(String texte) {
    final tampon = StringBuffer();
    for (final c in texte.toLowerCase().split('')) {
      tampon.write(_accents[c] ?? c);
    }
    return tampon.toString();
  }

  /// Minuscules, sans accents, ponctuation et apostrophes remplacées par des
  /// espaces, espaces multiples réduits.
  static String normaliser(String texte) =>
      _sansAccents(texte).replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();

  /// Pour les calculs : on garde les chiffres, les virgules et les symboles
  /// d'opération (+, −, ×, /, %).
  static String _pourCalcul(String texte) => _sansAccents(texte)
      .replaceAll('−', '-')
      .replaceAll(RegExp(r"[^a-z0-9+\-*/×÷%^,. ]+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
