import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/message_conversation.dart';
import '../voice_command_service.dart';
import 'detecteur_conversation.dart';
import 'detecteur_intention.dart';
import 'moteur_conversation.dart';

/// Conversation écrite avec JARVIS : une seule discussion, dans laquelle
/// l'utilisateur peut parler normalement, coller une conversation externe,
/// demander un résumé ou une réponse.
///
/// message → détection (conversation collée ? intention ?) → moteur →
/// réponse dans le fil. Les envois sont traités dans l'ordre, un à la
/// fois : jamais de réponse en double ni d'état bloqué.
///
/// Les détecteurs locaux ne font qu'un pré-classement : le moteur reçoit
/// toujours le texte réel et l'historique ([DemandeJarvis]), pour qu'un
/// moteur d'IA puisse les remplacer sans changer la session ni l'écran.
class ConversationSession extends ChangeNotifier {
  ConversationSession({
    MoteurConversation? moteur,
    this.delaiReflexion = const Duration(milliseconds: 450),
    DateTime Function()? horloge,
  }) : moteur = moteur ?? MoteurConversationLocal(),
       _horloge = horloge ?? DateTime.now;

  final MoteurConversation moteur;

  /// Courte « réflexion » visible avant la réponse.
  final Duration delaiReflexion;

  /// Heure de création des messages (horloge de l'appareil ; fixe dans
  /// les tests).
  final DateTime Function() _horloge;

  static const _detecteur = DetecteurConversation();
  static const _intentions = DetecteurIntention();

  final List<MessageConversation> messages = [];

  /// Vrai pendant que JARVIS prépare sa réponse.
  bool get enReflexion => _enCours > 0;
  int _enCours = 0;

  bool get vide => messages.isEmpty;

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
                  r.texte,
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
    notifyListeners();
    ReponseJarvis reponse;
    try {
      if (!vocal) await Future<void>.delayed(delaiReflexion);
      reponse = await moteur.repondre(demande);
    } catch (e) {
      debugPrint('[JARVIS conversation] réponse impossible : $e');
      reponse = const ReponseJarvis(
        'Je n’ai pas réussi à traiter ce message. Peux-tu reformuler ?',
      );
    }
    _enCours--;
    if (_ferme) return null;
    if (generation != _generation) {
      notifyListeners();
      return null;
    }
    messages.add(
      MessageConversation(
        id: _id++,
        auteur: AuteurMessage.jarvis,
        heure: _horloge(),
        texte: reponse.texte,
        // Conversation de référence (choix du ton, raccourcis).
        conversation: demande.conversation,
        actions: reponse.actions,
        choixTon: reponse.choixTon,
        vocal: vocal,
      ),
    );
    notifyListeners();
    return reponse;
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
    moteur.restaurerContexte(cible.contexte);
    notifyListeners();
    return true;
  }

  /// Supprime une conversation (mise de côté ou affichée) : ses messages
  /// et son contexte sont oubliés, sans être mis de côté. Si c'est la
  /// conversation affichée, l'accueil revient vide, et une réponse encore
  /// en préparation n'y arrive jamais. Faux si [id] est inconnu.
  bool supprimer(String id) {
    if (id == _idCourant) {
      _generation++;
      moteur.reinitialiser();
      messages.clear();
      _idCourant = null;
      _derniere = null;
      _questionAttendue = false;
      notifyListeners();
      return true;
    }
    final avant = _archives.length;
    _archives.removeWhere((a) => a.id == id);
    if (_archives.length == avant) return false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _ferme = true;
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
  });

  final String id;
  final List<MessageConversation> messages;
  final ConversationExterne? derniere;
  final bool questionAttendue;

  /// Contexte du moteur (prénom, sujet…), opaque.
  final Object? contexte;
}
