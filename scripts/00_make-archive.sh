#!/usr/bin/env bash
# ============================================================================
#  00_make-archive.sh — genere l'archive de sauvegarde/transfert PORTABLE.
#  A lancer dans un shell bash (Git Bash sous Windows : clic droit dans le
#  dossier -> "Open Git Bash here", ou double-clic sur le script), a la racine
#  ou via scripts/ :
#     ./scripts/00_make-archive.sh                # archive AVEC le layout (defaut)
#     ./scripts/00_make-archive.sh --sans-layout  # archive LEGERE (sans le layout)
#
#  ARCHIVEUR (auto-detecte, portable) : le script utilise `zip` s'il est present,
#  sinon **7-Zip** (7z). Utile car Git Bash sous Windows ne fournit PAS `zip` :
#  on bascule alors sur 7-Zip (a installer depuis installers/7z2602-x64.exe si
#  besoin). Le decoupage en volumes utilise `split` (present dans tout shell bash),
#  donc les volumes ont TOUJOURS le meme nom (.zip.001/.002...) quel que soit
#  l'archiveur. Si aucun archiveur n'est trouve, le script s'arrete avec un
#  message clair (et une PAUSE : la fenetre reste ouverte).
#
#  SORTIE : tout est ecrit dans un dossier dedie "archives/" a la racine du
#  projet (archive .zip OU volumes .zip.001/.002..., + empreintes .sha256). Ce
#  dossier n'est ni suivi par git, ni inclus dans une future archive.
#
#  Le layout Visual Studio (installers/vslayout, ~4 Go) est INCLUS par defaut :
#  l'archive suffit a equiper un poste HORS LIGNE (code + layout).
#
#  LIMITE FAT32 (4 Go par fichier) : si l'archive depasse 4 Go, elle est
#  automatiquement DECOUPEE en volumes EQUILIBRES < 4 Go (.zip.001, .zip.002...),
#  copiables sur une cle FAT32. Extraction cible : 7-Zip (clic droit sur le .001
#  -> Extraire ; il lit tous les volumes). Details : README, section « Archive portable ».
#
#  SECURITE : aucune CLE PRIVEE ni secret (certs/, *.pfx/.p12/.snk,
#  attachments.desc) n'est JAMAIS embarque — le certificat se transporte a part,
#  par un canal chiffre, distinct de l'archive.
#
#  Nom : archives/OutlookSpamAddin-migration-AAAAMMJJ-HHMM.zip  (+ .sha256)
# ============================================================================
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p logs
exec > >(tee -a "logs/make-archive-$(date +%Y%m%d-%H%M%S).log") 2>&1

# PAUSE a la sortie (succes OU erreur) : la fenetre ne se referme pas sans qu'on
# ait pu lire le resultat. Invite ecrite sur le terminal (/dev/tty) meme si la
# sortie standard est journalisee (tee). Sans terminal (tache planifiee), on ne
# bloque pas.
_pause() {
  local code=$?
  echo ""
  if [ "$code" -ne 0 ]; then
    echo ">> ECHEC (code $code). Cause probable ci-dessus ; journal complet dans logs/."
  fi
  # Pause seulement si un vrai terminal est disponible ET ouvrable (sinon, tache
  # planifiee / sortie redirigee : on ne bloque pas et on n'affiche pas d'erreur).
  if { : > /dev/tty; } 2>/dev/null; then
    printf ">> Termine (code %s). Appuyez sur Entree pour fermer cette fenetre... " "$code" > /dev/tty 2>/dev/null || true
    read -r _ < /dev/tty 2>/dev/null || true
  fi
}
trap _pause EXIT

SANS_LAYOUT=0
for a in "$@"; do
  case "$a" in
    --sans-layout|--no-layout) SANS_LAYOUT=1 ;;
    *) echo "Option inconnue : $a (seule option : --sans-layout)"; exit 1 ;;
  esac
done

# --- Detection de l'archiveur : `zip` en priorite (present sur beaucoup de shells
#     bash), sinon 7-Zip (Git Bash Windows). 7z cherche : PATH puis installations
#     standard, puis tools/7-Zip du projet.
ARCHIVER=""; SEVENZIP=""
if command -v zip >/dev/null 2>&1; then
  ARCHIVER="zip"
else
  for c in 7z 7za; do
    if command -v "$c" >/dev/null 2>&1; then SEVENZIP="$(command -v "$c")"; ARCHIVER="7z"; break; fi
  done
  if [ -z "$ARCHIVER" ]; then
    for p in "/c/Program Files/7-Zip/7z.exe" "/c/Program Files (x86)/7-Zip/7z.exe" \
             "$PWD/tools/7-Zip/7z.exe" "$PWD/tools/7zip/7z.exe"; do
      if [ -x "$p" ]; then SEVENZIP="$p"; ARCHIVER="7z"; break; fi
    done
  fi
fi
if [ -z "$ARCHIVER" ]; then
  echo "ERREUR : aucun archiveur trouve (ni 'zip', ni 7-Zip)."
  echo "  - Git Bash (Windows) ne fournit pas 'zip' : installez 7-Zip en double-cliquant"
  echo "    installers/7z2602-x64.exe  (ou copiez 7z.exe + 7z.dll dans tools/7-Zip/), puis relancez."
  echo "  - Sur un shell disposant du paquet 'zip', installez-le et relancez."
  exit 1
fi
echo ">> Archiveur : $ARCHIVER$( [ -n "$SEVENZIP" ] && echo "  ($SEVENZIP)" )"

# Dossier de sortie DEDIE (cree s'il n'existe pas). Racine du projet propre.
OUTDIR="archives"
mkdir -p "$OUTDIR"

STAMP="$(date +%Y%m%d-%H%M)"
NAME="OutlookSpamAddin-migration-${STAMP}.zip"   # nom de base (affichage / cible)
OUT="$OUTDIR/$NAME"                              # chemin complet de l'archive

if [ "$SANS_LAYOUT" = "1" ]; then
  echo ">> --sans-layout : le layout Visual Studio est EXCLU (archive legere ; layout a transporter a part)."
else
  echo ">> Le layout Visual Studio (installers/vslayout) est INCLUS dans l'archive."
fi

# Garde-fou : cle privee presente -> on PREVIENT (exclue, transport separe chiffre).
KEYS_FOUND="$(find . -type f \( -iname '*.pfx' -o -iname '*.p12' -o -iname '*.snk' -o -iname '*attachments.desc*' \) -not -path './.git/*' 2>/dev/null || true)"
if [ -n "$KEYS_FOUND" ]; then
  echo ">> SECURITE : cle(s) privee(s)/secret(s) detecte(s) - EXCLUS de l'archive (a transporter separement, canal chiffre) :"
  printf '     %s\n' $KEYS_FOUND
fi

echo ">> Compression en cours ($ARCHIVER ; avec le layout, cela peut prendre plusieurs minutes)..."
rm -f "$OUT" "${OUT}".[0-9][0-9][0-9] "${OUT}._part_"* 2>/dev/null || true

# DEUX PASSES (indispensable) :
#   Passe 1 : tout le projet SAUF le layout, avec TOUTES les exclusions de securite
#             (.git, archives/, *.zip, logs, corbeille, ET secrets/cles privees).
#   Passe 2 : le layout (installers/vslayout) ajoute INTEGRALEMENT, SANS les filtres
#             generiques. Raison : le layout contient des CHARGES OFFICIELLES Microsoft
#             en .zip (ex. aspnetcore-runtime-x64.zip, windowsdesktop-runtime-x64.zip)
#             et des certificats publics (certificates/*.cer). Les exclure rendait le
#             layout INUTILISABLE hors ligne : paquets manquants a la verification
#             d'integrite -> installation VS en echec code 8005 ("verifying source
#             payloads failed"). L'exclusion des secrets reste appliquee au RESTE du projet ; le layout
#             Microsoft ne contient aucun secret du projet.
if [ "$ARCHIVER" = "zip" ]; then
  ZEXC=( -x '.git/*' -x '*.fuse_hidden*' -x '*.DS_Store' -x 'archives/*' -x '*.zip' -x 'logs/*' -x 'release/*' -x 'webaddin/deploy/out/*' -x 'webaddin/deploy/deploy.env' \
         -x 'installers/vslayout-partiel-*/*' -x 'vslayout-partiel-*/*' \
         -x 'installers/vslayout/*' -x 'vslayout/*' \
         -x 'certs/*' -x '*.pfx' -x '*.p12' -x '*.snk' -x '*.pvk' -x '*.key' -x '*attachments.desc*' )
  # -9 max ; -n : stocke sans recompresser les types deja compresses (rapide).
  zip -r -q -9 -n .exe:.vsix:.zip:.png:.ico:.msi:.pdf:.cab:.opc:.nupkg:.msu:.msp "$OUT" . "${ZEXC[@]}"
else
  ZEXC=( '-xr!.git' '-xr!.DS_Store' '-xr!*.fuse_hidden*' '-xr!archives' '-xr!*.zip' '-xr!logs' '-xr!release' '-xr!out' '-xr!deploy.env' \
         '-xr!vslayout-partiel-*' '-xr!vslayout' \
         '-xr!certs' '-xr!*.pfx' '-xr!*.p12' '-xr!*.snk' '-xr!*.pvk' '-xr!*.key' '-xr!*attachments.desc*' )
  # -tzip format .zip universel ; -mx=1 rapide (layout deja quasi incompressible).
  "$SEVENZIP" a -tzip -mx=1 -y "$OUT" . "${ZEXC[@]}" >/dev/null
fi

# Passe 2 : ajout INTEGRAL du layout (sauf --sans-layout). Seuls les artefacts
# systeme (.DS_Store, .fuse_hidden) sont ecartes - AUCUN filtre *.zip / *.p12 ici.
if [ "$SANS_LAYOUT" != "1" ] && [ -d installers/vslayout ]; then
  echo ">> Ajout du layout Visual Studio (passe 2, INTEGRALE : charges .zip et certificats compris)..."
  if [ "$ARCHIVER" = "zip" ]; then
    zip -g -r -q -9 -n .exe:.vsix:.zip:.png:.ico:.msi:.pdf:.cab:.opc:.nupkg:.msu:.msp "$OUT" installers/vslayout -x '*.DS_Store' -x '*.fuse_hidden*'
  else
    "$SEVENZIP" a -tzip -mx=1 -y "$OUT" installers/vslayout '-xr!.DS_Store' '-xr!*.fuse_hidden*' >/dev/null
  fi
elif [ "$SANS_LAYOUT" != "1" ] && [ -d vslayout ]; then
  echo ">> ATTENTION : dossier vslayout/ a la RACINE ignore - placez le layout dans installers/vslayout puis relancez."
fi

SIZE_B="$(wc -c < "$OUT" | tr -d ' ')"
SIZE="$(du -h "$OUT" | cut -f1)"
echo "Archive creee : $OUT  (taille : $SIZE)"

# Integrite : test de l'archive complete AVANT decoupage (avec l'outil disponible).
_test_ok=0
if [ "$ARCHIVER" = "7z" ]; then
  "$SEVENZIP" t "$OUT" >/dev/null 2>&1 && _test_ok=1
elif command -v unzip >/dev/null 2>&1; then
  unzip -t "$OUT" >/dev/null 2>&1 && _test_ok=1
else
  _test_ok=2   # pas d'outil de test
fi
case "$_test_ok" in
  1) echo "OK : archive integre." ;;
  0) echo "AVERTISSEMENT : test d'integrite echoue — verifiez l'archive avant de l'utiliser." ;;
  2) echo "(test d'integrite ignore : aucun outil de verification disponible)" ;;
esac

FAT32_MAX=4294967295          # 4 Gio - 1 octet : taille max d'un fichier sur FAT32
SPLIT=0
if [ "$SIZE_B" -gt "$FAT32_MAX" ]; then
  # Decoupe EQUILIBREE : autant de volumes que necessaire pour que CHACUN reste
  # bien sous la limite FAT32 (plafond de securite 3900 Mio), tous de taille ~egale.
  # Archive ~4,4 Go -> 2 volumes ~2,2 Go. On decoupe en fragments d'octets (`split`,
  # options PORTABLES : -b <N>M + suffixes par defaut), puis on renomme en
  # .zip.001/.002... (que 7-Zip recolle et extrait tout seul depuis le .001).
  VOL_CEIL_B=$((3900 * 1024 * 1024))
  NVOL=$(( (SIZE_B + VOL_CEIL_B - 1) / VOL_CEIL_B ))
  [ "$NVOL" -lt 2 ] && NVOL=2
  SPLIT_MB=$(( (SIZE_B / NVOL / 1024 / 1024) + 9 ))
  echo ">> Archive > 4 Go : DECOUPAGE en $NVOL volumes equilibres (~${SPLIT_MB} Mio chacun, < 4 Go -> cle FAT32 OK)..."
  rm -f "${OUT}".[0-9][0-9][0-9] "${OUT}._part_"* 2>/dev/null || true
  if split -b "${SPLIT_MB}M" "$OUT" "${OUT}._part_" ; then
    # fragments ._part_aa, ._part_ab... (ordre alphabetique = ordre correct) -> .001/.002
    i=1
    for f in "${OUT}._part_"*; do
      printf -v suf "%03d" "$i"
      mv -- "$f" "${OUT}.${suf}"
      i=$((i + 1))
    done
    rm -f "$OUT"
    SPLIT=1
    echo ">> Volumes crees dans $OUTDIR/ (copier TOUS ces fichiers ensemble, dans le meme dossier, sur la cible) :"
    ls -1 "${OUT}".[0-9][0-9][0-9] 2>/dev/null | sed 's/^/     /'
    echo "   Extraction sur le poste cible : clic droit sur ${NAME}.001 -> 7-Zip -> Extraire (il lit tous les volumes)."
    echo "   (ou, en invite de commandes Windows :  copy /b \"${NAME}.*\" complet.zip   puis extraire complet.zip)."
  else
    echo ">> Echec du decoupage. Copie l'archive unique sur un support exFAT/NTFS (pas FAT32)."
  fi
else
  echo ">> Taille < 4 Go : copiable telle quelle, y compris sur une cle FAT32."
fi

# SECURITE : empreinte(s) SHA-256 pour verifier l'AUTHENTICITE sur le poste cible.
# A transmettre par un canal DISTINCT de l'archive, et verifier AVANT extraction :
#   PowerShell:  Get-FileHash .\<fichier> -Algorithm SHA256   (comparer au .sha256)
# On se place DANS archives/ pour que le .sha256 reference des NOMS SIMPLES (portables).
hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then hash_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then hash_cmd="shasum -a 256"; fi
if [ -n "$hash_cmd" ]; then
  if [ "$SPLIT" = "1" ]; then
    ( cd "$OUTDIR" && $hash_cmd "${NAME}".[0-9][0-9][0-9] 2>/dev/null | tee "${NAME}.sha256" )
    echo "Empreintes SHA-256 des volumes : $OUTDIR/${NAME}.sha256  (a transmettre separement)"
  else
    ( cd "$OUTDIR" && $hash_cmd "$NAME" | tee "$NAME.sha256" )
    echo "Empreinte SHA-256 : $OUT.sha256  (a transmettre separement, puis verifier avant extraction)"
  fi
else
  echo "AVERTISSEMENT : ni sha256sum ni shasum disponibles — empreinte NON generee."
fi

# LISEZMOI depose A COTE de l'archive (demande utilisateur : un mode d'emploi
# visible AVANT extraction, dans archives/ meme). Volontairement SANS accents :
# lisible partout, y compris le Bloc-notes d'un Windows ancien.
LISEZ="$OUTDIR/LISEZMOI-${STAMP}.txt"
{
  echo "================================================================"
  echo " LISEZMOI - Archive de migration BoutonSPAM"
  echo " Archive : $NAME"
  echo " Generee : $(date '+%d/%m/%Y %H:%M')"
  echo "================================================================"
  echo ""
  echo "CONTENU : le projet complet (sources, scripts, installeurs,"
  echo "documentation, layout Visual Studio hors ligne ~4 Go)."
  echo "AUCUN secret embarque : les certificats (.p12/.pfx) ne sont"
  echo "JAMAIS inclus, et branding.conf reste propre a chaque poste."
  echo ""
  echo "1) VERIFIER L'AUTHENTICITE (avant toute extraction)"
  echo "   PowerShell :  Get-FileHash .\\<fichier> -Algorithm SHA256"
  echo "   Comparer au contenu du fichier .sha256 de ce dossier"
  echo "   (a transmettre par un canal SEPARE de l'archive)."
  echo ""
  echo "2) SI VOUS VOYEZ DES VOLUMES ${NAME}.001 / .002 ..."
  echo "   Copier TOUS les volumes dans le MEME dossier, puis :"
  echo "   - clic droit sur le .001 -> 7-Zip -> Extraire (il recolle tout) ;"
  echo "   - ou en invite de commandes :"
  echo "       copy /b \"${NAME}.*\" complet.zip"
  echo "     puis extraire complet.zip."
  echo "   NB : ouvrir le .001 SEUL affiche une liste INCOMPLETE - normal,"
  echo "   le repertoire de l'archive vit dans le DERNIER volume."
  echo ""
  echo "3) EXTRAIRE puis COMMENCER"
  echo "   - Extraire vers une RACINE COURTE, ex. C:\\OSA"
  echo "     IMPERATIF - limite Visual Studio : l'installeur refuse un layout"
  echo "     dont le chemin depasse 80 CARACTERES (\"Le repertoire de"
  echo "     disposition source est trop long\"). C:\\OSA\\installers\\vslayout"
  echo "     fait 24 caracteres : OK. Un chemin du type"
  echo "     C:\\Dev\\<projet>\\<archive-horodatee>\\installers\\vslayout"
  echo "     depasse la limite et l'installation echoue."
  echo "     Deja extrait trop profond ? ->  move <dossier> C:\\OSA"
  echo "     puis relancer .\\scripts\\01_verification-poste.ps1 -Setup"
  echo "     (il reprend ou il en etait)."
  echo "   - Lire le README du projet (section Archive portable)"
  echo "   - Tout-en-un :"
  echo "       powershell -ExecutionPolicy Bypass -File .\\scripts\\05_assistant.ps1"
  echo "     (ou pas a pas : .\\scripts\\01_verification-poste.ps1 -Setup)"
  echo "================================================================"
} > "$LISEZ"
echo "Mode d'emploi depose a cote de l'archive : $LISEZ"
