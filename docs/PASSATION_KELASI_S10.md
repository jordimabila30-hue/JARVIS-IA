# Kelasi phase 2 (B et C) — vérifications restantes sur le Galaxy S10+

Le code et les tests automatiques sont faits (Flutter 968 / 968, backend
634 réussis + 1 ignoré). Le téléphone n'était pas branché : tout ce qui
suit n'a **pas** été vérifié sur l'appareil.

## 1. Backend avec la route du tuteur

La route n'existe que sur la branche `kelasi/phase2-bc`. Le déploiement du
backend principal (`jarvis-api`) demande une autorisation distincte. Pour
tester sans y toucher, un backend temporaire isolé (noms et port propres) :

```bash
cd backend
docker build -t kelasi-api-test .
docker network create kelasi-test
docker run -d --name kelasi-redis-test --network kelasi-test redis:7-alpine
docker run -d --name kelasi-api-test --network kelasi-test --env-file .env -e REDIS_URL=redis://kelasi-redis-test:6379/0 -e ENVIRONNEMENT=developpement -p 8001:8000 kelasi-api-test
curl http://127.0.0.1:8001/health/ready
```

`ENVIRONNEMENT=developpement` : les 9 fiches sont encore en brouillon ; en
production, le tuteur les refuse (422 `fiche_inconnue`) tant qu'elles ne
sont pas relues. Arrêt, par NOM seulement :
`docker stop kelasi-api-test kelasi-redis-test`.

## 2. Application sur le téléphone

```bash
adb reverse tcp:8001 tcp:8001
flutter run --profile -d R58M84VKRXV --dart-define-from-file=config_locale.json --dart-define=JARVIS_API_URL=http://127.0.0.1:8001 --dart-define=JARVIS_PERF=true
```

Le journal du backend donne, pour chaque demande, « 1er fragment … ms,
total … ms » (`docker logs kelasi-api-test`).

## 3. À vérifier

- Test de niveau : carte sur un parcours, « Commencer directement »,
  « Faire le test » (5 questions), niveau affiché, « Refaire le test ».
- Leçon : Plus simplement / Un exemple sous une fiche ; « Mon erreur »
  après une erreur ; M'entraîner (exercices locaux) ; réponse en direct,
  « Arrêter », sources à la fin, mode avion → message « demande Internet ».
- Situations : correction écrite, Nouvelle tentative.
- Oral : première réplique dite, écoute, transcription, réponse dite,
  « Arrêter la parole », « Couper le micro », saisie écrite (micro coupé),
  « Terminer » → bilan ; retour au chat : le chat vocal répond de nouveau
  normalement (répondeur rétabli) ; refus de l'oral pendant un chat vocal.
- Mesures : temps avant le premier fragment, durée de réponse, démarrage
  de l'écoute, délai de la voix, mémoire (RSS), images hors budget,
  PIM coupé pendant le module et repris au retour.
