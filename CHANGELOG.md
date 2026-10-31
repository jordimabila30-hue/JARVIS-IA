# Historique des versions de JARVIS

Politique : `docs/VERSIONING.md`. Détail technique : `AVANCEMENT.md`.

## [Non publiée] — depuis 1.0.0+1

Proposition pour la prochaine livraison : **1.1.0+2** (nouvelles fonctions
compatibles, aucune incompatibilité). Numéro à confirmer par ChatGPT.

### Ajouté
- Réponses : blocs de code (police à chasse fixe, défilement, « Copier le
  code »), tableaux défilants, liens web cliquables (http/https seulement).
- Clavier : Maj+Entrée = retour à la ligne (Windows, Web).
- Écran de lancement passable d'un appui.
- Affichage de la version réellement construite (Paramètres › Général).
- Gmail : nombre exact / minimum / estimé distingués.
- Mémoire des longues conversations : les échanges anciens restent connus
  (résumé contrôlé).

### Amélioré
- Performances : question envoyée sans attente, préparation serveur d'un
  message ≈ 1,48 → 0,60 s (médianes), recherche du menu 3,4 × plus rapide,
  démarrage (chargements parallèles), cache de prompt Claude (− 95 % sur
  la part relue).
- Accessibilité : texte agrandi jusqu'à 200 %, cible du « + » élargie.

### Corrigé
- Faux calculs locaux (« 3 clés … et une fonction » → « 3 plus 1 égale 4 »).
- Code abîmé dans les réponses (`__init__`, `**`, accents graves).
- Restitution de quota en double (requête offerte).
- Journaux sans contenu privé (erreurs : module et type seulement).

## 1.0.0+1 — 2026-10-12 → 2026-10-28

Version initiale de développement (Flutter Android / Web / Windows, backend
FastAPI unifié, MIA universel, ODO, Gmail lecture seule, WhatsApp, JARVIS
Touch, Kelasi). Jamais renumérotée jusqu'ici.
