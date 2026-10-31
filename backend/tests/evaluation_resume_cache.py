"""Évaluation RÉELLE (payante) des optimisations 72 et 73 avec Claude.

Lancer depuis la racine du dépôt, dans l'image backend (clé lue dans
backend/.env, jamais affichée) :

    docker run --rm --env-file backend/.env -v "$PWD:/depot" -w /depot/backend \
        backend-api python -m tests.evaluation_resume_cache

7 appels au plus : 1 résumé, puis 3 questions AVEC le résumé et 3 SANS
(mêmes messages récents). Affiche les réponses, les tokens (dont cache lu /
écrit) et le coût estimé. Conversation fictive, aucune donnée réelle.
"""

from __future__ import annotations

import asyncio
import time
from datetime import datetime, timezone

from app import resume
from app.api.v1.chat import Ton, build_system_prompt, ligne_date
from app.config import get_settings
from app.llm import selection
from app.llm.base import Fin, Texte

# Tarif de claude-opus-5-5 ($ / million de tokens), vérifié le 2026-10-31.
TARIF = {"entree": 4.00, "sortie": 20.00, "cache_ecriture": 5.00, "cache_lecture": 0.20}
MAX_APPELS = 7

ANCIENS = [
    ("J'organise la réunion de lancement du projet Kivu avec Amani.", "Très bien. Quel jour vise-t-on ?"),
    ("On part sur mardi 14 h, salle B.", "Noté : réunion de lancement mardi à 14 h, salle B."),
    ("Le code du portail du bureau est 4718, garde-le.", "D'accord, code du portail : 4718."),
    ("Pour les vacances, je pense à Mombasa en août.", "Mombasa en août, bonne idée."),
    ("Ma voiture doit passer au contrôle technique le 12 novembre.", "Contrôle technique le 12 novembre, noté."),
    ("Il y a deux dossiers en cours : le dossier Martin et le dossier assurance.", "Compris, deux dossiers."),
    ("Finalement la réunion Kivu est déplacée à jeudi 10 h, même salle.",
     "C'est noté : la réunion passe de mardi 14 h à jeudi 10 h, salle B."),
    ("Amani apportera la maquette.", "Parfait, Amani apporte la maquette."),
    ("Peut-être qu'on invitera aussi Grace, ce n'est pas sûr.", "D'accord, Grace peut-être, à confirmer."),
    ("Je préfère qu'on me réponde en phrases courtes.", "Entendu, je serai bref."),
]
RECENTS = [
    (f"Recette {i} : combien de temps pour cuire des haricots ?", f"Environ {40 + i} minutes à feu moyen.")
    for i in range(10)
]
QUESTIONS = [
    ("decision corrigee", "Au fait, la réunion Kivu c'est quand déjà ?", ["jeudi", "10"]),
    ("detail ancien", "Rappelle-moi le code du portail.", ["4718"]),
    ("reference ambigue", "Tu peux me redonner l'état du dossier ?", ["?"]),
]


class Appels:
    def __init__(self):
        self.n = 0
        self.cout = 0.0

    def compter(self, usage):
        self.n += 1
        self.cout += (usage.entree * TARIF["entree"] + usage.sortie * TARIF["sortie"]
                      + usage.cache_ecriture * TARIF["cache_ecriture"]
                      + usage.cache_lecture * TARIF["cache_lecture"]) / 1_000_000
        if self.n > MAX_APPELS or self.cout > 3.0:
            raise SystemExit(f"Plafond atteint ({self.n} appels, {self.cout:.3f} $) : arrêt.")


class Supabase:
    def __init__(self, lignes):
        self.lignes = lignes

    async def count_messages(self, _):
        return len(self.lignes)

    async def get_messages_range(self, _, *, offset, limit):
        return self.lignes[offset:offset + limit]


class Redis:
    def __init__(self):
        self.d = {}

    async def get(self, k):
        return self.d.get(k)

    async def set(self, k, v, ex=None):
        self.d[k] = v

    async def delete(self, k):
        self.d.pop(k, None)


def lignes(paires):
    return [m for q, r in paires for m in ({"role": "user", "content": q}, {"role": "assistant", "content": r})]


async def demander(llm, appels, systeme, historique, question, now):
    ligne = ligne_date(now, 60)
    prompt = [{"role": "system", "content": systeme.replace(ligne + "\n", "", 1)},
              *historique[:-1], {**historique[-1], "cache": True},
              {"role": "system", "content": ligne}, {"role": "user", "content": question}]
    debut = time.perf_counter()
    texte, fin, premier = [], None, None
    async for e in llm.flux(prompt, max_sortie=1024):
        if isinstance(e, Texte):
            premier = premier or time.perf_counter()
            texte.append(e.texte)
        elif isinstance(e, Fin):
            fin = e
    appels.compter(fin.usage)
    u = fin.usage
    return ("".join(texte).strip(), u, (premier or time.perf_counter()) - debut, time.perf_counter() - debut)


async def main():
    settings = get_settings()
    llm = selection.creer("anthropic", settings)
    print(f"Fournisseur : {llm.nom} / {llm.modele}")
    appels = Appels()
    now = datetime.now(timezone.utc)
    toutes = lignes(ANCIENS + RECENTS)                  # 40 messages
    recentes = toutes[-settings.chat_history_messages:]  # ce que voit le modèle

    redis = Redis()
    t = time.perf_counter()
    consomme = await resume.mettre_a_jour(redis=redis, supabase=Supabase(toutes), llm=llm,
                                          conversation_id="eval", fenetre=settings.chat_history_messages,
                                          ttl=600)
    appels.n += 1
    if consomme:
        appels.cout += (consomme[0] * TARIF["entree"] + consomme[1] * TARIF["sortie"]) / 1_000_000
    r = await resume.lire(redis, "eval")
    print(f"\n== RÉSUMÉ ({consomme} tokens, {time.perf_counter() - t:.1f} s)")
    bloc = resume.bloc(r) if r else ""
    print(bloc or "(aucun)")

    base = build_system_prompt(Ton.naturel, None, now, decalage_minutes=60)
    for nom_variante, systeme in (("AVEC résumé", f"{base}\n\n{bloc}"), ("SANS résumé", base)):
        print(f"\n######## {nom_variante}")
        for nom, question, attendus in QUESTIONS:
            reponse, u, premier, total = await demander(llm, appels, systeme, recentes, question, now)
            ok = all(a.lower() in reponse.lower() for a in attendus)
            print(f"\n-- {nom} : {question}\n{reponse}\n[{'attendu présent' if ok else 'attendu ABSENT'}] "
                  f"entrée {u.entree}, cache lu {u.cache_lecture}, cache écrit {u.cache_ecriture}, "
                  f"sortie {u.sortie} ; premier fragment {premier:.2f} s, total {total:.2f} s")
    print(f"\n== {appels.n} appel(s), coût estimé {appels.cout:.4f} $ (résumé compris)")


if __name__ == "__main__":
    asyncio.run(main())
