# JARVIS — Intégration du backend d'authentification

Document destiné au développeur backend et à l'équipe Flutter.

**État actuel :** les trois écrans (connexion, inscription, mot de passe
oublié) sont terminés côté interface. **Aucune authentification réelle
n'existe** : aucun serveur n'est configuré, aucune requête n'est envoyée,
aucun compte, aucune session et aucun jeton ne sont créés ni simulés.

Tout ce qui suit est une **proposition de contrat à confirmer** : les
adresses, les noms de champs JSON et le format des jetons ne sont pas
fixés tant que le backend ne les a pas définis.

---

## 1. Où se branche le backend (côté Flutter)

```text
lib/
├── models/authentification/
│   ├── utilisateur_auth.dart     # utilisateur renvoyé par le serveur (champs à confirmer)
│   └── resultat_auth.dart        # SuccesAuth / EchecAuth + familles d'erreurs (TypeErreurAuth)
├── services/authentification/
│   ├── auth_repository.dart      # CONTRAT d'accès au serveur + AuthRepositoryNonConfigure (actuel)
│   ├── auth_service.dart         # logique utilisée par les pages (chargement, double envoi)
│   ├── validation_auth.dart      # validations locales réglables (ReglesValidationAuth)
│   ├── stockage_session.dart     # contrat de stockage de la session + stratégie par plateforme
│   └── config_auth.dart          # configuration (--dart-define) : adresse, accès de développement
├── widgets/authentification/     # composants visuels réutilisables
└── pages/authentification/       # les trois écrans + le parcours (authentification_page.dart)
```

Couches :

| Couche | Rôle | Connaît le serveur ? |
| --- | --- | --- |
| Pages / widgets | Affichage, focus, validation locale, messages | Non |
| `AuthService` | Une opération à la fois, état de chargement, utilisateur courant | Non |
| `AuthRepository` | Requêtes, réponses, codes d'erreur, jetons | **Oui (seule couche)** |
| `StockageSession` | Garde la preuve de session sur l'appareil | Non (appelé par le dépôt) |

### Intégration en 4 étapes

1. Écrire `AuthRepositoryServeur implements AuthRepository` (nouveau fichier
   dans `services/authentification/`) : requêtes HTTP, traduction des
   réponses en `UtilisateurAuth`, traduction des codes d'erreur en
   `TypeErreurAuth`.
2. Écrire l'implémentation de `StockageSession` (mobile / desktop) ; sur le
   Web, préférer un cookie posé par le serveur (voir § 4).
3. Dans `ConfigAuth.creerRepository()`, renvoyer `AuthRepositoryServeur`
   quand `serveurConfigure` est vrai (adresse fournie par
   `--dart-define=JARVIS_API_URL=…`). C'est le **seul** point de bascule.
4. Aligner `ReglesValidationAuth` (longueur du mot de passe…) et, si besoin,
   les champs de `UtilisateurAuth` sur les règles du serveur.

Les pages, les widgets et `AuthService` n'ont pas à changer.

Paquets à ajouter **à ce moment-là seulement** (à valider) : un client HTTP
(`http` ou `dio`) et un stockage sécurisé (`flutter_secure_storage`).

---

## 2. Opérations à fournir (proposition de contrat)

Pour chaque opération : **adresse, méthode, format JSON, réponses et codes
d'erreur à définir par le backend.**

### Connexion — `AuthRepository.connecter`
- Envoyé : adresse e-mail (espaces retirés), mot de passe (tel quel).
- Réponse attendue : utilisateur (identifiant, e-mail, nom) + preuve de
  session (jeton ou cookie) — **format à définir**.
- Erreurs utiles : identifiants invalides, compte bloqué / non vérifié (?),
  trop de tentatives (?), données refusées.

### Inscription — `AuthRepository.inscrire`
- Envoyé : nom ou pseudonyme (espaces nettoyés), adresse e-mail, mot de
  passe.
- Réponse attendue : utilisateur créé ; session ouverte directement **ou**
  vérification d'e-mail requise — **à préciser** (l'interface s'adaptera).
- Erreurs utiles : e-mail déjà utilisé, mot de passe refusé (règles),
  données refusées (avec un message par champ si possible).

### Récupération — `AuthRepository.demanderRecuperation`
- Envoyé : adresse e-mail.
- Réponse attendue : accusé neutre (ne pas révéler si un compte existe).
  L'interface affiche alors : « Si un compte correspond à cette adresse,
  vous recevrez un lien de récupération. »
- Procédure ensuite (lien, code, page de réinitialisation, durée de
  validité) — **à définir**.

### Session
- `verifierSession` : comment vérifier qu'une session est valide — **à
  définir**.
- `restaurerSession` : au lancement, relire la preuve gardée sur l'appareil
  et la vérifier / renouveler — **méthode de renouvellement à définir**
  (jeton de rafraîchissement ? durée ?).
- `deconnecter` : révocation côté serveur — **à définir** ; l'appareil
  efface toujours sa session, même si le serveur ne répond pas.

---

## 3. Erreurs : correspondance proposée

Le serveur garde ses propres codes ; le dépôt les traduit vers :

| `TypeErreurAuth` | Exemple de cas serveur |
| --- | --- |
| `identifiantsInvalides` | e-mail ou mot de passe incorrect |
| `emailDejaUtilise` | inscription avec un e-mail existant |
| `donneesRefusees` | validation serveur échouée |
| `sessionExpiree` | jeton expiré, révoqué, ré-authentification exigée |
| `reseau` | serveur injoignable, délai dépassé |
| `inconnue` | tout le reste |

Si le serveur renvoie un message déjà rédigé pour l'utilisateur, il peut
être passé dans `ErreurAuth.detail` et sera affiché tel quel.

---

## 4. Sessions selon la plateforme (`StrategieSession`)

| Plateforme | Comportement voulu | Stockage prévu |
| --- | --- | --- |
| Android, iOS | Connexion une fois, restaurée à chaque ouverture | Keystore / Keychain (stockage sécurisé) |
| Windows, desktop | Idem | Credential Manager / équivalent sécurisé |
| Web | Valable pendant la session du navigateur, conservée à l'actualisation | Cookie `HttpOnly` + `Secure` + `SameSite` posé par le serveur |

Nouvelle connexion demandée seulement si : déconnexion, session expirée
sans renouvellement possible, session révoquée, ré-authentification exigée.

Règles de sécurité :
- jamais de mot de passe stocké, ni en clair ni chiffré ;
- aucune adresse, clé ou secret dans le code source (`--dart-define`) ;
- une préférence locale n'est jamais une preuve d'authentification : seule
  la réponse du serveur l'est ;
- Web : CORS et cookies à configurer côté serveur (origines autorisées,
  `credentials`).

---

## 5. Parcours de l'application

1. Écran de lancement (inchangé).
2. Pendant l'animation : `AuthService.restaurerSession()`.
3. Session acceptée par le serveur → accueil JARVIS.
4. Sinon → page de connexion.

Aujourd'hui l'étape 2 renvoie toujours « aucune session » : on arrive donc
sur la connexion.

**Accès de développement** : bouton « Continuer sans compte » sous le
formulaire de connexion. Il ouvre l'accueil sans utilisateur ni session
(aucune ressource protégée). Actif en debug et profile, **désactivé en
release** ; forçable avec `--dart-define=JARVIS_ACCES_DEV=true|false`.

---

## 6. Questions à poser au développeur backend

1. Adresse du serveur (développement, production) et version de l'API.
2. Pour chaque opération du § 2 : adresse, méthode, corps JSON, réponses.
3. Format de la session : jeton (JWT ou opaque ?), cookie, durée de vie,
   renouvellement (jeton de rafraîchissement ?), révocation.
4. Web : cookie `HttpOnly` possible ? Domaines et CORS ?
5. Règles du mot de passe (longueur, caractères) et du nom (longueur,
   caractères autorisés, unicité ?).
6. Vérification de l'e-mail à l'inscription : obligatoire ? Session ouverte
   avant ?
7. Procédure complète de récupération (lien, code, durée).
8. Liste des codes d'erreur et format des messages (par champ ?).
9. Limitation des tentatives (anti-force brute) et message associé.
10. Champs de l'utilisateur renvoyés (identifiant, nom, e-mail, avatar…).
