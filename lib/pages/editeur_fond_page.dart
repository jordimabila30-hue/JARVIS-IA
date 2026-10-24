import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/apparence/fond_photo.dart';
import '../services/apparence/depot_fonds_photo.dart';
import '../services/apparence/service_fonds.dart';
import '../theme/theme_jarvis.dart';
import '../widgets/apparence/rendu_fond_photo.dart';
import '../widgets/parametres/elements_parametres.dart';

/// Choisit une photo avec le sélecteur de la plateforme (Android : photos
/// du système ; iOS : sélecteur natif ; Web : fichiers du navigateur ;
/// Windows : fichiers image). Rend ses octets (null : rien de choisi).
/// Rien n'est envoyé nulle part.
Future<Uint8List?> choisirPhotoFond() async {
  final resultat = await FilePicker.pickFiles(
    dialogTitle: 'Choisir une photo de fond',
    type: FileType.image,
    withData: true,
    lockParentWindow: true,
  );
  return resultat?.files.singleOrNull?.bytes;
}

/// Ouvre l'éditeur plein écran du fond : [octets] (photo tout juste
/// choisie) ou [existante] (photo déjà en place, à régler). Rend la photo
/// réglée — rangée dans le dépôt local si elle est nouvelle — ou null si
/// l'utilisateur annule (rien n'est alors gardé).
Future<FondPhoto?> ouvrirEditeurFond(
  BuildContext context, {
  required ServiceFonds fonds,
  Uint8List? octets,
  FondPhoto? existante,
}) {
  assert(octets != null || existante != null);
  return Navigator.of(context, rootNavigator: true).push<FondPhoto>(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) =>
          EditeurFondPage(fonds: fonds, octets: octets, existante: existante),
      transitionsBuilder: (_, animation, _, enfant) {
        final courbe = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: courbe,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(courbe),
            child: enfant,
          ),
        );
      },
    ),
  );
}

/// Éditeur plein écran d'un fond photo : grand aperçu (la vraie taille de
/// l'écran, réduite), conversation de démonstration par-dessus (jamais
/// ajoutée à l'historique), cadrage au doigt (glisser, pincer, double
/// toucher = cadrage d'origine), visibilité, flou, assombrissement.
class EditeurFondPage extends StatefulWidget {
  const EditeurFondPage({
    super.key,
    required this.fonds,
    this.octets,
    this.existante,
  });

  final ServiceFonds fonds;
  final Uint8List? octets;
  final FondPhoto? existante;

  @override
  State<EditeurFondPage> createState() => _EditeurFondPageState();
}

class _EditeurFondPageState extends State<EditeurFondPage> {
  late ReglagesPhoto _r = widget.existante?.reglages ?? ReglagesPhoto.parDefaut;
  ui.Image? _image;
  String? _erreur;
  bool _enregistrement = false;

  // Geste en cours : zoom et décalage au début, point de départ.
  double _zoomDepart = 1;
  Offset _decalageDepart = Offset.zero;
  Offset _focalDepart = Offset.zero;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final octets =
        widget.octets ?? await widget.fonds.depot.lire(widget.existante!.id);
    if (octets == null) {
      if (mounted) {
        setState(() => _erreur = 'Photo introuvable sur l’appareil.');
      }
      return;
    }
    if (octets.length > DepotFondsPhoto.tailleMax) {
      if (mounted) {
        setState(() => _erreur = 'Photo trop lourde (25 Mo au plus).');
      }
      return;
    }
    final image = await decoderFondPhoto(octets, coteMax: 1600);
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      if (image == null) _erreur = 'Format d’image non pris en charge.';
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size get _ecran {
    final vue = View.of(context);
    return vue.physicalSize / vue.devicePixelRatio;
  }

  Size get _source => Size(_image!.width.toDouble(), _image!.height.toDouble());

  void _debutGeste(ScaleStartDetails d) {
    _zoomDepart = _r.zoom;
    _decalageDepart = _r.decalage;
    _focalDepart = d.localFocalPoint;
  }

  void _geste(ScaleUpdateDetails d) {
    if (_image == null) return;
    final ecran = _ecran;
    final zoom = (_zoomDepart * d.scale).clamp(1.0, ReglagesPhoto.zoomMax);
    final glisse = d.localFocalPoint - _focalDepart;
    final decalage = limiterDecalage(
      _decalageDepart +
          Offset(glisse.dx / ecran.width, glisse.dy / ecran.height),
      _source,
      ecran,
      zoom,
    );
    setState(() => _r = _r.copyWith(zoom: zoom, decalage: decalage));
  }

  void _reinitialiser() => setState(() => _r = ReglagesPhoto.parDefaut);

  Future<void> _appliquer() async {
    if (_image == null || _enregistrement) return;
    setState(() => _enregistrement = true);
    try {
      final existante = widget.existante;
      final photo = existante != null && widget.octets == null
          ? existante.avec(_r)
          : FondPhoto(
              id: await widget.fonds.importer(widget.octets!),
              reglages: _r,
            );
      if (mounted) Navigator.of(context).pop(photo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = e is FormatException
            ? e.message
            : 'La photo n’a pas pu être enregistrée.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ecran = _ecran;
    return Scaffold(
      backgroundColor: CouleursJarvis.ivoire,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Annuler',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: CouleursJarvis.texte,
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Personnaliser le fond',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: policeAffichage,
                        fontSize: 19,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _image == null ? null : _reinitialiser,
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursJarvis.signal,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Réinitialiser'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: ecran.width / ecran.height,
                    child: _apercu(ecran),
                  ),
                ),
              ),
            ),
            if (_erreur case final e?)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: NoteReglage(e),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  CurseurReglage(
                    titre: 'Visibilité de la photo',
                    valeurAffichee: '${(_r.visibilite * 100).round()} %',
                    valeur: _r.visibilite,
                    min: ReglagesPhoto.visibiliteMin,
                    max: 1,
                    divisions: 17,
                    surChangement: _image == null
                        ? null
                        : (v) =>
                              setState(() => _r = _r.copyWith(visibilite: v)),
                  ),
                  CurseurReglage(
                    titre: 'Flou de l’arrière-plan',
                    valeurAffichee: _r.flou < 0.5
                        ? 'Net'
                        : '${(_r.flou / ReglagesPhoto.flouMax * 100).round()} %',
                    valeur: _r.flou,
                    min: 0,
                    max: ReglagesPhoto.flouMax,
                    divisions: 24,
                    surChangement: _image == null
                        ? null
                        : (v) => setState(() => _r = _r.copyWith(flou: v)),
                  ),
                  CurseurReglage(
                    titre: 'Assombrissement',
                    valeurAffichee:
                        '${(_r.assombrissement / ReglagesPhoto.assombrissementMax * 100).round()} %',
                    valeur: _r.assombrissement,
                    min: 0,
                    max: ReglagesPhoto.assombrissementMax,
                    divisions: 14,
                    surChangement: _image == null
                        ? null
                        : (v) => setState(
                            () => _r = _r.copyWith(assombrissement: v),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CouleursJarvis.texte,
                        side: BorderSide(color: CouleursJarvis.trait),
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _image == null || _enregistrement
                          ? null
                          : _appliquer,
                      style: FilledButton.styleFrom(
                        backgroundColor: CouleursJarvis.signal,
                        foregroundColor: CouleursJarvis.surSignal,
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(
                        _enregistrement ? 'Application…' : 'Appliquer',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aperçu : l'écran à sa vraie taille (photo, flou, voile, bulles),
  /// réduit pour tenir dans le cadre.
  Widget _apercu(Size ecran) {
    final image = _image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CouleursJarvis.ivoire,
          border: Border.all(color: CouleursJarvis.trait),
          borderRadius: BorderRadius.circular(20),
        ),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: ecran,
            child: image == null
                ? Center(
                    child: _erreur == null
                        ? CircularProgressIndicator(
                            color: CouleursJarvis.signal,
                          )
                        : Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: CouleursJarvis.texteSecondaire,
                          ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _debutGeste,
                    onScaleUpdate: _geste,
                    onDoubleTap: () => setState(() => _r = _r.cadrageInitial),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          enabled: _r.flou > 0.05,
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: _r.flou,
                            sigmaY: _r.flou,
                            tileMode: TileMode.clamp,
                          ),
                          child: Opacity(
                            opacity: _r.visibilite,
                            child: CustomPaint(
                              painter: _PeintrePhoto(image, _r),
                            ),
                          ),
                        ),
                        ColoredBox(
                          color: Color.fromRGBO(
                            0,
                            0,
                            0,
                            _r.assombrissement * _r.visibilite,
                          ),
                        ),
                        const IgnorePointer(child: _ConversationDemo()),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PeintrePhoto extends CustomPainter {
  const _PeintrePhoto(this.image, this.r);

  final ui.Image image;
  final ReglagesPhoto r;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      Offset.zero & src,
      rectanglePhoto(src, size, r),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PeintrePhoto ancien) =>
      !identical(ancien.image, image) ||
      ancien.r.zoom != r.zoom ||
      ancien.r.decalage != r.decalage;
}

/// Conversation de démonstration (jamais enregistrée) : on juge la
/// lisibilité des bulles sur la photo.
class _ConversationDemo extends StatelessWidget {
  const _ConversationDemo();

  @override
  Widget build(BuildContext context) {
    final p = PaletteJarvis.of(context);
    final id = p.identite;
    Widget bulle(String texte, {required bool moi}) => Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: moi ? p.bulleUtilisateur : p.carteJarvis,
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(moi ? 20 : 6),
            topRight: Radius.circular(moi ? 20 : 20),
            bottomLeft: const Radius.circular(20),
            bottomRight: Radius.circular(moi ? 6 : 20),
          ),
          border: Border.all(
            color: moi ? p.bordBulle : p.trait.withValues(alpha: 0.6),
            width: id.marquee ? id.contour : 1,
          ),
          boxShadow: [
            if ((moi ? id.ombreBulle : id.ombreCarte) case final o?)
              BoxShadow(color: o, offset: const Offset(4, 4))
            else
              BoxShadow(
                color: p.ombre.withAlpha(0x10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Text(
          texte,
          style: TextStyle(fontSize: 15, height: 1.45, color: p.texte),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 90, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bulle('Bonjour JARVIS', moi: true),
          bulle('Bonjour ! Comment puis-je t’aider ?', moi: false),
          bulle('Tu peux m’aider à répondre à Sarah ?', moi: true),
        ],
      ),
    );
  }
}
