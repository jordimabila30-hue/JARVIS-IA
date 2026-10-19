import 'dart:async';
import 'dart:collection';

import 'texte_oral.dart';
import 'tts_service.dart';

/// Lecture vocale d'une réponse PENDANT sa réception (vocal principal et
/// JARVIS Touch : même `VoiceSession`, même voix).
///
/// - Seules des phrases COMPLÈTES sont dites (jamais un mot coupé, jamais
///   un fragment répété) ; chacune passe par [TexteOral].
/// - Démarrage adaptatif, sans connaître la longueur finale : réponse
///   courte reçue d'un coup → lue entière ; sinon la lecture commence dès
///   qu'une petite réserve est prête (deux phrases, ou ~140 caractères, ou
///   une phrase après [attenteMax] : jamais d'attente sans fin).
/// - Réseau lent : les phrases prêtes sont lues dans l'ordre ; réserve
///   vide → on attend la suite sans rien inventer.
/// - Coupure : les phrases complètes déjà reçues sont terminées, le bout
///   inachevé n'est jamais lu ; [terminer] avec `coupee` le signale.
/// - [annuler] : voix arrêtée par l'appelant, file vidée, plus rien ne
///   sera dit (un ancien fragment ne relance jamais la voix).
///
/// File bornée par construction (phrases en attente seulement, retirées
/// une fois dites) ; découpage incrémental (seul le texte nouveau est lu).
class LectureEnFlux {
  LectureEnFlux({
    required this.dire,
    this.surDebut,
    this.attenteMax = const Duration(milliseconds: 1800),
    this.reserveCaracteres = 140,
    DateTime Function()? horloge,
  }) : _horloge = horloge ?? DateTime.now;

  /// Dit UN segment oral ; rend son issue (lue, interrompue, échec).
  final Future<ResultatParole> Function(String segment) dire;

  /// Premier segment réellement envoyé à la voix.
  final void Function()? surDebut;

  /// Une phrase prête depuis ce délai (après le premier fragment) : la
  /// lecture commence même sans réserve plus grande.
  final Duration attenteMax;
  final int reserveCaracteres;
  final DateTime Function() _horloge;

  final _brut = StringBuffer();
  int _decoupe = 0; // position (dans _brut) jusqu'où le texte est découpé
  final _file = Queue<_Segment>();
  final _dits = <String>[]; // texte brut des segments entièrement dits
  String? _enCours; // texte brut du segment en train d'être dit
  DateTime? _premierFragment;
  Timer? _minuteur;
  Completer<void>? _reveil;
  bool _fini = false;
  bool _annule = false;
  bool _demarre = false;
  bool _coupee = false;
  final _termine = Completer<void>();

  /// Fin de la lecture (tout dit, ou annulée).
  Future<void> get fin => _termine.future;

  bool get demarre => _demarre;

  /// La voix attend la suite (réserve épuisée, réception en cours).
  bool get enAttente => _demarre && !_fini && _file.isEmpty && _enCours == null;

  /// Ce que l'utilisateur a pu entendre : phrases dites + phrase en cours.
  String get entendu => [..._dits, ?_enCours].join(' ').trim();

  /// Segments lus jusqu'au bout (mesure).
  int get segmentsDits => _dits.length;

  /// Fragment SSE (texte brut) : découpé en phrases complètes.
  void ajouter(String fragment) {
    if (_annule || _fini || fragment.isEmpty) return;
    _premierFragment ??= _horloge();
    _brut.write(fragment);
    _decouper(final_: false);
    _peutDemarrer();
  }

  /// Fin de réception. [texteComplet] : réponse entière quand aucun
  /// fragment n'est arrivé (réponse locale, flux absent). [coupee] : le
  /// réseau a interrompu la réponse (bout inachevé jamais lu).
  void terminer({String? texteComplet, bool coupee = false}) {
    if (_annule || _fini) return;
    if (_brut.isEmpty && texteComplet != null) _brut.write(texteComplet);
    _coupee = coupee;
    _decouper(final_: !coupee);
    if (!_demarre) {
      // Réponse arrivée avant le début de la lecture (courte, rapide) : dite
      // d'un seul tenant, sans découpage artificiel (sur coupure : jusqu'à
      // la dernière phrase complète seulement).
      _file.clear();
      final entier = _brut.toString().substring(0, _decoupe).trim();
      if (entier.isNotEmpty) {
        final oral = TexteOral.preparer(entier);
        if (oral.isNotEmpty) _file.add(_Segment(entier, oral));
      }
    }
    _fini = true;
    _demarrer();
  }

  /// Arrêt (interruption) : rien d'autre ne sera dit. La voix elle-même
  /// est coupée par l'appelant (`TtsService.arreter`).
  void annuler() {
    if (_annule) return;
    _annule = true;
    _file.clear();
    _minuteur?.cancel();
    _reveiller();
    if (!_termine.isCompleted) _termine.complete();
  }

  bool get coupee => _coupee;

  // ── Découpage ─────────────────────────────────────────────────────────

  // Fin de phrase : . ! ? … suivis d'un espace / retour à la ligne ; ou
  // ligne vide (paragraphe). Jamais un nombre décimal (« 3.5 »).
  static final _finPhrase = RegExp(r'([.!?…]+["»)]?)(?=\s)|\n\s*\n');

  static final _numero = RegExp(r'(^|\n)\s*([-*•]\s*)?\d{1,2}[.)]$');

  void _decouper({required bool final_}) {
    final texte = _brut.toString();
    var debut = _decoupe;
    final reste = texte.substring(debut);
    var dernier = 0;
    for (final m in _finPhrase.allMatches(reste)) {
      final fin = m.end;
      final phrase = reste.substring(dernier, fin).trim();
      // « 1. » d'une liste, « M. », « etc. » trop court : pas une phrase,
      // il rejoint la suite.
      if (_numero.hasMatch(phrase) || phrase.length < 4) continue;
      dernier = fin;
      _empiler(phrase);
    }
    debut += dernier;
    if (final_) {
      final bout = texte.substring(debut).trim();
      if (bout.isNotEmpty) _empiler(bout);
      debut = texte.length;
    }
    _decoupe = debut;
  }

  void _empiler(String brut) {
    // Une ligne de liste seule (« 1. ») ou un titre court se joint à la
    // phrase suivante : TexteOral la rendra en une seule phrase parlée.
    final oral = TexteOral.preparer(brut);
    if (oral.isEmpty) return;
    _file.add(_Segment(brut, oral));
    _reveiller();
  }

  // ── Démarrage adaptatif ───────────────────────────────────────────────

  void _peutDemarrer() {
    if (_demarre) return;
    final pret = _file.fold<int>(0, (n, s) => n + s.oral.length);
    if (_file.length >= 2 || pret >= reserveCaracteres) {
      _demarrer();
    } else if (_file.isNotEmpty && _minuteur == null) {
      final ecoule = _horloge().difference(_premierFragment!);
      final reste = attenteMax - ecoule;
      if (reste <= Duration.zero) {
        _demarrer();
      } else {
        _minuteur = Timer(reste, () {
          if (_file.isNotEmpty) _demarrer();
        });
      }
    }
  }

  void _demarrer() {
    if (_demarre || _annule) {
      _reveiller();
      if (_fini && !_demarre && _file.isEmpty && !_termine.isCompleted) {
        _termine.complete();
      }
      return;
    }
    if (_file.isEmpty && _fini) {
      if (!_termine.isCompleted) _termine.complete();
      return;
    }
    if (_file.isEmpty) return;
    _demarre = true;
    _minuteur?.cancel();
    unawaited(_boucle());
  }

  Future<void> _boucle() async {
    var premier = true;
    while (!_annule) {
      if (_file.isEmpty) {
        if (_fini) break;
        // Réserve épuisée, réception en cours : on attend la suite.
        await (_reveil = Completer<void>()).future;
        continue;
      }
      final s = _file.removeFirst();
      _enCours = s.brut;
      if (premier) {
        premier = false;
        surDebut?.call();
      }
      final r = await dire(s.oral);
      if (_annule) break;
      _enCours = null;
      _dits.add(s.brut);
      if (r.issue == IssueParole.echec) break; // voix indisponible : on s'arrête
    }
    if (!_termine.isCompleted) _termine.complete();
  }

  void _reveiller() {
    final r = _reveil;
    _reveil = null;
    if (r != null && !r.isCompleted) r.complete();
  }
}

class _Segment {
  const _Segment(this.brut, this.oral);
  final String brut;
  final String oral;
}
