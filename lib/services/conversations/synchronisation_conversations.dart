import 'package:flutter/foundation.dart';

import 'depot_conversations.dart';

/// Liste des conversations JARVIS enregistrées sur le serveur, pour le
/// menu latéral.
///
/// Actualisée à la connexion, à l'ouverture du menu, au retour au premier
/// plan et après un échange avec l'IA — jamais en continu : deux
/// actualisations automatiques sont espacées d'au moins [intervalle], et
/// les demandes simultanées n'en font qu'une. Hors connexion, la dernière
/// liste reçue reste affichée et [avertissement] l'explique.
///
/// Vit avec l'accueil d'un compte : à la déconnexion, l'accueil (et donc
/// cette liste) disparaît ; une réponse reçue pour un autre compte que
/// celui qui l'a demandée est ignorée.
class SynchronisationConversations extends ChangeNotifier {
  SynchronisationConversations(
    this.depot, {
    this.intervalle = const Duration(seconds: 20),
    DateTime Function()? horloge,
  }) : _horloge = horloge ?? DateTime.now;

  final DepotConversations depot;
  final Duration intervalle;
  final DateTime Function() _horloge;

  List<ConversationServeur> _conversations = const [];

  /// Conversations du serveur, la plus récemment active d'abord.
  List<ConversationServeur> get conversations => _conversations;

  ConversationServeur? conversation(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Vrai dès qu'une liste a été reçue.
  bool get chargee => _chargee;
  bool _chargee = false;

  /// Explication à afficher dans le menu (liste non actualisée,
  /// suppression impossible…) ; null si tout va bien.
  String? get avertissement => _avertissement;
  String? _avertissement;

  DateTime? _derniere;
  Future<void>? _enCours;
  bool _ferme = false;

  /// Relit la liste. Sans [force], ne fait rien si la dernière
  /// actualisation réussie date de moins de [intervalle].
  Future<void> actualiser({bool force = false}) {
    final enCours = _enCours;
    if (enCours != null) return enCours;
    final derniere = _derniere;
    if (!force &&
        derniere != null &&
        _horloge().difference(derniere) < intervalle) {
      return Future.value();
    }
    return _enCours = _lire().whenComplete(() => _enCours = null);
  }

  Future<void> _lire() async {
    final compte = depot.utilisateur;
    if (compte == null) return;
    try {
      final liste = await depot.lister();
      if (_ferme || depot.utilisateur != compte) return;
      _conversations = List.unmodifiable(liste);
      _chargee = true;
      _derniere = _horloge();
      _avertissement = null;
    } on EchecSynchro catch (e) {
      if (_ferme) return;
      debugPrint('[JARVIS synchro] liste non actualisée : $e');
      _avertissement = switch (e.type) {
        ErreurSynchro.horsLigne =>
          'Hors connexion : liste non actualisée. Touchez pour réessayer.',
        ErreurSynchro.sessionExpiree => e.type.message,
        _ =>
          'Conversations enregistrées indisponibles pour le moment. '
              'Touchez pour réessayer.',
      };
    }
    notifyListeners();
  }

  /// Supprime la conversation [id] sur le serveur. Elle reste listée
  /// jusqu'à la confirmation ; en cas d'échec, elle est conservée et
  /// [avertissement] l'explique. Déjà supprimée ailleurs : réussite.
  Future<bool> supprimer(String id) async {
    try {
      await depot.supprimer(id);
    } on EchecSynchro catch (e) {
      if (e.type != ErreurSynchro.introuvable) {
        debugPrint('[JARVIS synchro] suppression impossible : $e');
        if (!_ferme) {
          _avertissement =
              'Suppression impossible : ${e.type.message} '
              'La conversation est conservée.';
          notifyListeners();
        }
        return false;
      }
    }
    if (_ferme) return true;
    _avertissement = null;
    oublier(id);
    notifyListeners();
    return true;
  }

  /// Retire de la liste une conversation que le serveur ne connaît plus
  /// (supprimée depuis un autre appareil).
  void oublier(String id) {
    final avant = _conversations.length;
    _conversations = [
      for (final c in _conversations)
        if (c.id != id) c,
    ];
    if (_conversations.length != avant && !_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _conversations = const [];
    super.dispose();
  }
}
