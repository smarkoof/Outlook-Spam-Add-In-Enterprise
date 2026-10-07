#Requires -Version 5.1
<#
=========================================================================
 93_generate-icons.ps1 - construit UN MSI PAR ICONE, en une seule passe.

 POURQUOI : comparer les icones du ruban demande de construire, installer,
 regarder, desinstaller, recommencer. Quand le poste de build et le poste de
 test ne communiquent pas, chaque iteration coute un aller-retour physique.
 Ce script construit toutes les variantes d'affilee et les rassemble dans un
 seul dossier : un seul transfert, puis on compare sur place.

 Chaque MSI porte le nom de son icone. Tous partagent la meme identite
 produit : ils s'installent donc l'un APRES l'autre, jamais ensemble - c'est
 voulu, on compare un bouton a la fois dans le ruban.

 UTILISATION (a la racine du projet, Visual Studio ferme)
   .\scripts\93_generate-icons.ps1
   .\scripts\93_generate-icons.ps1 -Icones Risks,CancelRequest
   .\scripts\93_generate-icons.ps1 -Simulation        # n'ecrit rien, ne construit rien
   .\scripts\93_generate-icons.ps1 -SansSignature     # plus rapide, voir l'AVERTISSEMENT
   .\scripts\93_generate-icons.ps1 -SansBarre         # affichage direct, sans barre
   .\scripts\93_generate-icons.ps1 -Commandes         # refait INSTALLER.txt, SANS rien reconstruire

 INSTALLATION : aucun script n'accompagne les paquets. Le dossier de sortie
 recoit un INSTALLER.txt qui donne, pour chaque icone, les deux lignes
 msiexec a copier-coller - installation et desinstallation - avec le
 ProductCode et l'etat de signature du paquet. msiexec est un outil du
 systeme : il passe la ou un .ps1 serait refuse par AppLocker ou SRP.

 -Commandes sert quand les MSI sont deja la et qu'on veut seulement
 regenerer INSTALLER.txt : il relit les paquets presents dans essais-icones\,
 y reprend ProductName, ProductCode et signature, en quelques secondes au
 lieu de relancer toute la passe.

 SUIVI DE L'AVANCEMENT : une barre d'etat affiche l'icone en cours, l'etape de
 04_build.ps1 (1/5 a 5/5), le temps ecoule, le temps restant estime et la
 derniere ligne produite par le build. devenv.com pouvant rester muet plusieurs
 minutes d'affilee, le temps CPU consomme par devenv est affiche aussi : s'il
 augmente, la compilation travaille. Pour cela le build tourne dans un processus
 separe et sa sortie complete part dans logs\93-<icone>-<horodatage>.log ; en cas
 d'echec, les dernieres lignes sont reaffichees a l'ecran. Avec -SansBarre, le
 build s'execute en direct comme si on l'avait lance a la main.

 AVERTISSEMENT sur -SansSignature : si votre poste de test exige un editeur
 approuve, un paquet non signe donne un bouton qui NE SE CHARGE PAS. Vous
 conclueriez a tort que l'icone est en cause. Ne l'utilisez que sur un poste
 dont vous savez qu'il tolere les complements non signes.

 Le reglage BUTTON_ICON d'origine est RESTAURE en fin d'execution, y compris
 si un build echoue : votre branding.conf ressort tel que vous l'aviez laisse.
=========================================================================
#>
[CmdletBinding()]
param(
  [string]$Projet = "",
  [string[]]$Icones = @("Risks", "PermissionRestrict", "SourceControlRun", "FilePermissionView", "CancelRequest"),
  [string]$Sortie = "",
  [switch]$SansSignature,
  [switch]$SansBarre,
  [switch]$Commandes,
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

function Lire($p)      { [System.IO.File]::ReadAllText($p) }
# UTF-8 SANS BOM : la chaine de personnalisation lit branding.conf ligne a ligne.
function Ecrire($p,$c) { [System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($false))) }

function ValeurCle($contenu, $cle) {
  $m = [regex]::Match($contenu, '(?m)^\s*' + [regex]::Escape($cle) + '\s*=\s*"?([^"\r\n]*)"?\s*$')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return ""
}

# Remplace (ou ajoute) une cle dans branding.conf, en preservant le reste.
function DefinirCle($contenu, $cle, $valeur) {
  $nl = "`n"; if ($contenu -match "`r`n") { $nl = "`r`n" }
  $lignes = [System.Collections.ArrayList]@()
  foreach ($l in ($contenu -split "`r?`n")) { [void]$lignes.Add($l) }
  $motif = '^\s*' + [regex]::Escape($cle) + '\s*='
  $trouve = $false
  for ($i = 0; $i -lt $lignes.Count; $i++) {
    if ($lignes[$i] -match $motif) { $lignes[$i] = "$cle=`"$valeur`""; $trouve = $true }
  }
  if (-not $trouve) {
    [void]$lignes.Add("")
    [void]$lignes.Add("# Icone du bouton (voir branding.conf.example pour les valeurs admises)")
    [void]$lignes.Add("$cle=`"$valeur`"")
  }
  return ($lignes -join $nl)
}

# ------------------------------------------------------------ SUIVI DU TEMPS
# ATTENTION : en PowerShell [int]1,58 vaut 2 (arrondi, pas troncature). Un
# [int]$ts.TotalMinutes affichait donc 95 s comme "2m35s". On ne calcule qu'en
# entiers de secondes.
function Duree($ts) {
  $s = [int][math]::Floor($ts.TotalSeconds)
  if ($s -lt 0) { $s = 0 }
  if ($s -ge 3600) { return ("{0}h{1:00}m{2:00}s" -f [int][math]::Floor($s / 3600), [int][math]::Floor(($s % 3600) / 60), ($s % 60)) }
  if ($s -ge 60)   { return ("{0}m{1:00}s" -f [int][math]::Floor($s / 60), ($s % 60)) }
  return ("{0}s" -f $s)
}
function DureeSec($s) { return (Duree ([timespan]::FromSeconds([math]::Round($s)))) }

# Le journal du build contient DEUX encodages melanges : PowerShell et
# devenv.com ecrivent dans la page de codes de la console (CP850 sur un Windows
# francais), tandis que 02_customize.sh, qui est du bash, ecrit en UTF-8. Lire
# le tout avec un seul encodage abime forcement la moitie des lignes. On decide
# donc ligne par ligne : si la ligne est de l'UTF-8 valide c'en est, sinon
# c'est la page de codes de la console.
# PowerShell 7 ne connait pas les pages de codes anciennes sans ce fournisseur ;
# PowerShell 5.1 les a d'origine et ignorera l'echec.
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}

function EncodageConsole {
  # Page de codes OEM du systeme : celle qu'emploient reellement les
  # applications console (devenv.com) et PowerShell quand leur sortie est
  # redirigee vers un fichier. 850 sur un Windows francais.
  try {
    $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    if ($cp -gt 0) { return [System.Text.Encoding]::GetEncoding($cp) }
  } catch {}
  try { return [Console]::OutputEncoding } catch {}
  return [System.Text.Encoding]::GetEncoding(28591)
}

# Affichage sans accent : une page de codes qui ne correspond pas transforme un
# accent en caractere illisible. Pas d'accent, pas de probleme.
# Aucun caractere accentue dans ce code, et AUCUNE expression reguliere : les
# caracteres vises sont designes par leur code. (Un motif ecrit en clair ici
# serait un piege : "..." en expression reguliere signifie "trois caracteres
# quelconques", pas trois points.)
function SansAccents($t) {
  if (-not $t) { return "" }
  $s = [string]$t
  $s = $s.Replace([string][char]0x00A0, " ")
  $s = $s.Replace([string][char]0x0153, "oe").Replace([string][char]0x0152, "OE")
  $s = $s.Replace([string][char]0x00E6, "ae").Replace([string][char]0x00C6, "AE")
  $s = $s.Replace([string][char]0x2018, "'").Replace([string][char]0x2019, "'")
  $s = $s.Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"')
  $s = $s.Replace([string][char]0x00AB, '"').Replace([string][char]0x00BB, '"')
  $s = $s.Replace([string][char]0x2013, "-").Replace([string][char]0x2014, "-")
  $s = $s.Replace([string][char]0x2026, "...")
  $s = $s.Replace([string][char]0x20AC, "EUR")

  # decompose les lettres accentuees puis jette les signes diacritiques :
  # "e" + accent aigu devient "e".
  $s = $s.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  $s = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)

  # tout ce qui reste hors ASCII imprimable devient "?" plutot qu'un carre noir
  $out = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    $n = [int]$c
    if ($n -eq 9 -or ($n -ge 32 -and $n -le 126)) { [void]$out.Append($c) } else { [void]$out.Append("?") }
  }
  return $out.ToString()
}

function Raccourcir($t, $n) {
  if (-not $t) { return "" }
  if ($t.Length -le $n) { return $t }
  return ($t.Substring(0, $n - 3) + "...")
}

# Lit un fichier qu'un AUTRE processus est en train d'ecrire.
# FileShare.ReadWrite est indispensable : Get-Content refuserait le fichier
# ("en cours d'utilisation par un autre processus").
function LireTout($chemin) {
  if (-not $chemin) { return @() }
  if (-not (Test-Path -LiteralPath $chemin)) { return @() }
  $octets = $null
  try {
    $fs = New-Object System.IO.FileStream($chemin, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $ms = New-Object System.IO.MemoryStream
    $fs.CopyTo($ms)
    $fs.Dispose()
    $octets = $ms.ToArray()
    $ms.Dispose()
  } catch { return @() }
  if (-not $octets -or $octets.Length -eq 0) { return @() }

  # ISO-8859-1 fait correspondre un octet a un caractere, sans perte : on s'en
  # sert pour decouper en lignes sans rien interpreter, puis on redonne a
  # chaque ligne ses octets d'origine pour la decoder pour de bon.
  $latin = [System.Text.Encoding]::GetEncoding(28591)
  $utf8  = New-Object System.Text.UTF8Encoding($false, $true)
  $repli = EncodageConsole

  $lignes = New-Object System.Collections.ArrayList
  foreach ($brute in ($latin.GetString($octets) -split "`r?`n")) {
    if ($brute -eq "") { continue }
    $b = $latin.GetBytes($brute)
    $t = $null
    # UTF-8 strict : en cas d'octet invalide il leve une exception, ce qui est
    # precisement le signal que la ligne vient de la console et non de bash.
    try { $t = $utf8.GetString($b) } catch { $t = $repli.GetString($b) }
    $t = $t.TrimEnd()
    if ($t -ne "") { [void]$lignes.Add($t) }
  }
  return @($lignes.ToArray())
}

function LireFin($chemin, $nb) {
  $l = LireTout $chemin
  if ($l.Count -le $nb) { return $l }
  return $l[($l.Count - $nb)..($l.Count - 1)]
}

# Titre de la fenetre : un repere lisible depuis la barre des taches, sans
# avoir a basculer sur la console. Certains hotes le refusent, d'ou le catch.
$script:titreInitial = ""
try { $script:titreInitial = $Host.UI.RawUI.WindowTitle } catch {}
function TitreFenetre($t) { try { $Host.UI.RawUI.WindowTitle = $t } catch {} }

# La sortie du build etant redirigee, toute erreur resterait invisible :
# on reaffiche la fin du journal des que quelque chose ne va pas.
function MontrerJournal($jOut, $jErr) {
  if (-not $jOut) { return }
  Write-Host ""
  Detail ("journal complet : " + $jOut)
  Write-Host ""
  foreach ($l in (LireFin $jOut 25)) { Write-Host ("    " + (SansAccents $l)) -ForegroundColor DarkGray }
  $e = LireFin $jErr 10
  if ($e.Count -gt 0) {
    Write-Host ""
    foreach ($l in $e) { Write-Host ("    " + (SansAccents $l)) -ForegroundColor Red }
  }
}

# Lit ProductName / ProductCode / ProductVersion DANS le MSI. C'est la seule
# source exacte : le ProductCode change a chaque build (02_customize.sh le
# regenere), et ProductName est ce qui s'affichera dans "Programmes installes".
function ProprietesMsi($chemin) {
  $r = @{ Nom = ""; Code = ""; Version = ""; Erreur = "" }
  $inv = [System.Reflection.BindingFlags]::InvokeMethod
  $get = [System.Reflection.BindingFlags]::GetProperty
  try {
    $type = [Type]::GetTypeFromProgID("WindowsInstaller.Installer")
    if (-not $type) { $r.Erreur = "composant WindowsInstaller.Installer absent de ce poste"; return $r }
    $wi = [Activator]::CreateInstance($type)
    $db = $wi.GetType().InvokeMember("OpenDatabase", $inv, $null, $wi, @("$chemin", 0))
    foreach ($cle in @("ProductName", "ProductCode", "ProductVersion")) {
      $vue = $null
      try {
        $vue = $db.GetType().InvokeMember("OpenView", $inv, $null, $db, @("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '" + $cle + "'"))
        $vue.GetType().InvokeMember("Execute", $inv, $null, $vue, $null) | Out-Null
        $enr = $vue.GetType().InvokeMember("Fetch", $inv, $null, $vue, $null)
        if ($enr) {
          # StringData est une propriete INDEXEE : l'index doit etre passe dans
          # un tableau, sans quoi l'appel echoue.
          $val = [string]$enr.GetType().InvokeMember("StringData", $get, $null, $enr, @([int]1))
          if     ($cle -eq "ProductName") { $r.Nom = $val }
          elseif ($cle -eq "ProductCode") { $r.Code = $val }
          else                            { $r.Version = $val }
        }
      } finally {
        if ($vue) { try { $vue.GetType().InvokeMember("Close", $inv, $null, $vue, $null) | Out-Null } catch {} }
      }
    }
  } catch {
    # On NE masque PAS l'echec : sans ces proprietes, INSTALLER.txt ne pourrait
    # pas donner le ProductCode ni le nom affiche dans "Programmes installes".
    $r.Erreur = $_.Exception.Message
  }
  return $r
}

# Etat de signature du paquet, lu sur le fichier lui-meme : plus fiable que de
# se souvenir si -SansSignature etait de la partie.
function Signature($chemin) {
  try {
    $s = Get-AuthenticodeSignature -LiteralPath $chemin -ErrorAction Stop
    if ($s.Status -eq "Valid") {
      $sujet = ""
      if ($s.SignerCertificate) { $sujet = " (" + $s.SignerCertificate.Subject.Split(',')[0] + ")" }
      return "signe" + $sujet
    }
    if ($s.Status -eq "NotSigned") { return "NON SIGNE" }
    return ("signature " + $s.Status)
  } catch { return "inconnue" }
}

# INSTALLER.txt : le mode d'emploi qui voyage avec les paquets. Que du
# copier-coller msiexec, aucun script - msiexec est un outil du systeme, il
# passe la ou un .ps1 est refuse par AppLocker ou SRP.
function EcrireCommandes($dossier, $liste, $nomProduit, $versionProduit) {
  $nomAffiche = $nomProduit
  $lus = @($liste | Where-Object { $_.NomProduit } | Select-Object -First 1 -ExpandProperty NomProduit)
  if ($lus.Count -gt 0) { $nomAffiche = $lus[0] }

  $t = @()
  $t += "============================================================"
  $t += " Essais d'icones - " + $nomProduit + " " + $versionProduit
  $t += " Produit par 93_generate-icons.ps1 le " + (Get-Date -Format 'yyyy-MM-dd HH:mm')
  $t += "============================================================"
  $t += ""
  $t += "AVANT DE COMMENCER"
  $t += "  - console ADMINISTRATEUR (cmd ou PowerShell), depuis CE dossier"
  $t += "  - Outlook FERME a chaque installation et desinstallation"
  $t += "  - les variantes partagent la meme identite produit : elles ne"
  $t += "    cohabitent pas. DESINSTALLEZ avant d'installer la suivante,"
  $t += "    sinon erreur 1638 ou deux boutons dans le ruban."
  $t += "  - nom affiche dans Programmes installes : " + $nomAffiche
  $t += ""
  foreach ($p in $liste) {
    $t += "------------------------------------------------------------"
    $t += $p.Icone
    $t += "  installer      msiexec /i """ + $p.Fichier + """ /qb /norestart ALLUSERS=1"
    $t += "  desinstaller   msiexec /x """ + $p.Fichier + """ /qb /norestart"
    if ($p.CodeProduit) { $t += "  ProductCode    " + $p.CodeProduit }
    if ($p.Signe)       { $t += "  paquet         " + $p.Signe }
  }
  $t += "------------------------------------------------------------"
  $t += ""
  $t += "VERIFIER CE QUI EST EN PLACE (PowerShell)"
  # Chaine en apostrophes : sans cela PowerShell remplacerait $_ par du vide et
  # $env:USERNAME par le compte du poste de BUILD au moment de l'ecriture.
  $modele = '  Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*@NOM@*" } | Select-Object DisplayName, DisplayVersion, PSChildName'
  $t += $modele.Replace('@NOM@', $nomAffiche)
  $t += ""
  $t += "CODES DE RETOUR msiexec  (en cmd : echo %errorlevel%)"
  $t += "  0     installe"
  $t += "  3010  installe, redemarrage demande"
  $t += "  1619  paquet introuvable : chemin faux"
  $t += "  1625  refuse par la politique du poste (AppLocker / SRP)"
  $t += "  1638  une version est deja installee : desinstallez d'abord"
  $t += "  1603  echec en cours d'installation : relancer avec /l*v journal.txt"
  $t += ""
  $t += "SI 1625 - le poste refuse le paquet, ce n'est pas un defaut du MSI."
  $t += "  AppLocker bloque d'un bloc la collection MSI and Script. Pour savoir"
  $t += "  quelle regle statue, sans rien executer :"
  $t += '    Get-AppLockerPolicy -Effective | Test-AppLockerPolicy -Path .\<paquet>.msi -User $env:USERNAME'
  $t += "  Voir aussi le journal Microsoft-Windows-AppLocker/MSI and Script."
  $t += ""
  Ecrire (Join-Path $dossier "INSTALLER.txt") (($t -join "`r`n") + "`r`n")
}

# Temps CPU cumule de devenv : la preuve qu'un build muet travaille quand meme.
function CpuDevenv {
  $c = 0.0
  Get-Process devenv -ErrorAction SilentlyContinue | ForEach-Object { if ($_.CPU) { $c += $_.CPU } }
  return [int]$c
}

$script:procEnCours = $null

# Lance 04_build.ps1 dans un processus separe, sortie redirigee vers un journal,
# et rafraichit la barre d'etat pendant qu'il travaille. C'est le seul moyen
# d'afficher une progression : devenv.com ne rend la main qu'a la fin.
function ConstruireAvecBarre($build, $argsBuild, $jOut, $jErr, $etiquette, $rang, $total, $moyenne) {
  $psExe = $null
  try { $psExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch {}
  if (-not $psExe) { $psExe = Join-Path $PSHOME "powershell.exe" }

  $a = @("-NoProfile")
  if ($env:OS -eq "Windows_NT") { $a += @("-ExecutionPolicy", "Bypass") }
  $a += @("-File", $build)
  if ($argsBuild.Count -gt 0) { $a += $argsBuild }

  $sp = @{
    FilePath               = $psExe
    ArgumentList           = $a
    PassThru               = $true
    RedirectStandardOutput = $jOut
    RedirectStandardError  = $jErr
  }
  if ($env:OS -eq "Windows_NT") { $sp["WindowStyle"] = "Hidden" }
  $p = Start-Process @sp
  # PIEGE Start-Process -PassThru : sans toucher .Handle tout de suite, le
  # handle natif n'est pas conserve et $p.ExitCode revient VIDE apres la fin du
  # processus. Un build parfaitement reussi etait alors declare en echec.
  try { $null = $p.Handle } catch {}
  $script:procEnCours = $p

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $etape = 0; $etapeVue = -1; $libelle = "demarrage"; $derniere = ""
  $vues = 0
  $tailleVue = -1; $mouvement = [datetime]::Now; $echo = [datetime]::MinValue
  $cpu0 = CpuDevenv

  # Marqueur rappele a gauche de chaque ligne du build : meme apres cent lignes
  # de devenv, on sait toujours quelle icone est en cours de fabrication.
  $marque = ($etiquette + " " + $rang + "/" + $total)
  if ($marque.Length -gt 22) { $marque = $marque.Substring(0, 22) }
  $marque = $marque.PadRight(22)
  $creux  = (" " * 22)

  while ($true) {
    # WaitForExit(ms) rend la main des la seconde ou le build se termine, au
    # lieu de dormir en aveugle : pas de reveil manque, pas de fin detectee
    # avec un tour de retard.
    $fini = $p.WaitForExit(900)
    if ($fini) { $p.WaitForExit() }

    # Tant que le build tourne, on n'affiche pas la toute derniere ligne : elle
    # peut etre incomplete (ecriture en cours). Elle sortira au tour suivant.
    $lignes = LireTout $jOut
    $limite = $(if ($fini) { $lignes.Count } else { $lignes.Count - 1 })
    for ($k = $vues; $k -lt $limite; $k++) {
      $ligne = $lignes[$k]
      $m = [regex]::Match($ligne, '^===\s*(\d)/5\s+(.*?)\s*===$')
      if ($m.Success) {
        $etape = [int]$m.Groups[1].Value; $libelle = SansAccents $m.Groups[2].Value
        Write-Host ("  " + $marque + "| " + (SansAccents $ligne)) -ForegroundColor Cyan
      } else {
        Write-Host ("  " + $creux + "| " + (Raccourcir (SansAccents $ligne) 120)) -ForegroundColor DarkGray
      }
      $derniere = $ligne
    }
    if ($limite -gt $vues) { $vues = $limite }

    if ($fini) { break }

    $taille = -1
    try { $taille = (Get-Item -LiteralPath $jOut -ErrorAction Stop).Length } catch {}
    if ($taille -ne $tailleVue) { $tailleVue = $taille; $mouvement = [datetime]::Now }
    $silence = ([datetime]::Now - $mouvement)

    $cpu  = CpuDevenv
    $etat = "etape " + $etape + "/5 " + $libelle
    $info = "ecoule " + (Duree $sw.Elapsed)
    if ($cpu -gt $cpu0) { $info += "   devenv " + ($cpu - $cpu0) + " s CPU" }
    if ($silence.TotalSeconds -ge 120) { $info += "   sans sortie depuis " + (Duree $silence) }

    $pct = [int](((($rang - 1) + ([math]::Min($etape, 5) / 5.0)) / $total) * 100)
    if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }

    $pa = @{
      Id              = 1
      Activity        = ("ICONE " + $rang + "/" + $total + " : " + $etiquette)
      Status          = ($etat + "   |   " + $info)
      PercentComplete = $pct
    }
    if ($derniere) { $pa["CurrentOperation"] = (Raccourcir $derniere 100) }
    if ($moyenne -gt 0) {
      $reste = ($moyenne * ($total - $rang)) + [math]::Max(0, $moyenne - $sw.Elapsed.TotalSeconds)
      $pa["SecondsRemaining"] = [int]$reste
    }
    Write-Progress @pa

    # Repere hors de la fenetre : visible dans la barre des taches, donc lisible
    # sans basculer sur la console.
    TitreFenetre ("BoutonSPAM - icone " + $rang + "/" + $total + " " + $etiquette + " - etape " + $etape + "/5 - " + (Duree $sw.Elapsed))

    # Rappel periodique : c'est la ligne qui repond a "ou en est-on ?" pendant
    # les longues minutes muettes de devenv sur le projet Setup.
    if ($etape -ne $etapeVue -or ([datetime]::Now - $echo).TotalSeconds -ge 30) {
      $etapeVue = $etape; $echo = [datetime]::Now
      $suffixe = ""
      if ($cpu -gt $cpu0) { $suffixe = "   devenv " + ($cpu - $cpu0) + " s CPU" }
      # devenv.com n'ecrit pas ligne a ligne quand sa sortie est redirigee :
      # un long silence n'est pas un blocage, le compteur CPU le prouve.
      if ($silence.TotalSeconds -ge 120) { $suffixe += "   sans sortie depuis " + (Duree $silence) + " (normal : devenv ecrit par blocs)" }
      Write-Host ("  " + $marque + "> " + (Duree $sw.Elapsed).PadLeft(7) + "   " + $etat + $suffixe) -ForegroundColor Yellow
    }
  }

  $p.WaitForExit()
  Write-Progress -Id 1 -Activity "Variantes d'icone" -Completed
  $script:procEnCours = $null
  return @{ Code = $p.ExitCode; Secondes = $sw.Elapsed.TotalSeconds }
}

# ------------------------------------------------------------ 1. CONTROLES
# Tout est valide AVANT le premier build : un nom d'icone fautif ne doit pas
# se decouvrir apres vingt minutes de compilation.
Titre "CONTROLES PREALABLES"

if (-not $Projet) { $Projet = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Projet -PathType Container)) { Arret "Dossier projet introuvable : $Projet" }
$Projet = (Resolve-Path -LiteralPath $Projet).Path

$brand = Join-Path $Projet "branding.conf"
$build = Join-Path $Projet "scripts\04_build.ps1"
if (-not (Test-Path -LiteralPath $brand)) { Arret "branding.conf absent : $brand" }
if (-not (Test-Path -LiteralPath $build)) { Arret "scripts\04_build.ps1 absent : ce dossier n'est pas un projet BoutonSPAM." }
Ok "Projet : $Projet"

# Liste blanche : un imageMso inconnu ne leve AUCUNE erreur, Outlook affiche
# simplement un bouton sans icone. On refuse donc en amont plutot que de
# livrer une variante muette.
# tolere les deux ecritures : -Icones Risks,CancelRequest et -Icones "Risks,CancelRequest"
$Icones = @($Icones | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Icones.Count -eq 0) { Arret "Aucune icone demandee." }

$admises = @("Risks", "PermissionRestrict", "SourceControlRun", "FilePermissionView", "CancelRequest")
$fautives = @($Icones | Where-Object { $admises -notcontains $_ })
if ($fautives.Count -gt 0) {
  Err ("Icone(s) inconnue(s) : " + ($fautives -join ", "))
  Detail "Un identifiant inconnu ne provoque pas d'erreur : Outlook affiche un bouton"
  Detail "SANS icone. On s'arrete donc ici. Valeurs admises :"
  foreach ($a in $admises) { Detail "  $a" }
  Write-Host ""; exit 1
}
Ok ("Icones demandees (" + $Icones.Count + ") : " + ($Icones -join ", "))

$conf       = Lire $brand
$produit    = ValeurCle $conf "PRODUCT_NAME"
$msiBase    = ValeurCle $conf "MSI_BASENAME"
$version    = ValeurCle $conf "VERSION"
$iconeAvant = ValeurCle $conf "BUTTON_ICON"
if (-not $produit) { Arret "PRODUCT_NAME introuvable dans branding.conf" }
if (-not $version) { Arret "VERSION introuvable dans branding.conf" }
if (-not $msiBase) { $msiBase = "Setup" }
$msiBase = ($msiBase -replace '[^A-Za-z0-9._-]', '')
$v3 = (($version -split '\.')[0..2] -join '.')
# Le nom du MSI produit n'est PAS deductible de branding.conf : il suit
# PRODUCT_NAME, pas MSI_BASENAME, et 04_build.ps1 lui-meme retient "le MSI le
# plus recent" quand le nom qu'il attend n'existe pas. On ne devine donc aucun
# nom : apres chaque build on repere le MSI ecrit PENDANT ce build.
$dossierMsi = Join-Path $Projet "setup\Release"

Inf "Produit : $produit"
Inf "Version : $version"
Inf ("Icone actuelle : " + $(if ($iconeAvant) { $iconeAvant } else { "(non definie -> PermissionRestrict par defaut)" }))
Inf ("MSI produits dans : " + $dossierMsi)
Detail "le paquet est repere a son horodatage apres chaque build, pas a son nom"

if (-not $Sortie) { $Sortie = Join-Path $Projet "essais-icones" }
Inf "Dossier de sortie : $Sortie"

# ----------------------------------------- 1bis. INSTALLER.txt SEUL (sans build)
if ($Commandes) {
  Titre "RECONSTRUCTION DE INSTALLER.txt"
  Detail "aucun build : on relit les MSI deja presents dans le dossier de sortie"
  if (-not (Test-Path -LiteralPath $Sortie -PathType Container)) { Arret ("Dossier de sortie introuvable : " + $Sortie) }

  $liste = @()
  $avertiCom = $false
  foreach ($ic in $admises) {
    $f = @(Get-ChildItem -LiteralPath $Sortie -Filter ("*-" + $ic + ".msi") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($f.Count -eq 0) { continue }
    $prop = ProprietesMsi $f[0].FullName
    if ($prop.Erreur -and -not $avertiCom) {
      $avertiCom = $true
      Att ("Lecture des proprietes du MSI impossible : " + (Raccourcir (SansAccents $prop.Erreur) 100))
      Detail "INSTALLER.txt sera ecrit sans les ProductCode."
    }
    Detail ($ic.PadRight(20) + $f[0].Name)
    if ($prop.Nom) { Detail ("".PadRight(20) + "ProductName : " + $prop.Nom + "   ProductCode : " + $prop.Code) }
    $liste += [pscustomobject]@{ Icone = $ic; Fichier = $f[0].Name; Secondes = 0; NomProduit = $prop.Nom; CodeProduit = $prop.Code; Signe = (Signature $f[0].FullName) }
  }
  if ($liste.Count -eq 0) { Arret ("Aucun MSI de variante trouve dans " + $Sortie) }

  EcrireCommandes $Sortie $liste $produit $version
  Titre "TERMINE"
  Ok ($liste.Count.ToString() + " variante(s) inscrite(s) dans " + (Join-Path $Sortie "INSTALLER.txt"))
  Write-Host ""
  exit 0
}

if ($SansSignature) {
  Att "-SansSignature : les paquets ne seront PAS signes."
  Detail "Sur un poste exigeant un editeur approuve, le bouton ne se chargera pas du"
  Detail "tout - et l'icone n'y sera pour rien. A n'utiliser qu'en connaissance de cause."
}

if ($Simulation) {
  Titre "SIMULATION"
  Att "Rien ne sera ecrit, rien ne sera construit."
  foreach ($ic in $Icones) {
    Detail ("construirait avec BUTTON_ICON=" + $ic + "  ->  " + (Join-Path $Sortie ("<nom du MSI produit>-" + $ic + ".msi")))
  }
  Detail ("puis restaurerait BUTTON_ICON=" + $(if ($iconeAvant) { $iconeAvant } else { "(absent)" }))
  Write-Host ""
  exit 0
}

# --------------------------------------------------------- 2. CONSTRUCTIONS
Titre "CONSTRUCTIONS"
New-Item -ItemType Directory -Force -Path $Sortie | Out-Null

$produits = @()
$echec = $null
$argsBuild = @()
if ($SansSignature) { $argsBuild += "-NoSign" }

$logs = Join-Path $Projet "logs"
if (-not (Test-Path -LiteralPath $logs)) { New-Item -ItemType Directory -Force -Path $logs | Out-Null }
$horo = Get-Date -Format "yyyyMMdd-HHmmss"

$chrono = [System.Diagnostics.Stopwatch]::StartNew()
$rang = 0
$durees = @()
$avertiCom = $false

try {
  foreach ($ic in $Icones) {
    $rang++
    $moyenne = 0
    if ($durees.Count -gt 0) { $moyenne = ($durees | Measure-Object -Average).Average }

    Titre ("ICONE " + $rang + "/" + $Icones.Count + " : " + $ic)
    if ($moyenne -gt 0) {
      Detail ("duree moyenne des precedents : " + (DureeSec $moyenne) + "   -   fin estimee de la passe : " + (DureeSec ($moyenne * ($Icones.Count - $rang + 1))))
    }
    Ecrire $brand (DefinirCle (Lire $brand) "BUTTON_ICON" $ic)

    # Repere temporel : tout MSI ecrit apres cet instant est le notre. On ne
    # supprime rien d'avance - supprimer un fichier dont on ignore le nom exact
    # revient a supprimer au hasard.
    $debut = (Get-Date).AddSeconds(-5)

    $jOut = $null; $jErr = $null
    if ($SansBarre) {
      $t0 = [System.Diagnostics.Stopwatch]::StartNew()
      & $build @argsBuild
      $code = $LASTEXITCODE
      if ($null -eq $code) { $code = 0 }
      $secs = $t0.Elapsed.TotalSeconds
      if ($code -ne 0) { throw ("04_build.ps1 a echoue pour l'icone " + $ic + " (code " + $code + ").") }
    }
    else {
      $jOut = Join-Path $logs ("93-" + $ic + "-" + $horo + ".log")
      $jErr = Join-Path $logs ("93-" + $ic + "-" + $horo + ".err.log")
      $r    = ConstruireAvecBarre $build $argsBuild $jOut $jErr $ic $rang $Icones.Count $moyenne
      $code = $r.Code
      $secs = $r.Secondes
      # Un code indisponible n'est PAS un echec : c'est une information
      # manquante. Le MSI produit, lui, tranche sans ambiguite.
      # NE PAS tester $code -eq "" : en PowerShell, 0 -eq "" vaut VRAI (la
      # chaine vide se convertit en 0), ce qui declencherait l'avertissement a
      # chaque build reussi.
      if ($null -eq $code) {
        Att "Code de sortie du build indisponible : verification par le MSI produit."
        $code = 0
      }
      if ($code -ne 0) {
        Write-Host ""
        Err ("echec du build pour l'icone " + $ic + " (code " + $code + ") apres " + (DureeSec $secs))
        MontrerJournal $jOut $jErr
        throw ("build en echec pour l'icone " + $ic + " (code " + $code + ") - voir " + $jOut)
      }
      # journal d'erreurs vide = rien a garder, on ne laisse pas de traine dans logs\
      if ((Test-Path -LiteralPath $jErr) -and (Get-Item -LiteralPath $jErr).Length -eq 0) {
        Remove-Item -LiteralPath $jErr -Force -ErrorAction SilentlyContinue
      }
    }

    # un 04_build.ps1 qui s'arrete sur une exception ne renvoie pas toujours un
    # code non nul : le MSI fraichement ecrit est le controle qui ne ment pas.
    $msiTrouve = Get-ChildItem -LiteralPath $dossierMsi -Filter "*.msi" -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -ge $debut } |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $msiTrouve) {
      MontrerJournal $jOut $jErr
      throw ("Build termine mais aucun MSI n'a ete ecrit pendant ce build dans " + $dossierMsi)
    }

    $cible = Join-Path $Sortie ($msiTrouve.BaseName + "-" + $ic + ".msi")
    Copy-Item -LiteralPath $msiTrouve.FullName -Destination $cible -Force
    $taille = [math]::Round((Get-Item -LiteralPath $cible).Length / 1MB, 1)
    $prop = ProprietesMsi $cible
    $durees += $secs
    Ok ($ic + " -> " + (Split-Path -Leaf $cible) + "   (" + $taille + " Mo, " + (DureeSec $secs) + ")")
    Detail ("source : " + $msiTrouve.Name + "   ecrit a " + $msiTrouve.LastWriteTime.ToString("HH:mm:ss"))
    if ($prop.Nom) { Detail ("ProductName : " + $prop.Nom + "   ProductCode : " + $prop.Code) }
    elseif ($prop.Erreur -and -not $avertiCom) {
      $avertiCom = $true
      Att ("Lecture des proprietes du MSI impossible : " + (Raccourcir (SansAccents $prop.Erreur) 100))
      Detail "INSTALLER.txt sera ecrit sans les ProductCode."
      Detail "Rattrapage possible apres coup :  .\scripts\93_generate-icons.ps1 -Commandes"
    }
    Detail ("cumul de la passe : " + (Duree $chrono.Elapsed) + "   -   reste " + ($Icones.Count - $rang) + " icone(s)")
    $produits += [pscustomobject]@{
      Icone = $ic; Fichier = (Split-Path -Leaf $cible); Secondes = $secs
      NomProduit = $prop.Nom; CodeProduit = $prop.Code; Signe = (Signature $cible)
    }
  }
} catch {
  $echec = $_.Exception.Message
} finally {
  Write-Progress -Id 1 -Activity "Variantes d'icone" -Completed
  if ($script:titreInitial) { TitreFenetre $script:titreInitial }
  # Un build lance dans un processus separe survivrait a une interruption :
  # on l'arrete, lui et ses enfants (devenv, MSBuild).
  if ($script:procEnCours -and -not $script:procEnCours.HasExited) {
    Att ("Interruption : arret du build en cours (PID " + $script:procEnCours.Id + ") et de ses processus enfants.")
    try {
      if ($env:OS -eq "Windows_NT") { & taskkill /PID $script:procEnCours.Id /T /F 2>$null | Out-Null }
      else { Stop-Process -Id $script:procEnCours.Id -Force -ErrorAction SilentlyContinue }
    } catch {}
  }
  # Quoi qu'il arrive, branding.conf repart comme il etait.
  if ($iconeAvant) { Ecrire $brand (DefinirCle (Lire $brand) "BUTTON_ICON" $iconeAvant) }
  else {
    $c = Lire $brand
    $c = [regex]::Replace($c, '(?m)^\s*BUTTON_ICON\s*=.*\r?\n?', '')
    Ecrire $brand $c
  }
}

if ($echec) {
  Titre "ECHEC"
  Err $echec
  Detail "BUTTON_ICON a ete restaure a sa valeur d'origine."
  Detail ("temps ecoule avant l'arret : " + (Duree $chrono.Elapsed))
  if ($produits.Count -gt 0) { Detail ($produits.Count.ToString() + " paquet(s) deja produit(s) restent dans " + $Sortie) }
  Write-Host ""; exit 1
}

# --------------------------------------------------------- 3. INSTALLER.txt
# Le poste de test ne connait ni le projet ni branding.conf : ce fichier lui
# donne les commandes msiexec toutes faites, paquet par paquet.
EcrireCommandes $Sortie $produits $produit $version

Titre "TERMINE"
Ok ($produits.Count.ToString() + " paquet(s) dans : " + $Sortie)
foreach ($p in $produits) { Detail ($p.Icone.PadRight(20) + $p.Fichier.PadRight(42) + (DureeSec $p.Secondes).PadLeft(8)) }
$total = [math]::Round((Get-ChildItem -LiteralPath $Sortie -File | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Detail ("volume total : " + $total + " Mo")
Detail ("duree totale : " + (Duree $chrono.Elapsed) + "   -   moyenne par icone : " + (DureeSec (($durees | Measure-Object -Average).Average)))
Write-Host ""
Detail ("BUTTON_ICON restaure : " + $(if ($iconeAvant) { $iconeAvant } else { "(retire, comme avant)" }))
Write-Host ""
Detail "Emportez ce dossier entier sur le poste de test. Les commandes sont"
Detail "dans INSTALLER.txt, une paire par icone. Pour la premiere, console"
Detail "ADMINISTRATEUR et Outlook FERME, depuis le dossier :"
Write-Host ""
if ($produits.Count -gt 0) {
  Detail ("    msiexec /i """ + $produits[0].Fichier + """ /qb /norestart ALLUSERS=1")
  Detail ("    msiexec /x """ + $produits[0].Fichier + """ /qb /norestart")
}
Write-Host ""
Detail "Desinstallez toujours avant d'installer la suivante : meme identite"
Detail "produit, donc pas de cohabitation possible."
Write-Host ""
