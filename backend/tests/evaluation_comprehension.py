"""Évaluation de la compréhension conversationnelle (scenarios_comprehension.py).

Deux niveaux, toujours distingués dans le rapport :

  1. DÉTERMINISTE (aucune IA, gratuit, reproductible) : ce que le moteur
     prépare — message visé, messages fournis, chronologie, clarification,
     informations transmises aux lots de propositions, budget ;
  2. RÉEL (`--reel`, fournisseur MIA, GroqCloud par défaut) : réponses et
     propositions du vrai modèle ; mesures automatiques (longueurs,
     registre, diversité, plaisanteries, chiffres inventés, mots attendus)
     + textes enregistrés pour un jugement humain. Coûteux : quelques
     scénarios seulement (`--scenarios a,b`).

Fonctionne aussi sur l'ANCIENNE version du moteur (comparaison avant /
après) : les fonctionnalités absentes comptent simplement comme manquées.

    docker run --rm -v "<dépôt>:/repo" -w /repo/backend jarvis-tests \
        python tests/evaluation_comprehension.py [--json sortie.json]
    docker run --rm -v "<dépôt>:/repo" -w /repo/backend --env-file .env -e FOURNISSEUR=groq \
        --entrypoint python backend-api tests/evaluation_comprehension.py --reel --scenarios envoyee_puis_recue
"""

import argparse
import asyncio
import inspect
import json
import os
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI.parent))
sys.path.insert(0, str(ICI))
# Mode déterministe : aucune configuration privée nécessaire (valeurs de
# test, comme conftest.py) ; en mode réel, --env-file fournit les vraies.
for _cle, _valeur in {"SUPABASE_URL": "https://test-project.supabase.co",
                      "SUPABASE_SERVICE_ROLE_KEY": "service-role-test",
                      "SUPABASE_JWT_SECRET": "test-secret-with-at-least-32-characters!!",
                      "OPENAI_API_KEY": "sk-test"}.items():
    os.environ.setdefault(_cle, _valeur)

from app.comprehension import ciblage, generation, propositions as aide  # noqa: E402
from app.comprehension.moteur import MoteurComprehension, message_source  # noqa: E402
from app.config import get_settings  # noqa: E402

from scenarios_comprehension import SCENARIOS, Scenario  # noqa: E402
from test_campagne import contexte  # noqa: E402

AUJOURDHUI = date(2026, 10, 16)
BUDGET_GROQ = 6000          # comprehension_budget_tokens (GroqCloud)
EXTRA_AIDE = 2500           # comprehension_extra_output_tokens
TONS_ANNONCES = "Naturel, Chaleureux, Taquin"


# --- Construction --------------------------------------------------------------

def construire(s: Scenario):
    ctx = contexte(s.zip)
    for a in s.ajouts:
        ordre = ctx.messages[-1].ordre + 1
        ctx.messages.append(message_source(ctx, {
            "id": f"ajout-{ordre}", "message_order": ordre, "author": a.auteur, "content": a.texte,
            "kind": "text", "sent_at": None, "sent_at_raw": "", "origin": a.origine, "created_at": a.cree_le}))
    ctx.nombre = len(ctx.messages)
    envoyees = {ctx.id: [{"texte": d.texte, "ton": d.ton, "declared_at": d.declared_at, "dans_export": False,
                          "proposition_id": f"p-{i}", "statut": "declaree_envoyee"}
                         for i, d in enumerate(s.declarations)]} if s.declarations else None
    historique = [{"role": r, "content": c} for r, c in s.historique]
    return ctx, envoyees, historique


def _accepte(fonction, **kwargs):
    """Arguments acceptés par [fonction] (ancienne version : moins d'options)."""
    params = inspect.signature(fonction).parameters
    return {k: v for k, v in kwargs.items() if k in params}


def preparer(s: Scenario, ctx, envoyees, historique, systeme="Tu es JARVIS."):
    settings = get_settings()
    precedentes = [m["content"] for m in historique if m["role"] == "user"]
    visee = ciblage.cibler(s.question, [ctx], precedentes)
    cites = {k: set(v) for k, v in ciblage.voisins(visee).items()}
    budget = BUDGET_GROQ - (EXTRA_AIDE if s.aide else 0)
    moteur = MoteurComprehension(None, None, settings)
    p = moteur.preparer(**_accepte(
        moteur.preparer, systeme=systeme, contextes=[ctx], cibles=[ctx], historique=historique,
        question=s.question, aujourd_hui=AUJOURDHUI, budget=budget, cites=cites, envoyees=envoyees,
        ciblage=visee))
    return visee, p, budget


def brief_lots(s: Scenario, ctx, p, envoyees, analyse="(analyse de JARVIS)"):
    bloc = f'<propositions mode="reponse" tons="{TONS_ANNONCES}" lecture="(lecture de la situation)"></propositions>'
    e = generation.annoncer(bloc, p.fournis, ctx.id)
    memoire = aide.bloc_memoire(envoyees[ctx.id], ctx.contact) if envoyees else None
    texte, fournis = generation.brief(**_accepte(
        generation.brief, ctx=ctx, question=s.question, analyse=analyse, aujourd_hui=AUJOURDHUI,
        memoire=memoire, ensemble=e,
        vise=p.ciblage.cible.message if getattr(p, "ciblage", None) and p.ciblage.cible else None))
    return e, texte, fournis


# --- Contrôles déterministes ---------------------------------------------------

CRITERES = {
    "auteurs": "Exactitude des auteurs (message visé, auteur enregistré)",
    "chronologie": "Exactitude chronologique (ajouts, déclarations, ordre réel)",
    "selection": "Pertinence des messages sélectionnés",
    "ambiguite": "Gestion des ambiguïtés (clarification)",
    "suivi": "Questions de suivi (référent actif)",
    "contexte_recent": "Contexte récent transmis",
    "lots": "Informations partagées avec les lots de propositions",
    "budget": "Budget de tokens respecté",
}


def controler(s: Scenario) -> list[tuple[str, str, bool]]:
    """(critère, contrôle, réussi) pour un scénario."""
    ctx, envoyees, historique = construire(s)
    visee, p, budget = preparer(s, ctx, envoyees, historique)
    texte = "\n".join(m["content"] for m in p.messages)
    fournis = {(f.message.auteur, f.message.contenu) for f in p.fournis.values()}
    r: list[tuple[str, str, bool]] = []
    suivi = bool(s.historique) or s.question.lower().startswith(("pourquoi", "tu crois", "qu'est-ce"))

    if s.cible == "clarification":
        ok = visee is not None and visee.cible is None and bool(visee.ambigus)
        r.append(("ambiguite", "clarification demandée (aucune personne choisie au hasard)", ok))
    elif isinstance(s.cible, tuple):
        ok = visee is not None and visee.cible is not None and \
            (visee.cible.message.auteur, visee.cible.message.contenu) == s.cible
        r.append(("auteurs", f"message visé = {s.cible[0]} « {s.cible[1][:40]} »", ok))
        if suivi:
            r.append(("suivi", "le suivi vise le référent actif", ok))
    else:
        ok = visee is None or visee.cible is None and not visee.ambigus
        r.append(("auteurs", "aucun « dernier message » imposé à tort", ok))

    for auteur, t in s.fournis:
        r.append(("selection", f"fourni : {auteur} « {t[:40]} »", (auteur, t) in fournis))

    for a in s.ajouts:
        lignes = [l for l in texte.splitlines() if a.texte[:30] in l and a.auteur in l]
        r.append(("chronologie", f"ajout « {a.texte[:30]} » marqué « ajouté à la main »",
                  any("ajouté à la main" in l for l in lignes)))
    if s.declarations:
        vise = re.search(r"<message_vise>.*?</message_vise>", texte, re.S)
        r.append(("chronologie", "réponse déclarée envoyée placée dans le fil, avant le message visé",
                  bool(vise) and s.declarations[-1].texte[:25] in vise.group(0)))
        r.append(("contexte_recent", "la réponse déclarée envoyée est transmise",
                  s.declarations[-1].texte[:25] in texte))
    if s.historique and isinstance(s.cible, tuple):
        dernier = p.messages[-1]["content"]
        r.append(("contexte_recent", "question posée sur le message visé (bloc juste avant la question)",
                  s.cible[1][:25] in "\n".join(m["content"] for m in p.messages[-2:]) and dernier == s.question))

    if s.aide:
        e, brief, _ = brief_lots(s, ctx, p, envoyees)
        if s.lot_cible:
            r.append(("lots", "message auquel répondre désigné aux lots",
                      bool(re.search(r"(?i)message auquel r[ée]pondre[^\n]*" + re.escape(s.lot_cible[1][:20]), brief))))
        r.append(("lots", "habitudes d'écriture de l'utilisateur transmises", "Habitudes" in brief))
        r.append(("lots", "lecture commune à tous les lots", "(lecture de la situation)" in brief))
        if s.serieux:
            r.append(("lots", "situation sérieuse signalée (aucune plaisanterie)",
                      bool(re.search(r"(?i)s[ée]rieu", brief)) and "plaisanterie" in brief.lower()))
        if s.proportion_legere:
            r.append(("lots", "message très court : réponses proportionnées demandées",
                      bool(re.search(r"(?i)proportion", brief))))
    r.append(("budget", f"≤ {budget} tokens estimés", p.tokens_estimes <= budget + 50))
    return r


def deterministe(ids: list[str] | None = None) -> dict:
    resultats = {}
    for s in SCENARIOS:
        if ids and s.id not in ids:
            continue
        resultats[s.id] = [{"critere": c, "controle": t, "ok": ok} for c, t, ok in controler(s)]
    return resultats


def tableau(resultats: dict) -> str:
    par: dict[str, list[int]] = {c: [0, 0] for c in CRITERES}
    lignes = []
    for sid, cs in resultats.items():
        reussis = sum(c["ok"] for c in cs)
        lignes.append(f"{sid:28} {reussis}/{len(cs)}")
        for c in cs:
            par[c["critere"]][0] += c["ok"]
            par[c["critere"]][1] += 1
            if not c["ok"]:
                lignes.append(f"    ✗ [{c['critere']}] {c['controle']}")
    lignes.append("")
    for c, (ok, n) in par.items():
        if n:
            lignes.append(f"{CRITERES[c]:60} {ok}/{n}")
    total = sum(v[0] for v in par.values()), sum(v[1] for v in par.values())
    lignes.append(f"{'TOTAL':60} {total[0]}/{total[1]}")
    return "\n".join(lignes)


# --- Essais réels ------------------------------------------------------------

_RIRES = re.compile(r"(?i)\b(?:mdr+|ptdr|haha\w*|lol)\b|[😂🤣😆😜😝😏]")
_NOMBRES = re.compile(r"\b\d{1,2}(?:[:h]\d{0,2}|/\d{1,2})?\b")
_PRUDENCE = re.compile(r"(?i)peut-être|probabl|sembl|on dirait|j'ai l'impression|possible|difficile à dire|"
                       r"plutôt|sans doute|deux lectures|soit .* soit")


def _mots(t: str) -> int:
    return len(re.findall(r"\w+", t))


def _phrases(t: str) -> int:
    return len([p for p in re.split(r"[.!?…]+", t) if _mots(p) >= 2])


def mesurer_propositions(entree: dict, sources: str, serieux: bool) -> dict:
    """Mesures automatiques d'un ensemble (jamais un jugement de qualité)."""
    m = {"combinaisons": 0, "court_ok": 0, "court_n": 0, "moyen_ok": 0, "moyen_n": 0, "long_n": 0,
         "long_mots": [], "court_mots": [], "moyen_mots": [], "similarite_intra": [], "similarite_inter_tons": [],
         "plaisanteries_taquin_ou_autres": 0, "nombres_inventes": [], "approches_distinctes": 0}
    textes_sources = sources
    par_longueur: dict[str, dict[str, list[str]]] = {}
    for t in entree.get("tons", []):
        for lo in generation.LONGUEURS:
            xs = [x for x in t["propositions"] if x["longueur"] == lo]
            if not xs:
                continue
            m["combinaisons"] += 1
            textes = [x["texte"] for x in xs]
            par_longueur.setdefault(lo, {})[t["nom"]] = textes
            approches = {(x.get("approche") or "").lower() for x in xs}
            m["approches_distinctes"] += len(approches) == len(xs)
            for a in range(len(textes)):
                for b in range(a + 1, len(textes)):
                    m["similarite_intra"].append(_jaccard(textes[a], textes[b]))
            for x in textes:
                n = _mots(x)
                m[f"{lo}_mots"].append(n)
                if lo == "court":
                    m["court_n"] += 1
                    m["court_ok"] += _phrases(x) <= 1 or n <= 15
                elif lo == "moyen":
                    m["moyen_n"] += 1
                    m["moyen_ok"] += 2 <= _phrases(x) <= 3 or (1 <= _phrases(x) <= 3 and 12 <= n <= 60)
                else:
                    m["long_n"] += 1
                if serieux and _RIRES.search(x):
                    m["plaisanteries_taquin_ou_autres"] += 1
                for nb in _NOMBRES.findall(x):
                    if nb not in textes_sources:
                        m["nombres_inventes"].append(nb)
    for lo, tons in par_longueur.items():
        noms = list(tons)
        for i in range(len(noms)):
            for j in range(i + 1, len(noms)):
                for a in tons[noms[i]]:
                    for b in tons[noms[j]]:
                        m["similarite_inter_tons"].append(_jaccard(a, b))
    moy = lambda xs: round(sum(xs) / len(xs), 2) if xs else None  # noqa: E731
    return {
        "combinaisons": m["combinaisons"],
        "court_une_phrase": f"{m['court_ok']}/{m['court_n']}",
        "moyen_2_3_phrases": f"{m['moyen_ok']}/{m['moyen_n']}",
        "mots_moyens": {lo: moy(m[f"{lo}_mots"]) for lo in generation.LONGUEURS},
        "long_mots_max": max(m["long_mots"]) if m["long_mots"] else None,
        "similarite_intra_moyenne": moy(m["similarite_intra"]),
        "similarite_intra_max": max(m["similarite_intra"]) if m["similarite_intra"] else None,
        "similarite_entre_tons_moyenne": moy(m["similarite_inter_tons"]),
        "approches_distinctes": f"{m['approches_distinctes']}/{m['combinaisons']}",
        "plaisanteries_si_serieux": m["plaisanteries_taquin_ou_autres"],
        "nombres_absents_des_sources": sorted(set(m["nombres_inventes"])),
    }


def _jaccard(a: str, b: str) -> float:
    x, y = set(aide._simple(a)), set(aide._simple(b))
    return round(len(x & y) / len(x | y), 2) if x and y else 1.0


async def reel(ids: list[str], sortie: Path | None):
    from app.api.v1.chat import Ton, build_system_prompt, completer_ensemble, plafond
    from app.comprehension.attribution import CorrecteurAttributions
    from app.comprehension.references import FiltreReperes, verifier
    from app.llm import selection
    from app.llm.base import LimiteDebit, reponse_complete

    settings = get_settings()
    llm = selection.creer(os.environ.get("FOURNISSEUR", "groq"))
    systeme = build_system_prompt(Ton.naturel, None, datetime(2026, 10, 16, 18, 0))
    resultats = {}
    for s in SCENARIOS:
        if s.id not in ids:
            continue
        ctx, envoyees, historique = construire(s)
        visee, p, _ = preparer(s, ctx, envoyees, historique, systeme)
        extra = EXTRA_AIDE if s.aide else 0
        debut = time.time()
        for essai in range(4):
            try:
                brut, fin = await reponse_complete(
                    llm, p.messages,
                    max_sortie=plafond(llm, settings.comprehension_max_output_tokens + extra, settings))
                break
            except LimiteDebit as exc:      # 8 000 tokens par minute : on attend, puis on reprend
                if essai == 3:
                    raise
                await asyncio.sleep(min(70.0, (exc.attente or 30.0) + 2))
        c = CorrecteurAttributions(p.fournis)
        f = FiltreReperes(c)
        b = aide.FiltrePropositions()
        visible = f.ajouter(b.ajouter(brut) + b.terminer()) + f.terminer()
        v = verifier(visible, f.reperes, p.fournis)
        r = {
            "question": s.question, "reponse": visible, "bloc": b.bloc,
            "tokens": [fin.usage.entree_totale, fin.usage.sortie], "secondes": round(time.time() - debut, 1),
            "references": [f"{x['author']} « {x['excerpt'][:60]} »" for x in v.references],
            "cible_citee": bool(isinstance(s.cible, tuple) and any(
                x["excerpt"].startswith(s.cible[1][:20]) for x in v.references)),
            "mots_attendus": [w for w in s.mots_attendus if w.lower() in visible.lower()],
            "mots_interdits": [w for w in s.mots_interdits if w.lower() in visible.lower()],
            "prudence": bool(_PRUDENCE.search(visible)),
            "lecture_attendue": s.lecture_attendue,
        }
        if s.aide and b.bloc:
            e = generation.annoncer(b.bloc, p.fournis, ctx.id)
            r["tons_annonces"] = e.tons
            r["lecture_annoncee"] = getattr(e, "lecture", None)
            memoire = aide.bloc_memoire(envoyees[ctx.id], ctx.contact) if envoyees else None
            kwargs = _accepte(completer_ensemble, ensemble=e, ctx=ctx, question=s.question, analyse=visible,
                              aujourd_hui=AUJOURDHUI, memoire_bloc=memoire, llm=llm, settings=settings,
                              vise=visee.cible.message if visee is not None and visee.cible else None)
            debut = time.time()
            async for _ in completer_ensemble(**kwargs):
                pass
            entree = e.stockage()
            sources = " ".join(m.contenu for m in ctx.messages) + " " + visible
            r["lots"] = {"statut": entree["statut"], "raison": e.raison, "requetes": e.requetes,
                         "tokens": [e.tokens_entree, e.tokens_sortie], "secondes": round(time.time() - debut, 1)}
            r["mesures"] = mesurer_propositions(entree, sources, s.serieux)
            r["propositions"] = {
                t["nom"]: {lo: [f"({x.get('approche')}) {x['texte']}" for x in t["propositions"]
                                if x["longueur"] == lo] for lo in generation.LONGUEURS}
                for t in entree["tons"]}
        resultats[s.id] = r
        print(json.dumps({s.id: r}, ensure_ascii=False, indent=1), flush=True)
        if sortie:     # enregistré après chaque scénario : rien de perdu si la suite échoue
            sortie.write_text(json.dumps(resultats, ensure_ascii=False, indent=1), encoding="utf-8")
        await asyncio.sleep(60)     # GroqCloud : 8 000 tokens par minute


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--reel", action="store_true")
    a.add_argument("--scenarios", default="")
    a.add_argument("--json", default="")
    args = a.parse_args()
    ids = [x for x in args.scenarios.split(",") if x] or None
    sortie = Path(args.json) if args.json else None
    if args.reel:
        asyncio.run(reel(ids or [], sortie))
        return
    resultats = deterministe(ids)
    print(tableau(resultats))
    if sortie:
        sortie.write_text(json.dumps(resultats, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
