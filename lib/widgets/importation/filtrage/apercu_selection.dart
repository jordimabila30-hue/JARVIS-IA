import 'package:flutter/material.dart';

import '../../../models/importation/filtre_whatsapp.dart';
import '../../../services/importation/selection_whatsapp.dart';
import '../../../theme/theme_jarvis.dart';
import '../../defilement_sans_barre.dart';
import '../apercu_discussion.dart';
import '../lecture_whatsapp_widgets.dart';

/// Aperçu de la sélection : la discussion (bulles, auteurs, dates et
/// heures réelles, séparateurs de jour) avec une case par message.
/// Virtualisé (seules les lignes visibles sont construites) et ouvert sur
/// les messages les plus récents. Un message décoché reste visible, pâli.
/// Un groupe de médias garde l'identifiant de chacun : sa case les coche
/// ou décoche tous. Avec [navigation], deux flèches discrètes (en haut et
/// en bas, à gauche) remontent ou redescendent rapidement la discussion.
class ApercuSelection extends StatefulWidget {
  const ApercuSelection({
    super.key,
    required this.selection,
    required this.disposition,
    this.marges = EdgeInsets.zero,
    this.navigation = false,
  });

  static const aucunMessage = 'Aucun message pour ce choix.';
  static const monter = 'Remonter au début';
  static const descendre = 'Descendre aux derniers messages';

  final SelectionWhatsApp selection;
  final DispositionAuteurs disposition;
  final EdgeInsets marges;

  /// Flèches « Monter » et « Descendre » (mode « Par messages »).
  final bool navigation;

  @override
  State<ApercuSelection> createState() => _ApercuSelectionState();
}

class _ApercuSelectionState extends State<ApercuSelection> {
  List<ElementApercu> _elements = const [];
  int? _version;
  SelectionWhatsApp? _pour;

  final _defilement = ScrollController();

  // Liste inversée : 0 = derniers messages (bas), max = début (haut).
  bool _peutMonter = false;
  bool _peutDescendre = false;

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  /// Flèches visibles seulement s'il reste de la distance dans leur sens.
  bool _surDefilement(ScrollMetrics m) {
    final monter = m.pixels < m.maxScrollExtent - 4;
    final descendre = m.pixels > m.minScrollExtent + 4;
    if (monter != _peutMonter || descendre != _peutDescendre) {
      setState(() {
        _peutMonter = monter;
        _peutDescendre = descendre;
      });
    }
    return false;
  }

  /// Défilement rapide et animé. Loin de la cible : saut jusqu'à deux
  /// écrans d'elle, puis animation (fluide même sur des milliers de
  /// messages). La fin d'une liste virtualisée n'est connue qu'en
  /// l'approchant : on recommence si elle a reculé.
  Future<void> _allerVers({required bool haut}) async {
    for (var essai = 0; essai < 4; essai++) {
      if (!_defilement.hasClients) return;
      final p = _defilement.position;
      final cible = haut ? p.maxScrollExtent : p.minScrollExtent;
      if ((p.pixels - cible).abs() < 1) return;
      final ecran = p.viewportDimension * 2;
      if ((p.pixels - cible).abs() > ecran) {
        _defilement.jumpTo(haut ? cible - ecran : cible + ecran);
      }
      await _defilement.animateTo(
        cible,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Recalculés seulement quand la liste affichée change (pas à chaque
  /// case cochée).
  List<ElementApercu> get _actuels {
    final s = widget.selection;
    if (_version != s.versionAffichage || !identical(_pour, s)) {
      _elements = elementsApercu(s.visibles);
      _version = s.versionAffichage;
      _pour = s;
    }
    return _elements;
  }

  void _appui(String id) {
    final s = widget.selection;
    if (s.mode == ModeFiltrage.messages && s.plageEnCours) {
      s.designer(id);
    } else {
      s.basculer(id);
    }
  }

  Widget _element(ElementApercu e) {
    final s = widget.selection;
    final d = widget.disposition;
    switch (e) {
      case JourApercu(:final jour):
        return SeparateurJour(jour);
      case MessageApercu(:final message, :final debutSuite):
        final bulle = BulleApercu(
          message: message,
          cote: d.cote(message.auteur),
          debutSuite: debutSuite,
          auteur: debutSuite ? message.auteur : null,
          couleurAuteur: d.couleur(message.auteur),
        );
        if (!s.estSelectionnable(message.id)) {
          return Padding(
            // Événement centré : même retrait des deux côtés.
            padding: const EdgeInsets.symmetric(
              horizontal: LigneCochable.gouttiere,
            ),
            child: bulle,
          );
        }
        return LigneCochable(
          key: ValueKey(message.id),
          etat: s.estCoche(message.id),
          ancre: s.premierDeLaPlage == message.id,
          libelle: message.auteur,
          cote: d.cote(message.auteur),
          margeHaut: BulleApercu.margeHaut(debutSuite),
          surAppui: () => _appui(message.id),
          child: bulle,
        );
      case MediasApercu(:final medias, :final debutSuite):
        final auteur = medias.first.auteur;
        final coches = medias.where((m) => s.estCoche(m.id)).length;
        final ids = [for (final m in medias) m.id];
        return LigneCochable(
          key: ValueKey(ids.first),
          etat: coches == 0
              ? false
              : coches == medias.length
              ? true
              : null,
          ancre: ids.contains(s.premierDeLaPlage),
          libelle: auteur,
          cote: d.cote(auteur),
          margeHaut: BulleApercu.margeHaut(debutSuite),
          surAppui: () {
            if (s.mode == ModeFiltrage.messages && s.plageEnCours) {
              // Une plage commence au premier média du groupe et finit au
              // dernier.
              s.designer(s.premierDeLaPlage == null ? ids.first : ids.last);
            } else {
              s.cocher(ids, coches < medias.length);
            }
          },
          child: BulleMediasGroupes(
            medias: medias,
            cote: d.cote(auteur),
            debutSuite: debutSuite,
            auteur: debutSuite ? auteur : null,
            couleurAuteur: d.couleur(auteur),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final elements = _actuels;
    if (elements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ApercuSelection.aucunMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
      );
    }
    final n = elements.length;
    final liste = ScrollConfiguration(
      behavior: const DefilementSansBarre(),
      child: CustomScrollView(
        controller: _defilement,
        reverse: true,
        slivers: [
          SliverPadding(
            padding: widget.marges,
            sliver: SliverList.builder(
              itemCount: n,
              itemBuilder: (context, i) => _element(elements[n - 1 - i]),
            ),
          ),
        ],
      ),
    );
    if (!widget.navigation) return liste;
    final gauche = widget.marges.left;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _surDefilement(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _surDefilement(n.metrics),
            child: liste,
          ),
        ),
        Positioned(
          left: gauche,
          top: 6,
          child: BoutonDefilement(
            visible: _peutMonter,
            icone: Icons.keyboard_arrow_up_rounded,
            infobulle: ApercuSelection.monter,
            surAppui: () => _allerVers(haut: true),
          ),
        ),
        Positioned(
          left: gauche,
          bottom: 6,
          child: BoutonDefilement(
            visible: _peutDescendre,
            icone: Icons.keyboard_arrow_down_rounded,
            infobulle: ApercuSelection.descendre,
            surAppui: () => _allerVers(haut: false),
          ),
        ),
      ],
    );
  }
}

/// Flèche ronde et discrète (violet léger, icône claire) : facile à
/// toucher (48 px), petite à l'œil (34 px). Masquée quand elle n'a plus
/// rien à faire, sans prendre les touchers.
class BoutonDefilement extends StatelessWidget {
  const BoutonDefilement({
    super.key,
    required this.visible,
    required this.icone,
    required this.infobulle,
    required this.surAppui,
  });

  final bool visible;
  final IconData icone;
  final String infobulle;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: Tooltip(
          message: infobulle,
          child: Semantics(
            button: true,
            label: infobulle,
            child: InkWell(
              onTap: surAppui,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CouleursJarvis.signal.withValues(alpha: 0.55),
                      border: Border.all(
                        color: CouleursJarvis.lavande.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CouleursJarvis.texte.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icone, size: 22, color: CouleursJarvis.ivoire),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une ligne de l'aperçu avec sa case : toucher la ligne coche ou
/// décoche (ou désigne une borne de plage). Décochée : pâlie. La case est
/// du côté de la bulle (gauche ou droite), centrée sur elle.
class LigneCochable extends StatelessWidget {
  const LigneCochable({
    super.key,
    required this.etat,
    required this.ancre,
    required this.surAppui,
    required this.child,
    this.libelle,
    this.cote = CoteBulle.gauche,
    this.margeHaut = 0,
  });

  /// Largeur réservée à la case, du côté de la bulle.
  static const gouttiere = 36.0;

  /// Côté de la bulle : la case se place de ce côté.
  final CoteBulle cote;

  /// Espace au-dessus de la bulle dans [child] : la case est centrée sur
  /// la bulle, pas sur cet espace.
  final double margeHaut;

  /// true : cochée ; false : décochée ; null : en partie (groupe).
  final bool? etat;

  /// Premier message d'une plage en cours de choix.
  final bool ancre;
  final VoidCallback surAppui;
  final Widget child;
  final String? libelle;

  @override
  Widget build(BuildContext context) {
    // Décalée de la marge du haut : centre de la case = centre de la bulle.
    final caseCochee = SizedBox(
      width: gouttiere,
      child: Padding(
        padding: EdgeInsets.only(top: margeHaut),
        child: Center(child: CaseCochee(etat: etat)),
      ),
    );
    return Semantics(
      checked: etat ?? false,
      mixed: etat == null,
      label: libelle,
      child: InkWell(
        onTap: surAppui,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: ancre
                ? CouleursJarvis.lavande.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (cote == CoteBulle.gauche) caseCochee,
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: etat == false ? 0.45 : 1,
                  child: child,
                ),
              ),
              if (cote == CoteBulle.droite) caseCochee,
            ],
          ),
        ),
      ),
    );
  }
}

/// Case ronde : violette et cochée, vide, ou en partie (groupe).
class CaseCochee extends StatelessWidget {
  const CaseCochee({super.key, required this.etat});

  final bool? etat;

  @override
  Widget build(BuildContext context) {
    final pleine = etat != false;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pleine ? CouleursJarvis.signal : CouleursJarvis.coque,
        border: Border.all(
          color: pleine
              ? CouleursJarvis.signal
              : CouleursJarvis.trait.withValues(alpha: 0.95),
          width: 1.5,
        ),
      ),
      child: pleine
          ? Icon(
              etat == true ? Icons.check_rounded : Icons.remove_rounded,
              size: 15,
              color: CouleursJarvis.ivoire,
            )
          : null,
    );
  }
}

/// Au-dessus de l'aperçu : ce qui est montré, « Tout cocher »,
/// « Tout décocher ».
class EnteteApercu extends StatelessWidget {
  const EnteteApercu({super.key, required this.selection});

  static const toutCocher = 'Tout cocher';
  static const toutDecocher = 'Tout décocher';

  final SelectionWhatsApp selection;

  static String quoi(SelectionWhatsApp s) {
    if (s.afficheCorrespondants) {
      final n = s.nombreCorrespondants;
      return '${nombreEnFrancais(n)} message${n > 1 ? 's' : ''} '
          'correspondant${n > 1 ? 's' : ''}';
    }
    return 'Toute la conversation';
  }

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final vide = s.afficheCorrespondants && s.nombreCorrespondants == 0;
    Widget bouton(String texte, bool valeur) => TextButton(
      onPressed: vide ? null : () => s.cocherVisibles(valeur),
      style: TextButton.styleFrom(
        foregroundColor: CouleursJarvis.signal,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      child: Text(texte),
    );
    // Les deux actions passent sous le libellé si la place manque.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          quoi(s),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
        Wrap(children: [bouton(toutCocher, true), bouton(toutDecocher, false)]),
      ],
    );
  }
}

/// Messages d'une conversation sans date reconnue : jamais rattachés à
/// une période ; on les choisit dans « Par messages ».
String? avisSansDate(SelectionWhatsApp s) {
  final n = s.index.nombreSansDate;
  if (n == 0) return null;
  return n == 1
      ? '1 message sans date reconnue : choisissez-le dans « Par messages ».'
      : '${nombreEnFrancais(n)} messages sans date reconnue : '
            'choisissez-les dans « Par messages ».';
}
