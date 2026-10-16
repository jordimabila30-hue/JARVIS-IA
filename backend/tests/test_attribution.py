"""Correction des attributions AVANT diffusion (app/comprehension/attribution.py).

Le modèle est simulé : il prête des messages à la mauvaise personne. On
vérifie que la phrase fausse n'est jamais diffusée (même en morceaux),
qu'elle est remplacée par une phrase vraie quand la preuve est nette,
reformulée quand plusieurs auteurs sont possibles, écartée sinon, et que
les interprétations ne sont pas touchées.
"""

from datetime import datetime, timedelta

from app.comprehension.attribution import CorrecteurAttributions, phrases
from app.comprehension.references import FiltreReperes, verifier

from test_comprehension import CHAT, msg
from test_references import env, evenements, groupe, moquerie, post, preparer, reponse  # noqa: F401


def corriger(texte, rows=None, *, morceau=None, **options):
    """(texte diffusé, morceaux diffusés, vérification)."""
    _, p = preparer(rows or moquerie(), **options)
    c = CorrecteurAttributions(p.fournis)
    f = FiltreReperes(c)
    pas = morceau or len(texte)
    diffuses = [f.ajouter(texte[i:i + pas]) for i in range(0, len(texte), pas)]
    diffuses.append(f.terminer())
    v = verifier(f.visible, f.reperes, p.fournis)
    v.corrigees, v.ecartees = c.corrigees, c.ecartees
    return f.visible, [d for d in diffuses if d], v


def groupe_oui():
    """« oui » écrit par Rhodey ET par l'utilisateur (Tony)."""
    rows = groupe()
    t = datetime(2026, 10, 13, 20, 10)
    rows.append(msg(5, "Tony Stark", "oui", t, ctx="g"))
    return rows


GROUPE = dict(participants=["Happy Hogan", "Rhodey", "Tony Stark"], groupe_=True)


# --- Deux participants --------------------------------------------------

def test_reaction_courte_pretee_a_l_utilisateur_corrigee():
    visible, _, v = corriger("Tu as écrit « mdr » juste après [[3]]. Ensuite elle insiste.")
    assert visible == "C'est Pepper Potts qui a écrit « mdr ». Ensuite elle insiste."
    [ref] = v.references
    assert (ref["author"], ref["excerpt"], ref["context_message_id"]) == ("Pepper Potts", "mdr", "p-2")
    assert v.corrigees == 1 and v.attributions_contredites == 0
    assert "rectifié" in v.note and "mauvaise personne" not in v.note


def test_repere_sans_citation_corrige_avec_le_message_original():
    visible, _, v = corriger("Tony Stark a écrit mdr [[9]].")
    assert visible == "C'est Pepper Potts qui a écrit « mdr »."
    assert [r["message_order"] for r in v.references] == [8]


def test_utilisateur_reconnu_comme_auteur_reel():
    rows = [
        msg(0, "Pepper Potts", "On peut parler du budget ?", datetime(2026, 10, 3, 12, 0), ctx="b"),
        msg(1, "Tony Stark", "Explosent comme dans 'beaucoup' ou comme dans 'boum' ?",
            datetime(2026, 10, 3, 12, 30), ctx="b"),
    ]
    visible, _, v = corriger("Pepper commence par une blague (« Explosent comme dans 'beaucoup' ou "
                             "comme dans 'boum' ? », message 2). Puis elle revient au budget [[1]].", rows)
    assert visible == ("C'est toi qui as écrit « Explosent comme dans 'beaucoup' ou comme dans "
                       "'boum' ? ». Puis elle revient au budget.")
    assert [(r["author"], r["is_me"]) for r in v.references] == [("Tony Stark", True), ("Pepper Potts", False)]


def test_citation_sans_repere_auteur_unique_corrigee_sans_reference_au_hasard():
    # « mdr » existe deux fois, toujours de Pepper : l'auteur est certain,
    # le message ne l'est pas (aucune carte choisie au hasard).
    visible, _, v = corriger("Tony écrit « mdr » pour la taquiner.")
    assert visible == "C'est Pepper Potts qui a écrit « mdr »."
    assert v.references == [] and v.corrigees == 1


def test_attribution_juste_et_interpretation_intactes():
    texte = ("Pepper écrit « mdr » [[3]], elle plaisante sans doute. "
             "Tu sembles vexé, mais c'est peut-être du second degré [[4]].")
    visible, _, v = corriger(texte)
    assert visible == ("Pepper écrit « mdr », elle plaisante sans doute. "
                       "Tu sembles vexé, mais c'est peut-être du second degré.")
    assert v.corrigees == 0 and v.ecartees == 0 and v.note is None
    assert [r["author"] for r in v.references] == ["Pepper Potts", "Tony Stark"]


def test_incise_au_tiret_ne_prete_pas_le_tu_a_la_suite():
    # Cas réel (GroqCloud, 2026-10-16) : le « tu » de l'incise visait le
    # message de l'utilisateur ; ce qui suit le tiret a pour sujet « elle ».
    texte = ("Après que tu aies dit « Je suis une personne très demandée. » [[2]] — elle a "
             "d'abord ri (« mdr » [[3]]) puis a ajouté « Tu te prends pour un ministre "
             "maintenant ? » [[7]]. Ensuite elle insiste.")
    visible, _, v = corriger(texte)
    assert visible == ("Après que tu aies dit « Je suis une personne très demandée. » — elle a "
                       "d'abord ri (« mdr ») puis a ajouté « Tu te prends pour un ministre "
                       "maintenant ? ». Ensuite elle insiste.")
    assert v.corrigees == 0 and v.attributions_contredites == 0
    assert [r["author"] for r in v.references] == ["Tony Stark", "Pepper Potts", "Pepper Potts"]


def test_tiret_garde_la_correction_d_une_vraie_erreur():
    visible, _, v = corriger("Sans surprise — tu as écrit « mdr » [[3]].")
    assert visible == "C'est Pepper Potts qui a écrit « mdr »."
    assert v.corrigees == 1


def test_citation_originale_jamais_modifiee():
    visible, _, _ = corriger("Tu lui demandes « Tu te prends pour un ministre maintenant ? » [[7]].")
    assert "« Tu te prends pour un ministre maintenant ? »" in visible
    assert visible.startswith("C'est Pepper Potts qui a écrit")


# --- Groupes ---------------------------------------------------------------

def test_groupe_reaction_courte_corrigee():
    visible, _, v = corriger("Rhodey a répondu « haha » à ta proposition.", groupe(), **GROUPE)
    assert visible == "C'est Happy Hogan qui a écrit « haha »."
    assert [r["author"] for r in v.references] == ["Happy Hogan"]


def test_groupe_citation_ambigue_reformulee_sans_choisir():
    visible, _, v = corriger("Happy a écrit « oui ».", groupe_oui(), **GROUPE)
    assert visible == "« oui » apparaît dans des messages de Rhodey et de toi."
    assert v.references == [] and v.corrigees == 1


def test_citation_ambigue_mais_compatible_laissee():
    # Rhodey a bien écrit « oui » (Tony aussi) : rien de faux.
    visible, _, v = corriger("Rhodey a écrit « oui ».", groupe_oui(), **GROUPE)
    assert visible == "Rhodey a écrit « oui »." and v.corrigees == 0


def test_phrase_trop_confuse_ecartee():
    # Trois attributions fausses dans une même phrase : rien à sauver.
    texte = ("Happy écrit « Pas moi, j'ai payé la dernière fois », Happy ajoute « Moi, comme "
             "d'habitude » et Happy finit par « oui ». Ensuite tout le monde rit.")
    visible, _, v = corriger(texte, groupe(), **GROUPE)
    assert visible == "Ensuite tout le monde rit."
    assert v.ecartees == 1 and "retiré" in v.note


# --- Flux SSE : rien de faux, même un instant ------------------------------

def test_flux_jamais_de_passage_faux_meme_par_morceaux():
    texte = "Oui. Tu as écrit « mdr » juste après [[3]]. Puis Pepper rit encore [[6]]."
    for pas in (1, 3, 7):
        visible, diffuses, _ = corriger(texte, morceau=pas)
        assert "Tu as écrit" not in "".join(diffuses)
        assert all("Tu as" not in d for d in diffuses)
        assert visible == "Oui. C'est Pepper Potts qui a écrit « mdr ». Puis Pepper rit encore."


def test_decoupage_jamais_dans_une_citation():
    assert phrases("Elle dit « Super. Génial. » puis part. Fin.") == [(0, 39), (39, 43)]


async def test_route_corrige_avant_diffusion_et_enregistre_le_texte_juste(env):
    env.llm = reponse("Tu as écrit « m", "dr » juste après [", "[3]]. Elle te taquine.")
    resp = await post(env, message="Qui a dit mdr ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    deltas = [d["text"] for e, d in ev if e == "delta"]
    assert all("Tu as écrit" not in d for d in deltas)
    texte = "".join(deltas)
    assert texte == "C'est Pepper Potts qui a écrit « mdr ». Elle te taquine."
    refs = next(d for e, d in ev if e == "references")
    assert [r["context_message_id"] for r in refs["references"]] == ["p-2"]
    assert "rectifié" in refs["note"]
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert ligne["content"] == texte
    assert ligne["attachments"][-1] == {"type": "note_references", "text": refs["note"]}


async def test_question_de_suivi_corrigee_aussi(env):
    env.llm = reponse("Pepper te taquine [[7]].")
    await post(env, message="Elle me taquine ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    # Suivi : le modèle se trompe d'auteur cette fois.
    env.llm = reponse("Oui, et c'est toi qui conclus avec « mdr » [[9]].")
    resp = await post(env, message="Et qui a eu le dernier mot ?", conversation_id=CHAT,
                      whatsapp_analysis="allowed")
    texte = "".join(d["text"] for e, d in evenements(resp.text) if e == "delta")
    assert texte == "C'est Pepper Potts qui a écrit « mdr »."
    # L'historique envoyé au modèle pour ce suivi contient la réponse précédente.
    historique = env.llm.calls[0]["messages"]
    assert any(m["role"] == "assistant" and m["content"] == "Pepper te taquine." for m in historique)


def test_longue_conversation_reaction_dans_les_extraits():
    t = datetime(2026, 1, 1, 8, 0)
    rows = [msg(i, "Pepper Potts" if i % 2 else "Tony Stark", f"message {i}", t + timedelta(minutes=i), ctx="l")
            for i in range(3000)]
    rows[-1]["content"] = "ptdr"
    _, p = preparer(rows, question="Qui a écrit le dernier message ?")
    numero = max(p.fournis)
    assert p.fournis[numero].message.contenu == "ptdr"
    visible, _, v = corriger(f"Tu as répondu « ptdr » [[{numero}]].", rows,
                             question="Qui a écrit le dernier message ?")
    assert visible == "C'est Pepper Potts qui a écrit « ptdr »."
