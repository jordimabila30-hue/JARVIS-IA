import '../../models/importation/export_whatsapp.dart';

/// Ce que révèlent les premiers octets d'un fichier.
enum NatureContenu { vide, zip, zipVide, texte, binaire }

/// Ce qu'annonce une métadonnée (extension du nom, type MIME).
enum _Indice { zip, texte, autre, aucun }

/// Format d'un fichier reçu, ou la raison de son refus.
///
/// Le contenu réel prime : une archive ZIP est reconnue à sa signature,
/// un texte à l'absence d'octets binaires. Le nom et le type MIME, parfois
/// absents ou faux (partages Android, fichiers renommés), ne servent qu'à
/// départager et à expliquer un refus.
({FormatExportWhatsApp? format, ErreurSelectionExport? erreur}) detecterFormat({
  required String nom,
  String? typeMime,
  required List<int> debut,
  required bool fichierEntier,
}) {
  final nature = natureDuContenu(debut, fichierEntier: fichierEntier);
  final extension = _indiceExtension(nom);
  final mime = _indiceMime(typeMime);
  bool annonce(_Indice i) => extension == i || mime == i;

  ({FormatExportWhatsApp? format, ErreurSelectionExport? erreur}) refus(
    ErreurSelectionExport e,
  ) => (format: null, erreur: e);
  ({FormatExportWhatsApp? format, ErreurSelectionExport? erreur}) ok(
    FormatExportWhatsApp f,
  ) => (format: f, erreur: null);

  switch (nature) {
    case NatureContenu.vide:
    case NatureContenu.zipVide:
      return refus(ErreurSelectionExport.fichierVide);
    case NatureContenu.zip:
      return ok(FormatExportWhatsApp.zip);
    case NatureContenu.texte:
      if (annonce(_Indice.zip)) {
        return refus(ErreurSelectionExport.archiveEndommagee);
      }
      if (annonce(_Indice.texte)) return ok(FormatExportWhatsApp.txt);
      if (annonce(_Indice.autre)) {
        return refus(ErreurSelectionExport.formatNonPrisEnCharge);
      }
      // Ni nom parlant ni type : le contenu, du texte, suffit.
      return ok(FormatExportWhatsApp.txt);
    case NatureContenu.binaire:
      if (annonce(_Indice.zip)) {
        return refus(ErreurSelectionExport.archiveEndommagee);
      }
      if (annonce(_Indice.texte)) {
        return refus(ErreurSelectionExport.texteIllisible);
      }
      return refus(ErreurSelectionExport.formatNonPrisEnCharge);
  }
}

/// Nature des premiers octets. [fichierEntier] : [debut] contient tout le
/// fichier (un fichier fait de blancs est alors vide).
NatureContenu natureDuContenu(List<int> debut, {required bool fichierEntier}) {
  if (debut.isEmpty) return NatureContenu.vide;
  bool commencePar(List<int> signature) {
    if (debut.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (debut[i] != signature[i]) return false;
    }
    return true;
  }

  if (commencePar(const [0x50, 0x4B, 0x03, 0x04])) return NatureContenu.zip;
  if (commencePar(const [0x50, 0x4B, 0x05, 0x06])) return NatureContenu.zipVide;
  // Texte UTF-16 (marque d'ordre des octets).
  if (commencePar(const [0xFF, 0xFE]) || commencePar(const [0xFE, 0xFF])) {
    return NatureContenu.texte;
  }
  // Texte : aucun octet nul, presque aucun caractère de contrôle (hors
  // tabulation, retours à la ligne, saut de page, échappement).
  var controles = 0;
  for (final o in debut) {
    if (o == 0) return NatureContenu.binaire;
    if (o < 0x20 && o != 0x09 && o != 0x0A && o != 0x0D && o != 0x0C) {
      if (o != 0x1B) controles++;
    }
  }
  if (controles * 50 > debut.length) return NatureContenu.binaire;
  const blancs = {0x09, 0x0A, 0x0C, 0x0D, 0x20, 0xEF, 0xBB, 0xBF};
  if (fichierEntier && debut.every(blancs.contains)) return NatureContenu.vide;
  return NatureContenu.texte;
}

_Indice _indiceExtension(String nom) {
  final point = nom.lastIndexOf('.');
  if (point < 0 || point == nom.length - 1) return _Indice.aucun;
  return switch (nom.substring(point + 1).toLowerCase()) {
    'zip' => _Indice.zip,
    'txt' => _Indice.texte,
    // Pas une extension (« Discussion avec M. Dupont ») : on l'ignore.
    final e when e.contains(' ') || e.length > 5 => _Indice.aucun,
    _ => _Indice.autre,
  };
}

_Indice _indiceMime(String? mime) {
  final m = mime?.toLowerCase().split(';').first.trim() ?? '';
  return switch (m) {
    '' ||
    'application/octet-stream' ||
    'application/binary' ||
    '*/*' => _Indice.aucun,
    'application/zip' ||
    'application/x-zip' ||
    'application/x-zip-compressed' ||
    'application/zip-compressed' => _Indice.zip,
    'text/plain' => _Indice.texte,
    _ => _Indice.autre,
  };
}
