"""Images jointes au chat (capture de JARVIS Touch) : contrôle, envoi au
seul fournisseur qui lit les images, jamais en base, gardée pour la suite.

Image FICTIVE (PNG 2 × 2 généré ici) : aucune capture réelle.
"""

import base64
import json
import struct
import zlib

import pytest

from app import vision
from app.llm.anthropic import convertir
from faux_llm import ServeurClaude
from test_chat import USER, env, fournisseur_test, post_chat  # noqa: F401
from test_mia_chat import evenements, texte


def png(largeur: int = 2, hauteur: int = 2) -> bytes:
    def bloc(nom: bytes, donnees: bytes) -> bytes:
        return struct.pack(">I", len(donnees)) + nom + donnees + struct.pack(">I", zlib.crc32(nom + donnees))
    ihdr = struct.pack(">IIBBBBB", largeur, hauteur, 8, 2, 0, 0, 0)
    pixels = zlib.compress(b"".join(b"\x00" + b"\xff\x00\x00" * largeur for _ in range(hauteur)))
    return b"\x89PNG\r\n\x1a\n" + bloc(b"IHDR", ihdr) + bloc(b"IDAT", pixels) + bloc(b"IEND", b"")


def image(octets: bytes | None = None, media_type: str = "image/png") -> dict:
    return {"media_type": media_type, "data": base64.b64encode(octets or png()).decode()}


# --- Contrôle ------------------------------------------------------------------

def test_image_valide():
    assert vision.verifier(vision.ImageJointe(**image())) == len(png())


@pytest.mark.parametrize("donnees,message", [
    (image(media_type="image/jpeg"), "format"),                     # type annoncé ≠ octets
    ({"media_type": "image/png", "data": "pas du base64 !!!!"}, "illisible"),
    (image(b"GIF89a" + b"\x00" * 30), "format"),
    (image(png(9000, 10)), "trop grande"),
])
def test_image_refusee(donnees, message):
    with pytest.raises(vision.ImageInvalide, match=message):
        vision.verifier(vision.ImageJointe(**donnees))


def test_convertir_claude_image_avant_le_texte():
    _, tours = convertir([{"role": "user", "content": "Explique.", "images": [
        {"media_type": "image/png", "data": "QUJD"}]}])
    assert tours == [{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "QUJD"}},
        {"type": "text", "text": "Explique."},
    ]}]


# --- Route du chat -----------------------------------------------------------------

async def test_fournisseur_sans_vision_refuse_avant_tout_appel(env):
    resp = await post_chat(env, message="Que vois-tu ?", image=image())     # faux GroqCloud : texte seul
    assert resp.status_code == 403
    assert resp.json()["detail"]["code"] == "vision_offre"
    assert env.supa.inserted == []
    assert env.llm.calls == []


async def test_image_invalide_422(env):
    env.llm = ServeurClaude().fournisseur()
    resp = await post_chat(env, message="Q", image=image(b"pas une image du tout"))
    assert resp.status_code == 422 and resp.json()["detail"]["code"] == "image_invalide"
    assert env.supa.inserted == []


async def test_image_envoyee_a_claude_jamais_enregistree(env):
    serveur = ServeurClaude()
    env.llm = serveur.fournisseur()
    joint = image()
    events = evenements((await post_chat(env, message="Explique cet exercice.", image=joint)).text)
    assert events[-1][0] == "done" and texte(events) == "Bonjour Tony."

    [req] = serveur.requetes
    assert req["messages"][-1]["content"][0] == {
        "type": "image", "source": {"type": "base64", **joint}}
    question, reponse = env.supa.inserted
    assert question["content"] == "Explique cet exercice."
    [piece] = question["attachments"]
    assert piece["type"] == "capture_ecran" and piece["octets"] == len(png())
    assert joint["data"] not in json.dumps(env.supa.inserted)               # jamais les octets en base
    assert reponse["role"] == "assistant"


async def test_question_suivante_sur_la_meme_image(env):
    serveur = ServeurClaude()
    env.llm = serveur.fournisseur()
    joint = image()
    meta = evenements((await post_chat(env, message="Qu'est-ce ?", image=joint)).text)[0][1]
    cid = meta["conversation_id"]
    connue = env.supa.get_conversation

    async def get_conversation(c, uid):
        return {"id": c, "title": "Qu'est-ce ?", "persona": None} if c == cid else await connue(c, uid)

    env.supa.get_conversation = get_conversation
    await post_chat(env, message="Et la deuxième ligne ?", conversation_id=cid)
    suite = serveur.requetes[1]["messages"]
    assert suite[0]["content"][0]["type"] == "image"                         # l'image reste dans le contexte
    assert suite[-1]["content"] == [{"type": "text", "text": "Et la deuxième ligne ?"}]

    # Contexte expiré : l'image n'est plus envoyée, le modèle en est prévenu.
    await env.redis.delete(f"chat:image:{cid}")
    await post_chat(env, message="Et la troisième ?", conversation_id=cid)
    troisieme = serveur.requetes[2]["messages"]
    assert all(b["type"] == "text" for t in troisieme for b in t["content"])
    assert vision.NOTE_IMAGE_EXPIREE in troisieme[0]["content"][0]["text"]
