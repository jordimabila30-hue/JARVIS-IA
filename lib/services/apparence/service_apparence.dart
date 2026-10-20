import 'package:flutter/widgets.dart';

import '../../models/apparence/preferences_apparence.dart';
import '../../theme/motifs_jarvis.dart';
import '../../theme/palette_jarvis.dart';
import '../../theme/styles_jarvis.dart';
import '../voice_settings_service.dart';

/// Apparence de JARVIS : source de vérité des préférences (mode, style,
/// motif, intensité), enregistrées sur l'appareil (même stockage que les
/// autres réglages, clé [cleStockage]). Un choix s'applique tout de suite,
/// sans redémarrage, puis est écrit. Une seule instance (`JarvisApp`),
/// atteinte par [ServiceApparence.of].
class ServiceApparence extends ChangeNotifier {
  ServiceApparence({StockageReglages? stockage, Brightness? luminositeSysteme})
    : _stockage = stockage ?? const StockagePreferences(cle: cleStockage),
      _systeme = luminositeSysteme ?? Brightness.light {
    _publier();
  }

  static const cleStockage = 'jarvis.apparence';

  final StockageReglages _stockage;

  PreferencesApparence get preferences => _prefs;
  PreferencesApparence _prefs = PreferencesApparence.parDefaut;

  ModeAffichage get mode => _prefs.mode;
  StyleVisuel get style => _prefs.style;
  MotifJarvis get motif => _prefs.motif;
  double get intensite => _prefs.intensite;

  /// Luminosité demandée par le système (mode « Système »).
  Brightness get luminositeSysteme => _systeme;
  Brightness _systeme;
  set luminositeSysteme(Brightness b) {
    if (b == _systeme) return;
    final avant = palette;
    _systeme = b;
    if (_prefs.mode == ModeAffichage.systeme) _changer(_prefs, avant: avant);
  }

  /// Luminosité réellement affichée.
  Brightness get luminosite => switch (_prefs.mode) {
    ModeAffichage.clair => Brightness.light,
    ModeAffichage.sombre => Brightness.dark,
    ModeAffichage.systeme => _systeme,
  };

  PaletteJarvis get palette => _prefs.style.palette(luminosite);

  /// Change à chaque nouvelle palette affichée (pas pour le motif).
  int get versionPalette => _versionPalette;
  int _versionPalette = 0;

  bool _charge = false;
  bool get charge => _charge;

  /// Lit les préférences enregistrées (valeurs par défaut si absentes ou
  /// illisibles : jamais d'erreur).
  Future<void> charger() async {
    String? texte;
    try {
      texte = await _stockage.lire();
    } catch (e) {
      debugPrint('[JARVIS Apparence] préférences illisibles : $e');
    }
    _charge = true;
    _changer(PreferencesApparence.decoder(texte));
  }

  Future<void> choisirMode(ModeAffichage m) =>
      _choisir(_prefs.copyWith(mode: m));

  Future<void> choisirStyle(StyleVisuel s) =>
      _choisir(_prefs.copyWith(style: s));

  Future<void> choisirMotif(MotifJarvis m) =>
      _choisir(_prefs.copyWith(motif: m));

  /// Intensité du motif : affichée à chaque mouvement du curseur
  /// ([enregistrer] faux), écrite au relâchement.
  Future<void> reglerIntensite(double v, {bool enregistrer = true}) async {
    _changer(_prefs.copyWith(intensite: v));
    if (enregistrer) await _ecrire();
  }

  /// Revient à des préférences données (« Revenir au choix précédent »).
  Future<void> restaurer(PreferencesApparence p) => _choisir(p);

  Future<void> _choisir(PreferencesApparence p) async {
    if (p == _prefs) return;
    _changer(p);
    await _ecrire();
  }

  Future<void> _ecrire() async {
    try {
      await _stockage.ecrire(_prefs.encoder());
    } catch (e) {
      debugPrint('[JARVIS Apparence] préférences non enregistrées : $e');
    }
  }

  void _changer(PreferencesApparence p, {PaletteJarvis? avant}) {
    avant ??= palette;
    _prefs = p;
    _publier();
    if (!identical(avant, palette)) _versionPalette++;
    notifyListeners();
  }

  /// La façade `CouleursJarvis` suit la palette affichée.
  void _publier() => PaletteJarvis.active = palette;

  /// Service de l'application (null hors `PorteeApparence`, ex. tests).
  static ServiceApparence? of(BuildContext context, {bool ecouter = true}) =>
      ecouter
      ? context.dependOnInheritedWidgetOfExactType<PorteeApparence>()?.notifier
      : context.getInheritedWidgetOfExactType<PorteeApparence>()?.notifier;
}

/// Rend le [ServiceApparence] accessible à tout l'arbre ; les widgets qui
/// le lisent par [ServiceApparence.of] sont reconstruits à chaque
/// changement.
class PorteeApparence extends InheritedNotifier<ServiceApparence> {
  const PorteeApparence({
    super.key,
    required ServiceApparence service,
    required super.child,
  }) : super(notifier: service);
}
