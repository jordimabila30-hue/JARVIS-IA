import 'package:flutter/material.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../models/conversations/source_conversation.dart';
import '../../services/conversations/conversations_multicanal.dart';
import '../../theme/theme_jarvis.dart';
import '../defilement_sans_barre.dart';
import 'ligne_conversation.dart';
import 'selecteur_sources.dart';

/// « MES CONVERSATIONS » dans le menu latéral : sélecteur des messageries,
/// recherche dans la source choisie, puis sa liste.
///
/// Changer de source ne fait glisser que la zone de la liste ; le titre,
/// les logos et la recherche ne bougent pas, et rien n'est ouvert dans
/// l'accueil tant qu'on ne touche pas une conversation.
class SectionConversations extends StatelessWidget {
  const SectionConversations({
    super.key,
    required this.multicanal,
    required this.surOuvrir,
    this.surSupprimer,
  });

  final ConversationsMulticanal multicanal;

  /// Une conversation a été touchée.
  final ValueChanged<ApercuConversation> surOuvrir;

  /// Suppression confirmée par l'utilisateur ; par défaut, la conversation
  /// est supprimée des données de sa messagerie.
  final ValueChanged<ApercuConversation>? surSupprimer;

  static const titre = 'MES CONVERSATIONS';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            titre,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
        SelecteurSources(
          sources: multicanal.sources,
          selection: multicanal.selection,
          surChoix: multicanal.choisir,
        ),
        const SizedBox(height: 8),
        _Recherche(multicanal: multicanal),
        const SizedBox(height: 6),
        Expanded(
          child: ListesGlissantes(
            multicanal: multicanal,
            surOuvrir: surOuvrir,
            surSupprimer: surSupprimer,
          ),
        ),
      ],
    );
  }
}

/// Champ de recherche discret, limité à la source choisie.
class _Recherche extends StatefulWidget {
  const _Recherche({required this.multicanal});

  final ConversationsMulticanal multicanal;

  @override
  State<_Recherche> createState() => _RechercheState();
}

class _RechercheState extends State<_Recherche> {
  late final _controleur = TextEditingController(
    text: widget.multicanal.recherche.value,
  );

  ValueNotifier<String> get _recherche => widget.multicanal.recherche;

  @override
  void initState() {
    super.initState();
    _recherche.addListener(_surRecherche);
  }

  // Remise à zéro par le changement de source.
  void _surRecherche() {
    if (_controleur.text != _recherche.value) {
      _controleur.text = _recherche.value;
    }
  }

  @override
  void dispose() {
    _recherche.removeListener(_surRecherche);
    _controleur.dispose();
    super.dispose();
  }

  static OutlineInputBorder _bord(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controleur,
        onChanged: (v) => _recherche.value = v,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13.5, color: CouleursJarvis.texte),
        cursorColor: CouleursJarvis.signal,
        decoration: InputDecoration(
          hintText: 'Rechercher une conversation',
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: CouleursJarvis.texteSecondaire.withValues(alpha: 0.8),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: CouleursJarvis.texteSecondaire,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: ValueListenableBuilder<String>(
            valueListenable: _recherche,
            builder: (context, texte, _) => texte.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Effacer la recherche',
                    onPressed: () => _recherche.value = '',
                    iconSize: 16,
                    icon: const Icon(Icons.close_rounded),
                    color: CouleursJarvis.texteSecondaire,
                  ),
          ),
          isDense: true,
          filled: true,
          fillColor: CouleursJarvis.coque,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: _bord(CouleursJarvis.trait.withValues(alpha: 0.7)),
          enabledBorder: _bord(CouleursJarvis.trait.withValues(alpha: 0.7)),
          focusedBorder: _bord(CouleursJarvis.signal.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

/// Zone des listes : au changement de source, l'ancienne liste glisse d'un
/// côté pendant que la nouvelle arrive de l'autre (vers la droite si la
/// source est plus à droite dans le sélecteur), 200 ms, easeOutCubic.
///
/// Seules les deux listes concernées existent pendant le glissement, puis
/// une seule. Chacune retrouve sa position de défilement
/// ([ConversationsMulticanal.position]). Un changement rapide pendant le
/// glissement repart de la liste affichée : la liste suit toujours le logo
/// choisi.
class ListesGlissantes extends StatefulWidget {
  const ListesGlissantes({
    super.key,
    required this.multicanal,
    required this.surOuvrir,
    this.surSupprimer,
  });

  final ConversationsMulticanal multicanal;
  final ValueChanged<ApercuConversation> surOuvrir;
  final ValueChanged<ApercuConversation>? surSupprimer;

  static const duree = Duration(milliseconds: 200);

  @override
  State<ListesGlissantes> createState() => _ListesGlissantesState();
}

class _ListesGlissantesState extends State<ListesGlissantes>
    with SingleTickerProviderStateMixin {
  ValueNotifier<SourceConversation> get _selection =>
      widget.multicanal.selection;

  late SourceConversation _affichee = _selection.value;
  SourceConversation? _sortante;
  int _sens = 1;

  late final _anim = AnimationController(
    vsync: this,
    duration: ListesGlissantes.duree,
  )..addStatusListener(_surStatut);
  late final _courbe = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _selection.addListener(_surSelection);
  }

  void _surSelection() {
    final nouvelle = _selection.value;
    if (nouvelle == _affichee) return;
    setState(() {
      _sortante = _affichee;
      _sens = nouvelle.index > _affichee.index ? 1 : -1;
      _affichee = nouvelle;
    });
    _anim.forward(from: 0);
  }

  void _surStatut(AnimationStatus statut) {
    if (statut == AnimationStatus.completed && _sortante != null) {
      setState(() => _sortante = null);
    }
  }

  @override
  void dispose() {
    _selection.removeListener(_surSelection);
    _courbe.dispose();
    _anim.dispose();
    super.dispose();
  }

  Widget _liste(SourceConversation source, {required bool sortante}) {
    final liste = _ListeSource(
      source: source,
      multicanal: widget.multicanal,
      surOuvrir: widget.surOuvrir,
      surSupprimer: widget.surSupprimer,
    );
    return KeyedSubtree(
      // Même clé quel que soit le rôle : l'état (défilement) est gardé.
      key: ValueKey(source),
      child: IgnorePointer(
        ignoring: sortante,
        child: ExcludeSemantics(
          excluding: sortante,
          child: AnimatedBuilder(
            animation: _courbe,
            child: liste,
            builder: (context, liste) {
              final t = _anim.isAnimating || _sortante != null
                  ? _courbe.value
                  : 1.0;
              final x = sortante ? -_sens * t : _sens * (1 - t);
              return FractionalTranslation(
                translation: Offset(x, 0),
                child: liste,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortante = _sortante;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (sortante != null) _liste(sortante, sortante: true),
          _liste(_affichee, sortante: false),
        ],
      ),
    );
  }
}

/// Liste d'une messagerie : épinglées d'abord, recherche appliquée si
/// c'est la source choisie, position de défilement retrouvée.
class _ListeSource extends StatefulWidget {
  const _ListeSource({
    required this.source,
    required this.multicanal,
    required this.surOuvrir,
    this.surSupprimer,
  });

  final SourceConversation source;
  final ConversationsMulticanal multicanal;
  final ValueChanged<ApercuConversation> surOuvrir;
  final ValueChanged<ApercuConversation>? surSupprimer;

  @override
  State<_ListeSource> createState() => _ListeSourceState();
}

class _ListeSourceState extends State<_ListeSource> {
  late final _defilement = ScrollController(
    initialScrollOffset: widget.multicanal.position(widget.source),
  );

  @override
  void initState() {
    super.initState();
    _defilement.addListener(_memoriser);
  }

  void _memoriser() {
    if (_defilement.hasClients) {
      widget.multicanal.memoriserPosition(widget.source, _defilement.offset);
    }
  }

  @override
  void dispose() {
    _defilement.removeListener(_memoriser);
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.multicanal;
    return ListenableBuilder(
      listenable: Listenable.merge([m, m.recherche, m.selection]),
      builder: (context, _) {
        final contenu = _contenu(context, m);
        final avertissement = m.avertissement(widget.source);
        if (avertissement == null) return contenu;
        return Column(
          children: [
            _Avertissement(
              texte: avertissement,
              surAppui: () => m.actualiser(widget.source, force: true),
            ),
            Expanded(child: contenu),
          ],
        );
      },
    );
  }

  Widget _contenu(BuildContext context, ConversationsMulticanal m) {
    final requete = m.selection.value == widget.source ? m.recherche.value : '';
    final liste = m.liste(widget.source, requete: requete);
    if (liste.isEmpty) {
      return _Vide(
        texte: requete.trim().isNotEmpty
            ? 'Aucun résultat'
            : widget.source == SourceConversation.jarvis
            ? 'Aucune conversation pour l’instant'
            : 'Aucune conversation ${widget.source.libelle}',
      );
    }
    final maintenant = DateTime.now();
    return NotificationListener<ScrollStartNotification>(
      // La liste défile : une ligne restée ouverte se referme.
      onNotification: (_) {
        LigneConversation.fermerToutes();
        return false;
      },
      child: ScrollConfiguration(
        behavior: const DefilementSansBarre(),
        child: ListView.builder(
          controller: _defilement,
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          itemExtent: LigneConversation.hauteurPour(
            MediaQuery.textScalerOf(context),
          ),
          itemCount: liste.length,
          itemBuilder: (context, i) {
            final c = liste[i];
            return LigneConversation(
              key: ValueKey(c.cle),
              conversation: c,
              epinglee: m.epingles.estEpinglee(c),
              maintenant: maintenant,
              surOuvrir: () => widget.surOuvrir(c),
              surEpingler: () => m.epingles.basculer(c),
              surSupprimer: () {
                final supprimer = widget.surSupprimer;
                supprimer == null ? m.supprimer(c) : supprimer(c);
              },
            );
          },
        ),
      ),
    );
  }
}

/// Liste non actualisée, suppression impossible… : une ligne discrète
/// au-dessus de la liste ; la toucher relance l'actualisation.
class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.texte, required this.surAppui});

  final String texte;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: surAppui,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 14,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texte,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// État vide discret (aucune conversation, aucun résultat).
class _Vide extends StatelessWidget {
  const _Vide({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
      ),
    );
  }
}
