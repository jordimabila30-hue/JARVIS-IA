import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/message_conversation.dart';
import '../conversations/correspondance_conversations.dart';
import '../conversations/depot_conversations.dart';
import '../conversations/synchro_echanges_locaux.dart';
import '../ecriture/ecriture_progressive.dart';
import '../ecriture/texte_en_direct.dart';
import '../voice_command_service.dart';
import 'detecteur_conversation.dart';
import 'detecteur_intention.dart';
import 'moteur_conversation.dart';
import 'moteur_conversation_ia.dart';

/// Conversation écrite avec JARVIS : une seule discussion, dans laquelle
/// l'utilisateur peut parler normalement, coller une conversation externe,
/// demander un résumé ou une réponse.
///
/// message → détection (conversation collée ? intention ?) → moteur →
/// réponse dans le fil. Les envois sont traités dans l'ordre, un à la
/// fois : jamais de réponse en double ni d'état bloqué.
///
/// Chaque réponse de JARVIS s'écrit progressivement dans sa bulle
/// ([MessageConversation.ecriture]) : texte complet d'un coup (réponse
/// locale) ou fragments de l'IA dès leur arrivée. Trois étapes séparées :
/// réception (tampon [TexteEnDirect]), affichage (animation, côté écran,
/// qui peut finir après la réception), enregistrement (réponse finale,
/// une seule fois, indépendante de l'animation).
///
/// Les détecteurs locaux ne font qu'un pré-classement : le moteur reçoit
/// toujours le texte réel et l'historique ([DemandeJarvis]), pour qu'un
/// moteur d'IA puisse les remplacer sans changer la session ni l'écran.
class ConversationSession extends ChangeNotifier {
  ConversationSession({
    MoteurConversation? moteur,
    this.delaiReflexion = const Duration(milliseconds: 450),
    DateTime Function()? horloge,
    this.depot,
    CorrespondanceConversations? correspondance,
  }) : moteur = moteur ?? MoteurConversationLocal(),
       _horloge = horloge ?? DateTime.now,
       correspondance = correspondance ?? CorrespondanceConversations();

  final MoteurConversation moteur;

  /// Conversations enregistrées sur le serveur (null : aucun compte, tout
  /// reste en mémoire).
  final DepotConversations? depot;

  /// Conversation du fil <-> conversation serveur (partagée avec le moteur
  /// IA, qui l'établit à la première réponse).
  final CorrespondanceConversations correspondance;

  /// La conversation serveur [idServeur] n'existe plus (supprimée depuis
  /// un autre appareil).
  void Function(String idServeur)? surConversationIntrouvable;

  /// Un échange avec l'IA vient d'être enregistré par le serveur.
  VoidCallback? surEchangeEnregistre;

  /// Échange ordinaire traité sur l'appareil (heure, calcul…), à
  /// enregistrer dans la conversation du compte. Jamais appelé pour une
  /// conversation collée ou importée, ni pour un message d'erreur.
  void Function(EchangeLocal echange)? surEchangeLocal;

  /// Courte « réflexion » visible avant la réponse.
  final Duration delaiReflexion;

  /// Heure de création des messages (horloge de l'appareil ; fixe dans
  /// les tests).
  final DateTime Function() _horloge;

  static const _detecteur = DetecteurConversation();
  static const _intentions = DetecteurIntention();

  final List<MessageConversation> messages = [];

  /// Vrai pendant que JARVIS prépare sa réponse, avant que son texte
  /// commence à arriver (ensuite, il s'écrit dans sa bulle).
  bool get enReflexion => _enAttente > 0;
  int _enAttente = 0;

  /// Réponses en préparation ou en réception.
  int _enCours = 0;

  /// Vrai tant qu'aucun message n'est affiché (une conversation en cours
  /// de chargement n'est pas vide).
  bool get vide => messages.isEmpty && !chargement;

  /// Vrai pendant le chargement de la conversation affichée depuis le
  /// serveur.
  bool get chargement => _chargementDe != null && _chargementDe == _idCourant;
  String? _chargementDe;

  /// Le serveur garde des messages plus anciens que ceux affichés.
  bool get plusAnciens => _plusAnciens;
  bool _plusAnciens = false;

  /// UUID serveur de la conversation affichée, s'il existe.
  String? get idServeurCourant {
    final id = _idCourant;
    return id == null ? null : correspondance.serveur(id);
  }

  /// Dernière conversation externe de la discussion : les questions
  /// suivantes s'y rapportent (« et là, je dis quoi ? »).
  ConversationExterne? get conversationEnCours => _derniere;
  ConversationExterne? _derniere;

  /// « Poser une question » : le prochain message porte sur la
  /// conversation, même sans mot-clé.
  bool get questionAttendue => _questionAttendue;
  bool _questionAttendue = false;

  int _id = 0;

  // Change à chaque « nouvelle conversation » : une réponse en retard
  // n'arrive jamais dans le fil vidé.
  int _generation = 0;
  Future<void> _file = Future<void>.value();
  bool _ferme = false;

  /// Envoie un message de l'utilisateur (texte libre, conversation collée,
  /// ou les deux).
  Future<void> envoyer(String texte) {
    final t = texte.trim();
    if (t.isEmpty) return Future<void>.value();
    final generation = _generation;
    return _file = _file.then((_) => _traiter(t, generation));
  }

  /// Phrase validée du mode vocal : ajoutée au fil comme un message, la
  /// réponse aussi (même moteur, même contexte). Renvoie la réponse à
  /// prononcer, ou null si la conversation a été effacée entre-temps.
  ///
  /// Pas de réflexion visible ici : le mode vocal a la sienne.
  Future<ReponseVocale?> repondreVocal(String phrase) {
    final t = phrase.trim();
    if (t.isEmpty) return Future.value(null);
    final generation = _generation;
    final resultat = Completer<ReponseVocale?>();
    _file = _file.then((_) async {
      try {
        final r = await _traiter(t, generation, vocal: true);
        resultat.complete(
          r == null
              ? null
              : ReponseVocale(
                  // Réponse interrompue : le texte reçu, puis pourquoi il
                  // s'arrête. Toujours prononcée une seule fois, en entier.
                  r.interrompue ? '${r.texte} ${r.incident}' : r.texte,
                  source: SourceReponse.locale,
                  terminerSession: r.terminerSession,
                ),
        );
      } catch (e) {
        // Jamais de session vocale bloquée en attente d'une réponse.
        debugPrint('[JARVIS conversation] phrase vocale non traitée : $e');
        if (!resultat.isCompleted) resultat.complete(null);
      }
    });
    return resultat.future;
  }

  Future<ReponseJarvis?> _traiter(
    String texte,
    int generation, {
    bool vocal = false,
  }) async {
    if (_ferme || generation != _generation) return null;
    final analyse = _detecteur.analyser(
      texte,
      avecDemande: _intentions.concerneUneConversation,
    );
    final nouvelle = analyse.conversation;
    final connue = nouvelle ?? _derniere;
    var intention = _intentions.detecter(
      analyse.demande,
      conversationConnue: connue != null,
    );
    if (_questionAttendue && connue != null) {
      if (intention == IntentionMessage.discussion) {
        intention = IntentionMessage.analyse;
      }
    }
    _questionAttendue = false;
    if (nouvelle != null) _derniere = nouvelle;

    final historique = List<MessageConversation>.unmodifiable(messages);
    _idCourant ??= _nouvelIdentifiant();
    messages.add(
      MessageConversation(
        id: _id++,
        auteur: AuteurMessage.utilisateur,
        heure: _horloge(),
        texte: analyse.demande,
        conversation: nouvelle,
        vocal: vocal,
      ),
    );
    return _repondre(
      DemandeJarvis(
        texte: analyse.demande,
        texteComplet: texte,
        historique: historique,
        intention: intention,
        conversation: connue,
        conversationNouvelle: nouvelle != null,
        vocale: vocal,
        idConversation: _idCourant,
      ),
      vocal: vocal,
    );
  }

  Future<ReponseJarvis?> _repondre(
    DemandeJarvis demande, {
    bool vocal = false,
  }) async {
    final generation = _generation;
    _enCours++;
    _enAttente++;
    notifyListeners();
    // Réception : tampon des fragments de l'IA (texte mis en forme au fur
    // et à mesure, Markdown inachevé masqué).
    final flux = TexteEnDirect(
      nettoyer: MoteurConversationIA.texteSimpleProvisoire,
    );
    final ecriture = EcritureProgressive(flux);
    int? idBulle;
    DateTime? heureBulle;
    var attente = true;
    void finAttente() {
      if (!attente) return;
      attente = false;
      _enAttente--;
    }

    void surFragment(String fragment) {
      if (_ferme) return;
      flux.ajouter(fragment);
      // Fil changé avant le premier fragment : aucune bulle ici, la
      // réponse rejoindra sa conversation à la fin.
      if (idBulle != null || generation != _generation) return;
      // Premier fragment : la bulle de JARVIS remplace la réflexion, le
      // texte s'y écrit pendant que la suite arrive.
      finAttente();
      final id = idBulle = _id++;
      final heure = heureBulle = _horloge();
      messages.add(
        MessageConversation(
          id: id,
          auteur: AuteurMessage.jarvis,
          heure: heure,
          conversation: demande.conversation,
          vocal: vocal,
          ecriture: ecriture,
          redaction: true,
        ),
      );
      notifyListeners();
    }

    ReponseJarvis reponse;
    try {
      if (!vocal) await Future<void>.delayed(delaiReflexion);
      // Fil changé pendant la réflexion : la demande n'est pas envoyée
      // (aucune conversation créée pour rien sur le serveur).
      if (_ferme || generation != _generation) {
        _enCours--;
        finAttente();
        ecriture.arreter();
        if (!_ferme) notifyListeners();
        return null;
      }
      reponse = await moteur.repondre(demande.avecFragments(surFragment));
    } catch (e) {
      debugPrint('[JARVIS conversation] réponse impossible : $e');
      final recu = MoteurConversationIA.texteSimple(flux.brut);
      reponse = recu.isEmpty
          ? const ReponseJarvis(
              'Je n’ai pas réussi à traiter ce message. Peux-tu reformuler ?',
              erreur: true,
            )
          : ReponseJarvis(
              recu,
              erreur: true,
              incident:
                  'Réponse interrompue avant la fin. Renvoyez votre message '
                  'pour obtenir la réponse complète.',
            );
    }
    _enCours--;
    finAttente();
    if (_ferme) {
      ecriture.arreter();
      return null;
    }
    // Fin de la réception : le texte final remplace le texte reçu (jamais
    // une réponse interrompue présentée comme complète). L'écriture
    // continue jusqu'au bout si elle était en retard.
    if (reponse.interrompue) {
      flux.interrompre(reponse.texte);
    } else {
      flux.terminer(reponse.texte);
    }
    final idServeur = reponse.idServeur;
    final message = MessageConversation(
      // Même identifiant que la bulle : une seule bulle, finalisée une fois.
      id: idBulle ?? _id++,
      auteur: AuteurMessage.jarvis,
      heure: heureBulle ?? _horloge(),
      texte: reponse.texte,
      // Conversation de référence (choix du ton, raccourcis).
      conversation: demande.conversation,
      actions: reponse.actions,
      choixTon: reponse.choixTon,
      vocal: vocal,
      idServeur: idServeur,
      enregistre: idServeur != null,
      ecriture: ecriture,
      incident: reponse.incident,
    );
    if (idServeur != null) surEchangeEnregistre?.call();
    if (generation != _generation) {
      // Le fil a changé pendant la réponse (IA : plusieurs secondes). Elle
      // ne va jamais dans le fil affiché, mais rejoint sa propre
      // conversation, mise de côté ou rouverte, comme sur le serveur ;
      // conversation supprimée : perdue. Rien à dire en vocal. Jamais vue
      // en train de s'écrire : elle sera affichée entière.
      if (idBulle == null) ecriture.toutAfficher();
      _rangerReponseTardive(demande, message);
      notifyListeners();
      return null;
    }
    if (idServeur != null) _marquerEnregistree(messages, demande.texte);
    _placer(messages, message);
    _confierEchangeLocal(demande, reponse, message.id);
    notifyListeners();
    return reponse;
  }

  /// Remplace le message de même identifiant (bulle en réception), ou
  /// l'ajoute à la fin.
  static void _placer(
    List<MessageConversation> liste,
    MessageConversation message,
  ) {
    final i = liste.lastIndexWhere((m) => m.id == message.id);
    if (i < 0) {
      liste.add(message);
    } else {
      liste[i] = message;
    }
  }

  /// Réponse locale ordinaire : les deux messages reçoivent l'identifiant
  /// de leur future ligne serveur (une actualisation les reconnaîtra), et
  /// l'échange part dans la file d'enregistrement. L'affichage n'attend
  /// rien.
  void _confierEchangeLocal(
    DemandeJarvis demande,
    ReponseJarvis reponse,
    int idReponse,
  ) {
    final confier = surEchangeLocal;
    final idLocal = demande.idConversation;
    if (confier == null ||
        idLocal == null ||
        reponse.idServeur != null ||
        reponse.erreur ||
        demande.conversation != null ||
        reponse.texte.trim().isEmpty ||
        messages.length < 2) {
      return;
    }
    final r = messages.lastIndexWhere((m) => m.id == idReponse);
    if (r < 1) return;
    var q = -1;
    for (var i = r - 1; i >= 0; i--) {
      final m = messages[i];
      if (!m.deJarvis && m.idServeur == null && m.texte == demande.texte) {
        q = i;
        break;
      }
    }
    if (q < 0 || demande.texte.trim().isEmpty) return;
    final echange = EchangeLocal(
      idQuestion: EchangeLocal.nouvelId(),
      idReponse: EchangeLocal.nouvelId(),
      idLocal: idLocal,
      question: messages[q].texte,
      reponse: messages[r].texte,
      questionA: messages[q].heure,
      reponseA: messages[r].heure,
    );
    messages[q] = messages[q].avecIdPrevu(echange.idQuestion);
    messages[r] = messages[r].avecIdPrevu(echange.idReponse);
    confier(echange);
  }

  void _rangerReponseTardive(
    DemandeJarvis demande,
    MessageConversation message,
  ) {
    final id = demande.idConversation;
    if (id == null) return;
    final enregistre = message.enregistre;
    if (id == _idCourant) {
      if (enregistre) _marquerEnregistree(messages, demande.texte);
      _placer(messages, message);
      return;
    }
    final i = _archives.indexWhere((a) => a.id == id);
    if (i < 0) {
      message.ecriture?.arreter();
      return;
    }
    final liste = [..._archives[i].messages];
    if (enregistre) _marquerEnregistree(liste, demande.texte);
    _placer(liste, message);
    _archives[i] = _archives[i]._avec(liste);
  }

  /// La question de l'utilisateur a été enregistrée avec la réponse de
  /// l'IA : sa ligne serveur sera reconnue (et jamais affichée en double)
  /// à la prochaine actualisation.
  static void _marquerEnregistree(
    List<MessageConversation> liste,
    String texte,
  ) {
    for (var i = liste.length - 1; i >= 0; i--) {
      final m = liste[i];
      if (m.deJarvis || m.enregistre) continue;
      if (m.texte.trim() != texte.trim()) continue;
      liste[i] = m.enregistreSurServeur();
      return;
    }
  }

  /// Ton choisi pour la proposition du message [id] : la réponse proposée
  /// est (re)calculée, sans nouveau message.
  Future<void> choisirTon(int id, TonReponse ton) async {
    final i = messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final conversation = messages[i].conversation;
    if (conversation == null) return;
    final generation = _generation;
    final texte = await moteur.proposerReponse(conversation, ton);
    if (_ferme || generation != _generation) return;
    final j = messages.indexWhere((m) => m.id == id);
    if (j < 0) return;
    messages[j] = messages[j].avecReponse(ton, texte);
    notifyListeners();
  }

  /// Raccourci discret sous une réponse de JARVIS.
  Future<void> action(int id, ActionRapide action) {
    final message = messages.where((m) => m.id == id).firstOrNull;
    final conversation = message?.conversation;
    if (conversation == null) return Future<void>.value();
    if (action == ActionRapide.question) {
      _questionAttendue = true;
      notifyListeners();
      return Future<void>.value();
    }
    final (texte, intention) = switch (action) {
      ActionRapide.comprendre => (
        'Aide-moi à comprendre cette conversation.',
        IntentionMessage.comprendre,
      ),
      ActionRapide.resumer => (
        'Résume cette conversation.',
        IntentionMessage.resume,
      ),
      _ => ('Qu’est-ce que je peux répondre ?', IntentionMessage.reponse),
    };
    final generation = _generation;
    return _file = _file.then((_) async {
      if (_ferme || generation != _generation) return;
      _questionAttendue = false;
      final historique = List<MessageConversation>.unmodifiable(messages);
      _idCourant ??= _nouvelIdentifiant();
      messages.add(
        MessageConversation(
          id: _id++,
          auteur: AuteurMessage.utilisateur,
          heure: _horloge(),
          texte: texte,
        ),
      );
      await _repondre(
        DemandeJarvis(
          texte: texte,
          texteComplet: texte,
          historique: historique,
          intention: intention,
          conversation: conversation,
          idConversation: _idCourant,
        ),
      );
    });
  }

  // --- Plusieurs conversations -------------------------------------------
  //
  // « Nouvelle conversation » met la conversation actuelle de côté (en
  // mémoire, avec son contexte) au lieu de la perdre : le menu latéral la
  // liste et peut la rouvrir. Pas encore d'enregistrement sur l'appareil.

  /// Identifiant stable de la conversation affichée (null tant qu'elle est
  /// vide).
  String? get idCourant => _idCourant;
  String? _idCourant;
  int _conversationsCreees = 0;

  final List<ConversationArchivee> _archives = [];

  /// Conversations mises de côté, la plus récente d'abord.
  List<ConversationArchivee> get archives => List.unmodifiable(_archives);

  // Horloge système (pas celle des messages) : l'identifiant ne change
  // jamais l'heure affichée des messages.
  String _nouvelIdentifiant() =>
      'c${DateTime.now().microsecondsSinceEpoch}-${_conversationsCreees++}';

  void _archiverCourante() {
    final id = _idCourant;
    if (id == null || messages.isEmpty) return;
    _archives.insert(
      0,
      ConversationArchivee._(
        id: id,
        messages: List.unmodifiable(messages),
        derniere: _derniere,
        questionAttendue: _questionAttendue,
        contexte: moteur.capturerContexte(),
        plusAnciens: _plusAnciens,
      ),
    );
  }

  /// Nouvelle conversation : retour à l'accueil. La conversation actuelle
  /// est mise de côté (rouvrable depuis le menu).
  void effacer() {
    _generation++;
    _archiverCourante();
    // Contexte distinct pour la nouvelle conversation.
    moteur.reinitialiser();
    messages.clear();
    _idCourant = null;
    _derniere = null;
    _questionAttendue = false;
    _plusAnciens = false;
    notifyListeners();
  }

  /// Rouvre une conversation mise de côté : ses messages et son contexte
  /// reviennent ; la conversation actuelle est mise de côté à son tour.
  /// Faux si [id] est inconnu.
  bool ouvrir(String id) {
    if (id == _idCourant) return true;
    final i = _archives.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    // Une réponse encore en préparation n'arrive jamais dans l'autre fil.
    _generation++;
    final cible = _archives.removeAt(i);
    _archiverCourante();
    messages
      ..clear()
      ..addAll(cible.messages);
    _idCourant = cible.id;
    _derniere = cible.derniere;
    _questionAttendue = cible.questionAttendue;
    _plusAnciens = cible.plusAnciens;
    moteur.restaurerContexte(cible.contexte);
    notifyListeners();
    // Enregistrée sur le serveur : un autre appareil l'a peut-être
    // poursuivie entre-temps.
    if (idServeurCourant != null) unawaited(rafraichir());
    return true;
  }

  // --- Conversations enregistrées sur le serveur ---------------------------
  //
  // Les messages viennent du serveur (lecture seule : seul le backend les
  // enregistre). Une conversation ouverte depuis le serveur garde son UUID
  // comme identifiant local. Les réponses locales (heure, calcul...) et les
  // conversations collées restent sur l'appareil.

  /// Ouvre la conversation serveur [idServeur] : la conversation actuelle
  /// est mise de côté, les derniers messages sont chargés, et la suite de
  /// la discussion reprend le contexte du serveur.
  Future<bool> ouvrirServeur(String idServeur) async {
    if (depot == null) return false;
    final local = correspondance.local(idServeur);
    if (local != null &&
        (local == _idCourant || _archives.any((a) => a.id == local))) {
      return ouvrir(local);
    }
    _generation++;
    _archiverCourante();
    moteur.reinitialiser();
    messages.clear();
    _idCourant = idServeur;
    _derniere = null;
    _questionAttendue = false;
    _plusAnciens = false;
    correspondance.associer(idServeur, idServeur);
    await _charger(idServeur);
    return true;
  }

  /// Messages plus anciens de la conversation affichée (pagination).
  Future<void> chargerPlusAnciens() async {
    final serveur = idServeurCourant;
    final depot = this.depot;
    if (depot == null || serveur == null || !_plusAnciens || chargement) {
      return;
    }
    DateTime? avant;
    for (final m in messages) {
      if (m.idServeur != null) {
        avant = m.heure;
        break;
      }
    }
    if (avant == null) return;
    final id = _idCourant!;
    final generation = _generation;
    _chargementDe = id;
    notifyListeners();
    try {
      final page = await depot.messages(serveur, avant: avant);
      if (_ferme || generation != _generation || id != _idCourant) return;
      final connus = {for (final m in messages) ?m.idServeur};
      messages.insertAll(0, [
        for (final r in page.messages)
          if (r.role != 'system' && !connus.contains(r.id)) _depuisServeur(r),
      ]);
      _plusAnciens = page.plusAnciens;
    } on EchecSynchro catch (e) {
      debugPrint('[JARVIS synchro] messages anciens non chargés : $e');
    } finally {
      if (_chargementDe == id) _chargementDe = null;
      if (!_ferme) notifyListeners();
    }
  }

  /// Relit les derniers messages de la conversation affichée (retour au
  /// premier plan, autre appareil) et ajoute ceux qui manquent, sans
  /// jamais en dupliquer. Rien pendant une réponse ou un chargement.
  Future<void> rafraichir() async {
    final serveur = idServeurCourant;
    if (depot == null || serveur == null || chargement || _enCours > 0) {
      return;
    }
    await _charger(serveur);
  }

  Future<void> _charger(String serveur) async {
    final id = _idCourant!;
    final generation = _generation;
    _chargementDe = id;
    notifyListeners();
    try {
      final page = await depot!.messages(serveur);
      if (_ferme || generation != _generation || id != _idCourant) return;
      messages.removeWhere((m) => m.provisoire);
      final premierChargement = messages.isEmpty;
      _fusionner(page.messages);
      if (premierChargement) _plusAnciens = page.plusAnciens;
    } on EchecSynchro catch (e) {
      if (_ferme || generation != _generation || id != _idCourant) return;
      debugPrint('[JARVIS synchro] conversation non chargée : $e');
      if (e.type == ErreurSynchro.introuvable) {
        correspondance.oublier(id);
        surConversationIntrouvable?.call(serveur);
      }
      // Déjà affichée : elle reste telle quelle (hors connexion).
      if (messages.any((m) => !m.provisoire)) return;
      messages
        ..clear()
        ..add(
          MessageConversation(
            id: _id++,
            auteur: AuteurMessage.jarvis,
            heure: _horloge(),
            provisoire: true,
            texte: switch (e.type) {
              ErreurSynchro.introuvable =>
                'Cette conversation n’existe plus : elle a peut-être été '
                    'supprimée depuis un autre appareil.',
              ErreurSynchro.sessionExpiree => e.type.message,
              _ =>
                'Impossible de charger cette conversation pour le moment. '
                    '${e.type.message} Elle sera rechargée dès que possible.',
            },
          ),
        );
    } finally {
      if (_chargementDe == id) _chargementDe = null;
      if (!_ferme) notifyListeners();
    }
  }

  /// Ajoute les lignes serveur absentes du fil. Une ligne déjà affichée
  /// est reconnue par son UUID, ou (pour une question envoyée depuis cet
  /// appareil, dont le serveur ne renvoie pas l'UUID) par son texte.
  void _fusionner(List<MessageServeur> lignes) {
    final nouveaux = <MessageConversation>[];
    for (final r in lignes) {
      if (r.role == 'system') continue;
      if (messages.any((m) => m.idServeur == r.id)) continue;
      if (r.role == 'user') {
        final i = messages.indexWhere(
          (m) =>
              !m.deJarvis &&
              m.enregistre &&
              m.idServeur == null &&
              m.texte.trim() == r.contenu.trim(),
        );
        if (i >= 0) {
          messages[i] = messages[i].avecIdServeur(r.id);
          continue;
        }
      }
      nouveaux.add(_depuisServeur(r));
    }
    messages.addAll(nouveaux);
  }

  MessageConversation _depuisServeur(MessageServeur r) {
    final jarvis = r.role != 'user';
    return MessageConversation(
      id: _id++,
      auteur: jarvis ? AuteurMessage.jarvis : AuteurMessage.utilisateur,
      heure: r.date,
      texte: jarvis ? MoteurConversationIA.texteSimple(r.contenu) : r.contenu,
      idServeur: r.id,
      enregistre: true,
    );
  }

  /// Supprime une conversation (mise de côté ou affichée) : ses messages
  /// et son contexte sont oubliés, sans être mis de côté. Si c'est la
  /// conversation affichée, l'accueil revient vide, et une réponse encore
  /// en préparation n'y arrive jamais. Faux si [id] est inconnu.
  bool supprimer(String id) {
    if (id == _idCourant) {
      _generation++;
      moteur.reinitialiser();
      _arreterEcritures(messages);
      messages.clear();
      _idCourant = null;
      _derniere = null;
      _questionAttendue = false;
      _plusAnciens = false;
      notifyListeners();
      return true;
    }
    final i = _archives.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    _arreterEcritures(_archives.removeAt(i).messages);
    notifyListeners();
    return true;
  }

  /// Écritures des messages retirés : plus rien à animer ni à suivre.
  static void _arreterEcritures(List<MessageConversation> liste) {
    for (final m in liste) {
      m.ecriture?.arreter();
    }
  }

  @override
  void dispose() {
    _ferme = true;
    _arreterEcritures(messages);
    for (final a in _archives) {
      _arreterEcritures(a.messages);
    }
    super.dispose();
  }
}

/// Conversation mise de côté : ses messages et de quoi la reprendre
/// exactement où elle en était.
class ConversationArchivee {
  const ConversationArchivee._({
    required this.id,
    required this.messages,
    required this.derniere,
    required this.questionAttendue,
    required this.contexte,
    this.plusAnciens = false,
  });

  final String id;
  final List<MessageConversation> messages;
  final ConversationExterne? derniere;
  final bool questionAttendue;

  /// Contexte du moteur (prénom, sujet…), opaque.
  final Object? contexte;

  /// Le serveur garde des messages plus anciens que ceux chargés.
  final bool plusAnciens;

  ConversationArchivee _avec(List<MessageConversation> liste) =>
      ConversationArchivee._(
        id: id,
        messages: List.unmodifiable(liste),
        derniere: derniere,
        questionAttendue: questionAttendue,
        contexte: contexte,
        plusAnciens: plusAnciens,
      );
}
