"""Essai manuel (appel RÉEL, facturé) : Claude lit-il une image via MIA ?
Image FICTIVE générée ici (carré rouge sur fond blanc), jamais une capture.

    docker run --rm --name jarvis-essai-vision --env-file backend/.env \
      -v "<dépôt>:/repo" -w /repo/backend backend-api python -m tests.essai_vision_reel
"""

import asyncio
import base64

from app.config import get_settings
from app.llm import selection


def carre_rouge() -> bytes:
    # 64 × 64 : blanc, carré rouge au centre (PNG brut, sans dépendance).
    import struct
    import zlib
    lignes = []
    for y in range(64):
        ligne = b"".join(b"\xff\x00\x00" if 16 <= x < 48 and 16 <= y < 48 else b"\xff\xff\xff" for x in range(64))
        lignes.append(b"\x00" + ligne)

    def bloc(nom, d):
        return struct.pack(">I", len(d)) + nom + d + struct.pack(">I", zlib.crc32(nom + d))
    return (b"\x89PNG\r\n\x1a\n" + bloc(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0))
            + bloc(b"IDAT", zlib.compress(b"".join(lignes))) + bloc(b"IEND", b""))


async def main() -> None:
    llm = selection.fournisseur("anthropic", get_settings())
    print("fournisseur :", llm.nom, llm.modele, "vision :", llm.vision)
    messages = [{"role": "user", "content": "De quelle couleur est le carré au centre ? Un seul mot.",
                 "images": [{"media_type": "image/png", "data": base64.b64encode(carre_rouge()).decode()}]}]
    texte = []
    async for ev in llm.flux(messages, max_sortie=2000):
        if hasattr(ev, "texte"):
            texte.append(ev.texte)
        else:
            print("fin :", getattr(ev, "raison", None), getattr(ev, "modele", None), getattr(ev, "usage", None))
    print("réponse :", "".join(texte))


asyncio.run(main())
