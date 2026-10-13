#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Synchronisation automatique de l'horloge Windows (poste de développement
  JARVIS : Docker Desktop + WSL2).

.DESCRIPTION
  Les jetons Supabase sont refusés par FastAPI si l'horloge de la machine
  dérive de plus de 10 s. Docker Desktop et WSL2 suivent l'horloge de
  Windows : c'est elle qu'il faut synchroniser (aucun NTP dans les
  conteneurs).

  Ce script, relançable sans risque :
    1. met le service Windows Time en démarrage automatique et le démarre ;
    2. configure trois sources NTP fiables ;
    3. fixe l'intervalle de synchronisation à 1 h ;
    4. ajoute une tâche planifiée qui resynchronise au démarrage et au
       réveil de veille (dérive fréquente après une mise en veille) ;
    5. force une resynchronisation immédiate et affiche l'état.

  À exécuter dans PowerShell ouvert en administrateur :
    powershell -ExecutionPolicy Bypass -File scripts\windows\synchroniser_horloge.ps1

  Vérification ensuite (sans droits administrateur) :
    powershell -ExecutionPolicy Bypass -File scripts\windows\verifier_horloge.ps1
#>

$ErrorActionPreference = 'Stop'
$sources = 'time.windows.com,0x9 time.cloudflare.com,0x9 pool.ntp.org,0x9'
$tache = 'JARVIS - Resynchroniser l''horloge'

Write-Host '1/5 Service Windows Time : démarrage automatique'
Set-Service -Name w32time -StartupType Automatic
if ((Get-Service w32time).Status -ne 'Running') { Start-Service w32time }

Write-Host '2/5 Sources de temps : time.windows.com, time.cloudflare.com, pool.ntp.org'
w32tm /config /manualpeerlist:$sources /syncfromflags:manual /reliable:no /update | Out-Null

Write-Host '3/5 Synchronisation toutes les heures'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' `
  -Name SpecialPollInterval -Value 3600
Restart-Service w32time

Write-Host '4/5 Resynchronisation au démarrage et au réveil de veille'
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\w32tm.exe" -Argument '/resync /force'
$auDemarrage = New-ScheduledTaskTrigger -AtStartup
# Événement 1 de Power-Troubleshooter : « le système a quitté un état de veille ».
$reveil = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler |
  New-CimInstance -ClientOnly
$reveil.Enabled = $true
$reveil.Subscription = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>
'@
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$reglages = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $tache -Action $action -Trigger @($auDemarrage, $reveil) `
  -Principal $principal -Settings $reglages -Force | Out-Null

Write-Host '5/5 Resynchronisation immédiate'
Start-Sleep -Seconds 2
w32tm /resync /force
Write-Host ''
w32tm /query /status
Write-Host ''
Write-Host 'Terminé. Docker Desktop (WSL2) suit l''horloge de Windows ; vérifiez avec verifier_horloge.ps1.'
