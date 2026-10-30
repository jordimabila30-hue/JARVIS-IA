// Maj+Entrée = retour à la ligne dans la barre de saisie, sur toutes les
// plateformes. Ordinateur natif : raccourci Flutter (LigneDeCommande).
// Web : voir retour_ligne_web.dart (le navigateur déclenche l'envoi avant
// que Flutter ne voie la touche).
export 'retour_ligne_autre.dart'
    if (dart.library.js_interop) 'retour_ligne_web.dart';
