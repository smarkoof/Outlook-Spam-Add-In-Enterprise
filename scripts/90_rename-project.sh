#!/usr/bin/env bash
# ============================================================================
#  rename-project.sh — renomme les fichiers/dossiers de dev portant l'ancien nom
#  vers un slug générique (PROJECT_SLUG), et met à jour les références dans
#  le .sln et le .vdproj. Le NAMESPACE interne est PRÉSERVÉ (les ressources
#  continuent de charger). Opération UNIQUE, via git mv (historique conservé).
# ============================================================================
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

[ -f branding.conf ] && source ./branding.conf || true
SLUG="${PROJECT_SLUG:-${MSI_BASENAME:-OutlookSpamAddin}}"
SLUG="$(printf '%s' "$SLUG" | tr -cd 'A-Za-z0-9._-')"
[ -n "$SLUG" ] || { echo "ERREUR: PROJECT_SLUG invalide."; exit 1; }

# Découverte de l'existant
OLD_VBPROJ="$(ls */*.vbproj 2>/dev/null | head -1)"
[ -n "$OLD_VBPROJ" ] || { echo "ERREUR: aucun .vbproj trouvé."; exit 1; }
OLD_DIR="$(dirname "$OLD_VBPROJ")"
OLD_VBPROJ_BASE="$(basename "$OLD_VBPROJ")"
OLD_NAME="${OLD_VBPROJ_BASE%.vbproj}"

if [ "$OLD_DIR" = "$SLUG" ] && [ "$OLD_NAME" = "$SLUG" ]; then
  echo "Déjà renommé ($SLUG). Rien à faire."
  exit 0
fi

# Commande de déplacement (git si dispo, sinon mv)
if git rev-parse --git-dir >/dev/null 2>&1; then MV="git mv"; else MV="mv"; fi

echo ">> Renommage dossier + projet + solution + .reg"
$MV "$OLD_DIR" "$SLUG"
$MV "$SLUG/$OLD_VBPROJ_BASE" "$SLUG/$SLUG.vbproj"
OLD_SLN="$(ls *.sln 2>/dev/null | head -1)"
[ -n "$OLD_SLN" ] && [ "$OLD_SLN" != "$SLUG.sln" ] && $MV "$OLD_SLN" "$SLUG.sln"
OLD_REG="$(ls resources/DoNotDisableAddinList*.reg 2>/dev/null | head -1)"
[ -n "$OLD_REG" ] && [ "$OLD_REG" != "resources/DoNotDisableAddinList.reg" ] \
  && $MV "$OLD_REG" "resources/DoNotDisableAddinList.reg"

echo ">> Mise à jour des références (.sln, .vdproj)"
SLN="$SLUG.sln"
VDPROJ="$(ls setup/*.vdproj 2>/dev/null | head -1)"
# Le nom du projet (PascalCase) : chemin + libellé d'affichage dans le .sln
OLDN="$OLD_NAME" NEW="$SLUG" perl -pi -e 's{\Q$ENV{OLDN}\E}{$ENV{NEW}}g' "$SLN"
# Le dossier (token distinctif) : dans .sln ET .vdproj. Le NAMESPACE (même
# chaîne mais dans les .vb) n'est PAS touché ici.
OLDD="$(basename "$OLD_DIR")" NEW="$SLUG" perl -pi -e 's{\Q$ENV{OLDD}\E}{$ENV{NEW}}g' "$SLN"
[ -n "$VDPROJ" ] && OLDD="$(basename "$OLD_DIR")" NEW="$SLUG" perl -pi -e 's{\Q$ENV{OLDD}\E}{$ENV{NEW}}g' "$VDPROJ"

echo
echo "Terminé -> slug : $SLUG"
echo "Le namespace interne reste inchangé (chargement des ressources préservé)."
echo "Vérifiez :  git status  &&  git --no-pager diff -- '$SLN' '$VDPROJ'"
