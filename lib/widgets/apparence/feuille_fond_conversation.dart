import 'package:flutter/material.dart';

import '../../models/apparence/fond_photo.dart';
import '../../pages/editeur_fond_page.dart';
import '../../services/apparence/service_fonds.dart';
import '../../theme/theme_jarvis.dart';
import '../parametres/pages_apparence.dart';

/// « Personnaliser le fond » (menu d'une conversation) : fond général,
/// un motif, une photo, ou modifier la photo de cette conversation. Le
/// choix s'applique tout de suite ; aucun bouton permanent dans le chat.
Future<void> ouvrirFondConversation(
  BuildContext context, {
  required String id,
  required String titre,
}) async {
  final fonds = ServiceFonds.of(context, ecouter: false);
  if (fonds == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: CouleursJarvis.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) =>
        FeuilleFondConversation(fonds: fonds, id: id, titre: titre),
  );
}

class FeuilleFondConversation extends StatefulWidget {
  const FeuilleFondConversation({
    super.key,
    required this.fonds,
    required this.id,
    required this.titre,
  });

  final ServiceFonds fonds;
  final String id;
  final String titre;

  static const general = 'Utiliser le fond général';
  static const motif = 'Choisir un motif';
  static const photo = 'Choisir une photo';
  static const modifier = 'Modifier la photo';

  @override
  State<FeuilleFondConversation> createState() =>
      _FeuilleFondConversationState();
}

class _FeuilleFondConversationState extends State<FeuilleFondConversation> {
  bool _motifs = false;

  ServiceFonds get _f => widget.fonds;

  Future<void> _photo({FondPhoto? existante}) async {
    final octets = existante == null ? await choisirPhotoFond() : null;
    if (existante == null && octets == null) return;
    if (!mounted) return;
    final photo = await ouvrirEditeurFond(
      context,
      fonds: _f,
      octets: octets,
      existante: existante,
    );
    if (photo != null) await _f.definir(widget.id, FondPhotoChoisi(photo));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _f,
      builder: (context, _) {
        final propre = _f.fondDe([widget.id]);
        final a = _f.apparence;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CouleursJarvis.trait,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Fond de la conversation',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CouleursJarvis.texte,
                  ),
                ),
                Text(
                  widget.titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
                const SizedBox(height: 8),
                _Option(
                  icone: Icons.wallpaper_rounded,
                  titre: FeuilleFondConversation.general,
                  sousTitre: 'Applique le choix défini dans Apparence',
                  choisie: propre == null,
                  surAppui: () => _f.definir(widget.id, null),
                ),
                _Option(
                  icone: Icons.grid_view_rounded,
                  titre: FeuilleFondConversation.motif,
                  choisie: propre is FondMotif,
                  ouvert: _motifs,
                  surAppui: () => setState(() => _motifs = !_motifs),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_motifs
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: CarrouselFonds(
                            cle: 'motifs-conversation',
                            palette: a.palette,
                            intensite: propre is FondMotif
                                ? propre.intensite
                                : a.intensite,
                            fond: propre is FondMotif ? propre : null,
                            surMotif: (m) => _f.definir(
                              widget.id,
                              FondMotif(m, a.intensite),
                            ),
                          ),
                        ),
                ),
                _Option(
                  icone: Icons.add_photo_alternate_outlined,
                  titre: FeuilleFondConversation.photo,
                  choisie: false,
                  surAppui: _photo,
                ),
                if (propre case FondPhotoChoisi(:final photo))
                  _Option(
                    icone: Icons.tune_rounded,
                    titre: FeuilleFondConversation.modifier,
                    choisie: true,
                    surAppui: () => _photo(existante: photo),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icone,
    required this.titre,
    required this.choisie,
    required this.surAppui,
    this.sousTitre,
    this.ouvert,
  });

  final IconData icone;
  final String titre;
  final String? sousTitre;
  final bool choisie;
  final VoidCallback surAppui;

  /// Option dépliable (null : simple action).
  final bool? ouvert;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisie,
      child: InkWell(
        onTap: surAppui,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            children: [
              Icon(icone, size: 21, color: CouleursJarvis.signal),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    if (sousTitre case final s?)
                      Text(
                        s,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                  ],
                ),
              ),
              if (ouvert case final o?)
                AnimatedRotation(
                  turns: o ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                )
              else if (choisie)
                Icon(Icons.check_rounded, color: CouleursJarvis.signal),
            ],
          ),
        ),
      ),
    );
  }
}
