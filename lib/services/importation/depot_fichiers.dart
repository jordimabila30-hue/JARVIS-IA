import 'selection_export_whatsapp.dart';
import 'depot_fichiers_autre.dart'
    if (dart.library.js_interop) 'depot_fichiers_web.dart';

/// Fichiers glissés-déposés sur la fenêtre (Windows, navigateur).
///
/// Écoute seulement entre [demarrer] et [arreter] (page d'import ouverte) ;
/// ailleurs, rien n'est capté.
abstract class DepotFichiers {
  factory DepotFichiers() => creerDepotFichiers();

  /// La plateforme permet de déposer des fichiers.
  bool get disponible;

  /// [surSurvol] : un fichier passe au-dessus (navigateur seulement) ;
  /// [surDepot] : fichiers déposés.
  void demarrer({
    required void Function(bool survol) surSurvol,
    required void Function(List<FichierBrut> fichiers) surDepot,
  });

  void arreter();
}
