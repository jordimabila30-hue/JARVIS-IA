<#
.SYNOPSIS
  Diagnostic de l'horloge (lecture seule) : Windows, VM WSL2 de Docker
  Desktop et conteneur jarvis-api, comparés à une référence fiable.

.DESCRIPTION
  Ne modifie rien. À lancer après une mise en veille, un redémarrage ou
  si JARVIS affiche « Token invalide » :
    powershell -ExecutionPolicy Bypass -File scripts\windows\verifier_horloge.ps1

  Référence : l'en-tête HTTP Date de Cloudflare et de Supabase (précision
  d'environ 1 s, suffisante face à la tolérance de 10 s des jetons).
#>

$seuil = 5        # secondes : alerte
$tolerance = 10   # secondes : tolérance des jetons JWT (backend)

function Heure-Reference([string]$url) {
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10
    return [DateTimeOffset]::Parse($r.Headers['Date']).ToUnixTimeMilliseconds() / 1000.0 + 0.5
  } catch {
    if ($_.Exception.Response) {
      # Même une réponse d'erreur (401…) porte l'en-tête Date.
      return [DateTimeOffset]::Parse($_.Exception.Response.Headers['Date']).ToUnixTimeMilliseconds() / 1000.0 + 0.5
    }
    return $null
  }
}

function Ecrire-Ecart([string]$nom, $ecart) {
  if ($null -eq $ecart) { Write-Host ("  {0,-22} : non mesurable" -f $nom); return }
  $etat = if ([math]::Abs($ecart) -gt $tolerance) { 'CRITIQUE (jetons refusés)' }
          elseif ([math]::Abs($ecart) -gt $seuil) { 'décalé' } else { 'ok' }
  Write-Host ("  {0,-22} : {1,8:+0.0;-0.0} s  {2}" -f $nom, $ecart, $etat)
}

Write-Host 'Service Windows Time'
$svc = Get-Service w32time
Write-Host ("  état : {0}, démarrage : {1}" -f $svc.Status, $svc.StartType)
$type = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters').Type
Write-Host ("  mode : {0}" -f $type)
if ($svc.Status -eq 'Running') {
  w32tm /query /status 2>$null | Select-String 'Source|Dernière|Last Successful|Stratum' |
    ForEach-Object { Write-Host ('  ' + $_.Line.Trim()) }
}
if ($type -eq 'NoSync' -or $svc.StartType -eq 'Disabled') {
  Write-Host '  -> Synchronisation désactivée : lancez synchroniser_horloge.ps1 en administrateur.'
}

Write-Host ''
Write-Host 'Écart avec l''heure réelle (référence - horloge locale ; positif = en retard)'
$ref = Heure-Reference 'https://www.cloudflare.com'
if ($null -eq $ref) { Write-Host '  Référence injoignable (réseau ?).'; exit 1 }
$t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
Ecrire-Ecart 'Windows' ($ref - $t)

$vm = (wsl -d docker-desktop date -u +%s 2>$null) -replace "`0", ''
if ($vm -match '^\d+') { Ecrire-Ecart 'VM WSL2 docker-desktop' ($ref - [double]$Matches[0] - 0.5) }
else { Ecrire-Ecart 'VM WSL2 docker-desktop' $null }

$c = docker exec jarvis-api python -c "import time;print(time.time())" 2>$null
if ($c) { Ecrire-Ecart 'conteneur jarvis-api' ($ref - [double]$c) }
else { Ecrire-Ecart 'conteneur jarvis-api' $null }

Write-Host ''
Write-Host 'Diagnostic du backend (GET /health/clock) :'
try {
  $h = Invoke-RestMethod -Uri 'http://localhost:8000/health/clock' -TimeoutSec 5
  Write-Host ("  état : {0}, écart : {1} s (mesuré le {2})" -f $h.status, $h.ecart_secondes, $h.mesure_le)
} catch {
  if ($_.Exception.Response.StatusCode.value__ -eq 503) {
    Write-Host '  état : critique (503) - voir docker logs jarvis-api'
  } else { Write-Host '  backend injoignable' }
}
