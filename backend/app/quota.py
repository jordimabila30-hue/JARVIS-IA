"""Quotas par utilisateur : par jour ET par session (abonnements Free / Pro).

Limites : EFFECTIVES, lues dans Supabase (fonction `limites_effectives` :
offre `plan_config` du plan du compte, sauf exception `users.limits_override`),
mises en cache dans Redis `QUOTA_LIMITS_CACHE_TTL` secondes (30 par défaut) :
une modification dans l'éditeur de tables s'applique au plus tard après ce
délai, sans redémarrage.

Quota quotidien : Redis tient le compteur temps réel ; Supabase (`quota_usage`)
garde la trace persistante et réhydrate Redis si une clé manque.

Session : fenêtre ouverte au PREMIER appel IA autorisé (fonction SQL
`ouvrir_session`, verrou par compte), d'une durée `session_duration_minutes`
figée à l'ouverture (heure du serveur). Commune à tous les appareils ;
persistante (`usage_sessions`), réhydratée comme le quota du jour. Sans durée
de session dans les limites (anciens profils), pas de quota de session.

Clés Redis :
  quota:{user}:{YYYY-MM-DD}:requests / :tokens   compteurs du jour (TTL minuit UTC)
  quota:{user}:limites                           cache JSON des limites effectives
  session:{user}:active                          session en cours (JSON, TTL fin de session)
  session:{user}:{id}:requests / :tokens         compteurs de la session (TTL fin de session)

Cycle d'une requête :
  1. reserve()       contrôle jour + session et compte la requête dans les DEUX
                     en un seul script Lua (atomique : pas de dépassement par des
                     appels simultanés, pas de double comptage) ;
  2. record_usage()  après la réponse : tokens dans Redis et Supabase (jour,
                     session, suivi par fournisseur) ;
  3. release()       aucune réponse produite : la requête est rendue (jour et session).

Les tokens sont vérifiés avant la requête (le coût exact n'est connu
qu'après) ; `budget_depasse` refuse en plus une demande dont l'entrée estimée
dépasse déjà le reste. Les plafonds de sortie bornent le dépassement.
"""

import json
import logging
import math
from dataclasses import dataclass, field, replace
from datetime import date, datetime, time, timedelta, timezone

import httpx
from fastapi import Depends, HTTPException, status
from redis.asyncio import Redis
from redis.exceptions import RedisError

from .auth import AuthUser, get_current_user
from .supabase_client import SessionUsage, SupabaseAdmin, UserLimits

logger = logging.getLogger(__name__)

UNLIMITED = -1

# Codes de retour du script de réservation
_MISS = -1             # compteurs du jour absents : réhydrater depuis Supabase
_MISS_SESSION = -3     # compteurs de session absents : réhydrater depuis Supabase
_DENIED_MESSAGES = 0
_OK = 1
_DENIED_TOKENS = 2
_DENIED_SESSION_MESSAGES = 3
_DENIED_SESSION_TOKENS = 4

# KEYS : [1] requêtes du jour, [2] tokens du jour, [3] requêtes de session,
#        [4] tokens de session ([3] et [4] absents : pas de session)
# ARGV : 1 limite messages jour, 2 limite tokens jour, 3 ttl jour,
#        4 réhydrater jour (0/1), 5 requêtes, 6 tokens,
#        7 limite messages session, 8 limite tokens session, 9 ttl session,
#        10 réhydrater session (0/1), 11 requêtes, 12 tokens,
#        13 consulter seulement (0/1 : contrôle sans rien compter)
_RESERVE_LUA = """
local session = #KEYS == 4
if ARGV[4] == '1' then
  -- NX : si une requête concurrente a déjà réhydraté, on ne l'écrase pas.
  redis.call('SET', KEYS[1], ARGV[5], 'NX', 'EX', ARGV[3])
  redis.call('SET', KEYS[2], ARGV[6], 'NX', 'EX', ARGV[3])
end
if session and ARGV[10] == '1' then
  redis.call('SET', KEYS[3], ARGV[11], 'NX', 'EX', ARGV[9])
  redis.call('SET', KEYS[4], ARGV[12], 'NX', 'EX', ARGV[9])
end

local req = redis.call('GET', KEYS[1])
local tok = redis.call('GET', KEYS[2])
if not req or not tok then
  return {-1, 0, 0, 0, 0}
end
req = tonumber(req)
tok = tonumber(tok)
local sreq, stok = 0, 0
if session then
  sreq = redis.call('GET', KEYS[3])
  stok = redis.call('GET', KEYS[4])
  if not sreq or not stok then
    return {-3, req, tok, 0, 0}
  end
  sreq = tonumber(sreq)
  stok = tonumber(stok)
end

local msg_limit = tonumber(ARGV[1])
local tok_limit = tonumber(ARGV[2])
if msg_limit >= 0 and req >= msg_limit then return {0, req, tok, sreq, stok} end
if tok_limit >= 0 and tok >= tok_limit then return {2, req, tok, sreq, stok} end
if session then
  local smsg = tonumber(ARGV[7])
  local stokl = tonumber(ARGV[8])
  if smsg >= 0 and sreq >= smsg then return {3, req, tok, sreq, stok} end
  if stokl >= 0 and stok >= stokl then return {4, req, tok, sreq, stok} end
end
if ARGV[13] == '1' then
  return {1, req, tok, sreq, stok}
end

req = redis.call('INCR', KEYS[1])
if session then
  sreq = redis.call('INCR', KEYS[3])
end
return {1, req, tok, sreq, stok}
"""

# N'incrémente que si la clé existe : une clé recréée sans réhydratation
# fausserait le compteur. Si elle a disparu, le prochain reserve() la
# réhydratera depuis Supabase, déjà à jour.
_INCRBY_IF_EXISTS_LUA = """
if redis.call('EXISTS', KEYS[1]) == 1 then
  return redis.call('INCRBY', KEYS[1], ARGV[1])
end
return -1
"""

_DECR_IF_POSITIVE_LUA = """
local v = tonumber(redis.call('GET', KEYS[1]) or '0')
if v > 0 then
  return redis.call('DECR', KEYS[1])
end
return v
"""


# --- Clés & temps ---------------------------------------------------------------

def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def requests_key(user_id: str, day: date) -> str:
    return f"quota:{user_id}:{day.isoformat()}:requests"


def tokens_key(user_id: str, day: date) -> str:
    return f"quota:{user_id}:{day.isoformat()}:tokens"


def limits_key(user_id: str) -> str:
    """Cache des limites effectives (JSON)."""
    return f"quota:{user_id}:limites"


def limits_cache_keys(user_id: str) -> list[str]:
    """Toutes les clés de cache des limites, ancien format (hash) compris."""
    return [limits_key(user_id), f"quota:{user_id}:limits"]


def session_active_key(user_id: str) -> str:
    return f"session:{user_id}:active"


def session_keys(user_id: str, session_id: str) -> list[str]:
    return [f"session:{user_id}:{session_id}:requests", f"session:{user_id}:{session_id}:tokens"]


def seconds_until_utc_midnight(now: datetime) -> int:
    midnight = datetime.combine(now.date() + timedelta(days=1), time.min, tzinfo=timezone.utc)
    return max(1, math.ceil((midnight - now).total_seconds()))


def _secondes_jusqua(fin: datetime, now: datetime) -> int:
    return max(1, math.ceil((fin - now).total_seconds()))


def _encode_limit(value: int | None) -> int:
    return UNLIMITED if value is None else value


def _decode_limit(value: str | int) -> int | None:
    value = int(value)
    return None if value == UNLIMITED else value


def _reste(limite: int | None, utilise: int) -> int | None:
    return None if limite is None else max(0, limite - utilise)


# --- Modèles --------------------------------------------------------------------

@dataclass(frozen=True)
class SessionStatus:
    id: str
    started_at: datetime
    ends_at: datetime
    duration_minutes: int
    messages_used: int
    messages_limit: int | None
    tokens_used: int
    tokens_limit: int | None
    now: datetime = field(default_factory=utc_now, compare=False)

    @property
    def messages_remaining(self) -> int | None:
        return _reste(self.messages_limit, self.messages_used)

    @property
    def tokens_remaining(self) -> int | None:
        return _reste(self.tokens_limit, self.tokens_used)

    @property
    def resets_in(self) -> int:
        return _secondes_jusqua(self.ends_at, self.now)

    def to_dict(self) -> dict:
        return {
            "active": True,
            "id": self.id,
            "started_at": self.started_at.isoformat(),
            "ends_at": self.ends_at.isoformat(),
            "resets_in": self.resets_in,
            "duration_minutes": self.duration_minutes,
            "messages_used": self.messages_used,
            "messages_limit": self.messages_limit,
            "messages_remaining": self.messages_remaining,
            "tokens_used": self.tokens_used,
            "tokens_limit": self.tokens_limit,
            "tokens_remaining": self.tokens_remaining,
        }


@dataclass(frozen=True)
class QuotaStatus:
    plan: str
    day: date
    messages_used: int
    messages_limit: int | None
    tokens_used: int
    tokens_limit: int | None
    resets_in: int  # secondes avant minuit UTC
    session: SessionStatus | None = None
    # Offre (pour l'app : jauges, libellés) — None pour les anciens profils.
    llm_provider: str | None = None
    llm_model: str | None = None
    critical_threshold_percent: int | None = None
    exception: bool = False
    session_duration_minutes: int | None = None
    session_messages_limit: int | None = None
    session_tokens_limit: int | None = None

    @property
    def messages_remaining(self) -> int | None:
        return _reste(self.messages_limit, self.messages_used)

    @property
    def tokens_remaining(self) -> int | None:
        return _reste(self.tokens_limit, self.tokens_used)

    def headers(self) -> dict[str, str]:
        """En-têtes exposés à Flutter pour la jauge (-1 = illimité)."""
        def fmt(v: int | None) -> str:
            return str(UNLIMITED if v is None else v)

        entetes = {
            "X-Quota-Plan": self.plan,
            "X-Quota-Messages-Limit": fmt(self.messages_limit),
            "X-Quota-Messages-Remaining": fmt(self.messages_remaining),
            "X-Quota-Tokens-Limit": fmt(self.tokens_limit),
            "X-Quota-Tokens-Remaining": fmt(self.tokens_remaining),
            "X-Quota-Reset": str(self.resets_in),
        }
        if self.session is not None:
            entetes |= {
                "X-Quota-Session-Messages-Remaining": fmt(self.session.messages_remaining),
                "X-Quota-Session-Tokens-Remaining": fmt(self.session.tokens_remaining),
                "X-Quota-Session-Reset": str(self.session.resets_in),
            }
        return entetes

    def to_dict(self) -> dict:
        now = self.session.now if self.session is not None else utc_now()
        session = self.session.to_dict() if self.session is not None else {
            "active": False, "id": None, "started_at": None, "ends_at": None, "resets_in": None,
            "duration_minutes": self.session_duration_minutes,
            "messages_used": 0, "messages_limit": self.session_messages_limit,
            "messages_remaining": self.session_messages_limit,
            "tokens_used": 0, "tokens_limit": self.session_tokens_limit,
            "tokens_remaining": self.session_tokens_limit,
        }
        return {
            "plan": self.plan,
            "date": self.day.isoformat(),
            "messages_used": self.messages_used,
            "messages_limit": self.messages_limit,
            "messages_remaining": self.messages_remaining,
            "tokens_used": self.tokens_used,
            "tokens_limit": self.tokens_limit,
            "tokens_remaining": self.tokens_remaining,
            "resets_in": self.resets_in,
            "resets_at": (now + timedelta(seconds=self.resets_in)).replace(microsecond=0).isoformat(),
            "llm_provider": self.llm_provider,
            "llm_model": self.llm_model,
            "critical_threshold_percent": self.critical_threshold_percent,
            "exception": self.exception,
            "session": session,
        }


@dataclass(frozen=True)
class QuotaReservation:
    user: AuthUser
    status: QuotaStatus


_MESSAGES_LIMITE = {
    "messages": "Limite quotidienne de messages atteinte",
    "tokens": "Limite quotidienne de tokens atteinte",
    "session_messages": "Limite de messages de la session atteinte",
    "session_tokens": "Limite de tokens de la session atteinte",
}


def quota_exceeded(kind: str, quota: QuotaStatus) -> HTTPException:
    """429 explicite : type de limite et prochaine réinitialisation (fin de
    session pour une limite de session, minuit UTC sinon)."""
    if kind.startswith("session_") and quota.session is not None:
        resets_in = quota.session.resets_in
        resets_at = quota.session.ends_at
    else:
        resets_in = quota.resets_in
        resets_at = utc_now() + timedelta(seconds=resets_in)
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "error": "quota_exceeded", "kind": kind, "message": _MESSAGES_LIMITE[kind],
            "resets_in": resets_in, "resets_at": resets_at.replace(microsecond=0).isoformat(),
            "quota": quota.to_dict(),
        },
        headers={**quota.headers(), "Retry-After": str(resets_in)},
    )


_quota_exceeded = quota_exceeded     # nom historique

_CODES_REFUS = {
    _DENIED_MESSAGES: "messages", _DENIED_TOKENS: "tokens",
    _DENIED_SESSION_MESSAGES: "session_messages", _DENIED_SESSION_TOKENS: "session_tokens",
}


def _limits_json(limits: UserLimits) -> str:
    return json.dumps(limits.__dict__)


# --- Service --------------------------------------------------------------------

class QuotaService:
    def __init__(self, redis: Redis, supabase: SupabaseAdmin, *, limits_cache_ttl: int = 30) -> None:
        self._redis = redis
        self._supabase = supabase
        self._limits_cache_ttl = limits_cache_ttl
        self._reserve_script = redis.register_script(_RESERVE_LUA)
        self._incrby_script = redis.register_script(_INCRBY_IF_EXISTS_LUA)
        self._decr_script = redis.register_script(_DECR_IF_POSITIVE_LUA)

    # Limites ---------------------------------------------------------------------

    async def get_limits(self, user_id: str) -> UserLimits:
        """Limites effectives (cache court). 403 si le compte ou son offre
        est introuvable."""
        key = limits_key(user_id)
        try:
            cached = await self._redis.get(key)
        except RedisError:
            logger.warning("Redis indisponible pour le cache des limites", exc_info=True)
            cached = None
        if cached:
            return UserLimits(**json.loads(cached))

        limits = await self._supabase.get_user_limits(user_id)
        if limits is None:
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Profil utilisateur ou offre introuvable")
        try:
            await self._redis.set(key, _limits_json(limits), ex=self._limits_cache_ttl)
        except RedisError:
            logger.warning("Impossible de mettre en cache les limites", exc_info=True)
        return limits

    async def invalidate_limits(self, user_id: str) -> None:
        """À appeler après un changement d'abonnement ou d'exception."""
        await self._redis.delete(*limits_cache_keys(user_id))

    # Sessions --------------------------------------------------------------------

    async def _memoriser_session(self, user_id: str, s: SessionUsage, now: datetime) -> None:
        await self._redis.set(session_active_key(user_id), json.dumps({
            "id": s.id, "plan": s.plan, "started_at": s.started_at.isoformat(), "ends_at": s.ends_at.isoformat(),
        }), ex=_secondes_jusqua(s.ends_at, now))

    async def _session_en_cours(self, user_id: str, now: datetime) -> SessionUsage | None:
        """Session active (Redis, sinon Supabase), sans jamais en créer."""
        brut = await self._redis.get(session_active_key(user_id))
        if brut:
            d = json.loads(brut)
            s = SessionUsage(id=d["id"], plan=d["plan"], started_at=datetime.fromisoformat(d["started_at"]),
                             ends_at=datetime.fromisoformat(d["ends_at"]))
            if s.ends_at > now:
                return s
        s = await self._supabase.session_active(user_id)
        if s is None or s.ends_at <= now:
            return None
        await self._memoriser_session(user_id, s, now)
        return s

    async def _usage_session(self, user_id: str, s: SessionUsage) -> tuple[int, int]:
        """Consommation persistée d'une session (réhydratation)."""
        frais = await self._supabase.session_active(user_id)
        if frais is not None and frais.id == s.id:
            return frais.messages_used, frais.tokens_used
        return s.messages_used, s.tokens_used

    @staticmethod
    def _statut_session(s: SessionUsage, limits: UserLimits, req: int, tok: int, now: datetime) -> SessionStatus:
        duree = round((s.ends_at - s.started_at).total_seconds() / 60)
        return SessionStatus(
            id=s.id, started_at=s.started_at, ends_at=s.ends_at, duration_minutes=duree,
            messages_used=req, messages_limit=limits.session_message_limit,
            tokens_used=tok, tokens_limit=limits.session_token_limit, now=now,
        )

    @staticmethod
    def _statut(limits: UserLimits, day: date, req: int, tok: int, ttl: int,
                session: SessionStatus | None) -> QuotaStatus:
        return QuotaStatus(
            plan=limits.plan, day=day,
            messages_used=req, messages_limit=limits.daily_message_limit,
            tokens_used=tok, tokens_limit=limits.daily_token_limit,
            resets_in=ttl, session=session,
            llm_provider=limits.llm_provider, llm_model=limits.llm_model,
            critical_threshold_percent=limits.critical_threshold_percent,
            exception=limits.exception,
            session_duration_minutes=limits.session_duration_minutes,
            session_messages_limit=limits.session_message_limit,
            session_tokens_limit=limits.session_token_limit,
        )

    # Réservation -----------------------------------------------------------------

    async def _executer(self, user_id: str, day: date, limits: UserLimits, ttl: int,
                        session: SessionUsage | None, now: datetime, *, consulter: bool = False):
        """Script de réservation, avec réhydratation des compteurs absents."""
        keys = [requests_key(user_id, day), tokens_key(user_id, day)]
        jour = [0, 0, 0]
        sess = [UNLIMITED, UNLIMITED, 1, 0, 0, 0]
        if session is not None:
            keys += session_keys(user_id, session.id)
            sess = [_encode_limit(limits.session_message_limit), _encode_limit(limits.session_token_limit),
                    _secondes_jusqua(session.ends_at, now), 0, 0, 0]
        for _ in range(3):
            res = await self._reserve_script(keys=keys, args=[
                _encode_limit(limits.daily_message_limit), _encode_limit(limits.daily_token_limit), ttl,
                *jour, *sess, int(consulter)])
            code = int(res[0])
            if code == _MISS:
                jour = [1, *(await self._supabase.get_daily_usage(user_id, day))]
                continue
            if code == _MISS_SESSION:
                sess[3:6] = [1, *(await self._usage_session(user_id, session))]
                continue
            return code, int(res[1]), int(res[2]), int(res[3]), int(res[4])
        raise RuntimeError("Compteurs de quota introuvables après réhydratation")

    async def reserve(self, user_id: str) -> QuotaStatus:
        """Vérifie et consomme une requête (jour + session). 429 si une limite
        est atteinte. Une session ne s'ouvre qu'après le contrôle du jour."""
        limits = await self.get_limits(user_id)
        now = utc_now()
        day = now.date()
        ttl = seconds_until_utc_midnight(now)

        try:
            session = None
            if limits.session_duration_minutes:
                session = await self._session_en_cours(user_id, now)
                if session is None:
                    # Premier appel de la fenêtre : jour vérifié AVANT d'ouvrir
                    # la session (un appel refusé n'ouvre rien).
                    code, req, tok, _, _ = await self._executer(user_id, day, limits, ttl, None, now, consulter=True)
                    if code != _OK:
                        raise quota_exceeded(_CODES_REFUS[code], self._statut(limits, day, req, tok, ttl, None))
                    session = await self._supabase.ouvrir_session(user_id, limits.plan, limits.session_duration_minutes)
                    await self._memoriser_session(user_id, session, now)
            code, req, tok, sreq, stok = await self._executer(user_id, day, limits, ttl, session, now)
        except RedisError:
            logger.error("Redis indisponible : contrôle de quota en mode dégradé", exc_info=True)
            return await self._reserve_degraded(user_id, limits, day, ttl, now)

        statut_session = self._statut_session(session, limits, sreq, stok, now) if session is not None else None
        quota = self._statut(limits, day, req, tok, ttl, statut_session)
        if code in _CODES_REFUS:
            raise quota_exceeded(_CODES_REFUS[code], quota)
        if code != _OK:
            raise RuntimeError(f"Code de retour inattendu du script de quota : {code}")
        return quota

    async def _reserve_degraded(self, user_id: str, limits: UserLimits, day: date, ttl: int,
                                now: datetime) -> QuotaStatus:
        """Sans Redis : contrôle (non atomique) sur les traces Supabase.

        La consommation sera persistée par record_usage() en fin de requête.
        """
        used_messages, used_tokens = await self._supabase.get_daily_usage(user_id, day)
        quota = self._statut(limits, day, used_messages, used_tokens, ttl, None)
        if limits.daily_message_limit is not None and used_messages >= limits.daily_message_limit:
            raise quota_exceeded("messages", quota)
        if limits.daily_token_limit is not None and used_tokens >= limits.daily_token_limit:
            raise quota_exceeded("tokens", quota)
        statut_session = None
        if limits.session_duration_minutes:
            s = await self._supabase.ouvrir_session(user_id, limits.plan, limits.session_duration_minutes)
            statut_session = self._statut_session(s, limits, s.messages_used, s.tokens_used, now)
            quota = replace(quota, session=statut_session)
            if limits.session_message_limit is not None and s.messages_used >= limits.session_message_limit:
                raise quota_exceeded("session_messages", quota)
            if limits.session_token_limit is not None and s.tokens_used >= limits.session_token_limit:
                raise quota_exceeded("session_tokens", quota)
            statut_session = replace(statut_session, messages_used=s.messages_used + 1)
        return replace(quota, messages_used=used_messages + 1, session=statut_session)

    def budget_depasse(self, reservation: QuotaReservation, entree_estimee: int) -> str | None:
        """Type de limite qu'une demande dépasserait DÈS son entrée estimée
        (contrôle avant un appel coûteux), sinon None."""
        q = reservation.status
        if q.tokens_remaining is not None and entree_estimee > q.tokens_remaining:
            return "tokens"
        if q.session is not None and q.session.tokens_remaining is not None \
                and entree_estimee > q.session.tokens_remaining:
            return "session_tokens"
        return None

    # Fin de requête --------------------------------------------------------------

    async def record_usage(self, reservation: QuotaReservation, tokens: int, *,
                           tokens_input: int | None = None, tokens_output: int | None = None,
                           provider: str | None = None, model: str | None = None) -> None:
        """Comptabilise une requête terminée (UNE fois, appels internes compris :
        lots de propositions) : jour, session, suivi par fournisseur."""
        user_id = reservation.user.id
        tokens = max(0, tokens)
        session = reservation.status.session

        # Supabase d'abord : si une clé Redis disparaît entre-temps, la
        # réhydratation lira une valeur à jour.
        try:
            await self._supabase.increment_quota_usage(user_id, 1, tokens)
        except httpx.HTTPError:
            logger.error("Échec de persistance de la consommation (user=%s)", user_id, exc_info=True)
        if session is not None:
            try:
                await self._supabase.increment_session_usage(session.id, user_id, 1, tokens)
            except httpx.HTTPError:
                logger.error("Échec de persistance de la session (user=%s)", user_id, exc_info=True)

        if tokens:
            cles = [tokens_key(user_id, reservation.status.day)]
            if session is not None:
                cles.append(session_keys(user_id, session.id)[1])
            for cle in cles:
                try:
                    await self._incrby_script(keys=[cle], args=[tokens])
                except RedisError:
                    logger.warning("Échec d'incrément des tokens dans Redis (user=%s)", user_id, exc_info=True)

        if provider:
            # Suivi des coûts : jamais bloquant pour la réponse.
            try:
                await self._supabase.increment_llm_usage(
                    user_id, provider, model or "?", 1,
                    max(0, tokens_input if tokens_input is not None else tokens), max(0, tokens_output or 0))
            except Exception:
                logger.warning("Suivi par fournisseur indisponible (user=%s)", user_id, exc_info=True)

    async def release(self, reservation: QuotaReservation) -> None:
        """Rend une requête réservée qui n'a produit aucune réponse (jour et session)."""
        cles = [requests_key(reservation.user.id, reservation.status.day)]
        if reservation.status.session is not None:
            cles.append(session_keys(reservation.user.id, reservation.status.session.id)[0])
        for cle in cles:
            try:
                await self._decr_script(keys=[cle])
            except RedisError:
                logger.warning("Échec de libération du quota (user=%s)", reservation.user.id, exc_info=True)

    # Lecture seule ---------------------------------------------------------------

    async def get_status(self, user_id: str) -> QuotaStatus:
        """État du jour et de la session, sans rien consommer ni ouvrir."""
        limits = await self.get_limits(user_id)
        now = utc_now()
        day = now.date()
        try:
            req, tok = await self._redis.mget(requests_key(user_id, day), tokens_key(user_id, day))
        except RedisError:
            req = tok = None
        if req is None or tok is None:
            used_messages, used_tokens = await self._supabase.get_daily_usage(user_id, day)
        else:
            used_messages, used_tokens = int(req), int(tok)

        statut_session = None
        if limits.session_duration_minutes:
            try:
                s = await self._session_en_cours(user_id, now)
                sreq = stok = None
                if s is not None:
                    sreq, stok = await self._redis.mget(*session_keys(user_id, s.id))
            except RedisError:
                s = await self._supabase.session_active(user_id)
                sreq = stok = None
            if s is not None:
                if sreq is None or stok is None:
                    smsg, stoks = await self._usage_session(user_id, s)
                else:
                    smsg, stoks = int(sreq), int(stok)
                statut_session = self._statut_session(s, limits, smsg, stoks, now)
        return self._statut(limits, day, used_messages, used_tokens, seconds_until_utc_midnight(now), statut_session)


# --- Dépendances FastAPI ------------------------------------------------------

_service: QuotaService | None = None


def init_quota_service(redis: Redis, supabase: SupabaseAdmin, *, limits_cache_ttl: int = 30) -> QuotaService:
    global _service
    _service = QuotaService(redis, supabase, limits_cache_ttl=limits_cache_ttl)
    return _service


def get_quota_service() -> QuotaService:
    if _service is None:
        raise RuntimeError("QuotaService non initialisé : appeler init_quota_service() au démarrage.")
    return _service


async def enforce_quota(
    user: AuthUser = Depends(get_current_user),
    service: QuotaService = Depends(get_quota_service),
) -> QuotaReservation:
    """Dépendance à poser sur les routes coûteuses (ex. POST /chat).

    Authentifie, puis réserve une requête ; lève 401 / 429 sinon.
    La route doit ensuite appeler record_usage() ou release().
    """
    quota = await service.reserve(user.id)
    return QuotaReservation(user=user, status=quota)
