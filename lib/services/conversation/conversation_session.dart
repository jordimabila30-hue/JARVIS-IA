import '../../models/capture_jointe.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/conversations/source_conversation.dart';
import '../../models/importation/piece_jointe_whatsapp.dart';
import '../../models/importation/propositions_reponse.dart';
import '../../models/importation/reference_whatsapp.dart';
import '../../models/message_conversation.dart';
import '../conversations/correspondance_conversations.dart';
import '../conversations/depot_conversations.dart';
import '../conversations/synchro_echanges_locaux.dart';
import '../api_jarvis.dart';
import '../importation/actualisation_whatsapp.dart';
import '../importation/pieces_jointes_serveur.dart';
import '../ecriture/ecriture_progressive.dart';
import '../ecriture/texte_en_direct.dart';
import '../voice_command_service.dart';
import 'consentement_analyse.dart';
import 'detecteur_conversation.dart';
import 'detecteur_intention.dart';
import 'moteur_conversation.dart';
import 'moteur_conversation_ia.dart';
import 'reponses_envoyees.dart';

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
    this.piecesJointes,
    this.reponsesEnvoyees,
    this.actualisation,
    this.consentement,
    CorrespondanceConversations? correspondance,
  }) : moteur = moteur ?? MoteurConversationLocal(),
       _horloge = horloge ?? DateTime.now,
       correspondance = correspondance ?? CorrespondanceConversations();

  final MoteurConversation moteur;

  /// Conversations enregistrées sur le serveur (null : aucun compte, tout
  /// reste en mémoire).
  final DepotConversations? depot;

  /// Pièces jointes WhatsApp enregistrées par le serveur (compte connecté).
  /// Null : elles restent en mémoire sur l'appareil.
  final ServicePiecesJointes? piecesJointes;

  /// Phase 4 : réponses déclarées envoyées (appui long), enregistrées par
  /// le serveur ; null sans compte.
  final ServiceReponsesEnvoyees? reponsesEnvoyees;

  /// Phase 5 / 5.1 : messages WhatsApp collés, affichés en bulles dans le
  /// fil (relus du serveur à l'ouverture du chat).
  final ServiceActualisationWhatsApp? actualisation;

  /// Accord de l'utilisateur pour l'analyse distante des conversations
  /// WhatsApp jointes (demandé dans le fil, révocable dans les
  /// Paramètres). Null : jamais enregistré.
  final ConsentementAnalyse? consentement;

  /// Appelé avant d'enregistrer une pièce jointe dans la conversation
  /// locale [idLocal] (échanges locaux encore en route : la conversation
  /// serveur doit être connue d'abord).
  Future<void> Function(String idLocal)? avantPieceJointe;

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

  // Interruption vocale : génération vocale en cours (annulable) et ce que
  // l'utilisateur a entendu de la réponse coupée, pour la question suivante
  // de la même conversation.
  Completer<void>? _annulationVocale;
  String? _entendu;
  String? _entenduConversation;

  /// L'utilisateur a interrompu JARVIS : la génération vocale en cours est
  /// arrêtée (le serveur garde le texte déjà généré) et [entendu] est
  /// transmis avec la question suivante (jamais un second appel).
  void interrompreReponseVocale(String entendu) {
    final a = _annulationVocale;
    _annulationVocale = null;
    if (a != null && !a.isCompleted) a.complete();
    _entendu = entendu.trim();
    _entenduConversation = _idCourant;
  }

  String? _prendreEntendu() {
    final e = _entendu;
    final meme = _entenduConversation == _idCourant;
    _entendu = null;
    _entenduConversation = null;
    return meme ? e : null;
  }

  /// Message avec une capture d'écran (JARVIS Touch) : [image] part avec
  /// CE message seulement, après l'appui sur Envoyer ; le fil garde la
  /// référence [capture]. Toujours l'IA (jamais le moteur local).
  Future<void> envoyerAvecCapture(
    String texte,
    CaptureJointe capture,
    ImageAEnvoyer image,
  ) {
    final t = texte.trim();
    if (t.isEmpty) return Future<void>.value();
    final generation = _generation;
    return _file = _file.then(
      (_) => _traiter(t, generation, capture: capture, image: image),
    );
  }

  /// Message de pièce jointe sans compte : la consigne est reçue, mais
  /// rien n'a quitté l'appareil, donc aucune analyse n'est possible.
  static String reponsePieceJointe(PieceJointeWhatsApp p) {
    final n = p.nombre;
    final messages = '$n message${n > 1 ? 's' : ''}';
    return 'J’ai bien reçu votre consigne avec la conversation WhatsApp '
        '« ${p.titre} » ($messages). Pour que je l’analyse, connectez-vous à '
        'votre compte : ces messages restent pour l’instant sur cet appareil '
        'et n’ont été envoyés à aucun serveur.';
  }

  /// Réponse au refus de l'analyse distante (locale, jamais enregistrée).
  static const refusAnalyse =
      'Entendu : je n’envoie rien à l’IA. La conversation reste enregistrée '
      'dans votre compte et consultable avec « Voir les messages ». Vous '
      'pourrez autoriser l’analyse plus tard dans les Paramètres, rubrique '
      'Confidentialité.';

  // Demandes à relancer depuis un bouton (accord donné, nouvel essai),
  // par identifiant du message de JARVIS qui porte le bouton.
  final _aRelancer = <int, DemandeJarvis>{};

  /// La conversation [id] a des conversations WhatsApp jointes.
  bool _contexteImporte(String? id) =>
      id != null && _classements[id]?.source == SourceConversation.whatsapp;

  // Pièces jointes déjà envoyées : un double appui n'envoie rien de plus.
  final _piecesEnvoyees = <String>{};

  /// Conversations classées sous une source par une pièce jointe envoyée
  /// (en mémoire ; l'enregistrement attend le stockage définitif).
  final _classements = <String, ClassementConversation>{};

  /// Classement d'une conversation (null : JARVIS, inchangé).
  ClassementConversation? classement(String idConversation) =>
      _classements[idConversation];

  /// Une consigne vient d'être envoyée avec sa pièce jointe : tout ce qu'un
  /// futur dépôt devra enregistrer (rien ne l'est pour l'instant).
  void Function(EnvoiPieceJointe envoi)? surPieceJointe;

  // Pièces jointes relues du serveur, par conversation locale.
  final _contextesConnus = <String, List<ContexteServeur>>{};

  // Ton regardé dans les dernières propositions de réponse, par
  // conversation locale (« pourquoi la deuxième ? » vise ce ton).
  final _tonsRegardes = <String, String>{};

  /// L'utilisateur affiche le ton [ton] des propositions de réponse du
  /// message [idMessage] (aucun appel à l'IA : tous les tons sont déjà là).
  void regarderTon(int idMessage, String ton, {LongueurProposition? longueur}) {
    final id = _idCourant;
    if (id == null) return;
    if (longueur != null && _dernieresPropositions()?.id == idMessage) {
      _longueursRegardees[id] = longueur;
    }
    // Seules les propositions les plus récentes du fil comptent.
    if (_dernieresPropositions()?.id != idMessage) return;
    _tonsRegardes[id] = ton;
  }

  /// Pièces jointes WhatsApp du chat affiché (phase 5 : quel contexte
  /// actualiser) : relues du serveur, ou jointes pendant cette session.
  List<ContexteServeur> get contextesCourants {
    final id = _idCourant;
    if (id == null) return const [];
    final connus = [...?_contextesConnus[id]];
    for (final m in messages) {
      final p = m.pieceJointe;
      if (p == null || connus.any((c) => c.id == p.id)) continue;
      connus.add(
        ContexteServeur(
          id: p.id,
          consigne: p.idConsigne,
          contact: p.titre,
          nombre: p.messages.length,
          creeLe: p.creeLe,
          participants: p.participants,
          moi: p.moi,
          groupe: p.groupe,
        ),
      );
    }
    return connus;
  }

  /// Ton regardé dans les propositions du message [idMessage] (les plus
  /// récentes du fil), pour que la carte le réaffiche quand la liste la
  /// reconstruit : ce que voit l'utilisateur = ce que « pourquoi la
  /// deuxième ? » vise.
  String? tonRegarde(int idMessage) {
    final id = _idCourant;
    if (id == null || _dernieresPropositions()?.id != idMessage) return null;
    return _tonsRegardes[id];
  }

  /// Longueur regardée (phase 5.1), même règle que [tonRegarde].
  LongueurProposition? longueurRegardee(int idMessage) {
    final id = _idCourant;
    if (id == null || _dernieresPropositions()?.id != idMessage) return null;
    return _longueursRegardees[id];
  }

  final _longueursRegardees = <String, LongueurProposition>{};

  /// Contact WhatsApp du chat affiché (bulle de la réponse retenue).
  String? get contactPropositions {
    final c = contextesCourants;
    return c.length == 1 ? c.single.contact : null;
  }

  /// Le dialogue avec JARVIS, sans les bulles de messages WhatsApp collés
  /// (jamais données aux moteurs comme historique du chat).
  List<MessageConversation> get _dialogue => [
    for (final m in messages)
      if (m.ajoutWhatsApp == null) m,
  ];

  /// Bulles des messages WhatsApp que l'utilisateur vient d'ajouter (le
  /// serveur les a enregistrés) : à la fin du fil, sans réponse de l'IA.
  void afficherAjouts(ContexteServeur contexte, List<MessageAjoute> ajouts) {
    // Contexte d'un autre chat : enregistré, mais pas dans CE fil.
    if (!contextesCourants.any((c) => c.id == contexte.id)) return;
    final connus = {for (final m in messages) ?m.idServeur};
    for (final a in ajouts) {
      if (connus.contains('ajout:${a.id}')) continue;
      messages.add(_bulleAjout(contexte, a, heure: _horloge()));
    }
    notifyListeners();
  }

  MessageConversation _bulleAjout(
    ContexteServeur c,
    MessageAjoute a, {
    DateTime? heure,
  }) => MessageConversation(
    id: _id++,
    auteur: a.sens == SensMessage.envoye
        ? AuteurMessage.utilisateur
        : AuteurMessage.jarvis,
    heure: heure ?? a.ajouteLe ?? _horloge(),
    idServeur: 'ajout:${a.id}',
    enregistre: true,
    ajoutWhatsApp: AjoutDansLeFil(
      contexte: c.id,
      contact: c.contact,
      message: a,
    ),
  );

  /// Chat restauré : les bulles des ajouts, à leur place (moment de
  /// l'ajout), sans doublon.
  Future<void> _chargerAjouts(
    String idLocal,
    List<ContexteServeur> contextes,
  ) async {
    final service = actualisation;
    if (service == null || contextes.isEmpty) return;
    for (final c in contextes) {
      final r = await service.ajoutes(c.id);
      if (_ferme || idLocal != _idCourant) return;
      if (r is! SuccesApi<List<MessageAjoute>>) continue;
      final serveur = {for (final a in r.valeur) 'ajout:${a.id}': a};
      var change = false;
      // Corrigés ou supprimés ailleurs : la bulle suit.
      for (var i = messages.length - 1; i >= 0; i--) {
        final b = messages[i].ajoutWhatsApp;
        if (b == null || b.contexte != c.id) continue;
        final a = serveur[messages[i].idServeur];
        if (a == null) {
          messages.removeAt(i);
          change = true;
        } else if (a.texte != b.message.texte) {
          messages[i] = messages[i].avecAjout(b.avecMessage(a));
          change = true;
        }
      }
      final connus = {for (final m in messages) ?m.idServeur};
      for (final a in r.valeur) {
        if (connus.contains('ajout:${a.id}')) continue;
        final bulle = _bulleAjout(c, a);
        final i = messages.indexWhere((m) => m.heure.isAfter(bulle.heure));
        messages.insert(i < 0 ? messages.length : i, bulle);
        change = true;
      }
      if (change) notifyListeners();
    }
  }

  /// Corrige (texte) ou supprime une bulle d'ajout ; vrai si le serveur l'a
  /// enregistré. Les messages importés ne passent jamais par ici.
  Future<bool> corrigerAjout(int idMessage, String texte) async {
    final i = messages.indexWhere((m) => m.id == idMessage);
    final b = i < 0 ? null : messages[i].ajoutWhatsApp;
    final service = actualisation;
    if (b == null || service == null || texte.trim().isEmpty) return false;
    final r = await service.modifier(
      b.contexte,
      b.message.id,
      texte: texte.trim(),
    );
    if (r is! SuccesApi || _ferme) return false;
    final j = messages.indexWhere((m) => m.id == idMessage);
    if (j >= 0) {
      messages[j] = messages[j].avecAjout(
        b.avecMessage(b.message.avecTexte(texte.trim())),
      );
      notifyListeners();
    }
    return true;
  }

  Future<bool> supprimerAjout(int idMessage) async {
    final i = messages.indexWhere((m) => m.id == idMessage);
    final b = i < 0 ? null : messages[i].ajoutWhatsApp;
    final service = actualisation;
    if (b == null || service == null) return false;
    final r = await service.supprimer(b.contexte, b.message.id);
    if (r is! SuccesApi || _ferme) return false;
    messages.removeWhere((m) => m.id == idMessage);
    notifyListeners();
    return true;
  }

  // Reprises en cours (identifiants locaux de messages) : un double appui
  // n'envoie rien de plus.
  final _reprisesEnCours = <int>{};

  /// Vrai pendant la reprise des propositions du message [idMessage].
  bool repriseEnCours(int idMessage) => _reprisesEnCours.contains(idMessage);

  /// « Reprendre » : le serveur complète SEULEMENT les combinaisons
  /// manquantes du même ensemble (aucun nouveau message, aucune consigne
  /// renvoyée). Vrai si l'ensemble est désormais complet.
  Future<bool> reprendrePropositions(int idMessage) async {
    final service = reponsesEnvoyees;
    final conversation = idServeurCourant;
    final i = messages.indexWhere((m) => m.id == idMessage);
    if (service == null || conversation == null || i < 0) return false;
    final serveur = messages[i].idServeur;
    if (serveur == null || !_reprisesEnCours.add(idMessage)) return false;
    notifyListeners();
    try {
      final r = await service.completer(
        conversation: conversation,
        message: serveur,
      );
      if (_ferme) return false;
      switch (r) {
        case EchecApi(:final type):
          debugPrint('[JARVIS propositions] reprise impossible : ${type.name}');
          return false;
        case SuccesApi(:final valeur):
          final j = messages.indexWhere((m) => m.id == idMessage);
          if (valeur == null || j < 0) return false;
          messages[j] = messages[j].avecPropositions(valeur);
          return !valeur.incomplet;
      }
    } finally {
      _reprisesEnCours.remove(idMessage);
      if (!_ferme) notifyListeners();
    }
  }

  // Bulles dont le texte est fini mais dont les propositions se préparent
  // encore côté serveur (événement `preparation`).
  final _preparations = <int>{};

  /// Vrai tant que le serveur prépare les propositions de la bulle [id].
  bool preparationEnCours(int id) => _preparations.contains(id);

  MessageConversation? _dernieresPropositions() {
    final i = messages.lastIndexWhere((m) => m.propositions != null);
    return i < 0 ? null : messages[i];
  }

  // Déclarations en cours (identifiants de propositions) : un double appui
  // n'envoie rien de plus.
  final _declarationsEnCours = <String>{};

  /// Phase 4 : l'utilisateur DÉCLARE avoir envoyé (ou n'avoir finalement
  /// pas envoyé : [envoyee] faux) la proposition [idProposition] du message
  /// [idMessage]. Le statut ne change qu'après confirmation du serveur ;
  /// rien n'est envoyé à WhatsApp. Faux en cas d'échec (statut inchangé).
  Future<bool> declarerEnvoyee(
    int idMessage,
    String idProposition, {
    bool envoyee = true,
  }) async {
    final service = reponsesEnvoyees;
    final conversation = idServeurCourant;
    final i = messages.indexWhere((m) => m.id == idMessage);
    if (service == null || conversation == null || i < 0) return false;
    final message = messages[i];
    final serveur = message.idServeur;
    if (serveur == null ||
        idProposition.isEmpty ||
        !_declarationsEnCours.add(idProposition)) {
      return false;
    }
    try {
      final r = await service.statut(
        conversation: conversation,
        message: serveur,
        proposition: idProposition,
        envoyee: envoyee,
      );
      if (_ferme) return false;
      switch (r) {
        case EchecApi(:final type, :final detail):
          debugPrint('[JARVIS envoyée] non enregistrée : ${type.name}');
          // Un autre appareil a déjà choisi dans cet ensemble : son choix
          // est relu (un seul choix actif, garanti par le serveur).
          if ((detail ?? '').contains('deja_choisi')) {
            final local = _idCourant;
            if (local != null) {
              unawaited(_chargerReferences(local, conversation));
            }
          }
          return false;
        case SuccesApi(:final valeur):
          final j = messages.indexWhere((m) => m.id == idMessage);
          final p = j < 0 ? null : messages[j].propositions;
          final local = _idCourant;
          if (p != null && envoyee && local != null) {
            // Réponse retenue : à l'annulation, ce ton et cette longueur
            // reviennent.
            for (final t in p.tons) {
              for (final x in t.propositions) {
                if (x.id != idProposition) continue;
                _tonsRegardes[local] = t.nom;
                if (x.longueur case final l?) _longueursRegardees[local] = l;
              }
            }
          }
          if (p != null) {
            messages[j] = messages[j].avecPropositions(
              p.avecEnvoyee(idProposition, valeur),
            );
            notifyListeners();
          }
          return true;
      }
    } finally {
      _declarationsEnCours.remove(idProposition);
    }
  }

  // Références relues du serveur, par conversation locale puis par UUID
  // de réponse (gardées pour les messages plus anciens chargés ensuite).
  final _referencesConnues = <String, Map<String, ReferencesReponse>>{};

  /// Références d'un chat WhatsApp restauré : relues sur le serveur, qui
  /// les vérifie de nouveau dans Supabase (jamais reconstruites ici).
  Future<void> _chargerReferences(String idLocal, String serveur) async {
    final service = piecesJointes;
    if (service == null) return;
    final r = await service.references(serveur);
    if (_ferme || idLocal != _idCourant) return;
    switch (r) {
      case EchecApi(:final type):
        debugPrint('[JARVIS références] non chargées : ${type.name}');
      case SuccesApi(:final valeur):
        _referencesConnues[idLocal] = valeur;
        if (_appliquerReferences(idLocal)) notifyListeners();
    }
  }

  /// Rattache les références connues aux réponses affichées qui n'en ont
  /// pas encore. Vrai si un message a changé.
  bool _appliquerReferences(String idLocal) {
    final connues = _referencesConnues[idLocal];
    if (connues == null || connues.isEmpty) return false;
    var change = false;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final r = m.idServeur == null ? null : connues[m.idServeur];
      // Déjà rattachées : seuls les statuts « envoyée » peuvent avoir
      // changé (autre appareil, actualisation).
      if (r == null ||
          !m.deJarvis ||
          (m.references.isNotEmpty || m.propositions != null) &&
              m.propositions?.statuts == r.propositions?.statuts) {
        continue;
      }
      messages[i] = m.avecReferences(r);
      change = true;
    }
    return change;
  }

  // Pièces jointes en cours d'enregistrement : un double appui attend.
  final _piecesEnCours = <String>{};

  /// Envoie une [consigne] avec la conversation WhatsApp [piece], liées
  /// dans un seul message. Consigne vide : rien n'est envoyé. Une même
  /// pièce jointe n'est envoyée qu'une fois.
  ///
  /// Avec un compte ([piecesJointes]), le serveur enregistre d'abord
  /// consigne et pièce jointe (une transaction, jamais l'IA) ; le message
  /// n'apparaît qu'une fois l'enregistrement confirmé. Échec : rien n'est
  /// ajouté, [PieceJointeNonEnvoyee] l'explique, et un nouvel essai avec
  /// la même pièce jointe réutilise ses identifiants (aucun doublon).
  ///
  /// La conversation affichée est gardée (ses anciens échanges restent) ;
  /// sur l'accueil vide, elle commence ici. Une fois enregistrée, la
  /// consigne est envoyée au moteur ([DemandeJarvis.repondreA] : jamais
  /// réinsérée) : le serveur analyse la conversation jointe si
  /// l'utilisateur l'a accepté, sinon JARVIS demande son accord dans le
  /// fil. Les messages WhatsApp ne sont jamais des commandes pour JARVIS.
  Future<ResultatPieceJointe> envoyerAvecPieceJointe(
    String consigne,
    PieceJointeWhatsApp piece,
  ) async {
    final t = consigne.trim();
    if (t.isEmpty ||
        _ferme ||
        _piecesEnvoyees.contains(piece.id) ||
        !_piecesEnCours.add(piece.id)) {
      return const PieceJointeIgnoree();
    }
    try {
      final generation = _generation;
      PieceJointeEnregistree? enregistree;
      final service = piecesJointes;
      if (service != null) {
        final local = _idCourant;
        if (local != null) await avantPieceJointe?.call(local);
        if (_ferme) return const PieceJointeIgnoree();
        final r = await service.enregistrer(
          piece: piece,
          consigne: t,
          conversation: local == null ? null : correspondance.serveur(local),
        );
        switch (r) {
          case EchecApi(:final type, :final detail):
            debugPrint(
              '[JARVIS pièce jointe] non enregistrée : ${type.name}'
              '${detail == null ? '' : ' ($detail)'}',
            );
            return PieceJointeNonEnvoyee(type.message);
          case SuccesApi(:final valeur):
            enregistree = valeur;
        }
        if (_ferme) return const PieceJointeIgnoree();
        _piecesEnvoyees.add(piece.id);
        surEchangeEnregistre?.call();
        if (generation != _generation) {
          // Fil changé pendant l'enregistrement : la conversation est sur
          // le serveur, le menu la retrouvera.
          return const PieceJointeEnvoyee(enregistree: true);
        }
      } else {
        _piecesEnvoyees.add(piece.id);
      }
      final enregistreeFinale = enregistree;
      final ajoute = Completer<void>();
      _file = _file.then(
        (_) => _traiterPieceJointe(
          t,
          piece,
          generation,
          enregistreeFinale,
          ajoute,
        ),
      );
      // Rendu dès que le message est dans le fil ; la réponse suit.
      await ajoute.future;
      return PieceJointeEnvoyee(enregistree: enregistree != null);
    } finally {
      _piecesEnCours.remove(piece.id);
    }
  }

  Future<void> _traiterPieceJointe(
    String consigne,
    PieceJointeWhatsApp piece,
    int generation,
    PieceJointeEnregistree? enregistree,
    Completer<void> ajoute,
  ) async {
    try {
      await _ajouterPieceJointe(
        consigne,
        piece,
        generation,
        enregistree,
        ajoute,
      );
    } finally {
      if (!ajoute.isCompleted) ajoute.complete();
    }
  }

  Future<void> _ajouterPieceJointe(
    String consigne,
    PieceJointeWhatsApp piece,
    int generation,
    PieceJointeEnregistree? enregistree,
    Completer<void> ajoute,
  ) async {
    if (_ferme || generation != _generation) return;
    final nouvelle = _idCourant == null;
    final idConversation = _idCourant ??= _nouvelIdentifiant();
    if (enregistree != null) {
      correspondance.associer(idConversation, enregistree.conversation);
    }
    final heure = _horloge();
    final id = _id++;
    messages.add(
      MessageConversation(
        id: id,
        auteur: AuteurMessage.utilisateur,
        heure: heure,
        texte: consigne,
        pieceJointe: piece,
        idServeur: enregistree?.consigne,
        enregistre: enregistree != null,
      ),
    );
    _classements[idConversation] = ClassementConversation(
      source: piece.source,
      titre: piece.titre,
      pieceJointe: piece.id,
    );
    surPieceJointe?.call(
      EnvoiPieceJointe(
        idConversation: idConversation,
        idMessage: id,
        consigne: consigne,
        pieceJointe: piece,
        nouvelleConversation: nouvelle,
        envoyeLe: heure,
      ),
    );
    if (enregistree != null) {
      notifyListeners();
      ajoute.complete();
      // La consigne enregistrée devient la question : la réponse de l'IA
      // s'écrit dans le fil et le serveur l'enregistre dans ce chat.
      await _repondre(
        DemandeJarvis(
          texte: consigne,
          intention: IntentionMessage.discussion,
          historique: List<MessageConversation>.unmodifiable(_dialogue),
          idConversation: idConversation,
          repondreA: enregistree.consigne,
          contexteImporte: true,
        ),
      );
      return;
    }
    _enAttente++;
    notifyListeners();
    ajoute.complete();
    await Future<void>.delayed(delaiReflexion);
    _enAttente--;
    if (_ferme) return;
    final texte = reponsePieceJointe(piece);
    final flux = TexteEnDirect()..terminer(texte);
    final reponse = MessageConversation(
      id: _id++,
      auteur: AuteurMessage.jarvis,
      heure: _horloge(),
      texte: texte,
      ecriture: EcritureProgressive(flux),
    );
    if (generation != _generation) {
      // Fil changé pendant la réflexion : la réponse rejoint sa
      // conversation, mise de côté.
      reponse.ecriture?.toutAfficher();
      final i = _archives.indexWhere((a) => a.id == idConversation);
      if (i >= 0) {
        _archives[i] = _archives[i]._avec([..._archives[i].messages, reponse]);
      } else {
        reponse.ecriture?.arreter();
      }
      notifyListeners();
      return;
    }
    messages.add(reponse);
    notifyListeners();
  }

  /// Rattache aux consignes relues du serveur leurs pièces jointes
  /// (métadonnées ; messages lus à la demande) et classe la conversation
  /// sous WhatsApp si elle en a.
  void _rattacherPiecesJointes(
    String idLocal,
    List<ContexteServeur> contextes,
  ) {
    if (contextes.isEmpty) return;
    // Gardés pour les messages plus anciens chargés ensuite.
    _contextesConnus[idLocal] = contextes;
    final service = piecesJointes;
    for (final c in contextes) {
      final consigne = c.consigne;
      if (consigne == null) continue;
      final i = messages.indexWhere((m) => m.idServeur == consigne);
      if (i < 0 || messages[i].pieceJointe != null) continue;
      messages[i] = messages[i].avecPieceJointe(
        PieceJointeWhatsApp.enregistree(
          id: c.id,
          idConsigne: consigne,
          titre: c.contact,
          participants: c.participants,
          moi: c.moi,
          groupe: c.groupe,
          dateIncertaine: c.datesIncertaines,
          nombre: c.nombre,
          creeLe: c.creeLe,
          debut: c.debut,
          fin: c.fin,
          chargerMessages: service == null
              ? null
              : () async => switch (await service.messages(c.id)) {
                  SuccesApi(:final valeur) => valeur,
                  EchecApi(:final type) => throw EchecChargementPieceJointe(
                    type.message,
                  ),
                },
        ),
      );
    }
    final dernier = contextes.last;
    _classements[idLocal] = ClassementConversation(
      source: SourceConversation.whatsapp,
      titre: dernier.contact,
      pieceJointe: dernier.id,
    );
  }

  /// Phrase validée du mode vocal : ajoutée au fil comme un message, la
  /// réponse aussi (même moteur, même contexte). Renvoie la réponse à
  /// prononcer, ou null si la conversation a été effacée entre-temps.
  ///
  /// Pas de réflexion visible ici : le mode vocal a la sienne.
  Future<ReponseVocale?> repondreVocal(
    String phrase, {
    void Function(String fragment)? surFragment,
  }) {
    final t = phrase.trim();
    if (t.isEmpty) return Future.value(null);
    final generation = _generation;
    final resultat = Completer<ReponseVocale?>();
    _file = _file.then((_) async {
      try {
        final r = await _traiter(
          t,
          generation,
          vocal: true,
          surFragmentVocal: surFragment,
        );
        resultat.complete(
          r == null
              ? null
              : ReponseVocale(
                  // Réponse interrompue : le texte reçu, puis pourquoi il
                  // s'arrête. Toujours prononcée une seule fois, en entier.
                  r.interrompue ? '${r.texte} ${r.incident}' : r.texte,
                  source: SourceReponse.locale,
                  terminerSession: r.terminerSession,
                  interrompue: r.interrompue,
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
    CaptureJointe? capture,
    ImageAEnvoyer? image,
    void Function(String fragment)? surFragmentVocal,
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

    final historique = List<MessageConversation>.unmodifiable(_dialogue);
    _idCourant ??= _nouvelIdentifiant();
    messages.add(
      MessageConversation(
        id: _id++,
        auteur: AuteurMessage.utilisateur,
        heure: _horloge(),
        texte: analyse.demande,
        conversation: nouvelle,
        vocal: vocal,
        capture: capture,
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
        contexteImporte: _contexteImporte(_idCourant),
        tonPropose: _tonsRegardes[_idCourant],
        longueurPropose: _longueursRegardees[_idCourant]?.name,
        propositionsMessage: _dernieresPropositions()?.idServeur,
        image: image,
        annulation: vocal ? (_annulationVocale = Completer<void>()).future : null,
        entendu: vocal ? _prendreEntendu() : null,
      ),
      vocal: vocal,
      surFragmentVocal: surFragmentVocal,
    );
  }

  Future<ReponseJarvis?> _repondre(
    DemandeJarvis demande, {
    bool vocal = false,
    void Function(String fragment)? surFragmentVocal,
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
      surFragmentVocal?.call(fragment);
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
      reponse = await moteur.repondre(
        demande.avecFragments(
          surFragment,
          surPreparation: () {
            final id = idBulle;
            if (_ferme || id == null || !_preparations.add(id)) return;
            notifyListeners();
          },
        ),
      );
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
    if (idBulle != null) _preparations.remove(idBulle);
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
    // Décision attendue : accord pour l'analyse distante, ou nouvel essai
    // d'une analyse qui a échoué (aucun texte reçu : rien d'enregistré).
    final choix = reponse.accordRequis
        ? const [ChoixJarvis.autoriserAnalyse, ChoixJarvis.refuserAnalyse]
        : reponse.erreur &&
              !reponse.interrompue &&
              (demande.repondreA != null || demande.contexteImporte)
        ? const [ChoixJarvis.reessayer]
        : const <ChoixJarvis>[];
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
      choix: choix,
      references: reponse.references.references,
      noteReferences: reponse.references.note,
      propositions: reponse.references.propositions,
    );
    if (choix.isNotEmpty) _aRelancer[message.id] = demande;
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
    if (idServeur != null && demande.repondreA == null) {
      _marquerEnregistree(messages, demande.texte);
    }
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

  /// Bouton sous une réponse de JARVIS : accord (ou refus) pour l'analyse
  /// distante des conversations WhatsApp jointes, ou nouvel essai d'une
  /// analyse échouée. La question n'est jamais renvoyée comme un nouveau
  /// message : ni consigne ni pièce jointe en double.
  Future<void> choisir(int id, ChoixJarvis choix) {
    final i = messages.indexWhere((m) => m.id == id);
    if (_ferme || i < 0 || !messages[i].choix.contains(choix)) {
      return Future<void>.value();
    }
    final demande = _aRelancer.remove(id);
    messages[i] = messages[i].sansChoix();
    notifyListeners();
    final generation = _generation;
    return _file = _file.then((_) async {
      if (_ferme || generation != _generation) return;
      switch (choix) {
        case ChoixJarvis.autoriserAnalyse:
          await consentement?.accorder();
        case ChoixJarvis.refuserAnalyse:
          await consentement?.refuser();
          if (_ferme || generation != _generation) return;
          final flux = TexteEnDirect()..terminer(refusAnalyse);
          messages.add(
            MessageConversation(
              id: _id++,
              auteur: AuteurMessage.jarvis,
              heure: _horloge(),
              texte: refusAnalyse,
              ecriture: EcritureProgressive(flux),
            ),
          );
          notifyListeners();
          return;
        case ChoixJarvis.reessayer:
          break;
      }
      if (demande == null || _ferme || generation != _generation) return;
      await _repondre(demande);
    });
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
      final historique = List<MessageConversation>.unmodifiable(_dialogue);
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
      _rattacherPiecesJointes(id, _contextesConnus[id] ?? const []);
      _appliquerReferences(id);
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
      _rattacherPiecesJointes(id, page.contextes);
      _appliquerReferences(id);
      if (premierChargement) _plusAnciens = page.plusAnciens;
      // Chat WhatsApp : les cartes de références de ses réponses.
      if (page.contextes.isNotEmpty) {
        unawaited(_chargerReferences(id, serveur));
        unawaited(_chargerAjouts(id, page.contextes));
      }
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
      capture: r.capture ? const CaptureJointe() : null,
    );
  }

  /// Supprime une conversation (mise de côté ou affichée) : ses messages
  /// et son contexte sont oubliés, sans être mis de côté. Si c'est la
  /// conversation affichée, l'accueil revient vide, et une réponse encore
  /// en préparation n'y arrive jamais. Faux si [id] est inconnu.
  bool supprimer(String id) {
    _classements.remove(id);
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

/// Issue de [ConversationSession.envoyerAvecPieceJointe].
sealed class ResultatPieceJointe {
  const ResultatPieceJointe();
}

/// Envoyée : enregistrée dans le compte ([enregistree]) ou gardée sur
/// l'appareil (aucun compte).
final class PieceJointeEnvoyee extends ResultatPieceJointe {
  const PieceJointeEnvoyee({required this.enregistree});
  final bool enregistree;
}

/// Enregistrement impossible : rien n'a été ajouté au fil ; la pièce
/// jointe et la consigne peuvent être renvoyées telles quelles.
final class PieceJointeNonEnvoyee extends ResultatPieceJointe {
  const PieceJointeNonEnvoyee(this.raison);
  final String raison;
}

/// Rien à faire (consigne vide, déjà envoyée ou en cours d'envoi).
final class PieceJointeIgnoree extends ResultatPieceJointe {
  const PieceJointeIgnoree();
}

/// Lecture des messages d'une pièce jointe enregistrée impossible.
class EchecChargementPieceJointe implements Exception {
  const EchecChargementPieceJointe(this.raison);
  final String raison;

  @override
  String toString() => raison;
}
