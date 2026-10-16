"""Moteur de compréhension conversationnelle (phase 1).

Ce n'est pas un modèle de langage : il prépare, pour le fournisseur IA déjà
branché (GroqCloud, via le client du chat), les instructions et les extraits
des conversations WhatsApp jointes à un chat JARVIS.

  reperes.py        ce que vise la question (période, début / fin, mots)
  extraits.py       messages chargés, mise en forme, aperçu, sélection
                    sous budget de tokens
  instructions.py   instructions internes (analyse du discours, second
                    degré, faits / indices / hypothèses, anti-injection)
  moteur.py         orchestration : contextes du chat, consentement,
                    messages envoyés au modèle

Rien ici n'appelle l'IA ni n'écrit en base.
"""
