import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/conversations/apercu_conversation.dart';
import '../models/conversations/source_conversation.dart';
import '../services/conversation/conversation_session.dart';
import '../services/conversations/conversations_multicanal.dart';
import '../services/conversations/epingles_conversations.dart';
import '../services/conversations/fournisseur_conversations.dart';
import '../services/conversations/fournisseur_jarvis.dart';
import '../services/importation/pont_android_importation.dart';
import '../services/preferences_pim_service.dart';
import '../services/voice_session.dart';
import '../theme/gabarit_jarvis.dart';
import '../theme/theme_jarvis.dart';
import '../utils/local_date_time.dart';
import '../widgets/bouton_vocal.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/fond_jarvis_anime.dart';
import '../widgets/ligne_de_commande.dart';
import '../widgets/menu_lateral.dart';
import '../widgets/parametres/fenetre_parametres.dart';
import '../widgets/pim_particle.dart';
import '../widgets/voice_status.dart';
import 'conversation_page.dart';
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

  @override
  State<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends State<AccueilPage> {
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
  Timer? _retourAccueil;

  bool _modeVocal = false;

  // Chat vocal reprenable (capsule bleu-violet du bouton vocal).
  bool _vocalReprenable = false;

  // Lecture vocale des réponses en mode écrit (haut-parleur) : désactivée
  // par défaut et à chaque retour du mode vocal. Le micro n'en dépend pas.
  bool _lectureVocale = false;
  // Dernière réponse de JARVIS déjà vue (seules les nouvelles sont lues).
  int _derniereVue = -1;

  late final _conversation = widget.conversation ?? ConversationSession();
  bool _enConversation = false;

  late final _multicanal =
      widget.multicanal ??
      ConversationsMulticanal(
        fournisseurs: [
          FournisseurJarvis(_conversation),
          for (final s in SourceConversation.values)
            if (s != SourceConversation.jarvis) FournisseurNonIntegre(s),
        ],
        epingles: EpinglesConversations(),
      );

  // Forme principale de PIM, enregistrée sur l'appareil.
  late final _formesPim = widget.formesPim ?? PreferencesPimService();
  bool _formeAppliquee = false;

  // Menu latéral : seul le menu se reconstruit à l'ouverture (pas la page,
  // ni les particules).
  final _menu = ValueNotifier<bool>(false);

  // Import WhatsApp : partages reçus, et ceux qui arrivent pendant que la
  // page d'import est ouverte (null : page fermée).
  late final _partages = widget.partages ?? PontAndroidImportation.reception;
  StreamController<PartageRecu>? _partagesImport;

  @override
  void initState() {
    super.initState();
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
    _formesPim.addListener(_surFormePim);
    if (_formesPim.charge) {
      _surFormePim();
    } else {
      _formesPim.charger();
    }
    // Réglages vocaux enregistrés (voix, vitesse, micro…), appliqués à
    // chaque prise de parole.
    _session.reglages.charger();
    // Conversations épinglées (menu latéral).
    _multicanal.epingles.charger();
  }

  @override
  void dispose() {
    _partages.annonces.removeListener(_surPartage);
    _partagesImport?.close();
    _retourAccueil?.cancel();
    _controleur.dispose();
    _focus.dispose();
    _session.removeListener(_surSession);
    _session.dispose();
    _conversation.removeListener(_surConversation);
    if (widget.conversation == null) _conversation.dispose();
    _menu.dispose();
    if (widget.multicanal == null) _multicanal.dispose();
    _formesPim.removeListener(_surFormePim);
    if (widget.formesPim == null) _formesPim.dispose();
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
  }

  void _fermerMenu() => _menu.value = false;

  /// Titre de la conversation en cours pour le menu (début du premier
  /// message), ou null s'il n'y en a pas.
  String? get _titreConversation {
    if (!_enConversation) return null;
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
          surFermer: _fermerMenu,
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

  /// Suppression confirmée dans le menu (qui reste ouvert). Si c'est la
  /// conversation affichée, l'accueil revient vide : le chat vocal qui lui
  /// appartenait se termine, la saisie est vidée, PIM n'est pas touché.
  void _supprimerConversation(ApercuConversation c) {
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
    _multicanal.supprimer(c);
  }

  Future<void> _ouvrirParametres() async {
    _focus.unfocus();
    // Quitter l'accueil interrompt une démonstration en cours.
    _pim.annulerApercu();
    await ouvrirParametres(context, session: _session, formes: _formesPim);
  }

  /// « + » → « Importer une conversation » : page d'import WhatsApp
  /// par-dessus l'accueil (la conversation en cours n'est pas touchée).
  /// Page d'import WhatsApp par-dessus l'accueil (la conversation en
  /// cours n'est pas touchée). Une seule page à la fois : les partages
  /// suivants lui sont transmis.
  Future<void> _ouvrirImportationWhatsApp({PartageRecu? partage}) async {
    if (_partagesImport != null) return;
    final flux = _partagesImport = StreamController<PartageRecu>();
    _focus.unfocus();
    _pim.annulerApercu();
    try {
      await ouvrirImportationWhatsApp(
        context,
        partageInitial: partage,
        partages: flux.stream,
      );
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

  void _envoyer(String message) {
    // Petite impulsion des particules le long de la barre, puis le
    // message part dans la conversation.
    _pim.surEnvoi();
    _conversation.envoyer(message);
    _controleur.clear();
  }

  /// Lecture vocale activée : chaque nouvelle réponse écrite de JARVIS est
  /// aussi prononcée (les réponses du chat vocal le sont déjà).
  void _lireNouvelleReponse() {
    final messages = _conversation.messages;
    if (messages.isEmpty) return;
    final m = messages.last;
    if (!m.deJarvis || m.id <= _derniereVue) return;
    _derniereVue = m.id;
    if (_lectureVocale && !_modeVocal && !m.vocal) {
      _session.lireReponse(m.texte);
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
              // Fond fixe, centré sur la zone des particules.
              zoneParticules: _pim.zone,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      // Calque des particules, derrière toute l'interface : en
                      // conversation, elles restent visibles à travers le fond
                      // légèrement translucide des cartes, jamais devant le
                      // texte.
                      child: PimParticle(
                        controleur: _pim,
                        cleCentre: _cleCentre,
                        cleChamp: _cleChamp,
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
                                    axisAlignment: -1,
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
    final g = gabarit;
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
                color: CouleursJarvis.texteSecondaire,
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
          child: const Padding(
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
                const Flexible(
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
