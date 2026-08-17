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
<System.Runtime.InteropServices.ComVisible(True)>
Public Class Ribbon
    Implements Microsoft.Office.Core.IRibbonExtensibility

    Private ribbon As Microsoft.Office.Core.IRibbonUI
    Private config As New Config
    Private appLog As New System.Diagnostics.EventLog
    Private keyLanguage As Integer
    Private msgBoxErrorBody As String
    Private msgBoxErrorTitle As String

    Public Sub New()
    End Sub

    Public Function GetCustomUI(ByVal ribbonID As String) As String Implements Microsoft.Office.Core.IRibbonExtensibility.GetCustomUI
        ' Outlook will try to load all ribbons (found in your ribbon xml) into any window the user goes to. Error if "Show add-in user interface errors" option (in Options -> Advanced).
        Select Case ribbonID
            Case "Microsoft.Outlook.Explorer"
                Return GetResourceText("outlook_spam_addin.Ribbon.xml")
            Case Else
                Return Nothing
        End Select
    End Function

#Region "Ribbon Callbacks"
    'Create callback methods here. For more information about adding callback methods, visit https://go.microsoft.com/fwlink/?LinkID=271226
    Public Sub Ribbon_Load(ByVal ribbonUI As Microsoft.Office.Core.IRibbonUI)
        Me.ribbon = ribbonUI
        keyLanguage = Globals.ThisAddIn.Application.LanguageSettings.LanguageID(Microsoft.Office.Core.MsoAppLanguageID.msoLanguageIDUI)
    End Sub

    Public Function GroupSpam_Label(ByVal control As Microsoft.Office.Core.IRibbonControl) As String
        Return config.group.Item(If(config.group.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
    End Function

    Public Function ButtonSpam_Label(ByVal control As Microsoft.Office.Core.IRibbonControl) As String
        Return config.button.Item(If(config.button.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
    End Function

    Public Function ButtonSpam_Description(ByVal control As Microsoft.Office.Core.IRibbonControl) As String
        Return config.buttonHoverDescription.Item(If(config.buttonHoverDescription.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
    End Function

    Public Function ButtonSpam_ScreenTip(ByVal control As Microsoft.Office.Core.IRibbonControl) As String
        Return config.buttonScreenTip.Item(If(config.buttonScreenTip.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
    End Function

    Public Function ButtonSpam_SuperTip(ByVal control As Microsoft.Office.Core.IRibbonControl) As String
        Return config.buttonSuperTip.Item(If(config.buttonSuperTip.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
    End Function

    Public Sub ButtonSpam_Click(ByVal control As Microsoft.Office.Core.IRibbonControl)
        Try
            appLog.Source = Config.eventLogName

            Dim reportEmailBody As String = ""
            Dim msgBoxItemTypeTitle As String = ""
            Dim msgBoxItemTypeBody As String = ""

            Dim msgBoxConfirmTitle As String = ""
            Dim msgBoxConfirmBodyOne As String = ""
            Dim msgBoxConfirmBodyMore As String = ""

            Dim msgBoxEmptyTitle As String = ""
            Dim msgBoxEmptyBody As String = ""

            Dim msgBoxEncryptedTitle As String = ""
            Dim msgBoxEncryptedBody As String = ""

            Dim msgBoxTooManyRecipients As String = ""
            Dim msbBoxNoInternalMsg As String = ""

            Dim ackSubject As String = ""
            Dim ackBodyOne As String = ""
            Dim ackBodyMore As String = ""

            Dim msgBoxNotConfiguredTitle As String = "Add-in not configured"
            Dim msgBoxNotConfiguredBody As String = "The reporting add-in has not been configured on this computer. Please contact your IT support. No message was sent."

            Try
                reportEmailBody = config.reportEmailBody.Item(If(config.reportEmailBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxItemTypeTitle = config.msgBoxItemTypeTitle.Item(If(config.msgBoxItemTypeTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxItemTypeBody = config.msgBoxItemTypeBody.Item(If(config.msgBoxItemTypeBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxConfirmTitle = config.msgBoxConfirmTitle.Item(If(config.msgBoxConfirmTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxConfirmBodyOne = config.msgBoxConfirmBodyOne.Item(If(config.msgBoxConfirmBodyOne.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxConfirmBodyMore = config.msgBoxConfirmBodyMore.Item(If(config.msgBoxConfirmBodyMore.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxEmptyTitle = config.msgBoxEmptyTitle.Item(If(config.msgBoxEmptyTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxEmptyBody = config.msgBoxEmptyBody.Item(If(config.msgBoxEmptyBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxEncryptedTitle = config.msgBoxEncryptedTitle.Item(If(config.msgBoxEncryptedTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxEncryptedBody = config.msgBoxEncryptedBody.Item(If(config.msgBoxEncryptedBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxErrorTitle = config.msgBoxErrorTitle.Item(If(config.msgBoxErrorTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxErrorBody = config.msgBoxErrorBody.Item(If(config.msgBoxErrorBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxTooManyRecipients = config.msgBoxTooManyRecipients.Item(If(config.msgBoxTooManyRecipients.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msbBoxNoInternalMsg = config.msbBoxNoInternalMsg.Item(If(config.msbBoxNoInternalMsg.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                ackSubject = config.ackSubject.Item(If(config.ackSubject.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                ackBodyOne = config.ackBodyOne.Item(If(config.ackBodyOne.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                ackBodyMore = config.ackBodyMore.Item(If(config.ackBodyMore.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))

                msgBoxNotConfiguredTitle = config.msgBoxNotConfiguredTitle.Item(If(config.msgBoxNotConfiguredTitle.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
                msgBoxNotConfiguredBody = config.msgBoxNotConfiguredBody.Item(If(config.msgBoxNotConfiguredBody.ContainsKey(keyLanguage), keyLanguage, Config.wdEnglishUS))
            Catch ex As System.Exception
                Try
                    appLog.WriteEntry("Exception while setting language, (could be a KeyNotFoundException) " & ex.Message & ex.StackTrace, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                Catch appEx As System.Exception

                End Try
            End Try

            ' SECURITE (fail-close) : sans destinataire valide configure, on N'ENVOIE RIEN.
            If Not Config.IsValidRecipientList(config.toSecurityTeamCERT) AndAlso Not Config.IsValidRecipientList(config.ccSecurityTeamSpamBit) Then
                MsgBox(msgBoxNotConfiguredBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxNotConfiguredTitle)
                Try
                    appLog.WriteEntry("BoutonSPAM non configure (aucune adresse de destination valide) : envoi bloque.", System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                Catch appEx As System.Exception

                End Try
                Exit Sub
            End If

            Dim exp As Outlook.Explorer = Globals.ThisAddIn.Application.ActiveExplorer()

            'Dim ins As Outlook.Inspector = Globals.ThisAddIn.Application.ActiveInspector()

            'If ins IsNot Nothing Then
            '    exp.ClearSelection()
            '    exp.AddToSelection(ins.CurrentItem())
            'End If

            Dim selectionCount = &H0

            ' Avoid an exception if called from the home pane
            Try
                selectionCount = exp.Selection.Count
            Catch ex As System.Exception
                selectionCount = &H0
            End Try

            If selectionCount > &H0 Then
                ' Confirm the submission, no is the default value
                If MsgBox(If(selectionCount > &H1, String.Format(msgBoxConfirmBodyMore, selectionCount), msgBoxConfirmBodyOne), MsgBoxStyle.YesNo Or MsgBoxStyle.Question Or MsgBoxStyle.DefaultButton2, msgBoxConfirmTitle) = MsgBoxResult.Yes Then
                    ' Number of successfully reported emails (for the acknowledgment)
                    Dim reportedCount As Integer = 0
                    ' Nombre de messages entierement prepares et presentes a l'envoi
                    ' (apres tous les filtres/annulations). Sert a detecter un echec d'envoi
                    ' total (reportedCount=0 alors que des messages etaient prets) et a en
                    ' informer l'utilisateur au lieu d'un abandon silencieux.
                    Dim attemptedCount As Integer = 0
                    ' Nombre d'items ayant leve une exception NON geree pendant leur
                    ' traitement (captee par le Try/Catch par-item ci-dessous). Utilise pour
                    ' avertir l'utilisateur si, au final, rien n'a pu etre signale.
                    Dim failedCount As Integer = 0
                    For Each phishEmail As Object In exp.Selection()

                        ' Chaque item est traite dans un Try/Catch DEDIE. Un item forge
                        ' (propriete manquante, exception inattendue) est journalise puis IGNORE
                        ' sans interrompre le signalement des AUTRES items selectionnes (le bloc
                        ' se termine par la fin de boucle, equivalent d'un Continue For).
                        Try

                        ' Try to cast the selected item as an Microsoft.Office.Interop.Outlook.MailItem, only emails are supported at this time
                        Try
                            phishEmail = CType(phishEmail, Outlook.MailItem)
                        Catch ex As System.InvalidCastException
                            ' Continue to the next event if the type casting failed
                            MsgBox(msgBoxItemTypeBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxItemTypeTitle)
                            Try
                                appLog.WriteEntry("Unable to cast item (System.InvalidCastException) " & ex.Message & ex.StackTrace, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                            Continue For
                        End Try

                        Dim phishEmailSecurityFlags = Config.reportSecurityFlagsNothing
                        ' Try if the email was encrypted, and the certificate was not present to decrypt it
                        Try
                            ' Check the phishing email encrypted and signed flags
                            phishEmailSecurityFlags = CInt(CType(phishEmail, Outlook.MailItem).PropertyAccessor.GetProperty(Config.PR_SECURITY_FLAGS))
#If DEBUG Then
                            System.Diagnostics.Debug.Print("Phishing email signed/encrypted status : " & phishEmailSecurityFlags)
#End If
                        Catch ex As System.Exception
                            MsgBox(msgBoxEncryptedBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxEncryptedTitle)
                            Try
                                appLog.WriteEntry(msgBoxEncryptedBody, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                            Continue For
                        End Try

                        ' Phishing email was encrypted, check if we are trying to decrypt encrypted messages and if we do, decrypt it
                        If CBool(phishEmailSecurityFlags And Config.reportSecurityFlagsEncrypted) And Not config.handleEncryptedMailitem Then
                            MsgBox(msgBoxEncryptedBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxEncryptedTitle)
                            Try
                                appLog.WriteEntry(msgBoxEncryptedBody, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                            Continue For
                        End If

                        Dim internalMessageOverride As Boolean = False

                        If config.filterInternalMessages Then
                            Try
                                ' Regex d'origine REGISTRE appliquee a une entree controlee par
                                ' l'attaquant (adresse d'expediteur) : delai borne (MatchTimeout,
                                ' 500 ms) pour eviter un deni de service par retour arriere.
                                Dim rxInternal As New System.Text.RegularExpressions.Regex(config.regexInteralMessages, System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500))
                                If rxInternal.Match(CType(phishEmail, Outlook.MailItem).SenderEmailAddress).Success Then
                                    If MsgBox(String.Format(msbBoxNoInternalMsg, CType(phishEmail, Outlook.MailItem).SenderEmailAddress), MsgBoxStyle.YesNo Or MsgBoxStyle.Exclamation Or MsgBoxStyle.DefaultButton2, msgBoxEncryptedTitle) = MsgBoxResult.No Then
                                        Continue For
                                    End If

                                    internalMessageOverride = True
                                End If
                            Catch ex As System.ArgumentNullException
                                ' Adresse d'expediteur nulle : on laisse l'utilisateur signaler
                            Catch ex As System.Text.RegularExpressions.RegexMatchTimeoutException
                                ' Motif trop couteux : on ne bloque pas, on laisse signaler
                            Catch ex As System.Exception
                                ' Motif invalide ou autre : filtre interne ignore, on laisse signaler
                            End Try
                        End If

                        Dim reportEmail As Outlook.MailItem = CType(Globals.ThisAddIn.Application.CreateItem(Outlook.OlItemType.olMailItem), Outlook.MailItem)

                        ' Report email general infos
                        reportEmail.Subject = Config.reportEmailSubject
                        reportEmail.To = config.toSecurityTeamCERT
                        reportEmail.CC = config.ccSecurityTeamSpamBit
                        reportEmail.Importance = Outlook.OlImportance.olImportanceLow
                        reportEmail.Sensitivity = Outlook.OlSensitivity.olPersonal
                        reportEmail.Body = If(Config.reportDateEnabled, Config.reportDateLabel & Now.ToString(Config.reportDateFormat) & vbCrLf & vbCrLf, "") & reportEmailBody
                        reportEmail.DeleteAfterSubmit = True
                        reportEmail.OriginatorDeliveryReportRequested = False
                        reportEmail.ReadReceiptRequested = False
                        If CBool(phishEmailSecurityFlags And Config.reportSecurityFlagsEncrypted) And config.handleEncryptedMailitem Then
                            reportEmail.Body += Config.reportMsgEncrypted
                            reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                            reportEmail.Sensitivity = Outlook.OlSensitivity.olConfidential
                        End If

                        Try
                            ' Phishing email contains too many recipients ( > maxNumberOfRecipients), and thus cannot be forwarded
                            If config.maxNumberOfRecipients > 0 Then
                                Dim recipientsCount As Integer = CType(phishEmail, Outlook.MailItem).Recipients.Count
                                If recipientsCount > config.maxNumberOfRecipients Then
                                    MsgBox(String.Format(msgBoxTooManyRecipients, recipientsCount), MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxEncryptedTitle)
                                    Try
                                        appLog.WriteEntry(String.Format(msgBoxTooManyRecipients, recipientsCount), System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                                    Catch appEx As System.Exception

                                    End Try
                                    Continue For
                                End If
                            End If
                        Catch ex As System.Exception
                            ' Recipients count failed
                        End Try

                        ' SECURITE : nom de fichier temporaire ALEATOIRE (chemin non previsible),
                        ' et suppression GARANTIE via Finally (l'echantillon ne persiste pas
                        ' sur disque, meme en cas d'exception).
                        Dim tempMsgPath As String = Config.NewSpamTempPath()
                        Try
                            If CBool(phishEmailSecurityFlags And Config.reportSecurityFlagsEncrypted) And config.handleEncryptedMailitem Then
                                CType(phishEmail, Outlook.MailItem).PropertyAccessor.SetProperty("http://schemas.microsoft.com/mapi/proptag/0x6E010003", 0)
                            End If
                            CType(phishEmail, Outlook.MailItem).SaveAs(tempMsgPath, Outlook.OlSaveAsType.olMSG)
                            reportEmail.Attachments.Add(tempMsgPath, Outlook.OlAttachmentType.olEmbeddeditem)
                        Finally
                            Try
                                If Not String.IsNullOrEmpty(Dir(tempMsgPath)) Then
                                    SetAttr(tempMsgPath, vbNormal)
                                    Kill(tempMsgPath)
                                End If
                            Catch exDel As System.Exception
                                Try
                                    appLog.WriteEntry("Unable to delete temp message: " & exDel.Message, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                                Catch appEx As System.Exception

                                End Try
                            End Try
                        End Try

                        Dim linksCount = 0
                        Try
                            ' Count links in phishing email, could give a few more if the BodyFormat of the reported email is in html
                            linksCount = System.Text.RegularExpressions.Regex.Matches(CType(phishEmail, Outlook.MailItem).Body, "(https?:\/\/|[^https?:\/\/]www\.)", System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500)).Count
                        Catch ex As System.Exception
                            ' Has occured with an empty body
                        End Try

                        If linksCount > 0 Then
                            reportEmail.Body += String.Format(Config.reportMsgLinks, linksCount)
                            reportEmail.Importance = Outlook.OlImportance.olImportanceNormal
                        End If

#If DEBUG Then
                        System.Diagnostics.Debug.Print("Links count " & linksCount)
#End If

                        ' Count attachments in phishing email
                        Dim attachmentCount = CType(phishEmail, Outlook.MailItem).Attachments.Count
                        If attachmentCount > 0 Then
                            reportEmail.Body += String.Format(Config.reportMsgAttachments, attachmentCount)
                            reportEmail.Importance = Outlook.OlImportance.olImportanceNormal

                            ' TODO check the datatype (string, listof(string), Set, ...) and maybe change to a new one, or list.Contains() to perform a linear search
                            ' Potentially malicious filename extensions
                            Dim blacklistedExtensions = New String() {".exe", ".pif", ".application", ".gadget", ".msi", ".msp", ".com", ".scr", ".hta", ".cpl", ".msc", ".jar", ".bat", ".cmd", ".vb", ".vbs",
                                ".vbe", ".js", ".jse", ".ws", ".wsf", ".wsc", ".wsh", ".ps1", ".ps1xml", ".ps2", ".ps2xml", ".psc1", ".psc2", ".msh", ".msh1", ".msh2", ".mshxml", ".msh1xml", ".msh2xml", ".scf",
                                ".lnk", ".inf", ".reg",
                                ".doc", ".xls", ".ppt", ".docx", ".xlsx", ".pptx", ".docm", ".dotm", ".xlsm", ".xltm", ".xlam", ".pptm", ".potm", ".ppam", ".ppsm", ".sldm", ".pdf",
                                ".htm", ".html", ".xhtml", ".xht", ".mht", ".mhtml", ".maff", ".asp", ".aspx", ".bml", ".cfm", ".cgi", ".ihtml", ".jsp", ".las", ".lasso", ".lassoapp", ".pl", ".php", ".phtml",
                                ".rna", ".r", ".rnx", ".shtml", ".stm",
                                ".iso", ".tar", ".bz2", ".gz", ".lz", ".lzma", ".lzo", ".7z", ".s7z", ".ace", ".afa", ".alz", ".apk", ".arc", ".arj", ".b1", ".ba", ".bh", ".cab", ".car", ".cfs", ".cpt", ".dar", ".dd",
                                ".dgc", ".dmg", ".ear", ".gca", ".ha", ".hki", ".ice", ".jar", ".kgb", ".lzh", ".lha", ".lzx", ".pak", ".partimg", ".paq6", ".paq7", ".paq8", ".pea", ".pim", ".pit", ".qda", ".rar", ".rk",
                                ".sda", ".sea", ".sen", ".sfx", ".shk", ".sit", ".sitx", ".sqx", ".tgz", ".tbz2", ".tlz", ".uca", ".uha", ".war", ".wim", ".xar", ".xp3", ".yz1", ".zip", ".zipx", ".zoo", ".zpaq", ".zz"}

                            ' For each attachment, check if the blocklevel or the extension trigger
                            For Each attachment As Outlook.Attachment In CType(phishEmail, Outlook.MailItem).Attachments
                                Dim attachmentExt = Right(attachment.FileName, Len(attachment.FileName) - InStrRev(attachment.FileName, ".") + &H1)
                                Dim attachmentPrint = attachmentExt

                                ' There is no restriction on the type of the attachment based on its file extension, or there is a restriction on the type of the attachment based on its file extension such that users must first save the attachment to disk before opening it.
                                If CBool(attachment.BlockLevel) Then
                                    reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                                    attachmentPrint += Config.reportTagBlocklevel
#If DEBUG Then
                                    System.Diagnostics.Debug.Print("Blocklevel extension " & attachment.FileName)
#End If
                                End If

                                ' StringComparaison Enum https://msdn.microsoft.com/en-us/library/system.stringcomparison(v=vs.110).aspx
                                For Each ext In blacklistedExtensions
                                    If attachment.FileName.EndsWith(ext, System.StringComparison.InvariantCultureIgnoreCase) Then
                                        reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                                        attachmentPrint += Config.reportTagBlacklisted
#If DEBUG Then
                                        System.Diagnostics.Debug.Print("Blacklisted extensions " & attachment.FileName)
#End If
                                        Exit For
                                    End If
                                Next
                                reportEmail.Body += attachmentPrint & " [" & attachment.FileName & "]"
                            Next
                        End If

                        ' Most of the phishing email contains 1-2 links
                        If linksCount > 0 And linksCount < 3 Then
                            reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                        End If

                        ' Phishing email was signed
                        If CBool(phishEmailSecurityFlags And Config.reportSecurityFlagsSigned) Then
                            reportEmail.Body += Config.reportMsgSigned
                            reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                        End If

                        Dim listUnsubscribe As String = ""
                        Try
                            listUnsubscribe = System.Text.RegularExpressions.Regex.Match(GetRawHeaders(CType(phishEmail, Outlook.MailItem)), "List-Unsubscribe: (.*)", System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500)).Groups(1).Value
                            If Not String.IsNullOrEmpty(listUnsubscribe) Then
                                ' SECURITE : valeur d'en-tete controlee par l'expediteur. On la LABELLISE
                                ' explicitement comme provenant du message signale et on la neutralise
                                ' (caracteres de controle retires, longueur bornee) pour empecher la
                                ' forge d'un faux bandeau d'analyse trompant l'analyste.
                                reportEmail.Body += vbCrLf & "En-tete du message signale - List-Unsubscribe : " & Config.SafeInline(listUnsubscribe, 200)
                                reportEmail.Importance = Outlook.OlImportance.olImportanceLow
                            Else
                                ' If Regex.Match(CType(phishEmail, Outlook.MailItem).SenderEmailAddress, "(^/O=INTERNDOMAIN/OU=EXCHANGE|.*domain.ch)", RegexOptions.IgnoreCase).Success Then
                                If System.Text.RegularExpressions.Regex.Match(CType(phishEmail, Outlook.MailItem).SenderEmailAddress, "(\.fr$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500)).Success Then
                                    reportEmail.Body += Config.reportMsgNationalDomain
                                    reportEmail.Importance = Outlook.OlImportance.olImportanceHigh
                                End If
                            End If
                        Catch ex As System.Exception

                        End Try
#If DEBUG Then
                        ' Attachment count
                        System.Diagnostics.Debug.Print("Attachments count :  " & attachmentCount)

                        ' Print the email importance : 0=low, 1=normal, or 2=high
                        System.Diagnostics.Debug.Print("Email importance " & reportEmail.Importance)
#End If
                        ' Get the spam score from the headers or String.Empty and the reported email priority
                        Dim xSpamImportance As String = config.reportEmailImportance.Item(If(config.reportEmailImportance.ContainsKey(reportEmail.Importance), reportEmail.Importance, &H1))
                        Dim xSpamScore As String = ""

                        Try
                            xSpamScore = System.Text.RegularExpressions.Regex.Match(GetRawHeaders(CType(phishEmail, Outlook.MailItem)), "X-Spam-Status:.*score=([\d\.-]{1,6})", System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500)).Groups(1).Value
                        Catch ex As System.Exception
                            xSpamScore = ""
                        End Try

                        ' SECURITE : le routage du signalement ne doit JAMAIS dependre de l'en-tete
                        ' X-Spam-Status. Cet en-tete est ajoute par un filtre anti-spam
                        ' (SpamAssassin), PAS par Exchange : un attaquant peut le forger dans le
                        ' mail de phishing (ex. "X-Spam-Status: ... score=10") pour faire
                        ' disparaitre le CC (equipe securite) du signalement. On conserve donc
                        ' TOUJOURS les destinataires configures (To + Cc, definis lignes 244-245).
                        ' Le score reste affiche dans l'objet a titre purement informatif :
                        ' la regex borne l'extraction a [\d\.-]{1,6}, donc aucune injection
                        ' possible dans l'objet et aucune incidence sur le routage.
                        reportEmail.Subject = Config.reportEmailSubject & " [" & xSpamImportance & "] [" & xSpamScore & "] - '" & CType(phishEmail, Outlook.MailItem).Subject & "'" & If(internalMessageOverride, " [INTERN]", "")

                        ' Recupere les en-tetes bruts UNE fois (source de verite + base de l'analyse).
                        ' CORRECTIF DKIM/SPF : lecture Unicode-d'abord puis ANSI (voir GetRawHeaders) ;
                        ' l'ancienne lecture ANSI directe revenait souvent vide -> pas d'analyse d'auth.
                        Dim rawHeaders As String = GetRawHeaders(CType(phishEmail, Outlook.MailItem))

                        ' Bloc d'ANALYSE TECHNIQUE pour les analystes (auth, routage, scores, IOC).
                        ' Entierement protege : ne doit JAMAIS empecher l'envoi du signalement.
                        If config.includeTechnicalReport Then
                            Try
                                reportEmail.Body += vbCrLf & vbCrLf & Config.BuildHeaderAnalysis(rawHeaders)
                                reportEmail.Body += BuildOutlookAnalysis(CType(phishEmail, Outlook.MailItem), config)
                            Catch exTech As System.Exception
                                Try
                                    appLog.WriteEntry("Technical report skipped: " & exTech.Message, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                                Catch appEx As System.Exception

                                End Try
                            End Try
                        End If

                        ' En-tetes bruts complets (source de verite pour l'analyste).
                        reportEmail.Body += vbCrLf & vbCrLf & "===== EN-TETES BRUTS =====" & vbCrLf & rawHeaders

                        ' Send report email without encrypt and sign (mostly to team mailbox)
                        reportEmail.PropertyAccessor.SetProperty(Config.PR_SECURITY_FLAGS, Config.reportSecurityFlagsNothing)

                        Dim successLogEntry = CType(phishEmail, Outlook.MailItem).Subject & vbCrLf & reportEmail.Body

                        ' SECURITE : garde d'envoi STRICTE (au moins un destinataire valide).
                        ' Ce message a passe tous les filtres : il est pret a etre envoye.
                        attemptedCount += 1
                        Dim wasSent As Boolean = False
                        If Config.IsValidRecipientList(reportEmail.To) OrElse Config.IsValidRecipientList(reportEmail.CC) Then
                            Try
                                reportEmail.Send()
                                reportedCount += 1
                                wasSent = True
                            Catch exSend As System.Exception
                                ' L'echec d'envoi d'UN message (erreur de transport,
                                ' boite indisponible...) ne doit PAS interrompre le traitement
                                ' des autres messages selectionnes. On journalise et on continue ;
                                ' le message d'origine n'est pas supprime (wasSent reste False).
                                Try
                                    appLog.WriteEntry("Echec d'envoi du signalement pour '" & CType(phishEmail, Outlook.MailItem).Subject & "' : " & exSend.Message, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                                Catch appEx As System.Exception

                                End Try
                            End Try
                        Else
                            ' Pas d'echec silencieux. Un message pret mais non envoye
                            ' (aucun destinataire valide au moment de l'envoi) est journalise.
                            ' Le message d'origine n'est PAS supprime (wasSent reste False).
                            Try
                                appLog.WriteEntry("Signalement NON envoye (aucun destinataire valide To/Cc) pour '" & CType(phishEmail, Outlook.MailItem).Subject & "'. Verifier RegistryConfig.", System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                        End If

                        ' On ne supprime le message signale QUE s'il a bien ete envoye
                        ' (sinon aucune perte de donnees pour l'utilisateur).
                        If wasSent Then
                            Try
                                CType(phishEmail, Outlook.MailItem).Delete()
                            Catch ex As System.Runtime.InteropServices.COMException
                                ' Occurs in debug mode only ? (Win7 VS2010)
                            End Try
                            Try
                                appLog.WriteEntry("Spam reported successfully " & successLogEntry, System.Diagnostics.EventLogEntryType.Information, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                        End If

                        ' Fin du Try/Catch par-item. Toute exception non geree plus haut
                        ' est captee ici : on la journalise, on incremente le compteur d'echecs
                        ' et on passe a l'item suivant (le lot n'est jamais interrompu).
                        Catch exItem As System.Exception
                            failedCount += 1
                            Try
                                appLog.WriteEntry("Item ignore (exception non geree pendant le traitement) : " & exItem.Message & exItem.StackTrace, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                        End Try
                    Next

                    ' Automatic acknowledgment to the reporting user (registry switch: SendAcknowledgment)
                    If reportedCount > &H0 AndAlso config.sendAcknowledgment Then
                        Try
                            Dim ackEmail As Outlook.MailItem = CType(Globals.ThisAddIn.Application.CreateItem(Outlook.OlItemType.olMailItem), Outlook.MailItem)
                            ackEmail.To = Globals.ThisAddIn.Application.Session.CurrentUser.Address
                            ackEmail.Subject = ackSubject
                            ' Accuse de reception en HTML (mise en forme : sauts de ligne + derniere phrase en italique).
                            ' La police/taille est posee ICI, une fois, par un <div> englobant : les constantes
                            ' ackBody* (Config.vb) et les champs UI_ACK_BODY_* (branding.conf) ne portent donc
                            ' QUE le texte + la mise en forme en ligne (<br>, <i>...</i>), sur UNE seule ligne
                            ' (indispensable pour que 02_customize.sh puisse y injecter la valeur de branding.conf).
                            ackEmail.HTMLBody = "<div style='font-family:Calibri,Segoe UI,Arial,sans-serif;font-size:11pt'>" & If(reportedCount > &H1, String.Format(ackBodyMore, reportedCount), ackBodyOne) & "</div>"
                            ackEmail.Importance = Outlook.OlImportance.olImportanceLow
                            ackEmail.OriginatorDeliveryReportRequested = False
                            ackEmail.ReadReceiptRequested = False
                            ackEmail.DeleteAfterSubmit = True
                            ackEmail.Send()
                        Catch ex As System.Exception
                            ' Acknowledgment is best-effort: never block or bother the user if it fails
                            Try
                                appLog.WriteEntry("Unable to send the acknowledgment email " & ex.Message, System.Diagnostics.EventLogEntryType.Warning, Config.eventID)
                            Catch appEx As System.Exception

                            End Try
                        End Try
                    End If

                    ' Pas d'echec silencieux. Si des messages etaient prets a
                    ' etre signales (attemptedCount > 0) ou si des items ont echoue
                    ' (failedCount > 0) mais qu'AUCUN n'a finalement ete envoye, on informe
                    ' explicitement l'utilisateur (destinataires invalides / config incomplete
                    ' / item en erreur). Les messages d'origine ne sont PAS supprimes.
                    If reportedCount = &H0 AndAlso (attemptedCount > &H0 OrElse failedCount > &H0) Then
                        MsgBox(msgBoxNotConfiguredBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Exclamation, msgBoxNotConfiguredTitle)
                    End If
                End If
            Else
                ' No message selected
                MsgBox(msgBoxEmptyBody, MsgBoxStyle.OkOnly Or MsgBoxStyle.Information, msgBoxEmptyTitle)
            End If

        Catch ex As System.Exception
            ' Default exception handler, if an unexpected exception occurs
            MsgBox(msgBoxErrorBody & " " & ex.Message, MsgBoxStyle.OkOnly Or MsgBoxStyle.Critical, msgBoxErrorTitle)

            ' Send the message and stack trace by email only to the RibbonSpamConfig.SecurityTeamEmail team-mailbox
#If DEBUG Then
            System.Diagnostics.Debug.Print("Unable to process spam " & ex.Message & ex.StackTrace)
#End If
            ' La trace de pile complete reste dans le JOURNAL D'EVENEMENTS local (detail
            ' pour le poste concerne), et N'EST PAS envoyee par e-mail.
            Try
                appLog.WriteEntry("Unable to process spam " & ex.Message & vbCrLf & ex.StackTrace, System.Diagnostics.EventLogEntryType.Error, Config.eventID)
            Catch appEx As System.Exception

            End Try
            ' N'envoyer la notification d'erreur QUE vers un destinataire interne VALIDE
            ' (coherent avec le fail-close), et SANS trace de pile ni identifiants.
            If Config.IsValidRecipientList(config.toSecurityTeamCERT) Then
                Try
                    Dim errorEmail As Outlook.MailItem = CType(Globals.ThisAddIn.Application.CreateItem(Outlook.OlItemType.olMailItem), Outlook.MailItem)

                    errorEmail.Subject = Config.exceptionEmailSubject & " - 'Exception occurs'"
                    errorEmail.To = config.toSecurityTeamCERT
                    errorEmail.Body = "BoutonSPAM " & Config.addinVersion & " - " & Config.targetOS & vbCrLf &
                                      "Poste : " & Environ("COMPUTERNAME") & vbCrLf &
                                      "Une exception est survenue lors d'un signalement." & vbCrLf &
                                      "Message : " & ex.Message & vbCrLf &
                                      "Details techniques complets : voir le journal d'evenements Windows du poste concerne (source " & Config.eventLogName & ", ID " & Config.eventID & ")."
                    errorEmail.Send()
                Catch exMail As System.Exception
                    ' notification best-effort
                End Try
            End If
        End Try
    End Sub

#End Region

#Region "Helpers"

    ' CORRECTIF DKIM/SPF : lecture ROBUSTE des en-tetes internet bruts.
    ' L'ancienne lecture directe en ANSI (PR_TRANSPORT_MESSAGE_HEADERS, 0x007D001E)
    ' revenait souvent VIDE sur Outlook/Exchange moderne (magasin Unicode, mode
    ' cache, messages internes) : GetProperty levait, les en-tetes etaient vides,
    ' et l'analyse SPF/DKIM/DMARC comme le bloc "en-tetes bruts" restaient muets.
    ' On tente ici la variante UNICODE (0x007D001F) EN PREMIER, puis l'ANSI en
    ' repli. Ne leve jamais : renvoie "" si aucune variante n'est disponible
    ' (message reellement non-SMTP ou droits insuffisants).
    Private Shared Function GetRawHeaders(ByVal mi As Outlook.MailItem) As String
        Dim tags() As String = {Config.PR_TRANSPORT_MESSAGE_HEADERS_UNICODE, Config.PR_TRANSPORT_MESSAGE_HEADERS}
        For Each tag As String In tags
            Try
                Dim v As Object = mi.PropertyAccessor.GetProperty(tag)
                If v IsNot Nothing Then
                    Dim s As String = CStr(v)
                    If Not String.IsNullOrEmpty(s) Then Return s
                End If
            Catch
                ' Propriete absente sous ce tag : on tente la variante suivante.
            End Try
        Next
        Return ""
    End Function

    Private Shared Function GetResourceText(ByVal resourceName As String) As String
        Dim asm As System.Reflection.Assembly = System.Reflection.Assembly.GetExecutingAssembly()
        Dim resourceNames() As String = asm.GetManifestResourceNames()
        For i As Integer = 0 To resourceNames.Length - 1
            If String.Compare(resourceName, resourceNames(i), System.StringComparison.OrdinalIgnoreCase) = 0 Then
                Using resourceReader As System.IO.StreamReader = New System.IO.StreamReader(asm.GetManifestResourceStream(resourceNames(i)))
                    If resourceReader IsNot Nothing Then
                        Return resourceReader.ReadToEnd()
                    End If
                End Using
            End If
        Next
        Return Nothing
    End Function

    ' Complement d'ANALYSE TECHNIQUE a partir des proprietes Outlook (hors en-tetes) :
    ' adresse SMTP reelle de l'expediteur, liens neutralises et empreintes SHA-256 des
    ' pieces jointes. Tout est protege : cette fonction ne leve jamais d'exception.
    Private Function BuildOutlookAnalysis(ByVal pm As Outlook.MailItem, ByVal cfg As Config) As String
        Dim sb As New System.Text.StringBuilder()

        ' Expediteur cote Outlook (adresse SMTP reelle meme derriere un affichage Exchange).
        Try
            Dim senderSmtp As String = ""
            Try
                If String.Equals(pm.SenderEmailType, "EX", System.StringComparison.OrdinalIgnoreCase) Then
                    senderSmtp = CStr(pm.PropertyAccessor.GetProperty(Config.PR_SENDER_SMTP_ADDRESS))
                End If
            Catch exSmtp As System.Exception

            End Try
            sb.AppendLine("")
            sb.AppendLine("[ Expediteur (cote Outlook) ]")
            sb.AppendLine("  Nom affiche      : " & If(pm.SenderName IsNot Nothing, pm.SenderName, ""))
            sb.AppendLine("  Adresse          : " & If(pm.SenderEmailAddress IsNot Nothing, pm.SenderEmailAddress, ""))
            sb.AppendLine("  Type             : " & If(pm.SenderEmailType IsNot Nothing, pm.SenderEmailType, ""))
            If senderSmtp <> "" Then sb.AppendLine("  SMTP reel (EX)   : " & senderSmtp)
            Try
                sb.AppendLine("  Recu le          : " & pm.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss"))
            Catch exRt As System.Exception

            End Try
        Catch exSender As System.Exception

        End Try

        ' Liens contenus dans le corps, neutralises (hxxp), uniques, plafonnes.
        Try
            Dim phishBody As String = pm.Body
            If Not String.IsNullOrEmpty(phishBody) Then
                Dim seen As New System.Collections.Generic.HashSet(Of String)(System.StringComparer.OrdinalIgnoreCase)
                Dim urls As New System.Collections.Generic.List(Of String)
                For Each mm As System.Text.RegularExpressions.Match In System.Text.RegularExpressions.Regex.Matches(phishBody, "https?://[^\s""'>)\]]+", System.Text.RegularExpressions.RegexOptions.IgnoreCase, System.TimeSpan.FromMilliseconds(500))
                    Dim u As String = mm.Value.TrimEnd("."c, ","c, ";"c, ")"c)
                    If seen.Add(u) Then urls.Add(u)
                    If urls.Count >= Config.reportMaxLinks Then Exit For
                Next
                If urls.Count > 0 Then
                    sb.AppendLine("")
                    sb.AppendLine("[ Liens neutralises (hxxp, uniques, max " & Config.reportMaxLinks & ") ]")
                    For Each u As String In urls
                        sb.AppendLine("  " & Config.Defang(u))
                    Next
                End If
            End If
        Catch exUrl As System.Exception

        End Try

        ' Empreintes SHA-256 des pieces jointes (ecriture temporaire puis suppression garantie).
        Try
            If cfg.hashAttachments AndAlso pm.Attachments.Count > 0 Then
                sb.AppendLine("")
                sb.AppendLine("[ Pieces jointes - SHA-256 (recherche VirusTotal / MISP) ]")
                ' Nombre de PJ reellement ecrites/hachees sur ce message
                ' (borne les operations couteuses SaveAsFile + hachage sur le thread UI).
                Dim inspectedCount As Integer = 0
                For Each att As Outlook.Attachment In pm.Attachments
                    Dim attLine As String = "  " & att.FileName
                    Dim hpath As String = ""
                    Try
                        ' Plafond du nombre de PJ traitees (anti-DoS client).
                        If inspectedCount >= Config.reportMaxHashCount Then
                            attLine &= "  |  SHA-256: (ignore, trop de pieces jointes)"
                        Else
                            Dim sz As Long = -1
                            Try
                                sz = CLng(att.PropertyAccessor.GetProperty(Config.PR_ATTACH_SIZE))
                            Catch exSz As System.Exception

                            End Try
                            If sz >= 0 Then attLine &= "  |  " & sz.ToString() & " o"
                            If sz > Config.reportMaxHashBytes Then
                                ' Taille annoncee au-dela du plafond : on n'ecrit meme pas le fichier.
                                attLine &= "  |  SHA-256: (ignore, trop volumineux)"
                            Else
                                hpath = Config.NewSpamTempPath()
                                att.SaveAsFile(hpath)
                                inspectedCount += 1
                                ' La garde via PR_ATTACH_SIZE est contournable (propriete
                                ' absente => sz = -1 => "-1 > max" faux => hachage quand meme).
                                ' On REVALIDE sur la taille REELLE du fichier ecrit avant de hacher.
                                Dim realLen As Long = -1
                                Try
                                    realLen = New System.IO.FileInfo(hpath).Length
                                Catch exLen As System.Exception

                                End Try
                                If realLen > Config.reportMaxHashBytes Then
                                    attLine &= "  |  SHA-256: (ignore, trop volumineux)"
                                Else
                                    Using fsx As System.IO.FileStream = System.IO.File.OpenRead(hpath)
                                        Using sha As System.Security.Cryptography.SHA256 = System.Security.Cryptography.SHA256.Create()
                                            attLine &= "  |  SHA-256: " & System.BitConverter.ToString(sha.ComputeHash(fsx)).Replace("-", "").ToLowerInvariant()
                                        End Using
                                    End Using
                                End If
                            End If
                        End If
                    Catch exHash As System.Exception
                        attLine &= "  |  SHA-256: (indisponible)"
                    Finally
                        Try
                            If hpath <> "" AndAlso System.IO.File.Exists(hpath) Then Kill(hpath)
                        Catch exKill As System.Exception

                        End Try
                    End Try
                    sb.AppendLine(attLine)
                Next
            End If
        Catch exAtt As System.Exception

        End Try

        Return sb.ToString()
    End Function

#End Region

End Class