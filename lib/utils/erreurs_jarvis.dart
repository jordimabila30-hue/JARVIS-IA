import 'package:flutter/foundation.dart';

/// Erreurs non rattrapées : une panne reste locale (un widget en erreur ne
/// remplace que lui-même, une erreur asynchrone ne ferme pas JARVIS) et
/// reste visible dans le journal.
///
/// Hors debug, le journal ne garde que le module et le TYPE de l'erreur :
/// jamais son message, qui peut contenir du texte d'une conversation, un
/// e-mail ou une adresse. En debug, le comportement de Flutter est
/// inchangé (message complet, pile).
class ErreursJarvis {
  ErreursJarvis._();

  /// Dernières erreurs signalées (diagnostic, tests), sans contenu.
  @visibleForTesting
  static final signalees = <String>[];

  static void installer({bool complet = kDebugMode}) {
    final defaut = FlutterError.onError;
    FlutterError.onError = (details) {
      if (complet) {
        defaut?.call(details);
        return;
      }
      _signaler(details.library ?? 'Flutter', details.exception);
    };
    PlatformDispatcher.instance.onError = (erreur, pile) {
      if (complet) return false; // Flutter l'affiche en entier.
      _signaler('asynchrone', erreur);
      return true;
    };
  }

  static void _signaler(String module, Object erreur) {
    final ligne = '$module : ${erreur.runtimeType}';
    signalees.add(ligne);
    if (signalees.length > 20) signalees.removeAt(0);
    debugPrint('[JARVIS erreur] $ligne');
  }
}
