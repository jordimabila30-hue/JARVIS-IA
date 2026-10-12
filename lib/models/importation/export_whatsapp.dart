/// Import d'une conversation WhatsApp — étape 1 : le fichier reçu.
///
/// Quelle que soit sa provenance (sélecteur, partage Android,
/// glisser-déposer), un fichier suit le même chemin : réception, contrôle
/// initial, puis « fichier sélectionné ». Rien ici ne décrit le contenu de
/// la conversation (participants, messages) : il ne sera connu qu'après la
/// lecture du fichier (étape 2).
library;

/// Formats d'export WhatsApp reconnus.
enum FormatExportWhatsApp {
  /// Archive « avec médias » (ou sans, selon l'export) : un fichier texte
  /// et, parfois, des images, vidéos, vocaux, documents.
  zip('ZIP'),

  /// Historique des messages seul.
  txt('TXT');

  const FormatExportWhatsApp(this.libelle);

  /// Nom affiché (« ZIP », « TXT »).
  final String libelle;
}

/// Par où le fichier est arrivé dans JARVIS.
enum SourceReception {
  /// Sélecteur de fichiers (Android, iOS, Windows, navigateur).
  selecteur,

  /// Menu de partage Android (« Exporter la discussion » → JARVIS).
  partageAndroid,

  /// Fichier déposé sur la page (Windows, navigateur).
  glisserDeposer,
}

/// Résultat du contrôle initial (étape 1). La vérification approfondie
/// du contenu WhatsApp viendra avec la lecture du fichier (étape 2).
enum ValidationInitiale {
  /// Format reconnu d'après le contenu réel : le fichier peut être lu.
  formatReconnu,
}

/// Fichier d'export reçu et contrôlé.
class FichierExportWhatsApp {
  const FichierExportWhatsApp({
    required this.id,
    required this.nom,
    required this.format,
    required this.source,
    this.tailleOctets,
    this.typeMime,
    this.validation = ValidationInitiale.formatReconnu,
  });

  /// Identifiant temporaire, valable pendant la session (jamais un
  /// chemin : sur Android et le Web, il n'y en a pas toujours).
  final String id;

  final String nom;

  /// Format détecté d'après le contenu (pas seulement l'extension).
  final FormatExportWhatsApp format;
  final SourceReception source;

  /// Null si le système ne la donne pas (certains partages Android).
  final int? tailleOctets;

  /// Type MIME annoncé par le système, s'il y en a un (indicatif).
  final String? typeMime;

  final ValidationInitiale validation;
}

/// Raisons pour lesquelles un fichier reçu est refusé.
enum ErreurSelectionExport {
  formatNonPrisEnCharge(
    'Ce format n’est pas pris en charge. Choisissez un export WhatsApp '
    'au format ZIP ou TXT.',
  ),
  fichierVide('Ce fichier est vide.'),
  archiveEndommagee(
    'Cette archive ZIP semble endommagée ou incomplète. Exportez à '
    'nouveau la discussion depuis WhatsApp.',
  ),
  texteIllisible(
    'Ce fichier texte est illisible (son contenu n’est pas du texte). '
    'Exportez à nouveau la discussion depuis WhatsApp.',
  ),
  tropVolumineux('Ce fichier est trop volumineux (1 Go au maximum).'),
  accesImpossible(
    'Impossible d’ouvrir ce fichier. Vérifiez qu’il est toujours '
    'disponible, puis réessayez.',
  ),
  aucunFichier(
    'Aucun fichier n’a été reçu. Dans WhatsApp, utilisez « Exporter la '
    'discussion », puis choisissez JARVIS.',
  );

  const ErreurSelectionExport(this.message);

  /// Message affiché à l'utilisateur.
  final String message;
}
