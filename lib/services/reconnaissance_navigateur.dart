import 'reconnaissance_navigateur_autre.dart'
    if (dart.library.js_interop) 'reconnaissance_navigateur_web.dart';
import 'speech_recognition_service.dart';

/// Reconnaissance vocale directe du navigateur (API Web Speech).
///
/// Sur le Web, elle remplace le plugin speech_to_text, qui ne signale jamais
/// la fin d'une phrase (il attend 3 s de silence puis 2 s de plus) et qui
/// masque les erreurs du navigateur. Ici : une phrase par écoute, langue
/// française imposée, résultat final dès que l'utilisateur s'arrête, et
/// chaque erreur remontée avec son code.
abstract class ReconnaissanceNavigateur {
  /// Null hors Web.
  static ReconnaissanceNavigateur? creer() => creerReconnaissanceNavigateur();

  bool get disponible;

  void ecouter({
    required String langue,
    required void Function(String phrase) surPhrase,
    required void Function(ErreurReconnaissance erreur, String code) surErreur,
    required void Function() surFinSansResultat,
    void Function(String texte)? surPartiel,
    void Function()? surSon,
  });

  void annuler();
}
