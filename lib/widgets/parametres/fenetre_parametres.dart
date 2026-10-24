import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_jarvis.dart';
import '../../services/apparence/service_apparence.dart';
import '../../services/authentification/auth_service.dart';
import '../../services/conversation/consentement_analyse.dart';
import '../../services/voice_session.dart';
import '../../theme/theme_jarvis.dart';
import '../../models/forme_pim.dart';
import '../../services/preferences_pim_service.dart';
import '../../services/integrations/service_gmail.dart';
import '../../services/utilisation/service_utilisation.dart';
import '../integrations/panneau_gmail.dart';
import '../integrations/panneau_outils.dart';
import 'pages_apparence.dart';
import 'pages_jarvis_touch.dart';
import '../utilisation/panneau_utilisation.dart';
import 'elements_parametres.dart';
import 'icone_reacteur_arc.dart';
import 'panneau_chat_vocal.dart';
import 'panneau_compte.dart';
import 'panneau_confidentialite.dart';
import 'panneau_general.dart';

/// Sections du panneau Paramètres.
enum SectionParametres {
  apparence('Apparence', Icons.palette_outlined),
  general('Général', Icons.tune_rounded),
  chatVocal('Chat vocal', Icons.graphic_eq_rounded),
  particules('Particules PIM', Icons.blur_on_rounded),
  utilisation('Utilisation', Icons.data_usage_rounded),
  outils('Outils', Icons.build_outlined),
  confidentialite('Confidentialité', Icons.lock_outline_rounded),

  /// Ouverte par la carte du compte, en bas de la navigation.
  compte('Compte', Icons.person_outline_rounded);

  const SectionParametres(this.libelle, this.icone);

  final String libelle;
  final IconData icone;
}

/// Compte affiché en bas de la navigation. Aucune connexion n'existe
/// encore : ces informations seront remplacées par le vrai compte.
/// Largeur en dessous de laquelle le panneau passe en plein écran, avec
/// la liste des sections puis la section choisie.
const largeurParametresCompacte = 760.0;

/// Ouvre les Paramètres par-dessus l'interface (fond légèrement assombri
/// et flouté). L'état de l'application continue : les particules restent
/// animées derrière.
/// Ouvre les Paramètres par-dessus l'accueil (qui n'est jamais recréé).
Future<void> ouvrirParametres(
  BuildContext context, {
  required VoiceSession session,
  PreferencesPimService? formes,
  SectionParametres section = SectionParametres.chatVocal,
  bool ouvrirSection = false,
  AuthService? compte,
  ApiJarvis? api,
  VoidCallback? surConnexion,
  ConsentementAnalyse? consentement,
  ServiceUtilisation? utilisation,
  ServiceGmail? gmail,
}) async {
  final compact = MediaQuery.sizeOf(context).width < largeurParametresCompacte;
  final route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: 'Fermer les paramètres',
    barrierColor: const Color(0x1C2A2438),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) => FenetreParametres(
      session: session,
      formes: formes,
      sectionInitiale: section,
      ouvrirSection: ouvrirSection,
      compte: compte,
      api: api,
      surConnexion: surConnexion,
      consentement: consentement,
      utilisation: utilisation,
      gmail: gmail,
    ),
    transitionBuilder: (context, animation, _, enfant) {
      final courbe = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final contenu = FadeTransition(
        opacity: courbe,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(courbe),
          child: enfant,
        ),
      );
      // En plein écran (téléphone), rien n'est visible derrière : pas de
      // flou, qui coûterait pour rien.
      if (compact) return contenu;
      return AnimatedBuilder(
        animation: courbe,
        builder: (context, enfant) => BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 3 * courbe.value,
            sigmaY: 3 * courbe.value,
          ),
          child: enfant,
        ),
        child: contenu,
      );
    },
  );
  try {
    await Navigator.of(context, rootNavigator: true).push(route);
  } finally {
    // Fermeture : on écrit tout de suite et on coupe l'aperçu vocal.
    session.reglages.enregistrer();
    session.arreterApercu();
  }
}

/// Fenêtre des Paramètres : grande fenêtre centrée sur ordinateur et
/// tablette, plein écran à deux niveaux sur téléphone.
class FenetreParametres extends StatefulWidget {
  const FenetreParametres({
    super.key,
    required this.session,
    this.formes,
    this.sectionInitiale = SectionParametres.chatVocal,
    this.ouvrirSection = false,
    this.compte,
    this.api,
    this.surConnexion,
    this.consentement,
    this.utilisation,
    this.gmail,
  });

  final VoiceSession session;

  /// Utilisation de l'IA du compte (null : sans compte).
  final ServiceUtilisation? utilisation;
  final ServiceGmail? gmail;

  /// Accord pour l'analyse distante des conversations WhatsApp (null :
  /// sans compte).
  final ConsentementAnalyse? consentement;

  /// Préférences des particules PIM (forme principale). Créées sur place
  /// si absentes.
  final PreferencesPimService? formes;
  final SectionParametres sectionInitiale;

  /// Téléphone : ouvre directement [sectionInitiale] (avatar du menu →
  /// Compte) au lieu de la liste des sections ; Retour mène à la liste.
  final bool ouvrirSection;

  /// Compte connecté (null : aucun serveur de comptes).
  final AuthService? compte;

  /// Backend JARVIS, pour vérifier le compte côté serveur.
  final ApiJarvis? api;

  /// « Se connecter » quand JARVIS est ouvert sans compte.
  final VoidCallback? surConnexion;

  @override
  State<FenetreParametres> createState() => _FenetreParametresState();
}

class _FenetreParametresState extends State<FenetreParametres> {
  late SectionParametres _section = widget.sectionInitiale;
  late final PreferencesPimService _formes =
      widget.formes ?? (PreferencesPimService()..charger());

  @override
  void dispose() {
    if (widget.formes == null) _formes.dispose();
    super.dispose();
  }

  /// Téléphone : vrai quand une section est ouverte (sinon la liste).
  late bool _dansSection = widget.ouvrirSection;

  /// Outils : outil ouvert (null : la liste des outils).
  OutilJarvis? _outil;

  /// Général : sous-page ouverte (JARVIS Touch…), null : Général.
  PageGenerale? _pageGenerale;

  /// Une sous-page (outil ou page de Général) est ouverte.
  bool get _sousPage => _outil != null || _pageGenerale != null;

  @override
  void initState() {
    super.initState();
    widget.session.reglages.chargerCapacites();
  }

  bool _fermeture = false;

  /// Croix : ferme TOUS les Paramètres d'un coup et rend l'accueil tel
  /// quel (conversation intacte), quelle que soit la sous-page ouverte.
  /// `pop` (et non `maybePop`) : le retour d'un niveau du [PopScope] ne
  /// s'applique pas ici. Une seule fermeture, même sur double appui.
  void _fermer() {
    if (_fermeture) return;
    _fermeture = true;
    final route = ModalRoute.of(context);
    final navigateur = Navigator.of(context);
    if (route == null || route.isCurrent) {
      navigateur.pop();
    } else {
      // Une liste déroulante est ouverte par-dessus : tout se ferme.
      navigateur.removeRoute(route);
    }
  }

  void _choisir(SectionParametres s) => setState(() {
    _section = s;
    _outil = null;
    _pageGenerale = null;
    _dansSection = true;
  });

  void _ouvrirPageGenerale(PageGenerale? p) =>
      setState(() => _pageGenerale = p);

  void _ouvrirOutil(OutilJarvis? o) => setState(() => _outil = o);

  /// Retour d'un niveau : outil → Outils, sous-page → page parente
  /// (Capture → JARVIS Touch → Général), puis liste (téléphone).
  void _retour() => setState(() {
    if (_outil != null) {
      _outil = null;
    } else if (_pageGenerale != null) {
      _pageGenerale = _pageGenerale!.parent;
    } else {
      _dansSection = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    final compact = taille.width < largeurParametresCompacte;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_sousPage || (compact && _dansSection)) {
            _retour();
          } else {
            _fermer();
          }
        },
      },
      child: FocusScope(
        autofocus: true,
        child: compact ? _pleinEcran() : _fenetre(taille),
      ),
    );
  }

  // --- Ordinateur et tablette --------------------------------------------

  Widget _fenetre(Size ecran) {
    final largeurNav = ecran.width >= 1100 ? 248.0 : 212.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CouleursJarvis.ivoire,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: CouleursJarvis.trait.withValues(alpha: 0.6),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x173A3350),
                  blurRadius: 56,
                  offset: Offset(0, 18),
                ),
                BoxShadow(
                  color: Color(0x0F3A3350),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: largeurNav,
                          child: _Navigation(
                            section: _section,
                            surChoix: (s) => setState(() {
                              _section = s;
                              _outil = null;
                              _pageGenerale = null;
                            }),
                            compte: widget.compte,
                          ),
                        ),
                        Expanded(
                          child: _Contenu(
                            section: _section,
                            session: widget.session,
                            formes: _formes,
                            compte: widget.compte,
                            api: widget.api,
                            surConnexion: widget.surConnexion,
                            consentement: widget.consentement,
                            utilisation: widget.utilisation,
                            gmail: widget.gmail,
                            outil: _outil,
                            surOutil: _ouvrirOutil,
                            pageGenerale: _pageGenerale,
                            surPageGenerale: _ouvrirPageGenerale,
                            marge: ecran.width >= 1100 ? 44 : 30,
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: _BoutonFermer(surFermer: _fermer),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Téléphone ------------------------------------------------------------

  Widget _pleinEcran() {
    return PopScope(
      // Retour (Android, Échap) : d'abord revenir à la liste.
      canPop: !_dansSection,
      onPopInvokedWithResult: (aFerme, _) {
        if (!aFerme && _dansSection) _retour();
      },
      child: Material(
        color: CouleursJarvis.ivoire,
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _dansSection
                ? Column(
                    key: ValueKey((_section, _outil, _pageGenerale)),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EnteteMobile(
                        titre:
                            _outil?.nom ??
                            _pageGenerale?.libelle ??
                            _section.libelle,
                        surRetour: _retour,
                        infoRetour: _outil != null
                            ? 'Retour aux outils'
                            : _pageGenerale != null
                            ? 'Retour à ${_pageGenerale!.parent?.libelle ?? 'Général'}'
                            : null,
                        surFermer: _fermer,
                      ),
                      Expanded(
                        child: _Contenu(
                          section: _section,
                          session: widget.session,
                          formes: _formes,
                          compte: widget.compte,
                          api: widget.api,
                          surConnexion: widget.surConnexion,
                          consentement: widget.consentement,
                          utilisation: widget.utilisation,
                          gmail: widget.gmail,
                          outil: _outil,
                          surOutil: _ouvrirOutil,
                          pageGenerale: _pageGenerale,
                          surPageGenerale: _ouvrirPageGenerale,
                          marge: 18,
                          avecTitre: false,
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('liste'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EnteteMobile(titre: 'Paramètres', surFermer: _fermer),
                      Expanded(
                        child: _Navigation(
                          section: null,
                          surChoix: _choisir,
                          compte: widget.compte,
                          grand: true,
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

class _BoutonFermer extends StatelessWidget {
  const _BoutonFermer({required this.surFermer});

  final VoidCallback surFermer;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Fermer',
      onPressed: surFermer,
      icon: const Icon(Icons.close_rounded, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: CouleursJarvis.texteSecondaire,
        minimumSize: const Size(44, 44),
      ),
    );
  }
}

class _EnteteMobile extends StatelessWidget {
  const _EnteteMobile({
    required this.titre,
    required this.surFermer,
    this.surRetour,
    this.infoRetour,
  });

  final String titre;
  final VoidCallback surFermer;
  final VoidCallback? surRetour;
  final String? infoRetour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        children: [
          if (surRetour != null)
            IconButton(
              tooltip: infoRetour ?? 'Retour aux paramètres',
              onPressed: surRetour,
              icon: const Icon(Icons.arrow_back_rounded),
              style: IconButton.styleFrom(
                foregroundColor: CouleursJarvis.texte,
                minimumSize: const Size(48, 48),
              ),
            )
          else
            const SizedBox(width: 14),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                titre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: policeAffichage,
                  fontSize: surRetour == null ? 24 : 19,
                  fontWeight: FontWeight.w400,
                  color: CouleursJarvis.texte,
                ),
              ),
            ),
          ),
          _BoutonFermer(surFermer: surFermer),
        ],
      ),
    );
  }
}

/// Colonne de navigation : sections, puis le compte en bas.
class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.section,
    required this.surChoix,
    required this.compte,
    this.grand = false,
  });

  /// Section affichée (null sur téléphone : simple liste).
  final SectionParametres? section;
  final ValueChanged<SectionParametres> surChoix;
  final AuthService? compte;

  /// Téléphone : entrées plus hautes, chevron à droite.
  final bool grand;

  /// Premières sections des groupes de la liste du téléphone.
  static const _debutsDeGroupe = {
    SectionParametres.chatVocal,
    SectionParametres.utilisation,
  };

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grand
            ? Colors.transparent
            : CouleursJarvis.creme.withValues(alpha: 0.55),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, grand ? 8 : 26, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!grand)
              Padding(
                padding: EdgeInsets.only(left: 12, bottom: 22),
                child: Text(
                  'JARVIS',
                  style: TextStyle(
                    fontFamily: policeAffichage,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: CouleursJarvis.signal,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final s in SectionParametres.values)
                    if (s != SectionParametres.compte) ...[
                      // Téléphone : trois groupes (apparence, voix et
                      // particules, compte et données), séparés par un
                      // espace ; un trait fin entre deux lignes d'un groupe.
                      if (grand &&
                          _debutsDeGroupe.contains(s) &&
                          s != SectionParametres.values.first)
                        const SizedBox(height: 14)
                      else if (grand && s != SectionParametres.values.first)
                        Padding(
                          padding: const EdgeInsets.only(left: 60),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: CouleursJarvis.trait.withValues(alpha: 0.45),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(bottom: grand ? 0 : 4),
                        child: _EntreeNavigation(
                          section: s,
                          choisie: s == section,
                          grand: grand,
                          surChoix: () => surChoix(s),
                        ),
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _CarteUtilisateur(
              compte: compte,
              choisie: section == SectionParametres.compte,
              surAppui: () => surChoix(SectionParametres.compte),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntreeNavigation extends StatelessWidget {
  const _EntreeNavigation({
    required this.section,
    required this.choisie,
    required this.grand,
    required this.surChoix,
  });

  final SectionParametres section;
  final bool choisie;
  final bool grand;
  final VoidCallback surChoix;

  @override
  Widget build(BuildContext context) {
    final couleur = choisie ? CouleursJarvis.texte : CouleursJarvis.texte;
    return Semantics(
      selected: choisie,
      button: true,
      child: Material(
        color: choisie ? CouleursJarvis.coque : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: choisie
                ? CouleursJarvis.trait.withValues(alpha: 0.8)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: surChoix,
          focusColor: CouleursJarvis.signal.withValues(alpha: 0.12),
          hoverColor: CouleursJarvis.coque.withValues(alpha: 0.7),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: grand ? 56 : 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: grand ? 6 : 12),
              child: Row(
                children: [
                  if (grand)
                    // Téléphone : icône dans une pastille douce, toutes
                    // alignées sur la même colonne.
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: CouleursJarvis.signal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        section.icone,
                        size: 20,
                        color: CouleursJarvis.signal,
                      ),
                    )
                  else
                    Icon(
                      section.icone,
                      size: 19,
                      color: choisie
                          ? CouleursJarvis.signal
                          : CouleursJarvis.texteSecondaire,
                    ),
                  SizedBox(width: grand ? 16 : 12),
                  Expanded(
                    child: Text(
                      section.libelle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: grand ? 16 : 14,
                        fontWeight: choisie || grand
                            ? (grand ? FontWeight.w500 : FontWeight.w600)
                            : FontWeight.w400,
                        color: couleur,
                      ),
                    ),
                  ),
                  if (grand)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte du compte, discrète, en bas de la navigation : nom et offre du
/// compte connecté (lus sur le serveur), ou « Sans compte ». Ouvre la
/// section « Compte ».
class _CarteUtilisateur extends StatelessWidget {
  const _CarteUtilisateur({
    required this.compte,
    required this.choisie,
    required this.surAppui,
  });

  final AuthService? compte;
  final bool choisie;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final c = compte;
    if (c == null) return _carte(nom: 'Sans compte', offre: 'Compte');
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final u = c.utilisateur;
        if (u == null) return _carte(nom: 'Sans compte', offre: 'Se connecter');
        final p = c.profil;
        return _carte(
          nom: p?.nom ?? u.nom ?? u.email,
          offre: p?.offre.libelle ?? 'Compte JARVIS',
        );
      },
    );
  }

  Widget _carte({required String nom, required String offre}) {
    final initiale = nom.isEmpty ? '?' : nom.characters.first.toUpperCase();
    return Semantics(
      button: true,
      selected: choisie,
      label: 'Compte $nom, $offre',
      excludeSemantics: true,
      child: Material(
        color: choisie
            ? CouleursJarvis.coque
            : CouleursJarvis.coque.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: choisie
                ? CouleursJarvis.signal.withValues(alpha: 0.45)
                : CouleursJarvis.trait.withValues(alpha: 0.7),
          ),
        ),
        child: InkWell(
          onTap: surAppui,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: CouleursJarvis.signal.withValues(
                    alpha: 0.14,
                  ),
                  child: Text(
                    initiale,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CouleursJarvis.signal,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nom,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: CouleursJarvis.texte,
                        ),
                      ),
                      Text(
                        offre,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenu d'une section : titre « Paramètres », sous-titre de la section,
/// indicateur « Enregistré », puis les réglages (défilement propre).
class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.section,
    required this.session,
    required this.formes,
    required this.marge,
    this.compte,
    this.api,
    this.surConnexion,
    this.consentement,
    this.utilisation,
    this.gmail,
    this.outil,
    this.surOutil,
    this.pageGenerale,
    this.surPageGenerale,
    this.avecTitre = true,
  });

  /// Général : sous-page ouverte et navigation.
  final PageGenerale? pageGenerale;
  final ValueChanged<PageGenerale?>? surPageGenerale;

  final SectionParametres section;

  /// Outils : outil ouvert (null : la liste) et navigation entre les deux.
  final OutilJarvis? outil;
  final ValueChanged<OutilJarvis?>? surOutil;
  final ServiceUtilisation? utilisation;
  final ServiceGmail? gmail;
  final ConsentementAnalyse? consentement;
  final VoiceSession session;
  final PreferencesPimService formes;
  final AuthService? compte;
  final ApiJarvis? api;
  final VoidCallback? surConnexion;
  final double marge;
  final bool avecTitre;

  /// Apparence : thèmes et motifs sur une seule page.
  Widget _apparence(BuildContext context) {
    final a = ServiceApparence.of(context, ecouter: false);
    if (a == null) {
      return const NoteReglage('Apparence indisponible dans cette fenêtre.');
    }
    return PageApparence(apparence: a);
  }

  @override
  Widget build(BuildContext context) {
    // Outils : colonne plus étroite, centrée dans la place disponible.
    final outils = section == SectionParametres.outils;
    // Page d'un outil : bloc centré aussi verticalement quand il tient
    // dans l'écran (défilement sinon).
    // Particules PIM : la grille ENTIÈRE est centrée verticalement dans
    // l'espace sous l'en-tête (défilement si la place manque).
    final pim = section == SectionParametres.particules;
    final centre = (outils && outil != null) || pim;
    final marges = EdgeInsets.fromLTRB(
      marge,
      avecTitre ? 34 : 8,
      marge,
      marge + 8,
    );
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        key: PageStorageKey((section, outil, pageGenerale)),
        padding: marges,
        child: Align(
          alignment: outils || pim ? Alignment.topCenter : Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: outils || pim ? 560 : 680,
              minHeight: centre
                  ? (c.maxHeight - marges.vertical).clamp(0, double.infinity)
                  : 0,
            ),
            child: _Hauteur(
              active: centre,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (avecTitre) ...[
                    Text(
                      'Paramètres',
                      style: TextStyle(
                        fontFamily: policeAffichage,
                        fontSize: 27,
                        fontWeight: FontWeight.w300,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (outils && outil != null) ...[
                          _RetourOutils(surRetour: () => surOutil?.call(null)),
                          const SizedBox(width: 6),
                        ],
                        if (section == SectionParametres.general &&
                            pageGenerale != null) ...[
                          _RetourOutils(
                            libelle: pageGenerale!.parent?.libelle ?? 'Général',
                            surRetour: () =>
                                surPageGenerale?.call(pageGenerale!.parent),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          outil?.nom ??
                              (section == SectionParametres.general
                                  ? pageGenerale?.libelle
                                  : null) ??
                              section.libelle,
                          style: TextStyle(
                            fontSize: 15,
                            color: CouleursJarvis.texteSecondaire,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (section == SectionParametres.chatVocal)
                          _Enregistre(session: session),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ] else if (section == SectionParametres.chatVocal) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: _Enregistre(session: session),
                    ),
                    const SizedBox(height: 6),
                  ],
                  switch (section) {
                    SectionParametres.apparence => _apparence(context),
                    SectionParametres.general => PanneauGeneral(
                      page: pageGenerale,
                      surPage: (p) => surPageGenerale?.call(p),
                    ),
                    SectionParametres.utilisation => PanneauUtilisation(
                      service: utilisation,
                    ),
                    SectionParametres.outils => switch (outil) {
                      null => PanneauOutils(
                        gmail: gmail,
                        surChoix: (o) => surOutil?.call(o),
                      ),
                      OutilJarvis.gmail => Expanded(
                        child: Center(child: PanneauGmail(service: gmail)),
                      ),
                      OutilJarvis.agenda => const Expanded(
                        child: Center(child: PanneauAgenda()),
                      ),
                    },
                    SectionParametres.chatVocal => PanneauChatVocal(
                      session: session,
                    ),
                    SectionParametres.particules => Expanded(
                      child: Center(child: _FormePrincipale(formes: formes)),
                    ),
                    SectionParametres.confidentialite => PanneauConfidentialite(
                      consentement: consentement,
                    ),
                    SectionParametres.compte => PanneauCompte(
                      compte: compte,
                      api: api,
                      surConnexion: surConnexion,
                    ),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hauteur au moins égale à l'espace visible ([active]) : l'enfant
/// `Expanded` de la colonne peut alors centrer son contenu.
class _Hauteur extends StatelessWidget {
  const _Hauteur({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      active ? IntrinsicHeight(child: child) : child;
}

/// Ordinateur : « ‹ Outils » devant le nom de l'outil ouvert.
class _RetourOutils extends StatelessWidget {
  const _RetourOutils({required this.surRetour, this.libelle = 'Outils'});

  final VoidCallback surRetour;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: surRetour,
      icon: const Icon(Icons.arrow_back_rounded, size: 17),
      label: Text(libelle, style: const TextStyle(fontSize: 15)),
      style: TextButton.styleFrom(
        foregroundColor: CouleursJarvis.signal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 34),
      ),
    );
  }
}

/// « Enregistré » apparaît un instant après chaque sauvegarde.
class _Enregistre extends StatefulWidget {
  const _Enregistre({required this.session});

  final VoiceSession session;

  @override
  State<_Enregistre> createState() => _EnregistreState();
}

class _EnregistreState extends State<_Enregistre> {
  bool _visible = false;
  int _vu = 0;

  ValueNotifier<int> get _sauvegardes => widget.session.reglages.sauvegardes;

  @override
  void initState() {
    super.initState();
    _vu = _sauvegardes.value;
    _sauvegardes.addListener(_surSauvegarde);
  }

  @override
  void dispose() {
    _sauvegardes.removeListener(_surSauvegarde);
    super.dispose();
  }

  Future<void> _surSauvegarde() async {
    final n = _sauvegardes.value;
    if (n == _vu || !mounted) return;
    _vu = n;
    setState(() => _visible = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted && _vu == n) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 15, color: CouleursJarvis.signal),
          SizedBox(width: 4),
          Text(
            'Enregistré',
            style: TextStyle(fontSize: 12.5, color: CouleursJarvis.signal),
          ),
        ],
      ),
    );
  }
}

/// « Forme de JARVIS » : choix visuel parmi les quatre formes, enregistré.
class _FormePrincipale extends StatelessWidget {
  const _FormePrincipale({required this.formes});

  final PreferencesPimService formes;

  static Widget icone(FormePim f, Color couleur) => switch (f) {
    FormePim.sphere => Icon(Icons.language_rounded, size: 30, color: couleur),
    FormePim.cube => Icon(Icons.view_in_ar_rounded, size: 30, color: couleur),
    FormePim.tetraedre => Icon(
      Icons.change_history_rounded,
      size: 30,
      color: couleur,
    ),
    FormePim.reacteur => IconeReacteurArc(taille: 32, couleur: couleur),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: formes,
      builder: (context, _) {
        final principale = formes.forme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'FORME DE JARVIS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
            ),
            // Grille 2 × 2, quelle que soit la largeur : deux rangées de
            // deux tuiles de même largeur (sans LayoutBuilder : la section
            // mesure sa hauteur pour centrer la grille).
            for (var rang = 0; rang < FormePim.values.length; rang += 2) ...[
              if (rang > 0) const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (k, f)
                        in FormePim.values.skip(rang).take(2).indexed) ...[
                      if (k > 0) const SizedBox(width: 14),
                      Expanded(
                        child: TuileChoix(
                          icone: (couleur) => icone(f, couleur),
                          libelle: f.libelle,
                          choisie: f == principale,
                          surChoix: () => formes.choisir(f),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
