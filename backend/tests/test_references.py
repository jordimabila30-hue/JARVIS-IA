"""Phase 2 : attribution des messages et références vérifiées.

Conversations fictives. Le modèle est simulé : on lui fait écrire des
réponses justes, fausses ou malveillantes, et on vérifie ce que le serveur
diffuse, enregistre et restitue.
"""

import json
import re
from datetime import date, datetime, timedelta
from types import SimpleNamespace

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import chat, contexts
from app.auth import get_current_user
from app.comprehension import reperes
from app.comprehension.moteur import MoteurComprehension, contexte_joint, message_source
from app.comprehension.references import FiltreReperes, Fourni, verifier
from app.config import get_settings
from app.quota import QuotaService, get_quota_service
from app.redis_client import get_redis
from app.supabase_client import get_supabase

from test_chat import USER, FakeOpenAI, auth_headers, chunk, fournisseur_test
from test_comprehension import (
    AUTRE, CHAT, CONSIGNE, CTX_HAPPY, CTX_PEPPER, FakeSupabase, ctx_row, donnees, msg,
)

settings = get_settings()


# --- Conversations fictives ------------------------------------------------

def moquerie():
    """Le cas du « mdr » : la réaction appartient à Pepper."""
    t = datetime(2026, 10, 12, 18, 40)
    lignes = [
        ("Pepper Potts", "Tu es en retard !"),
        ("Tony Stark", "Je suis une personne très demandée."),
        ("Pepper Potts", "mdr"),
        ("Tony Stark", "Arrête de te moquer !"),
        ("Tony Stark", "Bon, j'arrive dans 10 minutes."),
        ("Pepper Potts", "😂"),
        ("Pepper Potts", "Tu te prends pour un ministre maintenant ?"),
        ("Tony Stark", "Exactement, je suis très occupé."),
        ("Pepper Potts", "mdr"),
    ]
    return [msg(i, a, texte, t + timedelta(minutes=i), ctx="p") for i, (a, texte) in enumerate(lignes)]


def groupe():
    t = datetime(2026, 10, 13, 20, 0)
    lignes = [
        ("Happy Hogan", "Qui ramène les pizzas ?"),
        ("Rhodey", "Pas moi, j'ai payé la dernière fois"),
        ("Tony Stark", "Moi, comme d'habitude"),
        ("Happy Hogan", "haha"),
        ("Rhodey", "oui"),
    ]
    return [msg(i, a, texte, t + timedelta(minutes=i), ctx="g") for i, (a, texte) in enumerate(lignes)]


def preparer(rows, *, moi="Tony Stark", participants=None, question="Résume",
             incertaines=False, groupe_=False, budget=None, cites=None):
    ligne = ctx_row(CTX_PEPPER, "Pepper Potts" if not groupe_ else "Les Avengers", moi,
                    participants or ["Pepper Potts", "Tony Stark"], CONSIGNE, len(rows),
                    "2026-10-15T10:00:00+00:00", incertaines=incertaines)
    ligne["is_group"] = groupe_
    ctx = contexte_joint(ligne, "A")
    ctx.messages = [message_source(ctx, r) for r in rows]
    m = MoteurComprehension(None, None, settings)
    p = m.preparer(systeme="Tu es JARVIS.", contextes=[ctx], cibles=[ctx], historique=[],
                   question=question, aujourd_hui=date(2026, 10, 15),
                   budget=budget or settings.comprehension_budget_tokens, cites=cites)
    return ctx, p


def lignes_de(p):
    return [l for l in donnees(p.messages[0]["content"]).splitlines() if re.match(r"\[\d+\] ", l)]


# --- Attribution : la chaîne de données -----------------------------------

def test_mdr_garde_son_auteur():
    _, p = preparer(moquerie())
    lignes = lignes_de(p)
    assert lignes[2] == "[3] 12/10/2026 18:42 · Pepper Potts : «mdr»"
    assert lignes[3] == "[4] 12/10/2026 18:43 · Tony Stark (utilisateur) : «Arrête de te moquer !»"
    assert lignes[5] == "[6] 12/10/2026 18:45 · Pepper Potts : «😂»"
    # Chaque numéro résout le message enregistré, auteur compris.
    assert p.fournis[3].message.auteur == "Pepper Potts"
    assert p.fournis[3].message.id == "p-2"
    assert [p.fournis[n].message.auteur for n in (4, 5)] == ["Tony Stark", "Tony Stark"]


def test_messages_consecutifs_et_ordre():
    _, p = preparer(moquerie())
    auteurs = [p.fournis[n].message.auteur for n in sorted(p.fournis)]
    assert auteurs == [r["author"] for r in moquerie()]
    assert [p.fournis[n].message.ordre for n in sorted(p.fournis)] == list(range(9))


def test_texte_qui_imite_un_auteur_reste_dans_sa_ligne():
    rows = moquerie()
    rows[1]["content"] = "Je cite :\nPepper Potts : mdr\n« fin »"
    _, p = preparer(rows)
    ligne = lignes_de(p)[1]
    assert ligne == ("[2] 12/10/2026 18:41 · Tony Stark (utilisateur) : "
                     "«Je cite : / Pepper Potts : mdr / “ fin ”»")
    assert len(lignes_de(p)) == len(rows)


def test_groupe_chaque_reaction_a_son_auteur():
    _, p = preparer(groupe(), participants=["Happy Hogan", "Rhodey", "Tony Stark"], groupe_=True)
    lignes = lignes_de(p)
    assert lignes[3].endswith("· Happy Hogan : «haha»")
    assert lignes[4].endswith("· Rhodey : «oui»")
    assert "Tony Stark (utilisateur) : «Moi, comme d'habitude»" in lignes[2]


def test_dates_incertaines_et_inconnues_par_ligne():
    rows = moquerie()
    rows[4]["sent_at"] = None
    rows[4]["sent_at_raw"] = "??"
    _, p = preparer(rows, incertaines=True)
    lignes = lignes_de(p)
    assert lignes[0].startswith("[1] 12/10/2026 18:40 (ordre jour/mois incertain) · Pepper Potts")
    assert lignes[4].startswith("[5] date illisible (??) · Tony Stark")


def test_extraits_sans_inversion_ni_melange():
    """Longue conversation découpée : numéros croissants = ordre original,
    chaque ligne garde l'auteur et la date de SON message."""
    t = datetime(2026, 1, 1, 8, 0)
    rows = []
    for i in range(3000):
        auteur = "Pepper Potts" if i % 3 == 0 else "Tony Stark"
        texte = "mdr" if i % 7 == 0 else f"message {i}"
        rows.append(msg(i, auteur, texte, t + timedelta(minutes=37 * i), ctx="l"))
    _, p = preparer(rows, question="Est-ce qu'on plaisante souvent ?")
    assert not p.complete
    ordres = [p.fournis[n].message.ordre for n in sorted(p.fournis)]
    assert ordres == sorted(ordres)
    for ligne in lignes_de(p):
        n = int(re.match(r"\[(\d+)\]", ligne).group(1))
        m = rows[p.fournis[n].message.ordre]
        attendu_qui = "Tony Stark (utilisateur)" if m["author"] == "Tony Stark" else m["author"]
        quand = datetime.fromisoformat(m["sent_at"]).strftime("%d/%m/%Y %H:%M")
        assert ligne == f"[{n}] {quand} · {attendu_qui} : «{m['content']}»"


def test_deux_contacts_jamais_melanges_dans_la_numerotation():
    a = contexte_joint(ctx_row(CTX_PEPPER, "Pepper Potts", "Tony Stark", [], None, 9, "1"), "A")
    a.messages = [message_source(a, r) for r in moquerie()]
    b = contexte_joint(ctx_row(CTX_HAPPY, "Les Avengers", "Tony Stark", [], None, 5, "2"), "B")
    b.messages = [message_source(b, r) for r in groupe()]
    m = MoteurComprehension(None, None, settings)
    p = m.preparer(systeme="", contextes=[a, b], cibles=[a, b], historique=[], question="x",
                   aujourd_hui=date(2026, 10, 15), budget=6000)
    assert {p.fournis[n].contexte.id for n in range(1, 10)} == {CTX_PEPPER}
    assert {p.fournis[n].contexte.id for n in range(10, 15)} == {CTX_HAPPY}
    assert p.fournis[13].message.auteur == "Happy Hogan" and p.fournis[13].message.contenu == "haha"


# --- Filtre des repères (flux SSE) ---------------------------------------

def test_filtre_retire_les_reperes_meme_coupes():
    f = FiltreReperes()
    morceaux = ["C'est Pepper qui rit", " : « mdr » [", "[3", "]]. Tu", " réponds [[4, ", "5]] ensuite.", " Fin [2]"]
    visible = "".join(f.ajouter(m) for m in morceaux) + f.terminer()
    assert visible == "C'est Pepper qui rit : « mdr ». Tu réponds ensuite. Fin"
    assert [r.numeros for r in f.reperes] == [[3], [4, 5], [2]]
    assert visible[: f.reperes[0].position] == "C'est Pepper qui rit : « mdr »"
    assert "[" not in visible and "]" not in visible


def test_filtre_laisse_les_crochets_ordinaires():
    f = FiltreReperes()
    visible = f.ajouter("Un [mot] entre crochets") + f.terminer()
    assert visible == "Un [mot] entre crochets" and f.reperes == []


# --- Vérification ----------------------------------------------------------

def verif(texte_avec_reperes, rows=None):
    _, p = preparer(rows or moquerie())
    f = FiltreReperes()
    visible = f.ajouter(texte_avec_reperes) + f.terminer()
    return visible, verifier(visible, f.reperes, p.fournis)


def test_reference_valide_porte_les_donnees_de_supabase():
    visible, v = verif("Pepper a répondu « mdr » à ta remarque [[3]].")
    assert visible == "Pepper a répondu « mdr » à ta remarque."
    [ref] = v.references
    assert ref["context_id"] == CTX_PEPPER and ref["context_message_id"] == "p-2"
    assert ref["message_order"] == 2 and ref["author"] == "Pepper Potts" and not ref["is_me"]
    assert ref["excerpt"] == "mdr" and ref["sent_at"] == "2026-10-12T18:42:00"
    assert ref["date_label"] == "12/10/2026 18:42"
    assert v.note is None


def test_attribution_incorrecte_refusee():
    # Le modèle prétend que Tony (l'utilisateur) a écrit « mdr ».
    _, v = verif("Tu as écrit « mdr » juste après [[3]].")
    assert v.references == [] and v.attributions_contredites == 1
    assert "mauvaise personne" in v.note
    _, v = verif("Tony Stark a écrit mdr [[9]].")
    assert v.references == [] and v.attributions_contredites == 1


def test_citation_sans_repere_mal_attribuee_detectee():
    _, v = verif("Tony répond « Je suis une personne très demandée. » puis Tony écrit « mdr ».")
    # La première citation est vérifiée (bon auteur) ; la seconde contredit
    # les messages : aucune référence fausse, un avertissement.
    assert [r["context_message_id"] for r in v.references] == ["p-1"]
    assert v.attributions_contredites == 1


def test_reference_inexistante_refusee():
    _, v = verif("Elle le dit clairement [[99]].")
    assert v.references == [] and v.refusees == 1
    assert "pas pu être vérifiées" in v.note


def test_citation_qui_ne_correspond_pas_au_message_refusee():
    _, v = verif("Pepper a écrit « Je t'adore » [[3]].")
    assert v.references == [] and v.refusees == 1


def test_citation_inventee_signalee():
    _, v = verif("Elle a dit « tu ne changeras jamais Tony ».")
    assert v.references == [] and v.citations_introuvables == 1
    assert "reformulation" in v.note


def test_pronom_dans_la_citation_ne_designe_pas_l_auteur():
    # « te » est dans la citation de Tony, pas dans la phrase de JARVIS.
    _, v = verif("Tony Stark lui répond « Arrête de te moquer ! » [[4]].")
    assert [r["author"] for r in v.references] == ["Tony Stark"]


def test_phrase_ambigue_acceptee_auteur_reel_affiche():
    _, v = verif("Vous deux vous taquinez souvent [[3, 4]].")
    assert [r["author"] for r in v.references] == ["Pepper Potts", "Tony Stark"]


def test_limite_et_doublons():
    # Un repère groupé n'en garde que 3 ; au total 6 au plus, sans doublon.
    _, v = verif("Exemples [[1, 2, 3, 4, 5, 6, 7, 8]]. Encore [[1]]. Et [[5]]. Et [[6, 7]]. Et [[8, 9]].")
    assert [r["message_order"] for r in v.references] == [0, 1, 2, 4, 5, 6]
    assert [r["rang"] for r in v.references] == list(range(6))
    assert v.refusees == 0


def test_repere_groupe_autour_d_une_citation():
    # [[1, 2, 3]] + une citation : le message cité est gardé, les autres
    # écartés sans compter comme refus.
    _, v = verif("Pepper commence : « Tu es en retard ! » [[1, 2, 3]].")
    assert [r["message_order"] for r in v.references] == [0]
    assert v.refusees == 0 and v.note is None
    # Aucun message du groupe ne correspond : refus.
    _, v = verif("Pepper dit « Je t'adore » [[1, 2]].")
    assert v.references == [] and v.refusees == 1


def test_mdr_court_ambigu_sans_repere_non_rattache():
    # « mdr » existe deux fois (Pepper) : pas de rattachement au hasard.
    _, v = verif("Elle écrit souvent « mdr ».")
    assert v.references == [] and v.attributions_contredites == 0


# --- Intégration : flux, enregistrement, restauration ---------------------

@pytest_asyncio.fixture
async def env(redis):
    supa = FakeSupabase()
    supa.context_messages[CTX_PEPPER] = moquerie()
    supa.contexts[0]["context_messages"] = [{"count": len(moquerie())}]
    service = QuotaService(redis, supa)
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    app.include_router(contexts.conversations_router, prefix="/api/v1")
    app.dependency_overrides[get_quota_service] = lambda: service
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    app.dependency_overrides[chat.get_fournisseur] = lambda: fournisseur_test(e.llm)
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    e = SimpleNamespace(client=client, supa=supa, redis=redis, llm=None)
    yield e
    await client.aclose()


def reponse(*fragments):
    return FakeOpenAI(chunks=[*(chunk(f) for f in fragments),
                              chunk(usage=SimpleNamespace(prompt_tokens=900, completion_tokens=60))])


async def post(env, **body):
    resp = await env.client.post("/api/v1/chat/stream", json=body, headers=auth_headers())
    await chat.wait_background_tasks()
    return resp


def evenements(raw):
    out = []
    for bloc in raw.strip().split("\n\n"):
        if bloc.startswith(":"):
            continue
        champs = dict(l.split(": ", 1) for l in bloc.splitlines())
        out.append((champs["event"], json.loads(champs["data"])))
    return out


async def test_flux_sans_repere_visible_puis_references(env):
    env.llm = reponse("Oui, vous vous taquinez : Pepper répond « mdr » [", "[3]] et tu ",
                      "répliques « Arrête de te moquer ! » [[4]].")
    resp = await post(env, message="On plaisante souvent ?", conversation_id=CHAT,
                      whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    noms = [e for e, _ in ev]
    assert noms[0] == "meta" and noms[-2:] == ["references", "done"]
    assert set(noms[1:-2]) == {"delta"}
    texte = "".join(d["text"] for e, d in ev if e == "delta")
    assert texte == "Oui, vous vous taquinez : Pepper répond « mdr » et tu répliques « Arrête de te moquer ! »."
    assert not re.search(r"\[|\]|\bA\d+\b", texte)
    refs = ev[-2][1]["references"]
    assert [(r["author"], r["excerpt"]) for r in refs] == [
        ("Pepper Potts", "mdr"), ("Tony Stark", "Arrête de te moquer !")]
    assert ev[-2][1]["message_id"] == ev[0][1]["message_id"]
    # Enregistré : texte propre + identifiants dans la même ligne.
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert ligne["content"] == texte
    assert [a["context_message_id"] for a in ligne["attachments"]] == ["p-2", "p-3"]
    assert all(a["type"] == "reference_whatsapp" for a in ligne["attachments"])


async def test_restauration_relit_supabase(env):
    env.llm = reponse("Pepper répond « mdr » [[3]].")
    await post(env, message="x", conversation_id=CHAT, whatsapp_analysis="allowed")
    resp = await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())
    assert resp.status_code == 200
    [r] = resp.json()["items"]
    [ref] = r["references"]
    assert (ref["author"], ref["excerpt"], ref["message_order"]) == ("Pepper Potts", "mdr", 2)
    assert ref["date_label"] == "12/10/2026 18:42" and ref["contact_name"] == "Pepper Potts"
    # Le message n'existe plus (pièce jointe supprimée) : plus de référence.
    env.supa.context_messages[CTX_PEPPER] = []
    resp = await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())
    assert resp.json() == {"items": []}


async def test_restauration_autre_compte_et_identifiant_force(env):
    env.llm = reponse("Pepper répond « mdr » [[3]].")
    await post(env, message="x", conversation_id=CHAT, whatsapp_analysis="allowed")
    # Une entrée modifiée pour viser le message d'un autre compte.
    ligne = [r for r in env.supa.inserted if r["role"] == "assistant"][0]
    ligne["attachments"].append({"type": "reference_whatsapp", "context_id": "autre",
                                 "context_message_id": "z-1", "message_order": 1, "rang": 1})
    env.supa.contexts.append(ctx_row("autre", "Natasha", "Tony", [], None, 1, "3", user=AUTRE))
    env.supa.context_messages["autre"] = [msg(1, "Natasha", "secret", ctx="z")]
    resp = await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())
    [r] = resp.json()["items"]
    assert [x["context_message_id"] for x in r["references"]] == ["p-2"]
    # Conversation d'un autre compte : 404.
    resp = await env.client.get("/api/v1/conversations/22222222-2222-2222-2222-222222222222/references",
                                headers=auth_headers())
    assert resp.status_code == 404


async def test_pourquoi_refournit_les_messages_cites(env):
    rows = []
    t = datetime(2026, 1, 1, 8, 0)
    for i in range(3000):
        rows.append(msg(i, "Pepper Potts" if i % 2 else "Tony Stark", f"message {i}", t + timedelta(hours=i), ctx="q"))
    rows[1501]["content"] = "mdr, Bangkok alors"
    env.supa.context_messages[CTX_PEPPER] = rows
    env.supa.contexts[0]["context_messages"] = [{"count": 3000}]
    # Première réponse : elle cite le message 1501 s'il est fourni.
    # Citation sans repère, unique et cohérente : rattachée par le serveur.
    env.llm = reponse("Pepper écrit « mdr, Bangkok alors ».")
    await post(env, message="Que dit-elle de Bangkok ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert [a["message_order"] for a in ligne["attachments"]] == [1501]
    # « Pourquoi ? » : le message cité revient, même sans mot commun.
    env.llm = reponse("Parce que.")
    await post(env, message="Pourquoi tu dis ça ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    envoye = env.llm.calls[0]["messages"][0]["content"]
    assert "«mdr, Bangkok alors»" in envoye
    assert "messages cités dans les réponses précédentes" in envoye
    # Ses voisins aussi, pour le contexte.
    assert "«message 1500»" in envoye and "«message 1502»" in envoye


async def test_chat_ordinaire_sans_filtre_ni_references(env):
    env.supa.contexts = []
    env.llm = reponse("La liste [1] et [[2]] reste telle quelle.")
    resp = await post(env, message="Bonjour", conversation_id=CHAT)
    ev = evenements(resp.text)
    assert "references" not in [e for e, _ in ev]
    assert "".join(d["text"] for e, d in ev if e == "delta") == "La liste [1] et [[2]] reste telle quelle."


async def test_refus_ne_fournit_aucun_numero(env):
    env.llm = reponse("Je ne peux pas lire [[3]].")
    resp = await post(env, message="x", conversation_id=CHAT, whatsapp_analysis="declined")
    ev = evenements(resp.text)
    assert "references" not in [e for e, _ in ev]
    assert "«mdr»" not in env.llm.calls[0]["messages"][0]["content"]


def test_reperes_question_precise_dernier_message():
    r = reperes.analyser("Montre-moi son dernier message", [], date(2026, 10, 15))
    assert r.fin


def test_filtre_formes_relachees_du_modele():
    """Formes vues avec le vrai modèle : plages à tiret insécable,
    « (message 5) », « …», message 22 »."""
    f = FiltreReperes()
    brut = ("Pepper ironise (« Super. Génial. », message 22 puis « Trois alarmes. », message 24). "
            "Elle taquine [[20‑24]]. Voir (message 5). Le message 7 est clair.")
    visible = "".join(f.ajouter(brut[i:i + 4]) for i in range(0, len(brut), 4)) + f.terminer()
    assert visible == ("Pepper ironise (« Super. Génial. » puis « Trois alarmes. »). "
                       "Elle taquine. Voir. Le message est clair.")
    assert [r.numeros for r in f.reperes] == [[22], [24], [20, 21, 22, 24], [5], [7]]
    assert not re.search(r"\d", visible)


def test_ponctuation_dans_une_citation_ne_coupe_pas_la_phrase():
    # Erreur réelle du modèle : « Explosent… » est de Tony, pas de Pepper.
    rows = [
        msg(0, "Pepper Potts", "On peut parler du budget ?", datetime(2026, 10, 3, 12, 0), ctx="b"),
        msg(1, "Tony Stark", "Explosent comme dans 'beaucoup' ou comme dans 'boum' ?",
            datetime(2026, 10, 3, 12, 30), ctx="b"),
    ]
    _, v = verif("Pepper commence par une blague (« Explosent comme dans 'beaucoup' ou comme "
                 "dans 'boum' ? », message 2).", rows)
    assert v.references == [] and v.attributions_contredites == 1



def test_possessif_ou_complement_ne_designe_pas_l_auteur():
    # « ton oubli », « elle te taquine » : l'utilisateur n'est pas l'auteur.
    _, v = verif("Elle vient de souligner ton retard (« Tu es en retard ! ») [[1]].")
    assert [r["author"] for r in v.references] == ["Pepper Potts"]
    assert v.attributions_contredites == 0
    _, v = verif("Pepper te taquine souvent, et tu prolonges la blague [[3, 4]].")
    assert [r["author"] for r in v.references] == ["Pepper Potts", "Tony Stark"]
    assert v.attributions_contredites == 0


async def test_battement_pendant_un_long_silence_du_modele(env, monkeypatch):
    """Le modèle réfléchit longtemps avant d'écrire : le flux reste vivant
    (commentaires SSE), puis la réponse arrive normalement."""
    import asyncio

    monkeypatch.setattr(chat, "SILENCE_MAX_FLUX", 0.05)

    class Lent(FakeOpenAI):
        async def _create(self, **kwargs):
            self.calls.append(kwargs)

            async def gen():
                await asyncio.sleep(0.2)
                yield chunk("Réponse après réflexion.")
                yield chunk(usage=SimpleNamespace(prompt_tokens=10, completion_tokens=5))
            return gen()

    env.llm = Lent()
    monkeypatch.setattr(chat._avec_battement, "__defaults__", (0.05,))
    resp = await post(env, message="x", conversation_id=CHAT, whatsapp_analysis="allowed")
    assert resp.text.count(": le modele reflechit") >= 2
    ev = evenements(resp.text)
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Réponse après réflexion."
    assert ev[-1][0] == "done"
