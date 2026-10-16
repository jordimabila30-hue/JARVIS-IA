import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../models/conversations/source_conversation.dart';
import '../../models/message_conversation.dart';
import '../conversation/conversation_session.dart';
import '../api_jarvis.dart';
import 'depot_conversations.dart';
import 'fournisseur_conversations.dart';
import 'synchro_echanges_locaux.dart';
import 'synchronisation_conversations.dart';

/// Conversations JARVIS : celle de l'accueil, celles mises de côté par
/// « Nouvelle conversation » (en mémoire), et — avec un compte — celles
/// enregistrées sur le serveur ([synchronisation]), créées sur cet
/// appareil ou sur un autre.
///
/// Une conversation classée sous une autre source par une pièce jointe
/// envoyée (WhatsApp…) n'est plus listée ici : elle l'est sous sa source
/// ([conversationsDe], [FournisseurSourceClassee]), avec le nom du contact,
/// sans que son historique bouge.
///
/// Une conversation présente à la fois en mémoire et sur le serveur n'est
/// listée qu'une fois (la version en mémoire, à jour) : la correspondance
/// des identifiants vient de [ConversationSession.correspondance]. Les
/// ouvrir passe toujours par la session.
class FournisseurJarvis extends ChangeNotifier
    implements FournisseurConversations {
  FournisseurJarvis(
    this._session, {
    this.synchronisation,
    this.echangesLocaux,
  }) {
    _session.addListener(_surSession);
    synchronisation?.addListener(_surSynchronisation);
    echangesLocaux?.addListener(_surSynchronisation);
    _session.surConversationIntrouvable = synchronisation?.oublier;
  }

  /// Échanges locaux en attente d'enregistrement (null : aucun compte).
  final SynchroEchangesLocaux? echangesLocaux;

  final ConversationSession _session;

  /// Conversations enregistrées (null : aucun compte).
  final SynchronisationConversations? synchronisation;

  // Ne prévient le menu que si la liste a changé (pas à chaque réflexion).
  String _signature = '';

  void _surSession() {
    final s = [
      _session.idCourant,
      _session.messages.length,
      _session.chargement,
      for (final a in _session.archives) '${a.id}:${a.messages.length}',
      // Un reclassement change la liste, même sans nouveau message.
      for (final id in [
        _session.idCourant,
        ..._session.archives.map((a) => a.id),
      ])
        if (id != null) _session.classement(id)?.titre ?? '',
    ].join('|');
    if (s == _signature) return;
    _signature = s;
    notifyListeners();
  }

  void _surSynchronisation() => notifyListeners();

  @override
  SourceConversation get source => SourceConversation.jarvis;

  @override
  String? get avertissement {
    final liste = synchronisation?.avertissement;
    if (liste != null) return liste;
    final e = echangesLocaux;
    if (e == null || e.enAttente == 0 || e.echec == null) return null;
    final n = e.enAttente;
    final quoi = n == 1
        ? '1 échange local n’est pas encore enregistré'
        : '$n échanges locaux ne sont pas encore enregistrés';
    return switch (e.echec!) {
      ErreurApi.sessionExpiree ||
      ErreurApi.jetonRefuse => '$quoi : reconnectez-vous.',
      _ => '$quoi (hors connexion). Touchez pour réessayer.',
    };
  }

  @override
  Future<void> actualiser({bool force = false}) async {
    // Échanges locaux d'abord : la liste relue les contient déjà.
    await echangesLocaux?.envoyer();
    await synchronisation?.actualiser(force: force);
  }

  @override
  List<ApercuConversation> get conversations =>
      conversationsDe(SourceConversation.jarvis);

  /// Conversations listées sous [source] : JARVIS (non classées), ou une
  /// messagerie à laquelle une pièce jointe envoyée les a rattachées.
  List<ApercuConversation> conversationsDe(SourceConversation source) => [
    for (final c in _toutes())
      if (c.source == source) c,
  ];

  List<ApercuConversation> _toutes() {
    final courante = _session.idCourant;
    final locales = <ApercuConversation>[
      if (courante != null && _session.messages.isNotEmpty)
        _apercu(courante, _session.messages, ouverte: true)
      else if (courante != null && _session.chargement)
        ?_apercuServeur(courante, ouverte: true),
      for (final a in _session.archives) _apercu(a.id, a.messages),
    ];
    // Déjà en mémoire (classée ou non) : la version locale suffit.
    final dejaListees = {
      for (final c in locales) _session.correspondance.serveur(c.id) ?? c.id,
    };
    return [
      ...locales,
      for (final c in synchronisation?.conversations ?? const [])
        if (!dejaListees.contains(c.id)) ?_apercuServeur(c.id),
    ];
  }

  @override
  bool ouvrir(String id) {
    if (id == _session.idCourant || _session.archives.any((a) => a.id == id)) {
      return _session.ouvrir(id);
    }
    if (synchronisation?.conversation(id) == null) return false;
    unawaited(_session.ouvrirServeur(id));
    return true;
  }

  /// Conversation enregistrée : supprimée d'abord sur le serveur (droits
  /// vérifiés par ses règles), puis en mémoire une fois la suppression
  /// confirmée. Échec : rien n'est retiré. Conversation jamais enregistrée
  /// (réponses locales seulement) : retirée de la mémoire.
  @override
  Future<bool> supprimer(String id) async {
    // Un échange local en cours d'envoi peut créer sa conversation serveur :
    // on attend d'en connaître l'UUID pour la supprimer aussi.
    await echangesLocaux?.attendre(id);
    final serveur =
        _session.correspondance.serveur(id) ??
        (synchronisation?.conversation(id) != null ? id : null);
    final sync = synchronisation;
    if (serveur == null || sync == null) {
      echangesLocaux?.oublierConversation(id);
      return _session.supprimer(id);
    }
    if (!await sync.supprimer(serveur)) return false;
    echangesLocaux?.oublierConversation(id);
    _session.supprimer(id);
    _session.correspondance.oublier(id);
    return true;
  }

  ApercuConversation? _apercuServeur(String id, {bool ouverte = false}) {
    final c = synchronisation?.conversation(id);
    if (c == null) return null;
    return ApercuConversation(
      // Une pièce jointe WhatsApp enregistrée : classée sous WhatsApp
      // (titre déjà au nom du contact), sur tous les appareils.
      source: c.contextes.isEmpty
          ? SourceConversation.jarvis
          : SourceConversation.whatsapp,
      id: id,
      titre: c.titre.isEmpty ? 'Conversation' : _uneLigne(c.titre),
      apercu: _uneLigne(c.apercu),
      derniereActivite: c.derniereActivite,
      ouverte: ouverte,
    );
  }

  ApercuConversation _apercu(
    String id,
    List<MessageConversation> messages, {
    bool ouverte = false,
  }) {
    // Réponse encore en réception : son texte n'est pas encore connu.
    final dernier = messages.lastWhere(
      (m) => !m.redaction,
      orElse: () => messages.last,
    );
    // Enregistrée : le titre du serveur (le début de la conversation peut
    // ne pas être chargé).
    final serveur = _session.correspondance.serveur(id);
    final titreServeur = serveur == null
        ? null
        : synchronisation?.conversation(serveur)?.titre;
    // Classée par une pièce jointe : sa source et le nom du contact
    // (envoyée ici, ou relue du serveur).
    final classement = _session.classement(id);
    final contextesServeur = serveur == null
        ? const <ContexteServeur>[]
        : synchronisation?.conversation(serveur)?.contextes ?? const [];
    final source =
        classement?.source ??
        (contextesServeur.isEmpty
            ? SourceConversation.jarvis
            : SourceConversation.whatsapp);
    final titreClasse =
        classement?.titre ??
        (contextesServeur.isEmpty ? null : contextesServeur.last.contact);
    return ApercuConversation(
      source: source,
      id: id,
      titre: titreClasse != null
          ? _uneLigne(titreClasse)
          : titreServeur == null || titreServeur.isEmpty
          ? titre(messages)
          : _uneLigne(titreServeur),
      apercu: _uneLigne(
        dernier.texte.trim().isNotEmpty
            ? dernier.texte
            : (dernier.conversation != null ? 'Conversation collée' : ''),
      ),
      derniereActivite: dernier.heure,
      ouverte: ouverte,
    );
  }

  /// Titre : début du premier message de l'utilisateur.
  static String titre(List<MessageConversation> messages) {
    for (final m in messages) {
      if (m.deJarvis) continue;
      if (m.texte.trim().isNotEmpty) return _uneLigne(m.texte);
      if (m.conversation != null) return 'Conversation collée';
    }
    return 'Conversation';
  }

  static String _uneLigne(String texte) =>
      texte.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void dispose() {
    _session.removeListener(_surSession);
    synchronisation?.removeListener(_surSynchronisation);
    echangesLocaux?.removeListener(_surSynchronisation);
    if (_session.surConversationIntrouvable == synchronisation?.oublier) {
      _session.surConversationIntrouvable = null;
    }
    super.dispose();
  }
}

/// Conversations JARVIS rangées sous une autre messagerie (WhatsApp…) par
/// une pièce jointe envoyée : même session, même identifiant, même
/// historique ; seul le classement change. L'ouverture et la suppression
/// passent par [FournisseurJarvis] (mémoire et serveur). En mémoire
/// seulement : le classement n'est pas encore enregistré.
class FournisseurSourceClassee extends ChangeNotifier
    implements FournisseurConversations {
  FournisseurSourceClassee(this.source, this._jarvis) {
    _jarvis.addListener(notifyListeners);
  }

  @override
  final SourceConversation source;
  final FournisseurJarvis _jarvis;

  @override
  List<ApercuConversation> get conversations => _jarvis.conversationsDe(source);

  @override
  bool ouvrir(String id) => _jarvis.ouvrir(id);

  @override
  Future<bool> supprimer(String id) => _jarvis.supprimer(id);

  @override
  String? get avertissement => null;

  @override
  Future<void> actualiser({bool force = false}) => Future.value();

  @override
  void dispose() {
    _jarvis.removeListener(notifyListeners);
    super.dispose();
  }
}
