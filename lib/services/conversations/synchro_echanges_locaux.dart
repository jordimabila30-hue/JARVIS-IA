import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api_jarvis.dart';
import '../voice_settings_service.dart';
import 'correspondance_conversations.dart';

/// Échange traité sur l'appareil (heure, calcul…), à enregistrer dans la
/// conversation du compte. Les identifiants des deux messages sont choisis
/// ici : un renvoi après une coupure ne crée jamais de doublon.
class EchangeLocal {
  const EchangeLocal({
    required this.idQuestion,
    required this.idReponse,
    required this.idLocal,
    required this.question,
    required this.reponse,
    required this.questionA,
    required this.reponseA,
  });

  final String idQuestion;
  final String idReponse;

  /// Conversation du fil (identifiant local).
  final String idLocal;
  final String question;
  final String reponse;

  /// Heures de l'appareil.
  final DateTime questionA;
  final DateTime reponseA;

  Map<String, Object> versJson() => {
    'q': idQuestion,
    'r': idReponse,
    'l': idLocal,
    'question': question,
    'reponse': reponse,
    'qa': questionA.toUtc().toIso8601String(),
    'ra': reponseA.toUtc().toIso8601String(),
  };

  static EchangeLocal depuisJson(Map<String, dynamic> j) => EchangeLocal(
    idQuestion: j['q'] as String,
    idReponse: j['r'] as String,
    idLocal: j['l'] as String,
    question: j['question'] as String,
    reponse: j['reponse'] as String,
    questionA: DateTime.parse(j['qa'] as String),
    reponseA: DateTime.parse(j['ra'] as String),
  );

  /// UUID v4 aléatoire (identifiant de message choisi par l'appareil).
  static String nouvelId() {
    final r = Random.secure();
    final o = List<int>.generate(16, (_) => r.nextInt(256));
    o[6] = (o[6] & 0x0f) | 0x40;
    o[8] = (o[8] & 0x3f) | 0x80;
    final h = [for (final b in o) b.toRadixString(16).padLeft(2, '0')].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Envoi d'un échange : [conversation] serveur connue, ou null (le serveur
/// en crée une). Renvoie l'UUID de la conversation.
typedef EnvoiEchangeLocal =
    Future<ResultatApi<String>> Function(EchangeLocal e, String? conversation);

/// File des échanges locaux à enregistrer sur le serveur.
///
/// La réponse locale est affichée tout de suite ; son enregistrement suit,
/// dans l'ordre, une seule fois. Hors connexion, la file est gardée sur
/// l'appareil (une file par compte) et envoyée au retour du réseau
/// (ouverture du menu, retour au premier plan, échange suivant). Elle n'est
/// envoyée qu'avec la session du compte qui l'a remplie.
class SynchroEchangesLocaux extends ChangeNotifier {
  SynchroEchangesLocaux({
    required this.compte,
    required this.compteActuel,
    required this.correspondance,
    required EnvoiEchangeLocal envoyer,
    StockageReglages? stockage,
    this.decalage,
  }) : _envoyer = envoyer,
       _stockage = stockage ?? StockagePreferences(cle: cleStockage(compte));

  static String cleStockage(String compte) => 'jarvis.echanges_locaux.$compte';

  /// Compte propriétaire de cette file.
  final String compte;

  /// Compte de la session actuelle (rien n'est envoyé s'il a changé).
  final String? Function() compteActuel;
  final CorrespondanceConversations correspondance;

  /// Avance de l'horloge du serveur sur celle de l'appareil : les heures
  /// envoyées sont corrigées (ordre des messages).
  final Duration? Function()? decalage;

  final EnvoiEchangeLocal _envoyer;
  final StockageReglages _stockage;

  final _file = <EchangeLocal>[];

  // Conversation serveur obtenue pour une conversation locale (gardée avec
  // la file : un redémarrage ne crée pas une seconde conversation).
  final _cartes = <String, String>{};

  Future<void>? _enCours;
  bool _ferme = false;

  /// Échanges pas encore enregistrés sur le serveur.
  int get enAttente => _file.length;

  /// Dernier envoi impossible (hors connexion…) ; null après un succès.
  ErreurApi? get echec => _echec;
  ErreurApi? _echec;

  /// Échange enregistré : sa conversation serveur.
  void Function(EchangeLocal e, String conversation)? surEnregistre;

  /// Relit la file gardée sur l'appareil.
  Future<void> charger() async {
    try {
      final brut = await _stockage.lire();
      if (brut == null || _ferme) return;
      final j = jsonDecode(brut) as Map<String, dynamic>;
      final deja = {for (final e in _file) e.idQuestion};
      for (final e in (j['file'] as List? ?? const [])) {
        final echange = EchangeLocal.depuisJson(e as Map<String, dynamic>);
        if (!deja.contains(echange.idQuestion)) _file.add(echange);
      }
      _cartes.addAll({
        for (final e in (j['cartes'] as Map? ?? const {}).entries)
          '${e.key}': '${e.value}',
      });
    } catch (e) {
      debugPrint('[JARVIS échanges locaux] file illisible : $e');
    }
  }

  void ajouter(EchangeLocal e) {
    if (_ferme) return;
    _file.add(e);
    unawaited(_enregistrer());
    notifyListeners();
    unawaited(envoyer());
  }

  /// Envoie la file, dans l'ordre (un seul envoi à la fois).
  Future<void> envoyer() =>
      _enCours ??= _vider().whenComplete(() => _enCours = null);

  /// Avant une question à l'IA dans la conversation [idLocal] : ses
  /// échanges locaux sont d'abord enregistrés, pour que la question
  /// rejoigne la même conversation serveur (et que l'IA en ait le
  /// contexte). Jamais plus de quelques secondes d'attente.
  Future<void> attendre(String idLocal) async {
    if (!_file.any((e) => e.idLocal == idLocal)) return;
    try {
      await envoyer().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Conversation supprimée : ses échanges en attente sont abandonnés.
  void oublierConversation(String idLocal) {
    _file.removeWhere((e) => e.idLocal == idLocal);
    _cartes.remove(idLocal);
    unawaited(_enregistrer());
    notifyListeners();
  }

  Future<void> _vider() async {
    var renvoiSansConversation = false;
    while (_file.isNotEmpty && !_ferme) {
      if (compteActuel() != compte) return;
      final e = _file.first;
      final conversation = renvoiSansConversation
          ? null
          : _cartes[e.idLocal] ?? correspondance.serveur(e.idLocal);
      renvoiSansConversation = false;
      final ecart = decalage?.call() ?? Duration.zero;
      final r = await _envoyer(
        EchangeLocal(
          idQuestion: e.idQuestion,
          idReponse: e.idReponse,
          idLocal: e.idLocal,
          question: e.question,
          reponse: e.reponse,
          questionA: e.questionA.add(ecart),
          reponseA: e.reponseA.add(ecart),
        ),
        conversation,
      );
      if (_ferme) return;
      switch (r) {
        case SuccesApi(valeur: final id):
          // Conversation supprimée pendant l'envoi : déjà retiré.
          _file.remove(e);
          _cartes[e.idLocal] = id;
          if (correspondance.serveur(e.idLocal) == null) {
            correspondance.associer(e.idLocal, id);
          }
          _echec = null;
          await _enregistrer();
          surEnregistre?.call(e, id);
          notifyListeners();
        case EchecApi(type: ErreurApi.conversationIntrouvable)
            when conversation != null:
          // Supprimée depuis un autre appareil : la suite repart dans une
          // nouvelle conversation (comme une question à l'IA).
          _cartes.remove(e.idLocal);
          if (correspondance.serveur(e.idLocal) == conversation) {
            correspondance.oublier(e.idLocal);
          }
          renvoiSansConversation = true;
        case EchecApi(:final type, :final detail)
            when type == ErreurApi.messageTropLong ||
                type == ErreurApi.conversationIntrouvable ||
                detail == 'HTTP 409':
          // Refus définitif : réessayer ne changerait rien.
          debugPrint('[JARVIS échanges locaux] abandonné : ${type.name}');
          _file.remove(e);
          await _enregistrer();
          notifyListeners();
        case EchecApi(:final type):
          // Hors connexion, serveur arrêté, session à renouveler : on
          // réessaiera plus tard, dans le même ordre.
          _echec = type;
          notifyListeners();
          return;
      }
    }
  }

  Future<void> _enregistrer() async {
    try {
      await _stockage.ecrire(
        jsonEncode({
          'file': [for (final e in _file) e.versJson()],
          'cartes': {
            for (final e in _cartes.entries)
              if (_file.any((x) => x.idLocal == e.key)) e.key: e.value,
          },
        }),
      );
    } catch (e) {
      debugPrint('[JARVIS échanges locaux] file non enregistrée : $e');
    }
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
