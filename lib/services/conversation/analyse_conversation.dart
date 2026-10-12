import '../../models/message_conversation.dart';
import 'detecteur_intention.dart';

/// Situation principale d'un échange (heuristique locale).
enum Situation {
  /// L'autre reproche quelque chose (« tu aurais pu me prévenir »).
  reproche,

  /// Proposition de se voir, d'une sortie (« tu viens ce soir ? »).
  invitation,

  /// L'autre remercie.
  remerciement,

  /// L'autre pose une question.
  question,

  /// Simple prise de nouvelles (« salut, ça va ? »).
  salutation,

  /// Rien de marqué.
  neutre,
}

/// Lecture locale d'une conversation externe : participants, situation,
/// tension, à qui c'est de répondre. Sert au moteur local ; une IA la
/// remplacera.
class AnalyseConversation {
  AnalyseConversation(this.conversation) {
    final autres = conversation.lignes.where((l) => !l.estMoi).toList();
    final texteAutres = DetecteurIntention.normaliser(
      autres.map((l) => l.texte).join(' '),
    );
    final texteMoi = DetecteurIntention.normaliser(
      conversation.lignes.where((l) => l.estMoi).map((l) => l.texte).join(' '),
    );
    bool chez(String t, List<String> mots) =>
        mots.any((m) => ' $t '.contains(' $m '));

    final dernier = conversation.dernierDesAutres;
    final dernierTexte = DetecteurIntention.normaliser(dernier?.texte ?? '');

    reproche = chez(texteAutres, _motsReproche);
    excuseDeMoi = chez(texteMoi, _motsExcuse);
    tension = [
      reproche,
      chez(texteAutres, _motsTension),
      autres.where((l) => l.texte.contains('!')).length >= 2,
      // Le reproche continue malgré une excuse.
      reproche && excuseDeMoi && chez(dernierTexte, _motsReproche),
    ].where((v) => v).length;

    if (reproche) {
      situation = Situation.reproche;
    } else if (chez(texteAutres, _motsInvitation)) {
      situation = Situation.invitation;
    } else if (chez(dernierTexte, const ['merci'])) {
      situation = Situation.remerciement;
    } else if ((dernier?.texte ?? '').trim().endsWith('?')) {
      situation = Situation.question;
    } else if (chez(texteAutres, _motsSalut)) {
      situation = Situation.salutation;
    } else {
      situation = Situation.neutre;
    }
  }

  final ConversationExterne conversation;
  late final bool reproche;
  late final bool excuseDeMoi;
  late final Situation situation;

  /// 0 = calme, 1 = un peu tendu, 2 et plus = tendu.
  late final int tension;

  static const _motsReproche = [
    'tu aurais pu',
    'tu aurais du',
    'pas la premiere fois',
    'encore une fois',
    'toujours la meme chose',
    'tu fais toujours',
    'tu ne fais jamais',
    'tu oublies',
    'tu as oublie',
    'decu',
    'decue',
    'serieux',
    'pas normal',
    'c est pas normal',
    'j attendais',
    'je t ai attendu',
    'tu m as pas',
    'tu ne m as pas',
    'prevenir',
    'previens',
    'en retard',
    'abuse',
  ];
  static const _motsTension = [
    'jamais',
    'toujours',
    'marre',
    'ras le bol',
    'enerve',
    'enervee',
    'fache',
    'fachee',
    'laisse tomber',
    'n importe quoi',
    'stop',
  ];
  static const _motsExcuse = [
    'desole',
    'desolee',
    'pardon',
    'excuse',
    'excuse moi',
    'mes excuses',
  ];
  static const _motsInvitation = [
    'tu viens',
    'on se voit',
    'ce soir',
    'demain',
    'ce week end',
    'tu es dispo',
    't es dispo',
    'tu serais dispo',
    'ca te dit',
    'on sort',
    'boire un verre',
    'diner',
    'rendez vous',
    'tu veux venir',
  ];
  static const _motsSalut = [
    'salut',
    'coucou',
    'hello',
    'bonjour',
    'bonsoir',
    'ca va',
    'quoi de neuf',
  ];

  // ---- Formulations -------------------------------------------------------

  // Personnes : toujours le nom donné par la conversation (« Sarah »,
  // « Clean Girl »…), jamais un genre deviné d'après le prénom. Sans nom
  // (« Elle : … », aucun autre locuteur), une formulation neutre.

  /// Nom d'une personne tel qu'écrit, ou « la personne » s'il n'est pas
  /// connu.
  static String _nom(String locuteur) =>
      LigneConversation(locuteur, '').sansNom ? 'la personne' : locuteur;

  String get _autres {
    final a = [
      for (final p in conversation.autres)
        if (!LigneConversation(p, '').sansNom) p,
    ];
    if (a.isEmpty) return 'ton interlocuteur';
    if (a.length == 1) return a.first;
    return '${a.sublist(0, a.length - 1).join(', ')} et ${a.last}';
  }

  String get _principal {
    final d = conversation.dernierDesAutres;
    return d == null ? _autres : _nom(d.locuteur);
  }

  /// [_principal] en début de phrase (« La personne attend… »).
  String get _enTete => _majuscule(_principal);

  bool get _cEstAMoi => !conversation.derniere.estMoi;

  static String _cite(String texte) {
    final t = texte.trim();
    return '« ${t.length > 90 ? '${t.substring(0, 87)}…' : t} »';
  }

  String get _situationEnClair => switch (situation) {
    Situation.reproche =>
      '$_principal te fait un reproche'
          '${conversation.dernierDesAutres == null ? '' : ' : ${_cite(conversation.dernierDesAutres!.texte)}'}',
    Situation.invitation => '$_principal te propose de se voir',
    Situation.remerciement => '$_principal te remercie',
    Situation.question =>
      '$_principal te pose une question : '
          '${_cite(conversation.dernierDesAutres!.texte)}',
    Situation.salutation => '$_principal prend de tes nouvelles',
    Situation.neutre => 'l’échange reste plutôt factuel',
  };

  String get _tensionEnClair => switch (tension) {
    0 => 'Le ton reste calme.',
    1 => 'Le ton se tend un peu.',
    _ => 'L’échange devient tendu.',
  };

  String get _tour => _cEstAMoi
      ? 'Le dernier message vient de $_principal : c’est à toi de répondre.'
      : 'Tu as envoyé le dernier message.';

  /// Lecture courte, quand une conversation est collée sans demande.
  String get lectureCourte {
    final n = conversation.lignes.length;
    return 'Je vois un échange entre $_autres et toi ($n message${n > 1 ? 's' : ''}). '
        '${_phrase(_majuscule(_situationEnClair))} $_tensionEnClair\n\n$_tour';
  }

  /// Avant de proposer une réponse.
  String get avantReponse {
    final base = switch (situation) {
      Situation.reproche =>
        '$_enTete attend surtout que tu reconnaisses le problème. '
            'Une réponse courte, sincère et sans te justifier trop passera '
            'mieux.',
      Situation.invitation =>
        'Tu peux accepter, proposer un autre moment ou décliner gentiment.',
      Situation.remerciement => 'Une réponse simple et chaleureuse suffit.',
      Situation.question => 'Le plus simple est de répondre directement.',
      Situation.salutation => 'Une réponse légère convient très bien.',
      Situation.neutre => 'Une réponse claire et brève convient.',
    };
    return '$base Choisis le ton qui te ressemble.';
  }

  /// Résumé de démonstration : l'essentiel de chaque participant.
  String get resume {
    final lignes = <String>[];
    for (final p in conversation.participants) {
      final siens = conversation.lignes
          .where((l) => l.locuteur.toLowerCase() == p.toLowerCase())
          .toList();
      final qui = LigneConversation(p, '').estMoi ? 'Toi' : p;
      final dits = siens.length == 1
          ? _cite(siens.first.texte)
          : '${_cite(siens.first.texte)} … ${_cite(siens.last.texte)}';
      lignes.add('• $qui : $dits');
    }
    return 'En bref : ${_phrase(_situationEnClair)} $_tensionEnClair\n\n'
        '${lignes.join('\n')}\n\n$_tour';
  }

  /// Compréhension du contexte.
  String get comprehension {
    final suite = switch (situation) {
      Situation.reproche =>
        excuseDeMoi
            ? 'Tu as déjà présenté tes excuses, mais $_principal insiste : ce n’est '
                  'sans doute pas un fait isolé, d’où sa frustration.'
            : '$_enTete ressent un manque de considération et te le '
                  'fait savoir.',
      Situation.invitation =>
        '$_enTete aimerait passer un moment avec toi et attend ta réponse.',
      Situation.remerciement => 'L’échange se termine sur une note positive.',
      Situation.question => '$_enTete attend une information de ta part.',
      Situation.salutation => 'C’est une prise de contact simple et amicale.',
      Situation.neutre => 'Rien d’inquiétant ne ressort de l’échange.',
    };
    return '${_phrase(_majuscule(_situationEnClair))} $suite $_tensionEnClair\n\n$_tour';
  }

  /// Réponse à une question libre sur la conversation.
  String analyser(String question) {
    final q = DetecteurIntention.normaliser(question);
    bool parle(List<String> mots) => mots.any((m) => ' $q '.contains(' $m '));

    if (parle(const ['mal repondu', 'bien repondu', 'j ai mal', 'j ai bien'])) {
      final moi = conversation.lignes.where((l) => l.estMoi).toList();
      if (moi.isEmpty) {
        return 'Je ne vois pas encore de message de ta part dans cet échange. '
            'Indique tes messages avec « Moi : » pour que je les distingue.';
      }
      if (situation == Situation.reproche && excuseDeMoi) {
        return 'Ta réponse n’était pas mauvaise : tu as présenté tes excuses, c’est '
            'l’essentiel. Mais elle était courte, et la justification peut '
            'sonner comme une excuse toute faite. $_enTete insiste : ce qui '
            'compte surtout, c’est que tu reconnaisses le problème, plutôt '
            'qu’une explication.';
      }
      if (situation == Situation.reproche) {
        return 'Ta réponse ne reconnaît pas vraiment le reproche, ce qui peut '
            'donner l’impression de l’esquiver. Un simple « tu as raison, '
            'j’aurais dû… » apaiserait sans doute les choses.';
      }
      return 'Ta réponse me paraît adaptée : elle répond à ce qui t’était dit, '
          'sans malentendu visible. $_tensionEnClair';
    }
    if (parle(const [
      'tendu',
      'tendue',
      'grave',
      'fache',
      'fachee',
      'enerve',
      'enervee',
      'en colere',
      'vexe',
      'vexee',
      'm en veut',
    ])) {
      return switch (tension) {
        0 => 'Non, l’échange reste calme. Rien ne montre de colère.',
        1 =>
          'Un peu. $_enTete montre de l’agacement, mais rien '
              'd’irrattrapable : une réponse sincère suffira sans doute.',
        _ =>
          'Oui, l’échange se tend. $_enTete insiste, ce qui montre une '
              'vraie frustration. Mieux vaut apaiser que te justifier.',
      };
    }
    if (parle(const [
      'veut dire',
      'veulent dire',
      'pourquoi il',
      'pourquoi elle',
      'qu est ce qu il veut',
      'qu est ce qu elle veut',
    ])) {
      final d = conversation.dernierDesAutres;
      final cite = d == null
          ? ''
          : 'Quand $_principal écrit ${_cite(d.texte)}, ';
      return switch (situation) {
        Situation.reproche =>
          '$cite${cite.isEmpty ? 'C’est' : 'c’est'} probablement le signe que ce '
              'n’est pas la première fois que la situation se produit. '
              '$_enTete a besoin de sentir que son ressenti compte pour '
              'toi.',
        Situation.invitation =>
          '${cite}il s’agit simplement d’une envie de te voir.',
        Situation.question =>
          '${cite}c’est une vraie question : '
              '$_principal attend une réponse précise.',
        _ => '${cite}rien n’indique de sous-entendu particulier.',
      };
    }
    // Avis général.
    return '${_phrase(_majuscule(_situationEnClair))} $_tensionEnClair '
        '${situation == Situation.reproche ? 'À ta place, je reconnaîtrais le problème simplement, sans trop me justifier.' : 'Rien d’inquiétant : tu peux répondre naturellement.'}\n\n$_tour';
  }

  /// Termine une phrase par un point, sauf si elle finit déjà par une
  /// citation ponctuée (« … fois. »).
  static String _phrase(String t) =>
      RegExp(r'[.!?…]( »)?$').hasMatch(t) ? t : '$t.';

  static String _majuscule(String t) =>
      t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}
