import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/applications_externes.dart';
import '../theme/theme_jarvis.dart';
import 'feuille_ajout.dart';
import 'importation/logo_whatsapp.dart';
import 'bouton_vocal.dart';

/// Mesures de la barre de saisie (toutes réglables ici).
class MesuresBarre {
  MesuresBarre._();

  /// Hauteur de la capsule au repos (bordure comprise), ordinateur et
  /// téléphone.
  static const hauteur = 60.0;
  static const hauteurCompacte = 54.0;

  /// Espace entre le bord de la capsule et les boutons.
  static const marge = 7.0;

  /// Texte saisi et invite : même taille et même interligne, pour qu'ils
  /// occupent exactement la même place.
  static const tailleTexte = 16.0;
  static const tailleTexteCompacte = 15.0;
  static const interligne = 1.375;

  /// Correction optique (px) : les minuscules (la majorité du texte) ont
  /// leur centre visuel un peu sous le centre de la ligne ; on remonte le
  /// texte d’un pixel : majuscules et minuscules s’équilibrent autour du
  /// centre (mesuré au rendu).
  static const decalageOptique = 1.0;

  /// Bouton vocal : largeur (sa hauteur suit celle de la capsule).
  static const largeurBoutonVocal = 60.0;
  static const largeurBoutonVocalCompacte = 54.0;

  /// Bouton « + » : diamètre.
  static const tailleBoutonPlus = 40.0;

  /// Séparateur discret entre « + » et le champ (barre au repos) : marges
  /// comprises.
  static const margeAvantSeparateur = 8.0;
  static const margeApresSeparateur = 14.0;

  /// Écart entre le champ et la capsule vocale (barre au repos).
  static const ecartVocal = 10.0;

  /// Barre dépliée : lignes de texte avant le défilement interne, marge du
  /// texte à gauche et à droite, écart entre le texte et les boutons.
  static const lignesMax = 4;
  static const margeTexteDeplie = 10.0;
  static const ecartBoutons = 6.0;

  /// Haut-parleur (lecture vocale) : diamètre, comme « + ».
  static const tailleHautParleur = 40.0;

  /// Dépliage (focus ou texte) et retour au repos.
  static const dureeDepliage = Duration(milliseconds: 230);
  static const dureeRepli = Duration(milliseconds: 300);
}

/// Barre de saisie de JARVIS : grande capsule claire avec le bouton « + »
/// (ajouter du contenu), le champ texte et la capsule vocale sombre.
///
/// Trois états, déduits du focus et du texte :
/// - repos (champ vide, sans focus) : une seule ligne, « + », séparateur,
///   champ, capsule vocale ;
/// - focus (champ vide, curseur présent) et saisie (texte présent, avec ou
///   sans focus) : la barre se déplie vers le haut. Le texte occupe la zone
///   supérieure sur toute la largeur (jusqu'à [MesuresBarre.lignesMax]
///   lignes, puis défilement interne) ; « + » et la capsule restent sur la
///   ligne du bas.
///
/// Les boutons ne bougent jamais : ils sont ancrés aux coins bas de la
/// capsule. Le dépliage élargit le champ et ouvre un espace sous lui : le
/// bas de la barre reste stable et le champ n'est jamais recréé (focus,
/// texte et sélection conservés).
///
/// La capsule vocale ouvre le chat vocal ; dès qu'un texte est saisi, elle
/// devient le bouton d'envoi (même place, même forme).
class LigneDeCommande extends StatefulWidget {
  const LigneDeCommande({
    super.key,
    required this.controleur,
    required this.focus,
    required this.onEnvoyer,
    required this.onChatVocal,
    this.compacte = false,
    this.chatVocalReprenable = false,
    this.lectureVocale,
    this.surLecture,
    this.surImporterWhatsApp,
    this.surAjouterMessageWhatsApp,
    this.pieceJointe,
  });

  final TextEditingController controleur;
  final FocusNode focus;
  final ValueChanged<String> onEnvoyer;
  final VoidCallback onChatVocal;

  /// Téléphone : barre un peu moins haute, invite plus courte.
  final bool compacte;

  /// Un chat vocal est en arrière-plan : la capsule vocale devient
  /// bleu-violet (même pendant la saisie) et le bouton le reprend.
  final bool chatVocalReprenable;

  /// Lecture vocale des réponses écrites : haut-parleur juste à gauche de
  /// la capsule vocale (activé ou non) ; null : pas de haut-parleur.
  final bool? lectureVocale;
  final VoidCallback? surLecture;

  /// « + » → « Importer une conversation » (export WhatsApp) ; null :
  /// l'entrée est indisponible.
  final VoidCallback? surImporterWhatsApp;

  /// Phase 5 : « Ajouter une réponse reçue » (actualiser un contexte
  /// WhatsApp par copier-coller) ; null : indisponible (sans compte).
  final VoidCallback? surAjouterMessageWhatsApp;

  /// Pièce jointe en attente d'envoi, posée au-dessus du texte dans la
  /// barre (dépliée tant qu'elle est là). Null : aucune.
  final Widget? pieceJointe;

  /// Invite quand une pièce jointe attend sa consigne.
  static const inviteConsigne = 'Écrivez votre consigne à JARVIS…';

  /// Invite : la mission de JARVIS (comprendre une conversation, aider à
  /// répondre).
  static const invite = 'Collez une conversation ou demandez conseil à JARVIS…';

  /// Sur téléphone, la place ne permet qu'une invite courte ; la phrase de
  /// mission, juste au-dessus, rappelle déjà le conseil.
  static const inviteCourte = 'Collez une conversation…';

  /// Message discret quand il n'y a rien à coller.
  static const pressePapiersVide = 'Le presse-papiers est vide.';

  @override
  State<LigneDeCommande> createState() => _LigneDeCommandeState();
}

class _LigneDeCommandeState extends State<LigneDeCommande>
    with SingleTickerProviderStateMixin {
  late final _depliage = AnimationController(
    vsync: this,
    duration: MesuresBarre.dureeDepliage,
    reverseDuration: MesuresBarre.dureeRepli,
    value: _depliee ? 1 : 0,
  );
  late final _courbe = CurvedAnimation(
    parent: _depliage,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  /// Dépliée dès que le champ a le focus ou contient du texte ; au repos
  /// seulement s'il est vide et sans focus.
  bool get _depliee =>
      widget.focus.hasFocus ||
      widget.controleur.text.isNotEmpty ||
      widget.pieceJointe != null;

  /// Barre dépliée ou en train de se déplier (pour les tests).
  @visibleForTesting
  bool get depliee =>
      _depliage.status == AnimationStatus.forward ||
      _depliage.status == AnimationStatus.completed;

  bool _focusConnu = false;

  @override
  void initState() {
    super.initState();
    _focusConnu = widget.focus.hasFocus;
    widget.focus.addListener(_surFocus);
    widget.controleur.addListener(_suivre);
  }

  @override
  void didUpdateWidget(LigneDeCommande ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.focus != widget.focus) {
      ancien.focus.removeListener(_surFocus);
      widget.focus.addListener(_surFocus);
    }
    if (ancien.controleur != widget.controleur) {
      ancien.controleur.removeListener(_suivre);
      widget.controleur.addListener(_suivre);
    }
    _suivre();
  }

  @override
  void dispose() {
    widget.focus.removeListener(_surFocus);
    widget.controleur.removeListener(_suivre);
    _courbe.dispose();
    _depliage.dispose();
    super.dispose();
  }

  void _surFocus() {
    // Le style de la capsule (bordure, lueur) suit le focus.
    if (widget.focus.hasFocus != _focusConnu) {
      _focusConnu = widget.focus.hasFocus;
      setState(() {});
    }
    _suivre();
  }

  /// Déplie ou replie si l'état change. Pas de reconstruction de la barre :
  /// seule l'animation avance.
  void _suivre() {
    if (_depliee != depliee) {
      _depliee ? _depliage.forward() : _depliage.reverse();
    }
  }

  void _envoyer() {
    final texte = widget.controleur.text.trim();
    if (texte.isNotEmpty) widget.onEnvoyer(texte);
  }

  /// Colle le texte du presse-papiers à la position du curseur, puis rend
  /// le focus au champ (le clavier reste utilisable).
  Future<void> _coller() async {
    final donnees = await Clipboard.getData(Clipboard.kTextPlain);
    final texte = donnees?.text;
    if (!mounted) return;
    if (texte == null || texte.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              LigneDeCommande.pressePapiersVide,
              style: TextStyle(fontSize: 13.5, color: CouleursJarvis.ivoire),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: CouleursJarvis.texte.withValues(alpha: 0.92),
            elevation: 0,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      widget.focus.requestFocus();
      return;
    }
    final c = widget.controleur;
    final sel = c.selection.isValid
        ? c.selection
        : TextSelection.collapsed(offset: c.text.length);
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, texte),
      selection: TextSelection.collapsed(offset: sel.start + texte.length),
    );
    widget.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focus.hasFocus;
    final compacte = widget.compacte;
    final hauteur = compacte
        ? MesuresBarre.hauteurCompacte
        : MesuresBarre.hauteur;
    // Hauteur intérieure (bordure de 1 px et marges retirées) : c'est la
    // ligne sur laquelle se centrent les boutons et le texte au repos.
    const marge = MesuresBarre.marge;
    final interieur = hauteur - 2 - 2 * marge;
    final taille = compacte
        ? MesuresBarre.tailleTexteCompacte
        : MesuresBarre.tailleTexte;
    // Hauteur de ligne arrondie au pixel : le moteur l'arrondit de toute
    // façon, autant en tenir compte pour un centrage exact.
    final ligne = (taille * MesuresBarre.interligne).roundToDouble();
    final interligne = ligne / taille;
    final vide = (interieur - ligne) / 2;
    // Interligne réparti également au-dessus et au-dessous des lettres
    // (par défaut, Flutter en met davantage sous la ligne de base, ce qui
    // fait paraître le texte trop bas).
    final texte = TextStyle(
      fontSize: taille,
      height: interligne,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final largeurVocal = compacte
        ? MesuresBarre.largeurBoutonVocalCompacte
        : MesuresBarre.largeurBoutonVocal;

    // Construits une fois par build : pendant le dépliage, seules leurs
    // positions changent (le champ n'est jamais reconstruit ni recréé).
    final champ = TextField(
      controller: widget.controleur,
      focusNode: widget.focus,
      minLines: 1,
      maxLines: MesuresBarre.lignesMax,
      textInputAction: TextInputAction.send,
      textAlignVertical: TextAlignVertical.center,
      // Hauteur de ligne imposée : identique pour toutes les polices de
      // secours, donc un centrage stable.
      strutStyle: StrutStyle(
        fontSize: taille,
        height: interligne,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      ),
      onSubmitted: (_) => _envoyer(),
      cursorColor: CouleursJarvis.signal,
      cursorWidth: 1.6,
      cursorRadius: const Radius.circular(2),
      style: Theme.of(context).textTheme.bodyLarge?.merge(texte),
      decoration: InputDecoration(
        hintText: widget.pieceJointe != null
            ? LigneDeCommande.inviteConsigne
            : compacte
            ? LigneDeCommande.inviteCourte
            : LigneDeCommande.invite,
        hintMaxLines: 1,
        hintStyle: texte.copyWith(
          overflow: TextOverflow.ellipsis,
          color: CouleursJarvis.texteSecondaire.withValues(alpha: 0.88),
        ),
        isDense: true,
        border: InputBorder.none,
        // Vide égal au-dessus et au-dessous de la ligne, moins la petite
        // correction optique.
        contentPadding: EdgeInsets.only(
          top: vide - MesuresBarre.decalageOptique,
          bottom: vide + MesuresBarre.decalageOptique,
        ),
      ),
    );
    final plus = _CentreBouton(
      hauteur: interieur,
      child: _BoutonAjouter(
        surColler: _coller,
        surImporter: widget.surImporterWhatsApp,
        surAjouterMessage: widget.surAjouterMessageWhatsApp,
        feuille: compacte,
      ),
    );
    final separateur = _CentreBouton(
      hauteur: interieur,
      child: Container(width: 1, height: 22, color: CouleursJarvis.trait),
    );
    final vocal = ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controleur,
      builder: (context, valeur, _) {
        final envoi = valeur.text.trim().isNotEmpty;
        return BoutonVocal(
          envoi: envoi,
          chatEnArrierePlan: widget.chatVocalReprenable,
          libelle: envoi
              ? 'Envoyer le message'
              : widget.chatVocalReprenable
              ? 'Reprendre le chat vocal'
              : 'Ouvrir le chat vocal',
          onPressed: envoi ? _envoyer : widget.onChatVocal,
          largeur: largeurVocal,
          hauteur: interieur,
        );
      },
    );

    final lecture = widget.lectureVocale;
    final hautParleur = lecture == null
        ? null
        : _CentreBouton(
            hauteur: interieur,
            child: _BoutonHautParleur(
              actif: lecture,
              surAppui: widget.surLecture,
            ),
          );

    // Au repos, le champ est entre « + » (et son séparateur) et la capsule
    // vocale (et le haut-parleur) ; déplié, il prend toute la largeur,
    // au-dessus des boutons.
    const gaucheRepos =
        MesuresBarre.tailleBoutonPlus +
        MesuresBarre.margeAvantSeparateur +
        1 +
        MesuresBarre.margeApresSeparateur;
    final droiteRepos =
        largeurVocal +
        MesuresBarre.ecartVocal +
        (hautParleur == null
            ? 0
            : MesuresBarre.tailleHautParleur + MesuresBarre.ecartBoutons);
    const margeDeplie = MesuresBarre.margeTexteDeplie;
    // Champ vide (invite seule) : pendant le dépliage ou le repli, l'invite
    // s'efface à mi-chemin puis réapparaît à sa nouvelle place, au lieu de
    // glisser en diagonale. Un texte saisi, lui, reste toujours visible.

    // Calque propre : la barre (ombres, texte) n'est repeinte que si elle
    // change elle-même, pas quand les particules ou le fond bougent.
    return RepaintBoundary(
      // Toucher la capsule ou ses boutons ne retire pas le focus du champ :
      // la barre ne se replie pas sous le doigt.
      child: TextFieldTapRegion(
        child: GestureDetector(
          // Toucher l'espace libre de la barre place le curseur.
          onTap: widget.focus.requestFocus,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(minHeight: hauteur),
            padding: const EdgeInsets.fromLTRB(marge + 1, marge, marge, marge),
            decoration: BoxDecoration(
              color: CouleursJarvis.coque.withValues(
                alpha: focus ? 0.96 : 0.86,
              ),
              // Pilule au repos ; dépliée, le même rayon donne un
              // rectangle très arrondi.
              borderRadius: BorderRadius.circular(hauteur / 2),
              border: Border.all(
                color: focus
                    ? CouleursJarvis.signal.withValues(alpha: 0.32)
                    : CouleursJarvis.trait.withValues(alpha: 0.75),
              ),
              boxShadow: [
                // Ombre portée très douce : la barre flotte sur le fond.
                const BoxShadow(
                  color: Color(0x14453B66),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
                const BoxShadow(
                  color: Color(0x0A3A3350),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
                // Lueur à peine perceptible quand on écrit.
                if (focus)
                  BoxShadow(
                    color: CouleursJarvis.signal.withValues(alpha: 0.1),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _courbe,
              child: champ,
              builder: (context, champ) {
                final t = _courbe.value;
                final opaciteInvite = widget.controleur.text.isEmpty
                    ? Curves.easeIn.transform((2 * t - 1).abs())
                    : 1.0;
                return Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Toujours présent (même vide) : le champ garde sa
                        // place dans la colonne et n'est jamais recréé.
                        AnimatedSize(
                          duration: MesuresBarre.dureeDepliage,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.bottomLeft,
                          child: widget.pieceJointe == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    2,
                                    4,
                                    6,
                                  ),
                                  child: widget.pieceJointe,
                                ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            left: lerpDouble(gaucheRepos, margeDeplie, t)!,
                            right: lerpDouble(droiteRepos, margeDeplie, t)!,
                          ),
                          // Toujours le même Opacity : le champ n'est
                          // jamais recréé (à 1, il ne coûte rien).
                          child: Opacity(opacity: opaciteInvite, child: champ),
                        ),
                        // Ligne des boutons : s'ouvre sous le texte.
                        SizedBox(
                          height: t * (interieur + MesuresBarre.ecartBoutons),
                        ),
                      ],
                    ),
                    Positioned(left: 0, bottom: 0, child: plus),
                    if (t < 1)
                      Positioned(
                        left:
                            MesuresBarre.tailleBoutonPlus +
                            MesuresBarre.margeAvantSeparateur,
                        bottom: 0,
                        child: Opacity(opacity: 1 - t, child: separateur),
                      ),
                    if (hautParleur != null)
                      Positioned(
                        right: largeurVocal + MesuresBarre.ecartBoutons,
                        bottom: 0,
                        child: hautParleur,
                      ),
                    Positioned(right: 0, bottom: 0, child: vocal),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton centré sur la hauteur d'une ligne de la barre.
class _CentreBouton extends StatelessWidget {
  const _CentreBouton({required this.hauteur, required this.child});

  final double hauteur;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hauteur,
    child: Center(child: child),
  );
}

/// Haut-parleur : lecture vocale des réponses écrites (chat vocal en
/// arrière-plan). Pastille lavande ; plus marquée quand la lecture est
/// active.
class _BoutonHautParleur extends StatelessWidget {
  const _BoutonHautParleur({required this.actif, this.surAppui});

  final bool actif;
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: actif ? 'Couper la lecture vocale' : 'Activer la lecture vocale',
      isSelected: actif,
      onPressed: surAppui,
      icon: const Icon(Icons.volume_off_outlined, size: 20),
      selectedIcon: const Icon(Icons.volume_up_outlined, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(MesuresBarre.tailleHautParleur),
        minimumSize: const Size.square(MesuresBarre.tailleHautParleur),
        padding: EdgeInsets.zero,
        foregroundColor: actif
            ? CouleursJarvis.signal
            : CouleursJarvis.texteSecondaire,
        backgroundColor: CouleursJarvis.signal.withValues(
          alpha: actif ? 0.14 : 0.06,
        ),
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Bouton « + » : coller une conversation ou importer un export WhatsApp.
///
/// Ordinateur : petit menu flottant. Téléphone ([feuille]) : feuille en bas
/// de l'écran, toujours visible même avec le clavier.
class _BoutonAjouter extends StatefulWidget {
  const _BoutonAjouter({
    required this.surColler,
    this.surImporter,
    this.surAjouterMessage,
    this.feuille = false,
  });

  final VoidCallback surColler;
  final VoidCallback? surImporter;
  final VoidCallback? surAjouterMessage;
  final bool feuille;

  @override
  State<_BoutonAjouter> createState() => _BoutonAjouterState();
}

class _BoutonAjouterState extends State<_BoutonAjouter> {
  bool _appui = false;

  Future<void> _ouvrirFeuille() async {
    final choix = await afficherFeuilleAjout(
      context,
      actualisation: widget.surAjouterMessage != null,
    );
    // La feuille est fermée avant de lire le presse-papiers.
    if (!mounted) return;
    switch (choix) {
      case ChoixAjout.coller:
        widget.surColler();
      case ChoixAjout.importerWhatsApp:
        widget.surImporter?.call();
      case ChoixAjout.ajouterMessageWhatsApp:
        widget.surAjouterMessage?.call();
      case ChoixAjout(:final application?):
        await _ouvrirApplication(application);
      case _:
        break;
    }
  }

  Future<void> _ouvrirApplication(ApplicationExterne app) async {
    final messager = ScaffoldMessenger.maybeOf(context);
    if (await ouvrirApplicationExterne(app)) return;
    messager?.showSnackBar(SnackBar(content: Text(app.echec)));
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(CouleursJarvis.coque),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: const WidgetStatePropertyAll(Color(0x403A3350)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: CouleursJarvis.trait),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.content_paste_rounded, size: 18),
          onPressed: widget.surColler,
          child: const Text('Coller une conversation'),
        ),
        MenuItemButton(
          leadingIcon: const LogoWhatsApp(taille: 18),
          trailingIcon: const Icon(Icons.chevron_right_rounded, size: 18),
          onPressed: widget.surImporter,
          child: const Text('Importer une conversation'),
        ),
        // Ordinateur : action secondaire discrète, juste sous l'import
        // (le glissement reste réservé à l'écran tactile).
        if (widget.surAjouterMessage case final ajouter?)
          MenuItemButton(
            key: const Key('menu-ajouter-message'),
            leadingIcon: const Padding(
              padding: EdgeInsets.only(left: 18),
              child: Icon(Icons.add_comment_outlined, size: 16),
            ),
            onPressed: ajouter,
            child: const Text(
              LigneImportGlissante.action,
              style: TextStyle(fontSize: 13),
            ),
          ),
        // Ouvrir une application (jamais ses messages).
        for (final app in ApplicationExterne.values)
          MenuItemButton(
            leadingIcon: LogoApplication(application: app, taille: 18),
            onPressed: () => _ouvrirApplication(app),
            child: Text('Ouvrir ${app.nom}'),
          ),
      ],
      builder: (context, menu, _) => Listener(
        onPointerDown: (_) => setState(() => _appui = true),
        onPointerUp: (_) => setState(() => _appui = false),
        onPointerCancel: (_) => setState(() => _appui = false),
        child: AnimatedScale(
          scale: _appui ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          child: IconButton(
            tooltip: 'Ajouter une conversation',
            onPressed: widget.feuille
                ? _ouvrirFeuille
                : () => menu.isOpen ? menu.close() : menu.open(),
            icon: const Icon(Icons.add_rounded, size: 22),
            style: ButtonStyle(
              fixedSize: const WidgetStatePropertyAll(
                Size.square(MesuresBarre.tailleBoutonPlus),
              ),
              minimumSize: const WidgetStatePropertyAll(
                Size.square(MesuresBarre.tailleBoutonPlus),
              ),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              foregroundColor: WidgetStatePropertyAll(CouleursJarvis.texte),
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.pressed)
                    ? CouleursJarvis.champ[2]
                    : s.contains(WidgetState.hovered) ||
                          s.contains(WidgetState.focused)
                    ? CouleursJarvis.champ[1]
                    : CouleursJarvis.champ[0],
              ),
              overlayColor: WidgetStatePropertyAll(
                CouleursJarvis.texte.withValues(alpha: 0.04),
              ),
              side: WidgetStatePropertyAll(
                BorderSide(color: CouleursJarvis.trait.withValues(alpha: 0.8)),
              ),
              shape: const WidgetStatePropertyAll(CircleBorder()),
            ),
          ),
        ),
      ),
    );
  }
}
