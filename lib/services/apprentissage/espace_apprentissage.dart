import '../voice_session.dart';
import 'catalogue_apprentissage.dart';
import 'service_progression.dart';
import 'session_tuteur.dart';

/// Interrupteur local du module Apprendre (Kelasi). Désactivé
/// (`--dart-define=JARVIS_APPRENTISSAGE=false`) : l'entrée du menu
/// disparaît et rien du module n'est créé ; la navigation reste intacte.
/// Un pilotage distant viendra avec l'intégration au serveur.
abstract final class ModuleApprentissage {
  static const actif = bool.fromEnvironment(
    'JARVIS_APPRENTISSAGE',
    defaultValue: true,
  );
}

/// Voix des exercices d'écoute. Toujours facultative : le texte reste
/// lisible à l'écran, une leçon n'est jamais bloquée par la synthèse.
abstract class LecteurEcoute {
  /// Une lecture peut être tentée maintenant.
  bool get disponible;

  /// Lit [texte] ; faux si aucune voix n'a pu le dire.
  Future<bool> lire(String texte);

  Future<void> arreter();
}

/// Écoute par la voix de JARVIS (réglages de l'utilisateur, même moteur
/// que l'aperçu de la voix). Indisponible pendant un chat vocal.
class LecteurEcouteSession implements LecteurEcoute {
  const LecteurEcouteSession(this.session);

  final VoiceSession session;

  @override
  bool get disponible => !session.actif;

  @override
  Future<bool> lire(String texte) async {
    if (!disponible) return false;
    await session.lireApercu(texte);
    return session.erreurApercu == null;
  }

  @override
  Future<void> arreter() => session.arreterApercu();
}

/// Ce dont le module a besoin, créé à la première ouverture seulement
/// (jamais au démarrage de JARVIS) puis gardé : corpus en cache,
/// progression déjà lue.
class EspaceApprentissage {
  EspaceApprentissage({
    CatalogueApprentissage? catalogue,
    ServiceProgression? progression,
    this.lecteur,
    this.tuteur,
    this.voix,
  }) : catalogue = catalogue ?? CatalogueApprentissage(),
       progression = progression ?? ServiceProgression();

  final CatalogueApprentissage catalogue;
  final ServiceProgression progression;
  final LecteurEcoute? lecteur;

  /// Professeur IA (backend unifié, MIA universel) ; null sans compte.
  final AppelTuteur? tuteur;

  /// Session vocale de JARVIS, réutilisée pour l'oral (aucun second
  /// moteur) ; null : oral indisponible (tests, plateforme sans voix).
  final VoiceSession? voix;

  /// Nouvelle demande au professeur IA.
  SessionTuteur session() => SessionTuteur(tuteur);

  Future<void>? _pret;

  /// Corpus et progression lus en parallèle (une seule fois).
  Future<void> preparer() =>
      _pret ??= Future.wait([catalogue.charger(), progression.charger()]);

  void dispose() {
    progression.dispose();
    catalogue.dispose();
  }
}
