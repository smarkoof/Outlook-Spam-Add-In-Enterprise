#!/usr/bin/env bash
# ============================================================================
#  02_customize.sh — applique branding.conf à l'ensemble de la solution.
#  Ré-exécutable (lit les valeurs courantes à chaud). N'exige aucune
#  compilation : pur traitement de texte, tourne sur macOS et Git Bash.
#  Vit dans scripts/ ; travaille toujours à la RACINE du projet.
#  Lancement :   ./scripts/02_customize.sh
# ============================================================================
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p logs
exec > >(tee -a "logs/customize-$(date +%Y%m%d-%H%M%S).log") 2>&1

[ -f branding.conf ] || { echo "ERREUR: branding.conf introuvable."; exit 1; }
# shellcheck disable=SC1091
source ./branding.conf

VBPROJ="$(ls */*.vbproj 2>/dev/null | head -1)"
[ -n "$VBPROJ" ] || { echo "ERREUR: projet .vbproj introuvable."; exit 1; }
PROJDIR="$(dirname "$VBPROJ")"
ASMINFO="$PROJDIR/My Project/AssemblyInfo.vb"
CONFIGVB="$PROJDIR/Config.vb"
RIBBONVB="$PROJDIR/Ribbon.vb"
THISADDIN="$PROJDIR/ThisAddIn.vb"
VDPROJ="$(ls setup/*.vdproj 2>/dev/null | head -1)"
REGCONF="resources/RegistryConfig.reg"
REGNODIS="$(ls resources/DoNotDisableAddinList*.reg 2>/dev/null | head -1)"

for f in "$VBPROJ" "$ASMINFO" "$CONFIGVB" "$RIBBONVB" "$THISADDIN" "$VDPROJ" "$REGCONF" "$REGNODIS"; do
  [ -f "$f" ] || { echo "ERREUR: fichier manquant -> $f"; exit 1; }
done

# --- GARDE-FOU SUPPORT_URL (vécu sur poste réel) -----------------------------
# Cette valeur part dans ARPHELPLINK du projet Setup (.vdproj). Ce champ
# n'accepte qu'une URL http:// ou https:// : toute autre forme (mailto:,
# chemin, texte libre) rend le projet Setup ILLISIBLE pour Visual Studio —
# la solution affiche « Unable to open project ... Setup.vdproj » SANS autre
# message, et la fabrication du MSI devient impossible. Refus net ICI, avant
# d'écrire quoi que ce soit.
if [ -n "${SUPPORT_URL:-}" ]; then
  case "$SUPPORT_URL" in
    http://*|https://*) : ;;
    *)
      echo "ERREUR: SUPPORT_URL doit être une URL http:// ou https:// (valeur lue : $SUPPORT_URL)."
      echo "        Ce champ alimente ARPHELPLINK du projet d'installation : sous une autre forme"
      echo "        (mailto: compris), Visual Studio refuse ensuite d'OUVRIR Setup.vdproj"
      echo "        (« Unable to open project », sans explication) et le MSI ne peut plus être fabriqué."
      echo "        Mettez ici une page web/intranet (ex. https://intranet/equipe-securite)."
      echo "        Le contact par e-mail, lui, se règle avec REPORT_TO / REPORT_CC."
      exit 1
      ;;
  esac
fi

VERSION_3="$(printf '%s' "$VERSION" | cut -d. -f1-3)"

# --- GARDE-FOU DE VERSION : la version ne doit JAMAIS diminuer --------------
# La version affichée dans « Programmes et fonctionnalités » (et comparée par
# Windows Installer pour les mises à niveau) doit toujours MONTER.
ver_lt () { # renvoie 1 si $1 < $2 (comparaison numérique champ par champ)
  awk -v a="$1" -v b="$2" 'BEGIN{
    n=split(a,x,"."); m=split(b,y,".");
    for(i=1;i<=4;i++){ xa=(i<=n?x[i]:0)+0; yb=(i<=m?y[i]:0)+0;
      if(xa<yb){print 1; exit} if(xa>yb){print 0; exit} }
    print 0 }'
}
# Lit UNIQUEMENT la vraie AssemblyVersion : ligne NON commentee (^\s*<Assembly:),
# valeur PUREMENT NUMERIQUE (ignore l'exemple commente "1.0.*"), 1re occurrence.
CUR_VER="$(perl -ne 'if (m{^\s*<Assembly:\s*AssemblyVersion\("([0-9][0-9.]*)"\)>}) { print $1; exit }' "$ASMINFO" 2>/dev/null || true)"
if [ -n "$CUR_VER" ] && [ "$(ver_lt "$VERSION" "$CUR_VER")" = "1" ]; then
  if [ "${FORCE_VERSION:-0}" = "1" ]; then
    echo ">> AVERTISSEMENT : retour de version FORCÉ ($CUR_VER -> $VERSION) car FORCE_VERSION=1."
    echo "   Réservé au démarrage d'une NOUVELLE BASE — jamais sur un produit déjà déployé."
  else
    echo "ERREUR: VERSION de branding.conf ($VERSION) est INFÉRIEURE à la version actuelle du projet ($CUR_VER)."
    echo "        Une version ne doit jamais diminuer (Windows la considérerait comme plus ancienne"
    echo "        et refuserait la mise à niveau). Corrigez VERSION dans branding.conf, puis relancez."
    echo "        Cas particulier — repartir d'une base vierge (produit NON déployé) :"
    echo "        FORCE_VERSION=1 ./scripts/02_customize.sh"
    exit 1
  fi
fi
if [ -n "$CUR_VER" ] && [ "$CUR_VER" != "$VERSION" ] && [ "$(ver_lt "$VERSION" "$CUR_VER")" != "1" ]; then
  echo ">> Montée de version : $CUR_VER -> $VERSION"
fi

# Nom de base du MSI : générique, sans espace. Défaut = MSI_BASENAME, sinon
# dérivé de PRODUCT_NAME. Caractères non sûrs (espaces inclus) retirés.
MSI_BASE="$(printf '%s' "${MSI_BASENAME:-$PRODUCT_NAME}" | tr -cd 'A-Za-z0-9._-')"
[ -n "$MSI_BASE" ] || MSI_BASE="Setup"
MSI_NAME="${MSI_BASE}-${VERSION_3}"

# Nom de produit ACTUEL, lu à chaud dans le .vbproj -> rend le script idempotent.
CUR_ASM="$(perl -ne 'print $1 if m{<AssemblyName>(.*?)</AssemblyName>}' "$VBPROJ")"
[ -n "$CUR_ASM" ] || { echo "ERREUR: <AssemblyName> introuvable dans $VBPROJ"; exit 1; }

# --- petites fabriques de substitution (valeur insérée via l'env => sûre) ----
xml_set () { TAG="$2" VAL="$3" perl -0777 -pi -e \
  's{(<\Q$ENV{TAG}\E>).*?(</\Q$ENV{TAG}\E>)}{"$1".$ENV{VAL}."$2"}se' "$1"; }
asm_set () { ATTR="$2" VAL="$3" perl -pi -e \
  's{^(\s*<Assembly:\s*\Q$ENV{ATTR}\E\(").*?("\)>)}{"$1".$ENV{VAL}."$2"}se' "$1"; }
vd_set  () { KEY="$2" VAL="$3" perl -pi -e \
  's{("\Q$ENV{KEY}\E" = "8:)[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$1"; }
vb_const () { ID="$2" VAL="$3" perl -pi -e \
  's{(\Q$ENV{ID}\E As String = ")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$1"; }

echo ">> .vbproj"
xml_set "$VBPROJ" AssemblyName        "$PRODUCT_NAME"
xml_set "$VBPROJ" ProductName         "$PRODUCT_NAME"
xml_set "$VBPROJ" FriendlyName        "$PRODUCT_NAME"
xml_set "$VBPROJ" PublisherName       "$COMPANY_NAME"
xml_set "$VBPROJ" SupportUrl          "$SUPPORT_URL"
xml_set "$VBPROJ" ApplicationVersion  "$VERSION"

echo ">> AssemblyInfo.vb"
asm_set "$ASMINFO" AssemblyTitle       "$PRODUCT_NAME"
asm_set "$ASMINFO" AssemblyProduct     "$PRODUCT_NAME"
asm_set "$ASMINFO" AssemblyCompany     "$COMPANY_NAME"
asm_set "$ASMINFO" AssemblyDescription "$PRODUCT_DESCRIPTION"
asm_set "$ASMINFO" AssemblyCopyright   "$COPYRIGHT"
asm_set "$ASMINFO" AssemblyVersion     "$VERSION"
asm_set "$ASMINFO" AssemblyFileVersion "$VERSION"

echo ">> Config.vb"
vb_const "$CONFIGVB" configKey     "$REGISTRY_CONFIG_KEY"
vb_const "$CONFIGVB" addinVersion  "$VERSION"

echo ">> Setup.vdproj"
vd_set "$VDPROJ" ProductName    "$PRODUCT_NAME"
vd_set "$VDPROJ" Manufacturer   "$COMPANY_NAME"
vd_set "$VDPROJ" ARPCONTACT     "$COMPANY_NAME"
vd_set "$VDPROJ" ARPHELPLINK    "$SUPPORT_URL"
vd_set "$VDPROJ" ProductVersion "$VERSION_3"
# Nom du fichier MSI de sortie = <MSI_BASENAME>-<version>.msi (sans espace,
# aligné avec sign.ps1). Préfixes Debug\ / Release\ conservés. Idempotent.
VAL="$MSI_NAME" perl -pi -e \
  's#("OutputFilename" = "8:(?:Debug|Release)\\\\)[^\\"]+(\.msi")#"$1".$ENV{VAL}."$2"#ge' "$VDPROJ"
# Dossier d'installation ( ...\<INSTALL_FOLDER>\[ProductName] )
VAL="$INSTALL_FOLDER" perl -pi -e \
  's{(\[ProgramFilesFolder\]\\\\)[^\\]+(\\\\\[ProductName\])}{"$1".$ENV{VAL}."$2"}e' "$VDPROJ"
# Nom de produit dans les chemins de fichiers / manifeste / clé add-in
FROM="$CUR_ASM" TO="$PRODUCT_NAME" perl -pi -e \
  's{\Q$ENV{FROM}\E}{$ENV{TO}}g' "$VDPROJ"

echo ">> *.reg"
VAL="$REGISTRY_CONFIG_KEY" perl -pi -e \
  's{(\[HKEY_LOCAL_MACHINE\\)[^\]]*(\])}{"$1".$ENV{VAL}."$2"}e' "$REGCONF"
FROM="$CUR_ASM" TO="$PRODUCT_NAME" perl -pi -e \
  's{\Q$ENV{FROM}\E}{$ENV{TO}}g' "$REGNODIS"

# LICENSE.md n'est volontairement PAS rebrandé : la licence MIT impose de
# CONSERVER les notices de copyright (milCERT + fork). COPYRIGHT ne s'applique
# qu'aux métadonnées produit (assembly, ARP, en-têtes de sources).

echo ">> En-têtes de copyright (sources)"
for f in "$CONFIGVB" "$RIBBONVB" "$THISADDIN"; do
  VAL="$COPYRIGHT" perl -pi -e "s{^'\s*Copyright.*}{'  \$ENV{VAL}}" "$f"
done

echo ">> Adresses & filtres par défaut"
if [ -n "${REPORT_TO+x}" ]; then
  VAL="$REPORT_TO" perl -pi -e 's{("To"=")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$REGCONF"
fi
if [ -n "${REPORT_CC+x}" ]; then
  VAL="$REPORT_CC" perl -pi -e 's{("Cc"=")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$REGCONF"
  # replis dans Config.vb (valeur de GetValue + branche Else)
  VAL="$REPORT_CC" perl -pi -e 's{(GetValue\("Cc", ")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$CONFIGVB"
  VAL="$REPORT_CC" perl -pi -e 's{(ccSecurityTeamSpamBit = ")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$CONFIGVB"
fi
if [ -n "${REGEX_INTERNAL+x}" ]; then
  # Config.vb (VB : backslash simple)
  VAL="$REGEX_INTERNAL" perl -pi -e 's{(regexDefault As String = ")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$CONFIGVB"
  # RegistryConfig.reg (format .reg : backslash doublé)
  REGEX_REG="${REGEX_INTERNAL//\\/\\\\}"
  VAL="$REGEX_REG" perl -pi -e 's{("Regex"=")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$REGCONF"
fi
# commentaires résiduels

echo ">> Textes utilisateur (ruban, dialogues, rapport)"
# Ne modifie une constante VB que si la variable de branding.conf est NON VIDE.
# (champ vide "" ou absent = texte actuel conservé — champs 100% optionnels)
vb_text () { # $1 = nom de la constante VB, $2 = nouvelle valeur
  [ -n "${2:-}" ] || return 0
  case "$2" in *'"'*) echo "   IGNORE $1 : les guillemets doubles (\") sont interdits dans les textes."; return 0;; esac
  ID="$1" VAL="$2" perl -pi -e 's{(Const \Q$ENV{ID}\E As String = ")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$CONFIGVB"
  echo "   $1 <- $2"
}
# Ruban Outlook (libellé du bouton + info-bulle titre, groupe, descriptions)
vb_text buttonFR                 "${UI_BUTTON_FR:-}"
vb_text buttonScreenTipFR        "${UI_BUTTON_FR:-}"
vb_text groupFR                  "${UI_GROUP_FR:-}"
vb_text buttonHoverDescriptionFR "${UI_BUTTON_TIP_FR:-}"
vb_text buttonSuperTipFR         "${UI_BUTTON_SUPERTIP_FR:-}"
vb_text buttonEN                 "${UI_BUTTON_EN:-}"
vb_text buttonScreenTipEN        "${UI_BUTTON_EN:-}"
vb_text groupEN                  "${UI_GROUP_EN:-}"
vb_text buttonHoverDescriptionEN "${UI_BUTTON_TIP_EN:-}"
vb_text buttonSuperTipEN         "${UI_BUTTON_SUPERTIP_EN:-}"
# Boîte de confirmation (titre) et rapport
vb_text msgBoxConfirmTitleFR     "${UI_CONFIRM_TITLE_FR:-}"
vb_text msgBoxConfirmTitleEN     "${UI_CONFIRM_TITLE_EN:-}"
vb_text reportEmailBodyFR        "${UI_REPORT_BODY_FR:-}"
vb_text reportEmailBodyEN        "${UI_REPORT_BODY_EN:-}"
vb_text reportEmailSubject       "${REPORT_SUBJECT_PREFIX:-}"
vb_text exceptionEmailSubject    "${REPORT_SUBJECT_PREFIX_ERROR:-}"
# Accusé de réception automatique au signaleur
vb_text ackSubjectFR             "${UI_ACK_SUBJECT_FR:-}"
vb_text ackSubjectEN             "${UI_ACK_SUBJECT_EN:-}"
vb_text ackBodyOneFR             "${UI_ACK_BODY_FR:-}"
vb_text ackBodyOneEN             "${UI_ACK_BODY_EN:-}"
vb_text ackBodyMoreFR            "${UI_ACK_BODY_MORE_FR:-}"
vb_text ackBodyMoreEN            "${UI_ACK_BODY_MORE_EN:-}"

ADMX="deploy/ADMX/BoutonSpam.admx"
if [ -f "$ADMX" ]; then
  echo ">> Modèle GPO (ADMX)"
  # clé de configuration (stratégie Machine)
  VAL="$REGISTRY_CONFIG_KEY" perl -pi -e 's{(<policy name="POL_Config"[^>]*key=")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$ADMX"
  # nom de valeur de l'anti-désactivation (stratégie User) = PRODUCT_NAME
  VAL="$PRODUCT_NAME" perl -pi -e 's{(DoNotDisableAddinList" valueName=")[^"]*(")}{"$1".$ENV{VAL}."$2"}e' "$ADMX"
fi

echo ">> Signature du manifeste (.vbproj)"
if [ -n "${CERT_THUMBPRINT:-}" ]; then
  TP="$(printf '%s' "$CERT_THUMBPRINT" | tr -cd '0-9A-Fa-f' | tr 'a-f' 'A-F')"
  if [ -n "$TP" ]; then
    if grep -q '<ManifestCertificateThumbprint>' "$VBPROJ"; then
      VAL="$TP" perl -0777 -pi -e 's{<ManifestCertificateThumbprint>.*?</ManifestCertificateThumbprint>}{"<ManifestCertificateThumbprint>".$ENV{VAL}."</ManifestCertificateThumbprint>"}se' "$VBPROJ"
    else
      VAL="$TP" perl -pi -e 's{(<SignManifests>true</SignManifests>)}{$1."\n    <ManifestCertificateThumbprint>".$ENV{VAL}."</ManifestCertificateThumbprint>"}e' "$VBPROJ"
    fi
    echo "   thumbprint câblé : $TP"
  fi
else
  echo "   (CERT_THUMBPRINT vide — signature non câblée)"
fi
if [ -n "${TIMESTAMP_URL:-}" ]; then
  VAL="$TIMESTAMP_URL" perl -0777 -pi -e 's{<ManifestTimestampUrl>.*?</ManifestTimestampUrl>}{"<ManifestTimestampUrl>".$ENV{VAL}."</ManifestTimestampUrl>"}se' "$VBPROJ"
fi

if [ "${REGEN_GUIDS:-0}" = "1" ]; then
  echo ">> Régénération des GUID (nouvelle identité produit)"
  # Un GUID valide, quel que soit l'outil dispo. ATTENTION Windows/Git Bash :
  # 'python'/'python3' peuvent être de FAUX alias du Microsoft Store qui ne
  # renvoient RIEN -> chaque candidat est VALIDÉ avant d'être accepté.
  # Ordre : uuidgen -> Python EMBARQUÉ du projet (tools/python) -> PowerShell
  # -> python3 système -> repli pur perl (toujours présent dans Git Bash).
  is_guid () { printf '%s' "$1" | grep -qiE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; }
  gen () {
    local g=""
    if command -v uuidgen >/dev/null 2>&1; then g="$(uuidgen 2>/dev/null | tr -d '\r' || true)"; fi
    if ! is_guid "$g" && [ -x "tools/python/python.exe" ]; then
      g="$(tools/python/python.exe -c 'import uuid;print(uuid.uuid4())' 2>/dev/null | tr -d '\r' || true)"
    fi
    if ! is_guid "$g" && command -v powershell.exe >/dev/null 2>&1; then
      g="$(powershell.exe -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null | tr -d '\r' || true)"
    fi
    if ! is_guid "$g" && command -v python3 >/dev/null 2>&1; then
      g="$(python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null | tr -d '\r' || true)"
    fi
    if ! is_guid "$g"; then
      g="$(perl -e 'my @r = map { int(rand(65536)) } 1..8; $r[3] = ($r[3] & 0x0fff) | 0x4000; $r[4] = ($r[4] & 0x3fff) | 0x8000; printf "%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n", @r')"
    fi
    is_guid "$g" || { echo "ERREUR: impossible de générer un GUID."; exit 1; }
    printf '%s\n' "$g"
  }
  up () { gen | tr 'a-f' 'A-F'; }   # majuscules (format vdproj)
  lo () { gen | tr 'A-F' 'a-f'; }   # minuscules (format attribut COM)
  # délimiteur # pour éviter le conflit avec les accolades des GUID.
  # Les motifs tolèrent une valeur actuelle VIDE ou invalide (réparation).
  G1="{$(up)}"; G2="{$(up)}"; G3="{$(up)}"; G4="$(lo)"
  VAL="$G1" perl -pi -e 's#("ProductCode" = "8:)\{[^}]*\}(")#"$1".$ENV{VAL}."$2"#e' "$VDPROJ"
  VAL="$G2" perl -pi -e 's#("PackageCode" = "8:)\{[^}]*\}(")#"$1".$ENV{VAL}."$2"#e' "$VDPROJ"
  VAL="$G3" perl -pi -e 's#("UpgradeCode" = "8:)\{[^}]*\}(")#"$1".$ENV{VAL}."$2"#e' "$VDPROJ"
  VAL="$G4" perl -pi -e 's#(Guid\(")[0-9a-fA-F-]*("\)>)#"$1".$ENV{VAL}."$2"#e' "$ASMINFO"
  echo "   ProductCode = $G1"
  echo "   PackageCode = $G2"
  echo "   UpgradeCode = $G3"
  echo "   Assembly    = $G4"
  echo "   RAPPEL : remets REGEN_GUIDS=0 dans branding.conf — l'identité ne se régénère qu'UNE fois."
fi

echo
echo "Terminé. Vérifiez avec :  git --no-pager diff"
