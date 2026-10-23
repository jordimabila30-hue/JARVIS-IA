import '../../models/apprentissage/contenu_pedagogique.dart';
import '../../models/apprentissage/exercice.dart';
import '../../models/apprentissage/progression.dart';

/// Apprentissage adaptatif de Kelasi : règles locales, déterministes et
/// explicables (aucun appel IA). Elles portent sur les RÉSULTATS (premiers
/// essais, maîtrise par notion), jamais sur la vitesse de réponse.
abstract final class AdaptationKelasi {
  /// Taille du test de niveau (court, non intimidant).
  static const tailleTest = 5;

  /// Difficulté d'un exercice, d'après sa forme : reconnaître (1),
  /// compléter ou choisir le meilleur message (2), construire (3).
  static int difficulte(Exercice e) => switch (e.type) {
    TypeExercice.vraiFaux || TypeExercice.choix => 1,
    TypeExercice.trous ||
    TypeExercice.meilleurMessage ||
    TypeExercice.ecoute => 2,
    TypeExercice.ordre || TypeExercice.association => 3,
  };

  /// Niveau estimé d'après un score du test (justes / total).
  static NiveauApprenant niveauPour(int justes, int total) {
    if (total == 0) return NiveauApprenant.debutant;
    final r = justes / total;
    if (r >= 0.8) return NiveauApprenant.avance;
    if (r >= 0.5) return NiveauApprenant.intermediaire;
    return NiveauApprenant.debutant;
  }

  /// Exercices du test : un par notion à tour de rôle (toutes les notions
  /// du parcours sont sondées), du plus simple au plus construit.
  static List<(Exercice, String)> exercicesTest(List<Lecon> lecons) {
    final parFiche = <String, List<(Exercice, String)>>{};
    for (final l in lecons) {
      for (final e in l.exercices) {
        (parFiche[e.fiche] ??= []).add((e, l.id));
      }
    }
    for (final liste in parFiche.values) {
      liste.sort((a, b) => difficulte(a.$1).compareTo(difficulte(b.$1)));
    }
    final choisis = <(Exercice, String)>[];
    for (var rang = 0; choisis.length < tailleTest; rang++) {
      var ajout = false;
      for (final liste in parFiche.values) {
        if (rang < liste.length && choisis.length < tailleTest) {
          choisis.add(liste[rang]);
          ajout = true;
        }
      }
      if (!ajout) break;
    }
    // Du plus simple au plus construit : un début rassurant (tri stable).
    final indices = List<int>.generate(choisis.length, (i) => i)
      ..sort((a, b) {
        final c = difficulte(choisis[a].$1).compareTo(difficulte(choisis[b].$1));
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final i in indices) choisis[i]];
  }

  /// Tri d'entraînement selon le niveau : notions les moins maîtrisées
  /// d'abord ; débutant → exercices simples d'abord, avancé → construits.
  static List<T> ordonner<T>(
    List<T> exercices, {
    required Exercice Function(T) exercice,
    required double Function(String fiche) maitrise,
    NiveauApprenant? niveau,
  }) {
    double score(T x) {
      final e = exercice(x);
      final d = difficulte(e);
      final cible = switch (niveau) {
        NiveauApprenant.avance => 3,
        NiveauApprenant.intermediaire => 2,
        _ => 1,
      };
      // Écart de difficulté pondéré, puis faiblesse de la notion.
      return (d - cible).abs() * 0.5 + maitrise(e.fiche);
    }

    final indices = List<int>.generate(exercices.length, (i) => i)
      ..sort((a, b) {
        final c = score(exercices[a]).compareTo(score(exercices[b]));
        return c != 0 ? c : a.compareTo(b); // ordre stable
      });
    return [for (final i in indices) exercices[i]];
  }

  /// Niveau après une leçon terminée : un cran plus haut si toutes les
  /// notions du parcours sont solides, un cran plus bas si la leçon a mal
  /// tourné ; sinon inchangé. Sans niveau connu : estimé par la leçon.
  static NiveauApprenant ajuster(
    NiveauApprenant? niveau, {
    required int justes,
    required int total,
    required Iterable<double> maitrises,
  }) {
    final estime = niveauPour(justes, total);
    if (niveau == null) return estime;
    final liste = maitrises.toList();
    final moyenne = liste.isEmpty
        ? 0.5
        : liste.reduce((a, b) => a + b) / liste.length;
    final i = niveau.index;
    if (estime.index > i && moyenne >= 0.7) {
      return NiveauApprenant.values[i + 1];
    }
    if (estime.index < i && moyenne < 0.5) {
      return NiveauApprenant.values[i - 1];
    }
    return niveau;
  }
}
