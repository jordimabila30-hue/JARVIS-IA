import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_jarvis.dart';
import '../utils/version_jarvis.dart';

/// Écran affiché au démarrage de JARVIS.
///
/// Déroulé :
/// 1. une légère lueur apparaît au centre ;
/// 2. les anneaux HUD se tracent, les graduations se mettent à tourner ;
/// 3. les lettres J-A-R-V-I-S se décodent en 3D puis se verrouillent ;
/// 4. flash de verrouillage, l'arc de progression se remplit ;
/// 5. la version apparaît discrètement en bas.
class EcranDeLancement extends StatefulWidget {
  const EcranDeLancement({super.key, this.onTermine});

  /// Appelé à la fin de l'animation (servira à aller vers la page suivante).
  final VoidCallback? onTermine;

  @override
  State<EcranDeLancement> createState() => _EcranDeLancementState();
}

class _EcranDeLancementState extends State<EcranDeLancement>
    with TickerProviderStateMixin {
  static const _nom = 'JARVIS';

  // Version réellement construite (pubspec.yaml), jamais écrite à la main.
  static final _version = VersionJarvis.courte;

  static Color get _bleu => CouleursJarvis.signal;
  static const _dureeMs = 3200;

  /// Déroulé principal, joué une seule fois.
  late final AnimationController _sequence;

  /// Rotation lente et continue des graduations.
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _sequence =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: _dureeMs),
          )
          ..addStatusListener((statut) {
            if (statut == AnimationStatus.completed) _terminer();
          })
          ..forward();

    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  bool _termine = false;

  /// Fin de l'animation, ou appui pour passer : la suite (session vérifiée
  /// comme d'habitude) n'est demandée qu'une fois.
  void _terminer() {
    if (_termine) return;
    _termine = true;
    widget.onTermine?.call();
  }

  @override
  void dispose() {
    _sequence.dispose();
    _rotation.dispose();
    super.dispose();
  }

  /// Progression (0 → 1) d'une étape située entre [debut] et [fin]
  /// du déroulé principal.
  double _etape(double debut, double fin, [Curve courbe = Curves.linear]) {
    final t = ((_sequence.value - debut) / (fin - debut)).clamp(0.0, 1.0);
    return courbe.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // Un appui passe l'animation (rien d'autre ne change).
        behavior: HitTestBehavior.opaque,
        onTap: _terminer,
        child: Semantics(
          button: true,
          label: 'Passer l’animation de lancement',
          child: FondJarvis(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, contraintes) {
                  final cote = math.min(
                    contraintes.maxWidth,
                    contraintes.maxHeight,
                  );
                  final diametre = math.min(cote * 0.8, 520.0);
                  final tailleTexte = diametre * 0.13;

                  return AnimatedBuilder(
                    animation: Listenable.merge([_sequence, _rotation]),
                    builder: (context, _) {
                      // Flash au moment où toutes les lettres sont verrouillées.
                      final flash = math.sin(_etape(0.62, 0.80) * math.pi);
                      final lueur = _etape(0.0, 0.15) * (1 + flash * 0.8);
                      final intensite = 0.8 + 0.2 * flash;

                      // SizedBox.expand : le Stack occupe tout l'écran, ce qui centre
                      // le contenu et place la version tout en bas.
                      return SizedBox.expand(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Lueur centrale.
                            SizedBox.square(
                              dimension: diametre * 1.3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      CouleursJarvis.violet.withValues(
                                        alpha: 0.16 * lueur,
                                      ),
                                      _bleu.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            RepaintBoundary(
                              child: CustomPaint(
                                size: Size.square(diametre),
                                painter: _AnneauxHud(
                                  traceExterieur: _etape(
                                    0.03,
                                    0.30,
                                    Curves.easeInOutCubic,
                                  ),
                                  traceInterieur: _etape(
                                    0.10,
                                    0.36,
                                    Curves.easeInOutCubic,
                                  ),
                                  graduations: _etape(0.20, 0.40),
                                  progression: _etape(
                                    0.45,
                                    0.88,
                                    Curves.easeInOutCubic,
                                  ),
                                  rotation: _rotation.value,
                                  intensite: intensite,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < _nom.length; i++)
                                  _construireLettre(i, tailleTexte, flash),
                              ],
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 24,
                              child: Opacity(
                                opacity: _etape(0.70, 0.85) * 0.35,
                                child: Text(
                                  _version,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CouleursJarvis.texte,
                                    fontSize: 12,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lettre [index] : invisible, puis en cours de décodage (symboles qui
  /// défilent en pivotant), puis verrouillée sur la vraie lettre.
  Widget _construireLettre(int index, double taille, double flash) {
    const debutDecodage = 0.25;
    final verrouillage = 0.38 + index * 0.045;
    final v = _sequence.value;

    // Largeur fixe par lettre : les symboles qui défilent ne font pas bouger
    // le mot. Le « I », très fin, a une place plus étroite.
    final largeur = taille * (_nom[index] == 'I' ? 0.42 : 0.72);

    final String caractere;
    final double angle;
    final Color couleur;
    final double halo;

    if (v < debutDecodage) {
      return _Lettre3D.vide(taille: taille, largeur: largeur);
    } else if (v < verrouillage) {
      // Un nouveau symbole toutes les 70 ms.
      final ms = v * _dureeMs;
      final cycle = (ms / 70).floor();
      final local = (ms % 70) / 70;
      caractere = _symbole(cycle, index);
      angle = (local - 0.5) * math.pi * 0.8;
      couleur = _bleu.withValues(alpha: 0.85);
      halo = 0.4;
    } else {
      final p = _etape(verrouillage, verrouillage + 0.08, Curves.easeOutBack);
      caractere = _nom[index];
      angle = (1 - p) * -math.pi / 2;
      couleur = CouleursJarvis.texte;
      halo = 0.35 + 0.65 * flash;
    }

    return _Lettre3D(
      caractere: caractere,
      angle: angle,
      couleur: couleur,
      halo: halo,
      taille: taille,
      largeur: largeur,
    );
  }

  /// Symbole pseudo-aléatoire mais stable pour un cycle et une lettre donnés
  /// (évite d'utiliser Random pendant le build).
  static String _symbole(int cycle, int index) {
    const symboles = '01<>/#%&\$@ABCDEFGHKLMNPQRTUWXYZ';
    final n = (cycle * 7 + index * 13 + (cycle * cycle) % 11) % symboles.length;
    return symboles[n];
  }
}

/// Une lettre qui pivote en 3D autour de son axe horizontal.
class _Lettre3D extends StatelessWidget {
  const _Lettre3D({
    required this.caractere,
    required this.angle,
    required this.couleur,
    required this.halo,
    required this.taille,
    required this.largeur,
  });

  const _Lettre3D.vide({required this.taille, required this.largeur})
    : caractere = '',
      angle = 0,
      couleur = Colors.transparent,
      halo = 0;

  final String caractere;
  final double angle;
  final Color couleur;
  final double halo;
  final double taille;
  final double largeur;

  @override
  Widget build(BuildContext context) {
    // OverflowBox : un symbole plus large que la place réservée (pendant le
    // décodage) déborde au lieu d'être coupé.
    return SizedBox(
      width: largeur,
      height: taille * 1.2,
      child: OverflowBox(
        maxWidth: taille * 1.5,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002) // perspective
            ..rotateX(angle),
          child: Text(
            caractere,
            style: TextStyle(
              color: couleur,
              fontSize: taille,
              fontWeight: FontWeight.w700,
              height: 1,
              shadows: [
                Shadow(
                  color: CouleursJarvis.violet.withValues(alpha: 0.45 * halo),
                  blurRadius: taille * 0.35 * halo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Anneaux façon interface HUD : deux anneaux tracés, un arc de progression,
/// des graduations et trois segments de viseur qui tournent lentement.
class _AnneauxHud extends CustomPainter {
  _AnneauxHud({
    required this.traceExterieur,
    required this.traceInterieur,
    required this.graduations,
    required this.progression,
    required this.rotation,
    required this.intensite,
  });

  static Color get _bleu => CouleursJarvis.signal;
  static const _tour = 2 * math.pi;
  static const _haut = -math.pi / 2;

  final double traceExterieur;
  final double traceInterieur;
  final double graduations;
  final double progression;
  final double rotation;
  final double intensite;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.width / 2;
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Rect cercle(double rayon) => Rect.fromCircle(center: centre, radius: rayon);

    // Anneau extérieur, tracé dans le sens horaire.
    trait
      ..color = _bleu.withValues(alpha: 0.55 * intensite)
      ..strokeWidth = 1.5;
    canvas.drawArc(
      cercle(r * 0.96),
      _haut,
      _tour * traceExterieur,
      false,
      trait,
    );

    // Anneau intérieur, tracé dans le sens inverse.
    trait
      ..color = _bleu.withValues(alpha: 0.35 * intensite)
      ..strokeWidth = 1;
    canvas.drawArc(
      cercle(r * 0.74),
      _haut,
      -_tour * traceInterieur,
      false,
      trait,
    );

    // Arc de progression.
    if (progression > 0) {
      trait
        ..color = _bleu.withValues(alpha: 0.9 * intensite)
        ..strokeWidth = 3;
      canvas.drawArc(
        cercle(r * 0.80),
        _haut,
        _tour * progression,
        false,
        trait,
      );
    }

    if (graduations <= 0) return;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    // Graduations, une plus longue tous les 30°.
    canvas.save();
    canvas.rotate(rotation * _tour);
    final graduation = Paint()
      ..strokeWidth = 1
      ..color = _bleu.withValues(alpha: 0.45 * graduations * intensite);
    for (var i = 0; i < 72; i++) {
      final a = i * _tour / 72;
      final direction = Offset(math.cos(a), math.sin(a));
      final interieur = i % 6 == 0 ? 0.85 : 0.875;
      canvas.drawLine(
        direction * (r * interieur),
        direction * (r * 0.90),
        graduation,
      );
    }
    canvas.restore();

    // Segments de viseur, en sens inverse et un peu plus vite.
    canvas.rotate(-rotation * _tour * 1.5);
    trait
      ..color = _bleu.withValues(alpha: 0.6 * graduations * intensite)
      ..strokeWidth = 2;
    for (var k = 0; k < 3; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 0.99),
        k * _tour / 3,
        math.pi / 6,
        false,
        trait,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnneauxHud ancien) =>
      ancien.traceExterieur != traceExterieur ||
      ancien.traceInterieur != traceInterieur ||
      ancien.graduations != graduations ||
      ancien.progression != progression ||
      ancien.rotation != rotation ||
      ancien.intensite != intensite;
}
