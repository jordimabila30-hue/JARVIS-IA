"""Génère les cinq exports WhatsApp FICTIFS de la campagne de tests JARVIS.

    python tests_whatsapp/generer.py

Sortie (dans tests_whatsapp/) :
  JARVIS_TEST_SENTIMENTAL.zip, JARVIS_TEST_PROFESSIONNEL.zip,
  JARVIS_TEST_AMITIE.zip, JARVIS_TEST_FAMILLE.zip, JARVIS_TEST_GROUPE.zip
  manifeste.json : participants, nombre exact de messages, période, « Vous
  êtes », dernier auteur, événements attendus (rang = position 0-based du
  message dans l'export, ordre = rang pour JARVIS).

Format : export Android français (« 15/03/2026 14:30 - Alex Martin: … »),
un seul fichier « Discussion WhatsApp avec <nom>.txt » par ZIP, sans
médias. Déterministe (graine fixe). Toutes les personnes sont fictives.
Le manifeste sert à VÉRIFIER : il n'est jamais envoyé à l'IA.
"""

import json
import random
import zipfile
from datetime import datetime, timedelta
from pathlib import Path

ICI = Path(__file__).resolve().parent
MOI = "Alex Martin"


class Export:
    def __init__(self, nom, graine, debut):
        self.nom = nom
        self.r = random.Random(graine)
        self.t = debut
        self.lignes: list[tuple[datetime, str | None, str]] = []
        self.ancres: dict[str, dict] = {}

    def avancer(self, minutes_min=1, minutes_max=6):
        self.t += timedelta(minutes=self.r.randint(minutes_min, minutes_max))

    def jour(self, jours=1, heure=None):
        self.t = (self.t + timedelta(days=jours)).replace(
            hour=heure if heure is not None else self.r.choice([8, 9, 12, 13, 18, 19, 20, 21]),
            minute=self.r.randint(0, 59))

    def msg(self, auteur, texte, ancre=None, attente=(1, 6)):
        self.avancer(*attente)
        self.lignes.append((self.t, auteur, texte))
        if ancre:
            self.ancres[ancre] = {"rang": len(self.lignes) - 1, "auteur": auteur, "texte": texte,
                                  "date": self.t.strftime("%d/%m/%Y %H:%M")}

    def systeme(self, texte):
        self.lignes.append((self.t, None, texte))

    def texte(self):
        sortie = []
        for t, auteur, texte in self.lignes:
            entete = t.strftime("%d/%m/%Y %H:%M")
            sortie.append(f"{entete} - {texte}" if auteur is None else f"{entete} - {auteur}: {texte}")
        return "\n".join(sortie) + "\n"

    def nombre(self):
        return sum(1 for _, a, _ in self.lignes if a is not None)


def ecrire(e: Export, fichier: str, contact: str, participants, groupe, attendus):
    nom_txt = f"Discussion WhatsApp avec {contact}.txt"
    chemin = ICI / fichier
    with zipfile.ZipFile(chemin, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(nom_txt, e.texte().encode("utf-8"))
    humains = [(t, a, x) for t, a, x in e.lignes if a is not None]
    return {
        "zip": fichier,
        "fichier_texte": nom_txt,
        "contact": contact,
        "groupe": groupe,
        "participants": participants,
        "vous_etes": MOI,
        "lignes_export": len(e.lignes),
        "messages": len(humains),
        "messages_systeme": len(e.lignes) - len(humains),
        "debut": humains[0][0].strftime("%d/%m/%Y %H:%M"),
        "fin": humains[-1][0].strftime("%d/%m/%Y %H:%M"),
        "dernier_auteur": humains[-1][1],
        "dernier_message": humains[-1][2],
        "ancres": e.ancres,
        "attendus": attendus,
    }


# --- Banques de phrases (variées, naturelles) -------------------------------

RIRES = ["mdr", "haha", "😂", "ptdr", "😅", "mdrr", "hahaha", "🤣", "lol"]
OK = ["ok", "d'accord", "ça marche", "oui", "parfait", "👍", "vu", "noté", "ça me va"]


def choix(r, liste):
    return r.choice(liste)


# --- 1. Sentimentale : Alex et Lina (~100) ---------------------------------

def sentimental():
    e = Export("sentimental", 101, datetime(2026, 9, 1, 19, 12))
    L, A = "Lina Moreau", MOI
    e.systeme("Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion, pas même WhatsApp, ne peut les lire ou les écouter.")
    seq = [
        (L, "Coucou toi, bien rentré ?"), (A, "Oui ! Le train avait 20 minutes de retard évidemment"),
        (L, "La SNCF fidèle à elle-même 😄"), (A, "Je commence à croire qu'ils le font exprès pour moi"),
        (L, "Ou alors c'est le karma pour la fois où tu m'as fait attendre 40 minutes devant le cinéma"),
        (A, "Ça c'était un cas de force majeure !! Le chat de ma voisine était coincé dans l'escalier"),
        (L, "Oui oui, l'excuse du chat… la plus vieille du monde 😏"), (A, "Je te jure que c'est vrai 😭"),
        (L, "Je te crois. Un peu."), (A, "Un peu c'est déjà beaucoup venant de toi"),
    ]
    for a, x in seq:
        e.msg(a, x)
    e.jour(1, 21)
    for a, x in [
        (L, "Tu fais quoi samedi soir ?"), (A, "Rien de prévu, pourquoi ?"),
        (L, "Je voulais tester La Petite Ourse, le petit restaurant près du canal"),
        (A, "Avec plaisir ! 20h ça te va ?"),
        (L, ("Parfait, je réserve pour samedi 20h", "diner_reserve")),
        (A, "Hâte d'y être 😊"), (L, "Moi aussi. Mais je te préviens, je choisis le dessert"),
        (A, "Ça me semble être un piège"), (L, "C'en est un 😇"),
    ]:
        if isinstance(x, tuple):
            e.msg(a, x[0], ancre=x[1])
        else:
            e.msg(a, x)
    e.jour(3, 23)
    for a, x in [
        (A, "Merci pour ce soir. C'était vraiment une super soirée"),
        (L, "Merci à toi. Le tiramisu valait le détour"), (A, "Tu avais raison pour le dessert, je l'admets"),
        (L, "Je le note quelque part, ça n'arrive pas souvent 😂"), (A, "Profite, c'est rare"),
        (L, "Bonne nuit Alex"), (A, "Bonne nuit Lina 🌙"),
    ]:
        e.msg(a, x)
    e.jour(4, 18)
    for a, x, k in [
        (L, "Tu n'as pas répondu à mon message d'hier", None),
        (A, "Désolé, journée compliquée au boulot", None),
        (L, "Tu fais ce que tu veux de toute façon", "incomprehension"),
        (A, "Attends, tu es fâchée ?", None),
        (L, "Non… enfin un peu. J'avais l'impression que tu m'évitais", None),
        (A, "Pas du tout. J'étais en réunion jusqu'à 21h et j'avais la tête ailleurs. Je suis désolé, j'aurais dû te prévenir", "clarification"),
        (L, "D'accord. Merci de me le dire. Je me suis fait des films", None),
        (A, "Ça arrive. La prochaine fois je t'envoie au moins un petit mot", None),
        (L, "Un petit mot avec un emoji chat, alors 🐱", None),
        (A, "Promis, avec un chat coincé dans un escalier", None),
        (L, "😂 idiot", None),
    ]:
        e.msg(a, x, ancre=k)
    sujets = [
        [(L, "Tu as fini le livre que je t'ai prêté ?"), (A, "Presque ! Il me reste deux chapitres"),
         (L, "Ne me spoile surtout pas la fin si tu en parles avec Samuel"), (A, "Motus et bouche cousue")],
        [(A, "Il pleut des cordes ici"), (L, "Pareil, j'ai oublié mon parapluie évidemment"),
         (A, "Tu veux que je passe te chercher ?"), (L, "C'est gentil, mais je prends le bus. Merci 💛")],
        [(L, "Je pense à toi"), (A, "Moi aussi. Ta journée se passe bien ?"),
         (L, "Longue, mais ça va mieux maintenant"), (A, "Tant mieux 😊")],
        [(A, "Tu es libre dimanche pour une balade ?"), (L, "Dimanche après-midi oui"),
         (A, "Parc de la Tête d'Or ?"), (L, "Va pour le parc. Et une glace après, c'est non négociable 🍦")],
        [(L, "Tu ronfles au téléphone tu sais"), (A, "Calomnie !"), (L, "J'ai des preuves audio 😏"),
         (A, "Je demande un avocat")],
    ]
    for s in sujets:
        e.jour(e.r.randint(1, 3))
        for a, x in s:
            e.msg(a, x)
        e.msg(choix(e.r, [A, L]), choix(e.r, RIRES + ["❤️", "😊"]))
    while e.nombre() < 92:
        e.jour(e.r.randint(1, 2))
        e.msg(L, choix(e.r, ["Bien dormi ?", "Tu rentres à quelle heure ce soir ?", "Regarde ce que j'ai trouvé au marché",
                             "J'ai repensé à notre balade", "Tu as mangé ?", "Courage pour ta présentation !"]))
        e.msg(A, choix(e.r, ["Comme un bébé", "Vers 19h normalement", "Montre !", "Moi aussi, c'était chouette",
                             "Pas encore, je meurs de faim", "Merci, j'en ai besoin 😅"]))
        e.msg(L, choix(e.r, ["😊", "Super", "Haha", "Tiens-moi au courant", "Bisous", "Je croise les doigts"]))
    e.jour(1, 22)
    e.msg(A, "Je crois que je m'habitue un peu trop à nos discussions du soir")
    e.msg(L, "Ah oui ? C'est grave docteur ?")
    e.msg(A, "Très grave. Aucun remède connu")
    e.msg(L, "Alors on va devoir continuer le traitement. Tous les soirs. C'est pas une blague hein 😊", "dernier")
    attendus = {
        "sujet": "relation affective naissante : sorties (restaurant La Petite Ourse, parc), taquineries, une incompréhension clarifiée",
        "incomprehension": "Lina écrit « Tu fais ce que tu veux de toute façon » (vexée), Alex clarifie (réunion jusqu'à 21h)",
        "dernier_message": "Lina, ton affectueux et joueur ; « c'est pas une blague » : ambigu entre humour et sincérité → interprétation prudente",
        "action_attendue": "répondre (Lina a écrit en dernier)",
    }
    return ecrire(e, "JARVIS_TEST_SENTIMENTAL.zip", "Lina Moreau", [MOI, L], False, attendus)


# --- 2. Professionnelle : Alex et Nora (~250) -------------------------------

def professionnel():
    e = Export("pro", 202, datetime(2026, 5, 4, 9, 2))
    N, A = "Nora Laurent", MOI
    e.systeme("Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion, pas même WhatsApp, ne peut les lire ou les écouter.")
    plan = [
        [(N, "Bonjour Alex, le client valide le lancement du projet Atlas. Réunion de cadrage jeudi 7 mai à 10h ?", "reunion_cadrage"),
         (A, "Bonjour Nora, oui c'est noté pour jeudi 10h"), (N, "Parfait. Je t'envoie l'ordre du jour")],
        [(N, "Compte rendu : livraison de la V1 fixée au 30 juin", "echeance_initiale"),
         (A, "30 juin ça me paraît serré avec la migration des données"), (N, "Je sais, mais c'est la date du client pour l'instant")],
        [(A, "Pour la base, je propose de rester sur MongoDB, on l'a déjà en production"),
         (N, "Je ne suis pas d'accord. Les rapports financiers demandent des jointures, PostgreSQL serait plus adapté", "desaccord_base"),
         (A, "Ça impose de tout migrer"), (N, "Oui, mais on le paiera beaucoup plus cher plus tard sinon"),
         (A, "Laisse-moi une journée pour chiffrer la migration")],
        [(A, "J'ai chiffré : 8 jours de migration. Tu avais raison, PostgreSQL est le bon choix"),
         (N, "Décision actée : on part sur PostgreSQL. Je préviens le client", "decision_base"), (A, "👍")],
        [(N, "Répartition : tu prends le module d'authentification de l'API, Karim le front, moi la revue de code", "repartition"),
         (A, "Ok pour l'authentification. Je commence lundi"), (N, "Merci")],
        [(N, "Le client demande deux écrans en plus. On décale la livraison au 15 juillet", "echeance_decalee"),
         (A, "Enfin une bonne nouvelle 😅"), (N, "Ne t'habitue pas trop 😄")],
        [(A, "Petit retard sur l'authentification, le fournisseur OAuth a changé son API"),
         (N, "Combien de jours ?", "retard_question"), (A, "Deux jours, livraison jeudi au lieu de mardi"),
         (N, "Ok, mais préviens-moi plus tôt la prochaine fois s'il te plaît")],
        [(N, "Réunion de suivi déplacée à vendredi 14h, la salle Turing est prise", "reunion_deplacee"), (A, "Noté")],
        [(N, "Revue faite. Il manque des tests sur le rafraîchissement des jetons"),
         (A, "Je pensais les ajouter après la recette"),
         (N, "Non, les tests passent avant la recette. C'est la règle pour tout le monde", "desaccord_tests"),
         (A, "Entendu, je les ajoute aujourd'hui")],
    ]
    pros = [(N, "Tu peux relire la spec des exports avant demain ?"), (A, "Je regarde ça ce soir"),
            (N, "Le serveur de recette est de nouveau disponible"), (A, "Merci pour l'info"),
            (A, "La CI est rouge, je regarde"), (N, "C'était un test instable, relancé"),
            (N, "Pense à mettre à jour le ticket ATL-142"), (A, "C'est fait"),
            (A, "Je serai en télétravail demain"), (N, "Pas de souci, on se voit en visio à 9h30"),
            (N, "Bon courage pour la démo 🍀"), (A, "Merci, j'en aurai besoin"),
            (A, "Tu as eu le retour du client sur les maquettes ?"), (N, "Pas encore, je relance cet après-midi"),
            (N, "Petit point café à 15h ?"), (A, "Avec plaisir ☕"),
            (A, "La documentation de l'API est à jour sur le wiki"), (N, "Super, merci beaucoup"),
            (N, "Le client trouve l'écran de connexion trop chargé"), (A, "Je simplifie et je t'envoie une capture")]
    for bloc in plan:
        e.jour(e.r.randint(2, 5), 9)
        for item in bloc:
            e.msg(item[0], item[1], ancre=item[2] if len(item) > 2 else None, attente=(2, 25))
        for _ in range(e.r.randint(8, 14)):
            i = e.r.randrange(0, len(pros), 2)
            if e.r.random() < 0.3:
                e.jour(e.r.randint(0, 1) or 1, e.r.choice([9, 11, 14, 16]))
            e.msg(pros[i][0], pros[i][1], attente=(3, 40))
            e.msg(pros[i + 1][0], pros[i + 1][1], attente=(1, 15))
    while e.nombre() < 246:
        i = e.r.randrange(0, len(pros), 2)
        e.jour(1, e.r.choice([9, 10, 14, 16]))
        e.msg(pros[i][0], pros[i][1])
        e.msg(pros[i + 1][0], pros[i + 1][1])
    e.jour(2, 17)
    e.msg(A, "Les tests sur les jetons sont ajoutés et la recette est verte")
    e.msg(N, "Bravo. Peux-tu m'envoyer le compte rendu de la recette avant jeudi 17h ? Je le transmets au client", "dernier")
    attendus = {
        "decision": "PostgreSQL retenu au lieu de MongoDB (proposé par Nora, accepté par Alex après chiffrage)",
        "delais": "V1 au 30 juin, puis décalée au 15 juillet (deux écrans en plus) ; retard OAuth de 2 jours",
        "taches": "Alex : module d'authentification ; Karim : front ; Nora : revue de code",
        "action_attendue": "répondre à Nora (compte rendu avant jeudi 17h)",
    }
    return ecrire(e, "JARVIS_TEST_PROFESSIONNEL.zip", "Nora Laurent", [MOI, N], False, attendus)


# --- 3. Amitié : Alex et Samuel (~800) --------------------------------------

def amitie():
    e = Export("amitie", 303, datetime(2026, 3, 2, 18, 40))
    S, A = "Samuel Petit", MOI
    e.systeme("Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion, pas même WhatsApp, ne peut les lire ou les écouter.")
    blagues = [
        [(S, "J'ai fait des pâtes au ketchup ce soir, cuisine gastronomique"), (A, "Appelle le guide Michelin"),
         (S, "Ils ont déjà appelé, ils veulent ma recette secrète"), (A, "mdr")],
        [(A, "J'ai réussi à monter l'étagère tout seul"), (S, "T'es vraiment un génie", "genie_sarcastique"),
         (A, "Il reste juste trois vis en trop"), (S, "Le génie des vis en option 😂")],
        [(S, "Je me suis inscrit à un semi-marathon"), (A, "Toi ? Le gars qui prend l'ascenseur pour un étage ?"),
         (S, "Les gens changent Alex"), (A, "Ou ils s'inscrivent et ne viennent pas 😏"), (S, "Blessant. Mais juste")],
        [(A, "Le canapé m'a encore avalé tout le dimanche"), (S, "Le canapé gagne toujours, c'est la règle"),
         (A, "Un jour je le battrai"), (S, "C'est ce qu'ils disent tous")],
        [(S, "Mon chef m'a dit que j'étais « créatif » dans mes horaires"), (A, "C'est un compliment à 50 %"),
         (S, "Je prends les 50 % 😅")],
    ]
    serieux = [
        [(S, "Je peux te parler sérieusement deux minutes ?"), (A, "Bien sûr, qu'est-ce qui se passe ?"),
         (S, "Je pense quitter mon boulot. Je n'en peux plus de cette ambiance"),
         (A, "Ça fait longtemps que tu y penses ?"), (S, "Depuis l'été. Mais j'ai peur de me planter"),
         (A, "Tu as déjà des pistes ? On peut regarder ensemble ce week-end si tu veux"),
         (S, "Merci mec. Ça me fait du bien d'en parler", "moment_serieux")],
        [(A, "Ma grand-mère est à l'hôpital depuis hier"), (S, "Oh mince… elle va comment ?"),
         (A, "Stable. Ils la gardent en observation"), (S, "Je pense fort à vous. Si tu as besoin de quoi que ce soit, dis-moi")],
    ]
    quotidien = [(S, "Tu regardes le match ce soir ?"), (A, "Évidemment, chez toi ?"),
                 (A, "Tu as vu la nouvelle série dont tout le monde parle ?"), (S, "Pas encore, ça vaut le coup ?"),
                 (S, "Je suis devant chez toi"), (A, "J'arrive, deux minutes"),
                 (A, "On se fait un ciné vendredi ?"), (S, "Carrément, tu choisis le film cette fois"),
                 (S, "J'ai perdu mes clés. Encore."), (A, "Record battu, troisième fois du mois 😂"),
                 (A, "Tu peux me rendre ma perceuse ?"), (S, "Quelle perceuse ? 😇"),
                 (S, "Brunch dimanche ?"), (A, "Oui ! Pas trop tôt par contre"),
                 (A, "J'ai trouvé une salle d'escalade pas loin"), (S, "On teste quand tu veux")]
    reac = RIRES + ["😂😂", "🙄", "😏", "sérieux ?", "trop fort", "non mais 😭", "j'avoue", "grave"]
    vu_genie = False
    while e.nombre() < 780:
        e.jour(e.r.randint(0, 2) or 1)
        r = e.r.random()
        if r < 0.25:
            bloc = e.r.choice(blagues)
        elif r < 0.30:
            bloc = e.r.choice(serieux)
        else:
            i = e.r.randrange(0, len(quotidien), 2)
            bloc = [quotidien[i], quotidien[i + 1]]
        for item in bloc:
            k = item[2] if len(item) > 2 else None
            if k and k in e.ancres:
                k = None
            e.msg(item[0], item[1], ancre=k)
        for _ in range(e.r.randint(1, 4)):
            e.msg(e.r.choice([A, S]), e.r.choice(reac), attente=(0, 2))
        if not vu_genie and e.nombre() > 400:
            # Même phrase, sens différent selon l'auteur.
            e.jour(1, 20)
            e.msg(A, "Tu m'as aidé à préparer mon entretien, t'es vraiment un génie", "genie_sincere")
            e.msg(S, "Je sais 😎 mais merci, ça me touche")
            vu_genie = True
    e.jour(3, 19)
    e.msg(S, "Bon je file, on se tient au courant pour le week-end")
    e.msg(A, "Alors, toujours partant pour l'escalade samedi ?", "dernier")
    attendus = {
        "humour": "très fréquent, lancé par les deux ; Samuel plus souvent sur l'autodérision (pâtes au ketchup, clés perdues)",
        "ironie": "« T'es vraiment un génie » : sarcastique quand Samuel le dit (étagère, vis en trop), sincère quand Alex le dit (entretien)",
        "serieux": "Samuel envisage de quitter son travail ; la grand-mère d'Alex à l'hôpital",
        "action_attendue": "relancer (Alex a écrit en dernier, sans réponse)",
    }
    return ecrire(e, "JARVIS_TEST_AMITIE.zip", "Samuel Petit", [MOI, S], False, attendus)


# --- 4. Famille : Alex et Maya (~1 500) -------------------------------------

def famille():
    e = Export("famille", 404, datetime(2025, 11, 3, 18, 0))
    M, A = "Maya Martin", MOI
    e.systeme("Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion, pas même WhatsApp, ne peut les lire ou les écouter.")
    routine = [(M, "Tu as appelé maman ?"), (A, "Pas encore, je l'appelle ce soir"),
               (M, "Tu peux me relire ma lettre de motivation ?"), (A, "Envoie, je regarde après le dîner"),
               (A, "Tu rentres pour le week-end ?"), (M, "Je pense, si j'ai fini mes révisions"),
               (M, "J'ai eu 15 en droit constitutionnel !!"), (A, "Bravo ! Je te l'avais dit 🎉"),
               (A, "N'oublie pas l'anniversaire de mamie dimanche"), (M, "Oui oui, j'ai déjà la carte"),
               (M, "Papa a encore cassé la télécommande"), (A, "Classique 😂"),
               (A, "Tu as besoin d'aide pour ton déménagement ?"), (M, "Oui ! Samedi matin si tu peux"),
               (M, "Je suis crevée, les partiels me tuent"), (A, "Courage, plus que deux semaines"),
               (A, "Tu as des nouvelles de tonton Marc ?"), (M, "Il va mieux, il est sorti de l'hôpital"),
               (M, "On fait quoi pour Noël cette année ?"), (A, "Chez les parents comme d'habitude je pense")]
    ancres = [
        (60, [(M, "Idée : on organise une fête surprise pour les 30 ans de mariage de papa et maman ?", "fete_premiere_mention"),
              (A, "Excellente idée ! C'est quand exactement ?"), (M, "Le 14 juin. On a le temps de préparer")]),
        (300, [(A, "Pour la fête surprise, je propose la salle des fêtes de Vernaison"),
               (M, "Parfait, je m'occupe des invitations", "repartition_fete")]),
        (400, [(M, "Tu sais si mamie viendra à la fête ?", "question_sans_reponse")]),
        (560, [(M, "La salle est réservée pour le samedi 12 juin", "date_initiale"), (A, "Top")]),
        (620, [(M, "Attends, erreur : le 12 juin c'est un vendredi. La salle est réservée le samedi 13 juin", "correction_date"),
               (A, "Ah oui bien vu, je corrige sur l'invitation")]),
        (860, [(A, "Finalement on déplace la fête au samedi 20 juin, papa a un séminaire le 13", "changement_decision"),
                (M, "Mince… mais d'accord, je préviens tout le monde"), (M, "La salle est libre le 20, c'est confirmé")]),
        (1300, [(M, "Tu te souviens de la fête ? Maman en parle encore 😄", "rappel_ancien"),
                (A, "Elle a pleuré de joie en entrant dans la salle")]),
    ]
    prochaines = list(ancres)
    while e.nombre() < 1490:
        if prochaines and e.nombre() >= prochaines[0][0]:
            _, bloc = prochaines.pop(0)
            e.jour(e.r.randint(1, 3))
            for item in bloc:
                e.msg(item[0], item[1], ancre=item[2] if len(item) > 2 else None)
            continue
        if e.r.random() < 0.3:
            e.jour(e.r.randint(1, 2))
        i = e.r.randrange(0, len(routine), 2)
        e.msg(*routine[i])
        if e.r.random() < 0.85:      # parfois sans réponse : conversation interrompue
            e.msg(*routine[i + 1])
        if e.r.random() < 0.3:
            e.msg(e.r.choice([A, M]), e.r.choice(["😂", "❤️", "ok", "merci !", "bisous", "👍", "haha"]))
    e.jour(2, 20)
    e.msg(A, "Tu passes à la maison dimanche ?")
    e.msg(M, "Oui, vers midi. Et j'apporte le gâteau cette fois, promis", "dernier")
    attendus = {
        "evenement": "fête surprise des 30 ans de mariage des parents",
        "premiere_mention": "première mention par Maya (ancre fete_premiere_mention)",
        "dates": "annoncée le 14 juin, salle d'abord « samedi 12 juin » (erreur), corrigée en samedi 13 juin, puis déplacée au samedi 20 juin",
        "question_sans_reponse": "« Tu sais si mamie viendra à la fête ? » (Maya) : pas de réponse d'Alex",
    }
    return ecrire(e, "JARVIS_TEST_FAMILLE.zip", "Maya Martin", [MOI, M], False, attendus)


# --- 5. Groupe Projet Nova (~4 800) ------------------------------------------

def groupe():
    e = Export("groupe", 505, datetime(2026, 2, 2, 9, 0))
    A, N, S, L, M = MOI, "Nora Laurent", "Samuel Petit", "Lina Moreau", "Maya Martin"
    tous = [A, N, S, L, M]
    e.systeme("Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion, pas même WhatsApp, ne peut les lire ou les écouter.")
    e.systeme("Nora Laurent a créé le groupe « Projet Nova »")
    e.systeme("Nora Laurent vous a ajouté")
    sujets = [
        [(N, "Qui a avancé sur la maquette de l'accueil ?"), (M, "Moi, je l'envoie ce soir"), (L, "Super !")],
        [(S, "Quelqu'un a les accès au serveur de test ?"), (A, "Je te les envoie en privé")],
        [(L, "J'ai mis à jour la charte graphique sur le drive"), (N, "Merci Lina"), (S, "Les couleurs sont top")],
        [(M, "On commande des pizzas pour la réunion ?"), (S, "Toujours oui pour les pizzas 🍕"), (A, "mdr Samuel")],
        [(A, "La version 0.3 est en ligne"), (N, "Bravo l'équipe"), (L, "🎉"), (M, "Enfin !")],
        [(S, "Bug sur la page de profil, je regarde"), (A, "Je peux t'aider si besoin")],
        [(N, "Rappel : rendu du dossier au financeur dans deux semaines"), (M, "Noté"), (L, "Ok")],
        [(L, "Samuel tu as encore cassé le build 😏"), (S, "Calomnie !! … ok peut-être un peu"), (A, "😂")],
        [(M, "Je serai absente vendredi"), (N, "Pas de problème, merci de prévenir")],
        [(S, "Vous avez vu la démo du concurrent ?"), (L, "Oui, leur interface est plus lente que la nôtre"), (A, "haha")],
    ]
    courts = ["oui", "mdr", "d'accord", "ok", "👍", "haha", "merci", "vu", "top", "😂", "ça marche"]
    ancres = [
        (900, [(S, "On garde React pour le front, c'est ce qu'on maîtrise"),
               (N, "Je préfère Svelte, plus léger pour les mobiles", "desaccord_samuel_nora"),
               (S, "Tout le monde devra apprendre un nouvel outil"), (N, "Pas d'accord, l'équipe apprend vite")]),
        (1300, [(S, "Bon, j'ai testé Svelte ce week-end. Nora a raison, on part dessus", "accord_samuel_nora"),
                (N, "Merci Samuel 🙏"), (A, "Décision prise alors : Svelte", "decision_svelte")]),
        (2000, [(M, "Je laisse la responsabilité du design à Lina à partir de lundi, je passe sur les tests", "changement_responsabilite"),
                (L, "Ok, je prends le relais"), (N, "Merci à vous deux")]),
        (2600, [(N, "Je propose une réunion de lancement de la phase 2 mardi prochain à 10h", "proposition_reunion"),
                (S, "Mardi 10h ça me va"), (L, "Pour moi aussi"),
                (A, "Confirmé pour mardi prochain à 10h, je réserve la salle", "confirmation_horaire")]),
        (3100, [(N, "Le rendu final est fixé au 30 novembre", "echeance_ancienne")]),
        (3900, [(N, "Mise à jour : le financeur accepte un report, rendu final au 15 décembre", "echeance_mise_a_jour"),
                (S, "Ouf"), (M, "oui"), (L, "oui")]),
    ]
    prochaines = list(ancres)
    while e.nombre() < 4790:
        if prochaines and e.nombre() >= prochaines[0][0]:
            _, bloc = prochaines.pop(0)
            e.jour(e.r.randint(1, 2), 10)
            for item in bloc:
                e.msg(item[0], item[1], ancre=item[2] if len(item) > 2 else None)
            continue
        if e.r.random() < 0.058:
            e.jour(e.r.choice([1, 1, 2, 3, 7]) if e.r.random() < 0.97 else 21)
        for a, x in e.r.choice(sujets):
            e.msg(a, x, attente=(0, 8))
        for _ in range(e.r.randint(0, 3)):
            e.msg(e.r.choice(tous), e.r.choice(courts), attente=(0, 2))
    e.jour(1, 18)
    e.msg(L, "Récap de la semaine posté sur le drive")
    e.msg(N, "Merci Lina. Point d'équipe demain 9h comme d'habitude ?", "dernier")
    attendus = {
        "reunion": "proposée par Nora (ancre proposition_reunion), horaire confirmé par Alex (ancre confirmation_horaire)",
        "samuel_nora": "désaccord React/Svelte, puis Samuel se range à l'avis de Nora (Svelte)",
        "responsabilite": "Maya passe le design à Lina",
        "echeance": "30 novembre puis 15 décembre (mise à jour)",
        "action_attendue": "répondre (Nora a écrit en dernier)",
    }
    return ecrire(e, "JARVIS_TEST_GROUPE.zip", "Projet Nova", [MOI, N, S, L, M], True, attendus)


if __name__ == "__main__":
    manifeste = {
        "avertissement": "Données FICTIVES. Manifeste de vérification : ne jamais l'envoyer à l'IA.",
        "vous_etes": MOI,
        "conversations": [sentimental(), professionnel(), amitie(), famille(), groupe()],
    }
    (ICI / "manifeste.json").write_text(json.dumps(manifeste, ensure_ascii=False, indent=2), encoding="utf-8")
    for c in manifeste["conversations"]:
        print(f"{c['zip']:32} {c['messages']:5} messages  {c['debut']} → {c['fin']}  dernier : {c['dernier_auteur']}")
