import 'dart:async';

import 'package:flutter/material.dart';

import '../models/importation/conversation_whatsapp.dart';
import '../services/api_jarvis.dart';
import '../services/importation/pieces_jointes_serveur.dart';
import '../theme/theme_jarvis.dart';
import '../utils/local_date_time.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/importation/apercu_discussion.dart';
import '../widgets/importation/lecture_whatsapp_widgets.dart';
import '../widgets/importation/logo_whatsapp.dart';

/// Résumé facultatif d'une conversation lue : son nom, son ampleur, puis
/// la discussion elle-même, présentée comme dans une messagerie (ouverte
/// sur les messages les plus récents). Aucun choix demandé ici : « Moi »
/// sera désigné à l'enregistrement. Revenir ne perd rien (la conversation
/// reste dans la page d'import).
class ResumeWhatsAppPage extends StatefulWidget {
  const ResumeWhatsAppPage({
    super.key,
    required this.conversation,
    this.titrePage = titre,
    this.moi,
  }) : chargeur = null,
       cible = null,
       nombre = null;

  /// « Voir les messages » ouvert SUR un message (référence d'une réponse
  /// de JARVIS) : seules les pages autour de lui sont lues ([chargeur]),
  /// il apparaît sans défilement manuel et s'éclaire un instant ; les
  /// messages précédents et suivants se chargent en faisant défiler.
  /// [conversation] ne sert qu'à l'en-tête (nom, participants, période).
  const ResumeWhatsAppPage.surMessage({
    super.key,
    required this.conversation,
    required ChargeurPagesWhatsApp this.chargeur,
    required int this.cible,
    this.titrePage = titre,
    this.moi,
    this.nombre,
  });

  /// Messages autour de la cible, lus avant l'affichage.
  static const fenetreAvant = 40;
  static const taillePage = 120;

  /// Durée de la mise en évidence du message visé.
  static const dureeSurbrillance = Duration(milliseconds: 2600);
  static const chargementImpossible = 'Impossible de charger ces messages.';

  /// Lecture d'une page (rangs [apres] + 1 à [apres] + [limite]).
  final ChargeurPagesWhatsApp? chargeur;

  /// Rang (0, 1, 2…) du message visé dans la pièce jointe.
  final int? cible;

  /// Nombre total de messages de la pièce jointe (en-tête), s'il est connu.
  final int? nombre;

  static const titre = 'Résumé de la conversation';
  static const mediasNonImportes = 'Médias non importés';
  static const datesIncertaines = 'jour et mois des dates incertains';

  final ConversationWhatsApp conversation;

  /// Petit titre au-dessus du nom (« Messages joints » pour une pièce
  /// jointe relue depuis le chat).
  final String titrePage;

  /// Utilisateur confirmé (pièce jointe) : ses messages à droite.
  final String? moi;

  /// « 172 messages · 3 juillet – 11 octobre 2026 ».
  static String ampleur(ConversationWhatsApp c, {int? nombre}) {
    final n = nombre ?? c.messages.length;
    final debut = c.debut, fin = c.fin;
    return [
      '${nombreEnFrancais(n)} message${n > 1 ? 's' : ''}',
      if (debut != null && fin != null) periode(debut, fin),
    ].join(' · ');
  }

  /// Période couverte : « 6 septembre 2026 », « 3 – 11 octobre 2026 »,
  /// « 3 juillet – 11 octobre 2026 », « 3 juillet 2020 – 11 octobre 2026 ».
  static String periode(DateTime debut, DateTime fin) {
    String jour(DateTime d) => d.day == 1 ? '1er' : '${d.day}';
    if (debut.year != fin.year) {
      return '${jourEnFrancais(debut)} – ${jourEnFrancais(fin)}';
    }
    if (debut.month != fin.month) {
      return '${jour(debut)} ${moisEnFrancais(debut)} – ${jourEnFrancais(fin)}';
    }
    if (debut.day != fin.day) return '${jour(debut)} – ${jourEnFrancais(fin)}';
    return jourEnFrancais(fin);
  }

  @override
  State<ResumeWhatsAppPage> createState() => _ResumeWhatsAppPageState();
}

/// Mode « ouvert sur un message » ([ResumeWhatsAppPage.surMessage]).
class _MessageVise extends StatefulWidget {
  const _MessageVise({required this.page});

  final ResumeWhatsAppPage page;

  @override
  State<_MessageVise> createState() => _MessageVisePageState();
}

/// Lit une page de messages d'une pièce jointe enregistrée.
typedef ChargeurPagesWhatsApp =
    Future<ResultatApi<PageWhatsApp>> Function(int apres, int limite);

/// Construit une bulle (message, médias groupés ou jour) avec la bonne
/// disposition.
Widget _elementApercu(ElementApercu e, DispositionAuteurs d) {
  switch (e) {
    case JourApercu(:final jour):
      return SeparateurJour(jour);
    case MessageApercu(:final message, :final debutSuite):
      return BulleApercu(
        message: message,
        cote: d.cote(message.auteur),
        debutSuite: debutSuite,
        // L'alignement ne dit pas qui est l'utilisateur : le nom est
        // donné en tête de chaque suite.
        auteur: debutSuite ? message.auteur : null,
        couleurAuteur: d.couleur(message.auteur),
      );
    case MediasApercu(:final medias, :final debutSuite):
      final auteur = medias.first.auteur;
      return BulleMediasGroupes(
        medias: medias,
        cote: d.cote(auteur),
        debutSuite: debutSuite,
        auteur: debutSuite ? auteur : null,
        couleurAuteur: d.couleur(auteur),
      );
  }
}

/// Fond et structure communs : en-tête, trait, puis la discussion.
class _CadreMessages extends StatelessWidget {
  const _CadreMessages({required this.entete, required this.discussion});

  final Widget entete;
  final Widget discussion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursJarvis.ivoire,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: degradeFondJarvis),
        child: SizedBox.expand(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                entete,
                Divider(
                  height: 1,
                  color: CouleursJarvis.trait.withValues(alpha: 0.6),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const DefilementSansBarre(),
                    child: discussion,
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

/// Marges latérales de la discussion (colonne de 640 px au plus).
double _coteDe(Size taille) {
  final marge = taille.width < 600 ? 12.0 : 28.0;
  return taille.width > 640 + 2 * marge ? (taille.width - 640) / 2 : marge;
}

class _MessageVisePageState extends State<_MessageVise> {
  final _cleCentre = GlobalKey();
  final _cleCible = GlobalKey();

  /// Messages lus, contigus : rangs [_premier] à _premier + length - 1.
  List<MessageWhatsApp> _messages = const [];
  int _premier = 0;
  bool _suite = false;
  MessageWhatsApp? _vise;

  List<ElementApercu> _avant = const [];
  List<ElementApercu> _apres = const [];
  late DispositionAuteurs _disposition;

  bool _chargement = true;
  bool _chargementAvant = false;
  bool _chargementApres = false;
  String? _erreur;
  bool _surbrillance = true;
  Timer? _finSurbrillance;

  @override
  void initState() {
    super.initState();
    _disposition = DispositionAuteurs(
      widget.page.conversation,
      moi: widget.page.moi,
    );
    _ouvrir();
  }

  @override
  void dispose() {
    _finSurbrillance?.cancel();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    final cible = widget.page.cible!;
    final apres = (cible - ResumeWhatsAppPage.fenetreAvant - 1).clamp(
      -1,
      cible - 1,
    );
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    final r = await widget.page.chargeur!(apres, ResumeWhatsAppPage.taillePage);
    if (!mounted) return;
    switch (r) {
      case EchecApi(:final type):
        setState(() {
          _chargement = false;
          _erreur = type.message;
        });
      case SuccesApi(:final valeur):
        final i = cible - valeur.premier;
        if (i < 0 || i >= valeur.messages.length) {
          setState(() {
            _chargement = false;
            _erreur = 'Ce message n’existe plus dans la pièce jointe.';
          });
          return;
        }
        _messages = valeur.messages;
        _premier = valeur.premier;
        _suite = valeur.suite;
        _vise = valeur.messages[i];
        _decouper();
        setState(() => _chargement = false);
        _finSurbrillance = Timer(ResumeWhatsAppPage.dureeSurbrillance, () {
          if (mounted) setState(() => _surbrillance = false);
        });
    }
  }

  /// Éléments de la discussion, coupés juste avant celui du message visé
  /// (centre du défilement : il apparaît sans calcul de position).
  void _decouper() {
    final elements = elementsApercu(_messages);
    final vise = _vise;
    var k = elements.indexWhere(
      (e) => switch (e) {
        MessageApercu(:final message) => identical(message, vise),
        MediasApercu(:final medias) => medias.any((m) => identical(m, vise)),
        JourApercu() => false,
      },
    );
    if (k < 0) {
      // Message masqué de l'aperçu (avis de chiffrement) : le suivant.
      final i = _messages.indexWhere((m) => identical(m, vise));
      k = elements.indexWhere(
        (e) => e is MessageApercu && _messages.indexOf(e.message) >= i,
      );
      if (k < 0) k = elements.length;
    }
    _avant = elements.sublist(0, k);
    _apres = elements.sublist(k);
  }

  bool _contientVise(ElementApercu e) => switch (e) {
    MessageApercu(:final message) => identical(message, _vise),
    MediasApercu(:final medias) => medias.any((m) => identical(m, _vise)),
    JourApercu() => false,
  };

  Future<void> _chargerAvant() async {
    if (_chargementAvant || _premier <= 0 || _chargement) return;
    _chargementAvant = true;
    final apres = (_premier - 1 - ResumeWhatsAppPage.taillePage).clamp(
      -1,
      _premier - 1,
    );
    final r = await widget.page.chargeur!(apres, _premier - apres - 1);
    _chargementAvant = false;
    if (!mounted) return;
    if (r case SuccesApi(:final valeur)
        when valeur.messages.isNotEmpty &&
            valeur.premier + valeur.messages.length == _premier) {
      setState(() {
        _messages = [...valeur.messages, ..._messages];
        _premier = valeur.premier;
        _decouper();
      });
    }
  }

  Future<void> _chargerApres() async {
    if (_chargementApres || !_suite || _chargement) return;
    _chargementApres = true;
    final dernier = _premier + _messages.length - 1;
    final r = await widget.page.chargeur!(
      dernier,
      ResumeWhatsAppPage.taillePage,
    );
    _chargementApres = false;
    if (!mounted) return;
    if (r case SuccesApi(:final valeur) when valeur.premier == dernier + 1) {
      setState(() {
        _messages = [..._messages, ...valeur.messages];
        _suite = valeur.suite;
        _decouper();
      });
    }
  }

  bool _surDefilement(ScrollNotification n) {
    final m = n.metrics;
    if (m.extentBefore < 900) _chargerAvant();
    if (m.extentAfter < 900) _chargerApres();
    return false;
  }

  Widget _element(ElementApercu e) {
    final bulle = _elementApercu(e, _disposition);
    if (!_contientVise(e)) return bulle;
    return Semantics(
      label: 'Message cité par JARVIS',
      child: AnimatedContainer(
        key: _cleCible,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: CouleursJarvis.lavande.withValues(
            alpha: _surbrillance ? 0.55 : 0,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: bulle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.page.conversation;
    final cote = _coteDe(MediaQuery.sizeOf(context));
    final bas = 12 + MediaQuery.viewPaddingOf(context).bottom;
    final Widget discussion;
    if (_chargement) {
      discussion = const Center(
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    } else if (_erreur case final erreur?) {
      discussion = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${ResumeWhatsAppPage.chargementImpossible} $erreur',
                textAlign: TextAlign.center,
                style: const TextStyle(color: CouleursJarvis.texteSecondaire),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _ouvrir, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    } else {
      final avant = _avant;
      discussion = NotificationListener<ScrollNotification>(
        onNotification: _surDefilement,
        child: CustomScrollView(
          center: _cleCentre,
          // Le message visé apparaît au premier quart de l'écran, avec
          // ce qui le précède juste au-dessus.
          anchor: 0.22,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(cote, 8, cote, 0),
              sliver: SliverList.builder(
                itemCount: avant.length,
                // Avant le centre, les éléments montent : le plus proche
                // du message visé d'abord.
                itemBuilder: (context, i) =>
                    _element(avant[avant.length - 1 - i]),
              ),
            ),
            SliverPadding(
              key: _cleCentre,
              padding: EdgeInsets.fromLTRB(cote, 0, cote, bas),
              sliver: SliverList.builder(
                itemCount: _apres.length,
                itemBuilder: (context, i) => _element(_apres[i]),
              ),
            ),
          ],
        ),
      );
    }
    final secondaires = [
      if (c.dateIncertaine) ResumeWhatsAppPage.datesIncertaines,
    ];
    return _CadreMessages(
      entete: Padding(
        padding: EdgeInsets.fromLTRB(cote, 6, cote, 10),
        child: _Entete(
          titre: widget.page.titrePage,
          nom: c.titre,
          ampleur: ResumeWhatsAppPage.ampleur(c, nombre: widget.page.nombre),
          secondaire: secondaires.join(' · '),
        ),
      ),
      discussion: discussion,
    );
  }
}

class _ResumeWhatsAppPageState extends State<ResumeWhatsAppPage> {
  // Préparés une fois (parcours linéaire) ; seules les bulles visibles
  // sont construites.
  late final List<ElementApercu> _elements = elementsApercu(
    widget.conversation.messages,
  );
  late final DispositionAuteurs _disposition = DispositionAuteurs(
    widget.conversation,
    moi: widget.moi,
  );

  Widget _element(ElementApercu e) => _elementApercu(e, _disposition);

  @override
  Widget build(BuildContext context) {
    if (widget.chargeur != null) return _MessageVise(page: widget);
    final c = widget.conversation;
    final taille = MediaQuery.sizeOf(context);
    final marge = taille.width < 600 ? 12.0 : 28.0;
    final cote = taille.width > 640 + 2 * marge
        ? (taille.width - 640) / 2
        : marge;
    final secondaires = [
      if (c.nombreMedias > 0) ResumeWhatsAppPage.mediasNonImportes,
      if (c.dateIncertaine) ResumeWhatsAppPage.datesIncertaines,
    ];
    final n = _elements.length;
    return Scaffold(
      backgroundColor: CouleursJarvis.ivoire,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: degradeFondJarvis),
        child: SizedBox.expand(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(cote, 6, cote, 10),
                  child: _Entete(
                    titre: widget.titrePage,
                    nom: c.titre,
                    ampleur: ResumeWhatsAppPage.ampleur(c),
                    secondaire: secondaires.join(' · '),
                  ),
                ),
                Divider(
                  height: 1,
                  color: CouleursJarvis.trait.withValues(alpha: 0.6),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const DefilementSansBarre(),
                    // Inversée : ouverte sur les messages les plus récents,
                    // et virtualisée (seules les bulles visibles existent).
                    child: CustomScrollView(
                      reverse: true,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            cote,
                            8,
                            cote,
                            12 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          sliver: SliverList.builder(
                            itemCount: n,
                            itemBuilder: (context, i) =>
                                _element(_elements[n - 1 - i]),
                          ),
                        ),
                      ],
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

/// Retour, puis le nom de la conversation et une ligne d'informations.
class _Entete extends StatelessWidget {
  const _Entete({
    required this.titre,
    required this.nom,
    required this.ampleur,
    required this.secondaire,
  });

  final String titre;
  final String nom;
  final String ampleur;
  final String secondaire;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: CouleursJarvis.texte,
            minimumSize: const Size(48, 48),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const LogoWhatsApp(taille: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: CouleursJarvis.texteSecondaire,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: policeAffichage,
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: CouleursJarvis.texte,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ampleur,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: CouleursJarvis.texte,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (secondaire.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaire,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
