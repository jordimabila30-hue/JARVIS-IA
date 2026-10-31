"""Client administrateur Supabase (PostgREST) utilisé par le backend.

Authentifié avec la clé `service_role` : il contourne la RLS, il ne doit donc
servir qu'à des opérations décidées côté serveur (lecture des limites, écriture
de la consommation, messages assistant). On passe par httpx directement plutôt
que par le SDK `supabase` : appels async natifs, peu de dépendances, et un
contrôle total des timeouts.
"""

from dataclasses import dataclass
from datetime import date, datetime

import httpx


@dataclass(frozen=True)
class UserLimits:
    """Limites EFFECTIVES d'un compte (fonction SQL `limites_effectives` :
    offre `plan_config`, sauf exception explicite `users.limits_override`)."""

    plan: str
    daily_message_limit: int | None  # None = illimité
    daily_token_limit: int | None
    llm_provider: str | None = None           # fournisseur de l'offre (MIA universel)
    llm_model: str | None = None
    session_duration_minutes: int | None = None   # None : pas de quota de session
    session_message_limit: int | None = None
    session_token_limit: int | None = None
    critical_threshold_percent: int | None = None
    exception: bool = False                    # limites personnelles actives


@dataclass(frozen=True)
class SessionUsage:
    """Une ligne de `usage_sessions` (heures du serveur)."""

    id: str
    plan: str
    started_at: datetime
    ends_at: datetime
    messages_used: int = 0
    tokens_used: int = 0

    @classmethod
    def depuis_ligne(cls, ligne: dict) -> "SessionUsage":
        return cls(
            id=str(ligne["id"]), plan=ligne["plan"],
            started_at=datetime.fromisoformat(ligne["started_at"]),
            ends_at=datetime.fromisoformat(ligne["ends_at"]),
            messages_used=int(ligne.get("messages_used") or 0),
            tokens_used=int(ligne.get("tokens_used") or 0),
        )


class SupabaseAdmin:
    def __init__(self, url: str, service_role_key: str, *, timeout: float = 5.0) -> None:
        headers = {"apikey": service_role_key, "Content-Type": "application/json"}
        # Clé legacy (JWT `service_role`) : aussi en Bearer. Les nouvelles clés
        # secrètes (`sb_secret_...`) ne sont pas des JWT : `apikey` seul.
        if not service_role_key.startswith("sb_"):
            headers["Authorization"] = f"Bearer {service_role_key}"
        self._http = httpx.AsyncClient(
            base_url=f"{url.rstrip('/')}/rest/v1",
            headers=headers,
            timeout=timeout,
        )

    async def get_user_limits(self, user_id: str) -> UserLimits | None:
        """Limites effectives (offre ou exception), calculées en SQL : une
        seule source de vérité pour le backend, get_my_quota et la vue admin."""
        resp = await self._http.post("/rpc/limites_effectives", json={"p_user_id": user_id})
        resp.raise_for_status()
        rows = resp.json()
        if not rows:
            return None     # compte inconnu, ou offre absente de plan_config
        row = rows[0]
        return UserLimits(
            plan=row["plan"],
            daily_message_limit=row["daily_message_limit"],
            daily_token_limit=row["daily_token_limit"],
            llm_provider=row["llm_provider"],
            llm_model=row["llm_model"],
            session_duration_minutes=row["session_duration_minutes"],
            session_message_limit=row["session_message_limit"],
            session_token_limit=row["session_token_limit"],
            critical_threshold_percent=row["critical_threshold_percent"],
            exception=bool(row["limits_override"]),
        )

    # --- Sessions d'utilisation -------------------------------------------------

    async def session_active(self, user_id: str) -> SessionUsage | None:
        resp = await self._http.post("/rpc/session_active", json={"p_user_id": user_id})
        resp.raise_for_status()
        rows = resp.json()
        return SessionUsage.depuis_ligne(rows[0]) if rows else None

    async def ouvrir_session(self, user_id: str, plan: str, duree_minutes: int) -> SessionUsage:
        """Session en cours, ou nouvelle (verrou par compte côté SQL)."""
        resp = await self._http.post("/rpc/ouvrir_session", json={
            "p_user_id": user_id, "p_plan": plan, "p_duree_minutes": duree_minutes})
        resp.raise_for_status()
        return SessionUsage.depuis_ligne(resp.json())

    async def increment_session_usage(self, session_id: str, user_id: str, messages: int, tokens: int) -> None:
        resp = await self._http.post("/rpc/increment_session_usage", json={
            "p_session_id": session_id, "p_user_id": user_id, "p_messages": messages, "p_tokens": tokens})
        resp.raise_for_status()

    async def increment_llm_usage(self, user_id: str, provider: str, model: str,
                                  requests: int, tokens_input: int, tokens_output: int) -> None:
        """Suivi des coûts estimés : tokens par jour, fournisseur et modèle."""
        resp = await self._http.post("/rpc/increment_llm_usage", json={
            "p_user_id": user_id, "p_provider": provider, "p_model": model,
            "p_requests": requests, "p_input": tokens_input, "p_output": tokens_output})
        resp.raise_for_status()

    async def get_daily_usage(self, user_id: str, day: date) -> tuple[int, int]:
        """Renvoie (messages_used, tokens_used) pour le jour UTC donné."""
        resp = await self._http.get(
            "/quota_usage",
            params={
                "user_id": f"eq.{user_id}",
                "usage_date": f"eq.{day.isoformat()}",
                "select": "messages_used,tokens_used",
            },
        )
        resp.raise_for_status()
        rows = resp.json()
        if not rows:
            return 0, 0
        return int(rows[0]["messages_used"]), int(rows[0]["tokens_used"])

    async def increment_quota_usage(self, user_id: str, messages: int, tokens: int) -> None:
        resp = await self._http.post(
            "/rpc/increment_quota_usage",
            json={"p_user_id": user_id, "p_messages": messages, "p_tokens": tokens},
        )
        resp.raise_for_status()

    async def list_plan_config(self) -> list[dict]:
        """Offres (fournisseur, modèle) : vérification du routage, jamais une clé."""
        resp = await self._http.get("/plan_config", params={"select": "plan,llm_provider,llm_model",
                                                             "order": "plan"})
        resp.raise_for_status()
        return resp.json()

    # Connexions externes (Gmail) ------------------------------------------------
    # Le jeton de rafraîchissement reste dans Vault ; ces fonctions SQL sont
    # réservées au backend (service_role). Jamais journalisé.

    async def enregistrer_connexion(self, user_id: str, provider: str, email: str, scopes: list[str],
                                    jeton: str) -> str:
        resp = await self._http.post("/rpc/enregistrer_connexion_externe", json={
            "p_user_id": user_id, "p_provider": provider, "p_email": email, "p_scopes": scopes, "p_jeton": jeton})
        resp.raise_for_status()
        return resp.json()

    async def jeton_connexion(self, user_id: str, provider: str) -> dict | None:
        """{connexion_id, account_email, scopes, status, jeton} ou None."""
        resp = await self._http.post("/rpc/jeton_connexion_externe",
                                     json={"p_user_id": user_id, "p_provider": provider})
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def etat_connexion(self, user_id: str, provider: str) -> dict | None:
        """Colonnes non sensibles de la connexion (jamais le jeton)."""
        resp = await self._http.get("/external_connections", params={
            "user_id": f"eq.{user_id}", "provider": f"eq.{provider}",
            "select": "account_email,scopes,status,connected_at,last_used_at,last_error"})
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def marquer_connexion(self, user_id: str, provider: str, status: str, erreur: str | None = None) -> None:
        resp = await self._http.post("/rpc/marquer_connexion_externe", json={
            "p_user_id": user_id, "p_provider": provider, "p_status": status, "p_erreur": erreur})
        resp.raise_for_status()

    async def supprimer_connexion(self, user_id: str, provider: str) -> bool:
        resp = await self._http.post("/rpc/supprimer_connexion_externe",
                                     json={"p_user_id": user_id, "p_provider": provider})
        resp.raise_for_status()
        return bool(resp.json())

    async def ping(self) -> None:
        resp = await self._http.get("/users", params={"select": "id", "limit": "1"})
        resp.raise_for_status()

    async def set_user_plan(
        self, user_id: str, plan: str, *, exception: bool = False,
        daily_message_limit: int | None = None, daily_token_limit: int | None = None,
    ) -> None:
        """Abonnement d'un compte. Sans exception : il suit son offre
        (plan_config), ses anciennes limites personnelles ne sont pas lues.
        Avec exception : limites personnelles (None = illimité)."""
        champs: dict = {"plan": plan, "limits_override": exception}
        if exception:
            champs |= {"daily_message_limit": daily_message_limit, "daily_token_limit": daily_token_limit}
        resp = await self._http.patch("/users", params={"id": f"eq.{user_id}"}, json=champs)
        resp.raise_for_status()

    async def find_user_id(self, email: str) -> str | None:
        resp = await self._http.get("/users", params={"email": f"eq.{email}", "select": "id"})
        resp.raise_for_status()
        rows = resp.json()
        return rows[0]["id"] if rows else None

    # Conversations & messages --------------------------------------------------

    async def get_conversation(self, conversation_id: str, user_id: str) -> dict | None:
        """La conversation, seulement si elle appartient à `user_id`."""
        resp = await self._http.get(
            "/conversations",
            params={
                "id": f"eq.{conversation_id}",
                "user_id": f"eq.{user_id}",
                "select": "id,title,persona",
            },
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def create_conversation(self, user_id: str, title: str) -> dict:
        resp = await self._http.post(
            "/conversations",
            json={"user_id": user_id, "title": title},
            params={"select": "id,title,persona"},
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return resp.json()[0]

    async def get_recent_messages(self, conversation_id: str, limit: int) -> list[dict]:
        """Les `limit` derniers messages, du plus ancien au plus récent."""
        resp = await self._http.get(
            "/messages",
            params={
                "conversation_id": f"eq.{conversation_id}",
                "select": "role,content,attachments",
                "order": "created_at.desc",
                "limit": str(limit),
            },
        )
        resp.raise_for_status()
        return list(reversed(resp.json()))

    async def count_messages(self, conversation_id: str) -> int:
        """Nombre exact de messages de la conversation (aucune ligne lue)."""
        resp = await self._http.get(
            "/messages",
            params={"conversation_id": f"eq.{conversation_id}", "select": "id", "limit": "1"},
            headers={"Prefer": "count=exact"},
        )
        resp.raise_for_status()
        plage = resp.headers.get("content-range", "")
        total = plage.rsplit("/", 1)[-1]
        return int(total) if total.isdigit() else len(resp.json())

    async def get_messages_range(self, conversation_id: str, *, offset: int, limit: int) -> list[dict]:
        """Messages [offset, offset+limit) du plus ancien au plus récent
        (résumé des parties anciennes)."""
        if limit <= 0:
            return []
        resp = await self._http.get(
            "/messages",
            params={
                "conversation_id": f"eq.{conversation_id}",
                "select": "role,content",
                "order": "created_at.asc,id.asc",
                "offset": str(max(0, offset)),
                "limit": str(limit),
            },
        )
        resp.raise_for_status()
        return resp.json()

    async def get_message(self, message_id: str) -> dict | None:
        """Propriétaire et conversation d'un message (tous comptes : le
        contrôle d'appartenance est fait par l'appelant)."""
        resp = await self._http.get(
            "/messages",
            params={"id": f"eq.{message_id}", "select": "id,conversation_id,user_id"},
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def get_user_message(self, message_id: str, user_id: str) -> dict | None:
        """Un message `user` de ce compte (consigne d'une pièce jointe)."""
        resp = await self._http.get(
            "/messages",
            params={
                "id": f"eq.{message_id}",
                "user_id": f"eq.{user_id}",
                "role": "eq.user",
                "select": "id,conversation_id,content",
            },
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def insert_messages(self, rows: list[dict]) -> None:
        # Insertion groupée : PostgREST exige les mêmes clés dans chaque
        # objet (sinon 400 PGRST102), or le message utilisateur n'a ni
        # modèle ni tokens. `columns` liste toutes les colonnes envoyées ;
        # une clé absente d'un objet prend la valeur par défaut de la base.
        columns = sorted({key for row in rows for key in row})
        resp = await self._http.post(
            "/messages",
            json=rows,
            params={"columns": ",".join(columns)},
            headers={"Prefer": "return=minimal,missing=default"},
        )
        resp.raise_for_status()

    # Contextes WhatsApp (conversation_contexts, context_messages) ------------
    # Toujours filtrés par user_id : la clé service_role contourne la RLS.

    CONTEXT_FIELDS = (
        "id,conversation_id,message_id,source,contact_name,is_group,"
        "current_user_name,participants,period_start,period_end,"
        "dates_uncertain,created_at"
    )
    # Nombre réel de messages, calculé par PostgREST (jamais stocké).
    CONTEXT_SELECT = CONTEXT_FIELDS + ",context_messages(count)"
    CONTEXT_MESSAGE_FIELDS = (
        "id,message_order,source_order,author,content,kind,media_type,sent_at,sent_at_raw,"
        "origin,edited_at,declared_proposition_id,created_at"
    )

    async def save_whatsapp_context(self, params: dict, *, timeout: float = 30.0) -> dict:
        """Appelle `enregistrer_contexte_whatsapp` : conversation, consigne,
        contexte et messages en UNE transaction (tout ou rien)."""
        resp = await self._http.post(
            "/rpc/enregistrer_contexte_whatsapp", json=params, timeout=timeout
        )
        resp.raise_for_status()
        return resp.json()

    async def list_contexts(self, conversation_id: str, user_id: str) -> list[dict]:
        resp = await self._http.get(
            "/conversation_contexts",
            params={
                "conversation_id": f"eq.{conversation_id}",
                "user_id": f"eq.{user_id}",
                "select": self.CONTEXT_SELECT,
                "order": "created_at.asc,id.asc",
            },
        )
        resp.raise_for_status()
        return resp.json()

    # --- Phase 5 : messages ajoutés à la main (origin manual_*) ------------

    async def add_context_messages(self, user_id: str, context_id: str, messages: list[dict]) -> list[dict]:
        """`ajouter_messages_contexte` : ajout atomique à la suite du contexte
        (verrou du contexte, rangs suivants, idempotent par identifiant)."""
        resp = await self._http.post(
            "/rpc/ajouter_messages_contexte",
            json={"p_user_id": user_id, "p_context_id": context_id, "p_messages": messages},
        )
        resp.raise_for_status()
        return resp.json()

    async def update_manual_message(
        self, message_id: str, context_id: str, user_id: str, champs: dict
    ) -> list[dict]:
        """Corrige un message AJOUTÉ (jamais un message d'export : filtre et
        déclencheur en base). Lignes modifiées (vide : introuvable)."""
        resp = await self._http.patch(
            "/context_messages",
            params={"id": f"eq.{message_id}", "context_id": f"eq.{context_id}",
                    "user_id": f"eq.{user_id}", "origin": "neq.export",
                    "select": self.CONTEXT_MESSAGE_FIELDS},
            json=champs,
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return resp.json()

    async def delete_manual_message(self, message_id: str, context_id: str, user_id: str) -> bool:
        resp = await self._http.delete(
            "/context_messages",
            params={"id": f"eq.{message_id}", "context_id": f"eq.{context_id}",
                    "user_id": f"eq.{user_id}", "origin": "neq.export", "select": "id"},
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return bool(resp.json())

    async def get_context_message(self, message_id: str, context_id: str, user_id: str) -> dict | None:
        resp = await self._http.get(
            "/context_messages",
            params={"id": f"eq.{message_id}", "context_id": f"eq.{context_id}",
                    "user_id": f"eq.{user_id}", "select": self.CONTEXT_MESSAGE_FIELDS},
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def list_last_context_messages(self, context_id: str, user_id: str, limit: int) -> list[dict]:
        """Les derniers messages (doublons d'un ajout), du plus récent au plus ancien."""
        resp = await self._http.get(
            "/context_messages",
            params={"context_id": f"eq.{context_id}", "user_id": f"eq.{user_id}",
                    "select": self.CONTEXT_MESSAGE_FIELDS, "order": "message_order.desc",
                    "limit": str(limit)},
        )
        resp.raise_for_status()
        return resp.json()

    async def list_user_contexts(self, user_id: str, *, limit: int = 50) -> list[dict]:
        """Toutes les pièces jointes du compte (les plus récentes d'abord)."""
        resp = await self._http.get(
            "/conversation_contexts",
            params={"user_id": f"eq.{user_id}", "select": self.CONTEXT_SELECT,
                    "order": "created_at.desc", "limit": str(limit)},
        )
        resp.raise_for_status()
        return resp.json()

    async def get_context(self, context_id: str, user_id: str) -> dict | None:
        resp = await self._http.get(
            "/conversation_contexts",
            params={
                "id": f"eq.{context_id}",
                "user_id": f"eq.{user_id}",
                "select": self.CONTEXT_SELECT,
            },
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def list_context_messages(
        self, context_id: str, user_id: str, *, after: int, limit: int, manuels: bool = False
    ) -> list[dict]:
        """Une page de messages, dans l'ordre original (pagination par rang,
        index unique (context_id, message_order))."""
        resp = await self._http.get(
            "/context_messages",
            params={
                "context_id": f"eq.{context_id}",
                "user_id": f"eq.{user_id}",
                "message_order": f"gt.{after}",
                "select": self.CONTEXT_MESSAGE_FIELDS,
                "order": "message_order.asc",
                "limit": str(limit),
                **({"origin": "neq.export"} if manuels else {}),
            },
        )
        resp.raise_for_status()
        return resp.json()

    async def get_context_messages_by_ids(self, ids: list[str], user_id: str) -> list[dict]:
        """Messages WhatsApp désignés par leur identifiant, de ce compte
        seulement (un identifiant d'un autre compte ne renvoie rien)."""
        if not ids:
            return []
        resp = await self._http.get(
            "/context_messages",
            params={
                "id": f"in.({','.join(ids)})",
                "user_id": f"eq.{user_id}",
                "select": "context_id," + self.CONTEXT_MESSAGE_FIELDS,
            },
        )
        resp.raise_for_status()
        return resp.json()

    # Références vérifiées : rangées avec la réponse, dans
    # `messages.attachments` (colonne JSON existante), entrées de type
    # « reference_whatsapp ».

    async def get_assistant_attachments(
        self, conversation_id: str, user_id: str, *, limit: int | None = None
    ) -> list[dict]:
        """Réponses de JARVIS qui portent des références (les plus récentes
        d'abord) : [{id, attachments}]."""
        params = {
            "conversation_id": f"eq.{conversation_id}",
            "user_id": f"eq.{user_id}",
            "role": "eq.assistant",
            "attachments": "neq.[]",
            "select": "id,attachments",
            "order": "created_at.desc",
        }
        if limit is not None:
            params["limit"] = str(limit)
        resp = await self._http.get("/messages", params=params)
        resp.raise_for_status()
        return resp.json()

    # Réponses déclarées envoyées (phase 4) : dans `messages.attachments` de
    # la réponse de JARVIS qui porte les propositions, type
    # « reponse_envoyee ». Jamais dans `context_messages` (messages WhatsApp
    # originaux).

    async def get_assistant_message(
        self, message_id: str, conversation_id: str, user_id: str
    ) -> dict | None:
        """Une réponse de JARVIS de CE chat et de CE compte, ou None."""
        resp = await self._http.get(
            "/messages",
            params={
                "id": f"eq.{message_id}",
                "conversation_id": f"eq.{conversation_id}",
                "user_id": f"eq.{user_id}",
                "role": "eq.assistant",
                "select": "id,conversation_id,content,attachments",
            },
        )
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    async def update_message_attachments(
        self, message_id: str, user_id: str, attachments: list[dict]
    ) -> None:
        resp = await self._http.patch(
            "/messages",
            params={"id": f"eq.{message_id}", "user_id": f"eq.{user_id}"},
            json={"attachments": attachments},
        )
        resp.raise_for_status()

    async def declare_reply(self, user_id: str, conversation_id: str, message_id: str, entree: dict) -> dict:
        """`declarer_reponse_envoyee` : un seul choix actif par ensemble,
        réponse verrouillée (deux appareils simultanés : un seul gagne)."""
        resp = await self._http.post("/rpc/declarer_reponse_envoyee", json={
            "p_user_id": user_id, "p_conversation_id": conversation_id,
            "p_message_id": message_id, "p_entree": entree})
        resp.raise_for_status()
        return resp.json()

    async def cancel_reply(self, user_id: str, conversation_id: str, message_id: str,
                           proposition_id: str, quand: str) -> dict:
        resp = await self._http.post("/rpc/annuler_reponse_envoyee", json={
            "p_user_id": user_id, "p_conversation_id": conversation_id,
            "p_message_id": message_id, "p_proposition_id": proposition_id, "p_annulee_le": quand})
        resp.raise_for_status()
        return resp.json()

    async def list_declared_replies(self, user_id: str, *, limit: int = 100) -> list[dict]:
        """Réponses de JARVIS du compte qui portent une réponse déclarée
        envoyée (tous chats), les plus récentes d'abord."""
        resp = await self._http.get(
            "/messages",
            params={
                "user_id": f"eq.{user_id}",
                "role": "eq.assistant",
                "attachments": 'cs.[{"type":"reponse_envoyee"}]',
                "select": "id,conversation_id,attachments",
                "order": "created_at.desc",
                "limit": str(limit),
            },
        )
        resp.raise_for_status()
        return resp.json()

    async def delete_context(self, context_id: str, user_id: str) -> bool:
        """Supprime le contexte (ses messages suivent par cascade). Faux si
        aucun contexte de ce compte ne porte cet identifiant."""
        resp = await self._http.delete(
            "/conversation_contexts",
            params={"id": f"eq.{context_id}", "user_id": f"eq.{user_id}", "select": "id"},
            headers={"Prefer": "return=representation"},
        )
        resp.raise_for_status()
        return bool(resp.json())

    async def aclose(self) -> None:
        await self._http.aclose()


_supabase: SupabaseAdmin | None = None


def init_supabase(url: str, service_role_key: str) -> SupabaseAdmin:
    global _supabase
    _supabase = SupabaseAdmin(url, service_role_key)
    return _supabase


def get_supabase() -> SupabaseAdmin:
    if _supabase is None:
        raise RuntimeError("Supabase non initialisé : appeler init_supabase() au démarrage.")
    return _supabase


async def close_supabase() -> None:
    global _supabase
    if _supabase is not None:
        await _supabase.aclose()
        _supabase = None
