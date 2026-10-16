"""Modèles (Pydantic) des contextes WhatsApp joints aux conversations.

Ils reprennent la pièce jointe préparée par l'application
(`PieceJointeWhatsApp` dans Flutter) : contact, « moi », participants et
messages sélectionnés, chacun avec son rang, son auteur, son contenu, son
type et sa date telle que lue dans l'export.
"""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

TypeMessage = Literal["text", "media", "deleted", "system"]


def _date_locale(value: datetime | None) -> datetime | None:
    """Date d'un export WhatsApp : heure locale SANS fuseau. Une date avec
    fuseau inventerait une précision que l'export ne donne pas."""
    if value is not None and value.tzinfo is not None:
        raise ValueError("date locale attendue, sans fuseau horaire")
    return value


class ContextMessageIn(BaseModel):
    """Un message WhatsApp sélectionné (jamais une commande pour JARVIS)."""

    message_order: int = Field(ge=0, description="Rang dans la sélection (0, 1, 2…)")
    source_order: int | None = Field(None, ge=0, description="Rang dans l'export d'origine")
    author: str | None = Field(None, max_length=200, description="Null : événement de WhatsApp")
    content: str = Field("", max_length=65536)
    kind: TypeMessage = "text"
    media_type: str | None = Field(None, max_length=40, description="Trace d'un média, jamais le fichier")
    sent_at: datetime | None = Field(None, description="Heure locale de l'export ; null si illisible")
    sent_at_raw: str = Field("", max_length=100, description="Date telle qu'écrite dans l'export")

    _locale = field_validator("sent_at")(_date_locale)


class ContextIn(BaseModel):
    source: Literal["whatsapp"] = "whatsapp"
    contact_name: str = Field(min_length=1, max_length=200)
    is_group: bool = False
    current_user_name: str | None = Field(None, max_length=200)
    participants: list[str] = Field(default_factory=list, max_length=1000)
    dates_uncertain: bool = False
    source_fingerprint: str | None = Field(None, max_length=100)

    @field_validator("contact_name")
    @classmethod
    def _contact_non_vide(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("nom du contact vide")
        return value

    @field_validator("participants")
    @classmethod
    def _participants(cls, value: list[str]) -> list[str]:
        if any(len(p) > 200 for p in value):
            raise ValueError("nom de participant trop long")
        return value


class SaveContextRequest(BaseModel):
    """Consigne + pièce jointe WhatsApp, enregistrées ensemble.

    `context_id` et `message_id` sont choisis par l'appareil, une fois par
    pièce jointe : ils rendent un réessai sans effet (idempotence).
    """

    context_id: UUID
    message_id: UUID = Field(description="Identifiant de la consigne (message utilisateur)")
    conversation_id: UUID | None = Field(
        None, description="Chat JARVIS existant ; null : nouvelle conversation (accueil vide)"
    )
    instruction: str = Field(min_length=1, max_length=8000, description="Consigne écrite à JARVIS")
    context: ContextIn
    messages: list[ContextMessageIn] = Field(min_length=1)

    @field_validator("instruction")
    @classmethod
    def _consigne_non_vide(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("consigne vide")
        return value

    @model_validator(mode="after")
    def _coherence(self) -> "SaveContextRequest":
        if self.context_id == self.message_id:
            raise ValueError("identifiants identiques")
        rangs = {m.message_order for m in self.messages}
        if rangs != set(range(len(self.messages))):
            raise ValueError("rangs des messages incohérents (attendu 0..n-1, sans doublon)")
        return self


class SaveContextResponse(BaseModel):
    conversation_id: UUID
    message_id: UUID
    context_id: UUID
    messages_count: int
    conversation_created: bool
    already_saved: bool


class ContextOut(BaseModel):
    id: UUID
    conversation_id: UUID
    message_id: UUID | None
    source: str
    contact_name: str
    is_group: bool
    current_user_name: str | None
    participants: list[str]
    period_start: datetime | None
    period_end: datetime | None
    dates_uncertain: bool
    created_at: datetime
    messages_count: int


Provenance = Literal["export", "manual_received", "manual_sent"]


class ContextMessageOut(ContextMessageIn):
    """Message relu : avec son identifiant et sa PROVENANCE (phase 5). Un
    message « manual_* » a été collé par l'utilisateur : jamais une
    réception vérifiée sur WhatsApp."""

    id: str | None = None
    origin: Provenance = "export"
    edited_at: datetime | None = None
    declared_proposition_id: str | None = None
    # Moment de l'ajout dans JARVIS (place de la bulle dans le fil, 5.1) :
    # jamais la date du message lui-même.
    created_at: datetime | None = None


class ManualMessageIn(BaseModel):
    """Un message collé par l'utilisateur (phase 5)."""

    id: UUID = Field(description="Choisi par l'appareil : un réessai ne duplique rien")
    direction: Literal["received", "sent"]
    # Reçu : un participant (obligatoire en groupe ; par défaut le contact).
    # Envoyé : toujours l'utilisateur confirmé (« Vous êtes »), ignoré ici.
    author: str | None = Field(None, max_length=200)
    content: str = Field(min_length=1, max_length=8000)
    sent_at: datetime | None = Field(None, description="Heure locale du message si connue ; jamais inventée")
    sent_at_raw: str = Field("", max_length=100)

    _locale = field_validator("sent_at")(_date_locale)


class AddMessagesRequest(BaseModel):
    messages: list[ManualMessageIn] = Field(min_length=1, max_length=50)
    # Doublons signalés (409 « correspondances ») confirmés par l'utilisateur.
    confirm_duplicates: bool = False


class UpdateManualMessage(BaseModel):
    content: str | None = Field(None, min_length=1, max_length=8000)
    author: str | None = Field(None, max_length=200)
    sent_at: datetime | None = None
    sent_at_raw: str | None = Field(None, max_length=100)
    clear_date: bool = False

    _locale = field_validator("sent_at")(_date_locale)


class ContextMessagesPage(BaseModel):
    context_id: UUID
    messages: list[ContextMessageOut]
    next_after: int | None = Field(
        description="Rang à passer en `after` pour la page suivante ; null : fin"
    )
