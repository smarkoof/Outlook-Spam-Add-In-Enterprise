#!/usr/bin/env bash
# =============================================================================
#  apply-config.sh — génère les fichiers personnalisés du complément à partir
#  de deploy.env. Rend dans deploy/out/ : manifest.xml et src/config.json.
#  Ne touche RIEN au système : il ne fait qu'écrire des fichiers dans out/.
#
#  Usage :   cp deploy.env.example deploy.env && nano deploy.env
#            ./apply-config.sh                     # ou ./apply-config.sh mon.env
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENVFILE="${1:-$HERE/deploy.env}"
OUT="$HERE/out"

[ -f "$ENVFILE" ] || { echo "ERREUR : $ENVFILE introuvable (copier deploy.env.example -> deploy.env)"; exit 1; }
# SECURITE : deploy.env est EXECUTE (source ci-dessous).
# Refuser s'il est inscriptible par le groupe ou les autres (injection possible).
if [ -n "$(find "$ENVFILE" -maxdepth 0 -perm /022 2>/dev/null)" ]; then
  echo "ERREUR : $ENVFILE est inscriptible par le groupe/autres."
  echo "  Ce fichier est execute par ce script. Faites : chmod 600 \"$ENVFILE\"  puis relancez."
  exit 1
fi
# shellcheck disable=SC1090
. "$ENVFILE"

# --- Contrôles fail-close ----------------------------------------------------
[ -n "${ADDIN_FQDN:-}" ] || { echo "ERREUR : variable 'ADDIN_FQDN' vide dans $ENVFILE"; exit 1; }
if [ -z "${ABUSE_TO:-}" ]; then
  echo "ERREUR : ABUSE_TO est vide. Par sécurité (fail-close) le complément refuserait"
  echo "         d'envoyer. Renseignez la boîte abuse dans $ENVFILE avant de générer."
  exit 1
fi

# GUID : généré si absent (source noyau, sans dépendance)
if [ -z "${ADDIN_ID:-}" ]; then
  if [ -r /proc/sys/kernel/random/uuid ]; then ADDIN_ID="$(cat /proc/sys/kernel/random/uuid)";
  else ADDIN_ID="$(python3 -c 'import uuid;print(uuid.uuid4())')"; fi
  echo ">> ADDIN_ID vide -> GUID généré : $ADDIN_ID"
  echo "   (fige-le dans $ENVFILE pour conserver le même identifiant aux mises à jour)"
fi

: "${ABUSE_CC:=}" "${REPORT_SUBJECT_PREFIX:=[SPAM]}"

mkdir -p "$OUT"

echo ">> Génération dans : $OUT"

# --- 1) manifeste ------------------------------------------------------------
sed \
  -e "s|11111111-2222-3333-4444-555555555555|${ADDIN_ID}|g" \
  -e "s|addin\.interne\.example|${ADDIN_FQDN}|g" \
  "$HERE/../manifest.xml" > "$OUT/manifest.xml"

# --- 2) config.json (édition JSON sûre) -------------------------------------
python3 - "$HERE/../config.example.json" "$OUT/config.json" \
  "$ABUSE_TO" "$ABUSE_CC" "$REPORT_SUBJECT_PREFIX" <<'PY'
import json, sys
src, dst, to, cc, prefix = sys.argv[1:6]
d = json.load(open(src, encoding="utf-8"))
d["abuseTo"] = to
d["abuseCc"] = cc
d["reportSubjectPrefix"] = prefix
json.dump(d, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print()
PY

# --- Validations best-effort -------------------------------------------------
echo ">> Contrôles :"
python3 -c "import json;json.load(open('$OUT/config.json'))" && echo "   [ok] config.json (JSON valide)"
python3 -c "import xml.dom.minidom as M;M.parse('$OUT/manifest.xml')" && echo "   [ok] manifest.xml (XML bien formé)"

# --- Récapitulatif -----------------------------------------------------------
cat > "$OUT/RESUME-copie.txt" <<EOF
Fichiers générés (à publier sur votre hébergement HTTPS interne) :

  out/manifest.xml  ->  /manifest.xml    (servi en https://${ADDIN_FQDN}/manifest.xml)
  out/config.json   ->  /src/config.json

Déploiement Exchange (pilote) :
  New-App -OrganizationApp -Url "https://${ADDIN_FQDN}/manifest.xml" -DefaultStateForUser Disabled

Détails : ../README-DEPLOIEMENT.md
EOF

echo ""
echo ">> Terminé. Voir $OUT/ (et RESUME-copie.txt pour les emplacements)."
echo "   GUID du manifeste : ${ADDIN_ID}"
