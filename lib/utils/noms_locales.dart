/// Nom lisible d'une locale : « fr-CA » → « Français (Canada) ». Un code
/// inconnu est affiché tel quel.
String nomLocale(String locale) {
  final parties = locale.split('-');
  final langue = _langues[parties.first] ?? parties.first;
  if (parties.length < 2) return langue;
  final region = _regions[parties[1]] ?? parties[1];
  return '$langue ($region)';
}

/// Nom d'une langue : « fr » → « Français ».
String nomLangue(String code) => _langues[code] ?? code;

/// Région d'une locale : « fr-CA » → « Canada » ; vide sans région.
String nomRegion(String locale) {
  final parties = locale.split('-');
  if (parties.length < 2) return '';
  return _regions[parties[1]] ?? parties[1];
}

const _langues = {
  'fr': 'Français',
  'en': 'Anglais',
  'es': 'Espagnol',
  'de': 'Allemand',
  'it': 'Italien',
  'pt': 'Portugais',
  'nl': 'Néerlandais',
  'ar': 'Arabe',
  'zh': 'Chinois',
  'ja': 'Japonais',
  'ko': 'Coréen',
  'ru': 'Russe',
  'pl': 'Polonais',
  'tr': 'Turc',
  'sv': 'Suédois',
  'da': 'Danois',
  'nb': 'Norvégien',
  'fi': 'Finnois',
  'el': 'Grec',
  'hi': 'Hindi',
  'id': 'Indonésien',
  'he': 'Hébreu',
  'cs': 'Tchèque',
  'ro': 'Roumain',
  'hu': 'Hongrois',
  'uk': 'Ukrainien',
  'th': 'Thaï',
  'vi': 'Vietnamien',
};

const _regions = {
  'FR': 'France',
  'BE': 'Belgique',
  'CA': 'Canada',
  'CH': 'Suisse',
  'LU': 'Luxembourg',
  'US': 'États-Unis',
  'GB': 'Royaume-Uni',
  'AU': 'Australie',
  'IE': 'Irlande',
  'IN': 'Inde',
  'NZ': 'Nouvelle-Zélande',
  'ZA': 'Afrique du Sud',
  'ES': 'Espagne',
  'MX': 'Mexique',
  'AR': 'Argentine',
  'DE': 'Allemagne',
  'AT': 'Autriche',
  'IT': 'Italie',
  'PT': 'Portugal',
  'BR': 'Brésil',
  'NL': 'Pays-Bas',
  'CN': 'Chine',
  'TW': 'Taïwan',
  'HK': 'Hong Kong',
  'JP': 'Japon',
  'KR': 'Corée',
  'RU': 'Russie',
  'SA': 'Arabie saoudite',
  'MA': 'Maroc',
  'SN': 'Sénégal',
  'CI': 'Côte d’Ivoire',
  'CM': 'Cameroun',
  'CD': 'RD Congo',
};
