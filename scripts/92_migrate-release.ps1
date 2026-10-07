#Requires -Version 5.1
<#
=========================================================================
 92_migrate-release.ps1 — migre un dossier de travail vers une nouvelle
 release, en épinglant l'identité MSI. Vit dans scripts\ ; s'exécute depuis
 n'importe où (les deux dossiers sont passés en paramètres).

 POURQUOI : une release ne contient jamais votre configuration. Migrer, c'est
 repartir du code neuf, y remettre ce qui vous appartient, puis reconstruire.
 Le seul point délicat est l'identité du paquet : l'UpgradeCode doit rester
 CELUI DE LA PRODUCTION (sinon la nouvelle version s'installe à côté de
 l'ancienne). Ce script le relève dans votre dossier actuel et l'inscrit dans
 branding.conf, où la chaîne le réappliquera désormais à chaque build.

 Après cette migration, les mises à jour suivantes se résument à : récupérer
 la release, relancer ce script, monter la version, construire.

 UTILISATION (depuis la racine du dossier NEUF, par exemple)
   .\scripts\92_migrate-release.ps1 -Ancien C:\...\ancien -Nouveau C:\...\neuf
   .\scripts\92_migrate-release.ps1 -Ancien ... -Nouveau ... -Simulation   # n'écrit rien
   .\scripts\92_migrate-release.ps1 -Ancien ... -Nouveau ... -Version 1.7.0.0
   .\scripts\92_migrate-release.ps1 -Ancien ... -Nouveau ... -Icone Risks

 CE QU'IL FAIT, DANS CET ORDRE
   1. contrôle que le dossier neuf est bien une release qui gère l'identité MSI
   2. relève UpgradeCode / ProductCode / VERSION dans le dossier actuel
   3. recopie vos fichiers (branding.conf, certs, installers, deploy.env)
   4. inscrit UPGRADE_CODE, REGEN_PRODUCTCODE et la nouvelle VERSION
   5. relit le résultat et signale les nouveaux réglages de la release

 Le dossier ACTUEL n'est jamais modifié : il reste votre retour arrière.
=========================================================================
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Ancien,
  [Parameter(Mandatory=$true)][string]$Nouveau,
  [string]$Version = "",
  [string]$UpgradeCode = "",
  [string]$Icone = "",
  [switch]$Simulation
)

$ErrorActionPreference = 'Stop'

function Titre($t) { Write-Host ""; Write-Host "== $t ==" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [ok]   $t" -ForegroundColor Green }
function Inf($t)   { Write-Host "  [--]   $t" -ForegroundColor DarkGray }
function Att($t)   { Write-Host "  [??]   $t" -ForegroundColor Yellow }
function Err($t)   { Write-Host "  [!!]   $t" -ForegroundColor Red }
function Detail($t){ Write-Host "         $t" }
function Arret($t) { Err $t; Write-Host ""; exit 1 }

# Lecture/écriture en UTF-8 SANS BOM : les scripts shell de la chaîne lisent
# branding.conf ligne à ligne, un BOM casserait la toute première clé.
function Lire($p)      { [System.IO.File]::ReadAllText($p) }
function Ecrire($p,$c) { [System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($false))) }

function ValeurCle($contenu, $cle) {
  $m = [regex]::Match($contenu, '(?m)^\s*' + [regex]::Escape($cle) + '\s*=\s*"?([^"\r\n]*)"?\s*$')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return ""
}

# ------------------------------------------------------------ 1. CONTRÔLES
# Tout est validé AVANT la moindre écriture : au moindre doute, on n'écrit rien.
Titre "CONTRÔLES PRÉALABLES"

if (-not (Test-Path -LiteralPath $Ancien -PathType Container)) { Arret "Dossier actuel introuvable : $Ancien" }
if (-not (Test-Path -LiteralPath $Nouveau -PathType Container)) { Arret "Dossier de la nouvelle release introuvable : $Nouveau" }

$Ancien  = (Resolve-Path -LiteralPath $Ancien).Path
$Nouveau = (Resolve-Path -LiteralPath $Nouveau).Path
if ($Ancien -eq $Nouveau) { Arret "Les deux dossiers sont identiques : la migration se fait TOUJOURS vers un dossier neuf." }

$brandAncien = Join-Path $Ancien "branding.conf"
$vdprojAncien = Join-Path $Ancien "setup\Setup.vdproj"
if (-not (Test-Path -LiteralPath $brandAncien)) { Arret "branding.conf absent du dossier actuel : $brandAncien" }
Ok "Dossier actuel : $Ancien"

$exemple = Join-Path $Nouveau "branding.conf.example"
$custom  = Join-Path $Nouveau "scripts\02_customize.sh"
if (-not (Test-Path -LiteralPath $exemple)) { Arret "Le dossier neuf n'est pas une release BoutonSPAM (branding.conf.example absent)." }
if (-not (Test-Path -LiteralPath $custom))  { Arret "Le dossier neuf n'est pas une release BoutonSPAM (scripts\02_customize.sh absent)." }

$contenuExemple = Lire $exemple
if ($contenuExemple -notmatch 'UPGRADE_CODE') {
  Err "Cette release ne gère pas encore l'identité MSI (v1.6.1 ou antérieure)."
  Detail "Récupérez la v1.6.2 ou une version plus récente : c'est elle qui rend"
  Detail "les mises à jour suivantes automatiques. Migration interrompue."
  Write-Host ""; exit 1
}
Ok "Dossier neuf : $Nouveau (release gérant l'identité MSI)"

if (Test-Path -LiteralPath (Join-Path $Nouveau "branding.conf")) {
  Att "Un branding.conf existe déjà dans le dossier neuf : il va être REMPLACÉ par le vôtre."
}

# ------------------------------------------------- 2. IDENTITÉ DE LA PRODUCTION
Titre "IDENTITÉ DE VOTRE PRODUCTION"

$contenuAncien = Lire $brandAncien
$versionAncienne = ValeurCle $contenuAncien "VERSION"
if (-not $versionAncienne) { Arret "VERSION introuvable dans $brandAncien" }
Inf "VERSION actuelle : $versionAncienne"

# L'UpgradeCode vient, par ordre de confiance : paramètre explicite, puis
# branding.conf (migrations suivantes), puis le projet d'installation (1re fois).
$uc = ""
$origineUc = ""
if ($UpgradeCode) {
  $uc = $UpgradeCode; $origineUc = "paramètre -UpgradeCode"
} else {
  $ucBrand = ValeurCle $contenuAncien "UPGRADE_CODE"
  if ($ucBrand) {
    $uc = $ucBrand; $origineUc = "branding.conf actuel (déjà épinglé)"
  } elseif (Test-Path -LiteralPath $vdprojAncien) {
    $v = Lire $vdprojAncien
    $m = [regex]::Match($v, '"UpgradeCode"\s*=\s*"8:\{([0-9A-Fa-f\-]+)\}"')
    if ($m.Success) { $uc = $m.Groups[1].Value; $origineUc = "setup\Setup.vdproj du dossier actuel" }
    $mp = [regex]::Match($v, '"ProductCode"\s*=\s*"8:\{([0-9A-Fa-f\-]+)\}"')
    if ($mp.Success) { Inf "ProductCode actuel : {$($mp.Groups[1].Value.ToUpper())}  (il sera renouvelé au build)" }
  }
}

$uc = $uc -replace '[{}\s]', ''
if ($uc -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') {
  Err "UpgradeCode introuvable ou invalide dans le dossier actuel."
  Detail "C'est LA valeur qui doit rester identique à celle de votre production :"
  Detail "sans elle, la nouvelle version s'installerait à côté de l'ancienne."
  Detail "Relevez-la sur un poste déployé et passez-la en paramètre :"
  Detail "  -UpgradeCode '{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}'"
  Write-Host ""; exit 1
}
$uc = $uc.ToUpper()
Ok "UpgradeCode retenu : {$uc}"
Detail "source : $origineUc"

# ------------------------------------------------------------- 3. VERSION
Titre "VERSION À PRODUIRE"

try { $vA = [version]$versionAncienne } catch { Arret "VERSION actuelle illisible : $versionAncienne" }
if (-not $Version) {
  $Version = "{0}.{1}.0.0" -f $vA.Major, ($vA.Minor + 1)
  Inf "Aucune version demandée : proposition automatique."
}
try { $vN = [version]$Version } catch { Arret "Version demandée invalide : $Version (attendu x.y.z.w)" }
if ($vN -le $vA) {
  Arret "La version demandée ($Version) n'est pas supérieure à l'actuelle ($versionAncienne). Une version ne diminue jamais."
}
Ok "Nouvelle VERSION : $Version   (précédente : $versionAncienne)"

# ------------------------------------------ 4. PLAN DE COPIE DE VOS FICHIERS
Titre "VOS FICHIERS À REMETTRE EN PLACE"

$aCopier = @()
$aCopier += @{ Src = $brandAncien; Dst = (Join-Path $Nouveau "branding.conf"); Nom = "branding.conf"; Type = "fichier" }
# tools\ (signtool, python) n'est pas versionne : sans lui, le build echoue a
# l'etape de SIGNATURE, et un poste isole ne peut rien re-telecharger.
foreach ($d in @("certs", "installers", "tools")) {
  $s = Join-Path $Ancien $d
  if (Test-Path -LiteralPath $s -PathType Container) {
    $n = (Get-ChildItem -LiteralPath $s -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    $aCopier += @{ Src = $s; Dst = (Join-Path $Nouveau $d); Nom = "$d\ ($n fichier(s))"; Type = "dossier" }
  } else { Inf "$d\ : absent du dossier actuel, rien à copier" }
}
$env1 = Join-Path $Ancien "webaddin\deploy\deploy.env"
if (Test-Path -LiteralPath $env1) {
  $aCopier += @{ Src = $env1; Dst = (Join-Path $Nouveau "webaddin\deploy\deploy.env"); Nom = "webaddin\deploy\deploy.env"; Type = "fichier" }
} else { Inf "webaddin\deploy\deploy.env : absent, rien à copier" }
foreach ($e in $aCopier) { Inf "à reprendre : $($e.Nom)" }

# ------------------------------------------- 5. NOUVEAU branding.conf (mémoire)
# On construit d'abord le contenu complet, on n'écrit qu'ensuite.
$nl = "`n"; if ($contenuAncien -match "`r`n") { $nl = "`r`n" }
$lignes = [System.Collections.ArrayList]@()
foreach ($l in ($contenuAncien -split "`r?`n")) { [void]$lignes.Add($l) }

$aDefinir = [ordered]@{
  "VERSION"           = '"' + $Version + '"'
  "UPGRADE_CODE"      = '"{' + $uc + '}"'
  "REGEN_PRODUCTCODE" = '0'
  "REGEN_GUIDS"       = '0'
}
if ($Icone) { $aDefinir["BUTTON_ICON"] = '"' + $Icone + '"' }

$ajoutees = @()
foreach ($cle in $aDefinir.Keys) {
  $motif = '^\s*' + [regex]::Escape($cle) + '\s*='
  $trouve = $false
  for ($i = 0; $i -lt $lignes.Count; $i++) {
    if (-not $trouve -and $lignes[$i] -match $motif) {
      $lignes[$i] = "$cle=$($aDefinir[$cle])"
      $trouve = $true
    }
  }
  if (-not $trouve) { $ajoutees += $cle }
}
if ($ajoutees.Count -gt 0) {
  [void]$lignes.Add("")
  [void]$lignes.Add("# ---- Identité MSI - ajoutée par migrer-boutonspam.ps1 le $(Get-Date -Format 'yyyy-MM-dd') ----")
  [void]$lignes.Add("# UPGRADE_CODE identifie la FAMILLE du produit : posé une fois, jamais modifié.")
  [void]$lignes.Add("# Le ProductCode, lui, est régénéré automatiquement à chaque montée de VERSION.")
  foreach ($cle in $ajoutees) { [void]$lignes.Add("$cle=$($aDefinir[$cle])") }
}
$nouveauContenu = ($lignes -join $nl)

# ------------------------------------------------------------- 6. EXÉCUTION
Titre "APPLICATION"

if ($Simulation) {
  Att "Mode simulation : RIEN n'est écrit."
  foreach ($e in $aCopier) { Detail "copierait $($e.Nom)  ->  $($e.Dst)" }
  Detail "écrirait branding.conf avec VERSION=$Version et UPGRADE_CODE={$uc}"
  if ($ajoutees.Count -gt 0) { Detail "clés ajoutées : $($ajoutees -join ', ')" }
  Write-Host ""
  exit 0
}

foreach ($e in $aCopier) {
  if ($e.Type -eq "dossier") {
    New-Item -ItemType Directory -Force -Path $e.Dst | Out-Null
    # on énumère le contenu plutôt que d'utiliser un joker : un dossier vide
    # ne doit pas faire échouer la migration, et rien ne doit s'imbriquer.
    $items = @(Get-ChildItem -LiteralPath $e.Src -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) {
      Copy-Item -Path $items.FullName -Destination $e.Dst -Recurse -Force
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $e.Dst) | Out-Null
    Copy-Item -LiteralPath $e.Src -Destination $e.Dst -Force
  }
  Ok "repris : $($e.Nom)"
}

Ecrire (Join-Path $Nouveau "branding.conf") $nouveauContenu
Ok "branding.conf écrit (UTF-8 sans BOM)"

# ------------------------------------------------------------ 7. VÉRIFICATION
Titre "VÉRIFICATION"

$relu = Lire (Join-Path $Nouveau "branding.conf")
$okTout = $true
$attendu = @{ "VERSION" = $Version; "UPGRADE_CODE" = "{$uc}"; "REGEN_PRODUCTCODE" = "0"; "REGEN_GUIDS" = "0" }
foreach ($cle in $attendu.Keys) {
  $v = ValeurCle $relu $cle
  if ($v -eq $attendu[$cle]) { Ok "$cle = $v" } else { Err "$cle = '$v' (attendu '$($attendu[$cle])')"; $okTout = $false }
}
$octets = [System.IO.File]::ReadAllBytes((Join-Path $Nouveau "branding.conf"))
if ($octets.Length -ge 3 -and $octets[0] -eq 0xEF -and $octets[1] -eq 0xBB -and $octets[2] -eq 0xBF) {
  Err "Un BOM UTF-8 est présent : la chaîne shell ne lirait pas la première clé."; $okTout = $false
} else { Ok "Aucun BOM : le fichier est lisible par la chaîne de personnalisation." }

# Réglages apparus dans la release et absents de votre configuration
$clesEx = [regex]::Matches($contenuExemple, '(?m)^\s*([A-Z_]+)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$clesMoi = [regex]::Matches($relu,          '(?m)^\s*([A-Z_]+)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$nouvelles = $clesEx | Where-Object { $clesMoi -notcontains $_ }
if ($nouvelles) {
  Att "Réglages proposés par cette release et absents de votre configuration :"
  foreach ($n in $nouvelles) { Detail "$n   (voir son commentaire dans branding.conf.example)" }
  Detail "Une clé absente n'est jamais une erreur : la valeur par défaut s'applique."
} else {
  Inf "Aucun nouveau réglage à adopter."
}

Titre "SUITE"
if ($okTout) {
  Ok "Dossier prêt : $Nouveau"
  Detail "1. PowerShell à la racine de ce dossier, Visual Studio fermé :"
  Detail "     .\scripts\05_assistant.ps1     (guidé)   ou   .\scripts\04_build.ps1"
  Detail "2. Au build, le journal doit afficher :"
  Detail "     UpgradeCode épinglé : {$uc}"
  Detail "     ProductCode régénéré : {...}   -> mise à niveau majeure"
  Detail "3. Poste pilote disposant de l'ancienne version : UNE seule entrée"
  Detail "   dans " Programmes et fonctionnalités ", au numéro $Version."
  Detail ""
  Detail "Le dossier actuel n'a pas été touché : il reste votre retour arrière."
} else {
  Err "Des contrôles ont échoué : corrigez avant de construire."
  Write-Host ""; exit 1
}
Write-Host ""
