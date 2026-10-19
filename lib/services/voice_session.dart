import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/signal_vocal.dart';
import '../models/voice_settings.dart';
import '../models/voice_state.dart';
import 'detecteur_intervention.dart';
import 'lecture_en_flux.dart';
import 'microphone_service.dart';
import 'niveau_micro.dart';
import 'prosodie.dart';
import 'speech_recognition_service.dart';
import 'texte_oral.dart';
import 'tts_service.dart';
import 'voice_command_service.dart';
import 'voice_settings_service.dart';

/// État réel du micro pendant le mode vocal (jamais déduit de la liste des
/// périphériques, que seul le navigateur fournit).
enum EtatMicro {
  /// Permission accordée, reconnaissance initialisée et disponible.
  disponible,

  /// Permission micro refusée.
  permissionRefusee,

  /// Pas de service de reconnaissance vocale.
  reconnaissanceIndisponible,

  /// Micro disponible, mais plusieurs écoutes de suite sans rien entendre
  /// (et aucun texte reconnu pendant cette session).
  aucunSon,

  /// Problème propre au moteur de reconnaissance (réseau, langue…).
  erreurReconnaissance,
}

/// Problème affiché à l'utilisateur dans le mode vocal.
class ProblemeVocal {
  const ProblemeVocal(
    this.message, {
    this.reglages = false,
    this.titre = 'Micro indisponible',
    this.micro = EtatMicro.erreurReconnaissance,
  });

  /// État du micro qui correspond à ce problème.
  final EtatMicro micro;

  /// Explication détaillée (affichée en petit, sous le titre).
  final String message;

  /// Libellé court et discret (« Micro indisponible »…).
  final String titre;

  /// Vrai si l'utilisateur doit passer par les réglages (refus définitif).
  final bool reglages;
}

/// Boucle du mode vocal : écoute → réflexion → parole → écoute.
///
/// Expose l'[etat] et le [statut] (notifyListeners, quelques fois par
/// phrase) et l'[amplitude] séparément (ValueNotifier, jusqu'à 60 fois par
/// seconde) pour que seul PIM se redessine à ce rythme.
class VoiceSession extends ChangeNotifier {
  VoiceSession({
    MicrophoneService? micro,
    SpeechRecognitionService? reconnaissance,
    TtsService? voix,
    VoiceCommandService? commandes,
    NiveauMicro? niveau,
    VoiceSettingsService? reglages,
  }) : _micro = micro ?? MicrophoneService(),
       _niveau = niveau ?? NiveauMicro(),
       _reconnaissance = reconnaissance ?? SpeechRecognitionService(),
       _voix = voix ?? reglages?.tts ?? TtsService(),
       _commandes = commandes ?? VoiceCommandService(),
       _reglagesInjectes = reglages;

  final VoiceSettingsService? _reglagesInjectes;

  /// Réglages du chat vocal (voix, vitesse, micro, réponse automatique…),
  /// partagés avec le panneau Paramètres. Même moteur de synthèse.
  late final VoiceSettingsService reglages =
      _reglagesInjectes ?? VoiceSettingsService(tts: _voix);

  final MicrophoneService _micro;
  final SpeechRecognitionService _reconnaissance;
  final TtsService _voix;
  final VoiceCommandService _commandes;
  final NiveauMicro _niveau;
  final _hasard = math.Random();

  /// Amplitude de 0 à 1 : voix de l'utilisateur, puis voix de JARVIS.
  final amplitude = ValueNotifier<double>(0);

  /// Bandes de fréquence du micro et rythme de la parole de JARVIS, lus
  /// par PIM à chaque image.
  final signal = SignalVocal();

  VoiceState etat = VoiceState.idle;

  /// Vrai tant que la boucle vocale tourne (faux après un arrêt ou une
  /// erreur : le [probleme] explique alors pourquoi).
  bool actif = false;

  /// Appelé quand la session se termine d'elle-même (« Au revoir JARVIS »).
  VoidCallback? surFin;

  /// Conversation partagée avec l'écrit : chaque phrase validée y est
  /// ajoutée avec sa réponse (même historique, même contexte). Sans
  /// répondeur, la session répond seule (ses propres règles locales).
  /// Null en retour : la conversation a été effacée, rien à dire.
  ///
  /// [surFragment] : texte de la réponse au fil de sa réception (IA) ; la
  /// voix commence avant la fin ([LectureEnFlux]).
  Future<ReponseVocale?> Function(
    String phrase, {
    void Function(String fragment)? surFragment,
  })?
  repondeur;

  /// Interruption : la génération en cours (s'il y en a une) est arrêtée,
  /// et [entendu] (ce que l'utilisateur a réellement pu entendre) est
  /// gardé pour la question suivante. Branché sur la conversation partagée.
  void Function(String entendu)? annulerReponse;

  /// Détection d'une intervention pendant la parole (Android ; null :
  /// absente). Active seulement en mode automatique validé, ou en mode
  /// mesure ([DetecteurIntervention.mesure]) où elle n'interrompt jamais.
  DetecteurIntervention? detecteur;

  bool get _detectionVoulue =>
      detecteur != null &&
      (DetecteurIntervention.mesure ||
          (reglages.reglages.interruption == ModeInterruption.automatique &&
              ModeInterruption.automatique.disponible));

  /// Intervention détectée pendant la parole : en mode automatique, même
  /// effet que le bouton (voix coupée, écoute aussitôt) ; en mesure, rien.
  void _surCandidat(int tour) {
    if (tour != _tour || !parle) return;
    if (DetecteurIntervention.mesure &&
        reglages.reglages.interruption != ModeInterruption.automatique) {
      debugPrint('[JARVIS voix] intervention détectée (mesure, sans effet)');
      return;
    }
    debugPrint('[JARVIS voix] interruption automatique');
    arreterParole();
  }
  String statut = '';
  String transcription = '';

  /// Dernière réponse de JARVIS, affichée sous la phrase entendue.
  String reponse = '';

  /// Réponse automatique désactivée : phrase reconnue qui attend d'être
  /// envoyée ([envoyerPhrase]) ou abandonnée ([ignorerPhrase]).
  String? phraseEnAttente;

  /// Vrai pendant l'aperçu de la voix (panneau Paramètres), dès la
  /// demande.
  bool apercuEnCours = false;

  /// Vrai seulement quand la voix de l'aperçu se fait réellement entendre
  /// (signal de début du moteur) : « Lecture… » n'est jamais affiché si la
  /// synthèse a échoué.
  bool apercuSonore = false;

  /// Explication si l'aperçu n'a pas pu être lu.
  String? erreurApercu;

  /// Explication si JARVIS n'a pas pu prononcer sa dernière réponse.
  String? erreurVoix;
  int _jetonApercu = 0;
  ProblemeVocal? probleme;

  // Chaque démarrage incrémente le jeton : les suites asynchrones d'une
  // session arrêtée sont ignorées.
  int _jeton = 0;
  Timer? _relance;
  Timer? _decroissance;
  Timer? _rythmeEstime;
  DateTime _dernierNiveauReel = DateTime.fromMillisecondsSinceEpoch(0);
  int _ecoutesVides = 0;
  int _refusConsecutifs = 0;

  /// Du texte a été reconnu pendant cette session : le micro fonctionne,
  /// quoi qu'il arrive ensuite.
  bool _texteEntendu = false;

  /// Pause avant de réécouter après la voix de JARVIS : le micro ne doit
  /// pas capter la fin de sa propre phrase.
  static const pauseApresParole = Duration(milliseconds: 350);

  /// Chat vocal en arrière-plan : l'utilisateur a quitté le mode vocal
  /// après au moins un échange ; micro et voix sont coupés, mais le
  /// contexte vocal est gardé et le chat peut être repris. Ce n'est pas un
  /// micro allumé.
  bool get reprenable => _reprenable;
  bool _reprenable = false;

  // Échanges (phrase + réponse) depuis le début du chat vocal.
  int _echanges = 0;

  /// Quitte le mode vocal sans terminer le chat : micro et voix coupés,
  /// contexte gardé. Reprenable s'il y a eu au moins un échange.
  Future<void> mettreEnArrierePlan() async {
    await arreter();
    _reprenable = _echanges > 0;
    notifyListeners();
  }

  /// « Quitter le mode vocal » : le chat vocal s'arrête pour de bon (rien à
  /// reprendre). La conversation, ses échanges vocaux et son contexte
  /// restent : seule « Nouvelle conversation » les efface.
  Future<void> quitterChatVocal() async {
    await arreter();
    _reprenable = false;
    _echanges = 0;
    notifyListeners();
  }

  /// Termine le chat vocal (nouvelle conversation) : plus rien à reprendre,
  /// contexte oublié.
  Future<void> terminerChatVocal() async {
    await arreter();
    _terminer();
    notifyListeners();
  }

  void _terminer() {
    _reprenable = false;
    _echanges = 0;
    _commandes.contexte.reinitialiser();
  }

  // ---- Lecture vocale en mode écrit ----------------------------------------
  //
  // Indépendante du chat vocal : le micro reste coupé, l'état vocal (et donc
  // PIM) ne change pas ; la voix lit seulement la réponse écrite.

  int _jetonLecture = 0;

  /// Vrai pendant la lecture d'une réponse écrite.
  bool get lectureEnCours => _lectureEnCours;
  bool _lectureEnCours = false;

  /// Lit [texte] avec les réglages de voix actuels (une lecture à la fois :
  /// la précédente s'arrête). Sans effet pendant le chat vocal.
  Future<void> lireReponse(String texte) async {
    if (actif || texte.trim().isEmpty) return;
    final jeton = ++_jetonLecture;
    _lectureEnCours = true;
    await _voix.arreter();
    await _voix.initialiser();
    await _voix.appliquer(reglages.reglages);
    if (jeton != _jetonLecture) return;
    await _voix.parler(TexteOral.preparer(texte));
    if (jeton == _jetonLecture) _lectureEnCours = false;
  }

  /// Arrête la lecture en cours (lecture vocale désactivée).
  Future<void> arreterLecture() async {
    _jetonLecture++;
    if (!_lectureEnCours) return;
    _lectureEnCours = false;
    await _voix.arreter();
  }

  // ---- Interruption (une seule action) --------------------------------------
  //
  // « Arrêter la parole » : la voix se tait, les phrases en attente sont
  // oubliées, la génération en cours est arrêtée, puis l'écoute reprend
  // AUSSITÔT (aucun second toucher). Distinct de couper le micro
  // (`mettreEnArrierePlan`), réduire une fenêtre (interface) et quitter
  // (`quitterChatVocal`). Chaque réponse a son tour ([_tour]) : un ancien
  // tour (fragment tardif, fin de lecture) ne relance jamais la voix.

  int _tour = 0;
  LectureEnFlux? _lecture;

  /// Durée du dernier arrêt de la voix (mesure, millisecondes).
  int? dernierArretMs;

  /// Vrai pendant que JARVIS parle ou attend la suite de sa réponse.
  bool get parle => actif && etat == VoiceState.speaking;

  Future<void> arreterParole() async {
    if (!parle) return;
    final chrono = Stopwatch()..start();
    _tour++;
    final lecture = _lecture;
    _lecture = null;
    final entendu = lecture?.entendu ?? '';
    lecture?.annuler();
    _rythmeEstime?.cancel();
    amplitude.value = 0;
    // Le micro de détection est rendu avant que la reconnaissance l'ouvre.
    final detection = detecteur?.arreter();
    // Transition contrôlée : plus « parle », pas encore « écoute ».
    _changer(VoiceState.idle, 'Interruption…');
    annulerReponse?.call(entendu);
    await _voix.arreter();
    await detection;
    dernierArretMs = chrono.elapsedMilliseconds;
    debugPrint('[JARVIS voix] parole arrêtée en $dernierArretMs ms');
    if (!actif) return;
    transcription = '';
    _ecouter(_jeton);
    debugPrint(
      '[JARVIS voix] écoute relancée ${chrono.elapsedMilliseconds} ms '
      'après l’interruption',
    );
  }

  Future<void> demarrer() async {
    // Le chat vocal a la parole : plus de lecture de réponse écrite.
    await arreterLecture();
    final jeton = ++_jeton;
    actif = true;
    // Le chat est ouvert (nouveau ou repris) : il n'est plus en arrière-plan.
    _reprenable = false;
    probleme = null;
    transcription = '';
    reponse = '';
    erreurVoix = null;
    _texteEntendu = false;
    _ecoutesVides = 0;
    _refusConsecutifs = 0;
    _changer(VoiceState.idle, 'Préparation…');
    _demarrerDecroissance();

    final acces = await _micro.demanderAcces();
    if (!_valide(jeton)) return;
    switch (acces) {
      case AccesMicro.autorise:
        break;
      case AccesMicro.refuse:
        return _signaler(
          'Le microphone est nécessaire pour le mode vocal. '
          'Autorise-le pour parler à JARVIS.',
          micro: EtatMicro.permissionRefusee,
        );
      case AccesMicro.refuseDefinitivement:
        return _signaler(
          'L’accès au microphone est bloqué. '
          'Active-le dans les réglages de l’appareil.',
          reglages: true,
          micro: EtatMicro.permissionRefusee,
        );
      case AccesMicro.indisponible:
        return _signaler('Aucun microphone n’est disponible sur cet appareil.');
      case AccesMicro.erreur:
        return _signaler('Le microphone n’a pas pu être ouvert. Réessaie.');
    }

    final erreur = await _reconnaissance.initialiser();
    if (!_valide(jeton)) return;
    if (erreur != null) return _signalerReconnaissance(erreur);

    await _arreterApercu();
    await _voix.initialiser();
    if (!_valide(jeton)) return;

    // Volume réel du micro quand la reconnaissance ne le fournit pas (Web),
    // sur le micro choisi dans les Paramètres.
    await _niveau.demarrer(
      _surNiveauMesure,
      surBandes: _surBandes,
      microphoneId: reglages.reglages.microphoneId,
    );
    if (!_valide(jeton)) {
      await _niveau.arreter();
      return;
    }
    _ecouter(jeton);
  }

  Future<void> arreter() async {
    _jeton++;
    _tour++;
    _lecture?.annuler();
    _lecture = null;
    await detecteur?.arreter();
    _jetonApercu++;
    apercuEnCours = false;
    actif = false;
    phraseEnAttente = null;
    _relance?.cancel();
    _decroissance?.cancel();
    _rythmeEstime?.cancel();
    amplitude.value = 0;
    signal.effacerBandes();
    await _reconnaissance.annuler();
    await _voix.arreter();
    await _niveau.arreter();
    _changer(VoiceState.idle, '');
  }

  Future<void> ouvrirReglages() => _micro.ouvrirReglages();

  bool _valide(int jeton) => actif && jeton == _jeton;

  /// État du micro, fondé sur de vrais signaux : permission, disponibilité
  /// de la reconnaissance, texte reconnu, écoutes vides.
  EtatMicro get etatMicro {
    final p = probleme;
    if (p != null) return p.micro;
    // Une phrase reconnue prouve que le micro fonctionne.
    if (!_texteEntendu && etat == VoiceState.listening && _ecoutesVides >= 3) {
      return EtatMicro.aucunSon;
    }
    return EtatMicro.disponible;
  }

  /// Vrai quand plusieurs écoutes de suite n'ont rien entendu alors
  /// qu'aucun texte n'a été reconnu pendant la session.
  bool get microSilencieux => etatMicro == EtatMicro.aucunSon;

  void _ecouter(int jeton) {
    if (!_valide(jeton)) return;
    _relance?.cancel();
    // Après plusieurs écoutes sans rien entendre, l'affichage le signale
    // discrètement (voir [microSilencieux]).
    _changer(VoiceState.listening, 'À l’écoute…');
    // Dernier texte partiel de cette écoute. Android termine parfois une
    // écoute par error_no_match (ou sans résultat final) alors qu'il a déjà
    // reconnu la phrase : ce texte est alors traité comme la phrase.
    var partiel = '';
    void finSansPhrase({bool compterVide = true}) {
      if (!_valide(jeton)) return;
      final texte = partiel.trim();
      if (texte.isNotEmpty) {
        _traiter(jeton, texte);
      } else {
        _relancer(jeton, compterVide: compterVide);
      }
    }

    _reconnaissance.ecouter(
      surNiveau: _surNiveauMesure,
      surPartiel: (texte) {
        if (!_valide(jeton)) return;
        partiel = texte;
        if (texte.trim().isNotEmpty) _texteEntendu = true;
        transcription = texte;
        reponse = '';
        _impulsionSiPasDeNiveau();
        notifyListeners();
      },
      surPhrase: (phrase) => _traiter(jeton, phrase),
      surFinSansResultat: finSansPhrase,
      surErreur: (e) {
        if (!_valide(jeton)) return;
        switch (e) {
          case ErreurReconnaissance.rienEntendu:
            // Rien de clair : simple réécoute après une courte pause (sauf
            // si une phrase partielle a été reconnue).
            finSansPhrase();
          case ErreurReconnaissance.client:
            // Requête refusée par le moteur : passager, sauf s'il se
            // répète.
            if (++_refusConsecutifs >= 4) {
              _signalerReconnaissance(ErreurReconnaissance.autre);
            } else {
              finSansPhrase(compterVide: false);
            }
          default:
            _signalerReconnaissance(e);
        }
      },
    );
  }

  /// Relance l'écoute après un silence (une seule relance à la fois).
  void _relancer(int jeton, {bool compterVide = true}) {
    if (!_valide(jeton) || etat != VoiceState.listening) return;
    _relance?.cancel();
    if (compterVide) _ecoutesVides++;
    // Pause courte, croissante, pour ne jamais boucler instantanément si
    // le moteur renvoie des fins d'écoute en série.
    final essais = math.max(_ecoutesVides, _refusConsecutifs);
    final delai = Duration(milliseconds: 400 + 300 * math.min(essais, 5));
    _relance = Timer(delai, () => _ecouter(jeton));
  }

  Future<void> _traiter(int jeton, String phrase) async {
    if (!_valide(jeton)) return;
    _ecoutesVides = 0;
    _refusConsecutifs = 0;
    _texteEntendu = true;
    transcription = phrase;
    reponse = '';
    if (!reglages.reglages.reponseAutomatique) {
      // La phrase attend une validation ; l'écoute est suspendue.
      await _reconnaissance.annuler();
      if (!_valide(jeton)) return;
      phraseEnAttente = phrase;
      _changer(VoiceState.idle, 'Phrase prête');
      return;
    }
    await _repondre(jeton, phrase);
  }

  /// Réponse automatique désactivée : envoie la phrase en attente.
  Future<void> envoyerPhrase() async {
    final phrase = phraseEnAttente;
    if (phrase == null || !actif) return;
    phraseEnAttente = null;
    await _repondre(_jeton, phrase);
  }

  /// Abandonne la phrase en attente et réécoute.
  void ignorerPhrase() {
    if (phraseEnAttente == null || !actif) return;
    phraseEnAttente = null;
    transcription = '';
    _ecouter(_jeton);
  }

  Future<void> _repondre(int jeton, String phrase) async {
    if (!_valide(jeton)) return;
    final tour = ++_tour;
    bool courant() => _valide(jeton) && tour == _tour;
    _changer(VoiceState.thinking, 'JARVIS réfléchit…');
    await _reconnaissance.annuler();
    await _voix.appliquer(reglages.reglages);
    if (!courant()) return;

    final debut = DateTime.now();
    var derniereVoix = debut;
    var pauses = 0;
    final lecture = _lecture = LectureEnFlux(
      dire: (segment) async {
        // Écrit inchangé dans la conversation ; la voix dit la version
        // orale, phrase par phrase.
        if (!courant()) return ResultatParole.interrompue;
        final ecart = DateTime.now().difference(derniereVoix);
        if (_lecture?.segmentsDits != 0 && ecart > const Duration(milliseconds: 600)) {
          pauses++;
        }
        final r = await _prononcer(courant, segment);
        derniereVoix = DateTime.now();
        if (!r.reussie && r.issue == IssueParole.echec && courant()) {
          erreurVoix = r.message;
          notifyListeners();
        }
        return r;
      },
      surDebut: () {
        if (!courant()) return;
        debugPrint(
          '[JARVIS voix] début de parole '
          '${DateTime.now().difference(debut).inMilliseconds} ms après la question',
        );
        _changer(VoiceState.speaking, 'JARVIS parle…');
        if (_detectionVoulue) {
          detecteur!.surCandidat = (_) => _surCandidat(tour);
          detecteur!.demarrer();
        }
      },
    );
    final repondeur = this.repondeur;
    final reponseJarvis = repondeur == null
        ? await _commandes.traiter(phrase)
        : await repondeur(
            phrase,
            surFragment: (f) {
              if (courant()) lecture.ajouter(f);
            },
          );
    // Interrompu pendant la réception : l'écoute a déjà repris, rien de
    // l'ancien tour ne doit parler ni relancer quoi que ce soit.
    if (!courant()) return;
    if (reponseJarvis == null) {
      lecture.annuler();
      return;
    }
    if (!lecture.demarre) {
      // Réponse locale ou courte : réflexion visible entre 0,6 et 1,2 s.
      final duree = Duration(milliseconds: 600 + _hasard.nextInt(600));
      final reste = duree - DateTime.now().difference(debut);
      if (!reste.isNegative) await Future<void>.delayed(reste);
      if (!courant()) return;
    }
    reponse = reponseJarvis.texte;
    _echanges++;
    notifyListeners();
    lecture.terminer(
      texteComplet: reponseJarvis.texte,
      coupee: reponseJarvis.interrompue,
    );
    await lecture.fin;
    await detecteur?.arreter();
    if (!courant()) return;
    if (lecture.segmentsDits > 1) {
      debugPrint(
        '[JARVIS voix] lecture en flux : ${lecture.segmentsDits} phrases, '
        '$pauses pause(s) > 0,6 s',
      );
    }
    if (reponseJarvis.interrompue) {
      // Coupure réseau : rien d'inventé, une phrase discrète.
      await _prononcer(courant, 'Le réseau a coupé la fin de ma réponse.');
      if (!courant()) return;
    }
    _lecture = null;

    if (reponseJarvis.terminerSession) {
      // « Au revoir JARVIS » : le chat vocal est terminé, rien à reprendre.
      await arreter();
      _terminer();
      surFin?.call();
      return;
    }
    // La phrase et la réponse restent affichées pendant l'écoute suivante,
    // jusqu'à ce que l'utilisateur parle à nouveau. Le micro ne rouvre
    // qu'après la vraie fin de la voix, et une courte pause.
    await Future<void>.delayed(pauseApresParole);
    if (!courant()) return;
    _ecouter(jeton);
  }

  /// Volume du micro (reconnaissance vocale ou mesure Web Audio). Pris en
  /// compte seulement pendant l'écoute : pendant que JARVIS parle, le micro
  /// capterait sa propre voix.
  void _surNiveauMesure(double a) {
    if (!actif || etat != VoiceState.listening) return;
    _dernierNiveauReel = DateTime.now();
    // Attaque rapide, la décroissance se fait dans le minuteur.
    if (a > amplitude.value) amplitude.value = a;
  }

  /// Sans niveau sonore réel (Web, Windows), le texte partiel qui arrive
  /// sert d'indice : on donne une petite impulsion à PIM.
  void _impulsionSiPasDeNiveau() {
    final recent = DateTime.now().difference(_dernierNiveauReel);
    if (recent > const Duration(milliseconds: 500)) {
      amplitude.value = math.max(
        amplitude.value,
        0.35 + _hasard.nextDouble() * 0.35,
      );
    }
  }

  /// Fait parler JARVIS en transmettant le rythme de la phrase à PIM.
  ///
  /// La synthèse vocale ne fournit pas le son lui-même : on suit les mots
  /// qu'elle signale, pondérés par la [Prosodie] du texte. Si la plateforme
  /// ne signale aucun mot, le rythme est estimé à partir du texte.
  Future<ResultatParole> _prononcer(
    bool Function() valide,
    String texte, {
    void Function()? surDebut,
  }) async {
    final prosodie = Prosodie.analyser(texte);
    signal.debutPhrase();
    var motsReels = false;
    var suivant = 0;
    final chrono = Stopwatch()..start();
    // Instant prévu du prochain mot estimé (laisse au système le temps de
    // commencer à parler).
    var prevu = 0.25;
    _rythmeEstime?.cancel();
    _rythmeEstime = Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (motsReels || !valide() || suivant >= prosodie.mots.length) {
        t.cancel();
        return;
      }
      if (chrono.elapsedMilliseconds / 1000 < prevu) return;
      final mot = prosodie.mots[suivant++];
      _surMotPrononce(mot);
      prevu += mot.duree + mot.pauseApres;
    });
    final resultat = await _voix.parler(
      texte,
      surDebut: surDebut,
      surMot: (debut, _) {
        if (!valide()) return;
        motsReels = true;
        final mot = prosodie.motA(debut);
        if (mot != null) _surMotPrononce(mot);
      },
    );
    _rythmeEstime?.cancel();
    return resultat;
  }

  /// Phrase de l'aperçu de la voix.
  static const phraseApercu =
      'Bonjour, je suis JARVIS. Comment puis-je vous aider aujourd’hui ?';

  /// Aperçu de la voix avec les réglages actuels (voix, langue, vitesse,
  /// hauteur, volume). Les particules PIM réagissent comme pendant une
  /// vraie réponse. Indisponible pendant une conversation vocale.
  Future<void> lireApercu([String texte = phraseApercu]) async {
    if (actif) return;
    final jeton = ++_jetonApercu;
    apercuEnCours = true;
    apercuSonore = false;
    erreurApercu = null;
    _demarrerDecroissance();
    _changer(VoiceState.speaking, 'Aperçu de la voix…');
    await _voix.initialiser();
    await _voix.appliquer(reglages.reglages);
    bool valide() => apercuEnCours && jeton == _jetonApercu;
    if (!valide()) return;
    final resultat = await _prononcer(
      valide,
      texte,
      surDebut: () {
        if (!valide()) return;
        apercuSonore = true;
        notifyListeners();
      },
    );
    if (jeton != _jetonApercu) return;
    if (!resultat.reussie) erreurApercu = resultat.message;
    _finApercu();
  }

  /// Arrête l'aperçu en cours.
  Future<void> arreterApercu() => _arreterApercu();

  Future<void> _arreterApercu() async {
    if (!apercuEnCours) return;
    _jetonApercu++;
    _finApercu();
    await _voix.arreter();
  }

  void _finApercu() {
    apercuEnCours = false;
    apercuSonore = false;
    _rythmeEstime?.cancel();
    if (!actif) _decroissance?.cancel();
    amplitude.value = 0;
    _changer(VoiceState.idle, '');
  }

  /// Chaque mot prononcé par JARVIS : PIM en reconstruit l'enveloppe
  /// (accent, durée, syllabes).
  void _surMotPrononce(MotProsodique mot) {
    signal.mot(mot.accent, duree: mot.duree, syllabes: mot.syllabes);
    amplitude.value = math.max(amplitude.value, 0.3 + 0.7 * mot.accent);
  }

  /// Spectre du micro (Web), pris en compte seulement pendant l'écoute.
  void _surBandes(double graves, double mediums, double aigus) {
    if (!actif || etat != VoiceState.listening) return;
    signal.bandes(graves, mediums, aigus);
  }

  void _demarrerDecroissance() {
    _decroissance?.cancel();
    _decroissance = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (amplitude.value > 0.001) amplitude.value *= 0.86;
      signal.attenuer(0.86);
    });
  }

  void _signalerReconnaissance(ErreurReconnaissance e) {
    switch (e) {
      case ErreurReconnaissance.permission:
        _signaler(
          'Le microphone est nécessaire pour le mode vocal. '
          'Autorise l’accès au micro puis réessaie.',
          micro: EtatMicro.permissionRefusee,
        );
      case ErreurReconnaissance.indisponible:
        _signaler(
          kIsWeb
              ? 'La reconnaissance vocale n’est pas disponible dans ce '
                    'navigateur. Essaie avec Chrome ou Edge.'
              : 'La reconnaissance vocale n’est pas disponible sur cet '
                    'appareil.',
          titre: 'Reconnaissance vocale indisponible',
          micro: EtatMicro.reconnaissanceIndisponible,
        );
      case ErreurReconnaissance.reseau:
        _signaler(
          'Le service de reconnaissance vocale ne répond pas. '
          'Vérifie ta connexion Internet puis réessaie.',
          titre: 'Reconnaissance vocale hors ligne',
        );
      case ErreurReconnaissance.langue:
        _signaler(
          'La reconnaissance vocale en français n’est pas disponible '
          'sur cet appareil.',
          titre: 'Français non disponible',
        );
      case ErreurReconnaissance.rienEntendu:
      case ErreurReconnaissance.client:
      case ErreurReconnaissance.autre:
        _signaler('Le microphone s’est arrêté. Réessaie.');
    }
  }

  void _signaler(
    String message, {
    bool reglages = false,
    String titre = 'Micro indisponible',
    EtatMicro micro = EtatMicro.erreurReconnaissance,
  }) {
    // La boucle s'arrête vraiment : plus d'écoute, de voix ni de mesure.
    // « Réessayer » relance une session neuve avec [demarrer].
    _jeton++;
    actif = false;
    _relance?.cancel();
    _decroissance?.cancel();
    _rythmeEstime?.cancel();
    _reconnaissance.annuler();
    _voix.arreter();
    _niveau.arreter();
    amplitude.value = 0;
    signal.effacerBandes();
    phraseEnAttente = null;
    probleme = ProblemeVocal(
      message,
      reglages: reglages,
      titre: titre,
      micro: micro,
    );
    _changer(VoiceState.idle, '');
  }

  void _changer(VoiceState nouvelEtat, String nouveauStatut) {
    // Le spectre du micro ne concerne que la voix de l'utilisateur.
    if (nouvelEtat != VoiceState.listening) signal.effacerBandes();
    etat = nouvelEtat;
    statut = nouveauStatut;
    notifyListeners();
  }

  @override
  void dispose() {
    _jeton++;
    _jetonApercu++;
    _relance?.cancel();
    _decroissance?.cancel();
    _rythmeEstime?.cancel();
    _reconnaissance.annuler();
    _voix.arreter();
    _niveau.arreter();
    amplitude.dispose();
    super.dispose();
  }
}
