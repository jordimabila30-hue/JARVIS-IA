/// Une ligne d'une conversation externe (« Sarah : Tu aurais pu me
/// prévenir. »).
class LigneConversation {
  const LigneConversation(this.locuteur, this.texte, {this.heure});

  final String locuteur;
  final String texte;

  /// Heure lue dans un export (WhatsApp…), si présente.
  final String? heure;

  static const _moi = {'moi', 'me', 'je', 'perso'};

  /// Locuteurs désignés par un pronom plutôt qu'un nom.
  static const _anonymes = {'il', 'elle', 'lui', 'iel', 'ils', 'elles', 'eux'};

  /// Vrai si la ligne a été écrite par l'utilisateur lui-même.
  bool get estMoi => _moi.contains(locuteur.trim().toLowerCase());

  /// Vrai si le locuteur n'a pas de nom (« Elle : … ») : JARVIS emploie
  /// alors une formulation neutre (« la personne »), sans jamais deviner
  /// un genre.
  bool get sansNom => _anonymes.contains(locuteur.trim().toLowerCase());
}

/// Conversation externe collée ou écrite par l'utilisateur.
class ConversationExterne {
  const ConversationExterne(this.lignes);

  final List<LigneConversation> lignes;

  /// Participants, dans l'ordre d'apparition.
  List<String> get participants {
    final vus = <String>[];
    for (final l in lignes) {
      if (!vus.any((p) => p.toLowerCase() == l.locuteur.toLowerCase())) {
        vus.add(l.locuteur);
      }
    }
    return vus;
  }

  /// Participants autres que l'utilisateur.
  List<String> get autres => [
    for (final p in participants)
      if (!LigneConversation(p, '').estMoi) p,
  ];

  LigneConversation get derniere => lignes.last;

  /// Dernier message d'un autre participant, s'il y en a un.
  LigneConversation? get dernierDesAutres {
    for (final l in lignes.reversed) {
      if (!l.estMoi) return l;
    }
    return null;
  }
}

/// Qui a écrit un message du fil.
enum AuteurMessage { utilisateur, jarvis }

/// Ton d'une réponse proposée.
enum TonReponse {
  naturel('Naturel'),
  amical('Amical'),
  bienveillant('Bienveillant'),
  direct('Direct'),
  poli('Poli'),
  professionnel('Professionnel');

  const TonReponse(this.libelle);

  final String libelle;
}

/// Raccourcis discrets proposés après une conversation collée.
enum ActionRapide {
  comprendre('Comprendre'),
  resumer('Résumer'),
  repondre('Répondre'),
  question('Poser une question');

  const ActionRapide(this.libelle);

  final String libelle;
}

/// Un message du fil de conversation avec JARVIS.
///
/// Message de l'utilisateur : [texte] (sa demande) et éventuellement la
/// [conversation] qu'il a collée. Message de JARVIS : [texte], des
/// [actions] discrètes, et, pour une demande de réponse, le choix du ton
/// puis la [reponseProposee].
///
/// [heure] : moment réel de création du message (heure locale de
/// l'appareil), affiché « HH:mm » sous le message.
class MessageConversation {
  const MessageConversation({
    required this.id,
    required this.auteur,
    required this.heure,
    this.texte = '',
    this.conversation,
    this.actions = const [],
    this.choixTon = false,
    this.ton,
    this.reponseProposee,
    this.vocal = false,
  });

  final int id;
  final AuteurMessage auteur;
  final DateTime heure;
  final String texte;
  final ConversationExterne? conversation;
  final List<ActionRapide> actions;

  /// Afficher « Quel ton ? » (demande de réponse).
  final bool choixTon;
  final TonReponse? ton;
  final String? reponseProposee;

  /// Échange du mode vocal (phrase reconnue ou réponse prononcée), dans la
  /// même conversation que l'écrit.
  final bool vocal;

  bool get deJarvis => auteur == AuteurMessage.jarvis;

  MessageConversation avecReponse(TonReponse ton, String reponse) =>
      MessageConversation(
        id: id,
        auteur: auteur,
        heure: heure,
        texte: texte,
        conversation: conversation,
        actions: actions,
        choixTon: choixTon,
        ton: ton,
        reponseProposee: reponse,
        vocal: vocal,
      );
}
