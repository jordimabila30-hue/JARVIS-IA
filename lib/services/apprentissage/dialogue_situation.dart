import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/tuteur.dart';
import '../api_jarvis.dart';
import '../voice_command_service.dart';
import '../voice_session.dart';
import 'session_tuteur.dart';

/// Dialogue d'une situation du quotidien (JARVIS joue un rôle), à l'oral
/// ou à l'écrit : UN historique, partagé par les deux modes (changer de
/// mode ne perd rien et ne réécrit rien). Les répliques ne sont gardées
/// qu'en mémoire, le temps de l'exercice.
class DialogueSituation extends ChangeNotifier {
  DialogueSituation({
    required this.situation,
    required AppelTuteur? appel,
    this.niveau,
    this.versionCorpus,
  }) : _appel = appel,
       _repliques = [Replique.jarvis(situation.ouverture)];

  final SituationPratique situation;
  final AppelTuteur? _appel;
  final String? niveau;
  final String? versionCorpus;

  final List<Replique> _repliques;
  List<Replique> get repliques => List.unmodifiable(_repliques);

  /// Réponse de JARVIS en cours de réception (affichée en direct).
  String get enCours => _enCours.toString();
  final _enCours = StringBuffer();

  bool _attente = false;
  bool get attente => _attente;

  String? _erreur;
  String? get erreur => _erreur;

  bool get disponible => _appel != null;

  /// L'élève a répondu au moins une fois : un bilan est possible.
  bool get bilanPossible => _repliques.any((r) => !r.deJarvis);

  Completer<void>? _annulation;

  /// Réplique de l'élève → réponse de JARVIS dans son rôle (texte), ou null
  /// (annulée, ou erreur : voir [erreur]).
  Future<String?> repondre(
    String phrase, {
    void Function(String fragment)? surFragment,
  }) async {
    final appel = _appel;
    final texte = phrase.trim();
    if (appel == null || texte.isEmpty) return null;
    annuler();
    _repliques.add(Replique.eleve(texte));
    _erreur = null;
    _attente = true;
    _enCours.clear();
    notifyListeners();
    final annulation = _annulation = Completer<void>();
    final r = await appel(
      DemandeTuteur(
        action: ActionTuteur.dialogue,
        situation: situation.id,
        // L'ouverture est connue du serveur : seules les répliques suivantes.
        historique: _repliques.sublist(1),
        niveau: niveau,
        oral: true,
        versionCorpus: versionCorpus,
      ),
      annulation: annulation.future,
      surFragment: (f) {
        if (annulation.isCompleted) return;
        _enCours.write(f);
        surFragment?.call(f);
        notifyListeners();
      },
    );
    if (identical(_annulation, annulation)) _annulation = null;
    _attente = false;
    _enCours.clear();
    if (annulation.isCompleted && r is! SuccesApi<ReponseTuteur>) {
      notifyListeners();
      return null;
    }
    switch (r) {
      case SuccesApi(:final valeur):
        _repliques.add(Replique.jarvis(valeur.texte.trim()));
        notifyListeners();
        return valeur.texte.trim();
      case EchecApi(type: final type, :final detail):
        _erreur = type == ErreurApi.injoignable || type == ErreurApi.fluxInterrompu
            ? 'Le dialogue demande Internet.'
            : (detail ?? type.message);
        notifyListeners();
        return null;
    }
  }

  /// Arrête la réponse en cours (la requête est abandonnée).
  void annuler() {
    final a = _annulation;
    _annulation = null;
    if (a != null && !a.isCompleted) a.complete();
  }

  /// Bilan pédagogique de l'échange (sort du rôle).
  DemandeTuteur demandeBilan() => DemandeTuteur(
    action: ActionTuteur.bilan,
    situation: situation.id,
    historique: _repliques.sublist(1),
    niveau: niveau,
    versionCorpus: versionCorpus,
  );

  @override
  void dispose() {
    annuler();
    super.dispose();
  }
}

/// Raisons pour lesquelles l'oral n'est pas proposé maintenant.
enum OralIndisponible {
  sansVoix('L’oral n’est pas disponible sur cet appareil.'),
  sansCompte('L’oral avec le professeur demande une connexion.'),
  chatVocal('Un chat vocal est en cours ou en pause : terminez-le d’abord.');

  const OralIndisponible(this.message);

  final String message;
}

/// Oral pédagogique sur LA [VoiceSession] de JARVIS (aucun second moteur
/// de reconnaissance ni de synthèse) : le temps de l'exercice, ses
/// réponses viennent du dialogue de situation ; à la fermeture, le
/// répondeur du chat est rétabli tel quel. Interruption : manuelle
/// seulement (`arreterParole`), jamais automatique.
class OralSituation {
  OralSituation(this.voix, this.dialogue);

  final VoiceSession voix;
  final DialogueSituation dialogue;

  Future<ReponseVocale?> Function(
    String phrase, {
    void Function(String fragment)? surFragment,
  })?
  _repondeurChat;
  void Function(String entendu)? _annulerChat;
  bool _ouvert = false;

  bool get ouvert => _ouvert;

  /// Null si l'oral peut commencer, sinon la raison.
  static OralIndisponible? empechement(
    VoiceSession? voix,
    DialogueSituation dialogue,
  ) {
    if (voix == null) return OralIndisponible.sansVoix;
    if (!dialogue.disponible) return OralIndisponible.sansCompte;
    if (voix.actif || voix.reprenable) return OralIndisponible.chatVocal;
    return null;
  }

  /// Prend la session : JARVIS dit sa première réplique, puis écoute.
  Future<void> ouvrir() async {
    if (_ouvert) return;
    _ouvert = true;
    _repondeurChat = voix.repondeur;
    _annulerChat = voix.annulerReponse;
    voix.repondeur = _repondre;
    voix.annulerReponse = (_) => dialogue.annuler();
    if (dialogue.repliques.length == 1) {
      await voix.lireReponse(dialogue.situation.ouverture);
    }
    if (_ouvert) await voix.demarrer();
  }

  Future<ReponseVocale?> _repondre(
    String phrase, {
    void Function(String fragment)? surFragment,
  }) async {
    final texte = await dialogue.repondre(phrase, surFragment: surFragment);
    if (texte != null) return ReponseVocale(texte, source: SourceReponse.distante);
    final erreur = dialogue.erreur;
    // Annulée : rien à dire. Erreur : une phrase claire, puis réécoute.
    return erreur == null
        ? null
        : ReponseVocale(erreur, source: SourceReponse.locale);
  }

  /// Micro coupé (saisie écrite, pause) sans quitter l'exercice.
  Future<void> pause() => voix.arreter();

  Future<void> reprendre() => voix.demarrer();

  /// Rend la session au chat : micro et voix arrêtés, répondeur rétabli.
  Future<void> fermer() async {
    if (!_ouvert) return;
    _ouvert = false;
    dialogue.annuler();
    await voix.arreter();
    voix.repondeur = _repondeurChat;
    voix.annulerReponse = _annulerChat;
  }
}
