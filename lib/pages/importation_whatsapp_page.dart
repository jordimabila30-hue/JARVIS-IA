import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/importation/conversation_whatsapp.dart';
import '../models/importation/export_whatsapp.dart';
import '../services/importation/depot_fichiers.dart';
import '../services/importation/export_local.dart';
import '../services/importation/identite_whatsapp.dart';
import '../services/importation/import_en_cours.dart';
import '../services/importation/lecture_whatsapp.dart';
import '../services/importation/pont_android_importation.dart';
import '../services/importation/selection_export_whatsapp.dart';
import '../theme/theme_jarvis.dart';
import '../widgets/authentification/bandeau_auth.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/importation/accueil_import_whatsapp.dart';
import '../widgets/importation/carte_export_choisi.dart';
import '../widgets/importation/choix_fichiers_recus.dart';
import '../widgets/importation/lecture_whatsapp_widgets.dart';
import '../widgets/importation/logo_whatsapp.dart';
import 'resume_whatsapp_page.dart';

/// Ouvre l'import WhatsApp par-dessus l'accueil, qui reste intact
/// (conversation en cours, chat vocal) ; les particules s'y mettent en
/// pause tant que la page le recouvre.
///
/// [partageInitial] : fichier(s) reçu(s) par le partage Android, déjà
/// sélectionné(s) à l'ouverture. [partages] : partages arrivant pendant
/// que la page est ouverte (ils remplacent le fichier affiché).
Future<void> ouvrirImportationWhatsApp(
  BuildContext context, {
  SelectionExportWhatsApp? selection,
  PartageRecu? partageInitial,
  Stream<PartageRecu>? partages,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => ImportationWhatsAppPage(
        selection: selection,
        partageInitial: partageInitial,
        partages: partages,
      ),
      transitionsBuilder: (_, animation, _, enfant) =>
          _transitionDouce(animation, enfant),
    ),
  );
}

Widget _transitionDouce(Animation<double> animation, Widget enfant) {
  final courbe = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: courbe,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).animate(courbe),
      child: enfant,
    ),
  );
}

/// Parcours d'import selon la plateforme.
enum ParcoursImport {
  /// Android : partage depuis WhatsApp d'abord, « Parcourir » ensuite.
  partageAndroid,

  /// Windows, navigateur, iOS : sélection d'un fichier (et dépôt).
  selection;

  static ParcoursImport get plateforme =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? partageAndroid
      : selection;
}

/// Import d'une conversation WhatsApp, sur une seule page : aucun fichier,
/// fichier reçu et lecture (automatique), conversation prête, erreur. Le
/// résumé est une vue facultative ; le filtrage (étape suivante) n'est
/// pas encore disponible.
class ImportationWhatsAppPage extends StatefulWidget {
  ImportationWhatsAppPage({
    super.key,
    SelectionExportWhatsApp? selection,
    this.partageInitial,
    this.partages,
    ParcoursImport? parcours,
    this.depot,
    this.creerLocal,
    IdentiteWhatsApp? identite,
    this.ouvrirWhatsApp,
  }) : selection = selection ?? SelectionExportWhatsApp(),
       parcours = parcours ?? ParcoursImport.plateforme,
       identite = identite ?? IdentiteWhatsApp();

  static const titre = 'Importer une conversation WhatsApp';
  static const whatsAppAbsent = 'WhatsApp n’est pas installé sur cet appareil.';

  /// Étapes de « Comment importer ? ».
  static const etapesAndroid = [
    'Dans WhatsApp, ouvrez la discussion, puis Menu › Plus › Exporter la '
        'discussion.',
    'Choisissez avec ou sans médias.',
    'Dans le menu de partage, choisissez JARVIS : la conversation est lue '
        'automatiquement.',
  ];
  static const etapesAutres = [
    'Dans WhatsApp sur votre téléphone, ouvrez la discussion, puis Menu › '
        'Plus › Exporter la discussion.',
    'Choisissez avec ou sans médias, puis enregistrez le fichier ou '
        'envoyez-le-vous.',
    'Ici, choisissez le fichier (ZIP ou TXT) : la conversation est lue '
        'automatiquement.',
  ];

  final SelectionExportWhatsApp selection;
  final PartageRecu? partageInitial;
  final Stream<PartageRecu>? partages;
  final ParcoursImport parcours;

  /// Glisser-déposer ; celui de la plateforme par défaut.
  final DepotFichiers? depot;

  /// Copie locale de l'export (tests : en mémoire).
  final Future<ExportLocal> Function()? creerLocal;

  final IdentiteWhatsApp identite;

  /// Ouvre WhatsApp (Android) ; celui du pont Android par défaut.
  final Future<bool> Function()? ouvrirWhatsApp;

  @override
  State<ImportationWhatsAppPage> createState() =>
      _ImportationWhatsAppPageState();
}

class _ImportationWhatsAppPageState extends State<ImportationWhatsAppPage> {
  ExportWhatsAppChoisi? _choisi;
  String? _erreur;
  bool _enCours = false;
  bool _survolDepot = false;

  /// Plusieurs fichiers reçus : l'utilisateur désigne l'export.
  List<FichierBrut>? _plusieurs;

  StreamSubscription<PartageRecu>? _abonnement;
  late final DepotFichiers _depot = widget.depot ?? DepotFichiers();

  // Chaque réception porte un numéro : seule la plus récente s'affiche.
  int _reception = 0;

  // --- Lecture -----------------------------------------------------------
  LecteurWhatsApp? _lecteur;
  Annulation? _annulation;
  EtatFichier _etat = const FichierNonLu();
  List<EntreeArchive>? _candidats;
  ConversationWhatsApp? _conversation;

  @override
  void initState() {
    super.initState();
    _abonnement = widget.partages?.listen(_recevoirPartage);
    if (widget.partageInitial case final p?) _recevoirPartage(p);
    if (_depot.disponible) {
      _depot.demarrer(
        surSurvol: (v) {
          if (mounted && v != _survolDepot) setState(() => _survolDepot = v);
        },
        surDepot: _recevoirFichiers,
      );
    }
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    if (_depot.disponible) _depot.arreter();
    _annulation?.annuler();
    _lecteur?.liberer();
    _choisi?.liberer();
    // Rien n'est enregistré : la conversation lue est oubliée.
    importWhatsAppEnCours.value = null;
    super.dispose();
  }

  // --- Réception -----------------------------------------------------------

  void _recevoirPartage(PartageRecu partage) {
    if (!mounted) return;
    if (partage.fichiers.isEmpty) {
      setState(() => _erreur = ErreurSelectionExport.aucunFichier.message);
      return;
    }
    _recevoirFichiers(partage.fichiers);
  }

  void _recevoirFichiers(List<FichierBrut> fichiers) {
    if (!mounted || fichiers.isEmpty) return;
    if (fichiers.length > 1) {
      _reception++;
      setState(() {
        _plusieurs = fichiers;
        _enCours = false;
        _erreur = null;
      });
      return;
    }
    _appliquer(widget.selection.verifier(fichiers.single));
  }

  void _choisirParmi(FichierBrut fichier) {
    setState(() => _plusieurs = null);
    _appliquer(widget.selection.verifier(fichier));
  }

  Future<void> _ouvrirSelecteur() async {
    if (_enCours) return;
    await _appliquer(widget.selection.choisir());
  }

  Future<void> _ouvrirWhatsApp() async {
    final ouvrir =
        widget.ouvrirWhatsApp ?? PontAndroidImportation.instance.ouvrirWhatsApp;
    final ouvert = await ouvrir();
    if (!ouvert && mounted) {
      setState(() => _erreur = ImportationWhatsAppPage.whatsAppAbsent);
    }
  }

  /// Même issue pour toutes les sources : fichier accepté (et sa lecture
  /// lancée aussitôt), refus expliqué (le fichier précédent reste), ou
  /// rien (annulation du sélecteur).
  Future<void> _appliquer(Future<ResultatSelectionExport> verification) async {
    final numero = ++_reception;
    setState(() => _enCours = true);
    final resultat = await verification;
    if (!mounted || numero != _reception) {
      if (resultat case SelectionReussie(:final export)) export.liberer();
      return;
    }
    setState(() {
      _enCours = false;
      switch (resultat) {
        case SelectionAnnulee():
          break;
        case SelectionRefusee(:final erreur):
          _erreur = erreur.message;
        case SelectionReussie(:final export):
          _arreterLecture();
          _choisi?.liberer();
          _choisi = export;
          _erreur = null;
          _plusieurs = null;
      }
    });
    // Lecture automatique, une seule fois par fichier accepté (jamais
    // depuis build).
    if (resultat is SelectionReussie) _lire();
  }

  void _retirer() {
    _arreterLecture();
    _choisi?.liberer();
    setState(() {
      _choisi = null;
      _erreur = null;
    });
  }

  // --- Lecture -----------------------------------------------------------

  /// Un autre fichier arrive (ou celui-ci est retiré) : la lecture en
  /// cours s'arrête et sa copie locale est effacée.
  void _arreterLecture() {
    _annulation?.annuler();
    _annulation = null;
    _lecteur?.liberer();
    _lecteur = null;
    _conversation = null;
    _candidats = null;
    _etat = const FichierNonLu();
    importWhatsAppEnCours.value = null;
  }

  Future<void> _lire({String? entree}) async {
    final export = _choisi;
    if (export == null || _annulation != null) return;
    final lecteur = _lecteur ??= LecteurWhatsApp(
      export,
      creerLocal: widget.creerLocal,
    );
    final annulation = _annulation = Annulation();
    setState(() {
      _erreur = null;
      _candidats = null;
      _etat = const FichierEnLecture(EtapeLecture.copie, null);
    });
    final resultat = await lecteur.lire(
      entreeChoisie: entree,
      annulation: annulation,
      progression: (etape, fraction) {
        if (!mounted || annulation.annulee) return;
        setState(() => _etat = FichierEnLecture(etape, fraction));
      },
    );
    // Lecture remplacée (autre fichier, retrait) : son résultat est ignoré.
    if (!mounted || !identical(_annulation, annulation)) return;
    _annulation = null;
    switch (resultat) {
      case LectureReussie(:final conversation):
        await widget.identite.charger();
        if (!mounted || !identical(_lecteur, lecteur)) return;
        // « Moi » déjà confirmé lors d'un import précédent : gardé pour
        // l'enregistrement (interface 3) ; le résumé ne s'en sert pas.
        importWhatsAppEnCours.value = ImportEnCours(
          conversation: conversation,
          moi: widget.identite.reconnaitre(conversation),
        );
        setState(() {
          _conversation = conversation;
          _etat = const FichierPret();
        });
      case ChoixFichierRequis(:final candidats):
        setState(() {
          _candidats = candidats;
          _etat = const FichierNonLu();
        });
      case LectureEchouee(:final erreur):
        setState(() {
          _erreur = erreur.message;
          _etat = const FichierNonLu();
        });
      case LectureAnnulee():
        setState(() => _etat = const FichierNonLu());
    }
  }

  void _annulerLecture() {
    _annulation?.annuler();
    _annulation = null;
    setState(() => _etat = const FichierNonLu());
  }

  /// Résumé facultatif ; au retour, tout est conservé.
  void _voirResume() {
    final conversation = _conversation;
    if (conversation == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            ResumeWhatsAppPage(conversation: conversation),
        transitionsBuilder: (_, animation, _, enfant) =>
            _transitionDouce(animation, enfant),
      ),
    );
  }

  void _retour() => Navigator.of(context).maybePop();

  // --- Affichage ---------------------------------------------------------

  Widget _contenu() {
    final choisi = _choisi;
    final plusieurs = _plusieurs;
    final candidats = _candidats;
    if (plusieurs != null) {
      return ChoixFichiersRecus(
        key: ObjectKey(plusieurs),
        fichiers: plusieurs,
        surChoix: _choisirParmi,
        surAnnuler: () => setState(() => _plusieurs = null),
      );
    }
    if (choisi != null && candidats != null) {
      return ChoixDansArchive(
        key: const ValueKey('archive'),
        candidats: candidats,
        surChoix: (e) => _lire(entree: e.nom),
      );
    }
    if (choisi != null) {
      return CarteExportChoisi(
        key: ObjectKey(choisi),
        fichier: choisi.fichier,
        etat: _etat,
        surChanger: _ouvrirSelecteur,
        surRetirer: _retirer,
        surAnnuler: _annulerLecture,
        surRelire: _lire,
        surResume: _voirResume,
      );
    }
    final android = widget.parcours == ParcoursImport.partageAndroid;
    return Column(
      key: const ValueKey('accueil'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteImporterWhatsApp(
          sousTitre: android
              ? CarteImporterWhatsApp.partager
              : _depot.disponible
              ? 'Choisissez ou déposez ici un export (ZIP, TXT).'
              : 'Choisissez un export (ZIP, TXT).',
          survolDepot: _survolDepot,
        ),
        // L'action principale, dans sa propre zone sous la carte.
        const SizedBox(height: 20),
        BoutonPrincipalImport(
          libelle: android
              ? CarteImporterWhatsApp.ouvrirWhatsApp
              : CarteParcourir.titre,
          icone: android
              ? Icons.open_in_new_rounded
              : Icons.folder_open_outlined,
          surAppui: android
              ? _ouvrirWhatsApp
              : _enCours
              ? null
              : _ouvrirSelecteur,
          enCours: !android && _enCours,
        ),
        if (android) ...[
          const SizedBox(height: 14),
          CarteParcourir(surAppui: _enCours ? null : _ouvrirSelecteur),
        ],
        const SizedBox(height: 14),
        BoutonCommentImporter(
          etapes: android
              ? ImportationWhatsAppPage.etapesAndroid
              : ImportationWhatsAppPage.etapesAutres,
        ),
      ],
    );
  }

  /// Fichier prêt : « Filtrer les messages » attend en bas de l'écran.
  bool get _actionFiltrerVisible =>
      _choisi != null &&
      _plusieurs == null &&
      _candidats == null &&
      _etat is FichierPret;

  /// Contenu de l'état courant, puis l'erreur éventuelle.
  Widget _centre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (enfant, animation) =>
                _transitionDouce(animation, enfant),
            // Pleine largeur (la mise en page par défaut centre et réduit
            // la zone à son contenu).
            layoutBuilder: (actuel, anciens) => Stack(
              fit: StackFit.passthrough,
              alignment: Alignment.center,
              children: [...anciens, ?actuel],
            ),
            child: _contenu(),
          ),
        ),
        if (_erreur case final erreur?) ...[
          const SizedBox(height: 14),
          BandeauAuth(message: erreur, type: TypeBandeau.erreur),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    final marge = taille.width < 600 ? 16.0 : 28.0;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _retour},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: CouleursJarvis.ivoire,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: degradeFondJarvis),
            child: SizedBox.expand(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, zone) => ScrollConfiguration(
                          behavior: const DefilementSansBarre(),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(marge, 8, marge, 8),
                            child: _Colonne(
                              // Au moins la hauteur visible : en-tête en
                              // haut, contenu centré verticalement (il
                              // défile s'il dépasse).
                              hauteurMin: zone.maxHeight - 16,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Entete(surRetour: _retour),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: _centre(),
                                  ),
                                  // Même hauteur que l'en-tête : le
                                  // contenu tombe au centre de l'écran.
                                  const SizedBox(height: _Entete.hauteur),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Zone d'action principale, hors du défilement : elle
                    // reste près du bas de l'écran sans recouvrir le contenu.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: _actionFiltrerVisible
                          ? SafeArea(
                              top: false,
                              minimum: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  marge,
                                  8,
                                  marge,
                                  4,
                                ),
                                // Branché à l'étape du filtrage.
                                child: const _Colonne(
                                  child: ActionFiltrer(surFiltrer: null),
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
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
}

/// Colonne centrée, 560 px au plus (ordinateur, tablette).
class _Colonne extends StatelessWidget {
  const _Colonne({required this.child, this.hauteurMin = 0});

  final Widget child;
  final double hauteurMin;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 560, minHeight: hauteurMin),
      child: child,
    ),
  );
}

class _Entete extends StatelessWidget {
  const _Entete({required this.surRetour});

  static const hauteur = 48.0;

  final VoidCallback surRetour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: surRetour,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: CouleursJarvis.texte,
            minimumSize: const Size(48, 48),
            side: BorderSide(
              color: CouleursJarvis.trait.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const LogoWhatsApp(taille: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            child: const Text(
              ImportationWhatsAppPage.titre,
              style: TextStyle(
                fontFamily: policeAffichage,
                fontSize: 19,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
