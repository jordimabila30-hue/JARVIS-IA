import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/importation/propositions_reponse.dart';
import '../../theme/theme_jarvis.dart';
import 'selecteurs_reponse.dart';

/// Ton et longueur affichés (mémorisés par la session).
typedef SurReglagePropositions =
    void Function(String ton, LongueurProposition? longueur);

/// Aide à répondre ou à relancer, sous une réponse de JARVIS : capsules de
/// ton et de longueur, puis les trois propositions de la combinaison
/// choisie, chacune avec « Copier ».
///
/// Toutes les combinaisons sont déjà là (reçues d'un coup) : changer de ton
/// ou de longueur ne fait qu'afficher d'autres propositions, sans réseau ni
/// IA. Une fois une proposition déclarée envoyée (appui long, confirmé par
/// le serveur), la carte se TRANSFORME en une bulle compacte du texte
/// retenu, avec un menu `···` (Copier, Annuler le choix) : même message,
/// rien de dupliqué. Rien n'est envoyé à WhatsApp.
class PropositionsJarvis extends StatefulWidget {
  const PropositionsJarvis({
    super.key,
    required this.propositions,
    this.surTon,
    this.surStatut,
    this.tonInitial,
    this.longueurInitiale,
    this.contact,
    this.surReprendre,
    this.repriseEnCours = false,
    this.taille = 15,
  });

  final PropositionsReponse propositions;

  /// Génération incomplète : « Reprendre » (seulement ce qui manque).
  final Future<bool> Function()? surReprendre;
  final bool repriseEnCours;

  /// Ton et longueur affichés (au choix de l'utilisateur), pour « pourquoi
  /// la deuxième ? » et pour les retrouver après un défilement.
  final SurReglagePropositions? surTon;

  /// Appui long sur une réponse : déclarée envoyée (ou annulée).
  final SurStatutProposition? surStatut;

  /// Réglages à afficher d'emblée (mémorisés par la session) : la carte,
  /// recréée par la liste après un défilement, les garde.
  final String? tonInitial;
  final LongueurProposition? longueurInitiale;

  /// Destinataire (bulle du choix : « Vous → Lina Moreau »).
  final String? contact;
  final double taille;

  @override
  State<PropositionsJarvis> createState() => _PropositionsJarvisState();
}

/// État discret d'une génération interrompue : rien d'affiché à moitié,
/// « Reprendre » complète ce qui manque (même ensemble).
class GenerationIncomplete extends StatelessWidget {
  const GenerationIncomplete({
    super.key,
    this.raison,
    this.enCours = false,
    this.surReprendre,
  });

  final String? raison;
  final bool enCours;
  final Future<bool> Function()? surReprendre;

  @override
  Widget build(BuildContext context) {
    final detail = switch (raison) {
      'quota' => 'Limite du service IA atteinte.',
      _ => 'Propositions pas encore prêtes.',
    };
    return Row(
      children: [
        Icon(
          Icons.hourglass_bottom_rounded,
          size: 16,
          color: CouleursJarvis.texteSecondaire,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Génération incomplète',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' · $detail'),
              ],
            ),
            style: TextStyle(
              fontSize: 13,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
        if (enCours)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (surReprendre != null)
          TextButton(
            key: const Key('reprendre-propositions'),
            onPressed: () => unawaited(surReprendre!()),
            child: const Text('Reprendre'),
          ),
      ],
    );
  }
}

class _PropositionsJarvisState extends State<PropositionsJarvis> {
  late int _choisi = _indexDe(widget.tonInitial);
  late LongueurProposition? _longueur =
      widget.propositions.longueurs.contains(widget.longueurInitiale)
      ? widget.longueurInitiale
      : widget.propositions.longueurParDefaut;

  int _indexDe(String? nom) {
    final i = widget.propositions.tons.indexWhere((t) => t.nom == nom);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(PropositionsJarvis ancien) {
    super.didUpdateWidget(ancien);
    if (_choisi >= widget.propositions.tons.length) _choisi = 0;
    // Choix annulé : retour au ton et à la longueur de la réponse retenue.
    final avant = ancien.propositions.choisie;
    // Carte → bulle (ou retour aux propositions) : la taille change
    // beaucoup ; le bas de la carte doit rester visible au-dessus de la
    // barre (vu sur le S10+ : bulle à moitié cachée après un Long).
    if ((avant == null) != (widget.propositions.choisie == null)) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 260), _rendreVisible),
      );
    }
    if (avant != null && widget.propositions.choisie == null) {
      final ton = widget.propositions.tonDe(avant);
      if (ton != null) _choisi = widget.propositions.tons.indexOf(ton);
      if (avant.longueur != null) _longueur = avant.longueur;
    }
  }

  void _regler({int? ton, LongueurProposition? longueur}) {
    final haut = _haut();
    setState(() {
      if (ton != null) _choisi = ton;
      if (longueur != null) _longueur = longueur;
    });
    widget.surTon?.call(widget.propositions.tons[_choisi].nom, _longueur);
    if (haut != null) _garderEnPlace(haut, DateTime.now());
  }

  /// Fait défiler juste assez pour que le bas de la carte soit dans le fil
  /// (marge pour le fondu du bas), sans jamais la faire sauter ailleurs.
  void _rendreVisible() {
    if (!mounted) return;
    final position = Scrollable.maybeOf(context)?.position;
    final boite = context.findRenderObject();
    final fenetre = position?.context.storageContext.findRenderObject();
    if (position == null ||
        boite is! RenderBox ||
        fenetre is! RenderBox ||
        !boite.attached ||
        !fenetre.attached) {
      return;
    }
    const marge = 48.0;
    final bas = boite.localToGlobal(Offset(0, boite.size.height)).dy;
    final limite =
        fenetre.localToGlobal(Offset(0, fenetre.size.height)).dy - marge;
    final depasse = bas - limite;
    if (depasse <= 0) return;
    // Liste inversée : défiler « en arrière » remonte le contenu.
    final sens = position.axisDirection == AxisDirection.up ? -1.0 : 1.0;
    unawaited(
      position.animateTo(
        (position.pixels + depasse * sens).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Position verticale (écran) du haut de la carte.
  double? _haut() {
    final boite = context.findRenderObject();
    if (boite is! RenderBox || !boite.attached || !boite.hasSize) return null;
    return boite.localToGlobal(Offset.zero).dy;
  }

  /// Le fil est une liste inversée, ancrée en bas : une carte qui grandit
  /// (Court → Long) pousserait ses capsules vers le haut, hors du doigt,
  /// voire hors de l'écran. À chaque image de l'animation de taille, le
  /// défilement est corrigé pour que le haut de la carte reste à [haut].
  void _garderEnPlace(double haut, DateTime debut) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position = Scrollable.maybeOf(context)?.position;
      final maintenant = _haut();
      if (position == null || maintenant == null) return;
      final ecart = haut - maintenant;
      if (ecart.abs() > 0.5) {
        // Liste inversée (axe vers le haut) : défiler « en avant » descend
        // le contenu à l'écran.
        final sens = position.axisDirection == AxisDirection.up ? 1.0 : -1.0;
        position.jumpTo(
          (position.pixels + ecart * sens).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      if (DateTime.now().difference(debut) <
          const Duration(milliseconds: 400)) {
        WidgetsBinding.instance.scheduleFrame();
        _garderEnPlace(haut, debut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.propositions;
    final choisie = p.choisie;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: p.incomplet
            ? GenerationIncomplete(
                key: const ValueKey('incomplet'),
                raison: p.raison,
                enCours: widget.repriseEnCours,
                surReprendre: widget.surReprendre,
              )
            : choisie != null
            ? BulleReponseChoisie(
                key: ValueKey('choisie-${choisie.id}'),
                proposition: choisie,
                contact: widget.contact,
                surAnnuler: widget.surStatut == null
                    ? null
                    : () => widget.surStatut!(choisie, false),
                taille: widget.taille,
              )
            : _choix(p),
      ),
    );
  }

  Widget _choix(PropositionsReponse p) {
    final ton = p.tons[_choisi];
    final trois = p.affichees(ton, _longueur);
    return Column(
      key: const ValueKey('choix'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, size: 14, color: CouleursJarvis.violet),
            const SizedBox(width: 6),
            Text(p.mode.titre, style: _styleTitre),
          ],
        ),
        const SizedBox(height: 8),
        // Ton ▾ / Longueur ▾ : composant partagé (toutes les idées de réponse).
        SelecteursReponse(
          tons: [for (final t in p.tons) t.nom],
          ton: _choisi,
          surTon: (i) => _regler(ton: i),
          longueurs: [for (final l in p.longueurs) l.libelle],
          longueur: _longueur == null ? null : p.longueurs.indexOf(_longueur!),
          surLongueur: (i) => _regler(longueur: p.longueurs[i]),
        ),
        const SizedBox(height: 10),
        // Même emplacement, même taille de cadre : seuls les textes changent.
        Column(
          key: ValueKey('${ton.nom}-${_longueur?.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, prop) in trois.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              CarteProposition(
                key: Key('proposition-${ton.nom}-$i'),
                numero: i + 1,
                proposition: prop,
                ton: ton.nom,
                surStatut: widget.surStatut,
                taille: widget.taille,
              ),
            ],
          ],
        ),
        if (p.incomplets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${p.incomplets.join(', ')} : propositions incomplètes, non affichées.',
              style: TextStyle(
                fontSize: 11.5,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ),
      ],
    );
  }

  static TextStyle get _styleTitre => TextStyle(
    fontSize: 12,
    letterSpacing: 0.3,
    color: CouleursJarvis.texteSecondaire,
  );
}

/// La réponse retenue (déclarée envoyée) : une bulle compacte, comme un
/// message envoyé, et un menu `···` (Copier, Annuler le choix, date de la
/// déclaration). Aucun autre bouton, aucun texte explicatif.
class BulleReponseChoisie extends StatelessWidget {
  const BulleReponseChoisie({
    super.key,
    required this.proposition,
    this.contact,
    this.surAnnuler,
    this.taille = 15,
  });

  final PropositionReponse proposition;
  final String? contact;
  final Future<bool> Function()? surAnnuler;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = proposition;
    final date = p.envoyee;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          key: const Key('reponse-choisie'),
          padding: const EdgeInsets.fromLTRB(14, 8, 2, 8),
          decoration: BoxDecoration(
            color: CouleursJarvis.violetPoudre,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(
              color: CouleursJarvis.lavande.withValues(alpha: 0.9),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (contact != null)
                      Text(
                        'Vous → $contact',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                    Text(
                      p.texte,
                      style: TextStyle(
                        fontSize: taille - 0.5,
                        height: 1.45,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: const Key('menu-reponse-choisie'),
                tooltip: 'Options',
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: CouleursJarvis.texteSecondaire,
                ),
                color: CouleursJarvis.coque,
                onSelected: (v) async {
                  if (v == 'copier') {
                    await Clipboard.setData(ClipboardData(text: p.texte));
                  } else if (v == 'annuler') {
                    await surAnnuler?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'copier', child: Text('Copier')),
                  if (surAnnuler != null)
                    const PopupMenuItem(
                      value: 'annuler',
                      child: Text('Annuler le choix'),
                    ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      date == null
                          ? 'Déclarée envoyée'
                          : 'Déclarée envoyée le ${_date(date)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CouleursJarvis.texteSecondaire,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      'à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Déclare (vrai) ou annule (faux) l'envoi d'une proposition ; vrai quand
/// le serveur l'a enregistré.
typedef SurStatutProposition =
    Future<bool> Function(PropositionReponse proposition, bool envoyee);

/// Une proposition : son approche, le texte à envoyer, « Copier ».
///
/// Phase 4 : un appui long (~800 ms, barre de progression discrète) sur la
/// carte DÉCLARE la réponse envoyée ; relâcher trop tôt ou faire défiler
/// annule. Souris et clavier : bouton « Marquer envoyée » (Web, ordinateur).
/// « Envoyée » n'apparaît qu'après confirmation du serveur ; « Annuler »
/// revient en arrière. Rien n'est envoyé à WhatsApp.
class CarteProposition extends StatefulWidget {
  const CarteProposition({
    super.key,
    required this.numero,
    required this.proposition,
    this.ton,
    this.surStatut,
    this.taille = 15,
  });

  final int numero;
  final PropositionReponse proposition;

  /// Nom du ton : une « approche » qui le répète n'est pas affichée.
  final String? ton;
  final SurStatutProposition? surStatut;
  final double taille;

  static const dureeAppui = Duration(milliseconds: 800);

  /// Déplacement au-delà duquel l'appui devient un défilement (annulé).
  static const toleranceAppui = 12.0;

  @override
  State<CarteProposition> createState() => _CartePropositionState();
}

class _CartePropositionState extends State<CarteProposition>
    with SingleTickerProviderStateMixin {
  bool _copie = false;
  bool _enregistrement = false;
  bool _echec = false;
  Timer? _retour;
  Offset? _depart;
  late final _appui = AnimationController(
    vsync: this,
    duration: CarteProposition.dureeAppui,
  )..addStatusListener(_finAppui);

  bool get _envoyee => widget.proposition.envoyee != null;

  bool get _declarable =>
      widget.surStatut != null &&
      widget.proposition.id.isNotEmpty &&
      !_envoyee &&
      !_enregistrement;

  /// Souris et clavier (Web, Windows…) : bouton visible en plus de l'appui.
  bool get _boutonVisible =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.proposition.texte));
    if (!mounted) return;
    setState(() => _copie = true);
    _retour?.cancel();
    _retour = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copie = false);
    });
  }

  void _debutAppui(PointerDownEvent e) {
    if (!_declarable) return;
    _depart = e.position;
    _appui.forward(from: 0);
  }

  void _deplacement(PointerMoveEvent e) {
    final depart = _depart;
    if (depart != null &&
        (e.position - depart).distance > CarteProposition.toleranceAppui) {
      _annulerAppui();
    }
  }

  void _annulerAppui() {
    _depart = null;
    if (_appui.status != AnimationStatus.completed) _appui.reset();
  }

  void _finAppui(AnimationStatus s) {
    if (s != AnimationStatus.completed || _depart == null) return;
    _depart = null;
    HapticFeedback.mediumImpact();
    _changer(true);
  }

  Future<void> _changer(bool envoyee) async {
    final surStatut = widget.surStatut;
    if (surStatut == null || _enregistrement) return;
    setState(() {
      _enregistrement = true;
      _echec = false;
    });
    final ok = await surStatut(widget.proposition, envoyee);
    if (!mounted) return;
    _appui.reset();
    setState(() {
      _enregistrement = false;
      _echec = !ok;
    });
  }

  @override
  void dispose() {
    _retour?.cancel();
    _appui.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposition;
    final approche = p.approche?.toLowerCase() == widget.ton?.toLowerCase()
        ? null
        : p.approche;
    final carte = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 2),
      decoration: BoxDecoration(
        color: _envoyee
            ? CouleursJarvis.violetPoudre.withValues(alpha: 0.55)
            : CouleursJarvis.coque.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _envoyee
              ? CouleursJarvis.violet.withValues(alpha: 0.55)
              : CouleursJarvis.lavande.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${widget.numero}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: CouleursJarvis.violet,
                    ),
                  ),
                  if (approche != null) TextSpan(text: '  ·  $approche'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: CouleursJarvis.texteSecondaire,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            // Texte simple (pas sélectionnable) : l'appui long est réservé
            // à la déclaration ; « Copier » reste là.
            child: Text(
              p.texte,
              style: TextStyle(
                fontSize: widget.taille - 0.5,
                height: 1.45,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
          // Progression discrète de l'appui long.
          AnimatedBuilder(
            animation: _appui,
            builder: (context, _) => _appui.value == 0
                ? const SizedBox(height: 6)
                : Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        key: const Key('progression-appui'),
                        value: _appui.value,
                        minHeight: 2,
                        color: CouleursJarvis.violet,
                        backgroundColor: CouleursJarvis.lavande.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_envoyee) ...[
                const _Envoyee(),
                TextButton(
                  key: Key('annuler-envoyee-${widget.numero}'),
                  onPressed: _enregistrement ? null : () => _changer(false),
                  style: _styleBouton,
                  child: const Text('Annuler'),
                ),
              ] else if (_boutonVisible && _declarable)
                TextButton.icon(
                  key: Key('marquer-envoyee-${widget.numero}'),
                  onPressed: () => _changer(true),
                  icon: const Icon(Icons.done_rounded, size: 15),
                  label: const Text('Marquer envoyée'),
                  style: _styleBouton,
                ),
              if (_enregistrement)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: CouleursJarvis.violet,
                    ),
                  ),
                ),
              if (_echec)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Text(
                    'Non enregistrée, réessayez',
                    style: TextStyle(
                      fontSize: 12,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
              TextButton.icon(
                key: Key('copier-proposition-${widget.numero}'),
                onPressed: _copier,
                icon: Icon(
                  _copie ? Icons.check_rounded : Icons.content_copy_rounded,
                  size: 15,
                ),
                label: Text(_copie ? 'Copié' : 'Copier'),
                style: _styleBouton,
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      onLongPressHint: _declarable ? 'marquer comme envoyée' : null,
      onLongPress: _declarable ? () => _changer(true) : null,
      child: Listener(
        onPointerDown: _debutAppui,
        onPointerMove: _deplacement,
        onPointerUp: (_) => _annulerAppui(),
        onPointerCancel: (_) => _annulerAppui(),
        // Le fil est sélectionnable (SelectionArea de la page) : sans cela,
        // l'appui long sélectionnait aussi le texte (vu sur Galaxy S10+).
        // Le récepteur d'appui long de la carte gagne l'arbitrage des gestes
        // (la progression reste pilotée par le Listener ci-dessus).
        child: GestureDetector(
          onLongPress: () {},
          excludeFromSemantics: true,
          child: SelectionContainer.disabled(child: carte),
        ),
      ),
    );
  }

  static ButtonStyle get _styleBouton => TextButton.styleFrom(
    foregroundColor: CouleursJarvis.signal,
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
  );
}

/// « ✓ Envoyée » : déclaration de l'utilisateur, confirmée par le serveur
/// (jamais présentée comme une livraison WhatsApp).
class _Envoyee extends StatelessWidget {
  const _Envoyee();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Vous avez indiqué l’avoir envoyée (non vérifié dans WhatsApp)',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 15, color: CouleursJarvis.violet),
            SizedBox(width: 4),
            Text(
              'Envoyée',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CouleursJarvis.violet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
