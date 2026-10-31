"""Optimisations 72 (résumé des longues conversations) et 73 (cache de
prompt Claude) : règles de déclenchement, d'invalidation et de placement.
Tests unitaires (aucun appel réel) ; la fidélité se mesure avec le vrai
fournisseur (voir AVANCEMENT.md)."""

import json

import pytest

from app import resume
from app.llm.anthropic import convertir
from app.llm.base import ReponseJSON, Usage


class FauxSupabase:
    def __init__(self, messages):
        self.messages = messages
        self.lectures = []

    async def count_messages(self, conversation_id):
        return len(self.messages)

    async def get_messages_range(self, conversation_id, *, offset, limit):
        self.lectures.append((offset, limit))
        return self.messages[offset:offset + limit]


class FauxLLM:
    def __init__(self, donnees):
        self.donnees = donnees
        self.appels = []

    async def json(self, messages, *, max_sortie, schema=None, effort=None):
        self.appels.append(messages)
        return ReponseJSON(texte=json.dumps(self.donnees), donnees=self.donnees,
                           usage=Usage(entree=800, sortie=120), modele="test")


def conversation(n):
    return [{"role": "user" if i % 2 == 0 else "assistant", "content": f"message {i + 1}"} for i in range(n)]


RESUME = {"faits": ["Réunion jeudi 10 h"], "decisions": ["d'abord mardi, puis changé en jeudi"],
          "incertitudes": ["« le dossier » : deux dossiers possibles"]}


def test_a_recalculer_seuils():
    assert resume.a_recalculer(None, 20, 20) == 0          # tout tient dans la fenêtre
    assert resume.a_recalculer(None, 29, 20) == 0          # moins de PAS messages anciens
    assert resume.a_recalculer(None, 30, 20) == 10
    assert resume.a_recalculer({"couvre": 10}, 35, 20) == 0
    assert resume.a_recalculer({"couvre": 10}, 40, 20) == 20
    assert resume.a_recalculer({"couvre": 30}, 40, 20) == 20  # messages supprimés : tout refaire


def test_bloc_distingue_faits_decisions_incertitudes():
    texte = resume.bloc(RESUME)
    assert texte.startswith("<memoire_conversation>")
    assert "Faits confirmés :\n- Réunion jeudi 10 h" in texte
    assert "Décisions (dernière version) :" in texte
    assert "Incertitudes :" in texte
    assert "pose une courte question" in texte
    assert resume.bloc({"faits": [], "decisions": [], "incertitudes": []}) == ""


async def test_conversation_courte_aucun_appel(redis):
    llm = FauxLLM(RESUME)
    r = await resume.mettre_a_jour(redis=redis, supabase=FauxSupabase(conversation(24)), llm=llm,
                                   conversation_id="c1", fenetre=20, ttl=60)
    assert r is None and llm.appels == []


async def test_resume_cree_puis_incremental(redis):
    supa = FauxSupabase(conversation(30))
    llm = FauxLLM(RESUME)
    r = await resume.mettre_a_jour(redis=redis, supabase=supa, llm=llm, conversation_id="c1", fenetre=20, ttl=60)
    assert r == (800, 120)
    assert supa.lectures == [(0, 10)]
    enregistre = await resume.lire(redis, "c1")
    assert enregistre["couvre"] == 10 and enregistre["faits"] == RESUME["faits"]

    # 5 messages de plus : sous le PAS, rien.
    supa.messages = conversation(35)
    assert await resume.mettre_a_jour(redis=redis, supabase=supa, llm=llm, conversation_id="c1",
                                      fenetre=20, ttl=60) is None
    # 10 de plus : seuls les messages 11 à 20 sont relus, avec l'ancien résumé.
    supa.messages = conversation(40)
    await resume.mettre_a_jour(redis=redis, supabase=supa, llm=llm, conversation_id="c1", fenetre=20, ttl=60)
    assert supa.lectures[-1] == (10, 10)
    contenu = llm.appels[-1][1]["content"]
    assert "Résumé précédent (messages 1 à 10)" in contenu
    assert "message 11" in contenu and "message 20" in contenu and "message 21" not in contenu


async def test_resume_vide_jamais_enregistre(redis):
    llm = FauxLLM({"faits": [], "decisions": [], "incertitudes": []})
    await resume.mettre_a_jour(redis=redis, supabase=FauxSupabase(conversation(30)), llm=llm,
                               conversation_id="c2", fenetre=20, ttl=60)
    assert await resume.lire(redis, "c2") is None


async def test_conversation_raccourcie_resume_efface(redis):
    llm = FauxLLM(RESUME)
    supa = FauxSupabase(conversation(30))
    await resume.mettre_a_jour(redis=redis, supabase=supa, llm=llm, conversation_id="c3", fenetre=20, ttl=60)
    supa.messages = conversation(12)
    await resume.mettre_a_jour(redis=redis, supabase=supa, llm=llm, conversation_id="c3", fenetre=20, ttl=60)
    assert await resume.lire(redis, "c3") is None


def test_cache_sur_le_dernier_message_de_l_historique_seulement():
    systeme, tours = convertir([
        {"role": "system", "content": "Tu es JARVIS."},
        {"role": "user", "content": "Ancienne question"},
        {"role": "assistant", "content": "Ancienne réponse", "cache": True},
        {"role": "system", "content": "Date et heure locales : samedi 31 octobre 2026, 10:12."},
        {"role": "user", "content": "Nouvelle question"},
    ])
    assert "10:12" not in systeme          # l'heure ne casse plus le préfixe
    assert tours[1]["content"][-1]["cache_control"] == {"type": "ephemeral"}
    derniere = tours[-1]["content"]
    assert all("cache_control" not in b for b in derniere)
    assert "10:12" in derniere[0]["text"] and derniere[-1]["text"] == "Nouvelle question"


@pytest.fixture
async def redis():
    import fakeredis.aioredis
    r = fakeredis.aioredis.FakeRedis(decode_responses=True)
    yield r
    await r.aclose()


def test_odo_garde_le_detail_du_cache_sans_changer_le_total():
    """Opt. 73 : avec ODO, le détail du cache restait invisible (fondu dans
    l'entrée) ; le total compté au quota reste identique."""
    from app.odo.orchestrateur import ExecutionODO

    ex = object.__new__(ExecutionODO)
    ex.entree = ex.sortie = ex.cache_lecture = ex.cache_ecriture = 0
    ex._cumuler(Usage(entree=100, sortie=20, cache_lecture=900, cache_ecriture=0))
    ex._cumuler(Usage(entree=50, sortie=10, cache_lecture=0, cache_ecriture=300))
    u = ex._usage()
    assert (u.cache_lecture, u.cache_ecriture, u.sortie) == (900, 300, 30)
    assert u.entree_totale == 100 + 900 + 50 + 300
