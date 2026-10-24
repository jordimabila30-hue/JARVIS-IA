"""Orchestrateur ODO : boucle bornée entre le modèle (par MIA) et les outils.

  1. outils autorisés pour CE compte (politique) → définitions exposées ;
  2. tour du modèle (MIA, fournisseur déjà choisi par la route) ;
  3. appels demandés → permission, validation, anti-doublon ;
  4. lecture : exécution (délai) ; action : préparation d'une confirmation,
     JAMAIS d'exécution dans cette demande ;
  5. résultats enveloppés (données, jamais instructions) renvoyés à MIA ;
  6. jusqu'à la réponse finale, au plus ODO_MAX_TOURS tours et
     ODO_MAX_APPELS appels.

Le flux produit les mêmes événements que `FournisseurLLM.flux` (Texte, puis
une Fin dont l'usage est la SOMME de tous les tours) et, en plus,
[EtatOutil] et [DemandeConfirmation] pour la route. Avant chaque nouveau
tour, le budget de tokens du jour est revérifié ([verifier_budget]).

Interruption (client parti) : le générateur est fermé, l'outil en cours est
annulé ; l'usage déjà consommé reste lisible ([usage_consomme]).
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterator, Callable, Sequence
from dataclasses import replace
from typing import Any

from ..llm import (
    ErreurFournisseur,
    ErreurLLM,
    Fin,
    FournisseurLLM,
    RaisonArret,
    ResultatAppel,
    Texte,
    Usage,
    message_appels,
    message_resultats,
)
from ..llm.base import AppelOutil, Message, estimer_tokens
from .confirmations import Confirmations
from .contrat import ContexteOutil, DemandeConfirmation, EtatOutil, Outil, ResultatOutil, Sensibilite
from .journal import journaliser
from .permissions import PolitiqueOutils
from .registre import RegistreOutils
from .securite import CONSIGNE_OUTILS, empreinte, envelopper
from .validation import valider

EvenementODO = Texte | Fin | EtatOutil | DemandeConfirmation

PLAFOND_DIRECT = 2048
MESSAGE_LIMITE = "La demande a demandé trop d'étapes d'outils. Reformule-la plus simplement."
MESSAGE_BUDGET = "Ta limite quotidienne de tokens serait dépassée pour terminer cette demande."


async def executer_outil(outil: Outil, arguments: dict[str, Any], contexte: ContexteOutil,
                         delai: float) -> ResultatOutil:
    """Exécution bornée dans le temps ; une panne devient un résultat
    d'erreur (jamais le message de l'exception : il peut contenir des données)."""
    debut = time.perf_counter()
    try:
        r = await asyncio.wait_for(outil.executer(arguments, contexte), timeout=outil.delai or delai)
        statut = r.erreur or "ok"
    except asyncio.TimeoutError:
        r, statut = ResultatOutil(contenu="L'outil n'a pas répondu à temps.", erreur="delai_depasse"), "delai_depasse"
    except Exception as exc:                  # noqa: BLE001 : outil défaillant, la demande continue
        r, statut = ResultatOutil(contenu="L'outil a échoué.", erreur="echec_outil"), f"echec:{type(exc).__name__}"
    journaliser("execution", outil=outil.nom, statut=statut, demande=contexte.demande_id,
                duree_ms=(time.perf_counter() - debut) * 1000, taille=len(r.contenu))
    return r


class ExecutionODO:
    """Une demande de l'utilisateur traitée par ODO (une instance par requête)."""

    def __init__(self, *, llm: FournisseurLLM, registre: RegistreOutils, politique: PolitiqueOutils,
                 confirmations: Confirmations | None, contexte: ContexteOutil,
                 max_tours: int, max_appels: int, delai_outil: float, resultat_max: int,
                 verifier_budget: Callable[[int], str | None] | None = None) -> None:
        self.llm = llm
        self.contexte = contexte
        self.politique = politique
        self.confirmations = confirmations
        self.outils = {o.nom: o for o in politique.autorises(registre, contexte)}
        self.max_tours = max(1, max_tours)
        self.max_appels = max(1, max_appels)
        self.delai_outil = delai_outil
        self.resultat_max = resultat_max
        self.verifier_budget = verifier_budget
        self._reinitialiser()

    def _reinitialiser(self) -> None:
        self.entree = 0            # tokens d'entrée des tours TERMINÉS
        self.sortie = 0
        self.tours = 0
        self.appels = 0
        self.prompt_courant: list[Message] = []
        self.texte_tour = ""       # texte du tour en cours (interruption)
        self._resultats: dict[str, ResultatAppel] = {}     # empreinte → résultat (doublons)
        #: Données structurées des outils exécutés (mémoire de recherche, mesures).
        self.donnees: list[tuple[str, dict[str, Any]]] = []
        self._debut = time.perf_counter()
        self._premier_outil_ms: int | None = None

    @property
    def actif(self) -> bool:
        """Des outils sont proposés à ce compte : sinon, aucune boucle."""
        return bool(self.outils)

    def usage_consomme(self) -> tuple[int, int]:
        """(entrée, sortie) consommés jusqu'ici, tour interrompu compris
        (estimé : son prompt est parti chez le fournisseur)."""
        entree, sortie = self.entree, self.sortie
        if self.prompt_courant:
            entree += estimer_tokens("".join(m["content"] for m in self.prompt_courant))
            sortie += estimer_tokens(self.texte_tour)
        return entree, sortie

    # --- Boucle -----------------------------------------------------------------

    def _plan_direct(self, prompt: Sequence[Message]) -> tuple[Outil, dict[str, Any]] | None:
        """Outil exécutable par ODO sans demander au modèle (demande simple)."""
        if not prompt or prompt[-1]["role"] != "user" or prompt[-1].get("images"):
            return None
        # La question seule (sans le rappel de la dernière recherche joint devant).
        question = prompt[-1]["content"].rsplit("</gmail_derniere_recherche>", 1)[-1].strip()
        for outil in self.outils.values():
            arguments = outil.direct(question) if outil.consigne_directe else None
            if arguments is not None and not valider(outil.schema, arguments):
                return outil, arguments
        return None

    async def _direct(self, outil: Outil, arguments: dict[str, Any], prompt: Sequence[Message],
                      max_sortie: int) -> AsyncIterator[EvenementODO]:
        """UN appel IA : ODO exécute l'outil, le modèle reçoit les données et
        répond (ni définitions d'outils, ni consigne de recherche). Rien
        d'utilisable : aucun événement texte, la boucle habituelle reprend."""
        self.appels += 1
        self._premier_outil_ms = int((time.perf_counter() - self._debut) * 1000)
        yield EtatOutil(outil.nom, "en_cours")
        r = await executer_outil(outil, arguments, self.contexte, self.delai_outil)
        yield EtatOutil(outil.nom, "erreur" if r.erreur else "termine", r.erreur)
        if r.donnees:
            self.donnees.append((outil.nom, r.donnees))
        if r.erreur or not (r.donnees or {}).get("lus"):
            self.direct_abandonne = True
            return
        systeme = prompt[0]["content"] if prompt[0]["role"] == "system" else ""
        donnees = envelopper(outil.nom, r.contenu, self.resultat_max)
        messages = [{"role": "system", "content": f"{systeme}\n\n{outil.consigne_directe}".strip()},
                    *[m for m in prompt[1:-1] if m["role"] != "system"],
                    {**prompt[-1], "content": f"{prompt[-1]['content']}\n\n{donnees}"}]
        self.prompt_courant, self.texte_tour = messages, ""
        fin: Fin | None = None
        # Plafond (pas une consommation) : le raisonnement interne de certains
        # modèles (gpt-oss) est compté dans la sortie ; sur un long e-mail, 1 024
        # tokens pouvaient être épuisés avant le texte (réponse vide).
        async for ev in self.llm.flux(messages, max_sortie=max(max_sortie, PLAFOND_DIRECT)):
            if isinstance(ev, Texte):
                self.texte_tour += ev.texte
                yield ev
            elif isinstance(ev, Fin):
                fin = ev
        if fin is None:
            return
        self.tours += 1
        self.entree += fin.usage.entree_totale
        self.sortie += fin.usage.sortie
        self.prompt_courant, self.texte_tour = [], ""
        journaliser("fin", demande=self.contexte.demande_id, tours=self.tours, appels=self.appels,
                    duree_ms=(time.perf_counter() - self._debut) * 1000, premier_outil_ms=self._premier_outil_ms,
                    entree=self.entree, sortie=self.sortie, direct=1,
                    requetes_gmail=sum(int(d.get("requetes_gmail", 0)) for _, d in self.donnees) or None,
                    fournisseur=self.llm.nom)
        yield replace(fin, usage=Usage(entree=self.entree, sortie=self.sortie), tour=None)

    async def flux(self, prompt: Sequence[Message], *, max_sortie: int) -> AsyncIterator[EvenementODO]:
        self._reinitialiser()
        plan = self._plan_direct(prompt)
        if plan is not None:
            self.direct_abandonne = False
            async for ev in self._direct(*plan, prompt, max_sortie):
                yield ev
            if not self.direct_abandonne:
                return
            # Rien de clairement pertinent : le modèle reprend la main (chemin habituel).
        consignes = list(dict.fromkeys(o.consigne for o in self.outils.values() if o.consigne))
        messages = _avec_consigne(list(prompt), consignes)
        definitions = [o.definition() for o in self.outils.values()]
        texte_emis = False
        while True:
            if self.tours >= self.max_tours:
                raise ErreurFournisseur("odo_limite", fournisseur=self.llm.nom, message=MESSAGE_LIMITE,
                                        apres_texte=True)
            if self.tours and self.verifier_budget is not None:
                deja = self.entree + self.sortie
                if self.verifier_budget(deja + estimer_tokens("".join(m["content"] for m in messages))):
                    raise ErreurFournisseur("llm_budget", fournisseur=self.llm.nom, message=MESSAGE_BUDGET,
                                            apres_texte=True)
            self.prompt_courant, self.texte_tour = messages, ""
            fin: Fin | None = None
            separer = texte_emis
            # Dernier tour permis (ou plus d'appels possibles) : le modèle
            # répond avec ce qu'il a déjà lu, sans nouvel outil.
            dernier = self.tours == self.max_tours - 1 or self.appels >= self.max_appels
            try:
                async for ev in self.llm.flux(messages, max_sortie=max_sortie, outils=definitions,
                                              forcer_reponse=dernier and self.tours > 0):
                    if isinstance(ev, Texte):
                        if separer:
                            separer = False
                            yield Texte("\n\n")
                        self.texte_tour += ev.texte
                        texte_emis = True
                        yield ev
                    elif isinstance(ev, Fin):
                        fin = ev
            except ErreurLLM as exc:
                if self.tours:
                    exc.apres_texte = True     # des outils ont servi : jamais de nouvel essai complet
                raise
            if fin is None:
                return                          # la route signale la réponse incomplète
            self.tours += 1
            self.entree += fin.usage.entree_totale
            self.sortie += fin.usage.sortie
            self.prompt_courant, self.texte_tour = [], ""
            if fin.raison is not RaisonArret.OUTIL or not fin.appels:
                # Mesures pour comparer les phases (aucun contenu, aucune identité).
                journaliser("fin", demande=self.contexte.demande_id, tours=self.tours, appels=self.appels,
                            duree_ms=(time.perf_counter() - self._debut) * 1000,
                            premier_outil_ms=self._premier_outil_ms, entree=self.entree, sortie=self.sortie,
                            requetes_gmail=sum(int(d.get("requetes_gmail", 0)) for _, d in self.donnees) or None,
                            fournisseur=self.llm.nom)
                yield replace(fin, usage=Usage(entree=self.entree, sortie=self.sortie), tour=None)
                return
            resultats: list[ResultatAppel] = []
            for appel in fin.appels:
                async for ev in self._traiter(appel, resultats):
                    yield ev
            messages = messages + [message_appels(fin.tour), message_resultats(resultats)]

    async def _traiter(self, appel: AppelOutil, resultats: list[ResultatAppel]) -> AsyncIterator[EvenementODO]:
        """Un appel demandé : refus, doublon, confirmation ou exécution.
        Ajoute toujours UN résultat (le modèle doit en recevoir un par appel)."""
        def repondre(contenu: str, *, erreur: bool) -> None:
            resultats.append(ResultatAppel(appel.id, envelopper(appel.nom, contenu, self.resultat_max, erreur=erreur),
                                           erreur=erreur))

        self.appels += 1
        outil = self.outils.get(appel.nom)
        demande = self.contexte.demande_id
        if self.appels > self.max_appels:
            journaliser("refus", outil=appel.nom, statut="limite_appels", demande=demande)
            yield EtatOutil(appel.nom, "refuse", "limite_appels")
            repondre("Limite d'appels d'outils atteinte pour cette demande : réponds sans outil.", erreur=True)
            return
        if outil is None:
            # Inconnu, ou existant mais non autorisé pour ce compte : même réponse.
            journaliser("refus", outil=appel.nom[:64], statut="non_autorise", demande=demande)
            yield EtatOutil(appel.nom[:64], "refuse", "non_autorise")
            repondre("Cet outil n'est pas disponible.", erreur=True)
            return
        if appel.erreur_arguments:
            yield EtatOutil(outil.nom, "refuse", "arguments_illisibles")
            repondre("Arguments illisibles : l'outil n'a pas été exécuté.", erreur=True)
            return
        erreurs = valider(outil.schema, appel.arguments)
        if erreurs:
            journaliser("refus", outil=outil.nom, statut="arguments_invalides", demande=demande)
            yield EtatOutil(outil.nom, "refuse", "arguments_invalides")
            repondre("Arguments invalides, outil non exécuté : " + "; ".join(erreurs[:5]), erreur=True)
            return
        cle = empreinte(outil.nom, appel.arguments)
        if cle in self._resultats:
            # Même appel, mêmes arguments : jamais exécuté deux fois.
            precedent = self._resultats[cle]
            resultats.append(ResultatAppel(appel.id, precedent.contenu, precedent.erreur))
            return
        if outil.sensibilite is Sensibilite.ACTION:
            async for ev in self._preparer(outil, appel, resultats):
                yield ev
            self._resultats[cle] = resultats[-1]
            return
        yield EtatOutil(outil.nom, "en_cours")
        if self._premier_outil_ms is None:
            # Temps de « compréhension » : demande reçue → premier outil appelé.
            self._premier_outil_ms = int((time.perf_counter() - self._debut) * 1000)
        r = await executer_outil(outil, appel.arguments, self.contexte, self.delai_outil)
        if r.donnees:
            self.donnees.append((outil.nom, r.donnees))
        yield EtatOutil(outil.nom, "erreur" if r.erreur else "termine", r.erreur)
        repondre(r.contenu, erreur=bool(r.erreur))
        self._resultats[cle] = resultats[-1]

    async def _preparer(self, outil: Outil, appel: AppelOutil,
                        resultats: list[ResultatAppel]) -> AsyncIterator[EvenementODO]:
        """Action sensible : préparée, jamais exécutée ici."""
        demande = None
        if self.confirmations is not None:
            try:
                demande = await self.confirmations.preparer(outil, appel.arguments, self.contexte)
            except Exception:                  # noqa: BLE001 : Redis absent → aucune action (fermé)
                demande = None
        if demande is None:
            journaliser("refus", outil=outil.nom, statut="confirmation_indisponible", demande=self.contexte.demande_id)
            yield EtatOutil(outil.nom, "refuse", "confirmation_indisponible")
            resultats.append(ResultatAppel(appel.id, envelopper(
                outil.nom, "Action impossible pour le moment : elle n'a PAS été faite.", self.resultat_max,
                erreur=True), erreur=True))
            return
        journaliser("confirmation", outil=outil.nom, statut="preparee", demande=self.contexte.demande_id)
        yield EtatOutil(outil.nom, "confirmation")
        yield demande
        resultats.append(ResultatAppel(appel.id, envelopper(
            outil.nom,
            f"Action préparée mais PAS exécutée : {demande.resume} L'utilisateur doit la confirmer "
            "lui-même dans JARVIS. Dis-le-lui ; n'affirme jamais qu'elle a été faite.",
            self.resultat_max)))


def _avec_consigne(messages: list[Message], consignes: Sequence[str] = ()) -> list[Message]:
    """Règle des outils (et consignes des outils proposés) ajoutée au message
    système du début (canal fiable)."""
    regle = "\n\n".join([CONSIGNE_OUTILS, *consignes])
    if messages and messages[0]["role"] == "system":
        return [{**messages[0], "content": f"{messages[0]['content']}\n\n{regle}"}, *messages[1:]]
    return [{"role": "system", "content": regle}, *messages]
