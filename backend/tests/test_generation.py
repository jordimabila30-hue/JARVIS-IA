"""Correction finale 5.1 : propositions générées PAR LOTS, validées, complétées
sans régénérer ce qui est déjà valide, reprises sans doublon. Faux GroqCloud
scénarisé (aucun appel réel)."""

import json
from types import SimpleNamespace

import httpx
import openai as openai_errors

from app.comprehension import generation, propositions as aide

from test_chat import FakeOpenAI, auth_headers, chunk, demandes_lot, json_lot, reponse_lot, texte_lot
from test_comprehension import CHAT
from test_references import env, evenements, post  # noqa: F401

ANNONCE = 'Lina attend ta réponse. Voici des idées.\n<propositions mode="reponse" tons="Amical, Taquin"></propositions>'
TONS = ["Amical", "Taquin", "Naturel", "Professionnel"]


class GroqScenario(FakeOpenAI):
    """Réponse principale en streaming ; chaque lot suit le scénario
    (fonction messages → contenu, ou exception), puis des lots corrects."""

    def __init__(self, principal=ANNONCE, lots=()):
        super().__init__(chunks=[chunk(principal),
                                 chunk(usage=SimpleNamespace(prompt_tokens=3000, completion_tokens=120))])
        self.lots = list(lots)
        self.demandes = []          # ce que chaque lot a demandé

    async def _create(self, **kwargs):
        if kwargs.get("stream"):
            return await super()._create(**kwargs)
        self.calls.append(kwargs)
        self.demandes.append(demandes_lot(kwargs["messages"]))
        etape = self.lots.pop(0) if self.lots else None
        if isinstance(etape, Exception):
            raise etape
        # Lot correct : textes propres à cet appel (un vrai modèle ne répète
        # pas mot pour mot ce qu'on lui demande d'éviter).
        contenu = etape(kwargs["messages"]) if etape else json_lot(kwargs["messages"], graine=f"g{len(self.calls)}")
        return reponse_lot(kwargs["messages"], contenu)


def limite(par_jour=False, delai="0.05"):
    requete = httpx.Request("POST", "https://api.groq.com/openai/v1/chat/completions")
    message = "Rate limit reached: tokens per day (TPD)" if par_jour else "Rate limit reached: tokens per minute"
    return openai_errors.RateLimitError(
        message, response=httpx.Response(429, request=requete, headers={"retry-after": delai}), body=None)


async def demander(env, llm):
    env.llm = llm
    resp = await post(env, message="Aide-moi à répondre à Lina", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    ligne = [r for r in env.supa.inserted if r["role"] == "assistant"][-1]
    # La demande est relue à la reprise (consigne enregistrée).
    for r in env.supa.inserted:
        if r["role"] == "user":
            env.supa.messages[r["id"]] = r
    [props] = [d for e, d in ev if e == "propositions"]
    return ev, ligne, props


def combinaisons(p):
    out = {}
    for t in p["tons"]:
        for x in t["propositions"]:
            out.setdefault((t["nom"], x["longueur"]), []).append(x)
    return out


def verifier_complet(p):
    assert p["statut"] == "complet"
    assert [t["nom"] for t in p["tons"]] == TONS
    c = combinaisons(p)
    assert len(c) == 12
    for (ton, lo), xs in c.items():
        assert [x["rang"] for x in xs] == [1, 2, 3], (ton, lo)
        assert len({x["texte"] for x in xs}) == 3
    ids = [x["id"] for xs in c.values() for x in xs]
    assert len(ids) == 36 == len(set(ids))


# 1. Réponse complète du premier coup ----------------------------------------

async def test_lots_complets_du_premier_coup(env):
    llm = GroqScenario()
    ev, ligne, props = await demander(env, llm)
    verifier_complet(props)
    # 2 lots de 2 tons, JSON strict, sortie bornée ; texte principal intact.
    assert [[t for t, _ in d] for d in llm.demandes] == [["Amical", "Taquin"], ["Naturel", "Professionnel"]]
    lots = [c for c in llm.calls if not c.get("stream")]
    assert all(c["response_format"] == {"type": "json_object"} for c in lots)
    assert all(c["max_tokens"] <= 2600 for c in lots)
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Lina attend ta réponse. Voici des idées."
    assert [e for e, _ in ev][-1] == "done"
    # Indicateur vivant côté appli : « preparation » avant les propositions.
    noms = [e for e, _ in ev]
    assert noms.index("preparation") < noms.index("propositions") < noms.index("done")
    # Tokens des lots comptés avec la réponse.
    done = [d for e, d in ev if e == "done"][0]
    assert done["usage"]["total_tokens"] == 3000 + 120 + 2 * (700 + 500)


# 2. Une seule proposition par longueur (le défaut du vrai modèle) -----------

async def test_une_par_longueur_completee_sans_regenerer(env):
    llm = GroqScenario(lots=[lambda m: json_lot(m, tronquer=lambda t, lo, n: 1)])
    _, _, props = await demander(env, llm)
    verifier_complet(props)
    # Le 2e lot traite les deux autres tons ; le 3e redemande seulement 2 par
    # longueur pour Amical et Taquin, en donnant celles déjà retenues.
    assert llm.demandes[2] == [("Amical", {"court": 2, "moyen": 2, "long": 2}),
                               ("Taquin", {"court": 2, "moyen": 2, "long": 2})]
    assert "déjà retenues, ne pas répéter" in llm.calls[-1]["messages"][-1]["content"]
    amical_court = combinaisons(props)[("Amical", "court")]
    assert amical_court[0]["texte"] == texte_lot("Amical", "court", 1)    # gardée, rang 1


# 3. Longueur entièrement manquante ------------------------------------------

async def test_longueur_manquante_seule_redemandee(env):
    def sans_long(m):
        d = json.loads(json_lot(m))
        for t in d["tons"]:
            t.pop("long", None)
        return json.dumps(d)
    llm = GroqScenario(lots=[sans_long])
    _, _, props = await demander(env, llm)
    verifier_complet(props)
    assert llm.demandes[2] == [("Amical", {"long": 3}), ("Taquin", {"long": 3})]


# 4. Ton entièrement manquant --------------------------------------------------

async def test_ton_manquant_seul_redemande(env):
    def sans_taquin(m):
        d = json.loads(json_lot(m))
        d["tons"] = [t for t in d["tons"] if t["nom"] != "Taquin"]
        return json.dumps(d)
    llm = GroqScenario(lots=[sans_taquin])
    _, _, props = await demander(env, llm)
    verifier_complet(props)
    assert llm.demandes[1] == [("Taquin", {"court": 3, "moyen": 3, "long": 3}),
                               ("Naturel", {"court": 3, "moyen": 3, "long": 3})]


# 5. Format invalide -------------------------------------------------------------

async def test_format_invalide_relance_bornee(env):
    llm = GroqScenario(lots=[lambda m: "Voici mes idées : 1. Coucou 2. Salut"])
    _, _, props = await demander(env, llm)
    verifier_complet(props)
    assert [t for t, _ in llm.demandes[1]] == ["Amical", "Taquin"]     # le lot illisible est refait


async def test_toujours_invalide_jamais_affiche_a_moitie(env):
    llm = GroqScenario(lots=[lambda m: "pas du json"] * 10)
    _, ligne, props = await demander(env, llm)
    assert props["statut"] == "incomplet" and props["raison"] == "invalide" and props["tons"] == []
    assert len([c for c in llm.calls if not c.get("stream")]) == 5     # limite de requêtes
    [entree] = [a for a in ligne["attachments"] if a["type"] == aide.TYPE]
    assert entree["statut"] == "incomplet"


# 6. Propositions répétitives -------------------------------------------------------

async def test_repetitions_refusees(env):
    def repetees(m):
        d = json.loads(json_lot(m))
        for t in d["tons"]:
            for lo in ("court", "moyen", "long"):
                t[lo] = [t[lo][0]] * 3                  # trois fois la même
        return json.dumps(d)
    llm = GroqScenario(lots=[repetees])
    _, _, props = await demander(env, llm)
    verifier_complet(props)
    assert llm.demandes[2] == [("Amical", {"court": 2, "moyen": 2, "long": 2}),
                               ("Taquin", {"court": 2, "moyen": 2, "long": 2})]


def test_long_trop_court_et_court_trop_long_refuses():
    e = generation.Ensemble(mode="reponse", context_id=None, tons=["Amical"])
    brut = json.dumps({"tons": [{"nom": "Amical",
                                 "court": [{"texte": " ".join(["mot"] * 60)}],
                                 "long": [{"texte": "Deux phrases. Seulement."}],
                                 "moyen": [{"texte": "Une idée <balise> cachée."}]}]})
    assert e.integrer(brut, {}) == (0, 3)


# 7 + 8. Quota pendant un lot : lots valides gardés, état incomplet --------------

async def test_quota_quotidien_pendant_un_lot(env):
    llm = GroqScenario(lots=[None, limite(par_jour=True)])
    ev, ligne, props = await demander(env, llm)
    assert props["statut"] == "incomplet" and props["raison"] == "quota" and props["tons"] == []
    assert props["manquants"] == 18                   # 2 tons × 3 longueurs × 3
    [entree] = [a for a in ligne["attachments"] if a["type"] == aide.TYPE]
    gardes = {t["nom"]: len(t["propositions"]) for t in entree["tons"]}
    assert gardes == {"Amical": 9, "Taquin": 9, "Naturel": 0, "Professionnel": 0}
    # Le texte principal reste une réponse normale, terminée.
    assert [e for e, _ in ev][-1] == "done"


async def test_limite_par_minute_attente_courte_puis_reprise_du_lot(env):
    llm = GroqScenario(lots=[None, limite(delai="0.05")])
    _, _, props = await demander(env, llm)
    verifier_complet(props)


# 9 + 10 + 12. Reprise sans doublon, restauration, identifiants stables -----------

async def test_reprise_sans_doublon_puis_restauration(env):
    llm = GroqScenario(lots=[None, limite(par_jour=True)])
    _, ligne, props = await demander(env, llm)
    avant = {x["id"] for t in ligne["attachments"][-1]["tons"] for x in t["propositions"]}
    assistants = len([r for r in env.supa.inserted if r["role"] == "assistant"])
    url = f"/api/v1/conversations/{CHAT}/messages/{ligne['id']}/propositions/completer"
    env.llm = GroqScenario()
    r = await env.client.post(url, headers=auth_headers())
    assert r.status_code == 200
    p = r.json()["propositions"]
    verifier_complet(p)
    # Seuls les deux tons manquants sont demandés ; le reste est intact.
    assert env.llm.demandes == [[("Naturel", {"court": 3, "moyen": 3, "long": 3}),
                                 ("Professionnel", {"court": 3, "moyen": 3, "long": 3})]]
    assert avant <= {x["id"] for t in p["tons"] for x in t["propositions"]}
    assert p["ensemble"] == ligne["id"]
    # Aucun second ensemble, aucune réponse ni consigne dupliquée.
    assert len([r for r in env.supa.inserted if r["role"] == "assistant"]) == assistants
    assert len([a for a in ligne["attachments"] if a["type"] == aide.TYPE]) == 1
    # Deuxième « Reprendre » : déjà complet, aucun appel à l'IA.
    env.llm = GroqScenario()
    r2 = await env.client.post(url, headers=auth_headers())
    assert r2.json()["propositions"]["tons"] == p["tons"] and env.llm.calls == []
    # Restauration (redémarrage) : même ensemble complet, mêmes identifiants.
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()
    restaure = next(i["propositions"] for i in items["items"] if i["message_id"] == ligne["id"])
    assert [x["id"] for t in restaure["tons"] for x in t["propositions"]] == [
        x["id"] for t in p["tons"] for x in t["propositions"]]
    # « Pourquoi la deuxième ? » : la bonne proposition (ton + longueur + rang).
    vise = next(x for x in combinaisons(p)[("Professionnel", "long")] if x["rang"] == 2)
    env.llm = FakeOpenAI(chunks=[chunk("Parce que."), chunk(usage=SimpleNamespace(prompt_tokens=10, completion_tokens=2))])
    await post(env, message="Pourquoi la deuxième ?", conversation_id=CHAT, whatsapp_analysis="allowed",
               ton_propose="Professionnel", longueur_proposee="long", propositions_message_id=ligne["id"])
    rappel = env.llm.calls[0]["messages"][-2]["content"]
    assert f"PROPOSITION VISÉE (identifiant {vise['id']}) : ton « Professionnel », longueur « Long », n° 2" in rappel


async def test_restauration_d_un_ensemble_incomplet_et_choix_impossible(env):
    llm = GroqScenario(lots=[None, limite(par_jour=True)])
    _, ligne, _ = await demander(env, llm)
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()
    restaure = next(i["propositions"] for i in items["items"] if i["message_id"] == ligne["id"])
    assert restaure["statut"] == "incomplet" and restaure["tons"] == []
    # Aucune proposition d'un ensemble incomplet ne peut être déclarée envoyée.
    pid = ligne["attachments"][-1]["tons"][0]["propositions"][0]["id"]
    r = await env.client.put(f"/api/v1/conversations/{CHAT}/messages/{ligne['id']}/propositions/{pid}/envoyee",
                             headers=auth_headers())
    assert r.status_code == 404


async def test_reprise_concurrente_refusee(env):
    llm = GroqScenario(lots=[None, limite(par_jour=True)])
    _, ligne, _ = await demander(env, llm)
    await env.redis.set(f"propgen:{ligne['id']}", "1")
    env.llm = GroqScenario()
    r = await env.client.post(f"/api/v1/conversations/{CHAT}/messages/{ligne['id']}/propositions/completer",
                              headers=auth_headers())
    assert r.status_code == 409 and r.json()["detail"]["code"] == "generation_en_cours"
    assert env.llm.calls == []


async def test_reprise_hors_compte_ou_hors_chat(env):
    r = await env.client.post(
        f"/api/v1/conversations/{CHAT}/messages/77777777-7777-7777-7777-777777777777/propositions/completer",
        headers=auth_headers())
    assert r.status_code == 404


# Annonce : tons, Professionnel, propositions déjà valides gardées -------------------

def test_annonce_tons_et_professionnel():
    e = generation.annoncer('<propositions mode="relance" tons="Taquin, Professionnel, Amical, Sérieux, Doux">'
                            "</propositions>", {}, "ctx", "dem")
    assert e.mode == "relance" and e.tons == ["Taquin", "Amical", "Sérieux", "Professionnel"]
    e2 = generation.annoncer("<propositions>\n</propositions>", {}, None)
    assert e2.tons == ["Naturel", "Chaleureux", "Direct", "Professionnel"]


# Correction finale : registre (tutoiement / vouvoiement) et Court concis ----------

def _ctx(lignes, groupe=False):
    from datetime import datetime
    from app.comprehension.moteur import contexte_joint, message_source
    ligne = {"id": "c", "contact_name": "Nora", "is_group": groupe, "current_user_name": "Alex",
             "participants": ["Nora", "Alex"], "created_at": "2026-10-15", "message_id": None,
             "context_messages": [{"count": len(lignes)}]}
    ctx = contexte_joint(ligne, "A")
    ctx.messages = [message_source(ctx, {"message_order": i, "author": a, "content": t, "id": f"m{i}",
                                         "kind": "text", "sent_at": datetime(2026, 10, 1, 9, i).isoformat()})
                    for i, (a, t) in enumerate(lignes)]
    return ctx


def test_registre_vouvoiement_tutoiement_incertain():
    vous = _ctx([("Nora", "Pourriez-vous m'envoyer votre rapport ?"), ("Alex", "Je vous l'envoie ce soir.")])
    tu = _ctx([("Nora", "Tu m'envoies le rapport ?"), ("Alex", "Je t'envoie ça, tu l'auras ce soir.")])
    rien = _ctx([("Nora", "Rapport reçu."), ("Alex", "Parfait.")])
    groupe = _ctx([("Nora", "Vous êtes prêts ? Votre démo est à 10 h."), ("Alex", "Vous verrez !")], groupe=True)
    assert generation.registre(vous) == generation.REGISTRE_VOUS
    assert generation.registre(tu) == generation.REGISTRE_TU
    assert generation.registre(rien) == generation.REGISTRE_INDETERMINE
    assert generation.registre(groupe) == generation.REGISTRE_INDETERMINE     # « vous » pluriel possible
    contexte, _ = generation.brief(tu, question="Aide-moi", analyse="Nora attend.", aujourd_hui=None)
    assert "se TUTOIENT" in contexte and "Professionnel compris" in contexte


def test_professionnel_garde_le_tutoiement_et_court_reste_court():
    e = generation.Ensemble(mode="reponse", context_id=None, tons=["Professionnel"],
                            registre=generation.REGISTRE_TU)
    brut = json.dumps({"tons": [{"nom": "Professionnel", "court": [
        {"texte": "Je vous envoie le rapport ce soir."},                 # vouvoie quelqu'un qu'on tutoie
        {"texte": "Je t'envoie le rapport ce soir."},                    # registre respecté
        {"texte": "Rapport envoyé ce soir, sans faute."},                # neutre
        {"texte": " ".join(["mot"] * 24) + "."},                          # trop long pour Court
    ]}]})
    assert e.integrer(brut, {}) == (2, 2)
    assert [p["texte"] for p in e.combos["Professionnel"]["court"]] == [
        "Je t'envoie le rapport ce soir.", "Rapport envoyé ce soir, sans faute."]
    v = generation.Ensemble(mode="reponse", context_id=None, tons=["Professionnel"],
                            registre=generation.REGISTRE_VOUS)
    assert v.integrer(json.dumps({"tons": [{"nom": "Professionnel", "court": [
        {"texte": "Tu as reçu le rapport ?"}, {"texte": "Avez-vous reçu le rapport ?"}]}]}), {}) == (1, 1)
    # Consignes du lot : Professionnel n'impose pas la distance.
    assert "deux personnes qui se tutoient restent au tutoiement" in generation.CONSIGNES_LOT


def test_sauts_de_ligne_en_rafale_reduits():
    e = generation.Ensemble(mode="reponse", context_id=None, tons=["Chaleureux"])
    brut = json.dumps({"tons": [{"nom": "Chaleureux", "moyen": [
        {"texte": "C'est tellement beau ! Samedi" + chr(10) * 4 + "Je suis impatient de te voir."}]}]})
    assert e.integrer(brut, {}) == (1, 0)
    assert e.combos["Chaleureux"]["moyen"][0]["texte"] == "C'est tellement beau ! Samedi Je suis impatient de te voir."


def test_indice_d_aide_sans_faux_positif():
    # Vu en réel : « réponse » seul réduisait le budget d'une simple analyse.
    from datetime import date
    from app.comprehension import reperes
    def aide(q):
        return reperes.analyser(q, [], date(2026, 10, 16)).aide_reponse
    assert not aide("JARVIS, que penses-tu de la dernière réponse de Lina ?")
    assert not aide("Sa réponse est bizarre, non ?")
    for q in ("aide moi", "Aide-moi à lui répondre", "Quelle réponse lui envoyer ?",
              "Propose-moi une réponse", "Comment la relancer ?", "Je veux une réponse pour elle"):
        assert aide(q), q


def test_plancher_des_messages_whatsapp():
    from app.comprehension.moteur import PLANCHER_MESSAGES
    from test_references import moquerie, preparer
    # Budget minuscule (partie fixe plus grande que le budget) : l'analyse
    # garde au moins le plancher, jamais quatre messages.
    _, p = preparer(moquerie() * 6, budget=1500)
    assert PLANCHER_MESSAGES == 1000 and len(p.fournis) >= 20

