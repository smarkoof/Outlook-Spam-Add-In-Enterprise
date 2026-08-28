#!/usr/bin/env bash
# ============================================================================
#  report-content.sh — rend éditable en UN endroit le contenu embarqué dans
#  le rapport (note multilingue, horodatage, phrases de diagnostic, easter egg).
#
#  Opération UNIQUE (refactorisation) : après l'avoir lancée, éditez directement
#  la « ZONE DE PERSONNALISATION » ajoutée en tête de Config.vb.
#  Ajuste éventuellement les textes ci-dessous AVANT de lancer.
#  À exécuter sur macOS ; recompilation ensuite dans Visual Studio.
# ============================================================================
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

PROJDIR="$(dirname "$(ls */*.vbproj 2>/dev/null | head -1)")"
CONFIGVB="$PROJDIR/Config.vb"
RIBBONVB="$PROJDIR/Ribbon.vb"
for f in "$CONFIGVB" "$RIBBONVB"; do
  [ -f "$f" ] || { echo "ERREUR: fichier manquant -> $f"; exit 1; }
done

# Garde-fou : ne pas appliquer deux fois (sinon constantes dupliquées).
if grep -q 'reportDateFormat' "$CONFIGVB"; then
  echo "Déjà appliqué (constante reportDateFormat présente). Rien à faire."
  exit 0
fi

# ---- TEXTES ÉDITABLES ------------------------------------------------------
NOTE_EN="This is a user-submitted report of a suspicious email. Please review the attached message."
NOTE_FR="Ceci est un signalement d'email suspect soumis par un utilisateur. Merci d'examiner le message ci-joint."
NOTE_DE="Dies ist eine von einem Benutzer gemeldete verdächtige E-Mail. Bitte prüfen Sie die angehängte Nachricht."
NOTE_IT="Questa è una segnalazione di email sospetta inviata da un utente. Si prega di esaminare il messaggio allegato."

DATE_LABEL="Signalé le : "
DATE_FORMAT="yyyy-MM-dd HH:mm:ss"

MSG_ENCRYPTED="Email chiffré"
MSG_SIGNED="Email signé"
MSG_SWISS="Domaine national utilisé"
MSG_LINKS="{0} lien(s) dans l'email suspect"
MSG_ATTACH="{0} pièce(s) jointe(s) dans l'email suspect"
TAG_BLOCKLEVEL=" Blocklevel"
TAG_BLACKLISTED=" **Blacklisted**"

# Regex de détection du domaine national (heuristique de priorité).
# Original suisse ; pour la France, mettez par ex. (\.fr$)
NATIONAL_REGEX='(\.ch$|\.li$)'

EASTEREGG_TITLE="Information"
EASTEREGG_MSG="Désolé, les œufs de Pâques sont trop fragiles pour voyager par email. Merci de votre compréhension."
# ----------------------------------------------------------------------------

# helper : remplace tout le contenu (RHS) d'une constante String par une valeur
setconst () { # $1=fichier $2=nomConstante  (valeur via env VAL)
  ID="$2" perl -pi -e 's{(\Q$ENV{ID}\E As String = ").*("(?:\s*&\s*vbCrLf)?\s*)$}{"$1".$ENV{VAL}."$2"}e' "$1"
}
# helper : remplace un littéral figé par un autre texte (ancre exacte)
litswap () { # $1=fichier  (FROM/TO via env)
  perl -pi -e 's{\Q$ENV{FROM}\E}{$ENV{TO}}g' "$1"
}

echo ">> Config.vb : note multilingue (dé-brandée + traduite)"
VAL="$NOTE_EN" setconst "$CONFIGVB" reportEmailBodyEN
# les 3 alias deviennent des constantes autonomes
FROM='Private Const reportEmailBodyDE As String = reportEmailBodyEN' TO="Private Const reportEmailBodyDE As String = \"$NOTE_DE\" & vbCrLf" litswap "$CONFIGVB"
FROM='Private Const reportEmailBodyFR As String = reportEmailBodyEN' TO="Private Const reportEmailBodyFR As String = \"$NOTE_FR\" & vbCrLf" litswap "$CONFIGVB"
FROM='Private Const reportEmailBodyIT As String = reportEmailBodyEN' TO="Private Const reportEmailBodyIT As String = \"$NOTE_IT\" & vbCrLf" litswap "$CONFIGVB"

echo ">> Config.vb : insertion de la ZONE DE PERSONNALISATION"
BLOCK="$(cat <<VBEOF

    ' ================================================================
    '  ZONE DE PERSONNALISATION — contenu embarqué dans le rapport
    '  Éditez librement les textes ci-dessous, puis recompilez.
    ' ================================================================
    ' Horodatage ajouté en tête du rapport (False pour le désactiver)
    Friend Const reportDateEnabled As Boolean = True
    Friend Const reportDateLabel As String = "$DATE_LABEL"
    Friend Const reportDateFormat As String = "$DATE_FORMAT"
    ' Annotations de diagnostic ajoutées au corps du rapport
    Friend Const reportMsgEncrypted As String = "$MSG_ENCRYPTED"
    Friend Const reportMsgSigned As String = "$MSG_SIGNED"
    Friend Const reportMsgSwissDomain As String = "$MSG_SWISS"
    Friend Const reportMsgLinks As String = "$MSG_LINKS"
    Friend Const reportMsgAttachments As String = "$MSG_ATTACH"
    Friend Const reportTagBlocklevel As String = "$TAG_BLOCKLEVEL"
    Friend Const reportTagBlacklisted As String = "$TAG_BLACKLISTED"
    ' Détection du domaine national (heuristique de priorité)
    Friend Const reportNationalDomainRegex As String = "__NATREGEX__"
    ' Easter egg (pièce jointe nommée *easter.egg)
    Friend Const easterEggTitle As String = "$EASTEREGG_TITLE"
    Friend Const easterEggMsg As String = "$EASTEREGG_MSG"
    ' ================================================================
VBEOF
)"
BLOCK="$BLOCK"$'\n'
export BLOCK
perl -i -pe 's{(^\s*Friend Const exceptionEmailSubject As String = "\[SPAMx\]"\s*\n)}{$1.$ENV{BLOCK}}e' "$CONFIGVB"
# Valeur du regex national injectée via l'env (sûr pour $ et \)
VAL="$NATIONAL_REGEX" perl -pi -e 's{__NATREGEX__}{$ENV{VAL}}' "$CONFIGVB"

echo ">> Ribbon.vb : horodatage en tête du corps"
FROM='reportEmail.Body = reportEmailBody' \
TO='reportEmail.Body = If(Config.reportDateEnabled, Config.reportDateLabel & Now.ToString(Config.reportDateFormat) & vbCrLf & vbCrLf, "") & reportEmailBody' \
litswap "$RIBBONVB"

echo ">> Ribbon.vb : littéraux -> constantes Config"
FROM='reportEmail.Body += "Phishing email was encrypted"' TO='reportEmail.Body += Config.reportMsgEncrypted' litswap "$RIBBONVB"
FROM='reportEmail.Body += "Phishing email was signed"'    TO='reportEmail.Body += Config.reportMsgSigned'    litswap "$RIBBONVB"
FROM='reportEmail.Body += "Swiss domain used"'            TO='reportEmail.Body += Config.reportMsgSwissDomain' litswap "$RIBBONVB"
FROM='SenderEmailAddress, "(\.ch$|\.li$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Success' \
TO='SenderEmailAddress, Config.reportNationalDomainRegex, System.Text.RegularExpressions.RegexOptions.IgnoreCase).Success' litswap "$RIBBONVB"
FROM='attachmentPrint += " Blocklevel"'                   TO='attachmentPrint += Config.reportTagBlocklevel'  litswap "$RIBBONVB"
FROM='attachmentPrint += " **Blacklisted**"'              TO='attachmentPrint += Config.reportTagBlacklisted' litswap "$RIBBONVB"
FROM='linksCount & " link" & If(linksCount > 1, "s", "") & " in phishing email"' \
TO='String.Format(Config.reportMsgLinks, linksCount)' litswap "$RIBBONVB"
FROM='attachmentCount & " attachment" & If(attachmentCount > 1, "s", "") & " in phishing email"' \
TO='String.Format(Config.reportMsgAttachments, attachmentCount)' litswap "$RIBBONVB"
FROM='MsgBox("Sorry, but Easter eggs are unfortunately too fragile To be transported by email." & vbCrLf & "Thank you For your understanding." & vbCrLf & "Your #SOC", MsgBoxStyle.Information Or MsgBoxStyle.OkOnly, "Information")' \
TO='MsgBox(Config.easterEggMsg, MsgBoxStyle.Information Or MsgBoxStyle.OkOnly, Config.easterEggTitle)' litswap "$RIBBONVB"

echo
echo "Terminé. Vérifiez :  git --no-pager diff"
