# ============================================================================
#  04_build.ps1 — construit ET signe le MSI en UNE SEULE commande.
#  Vit dans scripts\ ; travaille toujours a la RACINE du projet.
#
#  Ce qu'il enchaine :
#    1/5  Propagation de branding.conf (02_customize.sh, via Git Bash)
#    2/5  Compilation Release + fabrication du MSI (devenv.com, projet Setup)
#    3/5  Verification du MSI produit
#    4/5  Signature + horodatage (03_sign.ps1)
#    5/5  Assemblage du dossier release\ (MSI signe + .reg + vstor_redist + notice)
#
#  Usage (PowerShell, a la RACINE du projet, Visual Studio FERME) :
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     .\scripts\04_build.ps1                    # tout enchainer
#     .\scripts\04_build.ps1 -NoSign            # sans signature
#     .\scripts\04_build.ps1 -NoCustomize       # sans re-propager branding.conf
#
#  Tout est journalise dans logs\build-*.log
# ============================================================================
param(
  [switch]$NoSign,       # ne pas signer a la fin
  [switch]$NoCustomize,  # ne pas relancer 02_customize.sh avant le build
  [string]$Configuration = "Release"
)
$ErrorActionPreference = "Stop"

# RACINE du projet = dossier PARENT de scripts\
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ROOT "branding.conf"))) { $ROOT = $PSScriptRoot }

# Journalisation complete
$LOGDIR = Join-Path $ROOT "logs"
if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Path $LOGDIR | Out-Null }
$LOG = Join-Path $LOGDIR ("build-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
try { Start-Transcript -Path $LOG -Append | Out-Null } catch {}

function Etape([string]$t){ Write-Host ""; Write-Host ("=== " + $t + " ===") -ForegroundColor Cyan }

function Get-ConfValue([string]$file, [string]$key) {
  if (-not (Test-Path $file)) { return $null }
  $pat  = "^\s*{0}\s*=" -f [regex]::Escape($key)
  $line = Select-String -Path $file -Pattern $pat | Select-Object -First 1
  if (-not $line) { return $null }
  $v = $line.Line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($key)), ""
  if ($v -match '^"([^"]*)"') { return $Matches[1] }
  $v = ($v -split '#', 2)[0]
  return $v.Trim().Trim('"')
}

$conf    = Join-Path $ROOT "branding.conf"
$msiBase = Get-ConfValue $conf "MSI_BASENAME"; if (-not $msiBase) { $msiBase = "Setup" }
$msiBase = ($msiBase -replace '[^A-Za-z0-9._-]', '')
$ver     = Get-ConfValue $conf "VERSION"
$v3      = if ($ver) { (($ver -split '\.')[0..2] -join '.') } else { "" }
$msiPath = Join-Path $ROOT ("setup\" + $Configuration + "\" + $(if($v3){"$msiBase-$v3.msi"}else{"$msiBase.msi"}))

Write-Host ("Projet   : " + $ROOT)
Write-Host ("Version  : " + $ver + "   Configuration : " + $Configuration)
Write-Host ("MSI vise : " + $msiPath)

# ------------------------------------------------------ 1/5 CUSTOMIZE
Etape "1/5 Propagation de branding.conf (02_customize.sh)"
if ($NoCustomize) {
  Write-Host "Ignoree (-NoCustomize)."
} else {
  $bash = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($bash) {
    Push-Location $ROOT
    & $bash "./scripts/02_customize.sh"
    $rc = $LASTEXITCODE
    Pop-Location
    if ($rc -ne 0) { throw "02_customize.sh a echoue (code $rc). Cause frequente : VERSION en baisse dans branding.conf. Voir le message ci-dessus." }
  } else {
    Write-Warning "Git Bash introuvable : etape ignoree. Si branding.conf a change, lancez ./scripts/02_customize.sh manuellement."
  }
}

# ------------------------------------------------------ 2/5 BUILD
Etape "2/5 Compilation + fabrication du MSI (devenv.com)"
if (Get-Process devenv -ErrorAction SilentlyContinue) {
  throw "Visual Studio est OUVERT : fermez-le puis relancez (la generation en ligne de commande et l'IDE ne doivent pas travailler en meme temps)."
}
$vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vsw)) { throw "vswhere.exe introuvable : Visual Studio est-il installe ? (.\scripts\01_verification-poste.ps1 -Setup)" }
# -all -prerelease : detecte aussi une instance "incomplete" (installation hors ligne)
$vsPath = (& $vsw -all -prerelease -products * -latest -property installationPath | Select-Object -First 1)
# Repli par le systeme de fichiers si vswhere ne renvoie rien alors que VS est installe.
if (-not $vsPath) {
  foreach ($base in @("$env:ProgramFiles\Microsoft Visual Studio\2022", "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022")) {
    if (Test-Path $base) {
      $dc = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "Common7\IDE\devenv.com" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
      if ($dc) { $vsPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dc))); Write-Warning ("vswhere n'a rien renvoye ; VS detecte sur le disque : " + $vsPath); break }
    }
  }
}
if (-not $vsPath) { throw "Visual Studio 2022 introuvable (vswhere + disque). Verifiez l'installation (.\scripts\01_verification-poste.ps1)." }
$devenv = Join-Path $vsPath "Common7\IDE\devenv.com"
if (-not (Test-Path $devenv)) { throw ("devenv.com introuvable sous " + $vsPath) }

# Prerequis CONNU du build des projets d'installation en ligne de commande :
# sans ce reglage (une fois par utilisateur), devenv echoue avec HRESULT 8000000A.
# IMPORTANT : l'outil identifie l'instance VS d'apres le REPERTOIRE COURANT ;
# lance depuis le projet, il n'agit pas (il affiche seulement ses instructions).
$dopb = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\VSI\DisableOutOfProcBuild\DisableOutOfProcBuild.exe"
if (Test-Path $dopb) {
  Write-Host "Reglage DisableOutOfProcBuild (prerequis du build CLI des projets Setup)..."
  Push-Location (Split-Path $dopb)
  try { & $dopb | Out-Null } finally { Pop-Location }
}

$sln = Join-Path $ROOT "OutlookSpamAddin.sln"
if (Test-Path $msiPath) { Remove-Item $msiPath -Force }   # garantit un MSI FRAIS
$dllPath = Join-Path $ROOT ("OutlookSpamAddin\bin\" + $Configuration + "\BoutonSPAM.dll")

# --- Horodatage (manifeste + MSI) adapte a la CONNECTIVITE de ce build -------
# Le .vbproj porte <ManifestTimestampUrl> : PENDANT la compilation, Visual Studio
# contacte ce serveur pour horodater la signature du MANIFESTE ClickOnce/VSTO.
# Poste HORS LIGNE -> "error MSB3482 : Impossible de resoudre ... URL d'horodatage"
# et le build ECHOUE. On adapte donc a CHAQUE build :
#   hors ligne -> balise videe (signature du manifeste SANS horodatage : valide,
#                 meme logique que 03_sign -NoTimestamp) et MSI signe -NoTimestamp ;
#   en ligne   -> balise realignee sur TIMESTAMP_URL de branding.conf.
$tsUrl  = Get-ConfValue $conf "TIMESTAMP_URL"; if (-not $tsUrl) { $tsUrl = "http://timestamp.digicert.com" }
$tsHost = if ($tsUrl -match '^\w+://([^/]+)') { $Matches[1] } else { "timestamp.digicert.com" }
$netBuild = $false
try { $netBuild = [bool]([System.Net.Dns]::GetHostAddresses($tsHost)) } catch { $netBuild = $false }
$vbp = Join-Path $ROOT "OutlookSpamAddin\OutlookSpamAddin.vbproj"
if (Test-Path $vbp) {
  $rawVbp   = [System.IO.File]::ReadAllText($vbp)
  $tsWanted = if ($netBuild) { $tsUrl } else { "" }
  $newVbp   = [regex]::Replace($rawVbp, '<ManifestTimestampUrl>.*?</ManifestTimestampUrl>', ('<ManifestTimestampUrl>' + $tsWanted + '</ManifestTimestampUrl>'), 'Singleline')
  if ($newVbp -ne $rawVbp) {
    $bomVbp = $false; try { $b3 = [System.IO.File]::ReadAllBytes($vbp); $bomVbp = ($b3.Length -ge 3 -and $b3[0] -eq 0xEF -and $b3[1] -eq 0xBB) } catch {}
    [System.IO.File]::WriteAllText($vbp, $newVbp, (New-Object System.Text.UTF8Encoding($bomVbp)))
  }
  if ($netBuild) { Write-Host ("Horodatage : EN LIGNE (" + $tsHost + " resolu) -> manifeste horodate via " + $tsUrl) }
  else           { Write-Host "Horodatage : HORS LIGNE -> manifeste signe SANS horodatage (erreur MSB3482 evitee) ; le MSI sera signe avec -NoTimestamp." }
}

# --- Pre-verification du CERTIFICAT de signature des MANIFESTES --------------
# Retour terrain (poste neuf hors domaine) : la DLL compile puis la
# signature des manifestes echoue en MSB3482 « Une chaine de certificats n'a pas
# pu etre etablie vers une autorite racine de confiance » — le certificat FEUILLE
# etait bien importe, mais pas la CHAINE de l'IGC (racine + intermediaires),
# inconnue d'un poste qui n'a jamais recu la PKI interne. On verifie donc la
# chaine AVANT de lancer la compilation : echec immediat et remede clair, au lieu
# d'un MSB3482 apres 20 s de build. Concerne aussi -NoSign (la signature des
# MANIFESTES pendant la compilation est independante de la signature du MSI).
# Un certificat de TEST auto-signe est TOLERE (UntrustedRoot sur une feuille
# auto-signee = cas normal : la signature de manifeste passe).
$thumbPre = Get-ConfValue $conf "CERT_THUMBPRINT"
if ($thumbPre) {
  $thumbPre = ($thumbPre -replace '[^0-9A-Fa-f]', '').ToUpper()
  $leafCert = $null
  foreach ($stPre in @("Cert:\CurrentUser\My","Cert:\LocalMachine\My")) {
    $leafCert = Get-ChildItem $stPre -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumbPre } | Select-Object -First 1
    if ($leafCert) { break }
  }
  if (-not $leafCert) {
    Write-Warning ("Certificat CERT_THUMBPRINT (" + $thumbPre + ") INTROUVABLE dans les magasins My : la signature des manifestes echouera. Importez le .pfx/.p12 (assistant, etape 4/5) puis relancez.")
  } else {
    $chainPre = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chainPre.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
    $chainOk = $false
    try { $chainOk = $chainPre.Build($leafCert) } catch {}
    if ($chainOk) {
      Write-Host ("Certificat de signature : chaine OK -> " + $leafCert.Subject)
    } elseif ($leafCert.Subject -eq $leafCert.Issuer) {
      Write-Host ("Certificat de signature : auto-signe (certificat de TEST) -> tolere pour la signature des manifestes (" + $leafCert.Subject + ")")
    } else {
      $etatsPre = (@($chainPre.ChainStatus | ForEach-Object { "" + $_.Status }) -join ', ')
      Write-Warning ("La CHAINE du certificat de signature ne se construit pas (" + $etatsPre + ") : le build echouerait en MSB3482 'autorite racine de confiance'.")
      throw ("Chaine du certificat de signature INCOMPLETE sur ce poste. REMEDE : re-importer le .p12 via l'assistant (etape 4/5 : il importe desormais AUSSI la chaine de l'IGC), ou importer a la main la racine/les intermediaires de l'IGC dans le magasin machine. Puis relancer .\scripts\04_build.ps1")
    }
  }
}

# ETAPE 1 : compiler le PROJET DE CODE (produit BoutonSPAM.dll dans bin\<cfg>).
# Le projet Setup est exclu de la generation de solution ; on le construit
# SEPAREMENT ensuite, une fois le .dll present (l'ordre "code puis Setup" est
# celui du flux manuel qui fonctionne ; un /Project Setup seul ne compile PAS
# la dependance et echoue avec "Unable to find source file ...BoutonSPAM.dll").
Write-Host ("[a] devenv.com <sln> /Build " + $Configuration + " /Project OutlookSpamAddin")
& $devenv $sln /Build $Configuration /Project "OutlookSpamAddin"
if ($LASTEXITCODE -ne 0) { throw ("Echec de compilation du code (OutlookSpamAddin, devenv code " + $LASTEXITCODE + ") - details dans " + $LOG) }
if (-not (Test-Path $dllPath)) { throw ("Compilation OK mais " + $dllPath + " introuvable - verifier la configuration/plateforme.") }
Write-Host ("    OK : " + $dllPath)

# ETAPE 2 : fabriquer le MSI (le .dll existe desormais).
Write-Host ("[b] devenv.com <sln> /Build " + $Configuration + " /Project Setup")
& $devenv $sln /Build $Configuration /Project "Setup"
if ($LASTEXITCODE -ne 0) { throw ("Echec de fabrication du MSI (Setup, devenv code " + $LASTEXITCODE + ") - details dans " + $LOG) }

# ------------------------------------------------------ 3/5 VERIFICATION
Etape "3/5 Verification du MSI"
if (-not (Test-Path $msiPath)) {
  $found = Get-ChildItem (Join-Path $ROOT ("setup\" + $Configuration)) -Filter "*.msi" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($found) { $msiPath = $found.FullName; Write-Warning ("Nom attendu introuvable ; MSI le plus recent retenu : " + $msiPath) }
  else { throw ("Aucun MSI dans setup\" + $Configuration + " - voir " + $LOG) }
}
$item = Get-Item $msiPath
Write-Host ("MSI : " + $msiPath)
Write-Host ("     " + [math]::Round($item.Length/1KB) + " Ko - genere le " + $item.LastWriteTime)

# ------------------------------------------------------ 4/5 SIGNATURE
Etape "4/5 Signature + horodatage (03_sign.ps1)"
if ($NoSign) {
  Write-Host "Ignoree (-NoSign). Pour signer plus tard : .\scripts\03_sign.ps1"
} else {
  $signArgs = @("-MsiPath", $msiPath)
  if (-not $netBuild) {
    $signArgs += "-NoTimestamp"
    Write-Host "(hors ligne : MSI signe SANS horodatage ; pour un horodatage RFC 3161, re-signez plus tard sur un poste connecte : .\scripts\03_sign.ps1 -MsiPath <msi>)"
  }
  & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "03_sign.ps1") @signArgs
  if ($LASTEXITCODE -ne 0) { throw ("Echec de la signature (code " + $LASTEXITCODE + ")") }
}

# ------------------------------------------------------ 5/5 RELEASE
Etape "5/5 Assemblage du dossier release\ (instantane d'installation)"
# release\ = les 3 fichiers d'une installation manuelle, prets a distribuer :
# le MSI fraichement construit (et signe), la config registre et le runtime
# VSTO, plus une notice HORODATEE. REGENERE a chaque build ; les fichiers de
# REFERENCE restent dans resources\ et installers\ (utilises par
# 01_verification-poste.ps1 / 05_assistant.ps1). Dossier git-ignore.
# Un echec ici n'invalide JAMAIS le build (bloc entierement protege).
try {
  $REL = Join-Path $ROOT "release"
  if (-not (Test-Path $REL)) { New-Item -ItemType Directory -Path $REL | Out-Null }
  # On repart propre : artefacts et notices horodatees du build precedent.
  Get-ChildItem $REL -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Extension -in @(".msi", ".reg", ".exe")) -or ($_.Name -like "LISEZ-MOI-INSTALLATION-*") } |
    Remove-Item -Force -ErrorAction SilentlyContinue
  Copy-Item $msiPath $REL -Force
  foreach ($relSrc in @("resources\RegistryConfig.reg", "resources\DoNotDisableAddinList.reg", "installers\vstor_redist.exe")) {
    $src = Join-Path $ROOT $relSrc
    if (Test-Path $src) { Copy-Item $src $REL -Force }
    else { Write-Warning ("release\ : source absente, non copiee : " + $relSrc) }
  }
  $tsRel   = Get-Date -Format "yyyyMMdd-HHmm"
  $msiName = Split-Path -Leaf $msiPath
  $notice  = @"
# Installation du bouton SPAM - notice generee le $(Get-Date -Format "yyyy-MM-dd HH:mm")

Dossier ASSEMBLE AUTOMATIQUEMENT par scripts\04_build.ps1 a chaque build.
NE PAS EDITER : tout est ecrase au prochain build.

## Les 3 etapes (poste utilisateur)
1. Prerequis VSTO   -> executer vstor_redist.exe        (silencieux : vstor_redist.exe /q /norestart)
2. Config registre  -> importer RegistryConfig.reg      (cle HKLM 'To' OBLIGATOIRE)
   Optionnel : DoNotDisableAddinList.reg (empeche Outlook de desactiver l'add-in)
3. Add-in           -> executer $msiName

## Deploiement de masse (parc)
Voir deploy\ (install-silencieux.cmd + modeles GPO/ADMX) et le README, section Deploiement en parc.

Version : $ver   Configuration : $Configuration   Signature : $(if ($NoSign) { "NON SIGNE (-NoSign)" } else { "signee" })
"@
  Set-Content -Path (Join-Path $REL ("LISEZ-MOI-INSTALLATION-" + $tsRel + ".md")) -Value $notice -Encoding UTF8
  Write-Host ("release\ regenere : " + $msiName + " + RegistryConfig.reg + DoNotDisableAddinList.reg + vstor_redist.exe + notice " + $tsRel)
} catch {
  Write-Warning ("Assemblage release\ en echec (le build lui-meme est OK) : " + $_.Exception.Message)
}

Write-Host ""
Write-Host ("TERMINE : " + $msiPath) -ForegroundColor Green
Write-Host ("Journal : " + $LOG)
try { Stop-Transcript | Out-Null } catch {}
