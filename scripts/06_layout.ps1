# ============================================================================
#  06_layout.ps1 - VERIFIE (et, en ligne, COMPLETE) le layout Visual Studio
#  hors ligne DANS le repertoire du projet, pret a copier sur un poste offline.
#
#  BUT : ne plus JAMAIS decouvrir au moment du build qu'il manque une charge.
#  Ce script verifie la PRESENCE REELLE des paquets requis (charge Office,
#  charge .NET desktop, pack de ciblage 4.8), leur VERSION et la TAILLE du
#  layout AVANT toute installation. Si le layout est INCOMPLET et que le poste
#  est EN LIGNE (-Download), il telecharge le manquant DIRECTEMENT dans le
#  layout du projet (operation REPRENABLE : une relance ne reprend que le reste).
#
#  Emplacement du layout : installers\vslayout\ (dans le projet). Il est EXCLU
#  de l'archive (00_make-archive.sh) et de git (installers/*), mais present pour
#  etre copie tel quel vers l'environnement hors ligne.
#
#  Usage (PowerShell, a la racine du projet) :
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1                 # VERIFIE seulement (lecture seule)
#     powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download        # verifie PUIS, si EN LIGNE et
#                                              #   incomplet, telecharge le manquant
#     powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -LayoutDir D:\vslayout    # autre emplacement
#     powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download -Lang en-US     # autre langue
#
#  Apres un -Download termine (code 0) : copiez installers\vslayout\ sur le
#  poste hors ligne, puis la-bas :
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup -LayoutPath <dossier copie>
#
#  Journalise dans logs\layout-*.log.
# ============================================================================
param(
  [string]$LayoutDir,           # emplacement du layout (defaut : <projet>\installers\vslayout)
  [switch]$Download,            # EN LIGNE : telecharge le manquant DANS le layout
  [string]$Lang = "fr-FR",      # langue du layout
  [double]$MinSizeGB = 3.5,     # en dessous : layout probablement incomplet (avertissement). Un layout --includeRecommended de ces charges pese ~4 Go ; --includeOptional bien plus.
  [switch]$Fresh                # met de cote un layout PARTIEL avant de retelecharger (repart propre)
)
$ErrorActionPreference = "Stop"

# RACINE du projet = dossier PARENT de scripts\ (ou vit ce script)
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ROOT "branding.conf"))) { $ROOT = $PSScriptRoot }
if (-not $LayoutDir) { $LayoutDir = Join-Path $ROOT "installers\vslayout" }

# --- Charges/paquets REQUIS pour COMPILER et EXECUTER BoutonSPAM (VSTO) ------
#   L'extension "Installer Projects" (VSInstallerProjects2022) N'est PAS un
#   composant de layout : c'est un .vsix (voir 01_verification-poste.ps1).
# CHARGES a AJOUTER quand on TELECHARGE le layout (--add). Ce sont des META-paquets
# (workloads / composants) SANS charge utile propre : ils ne creent PAS de dossier
# dans le layout, ils sont decrits dans le CATALOGUE (ChannelManifest/Catalog.json)
# et tirent leurs COMPOSANTS. => Ne JAMAIS verifier leur presence par un dossier.
$ADD_WORKLOADS = @(
  "Microsoft.VisualStudio.Workload.Office",
  "Microsoft.VisualStudio.Workload.ManagedDesktop",
  "Microsoft.Net.Component.4.8.TargetingPack"
)

# PAQUETS a VERIFIER dans le layout : les vraies CHARGES UTILES (= dossiers presents)
# qui prouvent que le layout peut COMPILER BoutonSPAM (add-in VB.NET / VSTO) hors ligne.
# On verifie les COMPOSANTS concrets, pas les workloads (qui n'ont pas de dossier).
# IDs confirmes dans un layout reel (dd_setup) : Vsto.Runtime, Net.4.8.TargetingPack,
# CodeAnalysis.Compilers (Roslyn C#/VB), Templates.VB.ManagedCore.
$REQUIRED = @(
  @{ Id = "Microsoft.Net.4.8.TargetingPack";                 Label = "Pack de ciblage .NET Framework 4.8" },
  @{ Id = "Microsoft.VisualStudio.Vsto.Runtime";            Label = "Runtime VSTO (add-in Office)" },
  @{ Id = "Microsoft.CodeAnalysis.Compilers";               Label = "Compilateurs C#/VB (Roslyn)" },
  @{ Id = "Microsoft.VisualStudio.Templates.VB.ManagedCore"; Label = "Modeles de projet VB.NET" }
)

# --- Affichage colore : ROUGE=requis et ABSENT  ORANGE=avertissement  VERT=OK -
# NB: nom DISTINCTIF ($LogLines, pas $R) : PowerShell est INSENSIBLE A LA CASSE,
# un 'foreach ($r in ...)' au niveau du script ecraserait un accumulateur nomme $R
# (bug corrige : $R devenait la derniere entree de $REQUIRED puis $R.Add plantait).
$LogLines = New-Object System.Collections.Generic.List[string]
function L([string]$s){
  $LogLines.Add($s)
  $u = $s.ToUpper()
  if ($u -match 'AVERTISSEMENT' -or $u -match 'SECURITE' -or $u -match 'HORS LIGNE' -or $u -match 'ATTENTION') { Write-Host $s -ForegroundColor Yellow; return }
  if ($u -match 'ABSENT' -or $u -match 'MANQUANT' -or $u -match 'INTROUVABLE' -or $u -match 'INCOMPLET' -or $u -match 'ECHEC' -or $u -match 'ERREUR') { Write-Host $s -ForegroundColor Red; return }
  if ($u -match 'PRESENT' -or $u -match 'COMPLET' -or $u -match '\bOK\b') { Write-Host $s -ForegroundColor Green; return }
  Write-Host $s
}
function Titre([string]$t){
  Write-Host ""
  Write-Host ("="*70) -ForegroundColor Cyan
  Write-Host ("  " + $t) -ForegroundColor Cyan
  Write-Host ("="*70) -ForegroundColor Cyan
}

# Extrait "major.minor" ("17.14.36127.28" -> "17.14").
function VS-MajorMinor([string]$v) {
  if ($v -match '^\s*(\d+)\.(\d+)') { return ($Matches[1] + "." + $Matches[2]) }
  return ""
}

# Version d'un LAYOUT : Catalog.json (info.product*Version, au DEBUT du fichier,
# souvent minifie) ; on ne lit que les 1ers Ko. Repli : ChannelManifest.json.
function Get-LayoutVersion([string]$dir) {
  if (-not $dir -or -not (Test-Path $dir)) { return "" }
  $cat = Join-Path $dir "Catalog.json"
  if (Test-Path $cat) {
    $fs = $null
    try {
      $fs   = [System.IO.File]::OpenRead($cat)
      $buf  = New-Object byte[] 65536
      $n    = $fs.Read($buf, 0, $buf.Length)
      $head = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
      if ($head -match '"product(?:Display|Semantic)Version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)') { return $Matches[1] }
    } catch {} finally { if ($fs) { $fs.Close() } }
  }
  $chan = Join-Path $dir "ChannelManifest.json"
  if (Test-Path $chan) {
    try {
      $txt = Get-Content $chan -Raw -ErrorAction Stop
      if ($txt -match '"version"\s*:\s*"(1[0-9]\.[0-9]+\.[0-9]+)') { return $Matches[1] }
    } catch {}
  }
  return ""
}

# Presence d'un paquet dans le layout : dossier "<Id>,version=...". Renvoie un
# objet {Present, Count, Version}.
function Get-PkgInfo([string]$dir, [string]$id) {
  $out = New-Object psobject -Property @{ Present = $false; Count = 0; Version = "" }
  $folders = @(Get-ChildItem $dir -Directory -Filter ($id + ",*") -ErrorAction SilentlyContinue)
  if ($folders.Count -eq 0) {
    $folders = @(Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $id -or $_.Name -like ($id + ",*") })
  }
  if ($folders.Count -gt 0) {
    $out.Present = $true
    $out.Count   = $folders.Count
    if ($folders[0].Name -match 'version=([0-9][0-9.]+)') { $out.Version = $Matches[1] }
  }
  return $out
}

# Test de connexion internet (aka.ms:443). Repli requete HEAD.
function Test-Online {
  try { if (Test-NetConnection -ComputerName "aka.ms" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue) { return $true } } catch {}
  try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "https://aka.ms" -UseBasicParsing -TimeoutSec 8 -Method Head | Out-Null
    return $true
  } catch { return $false }
}

# SECURITE : verifie la signature
# Authenticode d'un binaire AVANT de l'executer. Refuse un binaire NON signe ou
# ALTERE. Hors ligne, tolere une signature presente mais non entierement validee
# (revocation injoignable) - jamais un binaire non signe. $Publisher impose l'editeur.
function Assert-TrustedBinary([string]$Path, [string]$Publisher = "Microsoft") {
  if (-not (Test-Path -LiteralPath $Path)) { L ("  SECURITE : binaire introuvable -> " + $Path); return $false }
  $sig = $null
  try { $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop } catch { L ("  SECURITE : signature illisible (" + $_.Exception.Message + ") -> REFUS : " + $Path); return $false }
  switch ("$($sig.Status)") {
    "Valid"        { }
    "NotSigned"    { L ("  SECURITE : binaire NON SIGNE -> REFUS : " + $Path); return $false }
    "HashMismatch" { L ("  SECURITE : binaire ALTERE (hash) -> REFUS : " + $Path); return $false }
    default {
      if (-not $sig.SignerCertificate) { L ("  SECURITE : signature absente/illisible (" + $sig.Status + ") -> REFUS : " + $Path); return $false }
      L ("  SECURITE : signature presente mais non entierement verifiee (" + $sig.Status + " ; hors-ligne ?) -> toleree pour " + (Split-Path $Path -Leaf))
    }
  }
  if ($Publisher -and $sig.SignerCertificate -and ($sig.SignerCertificate.Subject -notmatch [regex]::Escape($Publisher))) {
    L ("  SECURITE : editeur INATTENDU (" + $sig.SignerCertificate.Subject + ") ; attendu ~ '" + $Publisher + "' -> REFUS : " + $Path); return $false
  }
  return $true
}

# VERIFICATION complete d'un layout : affiche version/taille/presence, renvoie
# un objet {ManifestOk, Version, Folders, SizeGB, Missing[], Complete}.
function Invoke-LayoutCheck([string]$dir) {
  $res = New-Object psobject -Property @{ ManifestOk=$false; Version=""; Folders=0; SizeGB=0.0; Missing=@(); Complete=$false }
  if (-not (Test-Path $dir)) {
    L ("Layout : dossier ABSENT -> " + $dir)
    $res.Missing = @($REQUIRED | ForEach-Object { $_.Label })
    return $res
  }
  L ("Layout : " + $dir)
  $res.ManifestOk = (Test-Path (Join-Path $dir "ChannelManifest.json")) -and (Test-Path (Join-Path $dir "Catalog.json"))
  L ("  Manifestes (ChannelManifest/Catalog) : " + $(if($res.ManifestOk){"PRESENTS"}else{"ABSENTS -> layout non initialise"}))
  $res.Version = Get-LayoutVersion $dir
  L ("  Version du layout : " + $(if($res.Version){$res.Version + "  (VS 2022 " + (VS-MajorMinor $res.Version) + ")"}else{"INTROUVABLE"}))
  $res.Folders = @(Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue).Count
  L ("  Paquets (dossiers) : " + $res.Folders)
  Write-Host "  Calcul de la taille (peut prendre un instant)..." -ForegroundColor DarkGray
  try { $sum = (Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { $sum = 0 }
  if (-not $sum) { $sum = 0 }
  $res.SizeGB = [math]::Round($sum/1GB, 1)
  L ("  Taille totale : " + $res.SizeGB + " Go")
  if ($res.SizeGB -lt $MinSizeGB) { L ("  AVERTISSEMENT : taille < " + $MinSizeGB + " Go -> layout tres probablement INCOMPLET.") }

  L "  COMPOSANTS REQUIS pour COMPILER BoutonSPAM (charges utiles reelles) :"
  L "  (les workloads Office/.NET desktop n'ont PAS de dossier -> ils sont dans le catalogue ; on verifie leurs composants concrets)"
  $missing = @()
  foreach ($r in $REQUIRED) {
    $p = Get-PkgInfo $dir $r.Id
    if ($p.Present) {
      L ("     PRESENT : " + $r.Label + "  (" + $r.Id + ")" + $(if($p.Version){" v" + $p.Version}else{""}))
    } else {
      L ("     ABSENT  : " + $r.Label + "  (" + $r.Id + ")")
      $missing += $r.Label
    }
  }
  $res.Missing = $missing
  $res.Complete = ($res.ManifestOk -and ($missing.Count -eq 0) -and ($res.SizeGB -ge $MinSizeGB))
  return $res
}

# --------------------------------------------------------------------------
$LOGDIR = Join-Path $ROOT "logs"
if (-not (Test-Path $LOGDIR)) { try { New-Item -ItemType Directory -Path $LOGDIR -ErrorAction Stop | Out-Null } catch { $LOGDIR = [Environment]::GetFolderPath("Desktop") } }
$LOG = Join-Path $LOGDIR ("layout-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
try { Start-Transcript -Path $LOG -Append -ErrorAction Stop | Out-Null } catch {}

Titre "VERIFICATION DU LAYOUT VISUAL STUDIO (hors ligne)"
Write-Host "Legende : " -NoNewline
Write-Host "VERT=present/complet  " -ForegroundColor Green -NoNewline
Write-Host "ROUGE=requis et ABSENT/incomplet  " -ForegroundColor Red -NoNewline
Write-Host "ORANGE=avertissement" -ForegroundColor Yellow

$check = Invoke-LayoutCheck $LayoutDir

Titre "VERDICT"
if ($check.Complete) {
  L ("COMPLET : le layout contient tout le necessaire (VS 2022 " + (VS-MajorMinor $check.Version) + ", " + $check.SizeGB + " Go).")
  L "Etapes suivantes :"
  L ("   1) Copiez le dossier " + $LayoutDir + " sur le poste HORS LIGNE (cle exFAT/NTFS ou partage reseau).")
  L "   2) La-bas : powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup -LayoutPath <dossier copie>"
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
}

# --- INCOMPLET -------------------------------------------------------------
L "INCOMPLET : il manque des elements requis :"
foreach ($m in $check.Missing) { L ("   - " + $m) }

if (-not $Download) {
  L ""
  L "Pour telecharger le manquant, relancez ce script EN LIGNE avec -Download :"
  L "   powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download"
  L ("(le layout se remplira dans " + $LayoutDir + " ; l'operation reprend ou elle s'est arretee).")
  try { Stop-Transcript | Out-Null } catch {}
  exit 2
}

# -Download demande : verifier la connexion
Titre "COMPLETION DU LAYOUT (-Download)"
if (-not (Test-Online)) {
  L "HORS LIGNE : impossible de telecharger (aka.ms injoignable)."
  L "Sur ce poste hors ligne, on ne peut PAS completer le layout. Deux options :"
  L "   - Completez le layout sur un poste CONNECTE (memes charges), puis recopiez-le ici ;"
  L "   - ou branchez temporairement ce poste a internet et relancez -Download."
  try { Stop-Transcript | Out-Null } catch {}
  exit 3
}

# Layout PARTIEL existant = PIEGE : le moteur peut se declarer "Total packages to
# download: 0" alors qu'il manque des charges (etat verrouille par un 1er run
# interrompu). Repartir d'un dossier PROPRE resout ce blocage.
if ((Test-Path $LayoutDir) -and $check.ManifestOk -and -not $check.Complete) {
  if ($Fresh) {
    $aside = $LayoutDir + "-partiel-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    L ("Layout PARTIEL : mise de cote avant re-telechargement propre -> " + $aside)
    try { Move-Item -LiteralPath $LayoutDir -Destination $aside -Force -ErrorAction Stop }
    catch { L ("   AVERTISSEMENT : deplacement impossible (" + $_.Exception.Message + "). On continue sur place.") }
  } else {
    L "AVERTISSEMENT : un layout PARTIEL existe deja. Un layout incomplet peut BLOQUER"
    L "  le moteur (il affiche 'Total packages to download: 0' alors qu'il manque des"
    L "  charges). Si la taille ne grossit pas, relancez avec -Fresh pour repartir propre :"
    L "     powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download -Fresh"
  }
}

# Bootstrapper vs_community.exe (a cote du layout, reutilise s'il existe)
$parent = Split-Path $LayoutDir -Parent
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$boot = Join-Path $parent "vs_community.exe"
if (-not (Test-Path $boot)) {
  L "Telechargement du bootstrapper vs_community.exe (canal Release 17)..."
  try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "https://aka.ms/vs/17/release/vs_community.exe" -OutFile $boot -UseBasicParsing
    L "   OK."
  } catch {
    L ("   ECHEC du telechargement du bootstrapper : " + $_.Exception.Message)
    try { Stop-Transcript | Out-Null } catch {}
    exit 4
  }
}

# SECURITE : on NE lance JAMAIS le bootstrapper sans avoir verifie sa
# signature Authenticode (editeur Microsoft) - qu'il vienne d'etre telecharge
# OU qu'il preexiste dans installers\ (un binaire pre-depose serait sinon
# execute tel quel sur l'hote de fabrication).
if (-not (Assert-TrustedBinary $boot "Microsoft")) {
  L "REFUS : le bootstrapper Visual Studio n'a pas passe la verification de signature -> non execute."
  L "   Supprimez installers\vs_community.exe (potentiellement altere) et relancez pour le retelecharger depuis Microsoft."
  try { Stop-Transcript | Out-Null } catch {}
  exit 6
}

# Construction des arguments : commande CANONIQUE d'un layout complet
# (pas de --arch : le defaut inclut l'architecture hote x64, ne pas restreindre).
$vsArgs = @('--layout', $LayoutDir, '--lang', $Lang, '--includeRecommended')
foreach ($r in $ADD_WORKLOADS) { $vsArgs += @('--add', $r) }
$vsArgs += '--wait'   # BLOQUE jusqu'a la fin et renvoie un vrai code de sortie

L ("Telechargement dans : " + $LayoutDir)
L ("Charges ajoutees : " + ($ADD_WORKLOADS -join ', '))
L "Cette etape est LONGUE (des dizaines de Go). Laissez-la aller au bout..."
$p = Start-Process -FilePath $boot -ArgumentList $vsArgs -Wait -PassThru
L ("Code de sortie du layout : " + $p.ExitCode)

# Copier les journaux de l'installeur (utile en cas d'echec)
try {
  $ddDir = Join-Path $LOGDIR "layout-dd-logs"
  if (-not (Test-Path $ddDir)) { New-Item -ItemType Directory -Path $ddDir -Force | Out-Null }
  Get-ChildItem (Join-Path $env:TEMP "dd_*.log") -ErrorAction SilentlyContinue | Copy-Item -Destination $ddDir -Force -ErrorAction SilentlyContinue
} catch {}

# RE-VERIFICATION apres telechargement
Titre "RE-VERIFICATION APRES TELECHARGEMENT"
$check2 = Invoke-LayoutCheck $LayoutDir

Titre "VERDICT FINAL"
if ($check2.Complete) {
  L ("COMPLET : layout pret (VS 2022 " + (VS-MajorMinor $check2.Version) + ", " + $check2.SizeGB + " Go).")
  L ("   Copiez " + $LayoutDir + " sur le poste hors ligne, puis :")
  L "   powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup -LayoutPath <dossier copie>"
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
} else {
  L "INCOMPLET encore apres telechargement. Elements toujours manquants :"
  foreach ($m in $check2.Missing) { L ("   - " + $m) }
  if ($p.ExitCode -ne 0) {
    L ("Le layout s'est termine avec le code " + $p.ExitCode + " (!= 0). Relancez -Download : l'operation REPREND ou elle s'est arretee.")
  } else {
    # Code 0 mais TOUJOURS incomplet : on compare la taille AVANT/APRES. Si elle n'a
    # pas augmente, le moteur n'a RIEN telecharge -> layout PARTIEL "verrouille" par un
    # run precedent (souvent avec d'autres options, ex. --includeOptional interrompu).
    # Le SEUL remede fiable est de repartir d'un dossier PROPRE : -Fresh.
    $grew = [math]::Round($check2.SizeGB - $check.SizeGB, 1)
    if ($grew -le 0.4) {
      L ("AVERTISSEMENT : code 0 mais la taille n'a PAS augmente (" + $check.SizeGB + " Go -> " + $check2.SizeGB + " Go).")
      L "  Le layout PARTIEL est VERROUILLE : le moteur croit n'avoir rien a faire alors qu'il"
      L "  manque des charges. C'est le piege classique d'un layout laisse a moitie par un run"
      L "  precedent (ex. un --includeOptional interrompu)."
      L "  >>> REPARTEZ PROPRE - l'ancien layout est DEPLACE de cote (jamais supprime) :"
      L ""
      L "        powershell -ExecutionPolicy Bypass -File powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download -Fresh"
      L ""
      L "  (-Fresh renomme installers\vslayout en vslayout-partiel-AAAAMMJJ-HHMMSS puis retelecharge tout.)"
    } else {
      L ("Progression partielle (+" + $grew + " Go depuis le dernier controle). Relancez -Download pour REPRENDRE.")
      L "  S'il reste bloque au meme point (la taille ne bouge plus d'un run a l'autre), repartez"
      L "  propre :  powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download -Fresh"
    }
    L "  Journaux detailles du moteur (utile en cas d'echec reseau) : logs\layout-dd-logs\."
  }
  try { Stop-Transcript | Out-Null } catch {}
  exit 5
}
