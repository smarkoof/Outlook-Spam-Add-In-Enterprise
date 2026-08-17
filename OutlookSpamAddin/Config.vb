' MIT License
'
'  Copyright © 2026 MonOrganisation
'
' Permission Is hereby granted, free Of charge, to any person obtaining a copy
' of this software And associated documentation files (the "Software"), to deal
' in the Software without restriction, including without limitation the rights
' to use, copy, modify, merge, publish, distribute, sublicense, And/Or sell
' copies of the Software, And to permit persons to whom the Software Is
' furnished to do so, subject to the following conditions:
'
' The above copyright notice And this permission notice shall be included In all
' copies Or substantial portions of the Software.
'
' THE SOFTWARE Is PROVIDED "AS IS", WITHOUT WARRANTY Of ANY KIND, EXPRESS Or
' IMPLIED, INCLUDING BUT Not LIMITED To THE WARRANTIES Of MERCHANTABILITY,
' FITNESS FOR A PARTICULAR PURPOSE And NONINFRINGEMENT. IN NO EVENT SHALL THE
' AUTHORS Or COPYRIGHT HOLDERS BE LIABLE For ANY CLAIM, DAMAGES Or OTHER
' LIABILITY, WHETHER In AN ACTION Of CONTRACT, TORT Or OTHERWISE, ARISING FROM,
' OUT OF Or IN CONNECTION WITH THE SOFTWARE Or THE USE Or OTHER DEALINGS IN THE
' SOFTWARE.
Imports System.Collections.Generic
Imports Microsoft.Win32

Friend Class Config
    ' Target OS
    Friend Const targetOS As String = "Windows 10 x64"
    ' Current version
    Friend Const addinVersion As String = "1.4.0.33"

    ' Dossier temporaire dedie (sous %TEMP%) pour les .msg intermediaires.
    ' Chaque signalement utilise un nom de fichier ALEATOIRE dans ce dossier
    ' (voir NewSpamTempPath) : evite un chemin previsible et les collisions.
    Private Shared ReadOnly spamTempDir As String = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "BoutonSPAM")
    ' Windows EventLog name
    Friend Const eventLogName = "VSTO 4.0"
    ' Windows EventLod ID
    Friend Const eventID = 1337

    ' Message headers property tag (variante ANSI / PT_STRING8)
    Friend Const PR_TRANSPORT_MESSAGE_HEADERS = "http://schemas.microsoft.com/mapi/proptag/0x007D001E"
    ' Variante UNICODE (PT_UNICODE) du meme en-tete. CORRECTIF DKIM/SPF : sur
    ' Outlook/Exchange moderne (magasin Unicode, mode cache, messages internes),
    ' la variante ANSI ci-dessus (001E) est souvent ABSENTE -> GetProperty leve et
    ' les en-tetes internet reviennent vides, ce qui prive l'analyse SPF/DKIM/DMARC
    ' de toute matiere. On tente donc l'UNICODE en PRIORITE (cf. Ribbon.GetRawHeaders).
    Friend Const PR_TRANSPORT_MESSAGE_HEADERS_UNICODE = "http://schemas.microsoft.com/mapi/proptag/0x007D001F"
    ' Message security property tag
    Friend Const PR_SECURITY_FLAGS = "http://schemas.microsoft.com/mapi/proptag/0x6E010003"
    ' Adresse SMTP reelle de l'expediteur (utile quand Outlook affiche un nom Exchange) : PidTagSenderSmtpAddress
    Friend Const PR_SENDER_SMTP_ADDRESS = "http://schemas.microsoft.com/mapi/proptag/0x5D01001F"
    ' Taille d'une piece jointe (PidTagAttachSize)
    Friend Const PR_ATTACH_SIZE = "http://schemas.microsoft.com/mapi/proptag/0x0E200003"

    ' Registry key that define To and CC addresses
    Friend Const configKey As String = "SOFTWARE\OutlookSpamAddin"
    ' Regex Default
    Private Const regexDefault As String = "(@mondomaine\.fr$|@.*\.mondomaine\.fr$)"

    ' BIT spam email address should be (spam@domain.ch)
    Friend ccSecurityTeamSpamBit As String
    ' Security team mailbox
    Friend toSecurityTeamCERT As String
    ' Flag for filtering internal reported emails
    Friend filterInternalMessages As Boolean = True
    ' Regex to filter interal senders
    Friend regexInteralMessages As String
    ' Report email subject
    Friend Const reportEmailSubject As String = "[SPAM]"
    ' Exception email subject
    Friend Const exceptionEmailSubject As String = "[SPAMx]"

    ' ================================================================
    '  ZONE DE PERSONNALISATION — contenu embarqué dans le rapport
    '  Édite librement les textes ci-dessous, puis recompile.
    ' ================================================================
    ' Horodatage ajouté en tête du rapport (False pour le désactiver)
    Friend Const reportDateEnabled As Boolean = True
    Friend Const reportDateLabel As String = "Signalé le : "
    Friend Const reportDateFormat As String = "yyyy-MM-dd HH:mm:ss"
    ' Annotations de diagnostic ajoutées au corps du rapport
    Friend Const reportMsgEncrypted As String = "Email chiffré"
    Friend Const reportMsgSigned As String = "Email signé"
    Friend Const reportMsgNationalDomain As String = "Domaine national utilisé"
    Friend Const reportMsgLinks As String = "{0} lien(s) dans l'email suspect"
    Friend Const reportMsgAttachments As String = "{0} pièce(s) jointe(s) dans l'email suspect"
    Friend Const reportTagBlocklevel As String = " Blocklevel"
    Friend Const reportTagBlacklisted As String = " **Blacklisted**"
    ' ================================================================
    ' Define the max number of recipients allowed to be forwarded (-1 = no limit)
    Friend maxNumberOfRecipients As Integer = -1
    ' If True try to handle encrypted email
    Friend handleEncryptedMailitem As Boolean = False
    ' If True, send an automatic acknowledgment email to the user who reported (registry: SendAcknowledgment)
    Friend sendAcknowledgment As Boolean = True
    ' Ajoute au rapport un bloc "ANALYSE TECHNIQUE" (auth DKIM/SPF/DMARC, routage, scores, IOC) - registre: IncludeTechnicalReport
    Friend includeTechnicalReport As Boolean = True
    ' Calcule l'empreinte SHA-256 des pieces jointes (ecrit temporairement chaque PJ dans %TEMP%\BoutonSPAM) - registre: HashAttachments
    Friend hashAttachments As Boolean = True
    ' Nombre maximum de liens listes (defanges) dans l'analyse technique
    Friend Const reportMaxLinks As Integer = 25
    ' Taille max d'une PJ pour le calcul d'empreinte (au-dela : ignoree). 25 Mo.
    Friend Const reportMaxHashBytes As Long = 26214400
    ' Nombre max de PJ hachees par message. Le hachage est synchrone sur le
    ' thread UI ; sans plafond, un message forge avec des milliers de petites PJ
    ' figerait Outlook a chaque signalement (deni de service cote client).
    Friend Const reportMaxHashCount As Integer = 50

    ' Report email security flags &H0=nothing, &H1=encrypted, and &H2=signed 
    Friend Const reportSecurityFlagsNothing = &H0
    Friend Const reportSecurityFlagsEncrypted = &H1
    Friend Const reportSecurityFlagsSigned = &H2

    ' User languages https://msdn.microsoft.com/en-us/library/bb213877(v=office.12).aspx
    Friend Const wdEnglishUS As Integer = 1033
    Friend Const wdFrench As Integer = 1036

    ' Email importance subject
    Friend reportEmailImportance As New Dictionary(Of Integer, String)

    ' Language dictionnaries
    Friend group As New Dictionary(Of Integer, String)
    Friend button As New Dictionary(Of Integer, String)
    Friend buttonHoverDescription As New Dictionary(Of Integer, String)
    Friend buttonScreenTip As New Dictionary(Of Integer, String)
    Friend buttonSuperTip As New Dictionary(Of Integer, String)

    Friend reportEmailBody As New Dictionary(Of Integer, String)

    Friend msgBoxItemTypeBody As New Dictionary(Of Integer, String)
    Friend msgBoxItemTypeTitle As New Dictionary(Of Integer, String)
    Friend msgBoxConfirmTitle As New Dictionary(Of Integer, String)
    Friend msgBoxConfirmBodyOne As New Dictionary(Of Integer, String)
    Friend msgBoxConfirmBodyMore As New Dictionary(Of Integer, String)
    Friend msgBoxEmptyTitle As New Dictionary(Of Integer, String)
    Friend msgBoxEmptyBody As New Dictionary(Of Integer, String)
    Friend msgBoxEncryptedTitle As New Dictionary(Of Integer, String)
    Friend msgBoxEncryptedBody As New Dictionary(Of Integer, String)
    Friend msgBoxErrorTitle As New Dictionary(Of Integer, String)
    Friend msgBoxErrorBody As New Dictionary(Of Integer, String)
    Friend msgBoxTooManyRecipients As New Dictionary(Of Integer, String)
    Friend msbBoxNoInternalMsg As New Dictionary(Of Integer, String)

    ' Acknowledgment email sent back to the reporting user
    Friend ackSubject As New Dictionary(Of Integer, String)
    Friend ackBodyOne As New Dictionary(Of Integer, String)
    Friend ackBodyMore As New Dictionary(Of Integer, String)

    ' Message affiche quand aucun destinataire valide n'est configure (fail-close)
    Friend msgBoxNotConfiguredTitle As New Dictionary(Of Integer, String)
    Friend msgBoxNotConfiguredBody As New Dictionary(Of Integer, String)

    ' ---------------------------------------------------------------
    '  Chemin temporaire ALEATOIRE pour l'enregistrement d'un .msg.
    '  Cree le dossier dedie si besoin ; repli sur %TEMP% en cas d'echec.
    ' ---------------------------------------------------------------
    Friend Shared Function NewSpamTempPath() As String
        Dim dir As String = spamTempDir
        Try
            If Not System.IO.Directory.Exists(dir) Then
                System.IO.Directory.CreateDirectory(dir)
            End If
        Catch ex As System.Exception
            dir = System.IO.Path.GetTempPath()
        End Try
        Return System.IO.Path.Combine(dir, System.IO.Path.GetRandomFileName() & ".msg")
    End Function

    ' ---------------------------------------------------------------
    '  Valide qu'une liste d'adresses (separees par ';') contient au
    '  moins une adresse plausible. Sert de garde "fail-close" avant
    '  tout envoi : sans destinataire valide, on N'ENVOIE RIEN.
    '  Les crochets [ ] sont REFUSES : les adresses d'exemple du projet
    '  sont volontairement "defangees" (abuse@mondomaine[.]fr, notation
    '  forensic) -> un poste non personnalise est bloque PROPREMENT ici
    '  (message "extension non configuree" + journal) au lieu de tenter
    '  un envoi vers une adresse invalide.
    ' ---------------------------------------------------------------
    Friend Shared Function IsValidRecipientList(ByVal addresses As String) As Boolean
        If String.IsNullOrWhiteSpace(addresses) Then Return False
        For Each addr As String In addresses.Split(";"c)
            Dim a As String = addr.Trim()
            Dim at As Integer = a.IndexOf("@"c)
            If a.Length >= 3 AndAlso at > 0 AndAlso at < a.Length - 1 AndAlso Not a.Contains(" ") AndAlso
               Not a.Contains("[") AndAlso Not a.Contains("]") AndAlso a.IndexOf("."c, at) > at Then
                Return True
            End If
        Next
        Return False
    End Function

    ' ================================================================
    '  ANALYSE TECHNIQUE DU MESSAGE (aide aux analystes)
    '  Extraction, cote poste, des signaux utiles a partir des en-tetes
    '  MIME. Les verdicts DKIM / SPF / DMARC sont ceux calcules par la
    '  PASSERELLE de messagerie (relus dans Authentication-Results) : ils
    '  ne sont PAS recalcules ici (cela demanderait le DNS et la
    '  canonicalisation d'origine). Bloc desactivable par registre
    '  (IncludeTechnicalReport). Textes editables librement.
    ' ================================================================

    ' Deplie les en-tetes replies (continuation = ligne commencant par espace/tab).
    Friend Shared Function UnfoldHeaders(ByVal raw As String) As String
        If String.IsNullOrEmpty(raw) Then Return ""
        Try
            Return System.Text.RegularExpressions.Regex.Replace(raw, "\r?\n[ \t]+", " ", System.Text.RegularExpressions.RegexOptions.None, System.TimeSpan.FromMilliseconds(500))
        Catch
            Return raw
        End Try
    End Function

    ' 1re valeur d'un en-tete (sur en-tetes deja deplies), sinon "".
    Friend Shared Function HeaderValue(ByVal unfolded As String, ByVal name As String) As String
        Try
            Dim m = System.Text.RegularExpressions.Regex.Match(unfolded, "^" & System.Text.RegularExpressions.Regex.Escape(name) & "\s*:\s*(.*)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase Or System.Text.RegularExpressions.RegexOptions.Multiline, System.TimeSpan.FromMilliseconds(500))
            If m.Success Then Return m.Groups(1).Value.Trim()
        Catch
        End Try
        Return ""
    End Function

    ' Toutes les valeurs d'un en-tete, de haut en bas.
    Friend Shared Function HeaderValues(ByVal unfolded As String, ByVal name As String) As List(Of String)
        Dim res As New List(Of String)
        Try
            For Each m As System.Text.RegularExpressions.Match In System.Text.RegularExpressions.Regex.Matches(unfolded, "^" & System.Text.RegularExpressions.Regex.Escape(name) & "\s*:\s*(.*)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase Or System.Text.RegularExpressions.RegexOptions.Multiline, System.TimeSpan.FromMilliseconds(500))
                res.Add(m.Groups(1).Value.Trim())
            Next
        Catch
        End Try
        Return res
    End Function

    ' Sous-motif (groupe 1), delai borne, insensible a la casse.
    Friend Shared Function Rx(ByVal input As String, ByVal pattern As String) As String
        If String.IsNullOrEmpty(input) Then Return ""
        Try
            Dim m = System.Text.RegularExpressions.Regex.Match(input, pattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500))
            If m.Success Then Return m.Groups(1).Value.Trim()
        Catch
        End Try
        Return ""
    End Function

    ' Neutralise une URL / IP pour l'analyse ("http"->"hxxp", "."->"[.]").
    Friend Shared Function Defang(ByVal s As String) As String
        If String.IsNullOrEmpty(s) Then Return ""
        Dim r As String = s.Replace("https", "hxxps").Replace("http", "hxxp")
        r = r.Replace(".", "[.]")
        Return r
    End Function

    ' Domaine d'une adresse ("a@b.c" -> "b.c").
    Friend Shared Function DomainOf(ByVal addr As String) As String
        If String.IsNullOrEmpty(addr) Then Return ""
        Dim at As Integer = addr.LastIndexOf("@"c)
        If at >= 0 AndAlso at < addr.Length - 1 Then
            Return addr.Substring(at + 1).TrimEnd(">"c, ")"c, " "c, ";"c, ","c)
        End If
        Return ""
    End Function

    Private Shared Function NZ(ByVal s As String) As String
        If String.IsNullOrEmpty(s) Then Return "(absent)"
        Return s
    End Function

    Private Shared Function TruncStr(ByVal s As String, ByVal n As Integer) As String
        If String.IsNullOrEmpty(s) Then Return ""
        If s.Length <= n Then Return s
        Return s.Substring(0, n) & "..."
    End Function

    ' SECURITE : neutralise une valeur d'en-tete NON FIABLE (controlee par l'expediteur)
    ' avant de l'inliner dans le corps du rapport. Supprime les caracteres de
    ' controle (CR/LF/TAB...) qui permettraient a un attaquant de forger un faux
    ' bandeau (ex. injecter des lignes imitant " SPF : pass " pour tromper un
    ' analyste presse) et borne la longueur. A utiliser pour TOUTE valeur brute
    ' issue du message signale que l'on recopie dans le rapport.
    Friend Shared Function SafeInline(ByVal s As String, ByVal n As Integer) As String
        If String.IsNullOrEmpty(s) Then Return ""
        Dim sb As New System.Text.StringBuilder(s.Length)
        For Each c As Char In s
            If System.Char.IsControl(c) Then
                sb.Append(" "c)
            Else
                sb.Append(c)
            End If
        Next
        Dim r As String = sb.ToString().Trim()
        If n > 0 AndAlso r.Length > n Then r = r.Substring(0, n) & "..."
        Return r
    End Function

    Private Shared Function DescribeCAT(ByVal c As String) As String
        Select Case c.ToUpperInvariant()
            Case "PHSH" : Return " (hameconnage)"
            Case "HPHISH", "HPHSH" : Return " (hameconnage haute confiance)"
            Case "SPM" : Return " (spam)"
            Case "HSPM" : Return " (spam haute confiance)"
            Case "MALW" : Return " (logiciel malveillant)"
            Case "SPOOF" : Return " (usurpation)"
            Case "BULK" : Return " (courrier de masse)"
            Case "GIMP" : Return " (graymail)"
            Case Else : Return ""
        End Select
    End Function

    Private Shared Function DescribeSFV(ByVal c As String) As String
        Select Case c.ToUpperInvariant()
            Case "SPM" : Return " (marque SPAM par le filtre)"
            Case "NSPM" : Return " (marque non-spam)"
            Case "BLK" : Return " (bloque - liste noire)"
            Case "SKS" : Return " (marque spam par une regle)"
            Case "SKN" : Return " (marque legitime par une regle)"
            Case "SKB" : Return " (bloque par une regle)"
            Case Else : Return ""
        End Select
    End Function

    Private Shared Function DescribeSFTY(ByVal c As String) As String
        If c.StartsWith("9.19") Then Return " (hameconnage detecte)"
        If c.StartsWith("9.11") Then Return " (usurpation intra-organisation)"
        If c.StartsWith("9.20") Then Return " (usurpation de domaine)"
        If c.StartsWith("9.21") Then Return " (usurpation - domaine externe)"
        If c.StartsWith("9.25") Then Return " (premiere prise de contact)"
        Return ""
    End Function

    ' Construit le bloc d'analyse a partir des SEULS en-tetes (sans dependance Outlook).
    Friend Shared Function BuildHeaderAnalysis(ByVal rawHeaders As String) As String
        Dim sb As New System.Text.StringBuilder()
        Try
            If String.IsNullOrEmpty(rawHeaders) Then Return "(en-tetes indisponibles - message non SMTP ou droits insuffisants)"
            If rawHeaders.Length > 204800 Then rawHeaders = rawHeaders.Substring(0, 204800)
            Dim h As String = UnfoldHeaders(rawHeaders)

            Dim authAll As String = String.Join("  |  ", HeaderValues(h, "Authentication-Results").ToArray())
            Dim spf As String = Rx(authAll, "spf=([A-Za-z]+)")
            If spf = "" Then spf = Rx(HeaderValue(h, "Received-SPF"), "^\s*([A-Za-z]+)")
            Dim dkim As String = Rx(authAll, "dkim=([A-Za-z]+)")
            Dim dmarc As String = Rx(authAll, "dmarc=([A-Za-z]+)")
            Dim dmarcAction As String = Rx(authAll, "action=([A-Za-z]+)")
            Dim compauth As String = Rx(authAll, "compauth=([A-Za-z]+)")
            Dim compReason As String = Rx(authAll, "reason=(\d+)")
            Dim dkimSig As String = HeaderValue(h, "DKIM-Signature")
            Dim dkimD As String = Rx(dkimSig, "[;\s]d=([^;\s]+)")
            Dim dkimS As String = Rx(dkimSig, "[;\s]s=([^;\s]+)")
            Dim arc As String = Rx(String.Join(" ", HeaderValues(h, "ARC-Authentication-Results").ToArray()), "arc=([A-Za-z]+)")

            Dim fromH As String = HeaderValue(h, "From")
            Dim replyTo As String = HeaderValue(h, "Reply-To")
            Dim returnPath As String = HeaderValue(h, "Return-Path")
            Dim fromAddr As String = Rx(fromH, "<([^>]+)>")
            If fromAddr = "" Then fromAddr = fromH
            Dim fromDom As String = DomainOf(fromAddr)
            Dim rpDom As String = DomainOf(returnPath)
            Dim replyDom As String = DomainOf(Rx(replyTo, "<([^>]+)>"))
            If replyDom = "" Then replyDom = DomainOf(replyTo)

            sb.AppendLine("===== ANALYSE TECHNIQUE (automatique - aide analyste) =====")
            sb.AppendLine("")
            sb.AppendLine("[ Authentification ]  verdict de la PASSERELLE (non recalcule sur le poste)")
            sb.AppendLine("  SPF   : " & NZ(spf))
            sb.AppendLine("  DKIM  : " & NZ(dkim) & If(dkimD <> "", "   signe d=" & dkimD & If(dkimS <> "", " s=" & dkimS, ""), ""))
            sb.AppendLine("  DMARC : " & NZ(dmarc) & If(dmarcAction <> "", "   action=" & dmarcAction, ""))
            If arc <> "" Then sb.AppendLine("  ARC   : " & arc & "   (message transfere / liste)")
            If compauth <> "" Then sb.AppendLine("  CompAuth (Microsoft) : " & compauth & If(compReason <> "", "   reason=" & compReason, ""))

            sb.AppendLine("")
            sb.AppendLine("[ Expediteur & indices d'usurpation ]")
            sb.AppendLine("  From (affiche)   : " & NZ(TruncStr(fromH, 200)))
            If returnPath <> "" Then
                Dim rpFlag As String = ""
                If rpDom <> "" AndAlso fromDom <> "" AndAlso Not fromDom.EndsWith(rpDom, System.StringComparison.OrdinalIgnoreCase) AndAlso Not rpDom.EndsWith(fromDom, System.StringComparison.OrdinalIgnoreCase) Then rpFlag = "   <-- NON ALIGNE avec From (" & fromDom & ")"
                sb.AppendLine("  Return-Path      : " & TruncStr(returnPath, 200) & rpFlag)
            End If
            If replyTo <> "" Then
                Dim rtFlag As String = ""
                If replyDom <> "" AndAlso fromDom <> "" AndAlso Not replyDom.Equals(fromDom, System.StringComparison.OrdinalIgnoreCase) Then rtFlag = "   <-- DIFFERENT du From"
                sb.AppendLine("  Reply-To         : " & TruncStr(replyTo, 200) & rtFlag)
            End If
            If dkimD <> "" Then
                Dim dkFlag As String = "   (coherent)"
                If fromDom <> "" AndAlso Not dkimD.EndsWith(fromDom, System.StringComparison.OrdinalIgnoreCase) AndAlso Not fromDom.EndsWith(dkimD, System.StringComparison.OrdinalIgnoreCase) Then dkFlag = "   <-- ne correspond pas a From (" & fromDom & ")"
                sb.AppendLine("  Alignement DKIM  : d=" & dkimD & dkFlag)
            End If

            Dim recvs As List(Of String) = HeaderValues(h, "Received")
            Dim origin As String = ""
            If recvs.Count > 0 Then origin = recvs(recvs.Count - 1)
            Dim originIp As String = Rx(origin, "[\[\(](\d{1,3}(?:\.\d{1,3}){3})[\]\)]")
            If originIp = "" Then originIp = Rx(HeaderValue(h, "X-Originating-IP"), "(\d{1,3}(?:\.\d{1,3}){3})")
            If originIp = "" Then originIp = Rx(HeaderValue(h, "X-Sender-IP"), "(\d{1,3}(?:\.\d{1,3}){3})")
            Dim helo As String = Rx(origin, "helo=([^\s\)]+)")
            sb.AppendLine("")
            sb.AppendLine("[ Origine & routage ]")
            sb.AppendLine("  IP d'origine     : " & Defang(NZ(originIp)))
            If helo <> "" Then sb.AppendLine("  HELO/EHLO        : " & helo)
            sb.AppendLine("  Sauts (Received) : " & recvs.Count.ToString())
            If origin <> "" Then sb.AppendLine("  1er relais       : " & TruncStr(origin, 250))

            Dim ff As String = HeaderValue(h, "X-Forefront-Antispam-Report")
            Dim scl As String = HeaderValue(h, "X-MS-Exchange-Organization-SCL")
            If scl = "" Then scl = Rx(ff, "SCL:(-?\d+)")
            Dim bcl As String = Rx(HeaderValue(h, "X-Microsoft-Antispam"), "BCL:(\d+)")
            Dim sfv As String = Rx(ff, "SFV:([A-Za-z]+)")
            Dim cat As String = Rx(ff, "CAT:([A-Za-z]+)")
            Dim sfty As String = Rx(ff, "SFTY:([0-9.]+)")
            Dim spamScore As String = Rx(HeaderValue(h, "X-Spam-Status"), "score=([\d\.\-]+)")
            sb.AppendLine("")
            sb.AppendLine("[ Scores anti-spam / anti-hameconnage ]")
            Dim anyScore As Boolean = False
            If scl <> "" Then
                sb.AppendLine("  SCL (0..9, +eleve = +suspect) : " & scl)
                anyScore = True
            End If
            If bcl <> "" Then
                sb.AppendLine("  BCL (0..9, courrier de masse) : " & bcl)
                anyScore = True
            End If
            If sfv <> "" Then
                sb.AppendLine("  Verdict Forefront (SFV)       : " & sfv & DescribeSFV(sfv))
                anyScore = True
            End If
            If cat <> "" Then
                sb.AppendLine("  Categorie (CAT)               : " & cat & DescribeCAT(cat))
                anyScore = True
            End If
            If sfty <> "" Then
                sb.AppendLine("  Alerte securite (SFTY)        : " & sfty & DescribeSFTY(sfty))
                anyScore = True
            End If
            If spamScore <> "" Then
                sb.AppendLine("  X-Spam score                  : " & spamScore)
                anyScore = True
            End If
            If Not anyScore Then sb.AppendLine("  (aucun en-tete de score reconnu)")

            Dim msgId As String = HeaderValue(h, "Message-ID")
            ' Micro-correctif : Rx extrait DEJA le domaine du Message-ID ;
            ' DomainOf (qui cherche un @) renvoyait donc toujours "" et le drapeau
            ' "domaine != From" ne s'affichait JAMAIS. Decouvert lors du portage web
            ' (webaddin/src/analyse.js, meme logique) ; actif a la prochaine recompilation.
            Dim midDom As String = Rx(msgId, "@([^>\s]+)")
            Dim dateH As String = HeaderValue(h, "Date")
            Dim xmailer As String = HeaderValue(h, "X-Mailer")
            If xmailer = "" Then xmailer = HeaderValue(h, "User-Agent")
            Dim clang As String = HeaderValue(h, "Content-Language")
            sb.AppendLine("")
            sb.AppendLine("[ Message ]")
            If msgId <> "" Then
                Dim midFlag As String = ""
                If midDom <> "" AndAlso fromDom <> "" AndAlso Not midDom.EndsWith(fromDom, System.StringComparison.OrdinalIgnoreCase) Then midFlag = "   <-- domaine " & midDom & " != From"
                sb.AppendLine("  Message-ID       : " & TruncStr(msgId, 200) & midFlag)
            End If
            If dateH <> "" Then sb.AppendLine("  Date (en-tete)   : " & dateH)
            If xmailer <> "" Then sb.AppendLine("  Client emetteur  : " & TruncStr(xmailer, 160))
            If clang <> "" Then sb.AppendLine("  Langue declaree  : " & clang)
        Catch ex As System.Exception
            sb.AppendLine("(analyse des en-tetes interrompue : " & ex.Message & ")")
        End Try
        Return sb.ToString()
    End Function

    ' Lecture DEFENSIVE du registre. Une valeur mal typee dans HKLM
    ' (chaine non numerique la ou un entier/booleen est attendu, type de
    ' donnee inattendu, etc.) ne doit JAMAIS faire echouer tout le constructeur
    ' de configuration (ce qui rendrait le bouton inutilisable). En cas de
    ' probleme de conversion, on retombe silencieusement sur la valeur par
    ' defaut sure (fail-safe) et le bouton reste operationnel.
    Private Shared Function RegStr(ByVal k As RegistryKey, ByVal name As String, ByVal fallback As String) As String
        Try
            Dim v As Object = k.GetValue(name, fallback)
            If v Is Nothing Then Return fallback
            Return CStr(v)
        Catch ex As System.Exception
            Return fallback
        End Try
    End Function

    Private Shared Function RegBool(ByVal k As RegistryKey, ByVal name As String, ByVal fallback As Boolean) As Boolean
        Try
            Dim v As Object = k.GetValue(name, Nothing)
            If v Is Nothing Then Return fallback
            ' Accepte indifferemment un DWORD (0/1) ou une chaine ("0"/"1"/"true"/"false").
            If TypeOf v Is Integer Then Return (CInt(v) <> 0)
            Dim s As String = CStr(v).Trim()
            If s = "" Then Return fallback
            Dim n As Integer
            If Integer.TryParse(s, n) Then Return (n <> 0)
            Dim b As Boolean
            If Boolean.TryParse(s, b) Then Return b
            Return fallback
        Catch ex As System.Exception
            Return fallback
        End Try
    End Function

    Private Shared Function RegInt(ByVal k As RegistryKey, ByVal name As String, ByVal fallback As Integer) As Integer
        Try
            Dim v As Object = k.GetValue(name, Nothing)
            If v Is Nothing Then Return fallback
            If TypeOf v Is Integer Then Return CInt(v)
            Dim s As String = CStr(v).Trim()
            Dim n As Integer
            If Integer.TryParse(s, n) Then Return n
            Return fallback
        Catch ex As System.Exception
            Return fallback
        End Try
    End Function

    Public Sub New()
        Dim regkey As RegistryKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(configKey)

        If regkey IsNot Nothing Then
            ' Toutes les conversions passent par les lecteurs defensifs
            ' RegStr/RegBool/RegInt (aucune exception ne peut casser le chargement).
            toSecurityTeamCERT = RegStr(regkey, "To", "")
            ' Defaut VIDE (fail-close) : ne JAMAIS retomber sur un domaine reel.
            ccSecurityTeamSpamBit = RegStr(regkey, "Cc", "")
            filterInternalMessages = RegBool(regkey, "FilterInternalMessages", True)
            regexInteralMessages = RegStr(regkey, "Regex", regexDefault)
            maxNumberOfRecipients = RegInt(regkey, "MaxNumberOfRecipients", -1)
            handleEncryptedMailitem = RegBool(regkey, "HandleEncryptedMailItem", False)
            sendAcknowledgment = RegBool(regkey, "SendAcknowledgment", True)
            includeTechnicalReport = RegBool(regkey, "IncludeTechnicalReport", True)
            hashAttachments = RegBool(regkey, "HashAttachments", True)
        Else
            toSecurityTeamCERT = ""
            ccSecurityTeamSpamBit = ""
            filterInternalMessages = True
            regexInteralMessages = regexDefault
            maxNumberOfRecipients = -1
            handleEncryptedMailitem = False
            sendAcknowledgment = True
            includeTechnicalReport = True
            hashAttachments = True
        End If

        msgBoxConfirmBodyOneEN = "Thank you for your contribution to Cyber Security! The selected message will be forwarded to " & ccSecurityTeamSpamBit & " and irrevocably removed from your inbox. Our specialists will take care of it immediately. In case of particularly harmful or dangerous content, you will be contacted personally. Would you like to continue?"
        msgBoxConfirmBodyMoreEN = "Thank you for your contribution to Cyber Security! The selected {0} message will be forwarded to " & ccSecurityTeamSpamBit & " and irrevocably removed from your inbox. Our specialists will take care of it immediately. In case of particularly harmful or dangerous content, you will be contacted personally. Would you like to continue?"
        msgBoxErrorBodyEN = "An error occurred! Please contact " & toSecurityTeamCERT & " to resolve the issue. The selected message was not forwarded nor deleted from your inbox."


        msgBoxConfirmBodyOneFR = "Merci pour votre contribution à la cybersécurité! Le message sélectionné sera transmis à " & ccSecurityTeamSpamBit & " et sera irrévocablement supprimé de votre boîte de réception. Nos spécialistes s'en occupent immédiatement. En cas de contenu particulièrement nuisible ou dangereux, vous serez contacté personnellement. Voulez-vous continuer ?"
        msgBoxConfirmBodyMoreFR = "Merci pour votre contribution à la cybersécurité! Le {0} message sélectionné sera transmis à " & ccSecurityTeamSpamBit & " et sera irrévocablement supprimé de votre boîte de réception. Nos spécialistes s'en occupent immédiatement. En cas de contenu particulièrement nuisible ou dangereux, vous serez contacté personnellement. Voulez-vous continuer ?"
        msgBoxErrorBodyFR = "Une erreur est survenue! Veuillez contacter " & toSecurityTeamCERT & " pour résoudre le problème. Le message sélectionné n'a pas été transmis ni supprimé de votre boîte de réception."


        If String.IsNullOrEmpty(toSecurityTeamCERT) Then
            msgBoxErrorBodyEN = "An error occured. The selected message was not forwarded nor deleted from your inbox."
            msgBoxErrorBodyFR = "Une erreur est survenue. Le message sélectionné n'a pas été transmis ni supprimé de votre boîte de réception."
        End If

        If String.IsNullOrEmpty(ccSecurityTeamSpamBit) Then
            msgBoxConfirmBodyOneEN = "The selected message will be forwarded to " & toSecurityTeamCERT & " and removed from your inbox. Would you like to continue?"
            msgBoxConfirmBodyMoreEN = "The {0} selected messages will be forwarded to " & toSecurityTeamCERT & " and removed from your inbox. Would you like to continue?"


            msgBoxConfirmBodyOneFR = "Le message sélectionné sera transmis à " & toSecurityTeamCERT & " et supprimé de votre boîte de réception. Voulez-vous continuer ?"
            msgBoxConfirmBodyMoreFR = "Les {0} messages sélectionnés seront transmis à " & toSecurityTeamCERT & " et supprimés de votre boîte de réception. Voulez-vous continuer ?"

        End If

        With reportEmailImportance
            .Add(&H0, "L")
            .Add(&H1, "N")
            .Add(&H2, "H")
        End With
        With group
            .Add(wdEnglishUS, groupEN)
            .Add(wdFrench, groupFR)
        End With
        With button
            .Add(wdEnglishUS, buttonEN)
            .Add(wdFrench, buttonFR)
        End With
        With buttonHoverDescription
            .Add(wdEnglishUS, buttonHoverDescriptionEN)
            .Add(wdFrench, buttonHoverDescriptionFR)
        End With
        With buttonScreenTip
            .Add(wdEnglishUS, buttonScreenTipEN)
            .Add(wdFrench, buttonScreenTipFR)
        End With
        With buttonSuperTip
            .Add(wdEnglishUS, buttonSuperTipEN)
            .Add(wdFrench, buttonSuperTipFR)
        End With

        With reportEmailBody
            .Add(wdEnglishUS, reportEmailBodyEN)
            .Add(wdFrench, reportEmailBodyFR)
        End With

        With msgBoxItemTypeTitle
            .Add(wdEnglishUS, msgBoxItemTypeTitleEN)
            .Add(wdFrench, msgBoxItemTypeTitleFR)
        End With
        With msgBoxItemTypeBody
            .Add(wdEnglishUS, msgBoxItemTypeBodyEN)
            .Add(wdFrench, msgBoxItemTypeBodyFR)
        End With
        With msgBoxConfirmTitle
            .Add(wdEnglishUS, msgBoxConfirmTitleEN)
            .Add(wdFrench, msgBoxConfirmTitleFR)
        End With
        With msgBoxConfirmBodyOne
            .Add(wdEnglishUS, msgBoxConfirmBodyOneEN)
            .Add(wdFrench, msgBoxConfirmBodyOneFR)
        End With
        With msgBoxConfirmBodyMore
            .Add(wdEnglishUS, msgBoxConfirmBodyMoreEN)
            .Add(wdFrench, msgBoxConfirmBodyMoreFR)
        End With
        With msgBoxEmptyTitle
            .Add(wdEnglishUS, msgBoxEmptyTitleEN)
            .Add(wdFrench, msgBoxEmptyTitleFR)
        End With
        With msgBoxEmptyBody
            .Add(wdEnglishUS, msgBoxEmptyBodyEN)
            .Add(wdFrench, msgBoxEmptyBodyFR)
        End With
        With msgBoxEncryptedTitle
            .Add(wdEnglishUS, msgBoxEncryptedTitleEN)
            .Add(wdFrench, msgBoxEncryptedTitleFR)
        End With
        With msgBoxEncryptedBody
            .Add(wdEnglishUS, msgBoxEncryptedBodyEN)
            .Add(wdFrench, msgBoxEncryptedBodyFR)
        End With
        With msgBoxErrorTitle
            .Add(wdEnglishUS, msgBoxErrorTitleEN)
            .Add(wdFrench, msgBoxErrorTitleFR)
        End With
        With msgBoxErrorBody
            .Add(wdEnglishUS, msgBoxErrorBodyEN)
            .Add(wdFrench, msgBoxErrorBodyFR)
        End With
        With msgBoxTooManyRecipients
            .Add(wdEnglishUS, msgBoxTooManyRecipientsEN)
            .Add(wdFrench, msgBoxTooManyRecipientsFR)
        End With
        With msbBoxNoInternalMsg
            .Add(wdEnglishUS, msbBoxNoInternalMsgEN)
            .Add(wdFrench, msbBoxNoInternalMsgFR)
        End With
        With ackSubject
            .Add(wdEnglishUS, ackSubjectEN)
            .Add(wdFrench, ackSubjectFR)
        End With
        With ackBodyOne
            .Add(wdEnglishUS, ackBodyOneEN)
            .Add(wdFrench, ackBodyOneFR)
        End With
        With ackBodyMore
            .Add(wdEnglishUS, ackBodyMoreEN)
            .Add(wdFrench, ackBodyMoreFR)
        End With
        With msgBoxNotConfiguredTitle
            .Add(wdEnglishUS, msgBoxNotConfiguredTitleEN)
            .Add(wdFrench, msgBoxNotConfiguredTitleFR)
        End With
        With msgBoxNotConfiguredBody
            .Add(wdEnglishUS, msgBoxNotConfiguredBodyEN)
            .Add(wdFrench, msgBoxNotConfiguredBodyFR)
        End With

        ' SECURITE : trace la destination effective au demarrage (auditabilite d'une
        ' eventuelle redirection). N'ecrit rien de sensible d'autre.
        Try
            Dim src As New System.Diagnostics.EventLog
            src.Source = eventLogName
            src.WriteEntry("BoutonSPAM " & addinVersion & " charge. Destinataires configures -> To='" & toSecurityTeamCERT & "' Cc='" & ccSecurityTeamSpamBit & "'.", System.Diagnostics.EventLogEntryType.Information, eventID)
        Catch ex As System.Exception
            ' journalisation best-effort : ne jamais bloquer le chargement
        End Try
    End Sub

    ' ================================================================
    '  ZONE DE PERSONNALISATION — TEXTES VUS PAR L'UTILISATEUR
    '  Tous les textes ci-dessous (2 langues : FR et EN ; l'anglais sert de
    '  repli pour toute autre langue d'Outlook) sont modifiables librement,
    '  puis RECOMPILER (Visual Studio).
    '
    '  Les principaux champs FR/EN sont aussi pilotables SANS toucher
    '  ce fichier : branding.conf (section "Textes utilisateur") puis
    '  ./scripts/02_customize.sh. Correspondance :
    '    group*                  = nom du GROUPE dans le ruban Outlook
    '    button* / buttonScreenTip* = LIBELLE DU BOUTON / titre d'info-bulle
    '    buttonHoverDescription* = description courte au survol
    '    buttonSuperTip*         = description longue (grande info-bulle)
    '    msgBoxConfirmTitle*     = titre de la boite de confirmation
    '    msgBoxConfirmBodyOne/More* = corps de la confirmation (1 ou N mails)
    '                              (assembles avec les adresses, voir Sub New)
    '    msgBoxItemType*/Empty*/Encrypted*/Error*  = messages d'information/erreur
    '    msgBoxTooManyRecipients* / msbBoxNoInternalMsg* = garde-fous
    '    reportEmailBody*        = phrase d'introduction du rapport envoye
    '    ackSubject*/ackBodyOne*/ackBodyMore* = ACCUSE DE RECEPTION automatique
    '                              envoye a l'utilisateur qui signale (interrupteur
    '                              registre SendAcknowledgment, 1 = actif)
    '  Prefixes d'objet du rapport : reportEmailSubject / exceptionEmailSubject
    '  (plus haut dans ce fichier), pilotables via REPORT_SUBJECT_PREFIX*.
    '  Les {0} sont remplaces a l'execution (nombre, expediteur...) : les garder.
    '  NE PAS utiliser de guillemets doubles (") DANS les textes.
    ' ================================================================

    ' Ribbon locales EN (default)
    Private Const groupEN As String = "Report Security Issue"
    Private Const buttonEN As String = "Report Spam"
    Private Const buttonHoverDescriptionEN As String = "Report suspicious emails to the information security team."
    Private Const buttonScreenTipEN As String = "Report Spam"
    Private Const buttonSuperTipEN As String = "Use this button to report suspicious emails to the information security team."
    Private Const msgBoxConfirmTitleEN As String = "Report Spam to your security team"
    Private ReadOnly msgBoxConfirmBodyOneEN As String = "The selected message will be forwarded to " & ccSecurityTeamSpamBit & " and removed from your inbox. Would you like to continue?"
    Private ReadOnly msgBoxConfirmBodyMoreEN As String = "The {0} selected messages will be forwarded to " & ccSecurityTeamSpamBit & " and removed from your inbox. Would you like to continue?"
    Private Const msgBoxItemTypeTitleEN As String = "Not a email item"
    Private Const msgBoxItemTypeBodyEN As String = "Only emails can be forwarded to the security team."
    Private Const msgBoxEmptyTitleEN As String = "No message selected"
    Private Const msgBoxEmptyBodyEN As String = "Please select a message to continue."
    Private Const msgBoxEncryptedTitleEN As String = "Warning"
    Private Const msgBoxEncryptedBodyEN As String = "The selected email Is encrypted, therefore it cannot be forwarded due to privacy and confidentiality reasons."
    Private Const msgBoxErrorTitleEN As String = "Error"
    Private ReadOnly msgBoxErrorBodyEN As String = "An error occured, please contact " & toSecurityTeamCERT & " to resolve the issue. The selected Spam was Not forwarded nor deleted from your inbox."
    Private Const msgBoxTooManyRecipientsEN As String = "The selected email has too many recipients ({0}) and cannot be forwarded to your security team."
    Private Const msbBoxNoInternalMsgEN As String = "This email seems to come from within your organisation (sender: {0}), do you really want to report it as a Spam?"
    Private Const reportEmailBodyEN As String = "This is a user-submitted report of a suspicious email. Please review the attached message." & vbCrLf
    Private Const ackSubjectEN As String = "Your report has been received"
    ' Acknowledgment body in HTML, on ONE line so 02_customize.sh (UI_ACK_BODY_*) can override it.
    ' Inline formatting only: <br> = line break, <i>...</i> = italics. The font/size wrapper <div> is
    ' added once in Ribbon.vb (do NOT repeat it here). No double quotes " inside the text.
    Private Const ackBodyOneEN As String = "Thank you for your vigilance!<br><br>Your report has been sent to the security team and will be analyzed shortly. You will be contacted if any action is needed on your side.<br><br><i>This is an automatic acknowledgment &mdash; no reply is required.</i>"
    Private Const ackBodyMoreEN As String = "Thank you for your vigilance!<br><br>Your {0} reports have been sent to the security team and will be analyzed shortly. You will be contacted if any action is needed on your side.<br><br><i>This is an automatic acknowledgment &mdash; no reply is required.</i>"
    Private Const msgBoxNotConfiguredTitleEN As String = "Add-in not configured"
    Private Const msgBoxNotConfiguredBodyEN As String = "The reporting add-in has not been configured on this computer (no destination address). Please contact your IT support. No message was sent."


    ' Ribbon locales FR
    Private Const groupFR As String = "Signaler un incident de sécurité"
    Private Const buttonFR As String = "Rapporter un Spam"
    Private Const buttonHoverDescriptionFR As String = "Signaler des emails suspects à votre équipe de sécurité."
    Private Const buttonScreenTipFR As String = "Rapporter un Spam"
    Private Const buttonSuperTipFR As String = "Utilisez ce bouton pour signaler un email suspect à votre équipe de sécurité."
    Private Const msgBoxConfirmTitleFR As String = "Rapporter un Spam à votre équipe de sécurité"
    Private ReadOnly msgBoxConfirmBodyOneFR As String = "Le message sélectionné sera transmis à " & ccSecurityTeamSpamBit & " et supprimé de votre boîte de réception. Voulez-vous continuer ?"
    Private ReadOnly msgBoxConfirmBodyMoreFR As String = "Les {0} messages sélectionnés seront transmis à " & ccSecurityTeamSpamBit & " et supprimés de votre boîte de réception. Voulez-vous continuer ?"
    Private Const msgBoxItemTypeTitleFR As String = "Sélection incorrecte"
    Private Const msgBoxItemTypeBodyFR As String = "Seul un email peut être transmis à votre équipe de sécurité."
    Private Const msgBoxEmptyTitleFR As String = "Aucun message sélectionné"
    Private Const msgBoxEmptyBodyFR As String = "Veuillez choisir un email pour continuer."
    Private Const msgBoxEncryptedTitleFR As String = "Attention"
    Private Const msgBoxEncryptedBodyFR As String = "Le message sélectionné est chiffré, c'est pourquoi il ne peut être transmis pour des raisons de protection des données et de confidentialité."
    Private Const msgBoxErrorTitleFR As String = "Erreur"
    Private ReadOnly msgBoxErrorBodyFR As String = "Une erreur est survenue, veuillez contacter " & toSecurityTeamCERT & " pour résoudre le problème. Le message sélectionné n'a pas été transmis ni supprimé de votre boîte de réception."
    Private Const msgBoxTooManyRecipientsFR As String = "Le message sélectionné comporte trop de destinataires ({0}) et ne peut être transféré à votre équipe de sécurité."
    Private Const msbBoxNoInternalMsgFR As String = "Ce message semble provenir de votre organisation (expéditeur: {0}), voulez-vous vraiment le reporter en tant que Spam ?"
    Private Const reportEmailBodyFR As String = "Ceci est un signalement d'email suspect soumis par un utilisateur. Merci d'examiner le message ci-joint." & vbCrLf
    Private Const ackSubjectFR As String = "Votre signalement a bien été transmis"
    ' Accuse de reception en HTML, sur UNE ligne pour que 02_customize.sh (UI_ACK_BODY_*) puisse l'injecter.
    ' Mise en forme en ligne uniquement : <br> = saut de ligne, <i>...</i> = italique. Le <div> (police/taille)
    ' est ajoute une seule fois dans Ribbon.vb (ne PAS le repeter ici). Pas de guillemets doubles " dans le texte.
    Private Const ackBodyOneFR As String = "Merci pour votre vigilance !<br><br>Votre signalement a été transmis à MonOrganisationSSI et sera analysé rapidement. Vous serez recontacté si une action de votre part est nécessaire.<br><br><i>Ceci est un accusé de réception automatique &mdash; aucune réponse n'est attendue.</i>"
    Private Const ackBodyMoreFR As String = "Merci pour votre vigilance !<br><br>Vos {0} signalements ont été transmis à MonOrganisationSSI et seront analysés rapidement. Vous serez recontacté si une action de votre part est nécessaire.<br><br><i>Ceci est un accusé de réception automatique &mdash; aucune réponse n'est attendue.</i>"
    Private Const msgBoxNotConfiguredTitleFR As String = "Extension non configurée"
    Private Const msgBoxNotConfiguredBodyFR As String = "L'extension de signalement n'est pas configurée sur ce poste (aucune adresse de destination). Veuillez contacter votre support informatique. Aucun message n'a été envoyé."

End Class