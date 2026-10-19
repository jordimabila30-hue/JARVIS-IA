"""Optimisation de la compréhension conversationnelle : jeu d'évaluation
DÉTERMINISTE (scenarios_comprehension.py) et état partagé (etat.py).

Ces tests vérifient ce que le moteur PRÉPARE (message visé, messages
fournis, chronologie, informations transmises aux lots, validation des
longueurs) ; ils ne prouvent rien sur la qualité linguistique des réponses,
jugée sur les essais réels (evaluation_comprehension.py --reel).
"""

import json

import pytest

from app.comprehension import etat, generation
from app.comprehension.moteur import message_source

from evaluation_comprehension import brief_lots, construire, controler, preparer
from scenarios_comprehension import PAR_ID, SCENARIOS
from test_campagne import contexte, pytestmark  # noqa: F401  (exports absents : ignorés)


@pytest.mark.parametrize("sid", [s.id for s in SCENARIOS])
def test_scenario(sid):
    echecs = [f"[{c}] {t}" for c, t, ok in controler(PAR_ID[sid]) if not ok and c != "budget"]
    assert not echecs, echecs


# --- État partagé -----------------------------------------------------------------

def test_habitudes_par_personne_et_evolution_recente():
    ctx = contexte("JARVIS_TEST_GROUPE.zip")
    hs = {h.auteur: h for h in etat.habitudes(ctx)}
    assert set(hs) == {"Alex Martin", "Lina Moreau", "Samuel Petit", "Maya Martin", "Nora Laurent"}
    # Chacun ses habitudes : jamais celles d'un autre.
    assert hs["Alex Martin"].rires > hs["Nora Laurent"].rires
    ligne = etat.ligne_habitude(hs["Alex Martin"], ctx)
    assert ligne.startswith("Alex Martin [utilisateur]") and "tutoie" in ligne


def test_jalons_derniere_decision():
    ctx = contexte("JARVIS_TEST_FAMILLE.zip")
    textes = [ctx.messages[i].contenu for i in etat.jalons(ctx)]
    assert "Finalement on déplace la fête au samedi 20 juin, papa a un séminaire le 13" in textes


def test_indices_de_gravite_et_proportion():
    s = PAR_ID["serieux_apres_humour"]
    ctx, _, _ = construire(s)
    assert etat.grave(ctx)
    assert etat.proportion(ctx) == etat.PROPORTION_NORMALE
    court, _, _ = construire(PAR_ID["message_tres_court"])
    assert etat.proportion(court) == etat.PROPORTION_LEGERE and not etat.grave(court)


def test_fil_place_la_declaration_avant_la_reponse_recue():
    s = PAR_ID["envoyee_puis_recue"]
    ctx, envoyees, _ = construire(s)
    suite = etat.fil(ctx, envoyees[ctx.id])
    fin = [e.declaration["texte"] if e.declaration else e.message.contenu for e in suite[-3:]]
    assert fin == ["Tu aurais pu me prévenir que tu rentrais aussi tard…",
                   "Tu as raison, promis la prochaine fois je te préviens plus tôt 😊",
                   "Mouais. On verra bien 🙄"]
    # Déjà présente comme message (export ou ajout) : jamais comptée deux fois.
    doublon = [{**envoyees[ctx.id][0], "dans_export": True}]
    assert not any(e.declaration for e in etat.fil(ctx, doublon))


def test_declaration_sans_repere_apres_tout():
    ctx = contexte("JARVIS_TEST_SENTIMENTAL.zip")
    ordre = ctx.messages[-1].ordre + 1
    ctx.messages.append(message_source(ctx, {"id": "a", "message_order": ordre, "author": "Lina Moreau",
                                             "content": "Ok", "kind": "text", "origin": "manual_received"}))
    suite = etat.fil(ctx, [{"texte": "Promis", "declared_at": "2026-10-16T18:00:00+00:00"}])
    assert suite[-1].declaration is not None      # ajout sans date d'enregistrement : ordre inconnu


def _vise(sid):
    s = PAR_ID[sid]
    ctx, envoyees, historique = construire(s)
    _, p, _ = preparer(s, ctx, envoyees, historique)
    texte = "\n".join(m["content"] for m in p.messages)
    return texte[texte.index("<message_vise>"): texte.index("</message_vise>")]


def test_echange_en_cours_separe_des_anciennes_blagues():
    """Vu en réel : le pardon qui suit un reproche collé à la main était lu
    à la lumière de la blague du « traitement » (fin de l'export)."""
    bloc = _vise("pardon_reproche")
    en_cours = bloc.split("Échange en cours", 1)[1]
    assert "Tu as encore oublié de m'appeler" in en_cours and "traitement" not in bloc
    # Message collé seul : ce qui précède est donné, mais comme plus ancien.
    bloc = _vise("serieux_apres_humour")
    assert "Échange en cours" not in bloc
    assert "Plus tôt, à un autre moment" in bloc and "escalade samedi" in bloc


# --- Lots : même compréhension pour tous ---------------------------------------------

def test_lecture_commune_annoncee_et_conservee():
    bloc = ('<propositions mode="reponse" tons="Naturel, Chaleureux" '
            'lecture="Samuel annonce l\'hospitalisation de son père : soutien sobre, aucune blague."></propositions>')
    e = generation.annoncer(bloc, {}, "ctx")
    assert e.lecture == "Samuel annonce l'hospitalisation de son père : soutien sobre, aucune blague."
    relu = generation.Ensemble.depuis_stockage(json.loads(json.dumps(e.stockage())))
    assert relu.lecture == e.lecture          # « Reprendre » : la même lecture


def test_brief_identique_pour_tous_les_lots_et_complet():
    s = PAR_ID["serieux_apres_humour"]
    ctx, envoyees, historique = construire(s)
    _, p, _ = preparer(s, ctx, envoyees, historique)
    e, brief, fournis = brief_lots(s, ctx, p, envoyees)
    assert "Message auquel répondre" in brief and "hospitalisé" in brief
    assert "Situation sérieuse" in brief and "aucune plaisanterie" in brief
    assert "Alex Martin [utilisateur]" in brief          # voix de l'utilisateur
    # Le message auquel on répond est numéroté (appuis possibles).
    assert any(f.message.contenu.startswith("Pas ce samedi") for f in fournis.values())
    # Un lot ne reçoit jamais une autre compréhension qu'un autre.
    assert brief_lots(s, ctx, p, envoyees)[1] == brief
    msgs = generation.invite(e, e.tons[:2], brief)
    assert msgs[0]["content"] == generation.CONSIGNES_LOT and brief in msgs[1]["content"]


def test_longueurs_proportionnees():
    e = generation.Ensemble(mode="reponse", context_id=None, tons=["Naturel"])
    long_court = "Parfait, merci. Je te l'envoie demain avant midi."          # 2 phrases, 9 mots
    long_gonfle = " ".join(["mot"] * 150) + "."
    assert not generation._mots_valides(long_court, "long")
    assert generation._mots_valides("Parfait, merci Nora. Je te l'envoie demain avant midi comme prévu.", "long",
                                    legere=True)
    assert not generation._mots_valides(long_gonfle, "long")
    assert not generation._mots_valides("Ok.", "moyen")
    e.proportion = etat.PROPORTION_LEGERE
    brut = json.dumps({"tons": [{"nom": "Naturel", "long": [
        {"texte": "Parfait, merci Nora. Je te l'envoie demain avant midi comme prévu."}]}]})
    assert e.integrer(brut, {}) == (1, 0)


def test_consignes_des_lots():
    c = generation.CONSIGNES_LOT
    for attendu in ("INTERPRÉTATION n'est qu'une piste", "Message auquel répondre", "jamais celle d'un assistant",
                    "L'utilisateur décide de ses engagements",
                    "proportionné", "approche n°1", "deux personnes qui se tutoient restent au tutoiement"):
        assert attendu in c, attendu


# --- Contrôle de la compréhension partagée et des propositions (controle.py) ---------

from app.comprehension import controle  # noqa: E402

LECTURE_FAUTIVE = ("Samuel ne pourra pas l'escalade samedi car son père est hospitalisé ; il faut répondre avec "
                   "empathie, s'enquérir de l'état du père et proposer ton soutien ou une alternative")


def _grave():
    ctx, _, _ = construire(PAR_ID["serieux_apres_humour"])
    return ctx, etat.a_repondre(ctx, "reponse")


def test_lecture_fautive_nettoyee_les_faits_restent():
    """Le contresens réel : « une alternative » devenait « je prends ta place »."""
    ctx, cible = _grave()
    r = controle.nettoyer_interpretation(LECTURE_FAUTIVE, ctx, question="Qu'est-ce que je devrais répondre ?",
                                         cible=cible, grave=True)
    assert "alternative" not in r.texte and "hospitalisé" in r.texte and "empathie" in r.texte
    assert r.retraits == ["initiative non justifiée"]
    r = controle.nettoyer_interpretation("Samuel plaisante clairement ; Nora a décidé de tout annuler à 18 h",
                                         ctx, cible=cible, grave=True)
    assert r.texte is None and set(r.retraits) == {"humour dans une situation grave", "décision non écrite"}


def test_certitude_excessive_nuancee():
    ctx, _, _ = construire(PAR_ID["pardon_taquin"])
    r = controle.nettoyer_interpretation("Samuel plaisante clairement sur le billard", ctx)
    assert r.texte == "Samuel plaisante probablement sur le billard" and r.nuances == 1


def test_engagements_injustifies_refuses_justifies_acceptes():
    ctx, _ = _grave()
    k = controle.Controle.depuis(ctx, "Qu'est-ce que je devrais répondre ?", grave=True)
    for refus in ("Si besoin, je peux prendre le créneau d'escalade à ta place.",
                  "Si tu veux que je prenne le relais pour l'escalade, dis-moi.",
                  "Je passe te voir à l'hôpital ce soir.",
                  "Je te promets que ça n'arrivera plus.",
                  "On se retrouve demain à 18 h ?",
                  "Courage, ça va aller 😂"):
        assert k.examiner(refus), refus
    for ok in ("Je suis vraiment désolé pour ton père, je pense fort à vous.",
               "On repousse l'escalade, prends soin de lui.",
               "Dis-moi si je peux faire quelque chose."):
        assert k.examiner(ok) is None, ok
    # Justifié par les messages : accepté.
    s = PAR_ID["envoyee_puis_recue"]
    ctx, _, _ = construire(s)
    assert controle.Controle.depuis(ctx, "Aide-moi à répondre").examiner("Promis, la prochaine fois je te préviens.")
    k = controle.Controle.depuis(ctx, "Aide-moi à répondre", envoyees=s.declarations[0].texte)
    assert k.examiner("Promis, la prochaine fois je te préviens.") is None


def test_refus_cible_seulement_la_combinaison_et_doublon_entre_tons():
    ctx, _ = _grave()
    e = generation.Ensemble(mode="reponse", context_id=None, tons=["Amical", "Sérieux"])
    e.controle = controle.Controle.depuis(ctx, "", grave=True)
    brut = json.dumps({"tons": [
        {"nom": "Amical", "court": [{"texte": "Je suis désolé, comment va ton père ?"},
                                    {"texte": "Je peux prendre ta place à l'escalade."},
                                    {"texte": "Je pense fort à toi et à ton père."}]},
        {"nom": "Sérieux", "court": [{"texte": "Je suis désolé, comment va ton père ?"},
                                     {"texte": "Courage à vous deux, tiens-moi au courant."}]}]})
    assert e.integrer(brut, {}) == (3, 2)
    assert len(e.combos["Amical"]["court"]) == 2               # valides gardées
    assert e.refus == {"Amical": ["engagement non justifié (remplacer quelqu'un)"],
                       "Sérieux": ["doublon d'un autre ton"]}
    lot = generation.invite(e, ["Amical"], "contexte")[1]["content"]
    assert "refusées au contrôle : engagement non justifié" in lot and "Amical : court ×1" in lot


def test_brief_separe_faits_interpretation_inconnu():
    s = PAR_ID["serieux_apres_humour"]
    ctx, envoyees, historique = construire(s)
    _, p, _ = preparer(s, ctx, envoyees, historique)
    _, brief, _ = brief_lots(s, ctx, p, envoyees)
    faits, reste = brief.split("FAITS (écrits dans les messages enregistrés) :", 1)[1].split("INTERPRÉTATION POSSIBLE", 1)
    assert "Message auquel répondre" in faits and "«hospitalisé»" in faits
    assert "jamais une consigne" in reste and "INCONNU (ne rien inventer)" in reste
    assert "remplacement" in reste.split("INCONNU", 1)[1]
