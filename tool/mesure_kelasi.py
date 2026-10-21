"""Comparaison PIM/Kelasi sur S10+ (1440 x 3040), application en profile.

Lancer Flutter avec JARVIS_PERF=true, ouvrir l'accueil sans clavier/menu,
puis : python tool/mesure_kelasi.py <journal-flutter-run> <sortie.json>
Les positions correspondent au menu vérifié sur ce téléphone.
Aucun appel IA, aucune modification des données pédagogiques.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

adb = os.path.join(os.environ["LOCALAPPDATA"], "Android", "sdk",
                   "platform-tools", "adb.exe")
with open(sys.argv[1], encoding="utf-8", errors="ignore") as f:
    urls = re.findall(r"http://127\.0\.0\.1:\d+/[^ /]+=/", f.read())
url = urls[-1]


def rpc(method, **params):
    query = urllib.parse.urlencode(params)
    with urllib.request.urlopen(url + method + "?" + query, timeout=10) as r:
        answer = json.load(r)
    if "error" in answer:
        raise RuntimeError(answer["error"])
    return answer["result"]


isolate = next(i["id"] for i in rpc("getVM")["isolates"]
               if i["name"] == "main")


def chrono():
    return rpc("ext.jarvis.chrono", isolateId=isolate)


def input_phone(*args):
    subprocess.run([adb, "-s", "R58M84VKRXV", "shell", "input", *map(str, args)],
                   check=True, capture_output=True)


def rss():
    return rpc("getVM").get("_currentRSS")


results = {"device": "SM-G975F", "mode": "profile", "rss_debut": rss(),
           "mesures": []}
# Alternance dans la même compilation pour limiter le biais de température
# et de fréquence GPU. Le premier passage de chaque variante est conservé.
for tour in range(5):
    for suspendu in (False, True):
        rpc("ext.jarvis.variante", isolateId=isolate,
            sans="" if suspendu else "apprendre.pause,apprendre.transition",
            avec="")
        chrono()
        time.sleep(2)
        repos = chrono()
        input_phone("tap", 138, 225)
        time.sleep(1.3)
        chrono()
        input_phone("tap", 340, 813)
        time.sleep(1.5)
        ouverture = chrono()
        if "apprendre.affiche" not in ouverture:
            raise RuntimeError("Kelasi non observé : vérifier l'écran avant de continuer.")
        time.sleep(1)
        couvert = chrono()
        input_phone("keyevent", 4)
        time.sleep(1.5)
        retour = chrono()
        results["mesures"].append({
            "tour": tour + 1, "suspendu": suspendu, "repos": repos,
            "ouverture": ouverture, "couvert": couvert, "retour": retour,
            "rss": rss(),
        })
        with open(sys.argv[2], "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"Tour {tour + 1}, suspension={suspendu}", flush=True)
        time.sleep(1.5)
rpc("ext.jarvis.variante", isolateId=isolate, sans="", avec="")
results["rss_fin"] = rss()
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
