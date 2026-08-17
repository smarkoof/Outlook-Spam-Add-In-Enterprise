<#
  03_sign.ps1 — Signe le MSI généré (Authenticode, SHA-256, horodaté RFC 3161).
  À lancer sur WINDOWS, APRÈS le build. Vit dans scripts\ ; travaille toujours
  à la RACINE du projet (les chemins relatifs y sont résolus automatiquement).

  - Lit branding.conf : PRODUCT_NAME, CERT_THUMBPRINT, TIMESTAMP_URL.
  - Deux modes de signature :
      * magasin de certificats Windows (CERT_THUMBPRINT / -Thumbprint)  [recommandé]
      * fichier .pfx direct (-PfxPath certs\moncert.pfx [-PfxPassword ...])
  - CERT_THUMBPRINT vide et aucun -Thumbprint/-PfxPath ? REPLI AUTOMATIQUE :
      certificat de PRODUCTION unique du magasin s'il y en a exactement un,
      sinon certificat de TEST auto-signé (créé automatiquement s'il n'existe
      pas). Rien à configurer pour builder/tester ; plusieurs certificats de
      production = choix ambigu -> le script demande CERT_THUMBPRINT.

  Exemples (à la racine du projet) :
    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -MsiPath "setup\Release\MonProduit.msi"
    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -Thumbprint AABB...  -TimestampUrl http://timestamp.digicert.com
    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -PfxPath .\certs\moncert.pfx -PfxPassword "secret"
    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -PfxPath .\certs\moncert.pfx -PfxPassword "secret" -NoTimestamp   # poste HORS LIGNE (pas d horodatage)
#>
[CmdletBinding()]
param(
  [string]$MsiPath,
  [string]$Thumbprint,
  [string]$TimestampUrl,
  [string]$PfxPath,
  [string]$PfxPassword,
  [switch]$NoTimestamp,
  [string]$BrandingConf
)

$ErrorActionPreference = "Stop"

# RACINE du projet = dossier PARENT de scripts\ (ou vit ce script)
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ROOT "branding.conf"))) { $ROOT = $PSScriptRoot }  # repli : script encore a la racine
if (-not $BrandingConf) { $BrandingConf = Join-Path $ROOT "branding.conf" }

function Get-ConfValue([string]$file, [string]$key) {
  if (-not (Test-Path $file)) { return $null }
  $pat  = "^\s*{0}\s*=" -f [regex]::Escape($key)
  $line = Select-String -Path $file -Pattern $pat | Select-Object -First 1
  if (-not $line) { return $null }
  $v = $line.Line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($key)), ""
  # Valeur entre guillemets si présente (ignore tout commentaire # en fin de ligne)
  if ($v -match '^"([^"]*)"') { return $Matches[1] }
  $v = ($v -split '#', 2)[0]
  return $v.Trim().Trim('"')
}

# Fiche détaillée d'un certificat : numéro de série, empreinte, durée, expiration.
function Show-CertDetails($c) {
  $days  = [int][math]::Floor(($c.NotAfter - (Get-Date)).TotalDays)
  $duree = [math]::Round((($c.NotAfter - $c.NotBefore).TotalDays)/365.25, 1)
  Write-Host ("certificat : " + $c.Subject)
  if ($c.Subject -eq $c.Issuer) { Write-Host "émis par   : lui-même  [certificat AUTO-SIGNÉ]" -ForegroundColor Yellow }
  else                          { Write-Host ("émis par   : " + $c.Issuer) }
  Write-Host ("empreinte  : " + $c.Thumbprint)
  Write-Host ("n° série   : " + $c.SerialNumber)
  Write-Host ("validité   : du " + $c.NotBefore.ToString("dd/MM/yyyy") + " au " + $c.NotAfter.ToString("dd/MM/yyyy") + " (durée totale " + $duree + " ans)")
  if     ($days -lt 0)  { Write-Host ("expiration : EXPIRÉ depuis " + (-$days) + " jours") -ForegroundColor Red }
  elseif ($days -le 90) { Write-Host ("expiration : dans " + $days + " jours — pensez au renouvellement") -ForegroundColor Yellow }
  else                  { Write-Host ("expiration : dans " + $days + " jours") }
}

# --- Résolution des paramètres (arguments prioritaires, sinon branding.conf) ---
$prod = Get-ConfValue $BrandingConf "PRODUCT_NAME"
if (-not $Thumbprint)   { $Thumbprint   = Get-ConfValue $BrandingConf "CERT_THUMBPRINT" }
if (-not $TimestampUrl) { $TimestampUrl = Get-ConfValue $BrandingConf "TIMESTAMP_URL" }
if (-not $MsiPath) {
  $msiBase = Get-ConfValue $BrandingConf "MSI_BASENAME"
  if (-not $msiBase) { $msiBase = $prod }
  if ($msiBase) { $msiBase = ($msiBase -replace '[^A-Za-z0-9._-]', '') }
  $ver = Get-ConfValue $BrandingConf "VERSION"
  $v3  = if ($ver) { (($ver -split '\.')[0..2] -join '.') } else { '' }
  if ($msiBase) {
    $fname   = if ($v3) { "$msiBase-$v3.msi" } else { "$msiBase.msi" }
    $MsiPath = Join-Path (Join-Path $ROOT "setup\Release") $fname
  }
}

if (-not $TimestampUrl) { $TimestampUrl = "http://timestamp.digicert.com" }
if (-not $MsiPath)             { throw "Chemin du MSI indéterminé. Passe -MsiPath." }
if (-not (Test-Path $MsiPath)) { throw "MSI introuvable : '$MsiPath'. Génère-le d'abord dans Visual Studio." }

# --- Vérifier le certificat selon le mode choisi ---
$cert = $null
if ($PfxPath) {
  if (-not (Test-Path $PfxPath)) { throw "PFX introuvable : '$PfxPath'." }
} else {
  if ($Thumbprint) {
    $Thumbprint = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpper()
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
    if (-not $cert) {
      throw "Certificat $Thumbprint introuvable dans Cert:\CurrentUser\My ni LocalMachine\My. Importez-le d'abord (voir certs\README.md)."
    }
  } else {
    # --- REPLI AUTOMATIQUE (CERT_THUMBPRINT vide, aucun -Thumbprint/-PfxPath) ---
    # 1 seul certificat de PRODUCTION dans le magasin -> on le prend.
    # Plusieurs -> ambigu, on refuse (CERT_THUMBPRINT à renseigner).
    # Aucun -> certificat de TEST auto-signé (réutilisé, sinon créé).
    Write-Host "CERT_THUMBPRINT vide : recherche d'un certificat de signature dans le magasin..."
    $now = Get-Date
    $all = @()
    $all += @(Get-ChildItem Cert:\CurrentUser\My  -CodeSigningCert -ErrorAction SilentlyContinue)
    $all += @(Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue)
    $all = @($all | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt $now })
    $prods = @($all | Where-Object { $_.Subject -ne $_.Issuer })
    $tests = @($all | Where-Object { $_.Subject -eq $_.Issuer })
    if ($prods.Count -eq 1) {
      $cert = $prods[0]
      Write-Host ("Certificat de PRODUCTION retenu : " + $cert.Subject + " | empreinte " + $cert.Thumbprint)
      Write-Host ('Conseil : fige-le dans branding.conf ->  CERT_THUMBPRINT="' + $cert.Thumbprint + '"')
    } elseif ($prods.Count -gt 1) {
      Write-Host "Plusieurs certificats de PRODUCTION possibles :"
      foreach ($c in $prods) { Write-Host ("  - " + $c.Subject + " | empreinte " + $c.Thumbprint + " | expire " + $c.NotAfter) }
      throw 'Choix ambigu : renseignez CERT_THUMBPRINT="<empreinte>" dans branding.conf (ou passez -Thumbprint).'
    } elseif ($tests.Count -ge 1) {
      $cert = $tests | Where-Object { $_.Subject -match 'CN=TestBoutonAbuse' } | Select-Object -First 1
      if (-not $cert) { $cert = $tests | Sort-Object NotAfter -Descending | Select-Object -First 1 }
      Write-Warning ("Aucun certificat de production : signature avec le certificat de TEST " + $cert.Subject + " | empreinte " + $cert.Thumbprint + ".")
    } else {
      Write-Warning "Aucun certificat de signature dans le magasin : création d'un certificat de TEST auto-signé (CN=TestBoutonAbuse, 3 ans, magasin CurrentUser\My)."
      $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=TestBoutonAbuse" -FriendlyName "Certificat de TEST - Bouton Spam" -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(3)
      Write-Host ("Créé : empreinte " + $cert.Thumbprint + " (à remplacer plus tard par le vrai certificat — voir certs/README.md).")
    }
    $Thumbprint = $cert.Thumbprint
  }
  if ($cert.NotAfter -lt (Get-Date)) { throw "Le certificat a expiré le $($cert.NotAfter)." }
}

# --- Localiser signtool.exe (tools\ du projet, PATH, ou Windows SDK) ---
$signtool = $null
$localTool = Join-Path $ROOT "tools\signtool\signtool.exe"
if (Test-Path $localTool) { $signtool = $localTool }
if (-not $signtool) {
  $signtool = Get-ChildItem (Join-Path $ROOT "tools") -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $signtool) { $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (-not $signtool) {
  $roots = @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "${env:ProgramFiles}\Windows Kits\10\bin") |
           Where-Object { $_ -and (Test-Path $_) }
  foreach ($r in $roots) {
    $cand = Get-ChildItem -Path $r -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' } |
            Sort-Object FullName -Descending | Select-Object -First 1
    if ($cand) { $signtool = $cand.FullName; break }
  }
}
if (-not $signtool) { throw "signtool.exe introuvable. Lancez .\scripts\01_verification-poste.ps1 -CompleteVS (recuperation NuGet automatique) ou installez le Windows SDK." }

$descr = if ($prod) { $prod } else { "Outlook Spam Add-In" }

Write-Host "signtool   : $signtool"
if ($PfxPath) { Write-Host "certificat : fichier PFX '$PfxPath'" }
else          { Show-CertDetails $cert }
Write-Host "MSI        : $MsiPath"
if ($NoTimestamp) { Write-Host "horodatage : (désactivé — poste hors ligne)" } else { Write-Host "horodatage : $TimestampUrl" }
Write-Host ""

# --- Signature ---
$sigArgs = @("sign")
if ($PfxPath) {
  $sigArgs += @("/f", $PfxPath)
  if ($PfxPassword) { $sigArgs += @("/p", $PfxPassword) }
} else {
  $sigArgs += @("/sha1", $Thumbprint)
}
$sigArgs += @("/fd", "SHA256")
if (-not $NoTimestamp) { $sigArgs += @("/tr", $TimestampUrl, "/td", "SHA256") }
$sigArgs += @("/d", $descr, "$MsiPath")
& $signtool @sigArgs
if ($LASTEXITCODE -ne 0) { throw "Échec de la signature (signtool code $LASTEXITCODE)." }

# --- Rafraichissement du dossier release\ (si present) -----------------------
# La signature vient d'etre APPOSEE sur le MSI. Si un instantane release\
# existe (assemble par 04_build.ps1) et contient CE MSI, on y recopie la
# version fraichement signee : release\ ne doit jamais distribuer un MSI
# non signe / non horodate (cas d'usage : re-signature ulterieure en ligne).
$relDir = Join-Path $ROOT "release"
if ((Test-Path $relDir) -and (Test-Path (Join-Path $relDir (Split-Path -Leaf $MsiPath)))) {
  try { Copy-Item $MsiPath $relDir -Force; Write-Host ("release\ mis a jour avec le MSI signe : " + (Split-Path -Leaf $MsiPath)) } catch {}
}

# --- Vérification ---
& $signtool verify /pa /v "$MsiPath"
if ($LASTEXITCODE -ne 0) {
  # L'échec de 'verify' peut n'être qu'un problème de CHAÎNE DE CONFIANCE sur CE
  # poste (certificat de TEST auto-signé, OU AC d'entreprise absente du magasin
  # de confiance de cette machine). Dans les deux cas la signature est APPOSÉE.
  $sig = $null
  try { $sig = Get-AuthenticodeSignature $MsiPath } catch {}
  if ($sig -and $sig.SignerCertificate) {
    $selfSigned = ($sig.SignerCertificate.Subject -eq $sig.SignerCertificate.Issuer)
    Write-Host ""
    if ($selfSigned) {
      Write-Warning ("Chaîne de confiance refusée : NORMAL avec un certificat de TEST auto-signé (" + $sig.SignerCertificate.Subject + ").")
      Write-Host "La signature et l'horodatage sont bien APPOSÉS (voir 'Successfully signed' ci-dessus)."
      Write-Host "La vérification complète réussira avec le vrai certificat d'entreprise (PKI/CA)."
      Write-Host ""
      Write-Host "OK : $MsiPath signé et horodaté (certificat de TEST — non reconnu publiquement)." -ForegroundColor Green
    } else {
      Write-Warning ("Chaîne de confiance non validée sur CE poste — certificat émis par : " + $sig.SignerCertificate.Issuer)
      Write-Host "Cause fréquente : l'AC d'entreprise n'est pas dans le magasin de confiance de cette machine (VM hors domaine)."
      Write-Host "La signature et l'horodatage sont bien APPOSÉS (voir 'Successfully signed' ci-dessus)."
      Write-Host "La vérification complète réussira sur un poste qui fait confiance à l'AC (postes du domaine)."
      Write-Host ""
      Write-Host "OK : $MsiPath signé et horodaté (chaîne non vérifiable sur ce poste)." -ForegroundColor Green
    }
    exit 0
  }
  throw "Échec de la vérification (signtool code $LASTEXITCODE)."
}

Write-Host ""
Write-Host "OK : $MsiPath signé et vérifié." -ForegroundColor Green
