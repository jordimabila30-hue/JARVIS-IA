/// Taille d'un fichier en français : « 840 octets », « 12,4 Ko »,
/// « 3,1 Mo », « 1,2 Go » (unités de 1 024).
String tailleLisible(int octets) {
  if (octets < 1024) return octets <= 1 ? '$octets octet' : '$octets octets';
  const unites = ['Ko', 'Mo', 'Go', 'To'];
  var valeur = octets / 1024;
  var i = 0;
  while (valeur >= 1024 && i < unites.length - 1) {
    valeur /= 1024;
    i++;
  }
  // Une décimale sous 100 (« 12,4 Mo »), aucune au-delà (« 512 Mo »).
  final texte = valeur < 100
      ? valeur.toStringAsFixed(1).replaceAll('.', ',')
      : valeur.round().toString();
  return '${texte.endsWith(',0') ? texte.substring(0, texte.length - 2) : texte} ${unites[i]}';
}
