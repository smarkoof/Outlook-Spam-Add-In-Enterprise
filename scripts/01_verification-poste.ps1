# ============================================================================
#  01_verification-poste.ps1 — INVENTAIRE + INSTALLATION des prerequis.
#
#  Par defaut : INVENTAIRE EN LECTURE SEULE (ne modifie RIEN).
#  Vit dans scripts\ ; travaille toujours a la RACINE du projet.
#
#  Usage (PowerShell, a la RACINE du projet) :
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1              # inventaire seul (lecture seule)
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup       # CLE EN MAIN : installe VS 2022 si absent,
#                                                      #   complete VS, installe tout le manquant
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS  # complete VS (et l'INSTALLE s'il est absent), internet et/ou layout
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS -LayoutPath C:\vslayout   # layout precis
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS -LayoutPath C:\vslayout -UpdateFirst  # + montee de version hors ligne (VS plus ancien que le layout)
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS -Online                   # forcer internet
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Install       # installe depuis installers\ (confirmation ; propose aussi VS s'il est absent)
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Install -Auto # idem sans confirmation
#     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -MakeCert      # certificat de TEST + export certs\*.pfx
#
#  signtool : si deja present dans tools\signtool\ -> AUCUNE installation n'est tentee.
#  Sinon, -CompleteVS/-Setup le recupere en LEGER via NuGet (Microsoft.Windows.SDK.BuildTools)
#  dans tools\signtool\ — sans installer le SDK complet.
#
#  Certificats : tout .pfx/.p12 trouve sur le disque est signale ET copie automatiquement
#  dans certs\. Si AUCUN certificat n'existe (magasin + disque), un certificat de TEST
#  auto-signe est cree automatiquement (modes -Setup/-CompleteVS/-Install/-MakeCert) ;
#  il pourra etre remplace plus tard par le vrai certificat.
#
#  -Setup, -CompleteVS et -Install requierent les DROITS ADMINISTRATEUR.
#  Tout est journalise dans logs\ (transcription + journaux detailles de l'installeur VS).
#  Rapport : inventaire-poste-<MACHINE>-<AAAAMMJJ-HHMM>.txt (dossier du projet).
#  RETOUR : rapporter ce fichier vers le Mac, dossier reports\ du projet.
# ============================================================================
# [CmdletBinding()] : un parametre INCONNU (faute de frappe, ex. -LayouPath au lieu
# de -LayoutPath) est REFUSE avec un message clair, au lieu d'etre silencieusement
# ignore (et de laisser croire que l'option a ete prise en compte).
[CmdletBinding()]
param(
  [switch]$Install,     # tente d'installer les composants manquants (depuis installers\ ; VS compris s'il est absent)
  [switch]$Auto,        # n'affiche pas de confirmation avant chaque installation
  [switch]$CompleteVS,  # complete Visual Studio (l'installe s'il est ABSENT) : layout local ET/OU internet
  [string]$LayoutPath,  # chemin d'un layout precis (sinon recherche auto d'un dossier vslayout)
  [switch]$Online,      # force l'installation via internet (ignore le layout local)
  [switch]$Setup,       # CLE EN MAIN : installe VS 2022 si absent, complete VS, installe tout le manquant
  [switch]$UpdateFirst, # avec -CompleteVS : MONTEE DE VERSION hors ligne (update --noWeb depuis le layout) AVANT le modify, quand le VS installe est PLUS ANCIEN que le layout (ex. 17.4 -> 17.14)
  [switch]$MakeCert     # cree un certificat de signature de code de TEST (auto-signe) s'il n'y en a aucun
)
$ErrorActionPreference = "SilentlyContinue"
# RACINE du projet = dossier PARENT de scripts\ (ou vit ce script)
$ROOT = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ROOT "branding.conf"))) { $ROOT = $PSScriptRoot }  # repli : script encore a la racine

# --- Version de Visual Studio EXIGEE (optionnel) ---------------------------
#   ""      = accepte n'importe quel VS 2022 (17.x)  [defaut].
#   "17.14" = EXIGE cette version precise. Utile quand un LAYOUT hors ligne
#             impose 17.14 : une instance 17.4 ne peut PAS etre mise a jour
#             depuis un layout 17.14 (c'est le piege classique). En renseignant
#             ici la version de votre layout, le script signale tout ecart.
$EXPECTED_VS = ""

$R = New-Object System.Collections.Generic.List[string]
# Affichage colore (console uniquement ; le rapport reports\ reste sans couleur) :
#   ROUGE  = prerequis NECESSAIRE et ABSENT / manquant / introuvable / echec
#   ORANGE = point d'AVERTISSEMENT ou de SECURITE (a examiner, pas forcement bloquant)
#   VERT   = present / installe / OK
function L([string]$s){
  $R.Add($s)
  $u = $s.ToUpper()
  if ($u -match '^\s*AUCUN') { Write-Host $s -ForegroundColor Green; return }
  if ($u -match 'AVERTISSEMENT' -or $u -match 'SECURITE' -or $u -match 'REFUS' -or $u -match 'ATTENTION') { Write-Host $s -ForegroundColor Yellow; return }
  if (($u -notmatch 'OPTIONNEL') -and ($u -match 'ABSENT' -or $u -match 'MANQUANT' -or $u -match 'INTROUVABLE' -or $u -match 'ECHEC' -or $u -match 'ERREUR')) { Write-Host $s -ForegroundColor Red; return }
  if ($u -match 'PRESENT' -or $u -match 'INSTALLE' -or $u -match '\bOK\b') { Write-Host $s -ForegroundColor Green; return }
  Write-Host $s
}
function Titre([string]$t){
  foreach ($ln in @("", ("="*70), ("  " + $t), ("="*70))) { $R.Add($ln) }
  Write-Host ""
  Write-Host ("="*70) -ForegroundColor Cyan
  Write-Host ("  " + $t) -ForegroundColor Cyan
  Write-Host ("="*70) -ForegroundColor Cyan
}
# Lance un executable, ATTEND sa fin, retourne son code de sortie.
# ([System.Diagnostics.Process] direct : fiable la ou Start-Process echoue.)
# 3e parametre $vsProgress : pendant l'attente, affiche toutes les 30 s un battement
# de coeur (temps ecoule) + la DERNIERE OPERATION lue dans le journal dd_*.log le plus
# recent de %TEMP% (paquet en cours d'installation/verification) -> on VOIT ou en est
# l'installateur Visual Studio, meme sans interface. La ligne n'est repetee que si
# l'operation a change (pas de spam de console).
function RunWait([string]$exe, [string[]]$argv, [bool]$vsProgress=$false){
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (($argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $vsProgress) { $p.WaitForExit(); return $p.ExitCode }
    $t0 = Get-Date; $lastLine = ""
    L "  (suivi toutes les 30 s ; NB : un CLIC dans la fenetre fige l'affichage - touche Echap pour liberer)"
    while (-not $p.WaitForExit(30000)) {
      $el = [int]([Math]::Round(((Get-Date) - $t0).TotalMinutes))
      L ("  ... installation en cours (" + $el + " min ecoulees ; ne pas fermer cette fenetre)")
      try {
        $dd = Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        # (uniquement un journal ecrit PENDANT ce processus - pas un vieux dd_*.log d'une operation passee)
        if ($dd -and $dd.LastWriteTime -gt $t0) {
          $ln = (Get-Content $dd.FullName -Tail 40 -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match 'package|Applying|Executing|Download|Verif|Install' } |
                 Select-Object -Last 1)
          if ($ln) {
            $ln = ($ln -replace '^\s*\[[0-9a-fA-F:,\. ]*\]\s*','').Trim()
            if ($ln.Length -gt 120) { $ln = $ln.Substring(0,120) + "..." }
            if ($ln -ne $lastLine) { $lastLine = $ln; L ("      -> " + $ln) }
          }
        }
      } catch {}
    }
    return $p.ExitCode
  } catch { L ("  ERREUR lancement de '" + $exe + "' : " + $_.Exception.Message); return -1 }
}

# Compte combien des paquets demandes (par Id) sont presents dans un layout
# (dossiers nommes "<Id>,version=..."). Utilise avec les COMPOSANTS REELS de
# compilation (pas des workloads, qui n'ont PAS de dossier) pour CHOISIR
# AUTOMATIQUEMENT le layout le plus complet quand il y en a plusieurs.
function Get-LayoutWorkloadHits([string]$dir, [string[]]$workloadIds) {
  if (-not $dir -or -not (Test-Path $dir)) { return 0 }
  $hits = 0
  foreach ($w in $workloadIds) {
    $f = Get-ChildItem $dir -Directory -Filter ($w + "*") -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $hits++ }
  }
  return $hits
}

# Extrait "major.minor" d'une version ("17.14.36127.28" -> "17.14"). Sert a
# COMPARER la version INSTALLEE de VS a celle d'un LAYOUT : une mise a jour hors
# ligne n'aboutit que si les deux partagent le meme major.minor (piege 17.4 vs 17.14).
function VS-MajorMinor([string]$v) {
  if ($v -match '^\s*(\d+)\.(\d+)') { return ($Matches[1] + "." + $Matches[2]) }
  return ""
}

# Lit la version d'un LAYOUT VS hors ligne. Catalog.json porte
# info.productDisplayVersion / productSemanticVersion tout au DEBUT du fichier
# (souvent minifie sur UNE ligne, parfois enorme) : on ne lit que les 1ers Ko.
# Repli : ChannelManifest.json (version du produit dans channelItems).
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

# ---------------------------------------------------------------------------
#  SECURITE : verifie la signature Authenticode d'un binaire AVANT de
#  l'executer/l'utiliser. Refuse un fichier non signe ou alteré (hash). Sur un
#  poste hors-ligne, la revocation peut ne pas etre verifiable : on tolere alors
#  une signature presente mais non entierement validee (jamais un binaire
#  NON signe ni un HASH altere). $ExpectedPublisher (optionnel) impose l'editeur.
# ---------------------------------------------------------------------------
function Assert-TrustedBinary {
  param([string]$Path, [string]$ExpectedPublisher = "")
  if (-not (Test-Path -LiteralPath $Path)) { L ("  SECURITE : fichier introuvable -> " + $Path); return $false }
  $sig = $null
  try { $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop } catch { L ("  SECURITE : impossible de lire la signature (" + $_.Exception.Message + ") -> REFUS : " + $Path); return $false }
  switch ("$($sig.Status)") {
    "Valid"        { }
    "NotSigned"    { L ("  SECURITE : binaire NON SIGNE -> REFUS : " + $Path); return $false }
    "HashMismatch" { L ("  SECURITE : SIGNATURE ALTEREE (hash) -> REFUS : " + $Path); return $false }
    default {
      if (-not $sig.SignerCertificate) { L ("  SECURITE : signature absente/illisible (" + $sig.Status + ") -> REFUS : " + $Path); return $false }
      L ("  SECURITE : signature presente mais non entierement verifiee (" + $sig.Status + " ; hors-ligne ?) -> toleree pour : " + (Split-Path $Path -Leaf))
    }
  }
  if ($ExpectedPublisher -and $sig.SignerCertificate) {
    if ($sig.SignerCertificate.Subject -notmatch [regex]::Escape($ExpectedPublisher)) {
      L ("  SECURITE : editeur INATTENDU (" + $sig.SignerCertificate.Subject + ") ; attendu ~ '" + $ExpectedPublisher + "' -> REFUS : " + $Path); return $false
    }
  }
  L ("  Signature verifiee : " + (Split-Path $Path -Leaf) + $(if($sig.SignerCertificate){" [" + $sig.SignerCertificate.Subject.Split(',')[0] + "]"}else{""}))
  return $true
}

# ---------------------------------------------------------------------------
#  PATH : les INSTALLATEURS (Git...) modifient le PATH MACHINE dans le registre,
#  mais une session PowerShell DEJA OUVERTE garde son ancienne copie -> un
#  composant fraichement installe est rapporte a tort MANQUANT (retour terrain :
#  git declare ABSENT juste apres son installation). On recharge
#  donc $env:Path depuis le registre (Machine + User) au debut de l'inventaire
#  ET apres les installations de -Install.
# ---------------------------------------------------------------------------
function Rafraichir-Path {
  try {
    $pm = [Environment]::GetEnvironmentVariable("Path","Machine")
    $pu = [Environment]::GetEnvironmentVariable("Path","User")
    if ($pm -or $pu) { $env:Path = ((@($pm,$pu) | Where-Object { $_ }) -join ";") }
  } catch {}
}

$INST = Join-Path $ROOT "installers"
$missing = @{}   # cle -> $true si le composant est ABSENT

# Journalisation : transcription COMPLETE dans logs\ (survit a la fermeture du terminal)
$LOGDIR = Join-Path $ROOT "logs"
if (-not (Test-Path $LOGDIR)) { try { New-Item -ItemType Directory -Path $LOGDIR -ErrorAction Stop | Out-Null } catch { $LOGDIR = [Environment]::GetFolderPath("Desktop") } }
$LOG = Join-Path $LOGDIR ("verification-" + $env:COMPUTERNAME + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + $(if($Install){"-INSTALL"}else{""}) + ".log")
try { Start-Transcript -Path $LOG -Append -ErrorAction Stop | Out-Null; $script:TRANSCRIPT = $true } catch { $script:TRANSCRIPT = $false }

# PATH recharge depuis le registre AVANT l'inventaire : une session ouverte avant
# une installation (ex. Git) garderait sinon son ANCIEN PATH -> faux "MANQUANT".
Rafraichir-Path

L ("Inventaire du poste - " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
L ("Machine : " + $env:COMPUTERNAME + "   Utilisateur : " + $env:USERNAME)
L ("Mode : " + $(if($Install){"INSTALLATION (-Install)"}else{"INVENTAIRE lecture seule"}))
# Legende des couleurs (console)
$R.Add("Legende : VERT=present/OK  ROUGE=necessaire et ABSENT  ORANGE=avertissement/securite")
Write-Host "Legende : " -NoNewline
Write-Host "VERT=present/OK  " -ForegroundColor Green -NoNewline
Write-Host "ROUGE=necessaire et ABSENT  " -ForegroundColor Red -NoNewline
Write-Host "ORANGE=avertissement/securite" -ForegroundColor Yellow

# ---------------------------------------------------------------- 0) HORLOGE
# Une horloge fausse (poste neuf, VM, pile CMOS) casse la VALIDATION DES
# CERTIFICATS : installation VS en echec 5003 "InvalidCertificate", signatures
# Authenticode refusees, TLS en panne. Retour terrain : on verifie
# AVANT TOUT, plutot que de le decouvrir au milieu d'une installation.
Titre "0) Horloge systeme (indispensable aux certificats : VS, signatures, TLS)"
$now = Get-Date
L ("Date/heure du poste : " + $now.ToString("yyyy-MM-dd HH:mm") + "   (fuseau : " + ([TimeZoneInfo]::Local).Id + ")")
# Reference = fichier le plus RECENT du projet : si l'horloge du poste lui est
# ANTERIEURE (marge 26 h pour fuseaux/ete-hiver), elle est forcement en retard.
$refFile = $null
try {
  $refFile = Get-ChildItem -Path @((Join-Path $ROOT "scripts\*.ps1"),(Join-Path $ROOT "scripts\*.sh"),(Join-Path $ROOT "branding.conf"),(Join-Path $ROOT "*.md")) -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
} catch {}
$horlogeOK = $true
if ($refFile -and ($now -lt $refFile.LastWriteTime.AddHours(-26))) {
  $horlogeOK = $false
  L ("ERREUR : l'horloge du poste (" + $now.ToString("yyyy-MM-dd HH:mm") + ") est ANTERIEURE au fichier le plus recent du projet (" + $refFile.Name + " du " + $refFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + ") : elle est forcement FAUSSE (en retard).")
} elseif ($now.Year -lt 2024) {
  $horlogeOK = $false
  L ("ERREUR : annee aberrante (" + $now.Year + ") : horloge jamais reglee (poste neuf, VM, pile CMOS).")
} elseif ($refFile -and ($now -gt $refFile.LastWriteTime.AddDays(400))) {
  L ("AVERTISSEMENT : date du poste posterieure de PLUS D'UN AN au fichier le plus recent du projet (" + $refFile.Name + " du " + $refFile.LastWriteTime.ToString("yyyy-MM-dd") + ") : archive ancienne, ou horloge en AVANCE -> verifiez la date avant d'installer.")
}
if (-not $horlogeOK) {
  L "  CONSEQUENCE : certificats juges invalides -> installation VS en ECHEC 5003 (InvalidCertificate), signatures refusees, TLS en erreur."
  L ("  REMEDE (PowerShell ADMIN) :  Set-Date `"JJ/MM/AAAA HH:MM`"   <- mettez la date et l'heure REELLES")
  L ("  Fuseau horaire : verifier avec  tzutil /g   ; regler Paris avec  tzutil /s `"Romance Standard Time`"")
  L "  Puis RELANCEZ ce script. (Poste relie a un reseau avec serveur de temps :  w32tm /resync)"
} else {
  L "Horloge : coherente avec les fichiers du projet -> OK."
}

# ---------------------------------------------------------------- 1) WINDOWS
Titre "1) Windows (version exacte du systeme)"
$cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
L ("Produit        : " + $cv.ProductName)
L ("Build          : " + $cv.CurrentBuild + "." + $cv.UBR + "   (ReleaseId: " + $cv.ReleaseId + ")")
L ("Architecture   : " + $env:PROCESSOR_ARCHITECTURE)
L "INFO : build 14393 = generation LTSB2016/Server2016 -> .NET 4.8 NON integre d'origine."

# ------------------------------------------------------------- 2) .NET 4.x
Titre "2) .NET Framework (runtime + pack de ciblage)"
$rel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
$ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Version
$net = "inconnu"; if ($rel -ge 528040) { $net = "4.8 (ou +)" } elseif ($rel -ge 461808) { $net = "4.7.2" } elseif ($rel) { $net = "< 4.7.2" }
L ("Runtime .NET 4.x : Release=" + $rel + "  Version=" + $ver + "  => " + $net)
L "ATTENDU : Release >= 528040 (= .NET 4.8) pour EXECUTER l'add-in."
$missing["NET48RT"] = ($rel -lt 528040)
$tp48  = Test-Path "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
$tp472 = Test-Path "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.7.2"
L ("Pack de ciblage 4.8   (compilation) : " + $(if($tp48){"PRESENT"}else{"ABSENT"}))
L ("Pack de ciblage 4.7.2 (compilation) : " + $(if($tp472){"PRESENT"}else{"ABSENT"}))
L "ATTENDU : pack 4.8 PRESENT (le projet cible 4.8). Fourni par le 'Developer Pack .NET 4.8'."
$missing["NET48DEV"] = (-not $tp48)

# --------------------------------------------------------- 3) VISUAL STUDIO
Titre "3) Visual Studio 2022 (charges de travail, composants)"
$vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null; $wlDesk = $null; $wlOff = $null
# IMPORTANT : -all -prerelease pour detecter AUSSI une instance "incomplete"
# (frequent apres une installation hors ligne depuis un layout) que vswhere
# MASQUE par defaut -> sinon VS present est rapporte a tort comme ABSENT.
if (Test-Path $vsw) {
  $vsPath = (& $vsw -all -prerelease -products * -latest -property installationPath | Select-Object -First 1)
}
# Repli par le SYSTEME DE FICHIERS si vswhere ne renvoie rien (vswhere HS/instance non enregistree)
if (-not $vsPath) {
  foreach ($base in @("$env:ProgramFiles\Microsoft Visual Studio\2022", "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022")) {
    if (Test-Path $base) {
      $dv = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "Common7\IDE\devenv.exe" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
      if ($dv) { $vsPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dv))); break }
    }
  }
  if ($vsPath) { L ("AVERTISSEMENT : vswhere n'a rien renvoye, mais VS a ete trouve sur le disque -> " + $vsPath + " (instance peut-etre a reparer)") }
}
if ($vsPath) {
  $disp = (& $vsw -all -prerelease -products * -latest -property displayName | Select-Object -First 1)
  $ver  = (& $vsw -all -prerelease -products * -latest -property installationVersion | Select-Object -First 1)
  # Repli version : si vswhere n'a rien renvoye (instance non enregistree), lire
  # directement la version du binaire devenv.exe.
  if (-not $ver) {
    $dvx = Join-Path $vsPath "Common7\IDE\devenv.exe"
    if (Test-Path $dvx) { try { $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dvx).ProductVersion } catch {} }
  }
  L ("Edition        : " + $(if($disp){$disp}else{"Visual Studio 2022 (detecte par le disque)"}))
  L ("Chemin         : PRESENT -> " + $vsPath)
  # --- COMPARAISON DE VERSION explicite : ATTENDU vs DETECTE vs VERDICT -------
  $vsInstalledVer = "$ver"
  $vsMM = VS-MajorMinor $ver
  $attenduVS = if ($EXPECTED_VS) { "VS 2022 " + (VS-MajorMinor $EXPECTED_VS) + " (exige par EXPECTED_VS)" } else { "VS 2022 = 17.x (n'importe quelle 17.x convient)" }
  L ("Version - IL FAUT (ATTENDU) : " + $attenduVS)
  L ("Version - DETECTE (INSTALLE): " + $(if($ver){$ver + "   -> " + $(if($vsMM){"branche " + $vsMM}else{"branche ?"})}else{"inconnue"}))
  if (-not $vsMM) {
    L "Version - VERDICT          : AVERTISSEMENT : version illisible - impossible de confirmer VS 2022 (17.x)."
  } elseif ($vsMM -notmatch '^17\.') {
    L ("Version - VERDICT          : ERREUR : branche " + $vsMM + " -> ce N'EST PAS Visual Studio 2022 (17.x MANQUANT). VSTO exige VS 2022.")
  } elseif ($EXPECTED_VS -and ((VS-MajorMinor $EXPECTED_VS) -ne $vsMM)) {
    L ("Version - VERDICT          : AVERTISSEMENT (ECART) : il faut " + (VS-MajorMinor $EXPECTED_VS) + " mais " + $vsMM + " est installe -> mise a jour hors ligne impossible entre branches differentes.")
  } else {
    L ("Version - VERDICT          : OK -> " + $vsMM + " correspond a l'attendu (VS 2022 17.x).")
  }
  $wlDesk = (& $vsw -all -prerelease -products * -latest -requires Microsoft.VisualStudio.Workload.ManagedDesktop -property installationPath | Select-Object -First 1)
  $wlOff  = (& $vsw -all -prerelease -products * -latest -requires Microsoft.VisualStudio.Workload.Office -property installationPath | Select-Object -First 1)
  L ("Charge '.NET Desktop'        : " + $(if($wlDesk){"PRESENTE"}else{"ABSENTE"}))
  L ("Charge 'Office/SharePoint'   : " + $(if($wlOff){"PRESENTE"}else{"ABSENTE - indispensable pour VSTO !"}))
} else {
  $vsInstalledVer = ""
  L "Visual Studio 2022 : ABSENT (ni vswhere ni le disque ne le trouvent)."
}
$missing["VSOFFICE"]  = (-not $wlOff)
$missing["VSDESKTOP"] = (-not $wlDesk)

# --------------------------------------------- 4) SOURCE D'INSTALLATION VS
Titre "4) Source d'installation de VS (layout hors ligne) et cache"
Get-ChildItem "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances\*\state.json" | ForEach-Object {
  L ("state.json : " + $_.FullName)
  Select-String -Path $_.FullName -Pattern '"(channelUri|installChannelUri|layoutPath|installationVersion)"\s*:\s*"[^"]*"' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { L ("   " + $_.Value) }
}
$pk = Get-ChildItem "C:\ProgramData\Microsoft\VisualStudio\Packages" -Directory
L ("Cache de paquets : " + $(if($pk){ "" + $pk.Count + " dossiers" } else { "vide/absent" }))
L "INFO : channelUri/layoutPath = chemin du layout a rebrancher pour completer VS (charge Office, SDK)."

# 4bis) Le layout contient-il les CHARGES necessaires ? (crucial si le poste est HORS LIGNE)
# Decouverte LARGE : tout dossier "vslayout*" (donc vslayout-boutonspam, vslayout.2022...)
# sous C:\, Downloads, Documents et installers\ du projet, + -LayoutPath si fourni.
$layoutCands = @("C:\vslayout")
foreach ($base in @("C:\","$env:USERPROFILE\Downloads","$env:USERPROFILE\Documents",$ROOT,(Join-Path $ROOT 'installers'))) {
  if (Test-Path $base) { $layoutCands += (Get-ChildItem $base -Directory -Filter "vslayout*" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
}
if ($LayoutPath) { $layoutCands += $LayoutPath }
$layoutRoots = $layoutCands | Where-Object { $_ -and (Test-Path (Join-Path $_ "ChannelManifest.json")) } | Select-Object -Unique
if ($layoutRoots.Count -eq 0) {
  L "Layout : aucun ChannelManifest.json trouve (cherche : tout dossier vslayout* sous C:\, Downloads, Documents, installers\)."
} else {
  $vsInstMM = VS-MajorMinor $vsInstalledVer
  foreach ($lr in $layoutRoots) {
    # Le layout est-il COMPLET ? On verifie les COMPOSANTS REELS de compilation,
    # PAS des dossiers de "workloads" Office/.NET desktop : un workload n'a PAS de
    # dossier dans un layout (c'est une entree de CATALOGUE). Meme controle que
    # 06_layout.ps1 -> les deux scripts rendent desormais le MEME verdict.
    $reqComps = @(
      @{ Id = "Microsoft.Net.4.8.TargetingPack";                  Label = "pack de ciblage .NET 4.8" },
      @{ Id = "Microsoft.VisualStudio.Vsto.Runtime";              Label = "runtime VSTO (add-in Office)" },
      @{ Id = "Microsoft.CodeAnalysis.Compilers";                 Label = "compilateurs C#/VB (Roslyn)" },
      @{ Id = "Microsoft.VisualStudio.Templates.VB.ManagedCore";  Label = "modeles de projet VB.NET" }
    )
    $missComps = @($reqComps | Where-Object { @(Get-ChildItem $lr -Directory -Filter ($_.Id + ",*") -ErrorAction SilentlyContinue).Count -eq 0 } | ForEach-Object { $_.Label })
    $layoutComplete = ($missComps.Count -eq 0)
    $hasSetup  = @(Get-ChildItem $lr -Directory -Filter "*VisualStudio.Setup*" -ErrorAction SilentlyContinue).Count -gt 0
    $nb        = @(Get-ChildItem $lr -Directory -ErrorAction SilentlyContinue).Count
    $lv        = Get-LayoutVersion $lr
    $lvMM      = VS-MajorMinor $lv
    L ("Layout : " + $lr + "  (" + $nb + " paquets)")
    # Comparaison EXPLICITE layout <-> VS installe : LE piege hors ligne (17.4 vs 17.14).
    L ("   Version DISPONIBLE (layout) : " + $(if($lv){$lv + "   -> branche " + $(if($lvMM){$lvMM}else{"?"})}else{"inconnue"}))
    L ("   Version DETECTE (VS installe): " + $(if($vsInstalledVer){$vsInstalledVer + "   -> branche " + $(if($vsInstMM){$vsInstMM}else{"?"})}else{"aucun VS detecte"}))
    if ($lvMM -and $vsInstMM) {
      if ($lvMM -eq $vsInstMM) {
        L ("   VERDICT layout <-> VS       : OK -> memes branches (" + $lvMM + ") : completion/mise a jour hors ligne POSSIBLE.")
      } else {
        L ("   VERDICT layout <-> VS       : AVERTISSEMENT (ECART) : layout " + $lvMM + " != VS installe " + $vsInstMM + " -> 'update' hors ligne IMPOSSIBLE. Alignez les deux (recreez un layout " + $vsInstMM + ", ou mettez a jour VS vers " + $lvMM + " sur un poste connecte).")
      }
    } elseif ($lvMM -and -not $vsInstMM) {
      L ("   VERDICT layout <-> VS       : VS non detecte -> installez VS " + $lvMM + " depuis ce layout. Commande PRETE A COPIER (PowerShell ADMIN) :")
      L ("     powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup -LayoutPath `"" + $lr + "`"")
    }
    # Verdict base sur les COMPOSANTS REELS (VERT si tout est present).
    if ($layoutComplete) {
      L "   Composants de compilation dans le layout: PRESENTS (COMPLET : pack .NET 4.8, runtime VSTO, Roslyn, modeles VB.NET)"
    } else {
      L ("   Composants de compilation dans le layout: INCOMPLET -> composants ABSENTS : " + ($missComps -join ", "))
    }
    L ("   VS Installer (Setup) dans le layout     : " + $(if($hasSetup){"PRESENT"}else{"ABSENT"}))
  }
  $vsHasBuild = ([bool]$wlOff -and [bool]$wlDesk)   # VS a-t-il deja les charges Office + .NET desktop ?
  if ($layoutComplete) {
    L "OK : layout COMPLET -> il peut equiper un poste HORS LIGNE sans internet (detail : powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1)."
  } elseif ($vsHasBuild) {
    L "INFO : le layout ne servira qu'a equiper un poste hors ligne (composants a completer ci-dessus) ; VS est deja complet sur CE poste, aucun impact pour compiler ICI."
    L "       Pour equiper un poste hors ligne : powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download (poste connecte)."
  } else {
    L "layout INCOMPLET et charge aussi MANQUANTE dans VS -> completez le layout sur un poste CONNECTE :"
    L "       powershell -ExecutionPolicy Bypass -File .\scripts\06_layout.ps1 -Download   (verifie puis telecharge le manquant dans installers\vslayout)"
  }
}

# ------------------------------------------------- 5) EXTENSION VSIX SETUP
# Detection factorisee : composant enregistre (vswhere) OU manifeste d'extension sur
# disque (machine + utilisateur). Utilisee par l'inventaire ET par la verification
# POST-INSTALLATION de -Install (VSIXInstaller peut repondre OK sans avoir materialise
# le payload - vu sur Server 2016 : commit du cache seul, extension jamais posee).
function Get-InstallerProjectsExt {
  if ((Test-Path $vsw) -and $vsPath) {
    try {
      $extChk = & $vsw -all -prerelease -products * -latest -requires Component.VSInstallerProjects2022 -property installationPath 2>$null
      if ($extChk) { return "composant 'Component.VSInstallerProjects2022' enregistre dans VS (vu par vswhere)" }
    } catch {}
  }
  $vsixPat = "VSInstallerProjects|InstallerProjects|Installer Projects|DeploymentProject"
  $extDirs = @()
  if ($vsPath) { $extDirs += ("$vsPath\Common7\IDE\Extensions"); $extDirs += ("$vsPath\Common7\IDE\CommonExtensions") }
  $extDirs += "$env:LOCALAPPDATA\Microsoft\VisualStudio\17*\Extensions"
  $hit = Get-ChildItem $extDirs -Recurse -Filter "*.vsixmanifest" -ErrorAction SilentlyContinue | Select-String -Pattern $vsixPat -List -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.Path }
  return $null
}
Titre "5) Extension 'Installer Projects' (VSInstallerProjects2022)"
$found = Get-InstallerProjectsExt
if ($found) { L ("PRESENTE -> " + $found) }
else { L "ABSENTE (si vous venez de l'installer : ouvrez puis fermez Visual Studio une fois pour finaliser l'extension, puis relancez l'inventaire)" }
$missing["VSIX"] = (-not $found)

# ----------------------------------------------------- 6) VSTO RUNTIME
Titre "6) VSTO Runtime (execution des add-ins Office)"
$v1 = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VSTO Runtime Setup\v4R").Version
$v2 = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VSTO Runtime Setup\v4R").Version
# UNE seule des deux versions suffit (celle qui correspond a l'architecture
# d'Office) : l'absence de l'autre n'est PAS une erreur -> orange, pas rouge.
if ($v1 -or $v2) {
  $vstoList = @()
  if ($v1) { $vstoList += ("64 bits -> " + $v1) }
  if ($v2) { $vstoList += ("32 bits -> " + $v2) }
  L ("VSTO Runtime : PRESENT (" + ($vstoList -join "  |  ") + ")")
  if (-not $v1) { L "  AVERTISSEMENT (mineur) : variante 64 bits absente - sans impact si Office est en 32 bits (une seule variante, celle d'Office, suffit)." }
  if (-not $v2) { L "  AVERTISSEMENT (mineur) : variante 32 bits absente - sans impact si Office est en 64 bits (une seule variante, celle d'Office, suffit)." }
} else {
  L "VSTO Runtime (64 bits) : ABSENT"
  L "VSTO Runtime (32 bits) : ABSENT"
}
L "ATTENDU : present sur les postes qui EXECUTENT l'add-in. Pour compiler seul, pas bloquant."
$missing["VSTO"] = (-not ($v1 -or $v2))

# ----------------------------------------------------------- 7) OUTLOOK
Titre "7) Outlook (utile pour tester en local)"
# Detection LARGE : Outlook classique (MSI) ET Microsoft 365 / Click-to-Run.
$outlookPath = $null
# a) App Paths (le plus fiable, couvre MSI ET Click-to-Run) - valeur par defaut de la cle
foreach ($ap in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
                  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
                  "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE")) {
  $it = Get-Item -Path $ap -ErrorAction SilentlyContinue
  if ($it) { $p = $it.GetValue(""); if ($p -and (Test-Path $p)) { $outlookPath = $p; break } }
}
# b) InstallRoot des versions Office 16.0 (2016/2019/2021/365) et 15.0 (2013)
# NOTE : PowerShell est INSENSIBLE a la casse -> ne JAMAIS nommer une variable
# locale '$root' ici : elle ECRASERAIT $ROOT (racine du projet) pour tout le reste
# du script (outils re-telecharges au mauvais endroit, rapport egare, etc.).
if (-not $outlookPath) {
  foreach ($ir in @("HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\InstallRoot",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Outlook\InstallRoot",
                    "HKLM:\SOFTWARE\Microsoft\Office\15.0\Outlook\InstallRoot",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Outlook\InstallRoot")) {
    $olRoot = (Get-ItemProperty -Path $ir -Name "Path" -ErrorAction SilentlyContinue).Path
    if ($olRoot) { $olCand = Join-Path $olRoot "OUTLOOK.EXE"; $outlookPath = $(if (Test-Path $olCand) { $olCand } else { $olRoot }); break }
  }
}
# c) Enregistrement COM Outlook.Application (present des qu'Outlook est installe)
$outlookCom = (Test-Path "Registry::HKEY_CLASSES_ROOT\Outlook.Application") -or (Test-Path "HKLM:\SOFTWARE\Classes\Outlook.Application")
if ($outlookPath) {
  L ("Outlook : PRESENT -> " + $outlookPath)
} elseif ($outlookCom) {
  L "Outlook : PRESENT (COM Outlook.Application enregistre ; installe mais chemin exact non lu)"
} else {
  L "Outlook : ABSENT (OPTIONNEL : seulement pour TESTER l'add-in en local, pas pour compiler)"
}

# --------------------------------------------------------- 8) SIGNTOOL
Titre "8) signtool.exe (signature du MSI, etape 10)"
# Ordre de recherche : 1) tools\ du projet (copie NuGet)  2) PATH  3) SDK Windows installe
$st = Get-ChildItem (Join-Path $ROOT "tools") -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $st) { $st = (Get-Command signtool.exe).Source }
if (-not $st) { $st = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe | Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1 -ExpandProperty FullName }
L ("signtool : " + $(if($st){"PRESENT -> " + $st}else{"ABSENT - recuperable via internet (NuGet) ou composant 'SDK Windows' (layout VS)"}))
if ($st -and ($st -like (Join-Path $ROOT "tools*"))) { L "  (deja present dans tools\ du projet : AUCUN telechargement/installation ne sera tente)" }
$missing["SIGNTOOL"] = (-not $st)

# ------------------------------------------------------------- 9) GIT
Titre "9) Git pour Windows (execute 02_customize.sh)"
$g = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
# REPLI (retour terrain) : git installe mais PATH de la session pas
# (encore) a jour -> on sonde la cle de registre GitForWindows puis les
# emplacements standard, au lieu de conclure a tort "ABSENT".
$gHorsPath = $false
if (-not $g) {
  $gCands = @()
  foreach ($rk in @("HKLM:\SOFTWARE\GitForWindows","HKLM:\SOFTWARE\WOW6432Node\GitForWindows")) {
    $ip = (Get-ItemProperty $rk -ErrorAction SilentlyContinue).InstallPath
    if ($ip) { $gCands += (Join-Path $ip "cmd\git.exe") }
  }
  $gCands += @("$env:ProgramFiles\Git\cmd\git.exe","${env:ProgramFiles(x86)}\Git\cmd\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
  $g = $gCands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if ($g) {
    $gHorsPath = $true
    # rendre git utilisable DANS CETTE session (les NOUVELLES fenetres ont deja le bon PATH)
    $env:Path = (Split-Path -Parent $g) + ";" + $env:Path
  }
}
L ("git : " + $(if($g){ "PRESENT -> " + $g + "  (" + (& $g --version) + ")" } else {"ABSENT"}))
if ($gHorsPath) { L "  INFO : git etait installe mais pas dans le PATH de CETTE fenetre -> PATH de la session repare (aucune action requise)." }
$missing["GIT"] = (-not $g)

# ---------------------------------------------------- 10) CERTIFICATS
Titre "10) Certificats de signature de code (magasin + fichiers .pfx)"
$Q = [char]34
# a) dans le magasin Windows
$csU = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue)
$csM = @(Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue)
if ($csU.Count -or $csM.Count) {
  foreach ($c in $csU) { L ("  [magasin CurrentUser\My]  " + $c.Subject + " | empreinte: " + $c.Thumbprint + " | expire: " + $c.NotAfter) }
  foreach ($c in $csM) { L ("  [magasin LocalMachine\My] " + $c.Subject + " | empreinte: " + $c.Thumbprint + " | expire: " + $c.NotAfter) }
  $tp0 = (@($csU) + @($csM))[0].Thumbprint
  L ("  -> POUR LE PROJET : dans branding.conf mettez  CERT_THUMBPRINT=" + $Q + $tp0 + $Q)
  L ("  -> Ou exporte-le en .pfx dans certs\ :  Export-PfxCertificate -Cert Cert:\CurrentUser\My\" + $tp0 + " -FilePath .\certs\moncert.pfx -Password (Read-Host 'Mot de passe' -AsSecureString)")
} else { L "  Magasin Windows : aucun certificat de signature de code." }
# b) fichiers .pfx / .p12 presents sur le disque -> emplacement affiche + COPIE AUTO vers certs\
$certDir = Join-Path $ROOT "certs"
$pfxDirs = @("$env:USERPROFILE\Downloads","$env:USERPROFILE\Desktop","C:\Dev",$ROOT) | Where-Object { Test-Path $_ } | Select-Object -Unique
$pfx = Get-ChildItem $pfxDirs -Recurse -Include *.pfx,*.p12 -ErrorAction SilentlyContinue | Select-Object -First 15
if ($pfx) {
  L "  Fichiers certificat trouves sur le disque :"
  if (-not (Test-Path $certDir)) { try { New-Item -ItemType Directory -Path $certDir | Out-Null } catch {} }
  foreach ($f in $pfx) {
    $inCerts = ($f.DirectoryName -like ($certDir + "*"))
    if ($inCerts) { L ("     " + $f.FullName + "   [deja dans certs\]") }
    else {
      $target = Join-Path $certDir $f.Name
      # -LiteralPath OBLIGATOIRE : des crochets dans le chemin (ex. dossier
      # "0000003255-[Emission]_...") seraient interpretes comme des JOKERS par
      # Test-Path/Copy-Item -> fichier present rate, copie en echec silencieux.
      if (Test-Path -LiteralPath $target) { L ("     " + $f.FullName + "   [un fichier du meme nom existe deja dans certs\ : copie ignoree]") }
      else {
        try { Copy-Item -LiteralPath $f.FullName -Destination $target -ErrorAction Stop; L ("     " + $f.FullName + "   -> COPIE vers " + $target) }
        catch { L ("     " + $f.FullName + "   [ERREUR copie : " + $_.Exception.Message + "]") }
      }
    }
  }
  L "  -> Pour signer avec un fichier : powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -PfxPath .\certs\<fichier>.pfx -PfxPassword <mot de passe>"
} else { L "  Aucun fichier .pfx/.p12 trouve (Downloads, Desktop, C:\Dev, dossier du script)." }
$missing["CERT"] = (-not ($csU.Count -or $csM.Count -or $pfx))
if ($missing["CERT"]) { L "  -> AUCUN certificat : un certificat de TEST sera cree automatiquement (modes -Setup/-CompleteVS/-Install/-MakeCert)." }

# ------------------------------------------------- 11) NOTEPAD++ (optionnel)
Titre "11) Notepad++ (optionnel : lecture/edition des fichiers de conf)"
$npp = $null
foreach ($p in @("$env:ProgramFiles\Notepad++\notepad++.exe", "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe")) { if (Test-Path $p) { $npp = $p } }
L ("Notepad++ : " + $(if($npp){$npp}else{"ABSENT (optionnel - installable depuis installers\)"}))
$missing["NPP"] = (-not $npp)

# ------------------------------------ 11 bis) PYTHON (outillage : generation des GUID, scripts)
Titre "11 bis) Python (outillage : generation des GUID par customize.sh)"
# Ordre de recherche : 1) tools\python du projet (embarque)  2) python systeme REEL
# (le faux alias 'python' du Microsoft Store est EXCLU : il ne renvoie rien).
$py = $null
$pyEmb = Join-Path $ROOT "tools\python\python.exe"
if (Test-Path $pyEmb) { $py = $pyEmb }
if (-not $py) {
  foreach ($c in @((Get-Command python.exe -ErrorAction SilentlyContinue).Source, (Get-Command python3.exe -ErrorAction SilentlyContinue).Source)) {
    if ($c -and ($c -notlike "*WindowsApps*")) { $py = $c; break }
  }
}
L ("Python : " + $(if($py){"PRESENT -> " + $py}else{"ABSENT - sera embarque dans tools\python (modes action + internet)"}))
if ($py -and ($py -like (Join-Path $ROOT "tools*"))) { L "  (deja present dans tools\ du projet : AUCUN telechargement ne sera tente)" }
if (-not $py) { L "  (pas bloquant : customize.sh a des replis uuidgen/PowerShell/perl pour les GUID)" }
$missing["PYTHON"] = (-not $py)

# ------------------------------------------------------------ 12) DIVERS
Titre "12) Divers"
L ("PowerShell     : " + $PSVersionTable.PSVersion)
L ("Espace libre C:: " + [math]::Round((Get-PSDrive C).Free/1GB,1) + " Go")

# ============================================================================
#  SYNTHESE + (optionnel) INSTALLATION
# ============================================================================
Titre "SYNTHESE DES PREREQUIS MANQUANTS"
# Table des actions : cle -> [libelle, pattern fichier dans installers\, arguments, adminRequis]
$ACT = [ordered]@{
  "GIT"      = @("Git pour Windows",              "Git-*.exe",                    "/VERYSILENT /NORESTART /SP- /SUPPRESSMSGBOXES /NOCANCEL", $true)
  "NET48RT"  = @(".NET Framework 4.8 (runtime)",  "ndp48-x86-x64-allos-enu.exe",  "/q /norestart", $true)
  "NET48DEV" = @(".NET 4.8 Developer Pack (ciblage compil.)", "ndp48-devpack-enu.exe", "/q /norestart", $true)
  "VSTO"     = @("VSTO Runtime",                  "vstor_redist.exe",             "/q /norestart", $true)
  "VSIX"     = @("Extension Installer Projects",  "*.vsix",                       "", $false)
  "NPP"      = @("Notepad++ (optionnel)",         "npp.*.exe",                    "/S", $true)
}
$todo = @($ACT.Keys | Where-Object { $missing[$_] })
if ($todo.Count -eq 0) { L "Aucun composant installable manquant. (Verifier tout de meme les points ABSENTS ci-dessus.)" }
foreach ($k in $todo) {
  $lib = $ACT[$k][0]; $pat = $ACT[$k][1]
  $file = Get-ChildItem (Join-Path $INST $pat) -ErrorAction SilentlyContinue | Select-Object -First 1
  L (" - " + $lib + " : MANQUANT -> " + $(if($file){ "installateur present (" + $file.Name + ")" } else { "installateur ABSENT de installers\ (" + $pat + ")" }))
}
# Cas non couverts par un fichier isole
if (-not $vsPath) { L " - Visual Studio 2022 : ABSENT -> a installer depuis un LAYOUT hors ligne (voir installers\README.md, section 'Visual Studio hors ligne')" }
if ($missing["VSOFFICE"]) { L " - Charge 'Office/SharePoint' de VS : MANQUANTE -> via l'installeur Visual Studio + layout (voir ci-dessous)" }
if ($missing["SIGNTOOL"]) { L " - signtool (SDK Windows) : ABSENT -> via l'installeur Visual Studio + layout (composant 'SDK Windows')" }
if ($missing["VSOFFICE"] -or $missing["SIGNTOOL"]) {
  L ""
  L "   Commande type (a adapter au chemin de votre layout) :"
  L ('   "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe" modify \')
  L ('     --installPath "' + $(if($vsPath){$vsPath}else{"C:\Program Files\Microsoft Visual Studio\2022\Community"}) + '" \')
  L ('     --add Microsoft.VisualStudio.Workload.Office --add Microsoft.VisualStudio.Component.Windows10SDK \')
  L ('     --layoutPath "D:\VSlayout" --passive --norestart')
}

# ============================================================================
#  Variables partagees (admin + internet) et MODE CLE EN MAIN (-Setup)
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
# Test internet fiable : connexion TCP:443 (ICMP/ping est souvent bloque)
$net = $false
try {
  $tcp = New-Object Net.Sockets.TcpClient
  $ar = $tcp.BeginConnect("aka.ms",443,$null,$null)
  if ($ar.AsyncWaitHandle.WaitOne(3000,$false)) { $tcp.EndConnect($ar); $net = $true }
  $tcp.Close()
} catch { $net = $false }

# Certificats PUBLICS du layout (<layout>\certificates\*.cer) : sur un poste NEUF et
# HORS LIGNE, la chaine de confiance Microsoft peut manquer (aucun Windows Update pour
# la completer) -> la verification d'integrite/signature des paquets echoue (code 8005
# "verifying source payloads failed"). On les importe dans le magasin MACHINE "Racines
# de confiance" AVANT toute installation/completion hors ligne (admin deja requis).
# Best-effort : un echec d'import n'empeche pas de tenter l'installation (journalise).
function Import-LayoutCerts([string]$layRoot) {
  try {
    if (-not $layRoot) { return }
    $cdir = Join-Path $layRoot "certificates"
    if (-not (Test-Path $cdir)) { return }
    $cers = @(Get-ChildItem $cdir -Filter *.cer -File -ErrorAction SilentlyContinue)
    if ($cers.Count -gt 0) {
      L ("  Certificats publics du layout (" + $cers.Count + ") -> import magasin machine 'Racines de confiance' :")
      foreach ($c in $cers) {
        try {
          Import-Certificate -FilePath $c.FullName -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop | Out-Null
          L ("    importe : " + $c.Name)
        } catch { L ("    NON importe (" + $c.Name + ") : " + $_.Exception.Message) }
      }
    }
    # COMPLEMENTS optionnels : installers\certificates-extra\*.cer — intermediaires
    # Microsoft recoltes sur un poste CONNECTE (voir installers\README.md). Utiles sur
    # un OS ancien jamais mis a jour, dont le magasin ne peut pas construire la chaine
    # de signature du paquet OPC (echec 5003 "InvalidCertificate" malgre les racines).
    # Racine (Sujet = Emetteur) -> magasin 'Racines de confiance' ; sinon -> magasin
    # 'Autorites intermediaires' (CA).
    $xdir = Join-Path $ROOT "installers\certificates-extra"
    if (Test-Path $xdir) {
      $xcers = @(Get-ChildItem $xdir -Filter *.cer -File -ErrorAction SilentlyContinue)
      if ($xcers.Count -gt 0) {
        L ("  Certificats complementaires (installers\certificates-extra : " + $xcers.Count + ") :")
        foreach ($c in $xcers) {
          try {
            $x = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($c.FullName)
            $store = if ($x.Subject -eq $x.Issuer) { "Cert:\LocalMachine\Root" } else { "Cert:\LocalMachine\CA" }
            Import-Certificate -FilePath $c.FullName -CertStoreLocation $store -ErrorAction Stop | Out-Null
            L ("    importe (" + $(if($x.Subject -eq $x.Issuer){"Racines"}else{"intermediaires"}) + ") : " + $c.Name)
          } catch { L ("    NON importe (" + $c.Name + ") : " + $_.Exception.Message) }
        }
      }
    }
  } catch { L ("  Import des certificats du layout : " + $_.Exception.Message) }
}

# ---------------------------------------------------------------------------
#  INSTALLATION PRIMAIRE de Visual Studio 2022 (layout local, sinon internet).
#  FACTORISEE (retour terrain) : appelee par -Setup comme avant, et
#  DESORMAIS AUSSI par -CompleteVS et -Install quand VS est ABSENT - au lieu de
#  renvoyer l'utilisateur vers "lancez d'abord -Setup". Meme verification de
#  signature (Assert-TrustedBinary), memes journaux et replis (moteur, 5003).
#  Met a jour $script:vsPath / $script:wlDesk / $script:wlOff / $missing via la
#  re-detection finale. Retourne $true si VS est present a la fin.
# ---------------------------------------------------------------------------
$script:vsInstallTried = $false   # garde : UNE seule tentative par execution
function Installer-VS2022 {
  $script:vsInstallTried = $true
  Titre "Visual Studio 2022 ABSENT -> installation"
  if (-not $horlogeOK) {
    L "  ATTENTION : HORLOGE suspecte signalee en section 0 -> l'installation de VS echouera tres"
    L "  probablement en 5003 (InvalidCertificate). Corrigez la date (Set-Date) AVANT de continuer."
  }
  if (-not $isAdmin) { L "  ERREUR : droits administrateur requis pour installer VS." }
    else {
      $vsboot = $null; $vsman = $null
      # 1) layout LOCAL (ChannelManifest.json) + bootstrapper vs_*.exe (si pas -Online)
      if (-not $Online) {
        $lcands = @()
        if ($LayoutPath) { $lcands += $LayoutPath }                         # honore -LayoutPath
        $lcands += @((Join-Path $ROOT 'vslayout'),(Join-Path $ROOT 'installers\vslayout'),
                     "$env:USERPROFILE\Downloads\vslayout","C:\vslayout","C:\Dev\vslayout",
                     "$env:USERPROFILE\Desktop\vslayout","$env:USERPROFILE\Documents\vslayout")
        # dossiers 'vslayout*' (nommage par defaut de --layout : vslayout.2022.community)
        # ($scanBase, PAS '$root' : PowerShell est insensible a la casse -> $root ecraserait $ROOT !)
        foreach ($scanBase in @("$env:USERPROFILE\Documents","$env:USERPROFILE\Downloads","C:\","C:\Users\Administrateur\Documents","C:\Users\Public\Documents")) {
          try { Get-ChildItem $scanBase -Directory -Filter "vslayout*" -ErrorAction SilentlyContinue | ForEach-Object { $lcands += $_.FullName } } catch {}
        }
        foreach ($dl in 68..90) { $lcands += ([string][char]$dl + ":\vslayout") }   # D: a Z: (USB, partages)
        foreach ($c in ($lcands | Select-Object -Unique)) {
          # Concatenation (PAS Join-Path) : les candidats incluent des lecteurs D:..Z:
          # qui peuvent ne pas exister -> Join-Path leverait DriveNotFoundException.
          $cm = if ($c -match '\.json$') { $c } else { $c + "\ChannelManifest.json" }
          if (Test-Path $cm) {
            $cdir = Split-Path -Parent $cm
            # bootstrapper : d'abord DANS le layout, sinon dans installers\ du projet
            $b = Get-ChildItem $cdir -Filter "*.exe" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vs_(community|setup|professional|enterprise)' } | Select-Object -First 1
            if (-not $b) { $b = Get-ChildItem (Join-Path $ROOT 'installers') -Filter "*.exe" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'vs_(community|setup|professional|enterprise)' } | Select-Object -First 1 }
            if ($b) { $vsboot = $b.FullName; $vsman = $cm; L ("  Layout local : " + $cdir); L ("  Bootstrapper : " + $vsboot); break }
            else { L ("  Layout trouve (" + $cdir + ") mais AUCUN bootstrapper vs_*.exe (ni dans le layout, ni dans installers\).") }
          }
        }
        if (-not $vsboot) { L "  Aucun layout exploitable (ChannelManifest.json + bootstrapper vs_*.exe) trouve." }
      }
      # 2) sinon telechargement internet (canal 17 = VS 2022)
      if ((-not $vsboot) -and $net) {
        $vsboot = Join-Path $env:USERPROFILE "Downloads\vs_community.exe"
        L "  Telechargement de vs_community.exe (VS 2022) ..."
        try { & curl.exe -L --ssl-revoke-best-effort --retry 4 --retry-delay 5 -o $vsboot "https://aka.ms/vs/17/release/vs_community.exe" } catch {}
        if (-not (Test-Path $vsboot)) { try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest "https://aka.ms/vs/17/release/vs_community.exe" -OutFile $vsboot -UseBasicParsing } catch {} }
        if (-not (Test-Path $vsboot)) { $vsboot = $null }
      }
      if (-not $vsboot) { L "  IMPOSSIBLE d'obtenir l'installateur VS (ni layout local, ni internet)." }
      else {
        # Poste neuf hors ligne : importer d'abord les certificats publics du layout (anti-8005).
        if ($vsman) { Import-LayoutCerts (Split-Path -Parent $vsman) }
        $ilog = Join-Path $LOGDIR ("vs-install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
        # --passive (et non --quiet) : la FENETRE DE PROGRESSION officielle du Visual Studio
        # Installer s'affiche (barre + operation en cours), sans poser AUCUNE question.
        $iargs = @("--add","Microsoft.VisualStudio.Workload.ManagedDesktop","--add","Microsoft.VisualStudio.Workload.Office","--add","Microsoft.Net.Component.4.8.TargetingPack","--includeRecommended","--passive","--norestart","--wait")
        if ($vsman) { $iargs += @("--channelUri",$vsman,"--installChannelUri",$vsman,"--noWeb") }
        L ("  Installation de VS 2022 (" + $(if($vsman){"layout"}else{"internet"}) + ") ... journaux dans " + $LOGDIR)
        if (-not (Assert-TrustedBinary $vsboot "Microsoft")) {
          $rc = -1; L "  ECHEC SECURITE : l'installateur VS n'a pas passe la verification de signature -> non execute."
        } else {
          $rc = RunWait $vsboot $iargs $true
        }
        L ("  Code de sortie installation VS : " + $rc)
        if ($rc -ne 0 -and $rc -ne 3010) {
          # REPLI (vu sur un poste Server 2016 jamais mis a jour : bootstrapper en 5003
          # "InvalidCertificate" sur vs_installer.opc ALORS QUE les certificats du layout
          # sont importes -> la chaine OPC n'est pas validable sur un OS trop ancien).
          # Si le MOTEUR VS Installer est DEJA present sur le poste (tentative precedente),
          # on l'appelle DIRECTEMENT : 'setup.exe install' ne re-verifie pas vs_installer.opc.
          $engine = $null
          foreach ($d in @("${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer","$env:ProgramFiles\Microsoft Visual Studio\Installer")) {
            $h = $d + "\setup.exe"
            if (Test-Path $h) { $engine = $h; break }
          }
          # DEPLOIEMENT AUTOMATIQUE DU MOTEUR (retour terrain, poste Server 2022
          # patche : erreur 5003 malgre horloge OK + racines du layout +
          # certificates-extra importes, et AUCUN moteur present -> le repli ci-dessous
          # n'avait rien a appeler). vs_installer.opc est une archive zip dont Contents\
          # EST le dossier installe du VS Installer : la procedure moteur manuelle,
          # validee en reel, desormais AUTOMATISEE. Signature du setup.exe extrait verifiee AVANT execution.
          if ((-not $engine) -and ($rc -eq 5003) -and $vsman) {
            $opc = Join-Path (Split-Path -Parent $vsman) "vs_installer.opc"
            if (Test-Path -LiteralPath $opc) {
              L "  ECHEC 5003 sans moteur VS Installer -> DEPLOIEMENT AUTOMATIQUE du moteur depuis vs_installer.opc (le moteur ne re-verifie pas le paquet OPC du bootstrapper)."
              try {
                $xt = Join-Path $env:TEMP "vs_engine_extrait"
                try { if (Test-Path $xt) { Remove-Item $xt -Recurse -Force } } catch {}
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [IO.Compression.ZipFile]::ExtractToDirectory($opc, $xt)
                $srcEng = Join-Path $xt "Contents"
                $setupExt = Join-Path $srcEng "setup.exe"
                if ((Test-Path $setupExt) -and (Assert-TrustedBinary $setupExt "Microsoft")) {
                  $dstEng = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
                  New-Item -ItemType Directory -Force -Path $dstEng | Out-Null
                  Copy-Item (Join-Path $srcEng "*") $dstEng -Recurse -Force
                  if (Test-Path ($dstEng + "\setup.exe")) { $engine = $dstEng + "\setup.exe"; L ("  Moteur VS Installer deploye -> " + $engine) }
                  else { L "  Moteur NON deploye : copie incomplete (voir droits sur Program Files (x86))." }
                } else { L "  Moteur NON deploye : setup.exe extrait introuvable ou signature refusee." }
              } catch { L ("  Deploiement du moteur : ECHEC : " + $_.Exception.Message) }
            }
          }
          if ($engine -and (Assert-TrustedBinary $engine "Microsoft")) {
            L "  REPLI : moteur VS Installer present -> tentative DIRECTE 'setup.exe install' (ne re-verifie pas le paquet OPC du bootstrapper)."
            # SANS --wait : le moteur 'setup.exe install' REFUSE cette option (code 87
            # "L'option 'wait' est inconnue", vu en conditions reelles) —
            # --wait n'existe que sur le BOOTSTRAPPER ; RunWait attend de toute facon la
            # fin du processus. Et AVEC --noUpdateInstaller : hors ligne, le moteur ne
            # doit pas tenter de se mettre a jour lui-meme.
            $eargs = @("install","--productId","Microsoft.VisualStudio.Product.Community","--channelId","VisualStudio.17.Release","--installPath","$env:ProgramFiles\Microsoft Visual Studio\2022\Community","--noUpdateInstaller") + @($iargs | Where-Object { $_ -ne "--wait" })
            $rc = RunWait $engine $eargs $true
            L ("  Code de sortie repli moteur : " + $rc)
          } elseif ($rc -eq 5003) {
            L "  ECHEC 5003 (InvalidCertificate) et moteur indisponible : verifier horloge, certificats complementaires installers\certificates-extra, mise a jour Windows."
          }
        }
        Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 6 | ForEach-Object { Copy-Item $_.FullName $LOGDIR -Force -ErrorAction SilentlyContinue }
        # re-detecter VS et recalculer le manquant cote VS
        Start-Sleep -Seconds 3
        if (Test-Path $vsw) {
          # $script: : on est DANS une fonction -> sans ce prefixe, l'affectation
          # creerait une copie locale et le reste du script garderait "VS absent".
          $script:vsPath = & $vsw -all -prerelease -products * -latest -property installationPath
          $script:wlDesk = & $vsw -all -prerelease -products * -latest -requires Microsoft.VisualStudio.Workload.ManagedDesktop -property installationPath
          $script:wlOff  = & $vsw -all -prerelease -products * -latest -requires Microsoft.VisualStudio.Workload.Office -property installationPath
          $missing["VSDESKTOP"] = (-not $wlDesk); $missing["VSOFFICE"] = (-not $wlOff)
          $missing["NET48DEV"]  = (-not (Test-Path "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"))
        }
        L ("  VS apres installation : " + $(if($vsPath){$vsPath}else{"TOUJOURS ABSENT — voir le journal " + $ilog}))
      }
    }
  return [bool]$vsPath
}

if ($Setup) {
  Titre "MODE CLE EN MAIN (-Setup)"
  $CompleteVS = $true; $Install = $true; $Auto = $true
  L ("Internet : " + $(if($net){"OUI"}else{"NON (bascule sur layout local)"}))
  L ("Droits admin : " + $(if($isAdmin){"OUI"}else{"NON — relancez EN ADMINISTRATEUR !"}))
  # --- Installer Visual Studio 2022 s'il est ABSENT (routine factorisee) ---
  if (-not $vsPath) { [void](Installer-VS2022) }
  else { L ("Visual Studio deja present : " + $vsPath) }
}

if ($CompleteVS) {
  Titre "COMPLETER VISUAL STUDIO (-CompleteVS) : composants manquants, layout local et/ou internet"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
  if (-not $isAdmin) { L "ERREUR : lancez PowerShell EN ADMINISTRATEUR pour -CompleteVS." }
  else {
  # VS ABSENT ? -CompleteVS l'INSTALLE desormais LUI-MEME (retour terrain :
  # fini le renvoi vers "lancez d'abord -Setup") via la routine
  # factorisee de -Setup (Installer-VS2022 : layout local sinon internet,
  # signature verifiee). Si l'installation aboutit, la COMPLETION ci-dessous
  # s'enchaine dans la MEME execution.
  if ((-not $vsPath) -and (-not $script:vsInstallTried)) {
    L "Visual Studio introuvable -> installation PRIMAIRE integree, puis completion dans la foulee."
    [void](Installer-VS2022)
  }
  if (-not $vsPath) {
    L "ERREUR : Visual Studio toujours ABSENT apres la tentative d'installation (details ci-dessus, journaux dans logs\)."
    L "  -> Verifiez le layout (ChannelManifest.json + bootstrapper vs_*.exe dans installers\vslayout ou -LayoutPath),"
    L "     ou connectez le poste a internet, puis relancez la meme commande."
  }
  else {
    # 1) Composants VS reellement MANQUANTS -> liste --add ciblee
    $add = @()
    if ($missing["VSDESKTOP"]) { $add += "Microsoft.VisualStudio.Workload.ManagedDesktop" }
    if ($missing["VSOFFICE"])  { $add += "Microsoft.VisualStudio.Workload.Office" }
    if ($missing["NET48DEV"])  { $add += "Microsoft.Net.Component.4.8.TargetingPack" }
    if ($missing["SIGNTOOL"])  { $add += "Microsoft.VisualStudio.Component.Windows10SDK.20348"; $add += "Microsoft.VisualStudio.Component.Windows10SDK.19041" }

    # 1b) signtool SANS SDK : paquet NuGet Microsoft.Windows.SDK.BuildTools (quelques dizaines de Mo,
    #     aucune installation systeme). Evite le gros 'setup.exe modify' quand seul signtool manque.
    if ($missing["SIGNTOOL"] -and $net) {
      Titre "signtool via NuGet (leger, sans installation du SDK complet)"
      $nupkg = Join-Path $env:TEMP "sdk-buildtools.zip"
      $okDl = $false
      try { & curl.exe -L --ssl-revoke-best-effort --retry 4 --retry-delay 5 -o $nupkg "https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.BuildTools"; $okDl = ((Test-Path $nupkg) -and ((Get-Item $nupkg).Length -gt 1MB)) } catch {}
      if (-not $okDl) { try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest "https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.BuildTools" -OutFile $nupkg -UseBasicParsing -ErrorAction Stop; $okDl = ((Test-Path $nupkg) -and ((Get-Item $nupkg).Length -gt 1MB)) } catch { L ("  Telechargement NuGet : " + $_.Exception.Message) } }
      if ($okDl) {
        L ("  Telecharge : " + $nupkg + " (" + [math]::Round((Get-Item $nupkg).Length/1MB,1) + " Mo)")
        $xdir = Join-Path $env:TEMP "sdk-buildtools-extrait"
        try { if (Test-Path $xdir) { Remove-Item $xdir -Recurse -Force } } catch {}
        try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $xdir) } catch { L ("  ERREUR extraction : " + $_.Exception.Message) }
        $stExe = Get-ChildItem $xdir -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1
        if ($stExe -and -not (Assert-TrustedBinary $stExe.FullName "Microsoft")) {
          L "  ECHEC SECURITE : signtool.exe (NuGet) refuse (signature) -> non installe."
          $stExe = $null
        }
        if ($stExe) {
          $tdir = Join-Path $ROOT "tools"
          if (-not (Test-Path $tdir)) { try { New-Item -ItemType Directory -Path $tdir | Out-Null } catch {} }
          $dst = Join-Path $tdir "signtool"
          try { if (Test-Path $dst) { Remove-Item $dst -Recurse -Force } } catch {}
          try { Copy-Item $stExe.DirectoryName $dst -Recurse -Force } catch { L ("  ERREUR copie : " + $_.Exception.Message) }
          if (Test-Path (Join-Path $dst "signtool.exe")) {
            L ("  OK : signtool pret -> " + (Join-Path $dst "signtool.exe"))
            L "  (le SDK Windows complet n'est plus necessaire pour signer)"
            $missing["SIGNTOOL"] = $false
            $add = @($add | Where-Object { $_ -notmatch 'Windows10SDK' })
          }
        } else { L "  signtool.exe introuvable dans le paquet NuGet (structure inattendue)." }
      } else { L "  Telechargement NuGet impossible ; on tentera via l'installeur Visual Studio." }
    }

    if ($add.Count -eq 0) {
      L "Rien a completer cote Visual Studio : tous les composants suivis sont deja presents."
    } else {
      L ("Composants a ajouter : " + ($add -join ', '))

      # 2) Recherche d'un layout LOCAL (sauf si -Online) : on CHOISIT LE PLUS COMPLET,
      #    c.-a-d. celui qui contient le PLUS des charges demandees (pas juste le 1er trouve).
      $man = $null
      if (-not $Online) {
        # On score chaque layout par ses COMPOSANTS REELS de compilation (PAS par
        # des "workloads" : un workload n'a PAS de dossier dans un layout). Meme
        # liste que la section 4 et 06_layout.ps1 -> selection/verdict coherents.
        $reqCompIds = @("Microsoft.Net.4.8.TargetingPack","Microsoft.VisualStudio.Vsto.Runtime","Microsoft.CodeAnalysis.Compilers","Microsoft.VisualStudio.Templates.VB.ManagedCore")

        # dossiers candidats (l'ordre ne prime plus : c'est le CONTENU qui decide)
        $cands = @()
        if ($LayoutPath) { $cands += $LayoutPath }
        $cands += @((Join-Path $ROOT 'vslayout'),(Join-Path $ROOT 'installers\vslayout'),"$env:USERPROFILE\Downloads\vslayout","C:\vslayout","C:\Dev\vslayout","$env:USERPROFILE\Desktop\vslayout","$env:USERPROFILE\Documents\vslayout.2022.community")
        foreach ($root0 in @("$env:USERPROFILE\Documents","$env:USERPROFILE\Downloads","C:\","C:\Users\Administrateur\Documents")) {
          try { Get-ChildItem $root0 -Directory -Filter "vslayout*" -ErrorAction SilentlyContinue | ForEach-Object { $cands += $_.FullName } } catch {}
        }
        foreach ($dl in 68..90) { $cands += ([string][char]$dl + ":\vslayout") }   # D: a Z: (USB, partages)

        # scorer chaque layout par le nombre de charges demandees qu'il contient
        # ($layRoot, PAS '$root' : PowerShell est insensible a la casse -> $root
        #  ecraserait $ROOT et TOUS les chemins suivants partiraient dans le layout !)
        $bestHits = -1
        $seenLayouts = @{}
        foreach ($c in ($cands | Select-Object -Unique)) {
          if (-not $c) { continue }
          # Concatenation (PAS Join-Path) : les candidats incluent des lecteurs D:..Z:
          # qui peuvent ne pas exister -> Join-Path leverait DriveNotFoundException.
          $cm = if ($c -match '\.json$') { $c } else { $c + "\ChannelManifest.json" }
          if (-not (Test-Path $cm)) { continue }
          $layRoot = Split-Path -Parent $cm
          $lk = $layRoot.TrimEnd('\').ToLower()
          if ($seenLayouts.ContainsKey($lk)) { continue }   # deja evalue (dedup d'affichage)
          $seenLayouts[$lk] = $true
          $h = Get-LayoutWorkloadHits $layRoot $reqCompIds
          L ("  Layout candidat : " + $layRoot + "  -> " + $h + "/" + $reqCompIds.Count + " composant(s) de compilation present(s)")
          if ($h -gt $bestHits) { $bestHits = $h; $man = $cm }
        }
        if ($man) {
          L ("  Layout RETENU (le plus complet) : " + $man + "   (" + $bestHits + "/" + $reqCompIds.Count + " composants)")
          if ($bestHits -lt $reqCompIds.Count) {
            L "  ATTENTION : ce layout ne contient pas tous les composants de compilation. L'ajout"
            L "  hors ligne pourrait ECHOUER -> enrichis le layout sur un poste CONNECTE (voir la fin)."
          }
        } else {
          L "  Aucun layout local trouve."
        }
      }

      # 3) Internet (detection partagee) + ordre des tentatives
      L ("  Internet : " + $(if($net){"disponible"}else{"non detecte"}))
      # Localisation de setup.exe (VS Installer). vswhere.exe est deja localise et vit
      # dans le MEME dossier "Installer" -> on en derive setup.exe (le plus fiable),
      # avec Test-Path (le meme test qui a trouve vswhere). Diagnostic si introuvable.
      $setupExe = $null
      $instDirs = @()
      if ($vsw -and (Test-Path $vsw)) { $instDirs += (Split-Path -Parent $vsw) }
      $instDirs += "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
      $instDirs += "$env:ProgramFiles\Microsoft Visual Studio\Installer"
      foreach ($d in ($instDirs | Select-Object -Unique)) {
        if (-not $d) { continue }
        # Get-ChildItem (et pas Test-Path) : meme primitive que le diagnostic
        # ci-dessous -> detection et diagnostic ne peuvent plus se contredire.
        $hit = Get-ChildItem -LiteralPath $d -Filter "setup.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $setupExe = $hit.FullName; break }
      }
      if ($setupExe) {
        L ("  setup.exe (VS Installer) : PRESENT -> " + $setupExe)
      } else {
        L "  setup.exe (VS Installer) INTROUVABLE. Contenu des dossiers 'Installer' :"
        foreach ($d in ($instDirs | Select-Object -Unique)) {
          if ($d -and (Test-Path $d)) {
            $exes = (Get-ChildItem $d -Filter *.exe -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '
            L ("    " + $d + " -> " + $(if($exes){$exes}else{"(aucun .exe)"}))
          } elseif ($d) { L ("    " + $d + " -> (dossier absent)") }
        }
        L "  (S'il n'y a que vswhere.exe : le VS Installer est incomplet -> utilisez la METHODE GRAPHIQUE ci-dessous, ou reparez via 'Applications > Visual Studio Installer'.)"
      }
      # Repli si setup.exe (VS Installer) est ABSENT : le BOOTSTRAPPER vs_*.exe
      # (installers\ ou layout) REINSTALLE le VS Installer PUIS applique 'modify'.
      # Il accepte exactement les memes arguments que setup.exe.
      if (-not $setupExe) {
        $bsDirs = @((Join-Path $ROOT 'installers'), "$env:USERPROFILE\Downloads")
        if ($man) { $bsDirs += (Split-Path -Parent $man) }
        $bs = $null
        foreach ($bd in $bsDirs) {
          if (-not (Test-Path $bd)) { continue }
          $bs = Get-ChildItem $bd -Filter "*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'vs_(community|setup|professional|enterprise|boot)' } | Select-Object -First 1
          if ($bs) { break }
        }
        if ($bs -and $bs.FullName) {
          $setupExe = $bs.FullName
          L ("  Repli : VS Installer absent -> utilisation du bootstrapper : " + $setupExe)
          L "  (il REINSTALLE le Visual Studio Installer, puis ajoute les charges de travail)"
        } else {
          L "  Aucun bootstrapper vs_*.exe (installers\, Downloads, layout) : impossible de reparer le VS Installer automatiquement."
        }
      }
      $LO  = @{mode="LAYOUT (hors ligne) : $man"; web=$false; man=$man}
      $WEB = @{mode="INTERNET"; web=$true; man=$null}
      # Regle : -Online = internet seul ; -LayoutPath = layout puis internet ;
      #         defaut = internet d'abord (si dispo), sinon/echec -> layout local.
      $attempts = @()
      if ($Online)          { if ($net) { $attempts += $WEB } }
      elseif ($LayoutPath)  { if ($man) { $attempts += $LO }; if ($net) { $attempts += $WEB } }
      else                  { if ($net) { $attempts += $WEB }; if ($man) { $attempts += $LO } }
      if ($attempts.Count -eq 0) {
        L "  IMPOSSIBLE : ni layout local, ni internet. Fournis -LayoutPath, ou connecte le poste."
      }

      $ok = $false
      # SECURITE : ne JAMAIS lancer le programme
      # d'installation VS (setup.exe systeme OU bootstrapper de repli venant de
      # installers\/Downloads) sans verifier sa signature Authenticode Microsoft.
      if ($setupExe -and -not (Assert-TrustedBinary $setupExe "Microsoft")) {
        L "  REFUS : le programme d'installation VS retenu n'a pas passe la verification de signature -> non execute."
        $setupExe = $null
      }
      if (-not $setupExe) {
        L "  setup.exe introuvable/refuse : impossible de completer VS en ligne de commande (voir la methode GRAPHIQUE ci-dessous)."
      }
      # Poste hors ligne : certificats publics du layout dans le magasin machine (anti-8005).
      if ($man) { Import-LayoutCerts (Split-Path -Parent $man) }
      foreach ($a in $attempts) {
        if ($ok -or -not $setupExe) { break }
        Titre ("Tentative -> " + $a.mode)
        # -UpdateFirst : MONTEE DE VERSION hors ligne AVANT le modify. Quand le VS installe
        # est plus ANCIEN que le layout (ex. 17.4 -> 17.14), on ALIGNE d'abord VS sur la
        # version du layout ('update --noWeb --channelUri <layout>'), puis le 'modify --add'
        # ci-dessous fonctionne (meme branche). Uniquement sur une tentative LAYOUT (hors
        # ligne, $a.man present). Best-effort : un echec n'empeche pas de tenter le modify.
        if ($UpdateFirst -and (-not $a.web) -and $a.man) {
          $vsUp = @("update","--installPath",$vsPath,"--channelUri",$a.man,"--installChannelUri",$a.man,"--noWeb","--norestart","--passive","--wait")
          L ("  Montee de version hors ligne : setup.exe " + ($vsUp -join ' '))
          L ("  Journaux detailles VS : " + $LOGDIR + "   (ferme Visual Studio ; peut etre long)")
          $uc = RunWait $setupExe $vsUp $true
          Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 6 | ForEach-Object { Copy-Item $_.FullName $LOGDIR -Force -ErrorAction SilentlyContinue }
          if ($uc -eq 0 -or $uc -eq 3010) { L ("  Montee de version OK (code " + $uc + ").") }
          else { L ("  Montee de version : code " + $uc + " -> on tente quand meme l'ajout des charges (journaux " + $LOGDIR + ").") }
        }
        $vslog = Join-Path $LOGDIR ("vs-modify-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
        $vsArgs = @("modify","--installPath",$vsPath)
        foreach ($c in $add) { $vsArgs += @("--add",$c) }
        $vsArgs += @("--includeRecommended","--norestart","--passive","--wait")
        if (-not $a.web) { $vsArgs += @("--channelUri",$a.man,"--installChannelUri",$a.man,"--noWeb") }
        L ("  setup.exe " + ($vsArgs -join ' '))
        L ("  Journaux detailles VS : " + $LOGDIR + "   (ferme Visual Studio ; 10-20 min possibles)")
        $code = RunWait $setupExe $vsArgs $true
        Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 6 | ForEach-Object { Copy-Item $_.FullName $LOGDIR -Force -ErrorAction SilentlyContinue }
        if ($code -eq 0 -or $code -eq 3010) { L ("  OK (code " + $code + ")"); $ok = $true }
        elseif ($code -eq 1618) { L "  OCCUPE (1618) : fermez le Visual Studio Installer et reessayez." }
        elseif ($code -eq 1603) { L "  ECHEC (1603) : source incomplete." + $(if(-not $a.web){" On tente la suite (internet) si disponible."}else{""}) }
        else { L ("  ECHEC (code " + $code + ") : voir les journaux dans " + $LOGDIR) }
      }
      if ($ok) { L "" ; L "Visual Studio complete. Relancez l'inventaire (powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1) pour confirmer." }
      else {
        L "" ; L "Non complete en ligne de commande. METHODE MANUELLE (la plus fiable hors ligne) :"
        L "  Si vous ne trouvez PAS 'Visual Studio Installer' au menu Demarrer, c'est qu'il est absent :"
        L "  1) Double-clique le bootstrapper  installers\vs_Community.exe  -> il REINSTALLE le Visual Studio Installer."
        L "  2) La fenetre 'Visual Studio Installer' s'ouvre -> bouton MODIFIER sur Community 2022."
        L "  3) Onglet 'Charges de travail' : coche 'Developpement Office/SharePoint' ET 'Developpement .NET desktop', puis Installer."
        L "     (Si une source est demandee, pointe le layout : C:\vslayout ou installers\vslayout.)"
        L "  (Si une charge est GRISEE / 'package manquant' : le layout ne la contient pas -> recree-le sur un poste CONNECTE :"
        L "   vs_community.exe --layout C:\vslayout --add Microsoft.VisualStudio.Workload.Office --add Microsoft.VisualStudio.Workload.ManagedDesktop --includeRecommended --lang fr-FR en-US)"
      }
      L ("Journaux VS detailles : " + $LOGDIR)
    }
  }
  }
}

# --------- PYTHON EMBARQUE (tools\python) : modes action, si absent et internet disponible
if ($missing["PYTHON"] -and ($Setup -or $CompleteVS -or $Install) -and $net) {
  Titre "PYTHON EMBARQUE : recuperation dans tools\python (leger, sans installation systeme)"
  $pyUrl = "https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip"
  $pyZip = Join-Path $env:TEMP "python-embed.zip"
  $okPy = $false
  try { & curl.exe -L --ssl-revoke-best-effort --retry 4 --retry-delay 5 -o $pyZip $pyUrl; $okPy = ((Test-Path $pyZip) -and ((Get-Item $pyZip).Length -gt 1MB)) } catch {}
  if (-not $okPy) { try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest $pyUrl -OutFile $pyZip -UseBasicParsing -ErrorAction Stop; $okPy = ((Test-Path $pyZip) -and ((Get-Item $pyZip).Length -gt 1MB)) } catch { L ("  Telechargement : " + $_.Exception.Message) } }
  if ($okPy) {
    L ("  Telecharge : " + $pyZip + " (" + [math]::Round((Get-Item $pyZip).Length/1MB,1) + " Mo)")
    $pyDir = Join-Path $ROOT "tools\python"
    try { if (Test-Path $pyDir) { Remove-Item $pyDir -Recurse -Force } } catch {}
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory($pyZip, $pyDir) } catch { L ("  ERREUR extraction : " + $_.Exception.Message) }
    $pyExe = Join-Path $pyDir "python.exe"
    if ((Test-Path $pyExe) -and -not (Assert-TrustedBinary $pyExe "Python")) {
      L "  ECHEC SECURITE : python.exe refuse (signature) -> Python embarque non retenu."
      try { Remove-Item $pyDir -Recurse -Force } catch {}
    }
    if (Test-Path $pyExe) {
      L ("  OK : Python embarque -> " + $pyExe)
      L "  (customize.sh l'utilisera automatiquement pour generer les GUID)"
      $missing["PYTHON"] = $false
    }
  } else { L "  Telechargement impossible. PAS BLOQUANT : customize.sh a des replis PowerShell/perl." }
}

if ($Install) {
  Titre "INSTALLATION DES COMPOSANTS MANQUANTS (-Install)"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
  if ((-not $vsPath) -and (-not $script:vsInstallTried)) {
    # Retour terrain : -Install enchaine desormais LUI-MEME l'installation
    # primaire de Visual Studio (routine factorisee de -Setup, signature verifiee) au
    # lieu d'afficher "lancez d'abord -Setup" -> une seule commande, quel que soit
    # l'etat du poste. Grosse installation => confirmation (sauf -Auto).
    $goVS = $true
    if (-not $Auto) {
      $repVS = Read-Host "Visual Studio 2022 est ABSENT. L'installer maintenant (layout local sinon internet ; LONG : 30-60 min) ? (O/N)"
      if ($repVS -notmatch '^[OoYy]') { $goVS = $false; L "Installation de Visual Studio refusee : les composants qui en dependent seront sautes." }
    } else {
      L "Visual Studio 2022 ABSENT -> installation PRIMAIRE integree (layout local sinon internet)."
    }
    if ($goVS) { [void](Installer-VS2022) }
  }
  if (-not $vsPath) {
    L "ATTENTION : Visual Studio 2022 toujours ABSENT : l'extension Installer Projects (qui en"
    L "  depend) sera SAUTEE ; les autres composants de installers\ s'installent normalement."
  }
  # VS vient peut-etre d'etre installe AVEC le pack de ciblage 4.8 : on recalcule la
  # liste a installer ($missing a ete re-detecte par Installer-VS2022) pour ne pas
  # relancer inutilement un installateur deja couvert.
  $todo = @($ACT.Keys | Where-Object { $missing[$_] })
  $devenv = Get-Process devenv -ErrorAction SilentlyContinue
  foreach ($k in $todo) {
    $lib=$ACT[$k][0]; $pat=$ACT[$k][1]; $args=$ACT[$k][2]; $adm=$ACT[$k][3]
    $file = Get-ChildItem (Join-Path $INST $pat) -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) { L ("SKIP " + $lib + " : fichier absent de installers\ (" + $pat + ") — telechargez-le d'abord."); continue }
    if ($adm -and -not $isAdmin) { L ("SKIP " + $lib + " : DROITS ADMIN requis. Relancez PowerShell 'en tant qu'administrateur'."); continue }
    if ($k -eq "VSIX") {
      if ($devenv) { L "SKIP Extension : FERMEZ Visual Studio puis relancez."; continue }
      $vsix = "$vsPath\Common7\IDE\VSIXInstaller.exe"
      if (-not (Test-Path $vsix)) { L "SKIP Extension : VSIXInstaller.exe introuvable -> Visual Studio n'est pas (encore) installe. Relancez -Install (et acceptez l'installation de VS) ou -Setup, puis relancez -Install pour l'extension."; continue }
    }
    # SECURITE : verifier la signature Authenticode des installateurs .exe/.msi avant
    # execution (Git, VSTO, .NET, Notepad++, 7-Zip, Adobe... sont tous signes).
    if ($file.Extension -match '^\.(exe|msi)$') {
      if (-not (Assert-TrustedBinary $file.FullName)) { L ("SKIP " + $lib + " : signature non valide -> non installe (remplacez le fichier par la version officielle)."); continue }
    } elseif ($k -eq "VSIX") {
      # Un .vsix est un PAQUET OPC (une archive zip), PAS un executable : la signature
      # Authenticode (Get-AuthenticodeSignature) ne s'y applique pas -> la tester
      # produirait un faux negatif systematique ("UnknownError"). La signature INTERNE
      # du paquet est verifiee par VSIXInstaller.exe (composant Visual Studio signe
      # Microsoft) au moment de l'installation. On verifie donc VSIXInstaller, pas le .vsix.
      L "   INFO : .vsix = paquet OPC (zip) - signature Authenticode non applicable ; la signature INTERNE du paquet sera verifiee par VSIXInstaller (Microsoft) a l'installation."
      if (-not (Assert-TrustedBinary $vsix "Microsoft")) { L "SKIP Extension : VSIXInstaller.exe n'a pas passe la verification de signature -> non lance."; continue }
    }
    if (-not $Auto) {
      $rep = Read-Host ("Installer '" + $lib + "' depuis " + $file.Name + " ? (O/N)")
      if ($rep -notmatch '^[OoYy]') { L ("Ignore : " + $lib); continue }
    }
    L ("Installation de " + $lib + " ...")
    try {
      # RunWait + battement de coeur : temps ecoule toutes les 30 s, et derniere operation
      # du journal dd_*.log si l'installateur en ecrit un (VSIXInstaller le fait).
      if ($k -eq "VSIX") {
        $code = RunWait "$vsPath\Common7\IDE\VSIXInstaller.exe" @("/quiet", $file.FullName) $true
        # Journaux VSIXInstaller conserves dans logs\ (diagnostic sans aller fouiller %TEMP%).
        Get-ChildItem $env:TEMP -Filter "dd_VSIXInstaller*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 4 | ForEach-Object { Copy-Item $_.FullName $LOGDIR -Force -ErrorAction SilentlyContinue }
        # VERIFICATION REELLE : VSIXInstaller peut sortir 0 en n'ayant fait que du cache
        # (vu sur Server 2016 : "committed to VisualStudioExtensionCache" mais payload
        # jamais pose ; les tentatives /admin echouent hors ligne en "failed to download").
        if ($code -eq 0 -and -not (Get-InstallerProjectsExt)) {
          # REPLI (valide en conditions reelles) : le .vsix est une archive zip -> pose
          # DIRECTE a l'emplacement CANONIQUE de cette extension, CommonExtensions\Microsoft\VSI
          # (celui vise par VSIXInstaller ; il contient aussi DisableOutOfProcBuild.exe,
          # indispensable au build CLI des projets Setup - devenv "Parametre incorrect" sinon).
          L "  VSIXInstaller a repondu OK mais l'extension est INTROUVABLE sur disque -> REPLI : extraction a l'emplacement canonique + devenv /updateconfiguration."
          try {
            $zipTmp = Join-Path $env:TEMP "InstallerProjects2022.vsix.zip"
            Copy-Item $file.FullName $zipTmp -Force
            $dstExt = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\VSI"
            Expand-Archive $zipTmp $dstExt -Force
            # DATES : Expand-Archive pose les fichiers avec leur date D'ARCHIVE (ancienne).
            # Or le cache pkgdef de VS se fie aux dates ("PkgDefCache fast check:
            # timestamps are current") : des .pkgdef "vieux" ne seraient JAMAIS fusionnes,
            # meme par /updateconfiguration ou /setup (vu en reel : ActivityLog sans la
            # moindre mention du paquet). On rajeunit tout AVANT le mappage, pour que les
            # copies mappees heritent aussi de la date fraiche.
            $touchNow = Get-Date
            Get-ChildItem $dstExt -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { try { $_.LastWriteTime = $touchNow } catch {} }
            # DOSSIERS MAPPES : le vsix declare des 'folderMappings' (catalog.json) - des
            # dossiers $Xxx que l'installateur officiel REDIRIGE ailleurs dans VS (vu ici :
            # $PublicAssemblies -> Common7\IDE\PublicAssemblies, ou doit vivre
            # Microsoft.VisualStudio.DeployWizard.dll). Laisses sur place, le .vdproj
            # refuse de charger : "L'operation a ete annulee". On applique donc le mappage.
            try {
              $cat = Get-Content (Join-Path $dstExt "catalog.json") -Raw | ConvertFrom-Json
              $fmm = ($cat.packages | Where-Object { $_.folderMappings } | Select-Object -First 1).folderMappings
              if ($fmm) {
                foreach ($p in $fmm.PSObject.Properties) {
                  $srcMap = Join-Path $dstExt $p.Name
                  if (Test-Path -LiteralPath $srcMap) {
                    $dstMap = $p.Value -replace '\[installdir\]', $vsPath
                    if (-not (Test-Path -LiteralPath $dstMap)) { New-Item -ItemType Directory -Force -Path $dstMap | Out-Null }
                    Copy-Item (Join-Path $srcMap "*") $dstMap -Recurse -Force
                    Remove-Item -LiteralPath $srcMap -Recurse -Force
                    L ("  Dossier mappe applique : " + $p.Name + " -> " + $dstMap)
                  }
                }
              }
            } catch { L ("  AVERTISSEMENT : mappage des dossiers du vsix : " + $_.Exception.Message) }
            # ancienne extraction non canonique (versions precedentes du repli) : on la retire
            $oldExt = Join-Path $vsPath "Common7\IDE\Extensions\InstallerProjects2022"
            if (Test-Path $oldExt) { Remove-Item $oldExt -Recurse -Force -ErrorAction SilentlyContinue }
            # Caches PAR UTILISATEUR reconstruits au prochain demarrage de VS : on purge
            # l'etat fantome de VSIXInstaller (cache commite sans payload) + le cache MEF.
            Remove-Item "$env:LOCALAPPDATA\Microsoft\VisualStudio\VisualStudioExtensionCache" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Directory -Filter "17.0_*" -ErrorAction SilentlyContinue | ForEach-Object {
              Remove-Item (Join-Path $_.FullName "ComponentModelCache") -Recurse -Force -ErrorAction SilentlyContinue
              Remove-Item (Join-Path $_.FullName "Extensions") -Recurse -Force -ErrorAction SilentlyContinue
            }
            $devx = Join-Path $vsPath "Common7\IDE\devenv.exe"
            if (Test-Path $devx) {
              L "  Reconstruction du cache d'extensions (devenv /updateconfiguration - 1 a 3 min)..."
              [void](RunWait $devx @("/updateconfiguration") $true)
            }
            $dopb2 = Join-Path $dstExt "DisableOutOfProcBuild\DisableOutOfProcBuild.exe"
            if (Test-Path $dopb2) {
              # IMPORTANT : l'outil identifie l'instance VS d'apres le REPERTOIRE COURANT
              Push-Location (Split-Path $dopb2)
              try { & $dopb2 | Out-Null } finally { Pop-Location }
              L "  DisableOutOfProcBuild applique (prerequis du build CLI des projets Setup)."
            }
            if (Get-InstallerProjectsExt) { L "  Repli extraction : extension EN PLACE. Ouvrez puis fermez Visual Studio une fois, puis relancez l'inventaire." }
            else { L "  Repli extraction : fait, mais extension toujours indetectable -> ouvrez Visual Studio une fois puis relancez l'inventaire." }
          } catch { L ("  Repli extraction : ECHEC : " + $_.Exception.Message) }
        }
      }
      elseif ($args)     { $code = RunWait $file.FullName (@($args -split '\s+') | Where-Object { $_ }) $true }
      else               { $code = RunWait $file.FullName @() $true }
      if ($code -eq 0)        { L ("   OK (" + $lib + ")") }
      elseif ($code -eq 3010) { L ("   OK (" + $lib + ") — REDEMARRAGE requis pour finaliser.") }
      else                    { L ("   ECHEC (" + $lib + ") code=" + $code + " — voir le journal de l'installateur.") }
    } catch { L ("   ERREUR (" + $lib + ") : " + $_.Exception.Message) }
  }
  # Les installateurs viennent peut-etre de modifier le PATH machine (ex. Git) :
  # on RECHARGE le PATH de cette session et on re-verifie tout de suite, pour que
  # la fin du rapport ne montre plus un composant installe comme "MANQUANT".
  Rafraichir-Path
  if ($missing["GIT"]) {
    $g2 = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if (-not $g2) { $g2 = @("$env:ProgramFiles\Git\cmd\git.exe","${env:ProgramFiles(x86)}\Git\cmd\git.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
    if ($g2) { $missing["GIT"] = $false; L ("Verification post-installation : git PRESENT -> " + $g2) }
  }
  L ""
  L "Relancez le script SANS -Install pour confirmer que tout est maintenant PRESENT."
} elseif (-not $CompleteVS) {
  Titre "POUR AGIR (fenetre PowerShell EN ADMINISTRATEUR)"
  L "CLE EN MAIN (tout installer d'un coup) :"
  L "   powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Setup"
  L "Ou etape par etape :"
  L "   powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -CompleteVS      (complete Visual Studio)"
  L "   powershell -ExecutionPolicy Bypass -File .\scripts\01_verification-poste.ps1 -Install         (composants de installers\)"
  L "Tout est journalise dans logs\ (survit a la fermeture du terminal)."
}

# ------------- CERTIFICAT DE TEST (auto des qu'un mode ACTION tourne et qu'aucun certificat n'existe)
if ($MakeCert -or (($Setup -or $CompleteVS -or $Install) -and $missing["CERT"])) {
  Titre "CERTIFICAT DE SIGNATURE DE CODE (TEST, auto-signe)"
  if (-not $missing["CERT"]) { L "  Un certificat existe deja (voir section 10) : rien a creer." }
  else {
    $cert = $null
    try { $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=TestBoutonAbuse" -FriendlyName "Certificat de TEST - Bouton Spam" -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(3) -ErrorAction Stop }
    catch { L ("  ERREUR creation : " + $_.Exception.Message) }
    if ($cert) {
      L ("  Cree dans le magasin CurrentUser\My : " + $cert.Subject)
      L ("  Empreinte (thumbprint) : " + $cert.Thumbprint)
      L ("  -> Dans branding.conf, mettez :  CERT_THUMBPRINT=" + $Q + $cert.Thumbprint + $Q)
      $certDir = Join-Path $ROOT "certs"
      if (-not (Test-Path $certDir)) { try { New-Item -ItemType Directory -Path $certDir | Out-Null } catch {} }
      $pfxOut = Join-Path $certDir "TestBoutonAbuse.pfx"
      try {
        # SECURITE : mot de passe ALEATOIRE genere a chaque execution (plus de secret code en dur).
        $chars = (48..57) + (65..90) + (97..122)
        $pfxPwd = -join ($chars | Get-Random -Count 20 | ForEach-Object { [char]$_ })
        $pwdSec = ConvertTo-SecureString $pfxPwd -AsPlainText -Force
        Export-PfxCertificate -Cert ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -FilePath $pfxOut -Password $pwdSec -ErrorAction Stop | Out-Null
        L ("  Exporte : " + $pfxOut)
        L ("  MOT DE PASSE (genere, NOTEZ-LE, il ne sera plus affiche) : " + $pfxPwd)
      } catch { L ("  ERREUR export PFX : " + $_.Exception.Message) }
      L "  ATTENTION : certificat de TEST uniquement — a REMPLACER plus tard par le vrai certificat d'entreprise"
      L "  (il suffira de deposer le vrai .pfx dans certs\ : il ecrasera/remplacera celui de test)."
      $missing["CERT"] = $false
    }
  }
}

# ------------------------------------------------------------- RAPPORT
$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$nom   = "inventaire-poste-" + $env:COMPUTERNAME + "-" + $stamp + ".txt"
$dest  = Join-Path $ROOT $nom
try   { $R | Out-File -FilePath $dest -Encoding UTF8 -ErrorAction Stop }
catch { $dest = Join-Path ([Environment]::GetFolderPath("Desktop")) $nom ; $R | Out-File -FilePath $dest -Encoding UTF8 }
L ""
L ("Rapport enregistre : " + $dest)
if ($script:TRANSCRIPT) { L ("Journal complet (transcription) : " + $LOG) }
L "RETOUR DU RAPPORT : rapportez ce fichier (cle USB) vers le Mac, dossier reports\ du projet."
# Banniere de FIN impossible a rater (retour utilisateur : sans elle, on attend alors
# que tout est fini — la fenetre elevee ouverte par l'assistant reste sur un prompt,
# et la question suivante de l'assistant se perd sous les dernieres lignes).
if ($Setup -or $Install -or $CompleteVS -or $MakeCert) {
  Write-Host ""
  Write-Host "======================================================================" -ForegroundColor Green
  Write-Host "  TERMINE : plus AUCUNE operation en cours dans cette fenetre."         -ForegroundColor Green
  Write-Host "  (Fenetre ouverte par l'assistant ? Retournez dans la fenetre de"       -ForegroundColor Green
  Write-Host "   l'assistant et appuyez sur ENTREE la-bas pour continuer.)"            -ForegroundColor Green
  Write-Host "======================================================================" -ForegroundColor Green
}
if ($script:TRANSCRIPT) { try { Stop-Transcript | Out-Null } catch {} }
