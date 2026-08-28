# ============================================================================
#  05_assistant.ps1 - ASSISTANT INTERACTIF : configure PUIS construit le MSI.
#  Point d'entree RECOMMANDE. Vit dans scripts\ ; travaille a la RACINE du projet.
#
#  Il enchaine, en vous posant des questions (rien n'est fait sans votre reponse) :
#    1/5  Version   : version actuelle + explication majeur/mineur/correctif,
#                     puis incrementation guidee (une version ne diminue jamais).
#    2/5  Poste     : inventaire des prerequis (lecture seule, ne modifie rien).
#    3/5  Branding  : modification interactive de branding.conf (valeurs par
#                     defaut affichees ; Entree = garder, tiret '-' = vider).
#    4/5  Certificat: garder le certificat de TEST, ou pause pour recuperer le
#                     vrai (les autres certificats de code trouves sont listes
#                     avec leur chemin pour etre places dans certs\).
#    5/5  Build     : lancement du build complet (04_build.ps1).
#
#  Usage (PowerShell, a la RACINE du projet, Visual Studio FERME) :
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     .\scripts\05_assistant.ps1                 # tout l'assistant
#     .\scripts\05_assistant.ps1 -NoPrecheck     # sauter l'inventaire poste
#     .\scripts\05_assistant.ps1 -NoBuild        # configurer sans construire
# ============================================================================
param(
  [string]$Configuration = "Release",
  [switch]$NoPrecheck,   # sauter l'etape 2/5 (inventaire du poste)
  [switch]$NoBuild,      # s'arreter apres la configuration (ne pas lancer 04_build.ps1)
  [switch]$NoSign        # forcer une construction SANS signature
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---------------------------------------------------------------- RACINE
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ROOT "branding.conf"))) { $ROOT = $PSScriptRoot }
$conf = Join-Path $ROOT "branding.conf"
if (-not (Test-Path $conf)) { throw "branding.conf introuvable a la racine du projet ($ROOT)." }
$doSign = -not $NoSign

# ---------------------------------------------------------------- AFFICHAGE
function Titre([string]$t){ Write-Host ""; Write-Host ("==== " + $t + " ====") -ForegroundColor Cyan }
function Info([string]$t){ Write-Host $t -ForegroundColor Gray }
function Note([string]$t){ Write-Host $t -ForegroundColor DarkGray }
function Ok([string]$t){ Write-Host $t -ForegroundColor Green }
function Warn([string]$t){ Write-Host $t -ForegroundColor Yellow }

function Ask-YesNo([string]$question, [bool]$defaultYes = $true) {
  $suffix = if ($defaultYes) { "[O/n]" } else { "[o/N]" }
  while ($true) {
    $ans = Read-Host ("  " + $question + " " + $suffix)
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    $a = $ans.Trim().ToLower()
    if ($a -eq 'o' -or $a -eq 'oui' -or $a -eq 'y' -or $a -eq 'yes') { return $true }
    if ($a -eq 'n' -or $a -eq 'non' -or $a -eq 'no')                 { return $false }
    Warn "  Repondez par o (oui) ou n (non)."
  }
}

# ---------------------------------------------------------------- VERSIONS
function VerParts([string]$v){
  $r = @(0,0,0,0)
  if ($v) { $s = $v -split '\.'; for($i=0;$i -lt 4;$i++){ if($i -lt $s.Count -and $s[$i] -match '^\d+$'){ $r[$i]=[int]$s[$i] } } }
  return ,$r
}
function VerLt([string]$a,[string]$b){   # vrai si a < b (4 champs)
  $x=VerParts $a; $y=VerParts $b
  for($i=0;$i -lt 4;$i++){ if($x[$i] -lt $y[$i]){return $true}; if($x[$i] -gt $y[$i]){return $false} }
  return $false
}

# ---------------------------------------------------------------- branding.conf
# Chargement en memoire en PRESERVANT le BOM eventuel et la fin de ligne.
$script:BBYTES = [System.IO.File]::ReadAllBytes($conf)
$script:BBOM   = ($script:BBYTES.Length -ge 3 -and $script:BBYTES[0] -eq 0xEF -and $script:BBYTES[1] -eq 0xBB -and $script:BBYTES[2] -eq 0xBF)
$script:BRAW   = [System.IO.File]::ReadAllText($conf)
$script:BNL    = if ($script:BRAW -match "`r`n") { "`r`n" } else { "`n" }
$script:BLINES = ($script:BRAW -replace "`r`n","`n") -split "`n"

function BConf-Get([string]$key) {
  $pat = "^\s*{0}\s*=" -f [regex]::Escape($key)
  foreach ($l in $script:BLINES) {
    if ($l -match $pat) {
      $v = $l -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($key)), ""
      if ($v -match '^"([^"]*)"') { return $Matches[1] }
      $v = ($v -split '#',2)[0]
      return $v.Trim().Trim('"')
    }
  }
  return $null
}
function BConf-Set([string]$key, [string]$value) {
  $pat = '^(\s*' + [regex]::Escape($key) + '\s*=\s*)(.*)$'
  for ($i=0; $i -lt $script:BLINES.Count; $i++) {
    if ($script:BLINES[$i] -match $pat) {
      $prefix = $Matches[1]; $rest = $Matches[2]; $comment = ""
      if ($rest -match '^"[^"]*"(\s*#.*)$')      { $comment = $Matches[1] }
      elseif ($rest -match '^[^"#]*?(\s+#.*)$')  { $comment = $Matches[1] }
      $script:BLINES[$i] = ('{0}"{1}"{2}' -f $prefix, $value, $comment)
      return
    }
  }
  $script:BLINES += ('{0}="{1}"' -f $key, $value)
}
function Save-BConf {
  $enc = New-Object System.Text.UTF8Encoding($script:BBOM)   # meme etat de BOM qu'a l'origine
  [System.IO.File]::WriteAllText($conf, ($script:BLINES -join $script:BNL), $enc)
}

# Modifie un champ en interactif. Entree = garder ; '-' = vider.
function Edit-Field([string]$key,[string]$label,[string]$help){
  $cur = BConf-Get $key; if ($null -eq $cur) { $cur = "" }
  Write-Host ""
  Write-Host ("  " + $label) -ForegroundColor White
  if ($help) { Note ("    " + $help) }
  if ($cur -ne "") { Note ("    defaut : " + $cur) } else { Note "    (actuellement vide)" }
  $ans = Read-Host "    nouvelle valeur (Entree=garder, '-'=vider)"
  if ([string]::IsNullOrEmpty($ans)) { return }
  $ans = $ans.Trim()
  if ($ans -eq '-') { $ans = "" }
  if ($ans -eq $cur) { return }
  if ($ans.Contains('"')) { $ans = $ans -replace '"',''; Warn "    (guillemets doubles retires : interdits dans branding.conf)" }
  BConf-Set $key $ans
  Ok ("    -> " + $key + ' = "' + $ans + '"')
}

# Apercu du texte ACTUEL de l'accuse de reception : depuis la mise en forme HTML,
# le corps vit dans le CODE (Config.vb, constantes ackBody*)
# et les champs UI_ACK_BODY_* de branding.conf sont une simple SURCHARGE optionnelle
# (vides par defaut). Sans cet apercu, "(actuellement vide)" laisse croire a tort
# que l'accuse n'a plus de texte.
function Get-AckPreview([string]$constName){
  try {
    $cv = Join-Path $ROOT "OutlookSpamAddin\Config.vb"
    if (-not (Test-Path $cv)) { return "" }
    $m = Select-String -Path $cv -Pattern ('Const\s+' + $constName + '\s+As String\s*=\s*"([^"]*)"') | Select-Object -First 1
    if (-not $m) { return "" }
    $t = $m.Matches[0].Groups[1].Value
    $t = $t -replace '<br\s*/?>', ' / '
    $t = $t -replace '<[^>]+>', ''
    $t = $t -replace '&mdash;', '-'
    if ($t.Length -gt 100) { $t = $t.Substring(0, 100) + "..." }
    return $t
  } catch { return "" }
}

# ============================================================================
Clear-Host
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host "#   ASSISTANT BoutonSPAM  -  configuration + construction   #" -ForegroundColor Cyan
Write-Host "############################################################" -ForegroundColor Cyan
Info ("Projet        : " + $ROOT)
Info ("Configuration : " + $Configuration)
Note "A tout moment : Ctrl+C pour interrompre (aucune construction n'est lancee avant l'etape 5/5)."

# ------------------------------------------------------------ 1/5 VERSION
Titre "1/5  Version du produit"
$curConf = BConf-Get "VERSION"; if (-not $curConf) { $curConf = "1.0.0.0" }
$asm = Join-Path $ROOT "OutlookSpamAddin\My Project\AssemblyInfo.vb"
$built = $null
if (Test-Path $asm) {
  $mm = Select-String -Path $asm -Pattern '^\s*<Assembly:\s*AssemblyVersion\("([0-9][0-9.]*)"\)>' | Select-Object -First 1
  if ($mm) { $built = $mm.Matches[0].Groups[1].Value }
}

Info "Version = MAJEUR.MINEUR.CORRECTIF.BUILD"
Info "  Majeur     1.0.0.0 -> 2.0.0.0    refonte / rupture"
Info "  Mineur     1.0.0.0 -> 1.1.0.0    nouvelle fonctionnalite"
Info "  Correctif  1.0.0.0 -> 1.0.1.0    correction de bug"
Note "  Jamais en baisse ; les chiffres a droite du chiffre augmente repartent a 0."

$base = $curConf
if ($built -and (VerLt $base $built)) {
  Warn ("Note : la version deja compilee (" + $built + ") depasse branding.conf (" + $curConf + ") ; on repart de " + $built + ".")
  $base = $built
} elseif ($built) {
  Note ("(version deja compilee dans AssemblyInfo.vb : " + $built + ")")
}

$bp    = VerParts $base
$patch = "{0}.{1}.{2}.0" -f $bp[0],$bp[1],($bp[2]+1)
$minor = "{0}.{1}.0.0"   -f $bp[0],($bp[1]+1)
$major = "{0}.0.0.0"     -f ($bp[0]+1)

$newVer = $base; $chosen = $false
while (-not $chosen) {
  Write-Host ""
  Write-Host ("  Version actuelle : " + $base) -ForegroundColor White
  Write-Host ("    [1] Correctif (patch)        -> " + $patch.PadRight(12)) -NoNewline
  Write-Host "ex. correction de bug, retouche de texte" -ForegroundColor DarkGray
  Write-Host ("    [2] Fonctionnalite (mineur)  -> " + $minor.PadRight(12)) -NoNewline
  Write-Host "ex. nouvelle fonctionnalite ou option visible" -ForegroundColor DarkGray
  Write-Host ("    [3] Majeur                   -> " + $major.PadRight(12)) -NoNewline
  Write-Host "ex. refonte, changement incompatible" -ForegroundColor DarkGray
  Write-Host  "    [4] Saisir une version manuelle"
  Write-Host ("    [Entree] Garder la version   -> " + $base.PadRight(12)) -NoNewline
  Write-Host "ex. re-generation locale, rien a livrer" -ForegroundColor DarkGray
  $c = (Read-Host "  Choix").Trim()
  if ($c -eq "")      { $newVer=$base;  $chosen=$true }
  elseif ($c -eq '1') { $newVer=$patch; $chosen=$true }
  elseif ($c -eq '2') { $newVer=$minor; $chosen=$true }
  elseif ($c -eq '3') { $newVer=$major; $chosen=$true }
  elseif ($c -eq '4') {
    $mv = (Read-Host "  Nouvelle version (ex. 1.5.0.0)").Trim()
    if ($mv -notmatch '^\d+(\.\d+){1,3}$') { Warn "  Format invalide : uniquement des chiffres et des points (ex. 1.5.0.0)." }
    else {
      $pp = VerParts $mv; $mv = ("{0}.{1}.{2}.{3}" -f $pp[0],$pp[1],$pp[2],$pp[3])
      if (VerLt $mv $base) { Warn ("  " + $mv + " est INFERIEURE a " + $base + " : une version ne doit pas diminuer. Reessayez.") }
      else { $newVer=$mv; $chosen=$true }
    }
  }
  else { Warn "  Choix invalide." }
}
BConf-Set "VERSION" $newVer
if ($newVer -eq $base) { Info ("Version conservee : " + $newVer) } else { Ok ("Nouvelle version : " + $base + " -> " + $newVer) }

# --- Aides pour l'etape 2/5 : version (major.minor) d'un VS, et version d'un layout.
function Get-VsMM([string]$v) {
  if ($v -match '^\s*(\d+)\.(\d+)') { return ($Matches[1] + "." + $Matches[2]) }
  return ""
}
function Read-LayoutVer([string]$dir) {
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

# ------------------------------------------------------------ 2/5 POSTE
Titre "2/5  Verification / preparation du poste"
if ($NoPrecheck) {
  Info "Ignore (-NoPrecheck)."
} else {
  $v01 = Join-Path $PSScriptRoot "01_verification-poste.ps1"
  if (-not (Test-Path $v01)) {
    Warn "01_verification-poste.ps1 introuvable - etape ignoree."
  } else {
    $isAdmin = $false
    try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator) } catch {}
    # Detection de Visual Studio : PRESENCE, VERSION/BRANCHE, et CHARGES de build.
    $vsPresent = $false; $vsVer = ""; $vsMM = ""
    $vswA = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswA) {
      $vpp = (& $vswA -products * -latest -property installationPath 2>$null | Select-Object -First 1)
      if ($vpp) {
        $vsPresent = $true
        $vsVer = (& $vswA -products * -latest -property installationVersion 2>$null | Select-Object -First 1)
        $vsMM  = Get-VsMM $vsVer
      }
    }
    # On verifie aussi les CHARGES DE BUILD requises (Office/VSTO + .NET desktop) : VS peut
    # etre installe SANS elles -> build impossible.
    $vsBuildOk = $false
    if ($vsPresent) {
      try {
        $wl = & $vswA -latest -products * -requires Microsoft.VisualStudio.Workload.ManagedDesktop Microsoft.VisualStudio.Workload.Office -property installationPath 2>$null
        if ($wl) { $vsBuildOk = $true }
      } catch {}
    }
    # Recensement de TOUS les layouts hors ligne + leur version/branche (17.x). Pour
    # COMPLETER un VS installe il faut un layout de la MEME branche ; si le seul layout
    # dispo est PLUS RECENT (VS plus ancien), on peut faire une MONTEE DE VERSION hors ligne.
    $layoutCands = @((Join-Path $ROOT "installers\vslayout"),"C:\vslayout",
      "$env:USERPROFILE\Documents\vslayout.2022.community","$env:USERPROFILE\Documents\vslayout",
      "C:\Dev\vslayout","D:\VSlayout","D:\vslayout","$env:USERPROFILE\Downloads\vslayout")
    $layouts = @()
    foreach ($lc in $layoutCands) {
      # PAS de Join-Path ici : il LEVE une DriveNotFoundException si le lecteur du
      # candidat n'existe pas (ex. D:\ absent) et, avec ErrorActionPreference=Stop,
      # tue toute l'etape. La concatenation + Test-Path repond simplement $false.
      if ($lc -and (Test-Path ($lc + "\ChannelManifest.json"))) {
        $lv = Read-LayoutVer $lc
        $layouts += [pscustomobject]@{ Path = $lc; Ver = $lv; MM = (Get-VsMM $lv) }
      }
    }
    # Layout de reference : celui du PROJET (installers\vslayout) sinon le plus RECENT.
    $projLayout = $layouts | Where-Object { $_.Path -like "*installers\vslayout" } | Select-Object -First 1
    $bestLayout = if ($projLayout) { $projLayout } elseif ($layouts.Count -gt 0) { ($layouts | Sort-Object { try { [version]$_.Ver } catch { [version]"0.0" } } -Descending | Select-Object -First 1) } else { $null }
    $sameBranch = if ($vsMM) { $layouts | Where-Object { $_.MM -and ($_.MM -eq $vsMM) } | Select-Object -First 1 } else { $null }
    $olderThanBest = $false
    if ($vsPresent -and $bestLayout -and $bestLayout.Ver -and $vsVer) { try { $olderThanBest = ([version]$vsVer -lt [version]$bestLayout.Ver) } catch {} }

    # --- Choix de l'operation + du layout, et faut-il une montee de version ($useUpdate) ?
    $chosenLayout = ""; $chosenVer = ""; $useUpdate = $false; $branchMismatch = $false
    if (-not $vsPresent) {
      if ($bestLayout) { $chosenLayout = $bestLayout.Path; $chosenVer = $bestLayout.Ver }
    } elseif (-not $vsBuildOk) {
      if ($sameBranch)         { $chosenLayout = $sameBranch.Path; $chosenVer = $sameBranch.Ver }              # complement simple (meme branche)
      elseif ($olderThanBest)  { $chosenLayout = $bestLayout.Path; $chosenVer = $bestLayout.Ver; $useUpdate = $true }  # montee de version + complement
      elseif ($layouts.Count -gt 0) { $branchMismatch = $true }
    } else {
      # VS present ET complet : RIEN a changer cote VS. On memorise quand meme le layout
      # de MEME branche s'il existe (passe en -LayoutPath a 01 : utile pour recuperer
      # signtool/composants hors ligne) - et surtout pour ne PAS afficher le message
      # contradictoire "aucun layout adapte detecte" alors qu'un layout vient d'etre vu.
      if ($sameBranch) { $chosenLayout = $sameBranch.Path; $chosenVer = $sameBranch.Ver }
    }

    Write-Host ""
    if (-not $vsPresent) {
      Write-Host "  Visual Studio 2022 est ABSENT de ce poste." -ForegroundColor Red
      if ($chosenLayout) { Write-Host ("  -> [2] l'INSTALLE hors ligne (--noWeb) depuis : " + $chosenLayout + "  (VS " + $(if($chosenVer){$chosenVer}else{"?"}) + ").") -ForegroundColor Red }
      else { Warn "  Aucun layout hors ligne detecte : [2] tentera par internet ; sinon lancez d'abord  .\scripts\06_layout.ps1 -Download." }
    } elseif (-not $vsBuildOk) {
      Write-Host ("  Visual Studio 2022 " + $(if($vsMM){"(branche " + $vsMM + ", " + $vsVer + ") "}else{""}) + "present MAIS il MANQUE des charges de build (Office/VSTO et/ou .NET desktop).") -ForegroundColor Red
      if ($useUpdate) {
        Write-Host ("  -> VS installe (" + $vsVer + ") plus ANCIEN que le layout (" + $chosenVer + "). [2] fait la MONTEE DE VERSION hors ligne (--noWeb) PUIS ajoute les charges, depuis : " + $chosenLayout + ".") -ForegroundColor Red
      } elseif ($chosenLayout) {
        Write-Host ("  -> [2] le COMPLETE hors ligne (--noWeb) depuis le layout de MEME branche : " + $chosenLayout + "  (VS " + $(if($chosenVer){$chosenVer}else{"?"}) + ").") -ForegroundColor Red
      } elseif ($branchMismatch) {
        Warn "  Layout(s) present(s) mais d'une AUTRE branche et pas plus recent(s) : completion hors ligne impossible ici. [2] tentera par internet si disponible."
        foreach ($lyt in $layouts) { Write-Host ("       layout present : " + $lyt.Path + "  -> VS " + $(if($lyt.Ver){$lyt.Ver}else{"?"}) + " (branche " + $(if($lyt.MM){$lyt.MM}else{"?"}) + ")") -ForegroundColor Yellow }
      } else {
        Warn "  Aucun layout hors ligne detecte : [2] tentera par internet ; sinon lancez d'abord  .\scripts\06_layout.ps1 -Download."
      }
    } else {
      Ok ("  Visual Studio 2022 " + $(if($vsMM){"(branche " + $vsMM + ") "}else{""}) + "present AVEC les charges de build (Office/VSTO + .NET desktop) : pret a compiler.")
      if ($olderThanBest) { Note ("  (VS installe " + $vsVer + " plus ancien que le layout " + $bestLayout.Ver + " ; non bloquant pour compiler. Montee de version manuelle possible : powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS -LayoutPath `"" + $bestLayout.Path + "`" -UpdateFirst)") }
    }
    Write-Host "  [1] Inventaire seul (lecture seule, ne modifie rien)" -ForegroundColor White
    Write-Host "  [2] Preparation CLE EN MAIN : installe le manquant, Visual Studio 2022 COMPRIS (layout ou internet)  [admin]"
    Write-Host "  [3] Installer les composants depuis installers\ (propose AUSSI Visual Studio s'il est absent)  [admin]"
    Write-Host "  [Entree] Passer cette etape"
    if (-not $isAdmin) { Note "  (fenetre NON administrateur : les options 2 et 3 ouvriront une fenetre elevee dediee)" }
    $pc = (Read-Host "  Choix").Trim()
    if ($pc -eq '3' -and -not $vsPresent) {
      # Desormais, -Install PROPOSE lui-meme l'installation de VS quand il
      # est absent (confirmation O/N). [2] reste le chemin recommande (tout automatique,
      # layout detecte et passe en -LayoutPath).
      Note "  Visual Studio est absent : [3] (-Install) proposera AUSSI son installation (confirmation O/N)."
      if (Ask-YesNo "Preferer [2] (cle en main : tout automatique, layout detecte) ?" $true) { $pc = '2' }
    }
    if ($pc -eq '1') {
      try { & powershell.exe -ExecutionPolicy Bypass -File $v01 } catch { Warn ("  Inventaire interrompu : " + $_.Exception.Message) }
      Note "  Rapport d'inventaire ecrit a la racine (inventaire-poste-*.txt) : a ranger dans reports\ au besoin."
    } elseif ($pc -eq '2' -or $pc -eq '3') {
      # VS absent -> -Setup (installe VS) ; VS present incomplet -> -CompleteVS (+ -UpdateFirst
      # si montee de version quand VS est plus ancien que le layout) ; [3] -> -Install
      # (composants ; propose aussi VS s'il est absent, avec
      # confirmation). Hors ligne (--noWeb) des qu'un -LayoutPath ADAPTE est fourni.
      $mode = if ($pc -eq '2') { if ($vsPresent) { "-CompleteVS" } else { "-Setup" } } else { "-Install" }
      $extra = @()
      if ($pc -eq '2' -and $chosenLayout) { $extra = @("-LayoutPath", $chosenLayout); if ($useUpdate) { $extra += "-UpdateFirst" } }
      # VALIDATION explicite : on ANNONCE l'action AVANT de l'executer.
      $act = switch ($mode) {
        "-Setup"      { "INSTALLER Visual Studio 2022" + $(if($chosenVer){" " + $chosenVer}else{""}) }
        "-CompleteVS" { $(if($useUpdate){"MONTER Visual Studio 2022 en version " + $chosenVer + " puis AJOUTER les charges manquantes"}elseif(-not $vsBuildOk){"COMPLETER Visual Studio 2022" + $(if($vsMM){" (branche " + $vsMM + ")"}else{""}) + " avec les charges manquantes"}else{"VERIFIER le poste - Visual Studio est deja COMPLET, rien n'y sera change ; recupere seulement le manquant hors VS (signtool, certificat de test...)"}) }
        default       { "installer les composants depuis installers\" + $(if(-not $vsPresent){" (Visual Studio ABSENT : son installation sera PROPOSEE, confirmation O/N)"}else{""}) }
      }
      $src = ""
      if ($mode -ne "-Install") {
        # VS deja complet : ne PAS parler d'internet/layout (rien a installer cote VS).
        if ($vsPresent -and $vsBuildOk -and -not $useUpdate) { $src = "" }
        elseif ($chosenLayout) { $src = " HORS LIGNE (--noWeb) depuis " + $chosenLayout }
        else { $src = " par INTERNET (aucun layout hors ligne detecte)" }
      }
      if (-not (Ask-YesNo ("Confirmer : " + $act + $src + " ?") $true)) {
        Info "  Operation annulee (aucune modification apportee au poste)."
      } elseif ($isAdmin) {
        Info ("  Lancement : 01_verification-poste.ps1 " + $mode + " " + ($extra -join ' ') + "  (cela peut etre long)...")
        try { & powershell.exe -ExecutionPolicy Bypass -File $v01 $mode @extra } catch { Warn ("  Installation interrompue : " + $_.Exception.Message) }
        # Banniere IMPOSSIBLE A RATER : sans elle, la question qui suit se perd sous
        # les dernieres lignes de l'installation et on croit que ca tourne encore.
        Write-Host ""
        Write-Host "  ==================================================================" -ForegroundColor Green
        Write-Host "  ETAPE 2/5 TERMINEE : plus AUCUNE installation en cours."            -ForegroundColor Green
        Write-Host "  ==================================================================" -ForegroundColor Green
      } else {
        Warn ("  " + $mode + " installe des composants : DROITS ADMINISTRATEUR requis.")
        if (Ask-YesNo "Ouvrir une fenetre PowerShell ADMINISTRATEUR pour lancer maintenant ?" $true) {
          try {
            $argline = "-NoExit -ExecutionPolicy Bypass -File `"$v01`" $mode"
            if ($pc -eq '2' -and $chosenLayout) { $argline += " -LayoutPath `"$chosenLayout`"" }
            if ($pc -eq '2' -and $useUpdate)    { $argline += " -UpdateFirst" }
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argline | Out-Null
            Warn "  Une fenetre ADMINISTRATEUR s'est ouverte : l'installation s'y deroule."
            Warn "  A la FIN, cette fenetre affiche une banniere 'TERMINE' bien visible."
            [void](Read-Host "  Quand vous la voyez, appuyez sur ENTREE *ICI* (dans CETTE fenetre-ci) pour continuer")
          } catch {
            Warn ("  Elevation impossible (" + $_.Exception.Message + "). Ouvrez PowerShell en admin et lancez :  powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 " + $mode + $(if($chosenLayout){" -LayoutPath `"$chosenLayout`""}else{""}) + $(if($useUpdate){" -UpdateFirst"}else{""}))
          }
        } else {
          Info ("  Installation ignoree. Vous pouvez la lancer plus tard :  powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 " + $mode + $(if($chosenLayout){" -LayoutPath `"$chosenLayout`""}else{""}) + $(if($useUpdate){" -UpdateFirst"}else{""}) + "  (PowerShell admin)")
        }
      }
    } else {
      Info "  Etape poste passee."
    }
    if (-not (Ask-YesNo "Continuer vers la configuration (etape 3/5) ? (Entree = oui)" $true)) { Warn "Interrompu a votre demande. branding.conf n'a pas ete modifie."; exit 0 }
  }
}

# ------------------------------------------------------------ 3/5 BRANDING
Titre "3/5  Personnalisation (branding.conf)"
Info  ("Fichier des valeurs : " + $conf)
Note  "  Edition de MASSE possible : ouvrez ce fichier dans Notepad/Notepad++ (chaque champ y est"
Note  "  commente avec sa valeur par defaut) au lieu de repondre ici - puis relancez simplement"
Note  "  l'assistant (ou ./scripts/02_customize.sh) pour appliquer. Le mode interactif ci-dessous"
Note  "  reste ideal pour quelques champs."
Info  "Pour chaque champ : Entree = garder la valeur affichee, tiret '-' = vider."
Note  "Interdit dans les textes : les guillemets doubles (les apostrophes sont OK)."

Write-Host ""
Write-Host "  -- Identite / deploiement --" -ForegroundColor White
Edit-Field "PRODUCT_NAME"        "Nom du produit"                 "installeur, DLL, 'Programmes et fonctionnalites' (pas le libelle du bouton)"
Edit-Field "COMPANY_NAME"        "Editeur / organisation"         "affiche comme editeur du logiciel"
Edit-Field "PRODUCT_DESCRIPTION" "Description courte"              "metadonnee de l'assembly"
Edit-Field "SUPPORT_URL"         "Lien de support"                "page http:// ou https:// UNIQUEMENT - JAMAIS mailto: (le projet Setup refuserait de charger) ; contact e-mail = REPORT_TO/CC"
Edit-Field "COPYRIGHT"           "Mention de copyright"           ""
Edit-Field "INSTALL_FOLDER"      "Sous-dossier d'installation"    "sous %ProgramFiles%\\<ICI>\\<produit>"
Edit-Field "MSI_BASENAME"        "Nom de base du MSI (sans espace)" "la version est ajoutee automatiquement : Nom-1.2.3.msi"

Write-Host ""
Write-Host "  -- Adresses & filtre interne --" -ForegroundColor White
Edit-Field "REPORT_TO"      "Adresse qui RECOIT les signalements (To)" "boite de l'equipe securite / abuse"
Edit-Field "REPORT_CC"      "Adresse en copie (Cc)"                    "'-' pour n'envoyer qu'au To"
Edit-Field "REGEX_INTERNAL" "Regex expediteur INTERNE"                 "avertit avant de signaler un collegue ; ex. (@mondomaine\.fr`$|@.*\.mondomaine\.fr`$)"

Write-Host ""
Note ("  Les TEXTES utilisateur (bouton, dialogues, accuse) se modifient AUSSI en masse :")
Note ("   - " + $conf + "   (champs UI_* : FR et EN, valeurs par defaut commentees)")
Note ("   - " + (Join-Path $ROOT "OutlookSpamAddin\Config.vb") + "   (TOUS les messages FR/EN)")
if (Ask-YesNo "Modifier les TEXTES affiches (bouton, dialogues, accuse de reception) ?" $false) {
  Write-Host ""
  Write-Host "  -- Ruban Outlook --" -ForegroundColor White
  Edit-Field "UI_BUTTON_FR"          "Libelle du bouton (FR)"            "2 a 4 mots, verbe d'action"
  Edit-Field "UI_BUTTON_EN"          "Libelle du bouton (EN)"            ""
  Edit-Field "UI_GROUP_FR"           "Nom du groupe ruban (FR)"          "etiquette sous le bouton"
  Edit-Field "UI_GROUP_EN"           "Nom du groupe ruban (EN)"          ""
  Edit-Field "UI_BUTTON_TIP_FR"      "Info-bulle courte (FR)"            "une phrase au survol"
  Edit-Field "UI_BUTTON_TIP_EN"      "Info-bulle courte (EN)"            ""
  Edit-Field "UI_BUTTON_SUPERTIP_FR" "Info-bulle detaillee (FR)"         "1 a 2 phrases d'aide"
  Edit-Field "UI_BUTTON_SUPERTIP_EN" "Info-bulle detaillee (EN)"         ""
  Note  "    Icone du bouton : icones fournies par Office (rien a livrer, suit le theme clair/sombre)."
  Note  "    Valeurs possibles : PermissionRestrict (defaut) | Risks | SourceControlRun |"
  Note  "                        FilePermissionView | CancelRequest"
  Edit-Field "BUTTON_ICON"           "Icone du bouton"                   "une des 5 valeurs ci-dessus ; toute autre est refusee par 02_customize.sh"
  Write-Host ""
  Write-Host "  -- Dialogues & rapport --" -ForegroundColor White
  Edit-Field "UI_CONFIRM_TITLE_FR"   "Titre de la confirmation (FR)"     "boite affichee avant l'envoi"
  Edit-Field "UI_CONFIRM_TITLE_EN"   "Titre de la confirmation (EN)"     ""
  Edit-Field "UI_REPORT_BODY_FR"     "Intro du rapport aux analystes (FR)" "vu par l'equipe securite, pas l'utilisateur"
  Edit-Field "UI_REPORT_BODY_EN"     "Intro du rapport aux analystes (EN)" ""
  Write-Host ""
  Write-Host "  -- Accuse de reception a l'utilisateur --" -ForegroundColor White
  Note  "    NB : le CORPS de l'accuse est deja ecrit et MIS EN FORME (sauts de ligne, italique)"
  Note  "    dans le code : Config.vb, constantes ackBody*. Les champs"
  Note  "    'Corps' ci-dessous VIDES = on garde ce texte mis en forme ; les remplir REMPLACE"
  Note  "    le corps par votre texte SIMPLE (sans mise en forme)."
  $pvOne  = Get-AckPreview "ackBodyOneFR"
  $pvMore = Get-AckPreview "ackBodyMoreFR"
  if ($pvOne)  { Note ("    Texte actuel (1 signalement, FR) : " + $pvOne) }
  if ($pvMore) { Note ("    Texte actuel (plusieurs, FR)     : " + $pvMore) }
  Edit-Field "UI_ACK_SUBJECT_FR"     "Objet de l'accuse (FR)"            ""
  Edit-Field "UI_ACK_SUBJECT_EN"     "Objet de l'accuse (EN)"            ""
  Edit-Field "UI_ACK_BODY_FR"        "Corps de l'accuse - 1 signalement (FR)" "vide = texte mis en forme de Config.vb (affiche ci-dessus)"
  Edit-Field "UI_ACK_BODY_EN"        "Corps de l'accuse - 1 signalement (EN)" "vide = texte mis en forme de Config.vb"
  Edit-Field "UI_ACK_BODY_MORE_FR"   "Corps de l'accuse - plusieurs (FR)" "GARDER le {0} = le nombre ; vide = texte de Config.vb (ci-dessus)"
  Edit-Field "UI_ACK_BODY_MORE_EN"   "Corps de l'accuse - plusieurs (EN)" "GARDER le {0} = le nombre ; vide = texte de Config.vb"
  Write-Host ""
  Write-Host "  -- Prefixes d'objet du rapport --" -ForegroundColor White
  Edit-Field "REPORT_SUBJECT_PREFIX"       "Prefixe objet du rapport"        "ex. [SPAM]"
  Edit-Field "REPORT_SUBJECT_PREFIX_ERROR" "Prefixe objet en cas d'erreur"   "ex. [SPAM-ERREUR]"
} else {
  Info "Textes affiches inchanges."
}

Save-BConf
Ok ("branding.conf enregistre : " + $conf)

# ------------------------------------------------------------ 4/5 CERTIFICAT
Titre "4/5  Certificat de signature de code"

function Read-ThumbFromDisk {
  $m = Select-String -Path $conf -Pattern '^\s*CERT_THUMBPRINT\s*=\s*"?([0-9A-Fa-f]+)"?' | Select-Object -First 1
  if ($m) { return $m.Matches[0].Groups[1].Value } else { return "" }
}
function Get-StoreCodeCerts {
  $l = @()
  $l += Get-ChildItem Cert:\CurrentUser\My  -CodeSigningCert -ErrorAction SilentlyContinue
  $l += Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue
  return $l
}
# Un certificat n'est repute "de TEST" QUE s'il est AUTO-SIGNE (Sujet = Emetteur).
# ATTENTION : ne JAMAIS classer par le nom (CN) - le vrai certificat d'entreprise
# peut porter le meme nom que le certificat de test local (ex. CN=TestBoutonAbuse).
function Is-TestCert($c){ return ($c.Subject -eq $c.Issuer) }

# Fiche detaillee d'un certificat : numero de serie, empreinte, duree, expiration.
function Show-CertDetails($c) {
  $days  = [int][math]::Floor(($c.NotAfter - (Get-Date)).TotalDays)
  $duree = [math]::Round((($c.NotAfter - $c.NotBefore).TotalDays)/365.25, 1)
  Info ("   Sujet        : " + $c.Subject)
  if ($c.FriendlyName) { Info ("   Nom convivial : " + $c.FriendlyName) }
  if ($c.Subject -eq $c.Issuer) { Warn "   Emis par     : lui-meme  [certificat AUTO-SIGNE]" }
  else                          { Info ("   Emis par     : " + $c.Issuer) }
  Info ("   Empreinte    : " + $c.Thumbprint)
  Info ("   No de serie  : " + $c.SerialNumber)
  Info ("   Validite     : du " + $c.NotBefore.ToString("dd/MM/yyyy") + " au " + $c.NotAfter.ToString("dd/MM/yyyy") + "  (duree totale " + $duree + " ans)")
  if     ($days -lt 0)  { Warn ("   Expiration   : EXPIRE depuis " + (-$days) + " jours !") }
  elseif ($days -le 90) { Warn ("   Expiration   : dans " + $days + " jours (pensez au renouvellement)") }
  else                  { Info ("   Expiration   : dans " + $days + " jours") }
}

# APERCU : lit un .p12 EN MEMOIRE (sans l'importer dans le magasin) pour afficher son
# identite AVANT toute conversion. DefaultKeySet = chargement ephemere, rien n'est
# persiste dans CurrentUser\My. Accepte un mot de passe SecureString. $null si echec
# (mot de passe incorrect, fichier illisible...).
function Peek-P12([string]$p12Path, $secpw) {
  try {
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
    return (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 @($p12Path, $secpw, $flags))
  } catch {
    return $null
  }
}

# Lit le mot de passe depuis un fichier attachments.desc : accepte le mot de passe
# seul, ou une phrase du type "... mot de passe ... : XXXX". $null si introuvable.
function Get-DescPassword([string]$descPath) {
  try { $raw = Get-Content -LiteralPath $descPath -Raw -ErrorAction Stop } catch { return $null }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match 'mot de passe' -or $line -match 'passphrase' -or $line -match 'password') {
      $idx = $line.LastIndexOf(':')
      if ($idx -ge 0 -and $idx -lt ($line.Length - 1)) {
        $v = $line.Substring($idx + 1).Trim()
        if ($v) { return $v }
      }
    }
  }
  $t = $raw.Trim()
  if ($t -and ($t -notmatch "[\r\n]")) { return $t }   # fichier = mot de passe seul
  return $null
}

# ---------------------------------------------------------------------------
# CHAINE du .p12 (retour terrain, poste neuf hors domaine) : l'import
# du seul certificat FEUILLE laissait de cote la chaine (racine + intermediaires
# de l'IGC) embarquee dans le .p12 -> a la compilation, la signature des
# manifestes echoue en MSB3482 « Une chaine de certificats n'a pas pu etre
# etablie vers une autorite racine de confiance » (le poste n'a jamais recu la
# PKI interne). On importe donc AUSSI les certificats SANS cle privee du .p12 :
# racine (Sujet = Emetteur) -> magasin 'Racines de confiance', autres ->
# 'Autorites intermediaires'. Magasin MACHINE si admin (profite a tous les
# comptes), sinon UTILISATEUR (Windows demandera confirmation pour une racine).
# Best-effort : ne fait jamais echouer l'import du certificat lui-meme.
function Import-ChaineP12([string]$p12Path, $motdepasse) {
  try {
    # X509Certificate2Collection.Import n'a PAS de surcharge SecureString (.NET
    # Framework) : decodage via BSTR, tampon zeroise aussitot, jamais ecrit sur disque.
    if ($motdepasse -is [System.Security.SecureString]) {
      $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($motdepasse)
      try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    } else { $pw = [string]$motdepasse }
    $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $col.Import($p12Path, $pw, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
    $pw = $null
    $cas = @($col | Where-Object { -not $_.HasPrivateKey })
    if ($cas.Count -eq 0) { Note "    (le .p12 n'embarque pas sa chaine : si MSB3482 'autorite racine' a la compilation, importer la racine/intermediaires de l'IGC)"; return }
    $adm = $false
    try { $adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator) } catch {}
    $loc = if ($adm) { "LocalMachine" } else { "CurrentUser" }
    if (-not $adm) { Note "    (fenetre non administrateur : chaine importee dans le magasin UTILISATEUR ; Windows peut demander confirmation pour la racine)" }
    foreach ($c in $cas) {
      $mag = if ($c.Subject -eq $c.Issuer) { "Root" } else { "CA" }
      try {
        $st = New-Object System.Security.Cryptography.X509Certificates.X509Store($mag, $loc)
        $st.Open("ReadWrite")
        if (-not $st.Certificates.Contains($c)) { $st.Add($c); Note ("    chaine importee (" + $loc + "\" + $mag + ") : " + $c.Subject) }
        else { Note ("    chaine deja presente (" + $loc + "\" + $mag + ") : " + $c.Subject) }
        $st.Close()
      } catch { Warn ("    chaine NON importee (" + $c.Subject + ") : " + $_.Exception.Message) }
    }
  } catch { Warn ("    lecture de la chaine du .p12 : " + $_.Exception.Message) }
}

# Convertit un .p12 en .pfx (meme mot de passe), l'importe dans CurrentUser\My
# (exportable). Renvoie le certificat importe, ou $null en cas d'echec.
# Importe AUSSI la chaine embarquee (Import-ChaineP12, correctif MSB3482).
function Convert-And-Import([string]$p12Path, [string]$password, [string]$pfxOut) {
  try {
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]"Exportable,PersistKeySet"
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 @($p12Path, $password, $flags)
    $bytes = $c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password)
    [System.IO.File]::WriteAllBytes($pfxOut, $bytes)
    $sec = ConvertTo-SecureString $password -AsPlainText -Force
    $imp = Import-PfxCertificate -FilePath $pfxOut -CertStoreLocation Cert:\CurrentUser\My -Password $sec -Exportable -ErrorAction Stop
    Import-ChaineP12 $p12Path $password
    if ($imp -is [array]) { return $imp[0] } else { return $imp }
  } catch {
    Warn ("    Echec conversion/import de " + (Split-Path $p12Path -Leaf) + " : " + $_.Exception.Message)
    return $null
  }
}

# Importe un .p12 avec un mot de passe SAISI A LA MAIN (SecureString - jamais en
# clair). Sert quand il n'y a pas de attachments.desc a cote du .p12.
function Import-P12Secure([string]$p12Path, $secpw, [string]$pfxOut) {
  try {
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]"Exportable,PersistKeySet"
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 @($p12Path, $secpw, $flags)
    $bytes = $c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $secpw)
    [System.IO.File]::WriteAllBytes($pfxOut, $bytes)
    $imp = Import-PfxCertificate -FilePath $pfxOut -CertStoreLocation Cert:\CurrentUser\My -Password $secpw -Exportable -ErrorAction Stop
    Import-ChaineP12 $p12Path $secpw
    if ($imp -is [array]) { return $imp[0] } else { return $imp }
  } catch {
    Warn ("    Echec import de " + (Split-Path $p12Path -Leaf) + " : " + $_.Exception.Message)
    return $null
  }
}

# SECURITE : durcit les ACL du dossier certs\ (il contient des .pfx avec CLE PRIVEE apres
# import). Coupe l'heritage et limite l'acces a l'utilisateur courant + Administrateurs
# (SID S-1-5-32-544) + SYSTEM (SID S-1-5-18). Best-effort : ne fait JAMAIS echouer le
# script si icacls renacle (droits, systeme de fichiers particulier...).
#
# IMPORTANT : les drapeaux d'heritage (OI)(CI) ne sont valides que sur un DOSSIER.
# Les appliquer a un FICHIER (via /T) fait ECHOUER le grant -> le fichier se retrouve
# avec une DACL VIDE : plus personne (meme pas vous, sans passer admin + prise de
# possession) ne peut le lire ou le supprimer. On procede donc en DEUX temps :
#   1) le DOSSIER recoit les ACE HERITABLES (OI)(CI) (moi / Administrateurs / SYSTEM) ;
#   2) le CONTENU existant est remis en HERITAGE (icacls /reset) -> il herite des 3 ACE
#      du dossier => DACL NON VIDE, vos certificats restent accessibles normalement.
function Protect-CertDir([string]$dir) {
  if (-not (Test-Path $dir)) { return }
  try {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    # 1) Dossier : heritage coupe + ACE HERITABLES pour moi / Administrateurs / SYSTEM.
    & icacls "$dir" /inheritance:r /grant:r ("{0}:(OI)(CI)F" -f $me) "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" /C /Q 2>$null | Out-Null
    $rc = $LASTEXITCODE
    # 2) Contenu existant : re-heritage du dossier durci (evite la DACL VIDE que
    #    laisserait un (OI)(CI) applique a un fichier). Saute si le dossier est vide.
    if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue).Count -gt 0) {
      & icacls "$dir\*" /reset /T /C /Q 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0 -and $rc -eq 0) { $rc = $LASTEXITCODE }
    }
    if ($rc -eq 0) { Ok  ("  ACL renforcees sur " + $dir + " (acces limite a vous, Administrateurs, SYSTEM ; vos fichiers restent accessibles).") }
    else           { Warn ("  ACL non appliquees sur " + $dir + " (icacls code " + $rc + ") - restreignez l'acces manuellement.") }
  } catch {
    Warn ("  Durcissement ACL ignore (" + $_.Exception.Message + ") - pensez a restreindre l'acces a " + $dir + " manuellement.")
  }
}

# Detecte les .p12, verifie le attachments.desc voisin, liste, propose, puis (si valide)
# convertit -> certs\*.pfx, importe, et PROPOSE de cabler CERT_THUMBPRINT (jamais auto).
function Invoke-P12Conversion([string]$certDir) {
  # SECURITE : par defaut, on ne ramasse les .p12 QUE dans le dossier certs\ du projet.
  # Elargir a Downloads/Desktop/Documents/C:\Dev laisserait un .p12 MALVEILLANT depose
  # dans ces dossiers detourner la signature du MSI -> on ne le fait pas automatiquement.
  $dirs = @($certDir) | Where-Object { Test-Path $_ }
  $p12s = @()
  if ($dirs.Count -gt 0) { $p12s = @(Get-ChildItem $dirs -Recurse -Depth 3 -Include *.p12 -ErrorAction SilentlyContinue | Select-Object -First 15) }
  if ($p12s.Count -eq 0) { return }

  # --- DEDOUBLONNAGE (evite de demander PLUSIEURS FOIS le mot de passe du MEME cert) :
  #  1) meme CHEMIN atteint par plusieurs racines (certs\ est aussi sous C:\Dev) ;
  #  2) meme CONTENU (SHA-256) : le script 01 COPIE les .p12 trouves vers certs\,
  #     donc le meme certificat existe en plusieurs exemplaires. On garde UN seul
  #     exemplaire par contenu, en PREFERANT celui qui a un attachments.desc
  #     (mot de passe lu automatiquement -> zero saisie).
  $seenPath = @{}
  $p12u = @()
  foreach ($f in $p12s) { $pk = $f.FullName.ToLower(); if (-not $seenPath.ContainsKey($pk)) { $seenPath[$pk] = $true; $p12u += $f } }
  $pre = @()
  foreach ($f in $p12u) {
    $desc = Join-Path $f.DirectoryName "attachments.desc"
    # -LiteralPath OBLIGATOIRE : un dossier contenant des crochets (ex.
    # "0000003255-[Emission]_...") ferait interpreter [Emission] comme un JOKER
    # par Test-Path, et le fichier present serait rapporte ABSENT a tort.
    $hasDesc = Test-Path -LiteralPath $desc
    $hash = ""
    try { $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch {}
    $pre += [pscustomobject]@{ P12 = $f.FullName; Base = $f.BaseName; Desc = $desc; HasDesc = $hasDesc; Hash = $hash }
  }
  $byHash = @{}
  foreach ($it in ($pre | Sort-Object -Property @{Expression={ if ($_.HasDesc) { 0 } else { 1 } }})) {
    $hk = if ($it.Hash) { $it.Hash } else { $it.P12.ToLower() }
    if (-not $byHash.ContainsKey($hk)) { $byHash[$hk] = $it }
  }
  $items = @($byHash.Values)
  $dupCount = $p12u.Count - $items.Count
  Write-Host ""
  Write-Host "  Certificat(s) .p12 detecte(s) :" -ForegroundColor White
  if ($dupCount -gt 0) { Note ("  (" + $dupCount + " copie(s) du meme fichier ignoree(s) - un seul exemplaire traite par certificat)") }
  foreach ($it in $items) {
    if ($it.HasDesc) {
      Info ("   - " + $it.P12)
      Note ("       mot de passe : lu dans " + $it.Desc)
      # APERCU AVANT CONVERSION : on lit l'identite du certificat EN MEMOIRE (aucun
      # import dans le magasin) pour DECIDER si on veut l'utiliser (CN, emetteur,
      # expiration...). Le mot de passe (attachments.desc) est converti en SecureString
      # le temps de la lecture, puis oublie.
      $pwPlain = Get-DescPassword $it.Desc
      if ($pwPlain) {
        $secPeek = ConvertTo-SecureString $pwPlain -AsPlainText -Force
        $pwPlain = $null
        $peek = Peek-P12 $it.P12 $secPeek
        $secPeek = $null
        if ($peek) {
          Show-CertDetails $peek
          if (Is-TestCert $peek) { Note "       (certificat AUTO-SIGNE -> profil certificat de TEST, a ne pas cabler pour la PROD)" }
          try { $peek.Dispose() } catch {}
          $peek = $null
        } else {
          Warn "       Lecture impossible (mot de passe attachments.desc incorrect ?) - a verifier."
        }
      } else {
        Warn "       Mot de passe introuvable dans attachments.desc -> identite affichee a la saisie manuelle."
      }
    } else {
      Warn ("   - " + $it.P12)
      Note ("       pas de attachments.desc -> le mot de passe sera DEMANDE ; l'identite du certificat s'affiche juste apres la saisie.")
    }
  }
  Note "  La conversion charge chaque .p12 (mot de passe : attachments.desc si present, sinon"
  Note "  saisie manuelle), le ré-exporte en .pfx dans certs\, et l'importe dans votre magasin"
  Note "  (CurrentUser\My) : indispensable pour signer les MANIFESTES pendant la compilation."
  if (-not (Ask-YesNo "Convertir et importer ce(s) certificat(s) .p12 maintenant ?" $true)) {
    Info "  Conversion .p12 ignoree."
    return
  }

  $imported = @()
  foreach ($it in $items) {
    $safeBase = ($it.Base -replace '[^A-Za-z0-9._-]', '_')
    $pfxOut = Join-Path $certDir ($safeBase + ".pfx")
    # a) mot de passe disponible dans attachments.desc -> conversion automatique
    if ($it.HasDesc) {
      $pw = Get-DescPassword $it.Desc
      if ($pw) {
        Write-Host ("  Conversion : " + (Split-Path $it.P12 -Leaf) + "  ->  certs\" + $safeBase + ".pfx")
        $c = Convert-And-Import $it.P12 $pw $pfxOut
        $pw = $null
        if ($c) { Ok ("    Importe - empreinte " + $c.Thumbprint); $imported += $c }
        continue
      }
      Warn ("  Mot de passe introuvable dans " + $it.Desc + " -> saisie manuelle.")
    }
    # b) pas de desc (ou desc illisible) -> SAISIE MANUELLE du mot de passe (SecureString)
    Warn ("  Pas de attachments.desc pour : " + (Split-Path $it.P12 -Leaf))
    if (-not (Ask-YesNo "  Saisir le mot de passe a la main pour importer ce .p12 ?" $true)) {
      Info "  Ignore (non importe)."; continue
    }
    $sec = Read-Host "  Mot de passe du .p12 (saisie masquee)" -AsSecureString
    if (-not $sec -or $sec.Length -eq 0) { Info "  Mot de passe vide -> ignore."; continue }
    # Identite du certificat AVANT import (lecture en memoire, rien n'est ecrit dans le magasin).
    $peek = Peek-P12 $it.P12 $sec
    if ($peek) {
      Info "  Identite du certificat :"
      Show-CertDetails $peek
      try { $peek.Dispose() } catch {}
      $peek = $null
      if (-not (Ask-YesNo "  Importer CE certificat ?" $true)) { Info "  Ignore (non importe)."; $sec = $null; continue }
    }
    Write-Host ("  Import : " + (Split-Path $it.P12 -Leaf) + "  ->  certs\" + $safeBase + ".pfx")
    $c = Import-P12Secure $it.P12 $sec $pfxOut
    $sec = $null
    if ($c) { Ok ("    Importe - empreinte " + $c.Thumbprint); $imported += $c }
  }

  if ($imported.Count -eq 0) { Warn "  Aucun certificat .p12 converti."; return }

  # SECURITE : au moins un .pfx (cle privee) vient d'etre ecrit dans certs\ -> durcir ses ACL.
  Protect-CertDir $certDir

  # Meme certificat importe plusieurs fois (copies du meme .p12) -> UNE entree
  # par EMPREINTE, sinon on afficherait a tort "plusieurs certificats importes".
  $imported = @($imported | Sort-Object Thumbprint -Unique)

  # SECURITE : on NE cable JAMAIS CERT_THUMBPRINT automatiquement. Un .p12 depose sur le
  # poste ne doit pas pouvoir devenir, SANS action explicite, le certificat qui signe
  # le MSI. On AFFICHE le certificat importe et on DEMANDE confirmation (defaut NON).
  $wireCert = $null
  if ($imported.Count -eq 1) { $wireCert = $imported[0] }
  else {
    $prodOnly = @($imported | Where-Object { $_.Subject -ne $_.Issuer })
    if ($prodOnly.Count -eq 1) { $wireCert = $prodOnly[0] }
  }
  if ($wireCert) {
    Write-Host ""
    Info "  Certificat importe :"
    Show-CertDetails $wireCert
    if ($wireCert.Subject -eq $wireCert.Issuer) { Note "  (certificat AUTO-SIGNE : s'il s'agit du certificat de TEST local, ne le cable pas pour la production)" }
    if (Ask-YesNo "Cabler cette empreinte dans branding.conf pour signer le MSI ?" $false) {
      BConf-Set "CERT_THUMBPRINT" $wireCert.Thumbprint
      Save-BConf
      Ok ("  CERT_THUMBPRINT cable dans branding.conf -> " + $wireCert.Thumbprint)
    } else {
      Info "  CERT_THUMBPRINT inchange (non cable)."
      Note ('   -> pour l''utiliser plus tard, renseignez dans branding.conf :  CERT_THUMBPRINT="' + $wireCert.Thumbprint + '"')
    }
  } else {
    Warn "  Plusieurs certificats importes - choisissez lequel utiliser :"
    foreach ($c in $imported) { Info ("   - " + $c.Subject + " | empreinte " + $c.Thumbprint) }
    Note "  -> renseignez l'empreinte voulue dans branding.conf (CERT_THUMBPRINT) ; sinon 03_sign refusera (choix ambigu)."
  }
  Warn "  SECURITE : supprimez tout attachments.desc (mot de passe EN CLAIR) du poste apres usage ; les .pfx (cle privee) restent dans certs\ avec ACL restreintes."
}

$certDir = Join-Path $ROOT "certs"
$testPfx = Join-Path $certDir "TestBoutonAbuse.pfx"

if (-not $doSign) {
  Warn "Construction SANS signature demandee (-NoSign) : etape certificat ignoree."
} else {
  # 4.0 - Conversion automatique des .p12 (avec attachments.desc) en .pfx, puis import + cablage.
  Invoke-P12Conversion $certDir

  $thumb = Read-ThumbFromDisk
  $store = Get-StoreCodeCerts
  $wired = $null
  if ($thumb) { $wired = $store | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1 }

  # Le certificat CABLE (CERT_THUMBPRINT) et TROUVE dans le magasin n'est JAMAIS
  # requalifie d'apres son nom : on affiche son EMETTEUR et on demande.
  $needAlternative = $false
  if ($wired -and -not (Is-TestCert $wired)) {
    Ok "Certificat de PRODUCTION configure (CERT_THUMBPRINT, present dans le magasin) - il signera le MSI :"
    Show-CertDetails $wired
  } elseif ($wired) {
    # Cable + trouve, mais AUTO-SIGNE : peut etre le certificat de TEST local
    # COMME un certificat d'entreprise livre auto-signe -> on ne prejuge pas.
    Info "Certificat configure (CERT_THUMBPRINT, present dans le magasin) :"
    Show-CertDetails $wired
    Warn "  NOTE : ce certificat est AUTO-SIGNE (Sujet = Emetteur)."
    Note "   - certificat livre par votre IGC/PKI : vous pouvez signer avec ;"
    Note "   - certificat de TEST genere par les scripts : a remplacer avant la production."
    if (-not (Ask-YesNo "Signer avec CE certificat pour cette generation ?" $true)) { $needAlternative = $true }
  } else {
    # Rien de cable/trouve : etat courant (test / aucun)
    if ($thumb) {
      Warn ("CERT_THUMBPRINT est renseigne (" + $thumb + ") mais ce certificat est INTROUVABLE dans le magasin.")
      Note  "  (l'etape de conversion .p12 ci-dessus permet de l'importer ; ou Import-PfxCertificate, puis relancez)"
    } else {
      $storeTest = $store | Where-Object { Is-TestCert $_ } | Select-Object -First 1
      if ($storeTest) {
        Info "CERT_THUMBPRINT vide : le certificat de TEST du magasin sera utilise pour signer :"
        Show-CertDetails $storeTest
      } elseif (Test-Path $testPfx) {
        Info ("Certificat de TEST present : " + $testPfx)
      } else {
        Info "Aucun certificat configure. 03_sign creera/utilisera un certificat de TEST auto-signe."
      }
    }
    if (Ask-YesNo "Garder le certificat de TEST pour cette generation ?" $true) {
      Info "OK : signature avec le certificat de test. Pensez a le remplacer par le vrai avant la production."
    } else { $needAlternative = $true }
  }

  if ($needAlternative) {
      # Lister les AUTRES certificats de code (magasin + disque) pour les placer au bon endroit.
      Write-Host ""
      Write-Host "  Recherche d'autres certificats de signature de code..." -ForegroundColor White
      $real = @($store | Where-Object { -not (Is-TestCert $_) })
      if ($real.Count -gt 0) {
        Info "  Dans le magasin Windows (utilisables directement via leur empreinte) :"
        foreach ($c in $real) {
          Info ("   - " + $c.Subject + " | empreinte " + $c.Thumbprint + " | expire " + $c.NotAfter)
          Note ("       -> pour l'utiliser : dans branding.conf, CERT_THUMBPRINT=" + '"' + $c.Thumbprint + '"')
        }
      } else {
        Info "  Aucun certificat de PRODUCTION dans le magasin Windows."
      }

      $pfxDirs = @("$env:USERPROFILE\Downloads","$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","C:\Dev",$certDir) | Where-Object { Test-Path $_ }
      $pfx = @()
      if ($pfxDirs.Count -gt 0) {
        $pfx = @(Get-ChildItem $pfxDirs -Recurse -Depth 3 -Include *.pfx,*.p12 -ErrorAction SilentlyContinue | Select-Object -First 15)
      }
      if ($pfx.Count -gt 0) {
        Info "  Fichiers de certificat trouves sur le disque (a deposer dans certs\ si c'est le bon) :"
        $certDirFull = (Resolve-Path $certDir -ErrorAction SilentlyContinue)
        if ($certDirFull) { $certDirFull = $certDirFull.Path }
        foreach ($f in $pfx) {
          $flag = ""
          if ($certDirFull -and $f.DirectoryName -eq $certDirFull) { $flag = "   [deja dans certs\]" }
          Info ("   - " + $f.FullName + $flag)
        }
        Note ("       -> destination du projet : " + $certDir)
      } else {
        Info "  Aucun fichier .pfx/.p12 trouve (Downloads, Desktop, Documents, C:\Dev, certs\)."
      }

      # PAUSE : le temps de recuperer / placer le certificat.
      Write-Host ""
      Warn "PAUSE - recuperez votre certificat de PRODUCTION, puis :"
      Info ("   1) deposez le fichier .pfx dans :  " + $certDir)
      Info  '   2) renseignez son empreinte dans branding.conf :  CERT_THUMBPRINT="....."'
      Note  "      (empreinte d'un certificat du magasin ci-dessus, ou empreinte du .pfx importe)"
      $wait = $true
      while ($wait) {
        Write-Host ""
        Write-Host "  [R] Reprendre (certificat place / branding.conf mis a jour)" -ForegroundColor White
        Write-Host "  [T] Construire quand meme avec le certificat de TEST"
        Write-Host "  [S] Construire SANS signature (-NoSign)"
        Write-Host "  [A] Abandonner (rien n'est construit)"
        $ch = (Read-Host "  Choix").Trim().ToUpper()
        if ($ch -eq 'R') {
          $thumb2 = Read-ThumbFromDisk
          $store2 = Get-StoreCodeCerts
          $w2 = $null
          if ($thumb2) { $w2 = $store2 | Where-Object { $_.Thumbprint -eq $thumb2 } | Select-Object -First 1 }
          if ($w2) {
            Ok "Certificat detecte (CERT_THUMBPRINT present dans le magasin) - il signera le MSI :"
            Show-CertDetails $w2
            if (Is-TestCert $w2) { Warn "  NOTE : certificat AUTO-SIGNE (Sujet = Emetteur) - verifiez que c'est bien celui voulu." }
            $wait = $false
          } elseif ($thumb2) {
            Warn ("CERT_THUMBPRINT=" + $thumb2 + " renseigne mais introuvable dans le magasin. Importez le .pfx (double-clic -> magasin CurrentUser) puis reessayez, ou choisissez T/S/A.")
          } else {
            Warn "CERT_THUMBPRINT est vide : renseignez l'empreinte du certificat dans branding.conf, puis [R]."
          }
        } elseif ($ch -eq 'T') {
          Info "OK : construction avec le certificat de TEST."
          $wait = $false
        } elseif ($ch -eq 'S') {
          Warn "OK : construction SANS signature. Vous pourrez signer plus tard avec .\scripts\03_sign.ps1."
          $doSign = $false
          $wait = $false
        } elseif ($ch -eq 'A') {
          Warn "Abandon. branding.conf a ete enregistre ; aucun MSI n'a ete construit."
          exit 0
        } else {
          Warn "  Choix invalide (R / T / S / A)."
        }
      }
  }
}

# ------------------------------------------------------------ 5/5 BUILD
Titre "5/5  Construction du MSI"
# Recapitulatif
$recTo = BConf-Get "REPORT_TO"; $recCc = BConf-Get "REPORT_CC"
Write-Host "  Recapitulatif :" -ForegroundColor White
Info ("   Produit       : " + (BConf-Get "PRODUCT_NAME") + "  (" + (BConf-Get "COMPANY_NAME") + ")")
Info ("   Version       : " + (BConf-Get "VERSION"))
Info ("   Signalements  : To=" + $recTo + $(if($recCc){"  Cc=" + $recCc}else{"  (sans Cc)"}))
Info ("   Signature     : " + $(if($doSign){"OUI"}else{"NON (-NoSign)"}))
Info ("   Configuration : " + $Configuration)

if ($NoBuild) {
  Info "Etape build ignoree (-NoBuild). Tout est pret : lancez .\scripts\04_build.ps1 quand vous voulez."
  exit 0
}
$build = Join-Path $PSScriptRoot "04_build.ps1"
if (-not (Test-Path $build)) { throw "04_build.ps1 introuvable dans scripts\." }

if (Ask-YesNo "Lancer maintenant le build complet (branding -> compilation -> MSI -> signature) ?" $true) {
  $bargs = @("-ExecutionPolicy","Bypass","-File",$build,"-Configuration",$Configuration)
  if (-not $doSign) { $bargs += "-NoSign" }
  & powershell.exe @bargs
  $rc = $LASTEXITCODE
  Write-Host ""
  if ($rc -eq 0) {
    Ok "TERMINE : configuration + build reussis."
    # --- Dossier release\ : instantane d'installation regroupe ----------------
    $relDirInfo = Join-Path $ROOT "release"
    if (Test-Path $relDirInfo) {
      Write-Host ""
      Write-Host "==== Dossier pret a distribuer : release\ ====" -ForegroundColor Cyan
      Ok   ("  Tout est regroupe ici : " + $relDirInfo)
      Info  "   MSI signe + RegistryConfig.reg + DoNotDisableAddinList.reg + vstor_redist.exe + notice LISEZ-MOI"
      Note  "   Copiez ce dossier tel quel sur le partage de deploiement ; les commandes ci-dessous visent le meme MSI."
    }
    # --- Commandes de deploiement silencieux (GPO / gestion de parc) --------
    $mb = BConf-Get "MSI_BASENAME"; if (-not $mb) { $mb = "Setup" }
    $mb = ($mb -replace '[^A-Za-z0-9._-]', '')
    $vv = BConf-Get "VERSION"
    $vd3 = if ($vv) { (($vv -split '\.')[0..2] -join '.') } else { "" }
    $msiOut = Join-Path $ROOT ("setup\" + $Configuration + "\" + $(if($vd3){"$mb-$vd3.msi"}else{"$mb.msi"}))
    Write-Host ""
    Write-Host "==== Deploiement silencieux (GPO / gestion de parc) ====" -ForegroundColor Cyan
    Info  "  A copier dans l'outil de deploiement (contexte SYSTEME, zero action utilisateur) :"
    Write-Host ('   Installer      : msiexec /i "' + $msiOut + '" /qn /norestart ALLUSERS=1')
    Write-Host ('   Avec journal   : msiexec /i "' + $msiOut + '" /qn /norestart ALLUSERS=1 /l*v "C:\Windows\Temp\' + $mb + '-install.log"')
    Write-Host ('   Desinstaller   : msiexec /x "' + $msiOut + '" /qn /norestart')
    Note  "  Sur les postes cibles, adaptez le chemin du MSI (partage reseau, cache SCCM/Intune...)."
    Note  "  Mise a jour = meme commande /i avec le MSI de version superieure."
    Note  "  ATTENTION : le MSI seul ne suffit pas - aucune adresse n'est codee dans le programme (fail-close)."
    Note  "  La cle registre HKLM 'To' est OBLIGATOIRE (resources\RegistryConfig.reg, GPO/ADMX) + VSTO Runtime present."
    Note  "  Le .cmd tout-en-un (deploy\install-silencieux.cmd) n'est qu'un emballage : tout outil de parc"
    Note  "  (SCCM/MECM, Intune, GPO...) peut faire ces etapes en taches natives - voir deploy\README.md."
    Note  "  Pas-a-pas GPO / SCCM / Intune : deploy/README.md et README (Deploiement en parc)"
  }
  else { Warn ("Le build s'est termine avec le code " + $rc + " - voir logs\build-*.log.") }
  exit $rc
} else {
  Info "Build non lance. Tout est configure ; lancez .\scripts\04_build.ps1 quand vous voulez."
}
