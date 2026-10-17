# Campagne de tests WhatsApp (données FICTIVES)

Toutes les personnes et conversations sont inventées (identité commune
« Alex Martin »). Le manifeste sert à VÉRIFIER, il n'est jamais envoyé à l'IA.

| Fichier | Rôle |
| --- | --- |
| `generer.py` | génère les 5 ZIP + `manifeste.json` (déterministe, graine fixe) : `python tests_whatsapp/generer.py` |
| `JARVIS_TEST_*.zip` | exports Android français (« 15/03/2026 14:30 - Alex Martin: … »), un `.txt` par ZIP, sans médias |
| `manifeste.json` | participants, nombre exact de messages, période, « Vous êtes », dernier auteur, messages de référence (`rang` = ordre dans l'export) et résultats attendus |
| `faux_groq.py` | faux GroqCloud déterministe (API OpenAI compatible, streaming) pour tester l'appli sur appareil sans consommer de tokens |

| ZIP | Messages | Participants | Période | Dernier auteur |
| --- | --- | --- | --- | --- |
| SENTIMENTAL | 96 (+1 système) | Alex Martin, Lina Moreau | 01/09/2026 → 08/10/2026 | Lina |
| PROFESSIONNEL | 248 (+1) | Alex Martin, Nora Laurent | 09/05/2026 → 25/07/2026 | Nora |
| AMITIE | 782 (+1) | Alex Martin, Samuel Petit | 03/03/2026 → 23/09/2026 | Alex |
| FAMILLE | 1 493 (+1) | Alex Martin, Maya Martin | 05/11/2025 → 21/09/2026 | Maya |
| GROUPE « Projet Nova » | 4 792 (+3) | Alex, Nora, Samuel, Lina, Maya | 02/02/2026 → 01/09/2026 | Nora |

## Tests automatiques

- Parseur réel de l'appli : `flutter test test/campagne_whatsapp_test.dart`
- Moteur (IA simulée) : depuis la racine du dépôt
  `docker run --rm -v "<dépôt>:/repo" -w /repo/backend jarvis-tests python -m pytest tests/test_campagne.py`
  (image `jarvis-tests` = `backend-api` + pytest, pytest-asyncio, fakeredis)

## Appareil sans IA réelle

```bash
docker run -d --name faux-groq --network backend_default -v "<dépôt>/tests_whatsapp:/faux" -w /faux --entrypoint uvicorn backend-api faux_groq:app --host 0.0.0.0 --port 9000
docker stop jarvis-api
docker run -d --name jarvis-api-campagne --network backend_default -p 8000:8000 --env-file backend/.env -e REDIS_URL=redis://jarvis-redis:6379/0 -e OPENAI_BASE_URL=http://faux-groq:9000/v1 backend-api
```

Après les tests : `docker rm -f jarvis-api-campagne faux-groq` puis
`docker compose -f backend/docker-compose.yml up -d`. Sur le téléphone :
`adb push tests_whatsapp/JARVIS_TEST_*.zip /sdcard/Download/` puis
`flutter run --profile -d <appareil> --dart-define-from-file=config_locale.json --dart-define=JARVIS_API_URL=http://127.0.0.1:8000`
(après `adb reverse tcp:8000 tcp:8000`). Utiliser un compte JARVIS de TEST.
