import '../models/voice_settings.dart';
import 'noms_locales.dart';

/// Noms de voix lisibles : « Microsoft Denise Online (Natural) - French
/// (France) » devient « Denise ». Pas d'éditeur, de code de langue ni de
/// mention technique.

final _editeur = RegExp(
  r'^(Microsoft|Google|Apple|Samsung|Amazon)\s+',
  caseSensitive: false,
);
final _coupure = RegExp(r'\s+[-–—]\s+|\s*\(');
final _mentions = RegExp(
  r'\b(Online|Multilingual|Multilingue|Natural|Neural|Desktop)\b',
  caseSensitive: false,
);
// Identifiant système (Android : « fr-fr-x-frd-local », « fr-FR-language »).
final _technique = RegExp(
  r'^[a-z]{2,3}[-_][a-z]{2}([-_]|$)',
  caseSensitive: false,
);
final _naturelle = RegExp(
  r'natural|neural|enhanced|premium',
  caseSensitive: false,
);

/// Prénom ou nom court de la voix ; chaîne vide si le nom n'est qu'un
/// identifiant technique.
String nomCourtVoix(String nom) {
  if (_technique.hasMatch(nom)) return '';
  final coupe = nom.split(_coupure).first.trim();
  final sansEditeur = coupe.replaceFirst(_editeur, '');
  final court = sansEditeur
      .replaceAll(_mentions, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // « Google français » : sans l'éditeur, il ne resterait que la langue.
  if (court.isEmpty || court[0] != court[0].toUpperCase()) return coupe;
  return court;
}

/// Voix de haute qualité (voix « naturelles » ou améliorées).
bool voixNaturelle(VoixDisponible v) =>
    _naturelle.hasMatch('${v.nom} ${v.qualite ?? ''}');

/// Identifiant stable d'une voix (le nom seul peut exister dans plusieurs
/// régions).
String idVoix(VoixDisponible v) => '${v.locale}|${v.nom}';

/// Libellés courts pour une liste de voix d'une même langue, région
/// principale en tête : le nom, la région seulement pour les autres
/// régions (« Sylvie · Canada »), « Naturelle » pour les voix de haute
/// qualité. Deux libellés ne sont jamais identiques.
Map<String, String> libellesVoix(List<VoixDisponible> voix) {
  final principale = voix.isEmpty ? null : voix.first.locale;
  final libelles = <String, String>{};
  final vus = <String, int>{};
  var anonymes = 0;
  for (final v in voix) {
    var nom = nomCourtVoix(v.nom);
    if (nom.isEmpty) nom = 'Voix ${++anonymes}';
    final details = [
      if (v.locale != principale) nomRegion(v.locale),
      if (voixNaturelle(v)) 'Naturelle',
    ].where((d) => d.isNotEmpty);
    var libelle = [nom, ...details].join(' · ');
    final n = (vus[libelle] ?? 0) + 1;
    vus[libelle] = n;
    if (n > 1) libelle = '$libelle ($n)';
    libelles[idVoix(v)] = libelle;
  }
  return libelles;
}
