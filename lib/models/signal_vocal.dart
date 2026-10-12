/// Détails de la voix transmis à PIM, en plus de l'amplitude.
///
/// Rempli par la session vocale, lu par PIM à chaque image : simples champs
/// (aucune notification, aucune allocation). Les événements de la parole de
/// JARVIS sont des compteurs : PIM repère qu'ils ont changé depuis l'image
/// précédente et déclenche l'onde correspondante à son propre rythme.
class SignalVocal {
  /// Bandes de fréquence de la voix de l'utilisateur (0 à 1), mesurées sur
  /// le micro quand la plateforme le permet (Web Audio).
  double graves = 0;
  double mediums = 0;
  double aigus = 0;

  /// Vrai quand les bandes viennent d'une vraie mesure. Sinon PIM les
  /// déduit de la dynamique de l'amplitude.
  bool bandesMesurees = false;

  /// Nombre de phrases commencées par JARVIS (une par réponse prononcée).
  int phrases = 0;

  /// Nombre de mots prononcés par JARVIS ; accent (0 à 1), durée estimée
  /// (s) et nombre de syllabes du dernier.
  int mots = 0;
  double accent = 0;
  double dureeMot = 0.3;
  int syllabes = 1;

  void debutPhrase() => phrases++;

  void mot(double force, {double duree = 0.3, int syllabes = 1}) {
    accent = force;
    dureeMot = duree;
    this.syllabes = syllabes;
    mots++;
  }

  void bandes(double g, double m, double a) {
    graves = g;
    mediums = m;
    aigus = a;
    bandesMesurees = true;
  }

  /// Décroissance commune (appelée par le minuteur de la session).
  void attenuer(double facteur) {
    graves *= facteur;
    mediums *= facteur;
    aigus *= facteur;
  }

  void effacerBandes() {
    graves = mediums = aigus = 0;
    bandesMesurees = false;
  }
}
