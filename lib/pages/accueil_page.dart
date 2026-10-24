import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/conversations/apercu_conversation.dart';
import '../models/conversations/source_conversation.dart';
import '../models/importation/piece_jointe_whatsapp.dart';
import '../services/api_jarvis.dart';
import '../services/apprentissage/espace_apprentissage.dart';
import '../services/authentification/auth_service.dart';
import '../services/conversation/consentement_analyse.dart';
import '../services/conversation/conversation_session.dart';
import '../services/conversation/moteur_conversation_hybride.dart';
import '../services/conversation/moteur_conversation_ia.dart';
import '../services/conversations/correspondance_conversations.dart';
import '../services/conversations/depot_conversations.dart';
import '../services/conversations/synchro_echanges_locaux.dart';
import '../services/conversations/synchronisation_conversations.dart';
import '../services/conversations/conversations_multicanal.dart';
import '../services/conversations/epingles_conversations.dart';
import '../services/conversations/fournisseur_conversations.dart';
import '../services/conversations/fournisseur_jarvis.dart';
import '../services/importation/pieces_jointes_serveur.dart';
import '../services/conversation/reponses_envoyees.dart';
import '../services/importation/pont_android_importation.dart';
import '../services/detecteur_intervention.dart';
import '../services/jarvis_touch_chat.dart';
import '../services/jarvis_touch_service.dart';
import '../services/preferences_pim_service.dart';
import '../services/integrations/service_gmail.dart';
import '../services/utilisation/service_utilisation.dart';
import '../services/voice_session.dart';
import '../theme/gabarit_jarvis.dart';
import '../theme/theme_jarvis.dart';
import '../utils/local_date_time.dart';
import '../utils/chrono_perf.dart';
import '../widgets/conversation/volet_aide_reponse.dart';
import '../widgets/bouton_vocal.dart';
import '../widgets/conversation/carte_piece_jointe.dart';
import '../widgets/defilement_sans_barre.dart';
import '../models/apparence/fond_photo.dart';
import '../services/apparence/service_fonds.dart';
import '../widgets/fond_jarvis_anime.dart';
import '../widgets/ligne_de_commande.dart';
import '../widgets/menu_lateral.dart';
import '../widgets/parametres/fenetre_parametres.dart';
import '../widgets/pim_particle.dart';
import '../widgets/voice_status.dart';
import 'apprentissage/apprendre_page.dart';
import 'conversation_page.dart';
import '../services/importation/actualisation_whatsapp.dart';
import '../widgets/importation/volet_actualisation.dart';
import 'importation_whatsapp_page.dart';

/// Page d'accueil, affichée après l'écran de lancement.
///
/// Les particules PIM sont dessinées dans un calque plein écran, derrière
/// l'interface : elles se regroupent dans la zone centrale ([_cleCentre])
/// ou entourent le champ texte ([_cleChamp]) pendant l'écriture.
///
/// Mode vocal : la ligne de commande et la salutation s'effacent, la zone
/// centrale grandit, avec un statut discret et un bouton pour quitter.
///
/// Conversation écrite : dès le premier message envoyé, la zone centrale
/// devient le fil de discussion ([ConversationPage]) ; la barre, le fond et
/// les particules (autour de la barre) restent ceux de l'accueil.
/// « Nouvelle conversation » ramène à l'accueil.
class AccueilPage extends StatefulWidget {
  const AccueilPage({
    super.key,
    this.session,
    this.pim,
    this.conversation,
    this.formesPim,
    this.multicanal,
    this.partages,
    this.auth,
    this.api,
    this.surConnexion,
    this.depotConversations,
    this.ouvrirImport,
    this.consentement,
    this.utilisation,
    this.gmail,
    this.apprentissage,
  });

  /// Injectables pour les tests (services vocaux factices, diagnostic des
  /// particules, conversation). Créés par défaut sinon.
  final VoiceSession? session;
  final PimController? pim;
  final ConversationSession? conversation;

  /// Préférences des particules (forme principale) ; injectables pour les
  /// tests, créées sinon.
  final PreferencesPimService? formesPim;

  /// Conversations des messageries pour le menu latéral ; injectables pour
  /// les tests (données de démonstration), créées sinon : JARVIS réel, les
  /// autres messageries pas encore intégrées (listes vides).
  final ConversationsMulticanal? multicanal;

  /// Partages reçus de l'extérieur (export WhatsApp sur Android) ; ceux de
  /// la plateforme par défaut.
  final ReceptionPartages? partages;

  /// Compte (section « Compte » des Paramètres) ; null : aucun serveur
  /// d'authentification (tests, préversions).
  final AuthService? auth;

  /// Backend JARVIS : vérification du compte côté serveur, et IA de la
  /// conversation (écrite et vocale) quand les règles locales ne suffisent
  /// pas. Null : règles locales seules.
  final ApiJarvis? api;

  /// « Se connecter » depuis les Paramètres, quand JARVIS est ouvert sans
  /// compte (accès de développement).
  final VoidCallback? surConnexion;

  /// Conversations enregistrées du compte connecté (null : sans compte,
  /// tout reste en mémoire). Vit avec cette page : à la déconnexion, la
  /// page et ses données disparaissent.
  final DepotConversations? depotConversations;

  /// Accord pour l'analyse distante des conversations WhatsApp jointes ;
  /// injectable pour les tests, créé sinon pour le compte connecté.
  final ConsentementAnalyse? consentement;

  /// Utilisation de l'IA du compte (section « Utilisation » des
  /// Paramètres ; null : sans compte).
  final ServiceUtilisation? utilisation;

  /// Connexion Gmail du compte (Paramètres › Outils › Gmail) ; null sans compte.
  final ServiceGmail? gmail;

  /// Module Apprendre (tests) ; créé sinon à sa première ouverture
  /// seulement, jamais au démarrage.
  final EspaceApprentissage? apprentissage;

  /// Après un échec d'enregistrement d'une pièce jointe.
  static const pieceJointeGardee =
      'La pièce jointe et votre consigne sont gardées : renvoyez pour '
      'réessayer.';

  /// Parcours d'import WhatsApp (tests) ; [ouvrirImportationWhatsApp] par
  /// défaut. Renvoie la pièce jointe préparée, ou null.
  final Future<PieceJointeWhatsApp?> Function(
    BuildContext context, {
    PartageRecu? partageInitial,
    Stream<PartageRecu>? partages,
  })?
  ouvrirImport;

  @override
  State<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends State<AccueilPage> with WidgetsBindingObserver {
  static const _transition = Duration(milliseconds: 550);

  final _controleur = TextEditingController();
  final _focus = FocusNode();
  late final _session = widget.session ?? VoiceSession();

  late final _pim = widget.pim ?? PimController();
  final _cleCentre = GlobalKey();
  final _cleChamp = GlobalKey();
  // Zone PIM réservée au-dessus de la barre pendant une conversation.
  final _cleZonePim = GlobalKey();
  String _texteConnu = '';
  bool _accueilVisible = true;

  /// Conversation WhatsApp jointe (interface 3), en attente de sa
  /// consigne : en mémoire seulement, jamais envoyée seule.
  PieceJointeWhatsApp? _pieceJointe;

  /// Enregistrement de la pièce jointe en cours (serveur) : un second
  /// appui sur « Envoyer » attend.
  bool _envoiPieceJointe = false;
  Timer? _retourAccueil;

  bool _modeVocal = false;

  // Chat vocal reprenable (capsule bleu-violet du bouton vocal).
  bool _vocalReprenable = false;

  // Lecture vocale des réponses en mode écrit (haut-parleur) : désactivée
  // par défaut et à chaque retour du mode vocal. Le micro n'en dépend pas.
  bool _lectureVocale = false;
  // Dernière réponse de JARVIS déjà vue (seules les nouvelles sont lues).
  int _derniereVue = -1;

  // Conversation du fil <-> conversation serveur : partagée par le moteur
  // IA et la synchronisation (jamais deux fois la même conversation).
  final _correspondance = CorrespondanceConversations();

  late final _synchronisation = switch (widget.depotConversations) {
    final depot? => SynchronisationConversations(depot),
    null => null,
  };

  // Échanges traités sur l'appareil (heure, calcul…) : enregistrés dans
  // les conversations du compte connecté, sans passer par l'IA.
  late final _echangesLocaux = switch ((
    widget.depotConversations,
    widget.depotConversations?.utilisateur,
    widget.api,
  )) {
    (final depot?, final compte?, final api?) => SynchroEchangesLocaux(
      compte: compte,
      compteActuel: () => depot.utilisateur,
      correspondance: _correspondance,
      decalage: () => widget.auth?.decalageHorloge,
      envoyer: (e, conversation) => api.enregistrerEchangeLocal(
        idQuestion: e.idQuestion,
        idReponse: e.idReponse,
        question: e.question,
        reponse: e.reponse,
        conversation: conversation,
        questionA: e.questionA,
        reponseA: e.reponseA,
      ),
    ),
    _ => null,
  };

  // Accord pour l'analyse des conversations WhatsApp jointes, par compte
  // (sans compte : rien n'est enregistré sur le serveur, rien à analyser).
  late final _consentement =
      widget.consentement ??
      switch (widget.depotConversations?.utilisateur) {
        final compte? => ConsentementAnalyse(compte: compte),
        null => null,
      };

  late final _conversation =
      widget.conversation ??
      ConversationSession(
        moteur: switch (widget.api) {
          final api? => MoteurConversationHybride(
            ia: MoteurConversationIA(
              api,
              correspondance: _correspondance,
              avantEnvoi: _echangesLocaux?.attendre,
              analyseWhatsApp: () => _consentement?.etat.valeurApi,
            ),
          ),
          null => null,
        },
        consentement: _consentement,
        depot: widget.depotConversations,
        // Compte connecté : pièces jointes WhatsApp enregistrées par le
        // serveur (retrouvées sur les autres appareils).
        piecesJointes: switch ((widget.depotConversations, widget.api)) {
          (_?, final api?) => PiecesJointesApi(api),
          _ => null,
        },
        reponsesEnvoyees: switch ((widget.depotConversations, widget.api)) {
          (_?, final api?) => ReponsesEnvoyeesApi(api),
          _ => null,
        },
        correspondance: _correspondance,
        actualisation: _actualisation,
      );
  bool _enConversation = false;

  late final _multicanal = widget.multicanal ?? _creerMulticanal();

  /// JARVIS, puis WhatsApp (chats reclassés par une pièce jointe envoyée,
  /// en mémoire), puis les messageries pas encore intégrées.
  ConversationsMulticanal _creerMulticanal() {
    final jarvis = FournisseurJarvis(
      _conversation,
      synchronisation: _synchronisation,
      echangesLocaux: _echangesLocaux,
    );
    final epingles = EpinglesConversations();
    // Chat reclassé à l'envoi d'une pièce jointe : son épingle le suit.
    _conversation.surPieceJointe = (envoi) => epingles.deplacer(
      '${SourceConversation.jarvis.name}:${envoi.idConversation}',
      '${envoi.pieceJointe.source.name}:${envoi.idConversation}',
    );
    return ConversationsMulticanal(
      fournisseurs: [
        jarvis,
        FournisseurSourceClassee(SourceConversation.whatsapp, jarvis),
        // Conversations où Gmail a réellement servi (marquées par le serveur).
        FournisseurSourceClassee(SourceConversation.gmail, jarvis),
        for (final s in SourceConversation.values)
          if (s != SourceConversation.jarvis &&
              s != SourceConversation.whatsapp &&
              s != SourceConversation.gmail)
            FournisseurNonIntegre(s),
      ],
      epingles: epingles,
    );
  }

  // Forme principale de PIM, enregistrée sur l'appareil.
  late final _formesPim = widget.formesPim ?? PreferencesPimService();
  bool _formeAppliquee = false;

  // Mini-chat de JARVIS Touch (Android) : autre vue de la même conversation.
  PasserelleMiniChat? _miniChat;

  // Menu latéral : seul le menu se reconstruit à l'ouverture (pas la page,
  // ni les particules).
  final _menu = ValueNotifier<bool>(false);

  // Import WhatsApp : partages reçus, et ceux qui arrivent pendant que la
  // page d'import est ouverte (null : page fermée).
  late final _partages = widget.partages ?? PontAndroidImportation.reception;
  StreamController<PartageRecu>? _partagesImport;

  /// Fond propre à la conversation affichée (null : fond général). Changé
  /// seulement quand ce fond change, jamais à chaque message.
  final _fondConversation = ValueNotifier<FondChoisi?>(null);
  ServiceFonds? _fonds;

  void _majFond() {
    final fond = _fonds?.fondDe([
      _conversation.idServeurCourant,
      _conversation.idCourant,
    ]);
    if (fond != _fondConversation.value) _fondConversation.value = fond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fonds = ServiceFonds.of(context, ecouter: false);
    if (fonds != _fonds) {
      _fonds?.removeListener(_majFond);
      _fonds = fonds?..addListener(_majFond);
      _majFond();
    }
  }

  @override
  void initState() {
    super.initState();
    _conversation.addListener(_majFond);
    // Partage arrivé avant l'accueil (lancement à froid, connexion) ou
    // pendant qu'il est affiché.
    _partages.annonces.addListener(_surPartage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _surPartage());
    _conversation.addListener(_surConversation);
    _pim.amplitude = _session.amplitude;
    _pim.signal = _session.signal;
    _controleur.addListener(_surFrappe);
    // Toucher le champ interrompt une forme secondaire (cube, tétraèdre,
    // réacteur) : l'utilisateur va interagir.
    _focus.addListener(() => _pim.saisieFocus = _focus.hasFocus);
    _session.addListener(_surSession);
    _session.surFin = _surFinSession;
    // Une seule conversation : le vocal y ajoute ses échanges et partage
    // son contexte avec l'écrit.
    _session.repondeur = _conversation.repondreVocal;
    _session.annulerReponse = _conversation.interrompreReponseVocale;
    if (DetecteurIntervention.disponible) {
      _session.detecteur ??= DetecteurIntervention();
    }
    _formesPim.addListener(_surFormePim);
    if (_formesPim.charge) {
      _surFormePim();
    } else {
      _formesPim.charger();
    }
    // Réglages vocaux enregistrés (voix, vitesse, micro…), appliqués à
    // chaque prise de parole.
    _session.reglages.charger();
    // JARVIS Touch (Android) : bulle rallumée si elle était activée ; son
    // mini-chat affiche et alimente CETTE conversation.
    JarvisTouchService.instance.restaurer();
    if (JarvisTouchService.instance.disponible) {
      _miniChat = PasserelleMiniChat(_conversation, vocal: _session)
        ..attacher();
    }
    final consentement = _consentement;
    if (consentement != null && !consentement.charge) consentement.charger();
    // Conversations épinglées (menu latéral).
    _multicanal.epingles.charger();
    // Conversations enregistrées : à la connexion, puis à l'ouverture du
    // menu, au retour au premier plan et après chaque échange avec l'IA.
    WidgetsBinding.instance.addObserver(this);
    _conversation.avantPieceJointe = _echangesLocaux?.attendre;
    _conversation.surEchangeEnregistre = () {
      _echangesLocaux?.envoyer();
      _synchronisation?.actualiser();
    };
    final echanges = _echangesLocaux;
    if (echanges != null) {
      _conversation.surEchangeLocal = echanges.ajouter;
      // File restée sur l'appareil (hors connexion, application fermée).
      echanges.charger().then((_) => echanges.envoyer());
    }
    _synchronisation?.actualiser(force: true);
  }

  // Depuis quand JARVIS est masqué (onglet caché, application en arrière-
  // plan) ; null : visible.
  DateTime? _masqueDepuis;

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.hidden || etat == AppLifecycleState.paused) {
      _masqueDepuis ??= DateTime.now();
      return;
    }
    if (etat != AppLifecycleState.resumed) return;
    final depuis = _masqueDepuis;
    _masqueDepuis = null;
    // Une simple perte de focus (fréquente sur le Web et sous Windows) ne
    // relit rien : seulement un vrai retour après au moins 30 s, quand un
    // autre appareil a pu poursuivre ou supprimer une conversation.
    if (depuis == null ||
        DateTime.now().difference(depuis) < const Duration(seconds: 30)) {
      return;
    }
    _echangesLocaux?.envoyer();
    _synchronisation?.actualiser();
    _conversation.rafraichir();
  }

  @override
  void dispose() {
    _pimPendantApprendre.dispose();
    _conversation.removeListener(_majFond);
    _fonds?.removeListener(_majFond);
    _fondConversation.dispose();
    _miniChat?.detacher();
    WidgetsBinding.instance.removeObserver(this);
    _conversation.surEchangeEnregistre = null;
    _conversation.surEchangeLocal = null;
    _partages.annonces.removeListener(_surPartage);
    _partagesImport?.close();
    _retourAccueil?.cancel();
    _controleur.dispose();
    _focus.dispose();
    _session.removeListener(_surSession);
    _session.dispose();
    _conversation.removeListener(_surConversation);
    if (widget.conversation == null) _conversation.dispose();
    if (widget.consentement == null) _consentement?.dispose();
    _menu.dispose();
    if (widget.multicanal == null) _multicanal.dispose();
    _synchronisation?.dispose();
    _echangesLocaux?.dispose();
    _formesPim.removeListener(_surFormePim);
    if (widget.formesPim == null) _formesPim.dispose();
    if (widget.apprentissage == null) _apprentissage?.dispose();
    super.dispose();
  }

  void _surFrappe() {
    if (_controleur.text == _texteConnu) return;
    _texteConnu = _controleur.text;
    _pim.surTexte(_texteConnu);
    // En conversation, la salutation est déjà masquée : la frappe ne
    // reconstruit pas la page (ni le fil).
    if (_enConversation) return;
    // Pendant l'écriture, les particules entourent la barre et passeraient
    // sur la salutation : elle s'efface, puis revient avec les particules
    // (même délai que leur retour au centre).
    _retourAccueil?.cancel();
    if (_texteConnu.trim().isNotEmpty) {
      if (_accueilVisible) setState(() => _accueilVisible = false);
    } else {
      _retourAccueil = Timer(
        Duration(
          milliseconds: (PimReglages.delaiRetourCentre * 1000).round() + 300,
        ),
        () {
          if (mounted) setState(() => _accueilVisible = true);
        },
      );
    }
  }

  /// Forme principale : appliquée sans transition au lancement, puis avec
  /// une transition naturelle à chaque changement.
  void _surFormePim() {
    _pim.definirFormePrincipale(_formesPim.forme, immediat: !_formeAppliquee);
    _formeAppliquee = true;
  }

  void _surSession() {
    if (_session.reprenable != _vocalReprenable) {
      setState(() {
        _vocalReprenable = _session.reprenable;
        // Le haut-parleur n'existe qu'avec un chat vocal en arrière-plan :
        // sans lui, la lecture vocale se coupe.
        if (!_vocalReprenable) _lectureVocale = false;
      });
      if (!_vocalReprenable) _session.arreterLecture();
    }
    // L'aperçu de la voix (Paramètres) anime aussi les particules.
    _pim.etatVocal = _modeVocal || _session.apercuEnCours
        ? _session.etat
        : null;
  }

  void _ouvrirMenu() {
    // Le clavier se referme ; le texte saisi reste dans la barre.
    _focus.unfocus();
    _menu.value = true;
    _multicanal.actualiser(SourceConversation.jarvis);
  }

  void _fermerMenu() => _menu.value = false;

  /// Titre de la conversation en cours pour le menu (début du premier
  /// message), ou null s'il n'y en a pas.
  String? get _titreConversation {
    if (!_enConversation) return null;
    // Chat classé sous WhatsApp : le nom du contact.
    final id = _conversation.idCourant;
    final classement = id == null ? null : _conversation.classement(id);
    if (classement != null) return classement.titre;
    for (final m in _conversation.messages) {
      if (m.deJarvis) continue;
      if (m.texte.trim().isNotEmpty) return m.texte.trim();
      if (m.conversation != null) return 'Conversation collée';
    }
    return 'Conversation en cours';
  }

  Widget _menuLateral() {
    return ValueListenableBuilder<bool>(
      valueListenable: _menu,
      builder: (context, ouvert, _) => PopScope(
        // Retour (Android) : ferme d'abord le menu.
        canPop: !ouvert,
        onPopInvokedWithResult: (aFerme, _) {
          if (!aFerme && ouvert) _fermerMenu();
        },
        child: MenuLateral(
          ouvert: ouvert,
          surOuvrir: _ouvrirMenu,
          surFermer: _fermerMenu,
          compte: widget.auth,
          surCompte: () {
            _fermerMenu();
            _ouvrirParametres(
              section: SectionParametres.compte,
              ouvrirSection: true,
            );
          },
          conversationEnCours: ouvert ? _titreConversation : null,
          surAccueil: _fermerMenu,
          surNouvelle: () {
            _fermerMenu();
            _nouvelleConversation();
          },
          surChatVocal: () {
            _fermerMenu();
            if (!_modeVocal) _ouvrirModeVocal();
          },
          surParametres: () {
            _fermerMenu();
            _ouvrirParametres();
          },
          surApprendre: ModuleApprentissage.actif ? _ouvrirApprendre : null,
          multicanal: _multicanal,
          surOuvrirConversation: _ouvrirConversation,
          surSupprimerConversation: _supprimerConversation,
        ),
      ),
    );
  }

  /// Conversation touchée dans le menu : le menu se ferme et l'accueil
  /// l'affiche (messages et contexte). Le chat vocal en cours s'arrête :
  /// il appartenait à l'autre conversation.
  void _ouvrirConversation(ApercuConversation c) {
    if (!c.disponible) return;
    _fermerMenu();
    if (c.ouverte) return;
    if (_modeVocal) {
      setState(() {
        _modeVocal = false;
        _lectureVocale = false;
      });
      _pim.etatVocal = null;
    }
    _session.quitterChatVocal();
    _multicanal.ouvrir(c);
  }

  /// Suppression confirmée dans le menu (qui reste ouvert). Une fois la
  /// suppression réussie (serveur compris), si c'était la conversation
  /// affichée, l'accueil revient vide : le chat vocal qui lui appartenait
  /// se termine, la saisie est vidée, PIM n'est pas touché. Échec : rien
  /// ne change (le menu explique pourquoi).
  Future<void> _supprimerConversation(ApercuConversation c) async {
    final supprimee = await _multicanal.supprimer(c);
    if (!mounted || !supprimee) return;
    if (c.ouverte) {
      if (_modeVocal) {
        setState(() {
          _modeVocal = false;
          _lectureVocale = false;
        });
        _pim.etatVocal = null;
      }
      _session.terminerChatVocal();
      _controleur.clear();
    }
  }

  /// Module Apprendre : créé à la première ouverture puis gardé (corpus en
  /// cache, progression lue). L'accueil passe hors scène pendant ce temps :
  /// PIM s'arrête de lui-même et repart au retour.
  EspaceApprentissage? _apprentissage;
  final _pimPendantApprendre = ValueNotifier<bool>(true);

  Future<void> _ouvrirApprendre() async {
    if (!_pimPendantApprendre.value) return;
    _fermerMenu();
    _focus.unfocus();
    _pim.annulerApercu();
    final espace = _apprentissage ??=
        widget.apprentissage ??
        EspaceApprentissage(lecteur: LecteurEcouteSession(_session));
    // Geler les tickers avant la première image de transition, sans
    // capture GPU ni modification du moteur. Comparaison profile possible
    // avec ext.jarvis.variante (sans=apprendre.pause).
    _pimPendantApprendre.value = false;
    try {
      await ouvrirApprendre(context, espace);
    } finally {
      if (mounted) _pimPendantApprendre.value = true;
    }
  }

  Future<void> _ouvrirParametres({
    SectionParametres section = SectionParametres.chatVocal,
    bool ouvrirSection = false,
  }) async {
    _focus.unfocus();
    // Quitter l'accueil interrompt une démonstration en cours.
    _pim.annulerApercu();
    await ouvrirParametres(
      context,
      session: _session,
      formes: _formesPim,
      section: section,
      ouvrirSection: ouvrirSection,
      compte: widget.auth,
      api: widget.api,
      surConnexion: widget.surConnexion,
      consentement: _consentement,
      utilisation: widget.utilisation,
      gmail: widget.gmail,
    );
  }

  /// « + » → « Importer une conversation » : page d'import WhatsApp
  /// par-dessus l'accueil (la conversation en cours n'est pas touchée).
  /// Page d'import WhatsApp par-dessus l'accueil (la conversation en
  /// cours n'est pas touchée). Une seule page à la fois : les partages
  /// suivants lui sont transmis.
  /// Phase 5 : actualiser un contexte WhatsApp par copier-coller (compte
  /// connecté seulement).
  late final ServiceActualisationWhatsApp? _actualisation = switch ((
    widget.depotConversations,
    widget.api,
  )) {
    (_?, final api?) => ActualisationWhatsAppApi(api),
    _ => null,
  };

  /// Volet par-dessus le chat : brouillon, pièce jointe en attente,
  /// position, vocal et PIM intacts. Aucun appel à l'IA.
  Future<void> _ouvrirActualisation() async {
    final service = _actualisation;
    if (service == null) return;
    final r = await afficherVoletActualisation(
      context,
      service: service,
      contextesDuChat: _conversation.contextesCourants,
    );
    if (!mounted || r == null) return;
    // Confirmation visuelle : les bulles dans le fil (aucun message de
    // JARVIS, aucun appel à l'IA).
    _conversation.afficherAjouts(r.contexte, r.messages);
  }

  Future<void> _ouvrirImportationWhatsApp({PartageRecu? partage}) async {
    if (_partagesImport != null) return;
    final flux = _partagesImport = StreamController<PartageRecu>();
    _focus.unfocus();
    _pim.annulerApercu();
    try {
      final ouvrir = widget.ouvrirImport ?? _importParDefaut;
      final piece = await ouvrir(
        context,
        partageInitial: partage,
        partages: flux.stream,
      );
      // Retour dans le même chat (ou l'accueil vide) : la pièce jointe
      // attend dans la barre ; le texte déjà saisi est gardé.
      if (piece != null && mounted) setState(() => _pieceJointe = piece);
    } finally {
      _partagesImport = null;
      flux.close();
    }
  }

  /// Partage Android (« Exporter la discussion » → JARVIS) : pris une
  /// seule fois, puis montré dans la page d'import (ouverte au besoin).
  Future<void> _surPartage() async {
    final partage = await _partages.prendre();
    if (partage == null || !mounted) return;
    final ouverte = _partagesImport;
    if (ouverte != null) {
      ouverte.add(partage);
    } else {
      _ouvrirImportationWhatsApp(partage: partage);
    }
  }

  /// La session s'arrête d'elle-même après « Au revoir JARVIS » : on
  /// revient alors au mode texte. (Après une erreur micro, on reste en mode
  /// vocal pour afficher le message et « Réessayer ».)
  void _surFinSession() {
    if (!mounted || !_modeVocal) return;
    setState(() => _modeVocal = false);
    _pim.etatVocal = null;
  }

  /// La conversation commence (premier message) ou se termine
  /// (« Nouvelle conversation ») : seule bascule qui reconstruit la page.
  void _surConversation() {
    _lireNouvelleReponse();
    final actif = !_conversation.vide;
    _pim.conversation = actif;
    if (actif == _enConversation) return;
    setState(() {
      _enConversation = actif;
      // Retour à l'accueil : la salutation revient si la barre est vide.
      if (!actif) _accueilVisible = _texteConnu.trim().isEmpty;
    });
  }

  /// Message reçu hors WhatsApp : JARVIS propose une réponse dans le chat
  /// (moteur habituel), rien n'est envoyé dans la messagerie.
  Future<void> _aiderARepondre() async {
    final demande = await afficherVoletAideReponse(context);
    if (demande == null || !mounted) return;
    _pim.surEnvoi();
    _conversation.envoyer(demande.question);
  }

  void _envoyer(String message) {
    // Petite impulsion des particules le long de la barre, puis le
    // message part dans la conversation.
    final piece = _pieceJointe;
    if (piece != null) {
      _envoyerPieceJointe(message, piece);
      return;
    }
    _pim.surEnvoi();
    _conversation.envoyer(message);
    _controleur.clear();
  }

  /// Consigne et pièce jointe partent ensemble, une seule fois. Avec un
  /// compte, elles ne quittent la barre qu'une fois enregistrées ; échec :
  /// elles restent (même pièce jointe, mêmes identifiants : un nouvel
  /// envoi ne crée aucun doublon).
  Future<void> _envoyerPieceJointe(
    String message,
    PieceJointeWhatsApp piece,
  ) async {
    if (_envoiPieceJointe) return;
    setState(() => _envoiPieceJointe = true);
    _pim.surEnvoi();
    final r = await _conversation.envoyerAvecPieceJointe(message, piece);
    if (!mounted) return;
    setState(() {
      _envoiPieceJointe = false;
      if (r is PieceJointeEnvoyee && identical(_pieceJointe, piece)) {
        _pieceJointe = null;
        _controleur.clear();
      }
    });
    if (r case PieceJointeNonEnvoyee(:final raison)) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$raison ${AccueilPage.pieceJointeGardee}',
              style: TextStyle(fontSize: 13.5, color: CouleursJarvis.ivoire),
            ),
            behavior: SnackBarBehavior.floating,
            // Au-dessus de la barre : « Envoyer » reste accessible pour
            // réessayer.
            margin: _margeAuDessusDeLaBarre(),
            backgroundColor: CouleursJarvis.texte.withValues(alpha: 0.92),
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
    }
  }

  static Future<PieceJointeWhatsApp?> _importParDefaut(
    BuildContext context, {
    PartageRecu? partageInitial,
    Stream<PartageRecu>? partages,
  }) => ouvrirImportationWhatsApp(
    context,
    partageInitial: partageInitial,
    partages: partages,
  );

  EdgeInsets? _margeAuDessusDeLaBarre() {
    final barre = _cleChamp.currentContext?.findRenderObject();
    if (barre is! RenderBox || !barre.hasSize) return null;
    final haut = barre.localToGlobal(Offset.zero).dy;
    final ecran = MediaQuery.sizeOf(context).height;
    return EdgeInsets.fromLTRB(16, 0, 16, (ecran - haut + 8).clamp(8, ecran));
  }

  /// Croix de la pièce jointe : la préparation est abandonnée (rien
  /// n'avait été enregistré) ; le texte saisi et le chat restent.
  void _retirerPieceJointe() {
    if (_envoiPieceJointe) return;
    setState(() => _pieceJointe = null);
  }

  /// Lecture vocale activée : chaque nouvelle réponse écrite de JARVIS est
  /// aussi prononcée (les réponses du chat vocal le sont déjà), une seule
  /// fois et en entier : dès la fin de sa réception, sans attendre la fin
  /// de son écriture à l'écran ni lire les fragments un à un.
  void _lireNouvelleReponse() {
    final messages = _conversation.messages;
    if (messages.isEmpty) return;
    final m = messages.last;
    if (!m.deJarvis || m.redaction || m.id <= _derniereVue) return;
    _derniereVue = m.id;
    if (_lectureVocale && !_modeVocal && !m.vocal) {
      _session.lireReponse(
        m.incident == null ? m.texte : '${m.texte} ${m.incident}',
      );
    }
  }

  void _basculerLecture() {
    setState(() => _lectureVocale = !_lectureVocale);
    if (!_lectureVocale) _session.arreterLecture();
  }

  void _nouvelleConversation() {
    _conversation.effacer();
    _controleur.clear();
    // Nouvelle conversation : le chat vocal précédent se termine aussi.
    _session.terminerChatVocal();
  }

  void _ouvrirModeVocal() {
    _focus.unfocus();
    _session.arreterLecture();
    setState(() => _modeVocal = true);
    _pim.etatVocal = _session.etat;
    _session.demarrer();
  }

  /// Retour au mode écrit : interface vocale fermée, la voix se tait
  /// jusqu'à nouvelle activation de la lecture.
  void _fermerModeVocal() {
    setState(() {
      _modeVocal = false;
      _lectureVocale = false;
    });
    _pim.etatVocal = null;
  }

  /// « Quitter le mode vocal » : le chat vocal s'arrête pour de bon (micro
  /// et voix coupés, rien à reprendre : capsule sombre, pas de
  /// haut-parleur). La conversation écrite est conservée.
  Future<void> _quitterModeVocal() async {
    _fermerModeVocal();
    await _session.quitterChatVocal();
  }

  /// « Retour au chat » : micro, reconnaissance et voix coupés, interface
  /// vocale fermée, conversation écrite retrouvée (avec les échanges
  /// vocaux). Le chat vocal reste reprenable s'il y a eu un échange.
  Future<void> _retourAuChat() async {
    _fermerModeVocal();
    await _session.mettreEnArrierePlan();
  }

  @override
  Widget build(BuildContext context) {
    final gabarit = GabaritJarvis.of(context);
    // Lu au-dessus du Scaffold : dans son corps, l'encart du clavier est
    // déjà retiré (le corps est redimensionné).
    final clavier = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      // Aucune barre de défilement visible sur l'accueil (fil, champ de
      // saisie, salutation) ; le défilement reste actif. Le menu latéral se
      // pose par-dessus (voile léger + panneau).
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScrollConfiguration(
            behavior: const DefilementSansBarre(),
            child: FondJarvisAnime(
              // Fond fixe, centré sur la zone des particules ; celui de la
              // conversation affichée s'il en a un.
              zoneParticules: _pim.zone,
              fondConversation: _fondConversation,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // Calque des particules, derrière toute l'interface : en
                      // conversation, elles restent visibles à travers le fond
                      // légèrement translucide des cartes, jamais devant le
                      // texte.
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _pimPendantApprendre,
                        builder: (context, actif, child) => TickerMode(
                          enabled: actif || ChronoPerf.sans('apprendre.pause'),
                          child: child!,
                        ),
                        child: PimParticle(
                          controleur: _pim,
                          cleCentre: _cleCentre,
                          cleChamp: _cleChamp,
                        ),
                      ),
                    ),
                    Padding(
                      padding: gabarit.marges,
                      child: Column(
                        children: [
                          _BarreHaute(
                            gabarit,
                            surMenu: _ouvrirMenu,
                            surNouvelle: _enConversation && !_modeVocal
                                ? _nouvelleConversation
                                : null,
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                _zoneCentrale(gabarit, clavier: clavier),
                                if (_enConversation && !_modeVocal)
                                  Positioned.fill(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: 1),
                                      duration: const Duration(
                                        milliseconds: 350,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, t, enfant) =>
                                          Opacity(opacity: t, child: enfant),
                                      child: ConversationPage(
                                        session: _conversation,
                                        gabarit: gabarit,
                                        surPoserQuestion: _focus.requestFocus,
                                        cleZonePim: _cleZonePim,
                                        reveilServeur:
                                            widget.api?.reveilEnCours,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: _transition,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (enfant, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    alignment: Alignment.topLeft,
                                    // SizeTransition aligne à gauche : on recentre.
                                    child: Center(child: enfant),
                                  ),
                                ),
                            child: _modeVocal
                                ? Padding(
                                    key: const ValueKey('quitter'),
                                    padding: const EdgeInsets.only(top: 4),
                                    child: _CommandesVocales(
                                      quitter: _BoutonQuitter(
                                        session: _session,
                                        surQuitter: _quitterModeVocal,
                                      ),
                                      surRetourChat: _retourAuChat,
                                    ),
                                  )
                                : ConstrainedBox(
                                    key: const ValueKey('texte'),
                                    constraints: BoxConstraints(
                                      maxWidth: gabarit.largeurSaisie,
                                    ),
                                    child: LigneDeCommande(
                                      key: _cleChamp,
                                      controleur: _controleur,
                                      focus: _focus,
                                      onEnvoyer: _envoyer,
                                      onChatVocal: _ouvrirModeVocal,
                                      chatVocalReprenable: _vocalReprenable,
                                      // Haut-parleur à côté de la capsule
                                      // vocale, seulement quand elle est
                                      // bleu-violet.
                                      lectureVocale: _vocalReprenable
                                          ? _lectureVocale
                                          : null,
                                      surLecture: _basculerLecture,
                                      surImporterWhatsApp:
                                          _ouvrirImportationWhatsApp,
                                      surAiderARepondre: _aiderARepondre,
                                      surAjouterMessageWhatsApp:
                                          _actualisation == null
                                          ? null
                                          : _ouvrirActualisation,
                                      pieceJointe: _pieceJointe == null
                                          ? null
                                          : PieceJointeEnAttente(
                                              piece: _pieceJointe!,
                                              surRetirer: _retirerPieceJointe,
                                              enCours: _envoiPieceJointe,
                                            ),
                                      compacte: gabarit.compact,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: _menuLateral()),
        ],
      ),
    );
  }

  Widget _zoneCentrale(GabaritJarvis gabarit, {required bool clavier}) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final hauteur = contraintes.maxHeight;
        // Zone des particules : bornée entre un minimum et un maximum selon
        // le format, jamais plus grande que la place disponible.
        var taille = gabarit.zone(
          contraintes.maxWidth,
          hauteur,
          vocal: _modeVocal,
        );
        // Clavier ouvert et place trop juste pour la salutation : elle
        // s'efface (même fondu que pendant la frappe) et la sphère reprend
        // cette place, sans jamais dépasser sa taille clavier fermé.
        final salutCache =
            clavier && !_modeVocal && hauteur - taille < gabarit.reserveTexte;
        if (salutCache) {
          taille = math.min(
            gabarit.zone(
              contraintes.maxWidth,
              hauteur + gabarit.reserveTexte,
              vocal: false,
            ),
            hauteur - 16,
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: taille),
                duration: _transition,
                curve: Curves.easeInOutCubic,
                // Zone vide : les particules PIM s'y regroupent (calque).
                // Pendant la transition, la taille animée ne dépasse jamais
                // la place réelle : quand le clavier monte, la place
                // diminue plus vite que l'animation.
                builder: (context, t, _) => SizedBox.square(
                  key: _cleCentre,
                  dimension: math.max(0.0, math.min(t, hauteur)),
                ),
              ),
              // Le texte prend la place restante ; s'il est trop long, il
              // défile au lieu de déborder.
              Flexible(
                child: ScrollConfiguration(
                  // Jamais de barre de défilement visible.
                  behavior: const DefilementSansBarre(),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: AnimatedSwitcher(
                      duration: _transition,
                      child: _modeVocal
                          ? VoiceStatus(
                              key: const ValueKey('statut'),
                              session: _session,
                            )
                          : AnimatedOpacity(
                              key: const ValueKey('salut'),
                              // En conversation, la salutation laisse la
                              // place au fil (la mise en page, et donc le
                              // fond, ne bougent pas).
                              opacity:
                                  _accueilVisible &&
                                      !salutCache &&
                                      !_enConversation
                                  ? 1
                                  : 0,
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOutCubic,
                              child: _Accueil(gabarit: gabarit),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Salutation et mission de JARVIS, sous les particules.
class _Accueil extends StatelessWidget {
  const _Accueil({required this.gabarit});

  final GabaritJarvis gabarit;

  /// Mission principale de JARVIS.
  static const mission =
      'JARVIS vous aide à comprendre et répondre à vos conversations.';

  @override
  Widget build(BuildContext context) {
    final clarte = ServiceFonds.of(context, ecouter: false)?.clarteFondPhoto;
    if (clarte == null) return _textes(context, null);
    return ValueListenableBuilder<double?>(
      valueListenable: clarte,
      builder: (context, c, _) => _textes(context, c),
    );
  }

  /// Fond photo trop sombre pour l'encre du thème (ou trop clair pour un
  /// thème sombre) : texte inversé, avec une ombre douce, toujours lisible.
  Widget _textes(BuildContext context, double? clarteFond) {
    final g = gabarit;
    final p = PaletteJarvis.of(context);
    final inverse =
        clarteFond != null &&
        (p.sombre ? clarteFond > 0.55 : clarteFond < 0.42);
    final clair = inverse ? !p.sombre : p.sombre;
    final titre = inverse
        ? (clair ? const Color(0xFFFAF8F2) : const Color(0xFF1E1F26))
        : null;
    final ombres = clarteFond == null
        ? null
        : [
            Shadow(
              color: (clair ? Colors.black : Colors.white).withValues(
                alpha: 0.45,
              ),
              blurRadius: 10,
            ),
          ];
    return Padding(
      padding: EdgeInsets.only(top: g.ecartSphereTexte),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            salutation(DateTime.now()),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontSize: g.tailleSalutation,
              letterSpacing: -0.3,
              color: titre,
              shadows: ombres,
            ),
          ),
          SizedBox(height: g.compact ? 8 : 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: g.largeurMission),
            child: Text(
              mission,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: g.tailleMission,
                height: 1.5,
                letterSpacing: 0.1,
                color:
                    titre?.withValues(alpha: 0.88) ??
                    CouleursJarvis.texteSecondaire,
                shadows: ombres,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Commandes du mode vocal : « Quitter le mode vocal » et « Retour au
/// chat », centrés ensemble sur une ligne si la place le permet, sinon
/// l'un sous l'autre.
class _CommandesVocales extends StatelessWidget {
  const _CommandesVocales({required this.quitter, required this.surRetourChat});

  final Widget quitter;
  final VoidCallback surRetourChat;

  @override
  Widget build(BuildContext context) {
    final retour = _BoutonRetourChat(surRetour: surRetourChat);
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth >= 600) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [quitter, const SizedBox(width: 8), retour],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [quitter, retour],
        );
      },
    );
  }
}

/// « Retour au chat » : petite icône de conversation et libellé discret.
class _BoutonRetourChat extends StatelessWidget {
  const _BoutonRetourChat({required this.surRetour});

  final VoidCallback surRetour;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: surRetour,
        customBorder: const StadiumBorder(),
        hoverColor: CouleursJarvis.texte.withValues(alpha: 0.04),
        focusColor: CouleursJarvis.signal.withValues(alpha: 0.1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: CouleursJarvis.texteSecondaire,
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Retour au chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mode vocal : la capsule vocale montre l'état (écoute, parole) ; le tout
/// est le bouton « Quitter le mode vocal », discret.
class _BoutonQuitter extends StatelessWidget {
  const _BoutonQuitter({required this.session, required this.surQuitter});

  final VoiceSession session;
  final VoidCallback surQuitter;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: surQuitter,
        customBorder: const StadiumBorder(),
        hoverColor: CouleursJarvis.texte.withValues(alpha: 0.04),
        focusColor: CouleursJarvis.signal.withValues(alpha: 0.1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => BoutonVocal(
                        etat: session.etat,
                        libelle: 'Quitter le mode vocal',
                        onPressed: surQuitter,
                        largeur: 48,
                        hauteur: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Écran très étroit : le libellé se raccourcit plutôt que de
                // déborder.
                Flexible(
                  child: Text(
                    'Quitter le mode vocal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo JARVIS centré et discret en haut ; menu latéral à gauche (dont les
/// Paramètres) ; pendant une conversation, « Nouvelle conversation » à
/// droite (retour à l'accueil).
class _BarreHaute extends StatelessWidget {
  const _BarreHaute(this.gabarit, {required this.surMenu, this.surNouvelle});

  final GabaritJarvis gabarit;
  final VoidCallback surMenu;
  final VoidCallback? surNouvelle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: gabarit.hauteurBarre,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Le logo reste au centre de l'écran, quelle que soit la place
          // prise par les boutons.
          Text(
            'JARVIS',
            style: TextStyle(
              fontFamily: policeAffichage,
              fontSize: gabarit.tailleLogo,
              fontWeight: FontWeight.w500,
              letterSpacing: 4.5,
              color: CouleursJarvis.signal.withValues(alpha: 0.78),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: BoutonMenu(surOuvrir: surMenu),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (surNouvelle != null)
                  IconButton(
                    tooltip: 'Nouvelle conversation',
                    onPressed: surNouvelle,
                    icon: const Icon(Icons.edit_square, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: CouleursJarvis.texteSecondaire,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
