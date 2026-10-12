import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../models/importation/export_whatsapp.dart';
import 'detection_format.dart';
import 'pont_android_importation.dart';

/// Fichier tel qu'il arrive (sélecteur, partage, dépôt), avant contrôle.
class FichierBrut {
  const FichierBrut({
    required this.nom,
    required this.source,
    this.tailleOctets,
    this.typeMime,
    this.flux,
  });

  final String nom;
  final SourceReception source;

  /// Null si le système ne la donne pas.
  final int? tailleOctets;
  final String? typeMime;

  /// Contenu, lu par morceaux à l'écoute (jamais chargé d'un bloc en
  /// mémoire) ; null si le fichier n'a pas pu être ouvert.
  final Stream<List<int>>? flux;
}

/// Ouvre le sélecteur ; null si l'utilisateur l'a fermé sans choisir.
typedef OuvrirSelecteur = Future<FichierBrut?> Function();

/// Issue d'une sélection ou d'une réception.
sealed class ResultatSelectionExport {
  const ResultatSelectionExport();
}

/// Sélecteur fermé sans choix : on ne change rien.
final class SelectionAnnulee extends ResultatSelectionExport {
  const SelectionAnnulee();
}

final class SelectionRefusee extends ResultatSelectionExport {
  const SelectionRefusee(this.erreur);
  final ErreurSelectionExport erreur;
}

final class SelectionReussie extends ResultatSelectionExport {
  const SelectionReussie(this.export);
  final ExportWhatsAppChoisi export;
}

/// Export reçu et contrôlé, avec son contenu encore ouvert pour la future
/// lecture (étape 2). Seuls les premiers octets ont été lus.
class ExportWhatsAppChoisi {
  ExportWhatsAppChoisi._(
    this.fichier,
    this._debut,
    this._suite, {
    required bool lu,
  }) : _fini = lu;

  final FichierExportWhatsApp fichier;
  final List<List<int>> _debut;
  StreamIterator<List<int>>? _suite;
  bool _lu = false;

  // Fichier déjà lu en entier pendant la vérification (petit fichier).
  final bool _fini;

  /// Tout le contenu, morceau par morceau. Une seule lecture possible :
  /// un fichier partagé ou choisi dans le navigateur ne se rouvre pas
  /// toujours. L'étape 2 y ajoutera ses propres limites (taille réelle,
  /// archives démesurées ou malveillantes).
  Stream<List<int>> lireContenu() async* {
    final suite = _suite;
    if (_lu || suite == null) {
      throw StateError('Le contenu de cet export a déjà été lu ou libéré.');
    }
    _lu = true;
    yield* Stream.fromIterable(_debut);
    // Un flux terminé ne se relance pas.
    while (!_fini && await suite.moveNext()) {
      yield suite.current;
    }
  }

  /// Ferme le fichier (retrait, remplacement, page quittée).
  Future<void> liberer() async {
    final suite = _suite;
    _suite = null;
    await suite?.cancel();
  }
}

/// Réception d'un export WhatsApp : toutes les sources (sélecteur,
/// partage Android, glisser-déposer) passent par [verifier], qui contrôle
/// la taille et détecte le format d'après le contenu réel.
///
/// Les étapes suivantes (lecture de l'archive, filtrage, enregistrement)
/// partiront de [ExportWhatsAppChoisi] sans toucher à cette réception.
class SelectionExportWhatsApp {
  SelectionExportWhatsApp({OuvrirSelecteur? ouvrirSelecteur})
    : _ouvrir = ouvrirSelecteur ?? ouvrirSelecteurSysteme;

  final OuvrirSelecteur _ouvrir;

  /// Au-delà, le fichier est refusé avant toute lecture.
  static const tailleMaximale = 1024 * 1024 * 1024;

  /// Octets lus pour reconnaître le contenu.
  static const tailleDebut = 4096;

  static int _compteur = 0;

  /// Ouvre le sélecteur du système, puis contrôle le fichier choisi.
  Future<ResultatSelectionExport> choisir() async {
    final FichierBrut? brut;
    try {
      brut = await _ouvrir();
    } catch (_) {
      return const SelectionRefusee(ErreurSelectionExport.accesImpossible);
    }
    if (brut == null) return const SelectionAnnulee();
    return verifier(brut);
  }

  /// Contrôle initial, le même pour toutes les sources.
  Future<ResultatSelectionExport> verifier(FichierBrut brut) async {
    final taille = brut.tailleOctets;
    if (taille != null && taille > tailleMaximale) {
      return const SelectionRefusee(ErreurSelectionExport.tropVolumineux);
    }
    final flux = brut.flux;
    if (flux == null) {
      return const SelectionRefusee(ErreurSelectionExport.accesImpossible);
    }

    final suite = StreamIterator<List<int>>(flux);
    final morceaux = <List<int>>[];
    var lus = 0;
    var termine = false;
    try {
      while (lus < tailleDebut) {
        if (!await suite.moveNext()) {
          termine = true;
          break;
        }
        morceaux.add(suite.current);
        lus += suite.current.length;
      }
    } catch (_) {
      // Fermeture en arrière-plan : le refus s'affiche tout de suite.
      unawaited(suite.cancel());
      return const SelectionRefusee(ErreurSelectionExport.accesImpossible);
    }
    final debut = [for (final m in morceaux) ...m].take(tailleDebut).toList();
    final detection = detecterFormat(
      nom: brut.nom,
      typeMime: brut.typeMime,
      debut: debut,
      fichierEntier: termine || (taille != null && taille <= debut.length),
    );
    final format = detection.format;
    if (format == null) {
      unawaited(suite.cancel());
      return SelectionRefusee(detection.erreur!);
    }
    return SelectionReussie(
      ExportWhatsAppChoisi._(
        FichierExportWhatsApp(
          id: 'export-${DateTime.now().microsecondsSinceEpoch}-${_compteur++}',
          nom: brut.nom,
          format: format,
          source: brut.source,
          // Taille inconnue mais fichier lu en entier : on la connaît.
          tailleOctets: taille ?? (termine ? lus : null),
          typeMime: brut.typeMime,
        ),
        morceaux,
        suite,
        lu: termine,
      ),
    );
  }
}

/// Sélecteur du système. Android : sélecteur natif (contenu lu en flux,
/// sans copie ni filtre de type, qui griserait les exports mal étiquetés).
/// Ailleurs : `file_picker` (filtre ZIP / TXT, contenu lu en flux).
Future<FichierBrut?> ouvrirSelecteurSysteme() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return PontAndroidImportation.instance.choisirFichier();
  }
  final resultat = await FilePicker.pickFiles(
    dialogTitle: 'Choisir un export WhatsApp',
    type: FileType.custom,
    allowedExtensions: const ['zip', 'txt'],
    withReadStream: true,
    lockParentWindow: true,
  );
  final fichier = resultat?.files.singleOrNull;
  if (fichier == null) return null;
  return FichierBrut(
    nom: fichier.name,
    source: SourceReception.selecteur,
    tailleOctets: fichier.size,
    flux: fichier.readStream,
  );
}
