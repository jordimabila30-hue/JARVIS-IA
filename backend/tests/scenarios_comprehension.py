"""Jeu d'évaluation de la compréhension conversationnelle (données FICTIVES).

Douze situations construites sur les cinq exports de tests_whatsapp/ (+ des
messages ajoutés à la main, des réponses déclarées envoyées, un historique
JARVIS). Chaque scénario dit ce qui est ATTENDU :

  - partie DÉTERMINISTE (vérifiée sans IA, test_evaluation_comprehension.py
    et evaluation_comprehension.py) : message visé, messages fournis,
    chronologie, clarification, informations transmises aux lots ;
  - partie QUALITATIVE (`lecture_attendue`, `mots_attendus`) : ce qu'une
    bonne réponse doit comprendre ; jugée sur les essais réels, jamais
    « prouvée » par un test de format.

Ce module ne dépend que d'API stables du moteur : il sert aussi à mesurer
l'ancienne version (comparaison avant / après).
"""

from dataclasses import dataclass, field

LINA, ALEX, SAMUEL, NORA, MAYA = "Lina Moreau", "Alex Martin", "Samuel Petit", "Nora Laurent", "Maya Martin"
SENTIMENTAL = "JARVIS_TEST_SENTIMENTAL.zip"
PRO = "JARVIS_TEST_PROFESSIONNEL.zip"
AMITIE = "JARVIS_TEST_AMITIE.zip"
FAMILLE = "JARVIS_TEST_FAMILLE.zip"
GROUPE = "JARVIS_TEST_GROUPE.zip"

PARDON = "Bon, je te pardonne pour cette fois."


@dataclass
class Ajout:
    auteur: str
    texte: str
    origine: str                     # manual_received | manual_sent
    cree_le: str | None = None       # created_at (UTC) de l'ajout


@dataclass
class Declaration:
    texte: str
    ton: str
    declared_at: str                 # UTC


@dataclass
class Scenario:
    id: str
    titre: str
    zip: str
    question: str
    ajouts: list[Ajout] = field(default_factory=list)
    declarations: list[Declaration] = field(default_factory=list)
    historique: list[tuple[str, str]] = field(default_factory=list)
    # --- Attendus déterministes ---
    # (auteur, texte) du message visé ; "clarification" ; None : aucune cible.
    cible: tuple[str, str] | str | None = None
    fournis: list[tuple[str, str]] = field(default_factory=list)
    aide: bool = False               # demande d'aide à répondre (lots)
    lot_cible: tuple[str, str] | None = None   # message auquel les lots répondent
    proportion_legere: bool = False
    serieux: bool = False
    # --- Attendus qualitatifs (essais réels) ---
    lecture_attendue: str = ""
    mots_attendus: list[str] = field(default_factory=list)    # au moins un
    mots_interdits: list[str] = field(default_factory=list)   # aucun


SCENARIOS: list[Scenario] = [
    # 1. Même message, deux contextes : reproche sérieux puis pardon.
    Scenario(
        id="pardon_reproche", titre="Même message après un vrai reproche", zip=SENTIMENTAL,
        ajouts=[
            Ajout(LINA, "Tu as encore oublié de m'appeler hier soir. J'ai attendu toute la soirée.",
                  "manual_received", "2026-10-16T17:00:00+00:00"),
            Ajout(ALEX, "Je suis vraiment désolé, j'ai été pris au travail et je n'ai pas vu l'heure.",
                  "manual_sent", "2026-10-16T17:05:00+00:00"),
            Ajout(LINA, PARDON, "manual_received", "2026-10-16T17:20:00+00:00"),
        ],
        question="Pourquoi elle me dit ça ?",
        cible=(LINA, PARDON),
        fournis=[(LINA, "Tu as encore oublié de m'appeler hier soir. J'ai attendu toute la soirée.")],
        lecture_attendue="pardon réel après un oubli reproché (pas une plaisanterie) ; « pour cette fois » = "
                         "une limite, peut-être un léger avertissement ; prudence sur le ressenti",
        mots_attendus=["oubli", "appel", "excuse", "désol", "pardon"],
        mots_interdits=["traitement"],
    ),
    # 1 bis. Même message, contexte de taquinerie.
    Scenario(
        id="pardon_taquin", titre="Même message dans une taquinerie", zip=AMITIE,
        ajouts=[
            Ajout(SAMUEL, "Tu m'as encore battu au billard, j'exige une revanche 😤", "manual_received",
                  "2026-10-16T20:00:00+00:00"),
            Ajout(ALEX, "Désolé de t'avoir humilié devant tout le bar 😎", "manual_sent",
                  "2026-10-16T20:02:00+00:00"),
            Ajout(SAMUEL, PARDON, "manual_received", "2026-10-16T20:03:00+00:00"),
        ],
        question="Pourquoi il me dit ça ?",
        cible=(SAMUEL, PARDON),
        fournis=[(ALEX, "Désolé de t'avoir humilié devant tout le bar 😎")],
        lecture_attendue="suite de la taquinerie (billard, « humilié » 😎) : faux pardon joueur, pas un reproche",
        mots_attendus=["billard", "taquin", "jeu", "blague", "plaisant", "humour", "second degré"],
        mots_interdits=["traitement", "escalade"],
    ),
    # 2. Ironie : « T'es vraiment un génie » (sarcastique chez Samuel).
    Scenario(
        id="ironie_genie", titre="Ironie selon l'auteur", zip=AMITIE,
        question="Quand Samuel m'a dit que j'étais un génie, il était sérieux ?",
        cible=None,
        fournis=[(SAMUEL, "T'es vraiment un génie"), (ALEX, "J'ai réussi à monter l'étagère tout seul"),
                 (ALEX, "Il reste juste trois vis en trop")],
        lecture_attendue="ironie probable : étagère montée, « trois vis en trop » juste après",
        mots_attendus=["vis", "étagère", "ironi", "second degré", "taquin"],
    ),
    # 3. Désaccord suivi de réconciliation.
    Scenario(
        id="desaccord_reconciliation", titre="Désaccord puis réconciliation", zip=SENTIMENTAL,
        question="Elle était vraiment fâchée quand elle a écrit « Tu fais ce que tu veux de toute façon » ? Et après ?",
        cible=None,
        fournis=[(LINA, "Tu fais ce que tu veux de toute façon"),
                 (LINA, "Non… enfin un peu. J'avais l'impression que tu m'évitais"),
                 (LINA, "D'accord. Merci de me le dire. Je me suis fait des films"),
                 (LINA, "😂 idiot")],
        lecture_attendue="vexée (elle le dit : « enfin un peu »), Alex explique (réunion), elle accepte, "
                         "retour de la complicité (chat, « idiot »)",
        mots_attendus=["un peu", "réunion", "films", "évitais"],
    ),
    # 4. Changement de décision.
    Scenario(
        id="changement_decision", titre="Date de la fête modifiée deux fois", zip=FAMILLE,
        question="C'est quand la fête finalement ?",
        cible=None,
        fournis=[(ALEX, "Finalement on déplace la fête au samedi 20 juin, papa a un séminaire le 13")],
        lecture_attendue="samedi 20 juin (après 12 juin erroné → 13 juin → 20 juin)",
        mots_attendus=["20 juin"],
    ),
    # 5. Message récent ajouté sans date.
    Scenario(
        id="ajout_sans_date", titre="Ajout récent sans date", zip=PRO,
        ajouts=[Ajout(NORA, "Finalement vendredi midi ça ira aussi si tu es charrette.", "manual_received", None)],
        question="Que veut dire son dernier message ?",
        cible=(NORA, "Finalement vendredi midi ça ira aussi si tu es charrette."),
        lecture_attendue="le délai du compte rendu (jeudi 17h) est assoupli à vendredi midi ; date de "
                         "l'ajout inconnue, mais plus récent que l'export",
        mots_attendus=["compte rendu", "jeudi", "vendredi"],
    ),
    # 6. Dernière réponse d'un participant dans un groupe.
    Scenario(
        id="groupe_participant", titre="Dernier message de Samuel dans le groupe", zip=GROUPE,
        question="Quelle est la dernière réponse de Samuel ?",
        cible=(SAMUEL, "Calomnie !! … ok peut-être un peu"),
        lecture_attendue="« Calomnie !! … ok peut-être un peu » en réponse à Lina (build cassé), ton joueur",
        mots_attendus=["build", "calomnie"],
        mots_interdits=["point d'équipe"],
    ),
    # 7. Humour habituel interrompu par un message sérieux.
    Scenario(
        id="serieux_apres_humour", titre="Annonce grave dans une amitié très blagueuse", zip=AMITIE,
        ajouts=[Ajout(SAMUEL, "Pas ce samedi… Mon père a été hospitalisé cette nuit, je suis à l'hôpital avec lui.",
                      "manual_received", "2026-10-16T08:00:00+00:00")],
        question="Qu'est-ce que je devrais répondre ?",
        cible=(SAMUEL, "Pas ce samedi… Mon père a été hospitalisé cette nuit, je suis à l'hôpital avec lui."),
        aide=True, serieux=True,
        lot_cible=(SAMUEL, "Pas ce samedi… Mon père a été hospitalisé cette nuit, je suis à l'hôpital avec lui."),
        lecture_attendue="situation grave : soutien sobre, aucune blague (même si l'humour est habituel), "
                         "escalade oubliée",
        mots_interdits=["😂", "mdr", "haha", "🤣"],
    ),
    # 8. Suivi ambigu dans un groupe.
    Scenario(
        id="suivi_ambigu_groupe", titre="« Pourquoi il dit ça ? » dans un groupe", zip=GROUPE,
        question="Pourquoi il dit ça ?",
        cible="clarification",
        lecture_attendue="question courte : de qui parle-t-il ?",
        mots_attendus=["qui", "lequel", "quel message", "Samuel", "Alex"],
    ),
    # 9. Proposition déclarée envoyée, puis réponse reçue collée.
    Scenario(
        id="envoyee_puis_recue", titre="Réponse déclarée envoyée puis réponse reçue", zip=SENTIMENTAL,
        ajouts=[
            Ajout(LINA, "Tu aurais pu me prévenir que tu rentrais aussi tard…", "manual_received",
                  "2026-10-16T17:50:00+00:00"),
            Ajout(LINA, "Mouais. On verra bien 🙄", "manual_received", "2026-10-16T18:30:00+00:00"),
        ],
        declarations=[Declaration("Tu as raison, promis la prochaine fois je te préviens plus tôt 😊", "Chaleureux",
                                  "2026-10-16T18:00:00+00:00")],
        historique=[
            ("user", "Que penses-tu de son dernier message ?"),
            ("assistant", "Son message sur le « traitement » tous les soirs est tendre et joueur : elle prolonge "
                          "votre blague, avec un clin d'œil 😊."),
        ],
        question="Pourquoi elle me dit ça ?",
        cible=(LINA, "Mouais. On verra bien 🙄"),
        fournis=[(LINA, "Tu aurais pu me prévenir que tu rentrais aussi tard…")],
        lecture_attendue="réaction sceptique à la PROMESSE que l'utilisateur déclare avoir envoyée (« on verra "
                         "bien » 🙄) : elle attend des actes ; pas l'ancien message du traitement",
        mots_attendus=["promesse", "promis", "prévenir", "préviens", "sceptique", "doute"],
        mots_interdits=["traitement"],
    ),
    # 10. Message très court : réponse proportionnée.
    Scenario(
        id="message_tres_court", titre="Réponse à « Ok 👍 »", zip=PRO,
        ajouts=[
            Ajout(ALEX, "Je te l'envoie demain avant midi.", "manual_sent", "2026-10-16T09:00:00+00:00"),
            Ajout(NORA, "Ok 👍", "manual_received", "2026-10-16T09:05:00+00:00"),
        ],
        question="Aide-moi à lui répondre",
        cible=None, aide=True, proportion_legere=True,
        lot_cible=(NORA, "Ok 👍"),
        lecture_attendue="rien à négocier : un accusé de réception bref suffit ; pas de long message artificiel",
    ),
    # 11. Suivi naturel : « Tu crois qu'elle plaisante ? » après une question sur son dernier message.
    Scenario(
        id="suivi_plaisante", titre="« Tu crois qu'elle plaisante ? »", zip=SENTIMENTAL,
        historique=[
            ("user", "Que penses-tu de son dernier message ?"),
            ("assistant", "Elle parle de « continuer le traitement » tous les soirs : c'est tendre, avec une "
                          "pointe de jeu."),
        ],
        question="Tu crois qu'elle plaisante ?",
        cible=(LINA, "Alors on va devoir continuer le traitement. Tous les soirs. C'est pas une blague hein 😊"),
        lecture_attendue="deux lectures : jeu (😊, blague du « traitement ») ET sincérité (« c'est pas une "
                         "blague ») ; pas de certitude",
        mots_attendus=["traitement"],
    ),
]

PAR_ID = {s.id: s for s in SCENARIOS}
