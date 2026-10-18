"""Validation stricte des arguments d'un outil (sous-ensemble de JSON
Schema, sans dépendance) : types, champs obligatoires, champs inconnus
refusés, énumérations, bornes de longueur et de valeur, éléments de liste.

Tout ce que le schéma ne décrit pas est refusé : un modèle (ou un contenu
injecté) ne peut pas glisser un argument supplémentaire (`user_id`…).
"""

from __future__ import annotations

from typing import Any

_TYPES = {
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "array": list,
    "object": dict,
}

MOTS_CONNUS = {
    "type", "properties", "required", "additionalProperties", "enum", "minLength", "maxLength",
    "minimum", "maximum", "items", "maxItems", "minItems", "description", "default", "pattern",
}


def _type_ok(valeur: Any, attendu: str) -> bool:
    if attendu in ("integer", "number") and isinstance(valeur, bool):
        return False                      # True n'est pas un nombre
    return isinstance(valeur, _TYPES[attendu])


def verifier_schema(schema: dict[str, Any], chemin: str = "arguments") -> None:
    """Schéma utilisable par [valider] (erreur de programmation sinon)."""
    if not isinstance(schema, dict):
        raise ValueError(f"{chemin} : schéma attendu")
    inconnus = set(schema) - MOTS_CONNUS
    if inconnus:
        raise ValueError(f"{chemin} : mots-clés non pris en charge {sorted(inconnus)}")
    if schema.get("type") not in _TYPES:
        raise ValueError(f"{chemin} : type manquant ou inconnu")
    if schema["type"] == "object":
        for nom, sous in (schema.get("properties") or {}).items():
            verifier_schema(sous, f"{chemin}.{nom}")
        for nom in schema.get("required") or ():
            if nom not in (schema.get("properties") or {}):
                raise ValueError(f"{chemin} : champ obligatoire non décrit {nom!r}")
    if schema["type"] == "array" and "items" in schema:
        verifier_schema(schema["items"], f"{chemin}[]")


def valider(schema: dict[str, Any], valeur: Any, chemin: str = "arguments") -> list[str]:
    """Erreurs de [valeur] contre [schema] (liste vide : valide)."""
    erreurs: list[str] = []
    attendu = schema.get("type")
    if attendu and not _type_ok(valeur, attendu):
        return [f"{chemin} : {attendu} attendu"]
    if "enum" in schema and valeur not in schema["enum"]:
        erreurs.append(f"{chemin} : valeur non autorisée")
    if isinstance(valeur, str):
        if "minLength" in schema and len(valeur) < schema["minLength"]:
            erreurs.append(f"{chemin} : trop court")
        if "maxLength" in schema and len(valeur) > schema["maxLength"]:
            erreurs.append(f"{chemin} : trop long (au plus {schema['maxLength']} caractères)")
    if isinstance(valeur, (int, float)) and not isinstance(valeur, bool):
        if "minimum" in schema and valeur < schema["minimum"]:
            erreurs.append(f"{chemin} : au moins {schema['minimum']}")
        if "maximum" in schema and valeur > schema["maximum"]:
            erreurs.append(f"{chemin} : au plus {schema['maximum']}")
    if isinstance(valeur, list):
        if "maxItems" in schema and len(valeur) > schema["maxItems"]:
            erreurs.append(f"{chemin} : au plus {schema['maxItems']} éléments")
        if "minItems" in schema and len(valeur) < schema["minItems"]:
            erreurs.append(f"{chemin} : au moins {schema['minItems']} éléments")
        if "items" in schema:
            for i, v in enumerate(valeur):
                erreurs += valider(schema["items"], v, f"{chemin}[{i}]")
    if isinstance(valeur, dict):
        proprietes = schema.get("properties") or {}
        for nom in schema.get("required") or ():
            if nom not in valeur:
                erreurs.append(f"{chemin}.{nom} : obligatoire")
        for nom, v in valeur.items():
            if nom not in proprietes:
                if schema.get("additionalProperties", False) is not True:
                    erreurs.append(f"{chemin}.{nom} : champ inconnu")
                continue
            erreurs += valider(proprietes[nom], v, f"{chemin}.{nom}")
    return erreurs
