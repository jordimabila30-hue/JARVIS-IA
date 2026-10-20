import 'package:flutter/material.dart';

import 'palette_jarvis.dart';

/// Registre des styles visuels. Le style choisit les couleurs et la
/// personnalité de l'interface ; le mode (clair / sombre / système) choisit
/// la variante. Les six styles importés reprennent les jetons exacts de
/// l'application source (`www/index.html`, `:root[data-jt=…]`) pour leur
/// variante d'origine ; l'autre variante est créée dans le même esprit
/// (mêmes accents vifs pour la frise et les ombres décoratives, accents
/// d'action foncés ou éclaircis pour rester lisibles).
enum StyleVisuel {
  jarvis(
    'JARVIS original',
    'Ivoire, graphite et bleu-violet : l’identité de JARVIS.',
  ),
  congotronics('Congotronics', 'La nuit de Kin, la tradition branchée.'),
  raphiaKuba('Raphia Kuba', 'Le tissu des rois kuba, en plein jour.'),
  fleuve('Fleuve', 'Le fleuve Congo au crépuscule.'),
  sape('La Sape', 'L’élégance des sapeurs.'),
  rumba('Rumba', 'Les soirées de Kin, patrimoine UNESCO.'),
  leopards('Léopards', 'Bleu ciel, étoile jaune, comme au stade.');

  const StyleVisuel(this.nom, this.description);

  final String nom;
  final String description;

  /// Variante d'origine dans l'application source (null : JARVIS).
  Brightness? get varianteSource => switch (this) {
    StyleVisuel.jarvis => null,
    StyleVisuel.raphiaKuba => Brightness.light,
    _ => Brightness.dark,
  };

  PaletteJarvis palette(Brightness luminosite) =>
      luminosite == Brightness.dark ? _sombres[this]! : _claires[this]!;

  static StyleVisuel depuisNom(String? nom) =>
      values.asNameMap()[nom] ?? StyleVisuel.jarvis;
}

// --- Frises (ordre de la source : acc3, acc, acc2), toujours vives -------

const _friseCongo = [Color(0xFFD2452F), Color(0xFFF4B400), Color(0xFF22C3BC)];
const _friseKuba = [Color(0xFFC98A1A), Color(0xFFA8321F), Color(0xFF23170F)];
const _friseFleuve = [Color(0xFFE2734A), Color(0xFFF2C14E), Color(0xFF3FC1B0)];
const _friseSape = [Color(0xFF9B7BFF), Color(0xFFF2A7C3), Color(0xFFD9B44A)];
const _friseRumba = [Color(0xFFB8325A), Color(0xFFF0B24A), Color(0xFFFF7B5C)];
const _friseLeopards = [
  Color(0xFFE3152A),
  Color(0xFFF7D618),
  Color(0xFF4DB3FF),
];

final Map<StyleVisuel, PaletteJarvis> _claires = {
  StyleVisuel.jarvis: PaletteJarvis.jarvisClair,
  // Variante créée : Kin en plein jour (papier chaud, encre de nuit).
  StyleVisuel.congotronics: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFF6F2EA),
    deep: const Color(0xFFEDE7DB),
    panel: const Color(0xFFFFFDF8),
    line: const Color(0xFFD3CBBB),
    txt: const Color(0xFF070A12),
    dim: const Color(0xFF4E576C),
    acc: const Color(0xFFB3362A),
    acc2: const Color(0xFF117A74),
    acc3: const Color(0xFF8A6200),
    raf: const Color(0xFF24304A),
    onacc: const Color(0xFFFFFDF8),
    user: const Color(0xFFF1E3C8),
    frise: _friseCongo,
    ombreBulle: const Color(0xFFD2452F),
    ombreCarte: const Color(0xFFF4B400),
  ),
  // Source exacte (data-jt="kuba").
  StyleVisuel.raphiaKuba: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFEFE3C8),
    deep: const Color(0xFFE6D6B4),
    panel: const Color(0xFFF8F0DE),
    line: const Color(0xFFCDB78F),
    txt: const Color(0xFF23170F),
    dim: const Color(0xFF6E5A43),
    acc: const Color(0xFFA8321F),
    acc2: const Color(0xFF23170F),
    acc3: const Color(0xFFC98A1A),
    raf: const Color(0xFF23170F),
    onacc: const Color(0xFFF8F0DE),
    user: const Color(0xFFE2D0A8),
    frise: _friseKuba,
    ombreBulle: const Color(0xFFC98A1A),
    ombreCarte: const Color(0xFFA8321F),
    critique: const Color(0xFF9A6410),
  ),
  // Variante créée : le fleuve au matin (eau claire, sarcelle profonde).
  StyleVisuel.fleuve: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFEEF6F4),
    deep: const Color(0xFFE0EEEA),
    panel: const Color(0xFFFAFDFC),
    line: const Color(0xFFB7D2CC),
    txt: const Color(0xFF0A2429),
    dim: const Color(0xFF46676A),
    acc: const Color(0xFF15766B),
    acc2: const Color(0xFF9A6A12),
    acc3: const Color(0xFFB04A24),
    raf: const Color(0xFF1E4A52),
    onacc: const Color(0xFFFAFDFC),
    user: const Color(0xFFD2E8E3),
    frise: _friseFleuve,
    ombreBulle: const Color(0xFFE2734A),
    ombreCarte: const Color(0xFFF2C14E),
  ),
  // Variante créée : la Sape de jour (rose poudré, prune, or ancien).
  StyleVisuel.sape: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFFBF3F7),
    deep: const Color(0xFFF3E5EE),
    panel: const Color(0xFFFFFCFE),
    line: const Color(0xFFE0C9D7),
    txt: const Color(0xFF2A1631),
    dim: const Color(0xFF6C5375),
    acc: const Color(0xFFA2386A),
    acc2: const Color(0xFF7E5E0E),
    acc3: const Color(0xFF6A4CCB),
    raf: const Color(0xFF4A2F57),
    onacc: const Color(0xFFFFFCFE),
    user: const Color(0xFFF2DCE8),
    frise: _friseSape,
    ombreBulle: const Color(0xFF9B7BFF),
    ombreCarte: const Color(0xFFF2A7C3),
  ),
  // Variante créée : Rumba au soleil couchant (crème rosée, bordeaux).
  StyleVisuel.rumba: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFFBF1EA),
    deep: const Color(0xFFF4E2D6),
    panel: const Color(0xFFFFFBF8),
    line: const Color(0xFFE2C5B6),
    txt: const Color(0xFF2E1217),
    dim: const Color(0xFF6E4842),
    acc: const Color(0xFFA32E4C),
    acc2: const Color(0xFFB64A28),
    acc3: const Color(0xFF8E5C0E),
    raf: const Color(0xFF5A2A33),
    onacc: const Color(0xFFFFFBF8),
    user: const Color(0xFFF5DBD1),
    frise: _friseRumba,
    ombreBulle: const Color(0xFFB8325A),
    ombreCarte: const Color(0xFFF0B24A),
  ),
  // Variante créée : ciel de stade en plein jour (bleu ciel, bleu roi).
  StyleVisuel.leopards: PaletteJarvis.depuisJetons(
    luminosite: Brightness.light,
    bg: const Color(0xFFEEF5FD),
    deep: const Color(0xFFE0ECFA),
    panel: const Color(0xFFFFFFFF),
    line: const Color(0xFFB6CBEA),
    txt: const Color(0xFF072C6B),
    dim: const Color(0xFF3B5888),
    acc: const Color(0xFF0B4FB3),
    acc2: const Color(0xFFC0111F),
    acc3: const Color(0xFF7A6600),
    raf: const Color(0xFF0A3680),
    onacc: const Color(0xFFFFFFFF),
    user: const Color(0xFFD5E5FA),
    frise: _friseLeopards,
    ombreBulle: const Color(0xFFE3152A),
    ombreCarte: const Color(0xFFF7D618),
    critique: const Color(0xFFC0111F),
  ),
};

final Map<StyleVisuel, PaletteJarvis> _sombres = {
  StyleVisuel.jarvis: PaletteJarvis.jarvisSombre,
  // Source exacte (thème par défaut, :root).
  StyleVisuel.congotronics: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF070A12),
    deep: const Color(0xFF0D1322),
    panel: const Color(0xFF141C2F),
    line: const Color(0xFF24304A),
    txt: const Color(0xFFEEF1F8),
    dim: const Color(0xFF8C97B0),
    acc: const Color(0xFFF4B400),
    acc2: const Color(0xFF22C3BC),
    acc3: const Color(0xFFD2452F),
    raf: const Color(0xFFEADCBF),
    onacc: const Color(0xFF070A12),
    user: const Color(0xFF1C2742),
    frise: _friseCongo,
    ombreBulle: const Color(0xFFD2452F),
    ombreCarte: const Color(0xFFF4B400),
    critique: const Color(0xFFE8663D),
  ),
  // Variante créée : raphia à la veillée (brun profond, rouge ocre).
  StyleVisuel.raphiaKuba: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF1C140D),
    deep: const Color(0xFF241A11),
    panel: const Color(0xFF2E2216),
    line: const Color(0xFF4A3824),
    txt: const Color(0xFFF3E7CD),
    dim: const Color(0xFFBBA582),
    acc: const Color(0xFFE4694A),
    acc2: const Color(0xFFEFE3C8),
    acc3: const Color(0xFFD9A033),
    raf: const Color(0xFFEFE3C8),
    onacc: const Color(0xFF1C140D),
    user: const Color(0xFF3A2A1A),
    frise: const [Color(0xFFC98A1A), Color(0xFFA8321F), Color(0xFFEFE3C8)],
    ombreBulle: const Color(0xFFC98A1A),
    ombreCarte: const Color(0xFFA8321F),
  ),
  // Source exacte (data-jt="fleuve").
  StyleVisuel.fleuve: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF061A1E),
    deep: const Color(0xFF0A2429),
    panel: const Color(0xFF10333A),
    line: const Color(0xFF1E4A52),
    txt: const Color(0xFFE8F6F4),
    dim: const Color(0xFF86AFAA),
    acc: const Color(0xFFF2C14E),
    acc2: const Color(0xFF3FC1B0),
    acc3: const Color(0xFFE2734A),
    raf: const Color(0xFFCFE8E2),
    onacc: const Color(0xFF061A1E),
    user: const Color(0xFF12404A),
    frise: _friseFleuve,
    ombreBulle: const Color(0xFFE2734A),
    ombreCarte: const Color(0xFFF2C14E),
  ),
  // Source exacte (data-jt="sape").
  StyleVisuel.sape: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF1A0F1F),
    deep: const Color(0xFF24152B),
    panel: const Color(0xFF2E1B37),
    line: const Color(0xFF4A2F57),
    txt: const Color(0xFFF8EEF6),
    dim: const Color(0xFFB79CB8),
    acc: const Color(0xFFF2A7C3),
    acc2: const Color(0xFFD9B44A),
    acc3: const Color(0xFF9B7BFF),
    raf: const Color(0xFFF8EEF6),
    onacc: const Color(0xFF1A0F1F),
    user: const Color(0xFF3A2245),
    frise: _friseSape,
    ombreBulle: const Color(0xFF9B7BFF),
    ombreCarte: const Color(0xFFF2A7C3),
    critique: const Color(0xFFD9B44A),
  ),
  // Source exacte (data-jt="rumba").
  StyleVisuel.rumba: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF220C10),
    deep: const Color(0xFF2E1217),
    panel: const Color(0xFF3A1820),
    line: const Color(0xFF5A2A33),
    txt: const Color(0xFFFBEFE6),
    dim: const Color(0xFFC9A39A),
    acc: const Color(0xFFF0B24A),
    acc2: const Color(0xFFFF7B5C),
    acc3: const Color(0xFFB8325A),
    raf: const Color(0xFFFBEFE6),
    onacc: const Color(0xFF220C10),
    user: const Color(0xFF47202A),
    frise: _friseRumba,
    ombreBulle: const Color(0xFFB8325A),
    ombreCarte: const Color(0xFFF0B24A),
    critique: const Color(0xFFFF7B5C),
  ),
  // Source exacte (data-jt="leopards").
  StyleVisuel.leopards: PaletteJarvis.depuisJetons(
    luminosite: Brightness.dark,
    bg: const Color(0xFF072C6B),
    deep: const Color(0xFF0A3680),
    panel: const Color(0xFF0F428F),
    line: const Color(0xFF2B5EAD),
    txt: const Color(0xFFFFFFFF),
    dim: const Color(0xFFAFC8F2),
    acc: const Color(0xFFF7D618),
    acc2: const Color(0xFF4DB3FF),
    acc3: const Color(0xFFE3152A),
    raf: const Color(0xFFFFFFFF),
    onacc: const Color(0xFF072C6B),
    user: const Color(0xFF144C9E),
    frise: _friseLeopards,
    ombreBulle: const Color(0xFFE3152A),
    ombreCarte: const Color(0xFFF7D618),
    critique: const Color(0xFFFF6B5E),
  ),
};
