/* commands.js — Logique du bouton "Rapporter un Spam à Abuse" (OWA / nouveau
 * Outlook). Chargee par commands.html (FunctionFile du manifeste). Parite avec
 * le VSTO : meme rapport (analyse.js), meme .eml joint, meme boite abuse.
 *
 * Contraintes on-prem (Exchange 2016/2019/SE, jeu d'API <= 1.5) : on n'utilise
 * PAS getAllInternetHeadersAsync (1.8). En-tetes ET .eml proviennent d'un seul
 * appel EWS GetItem + IncludeMimeContent (le MIME contient les deux). Envoi via
 * EWS CreateItem (message neuf + piece jointe .eml). makeEwsRequestAsync existe
 * des le jeu 1.1.
 */
/* global Office, AnalyseSPAM */
"use strict";

var CONFIG = null;

Office.onReady(function () {
  // Precharge la config (fail-close si injoignable). Erreur avalee : re-tentee au clic.
  loadConfig().catch(function () {});
});

function loadConfig() {
  return fetch("./config.json", { cache: "no-store" })
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(function (j) { CONFIG = j; return j; });
}

/* Point d'entree declare dans le manifeste (<FunctionName>signalerSpam</FunctionName>). */
function signalerSpam(event) {
  var item = Office.context.mailbox.item;
  ensureConfig()
    .then(function (cfg) {
      if (!cfg || !cfg.abuseTo) {
        // FAIL-CLOSE : aucune adresse -> on refuse, comme le VSTO.
        throw new UserError("Configuration incomplète : aucune boîte « abuse » définie. Signalement non envoyé — contactez le support SSI.");
      }
      return getMimeViaEws(item.itemId).then(function (mime) {
        var headers = AnalyseSPAM.headersFromMime(mime);
        var subject = buildSubject(cfg, item, headers);
        var body = buildBody(cfg, headers);
        return sendReportViaEws(cfg, subject, body, mime, item)
          .then(function () { return cfg; });
      });
    })
    .then(function (cfg) {
      notify("✓ Signalement envoyé à l'équipe sécurité. Merci !");
      if (cfg.ackToUser) { /* accuse optionnel : envoye cote serveur ou ignore */ }
      finish(event);
    })
    .catch(function (err) {
      var msg = (err && err.isUser) ? err.message
        : "Échec de l'envoi du signalement. Réessayez ; si le problème persiste, prévenez le support SSI.";
      notify(msg, true);
      finish(event);
    });
}

function ensureConfig() {
  return CONFIG ? Promise.resolve(CONFIG) : loadConfig().catch(function () { return null; });
}

/* --------- Objet du rapport : parite avec Ribbon.vb:437 (prefixe + score) --------- */
function buildSubject(cfg, item, headers) {
  var h = AnalyseSPAM.unfoldHeaders(headers);
  var score = AnalyseSPAM.rx(AnalyseSPAM.headerValue(h, "X-Spam-Status"), "score=([\\d\\.\\-]{1,6})");
  var subj = (item && item.subject) ? item.subject : "";
  var prefix = cfg.reportSubjectPrefix || "[SPAM]";
  return prefix + (score ? " [" + score + "]" : "") + " - '" + subj + "'";
}

/* --------- Corps du rapport : bloc ANALYSE TECHNIQUE + en-tetes bruts --------- */
function buildBody(cfg, headers) {
  var parts = [];
  parts.push("Message signalé via le bouton SPAM (Outlook web).");
  if (cfg.includeTechnicalReport) {
    parts.push("");
    parts.push(AnalyseSPAM.buildHeaderAnalysis(headers));
  }
  parts.push("");
  parts.push("===== EN-TETES BRUTS =====");
  parts.push(headers);
  return parts.join("\r\n");
}

/* ============================ EWS : lecture MIME ============================ */
function getMimeViaEws(itemId) {
  var soap =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"' +
    ' xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"' +
    ' xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">' +
    '<soap:Body>' +
    '<m:GetItem>' +
    '<m:ItemShape>' +
    '<t:BaseShape>IdOnly</t:BaseShape>' +
    '<t:IncludeMimeContent>true</t:IncludeMimeContent>' +
    '</m:ItemShape>' +
    '<m:ItemIds><t:ItemId Id="' + xmlEsc(itemId) + '"/></m:ItemIds>' +
    '</m:GetItem>' +
    '</soap:Body></soap:Envelope>';

  return ewsRequest(soap).then(function (xml) {
    var b64 = between(xml, "<t:MimeContent", "</t:MimeContent>");
    if (!b64) b64 = between(xml, ":MimeContent", ":MimeContent>"); // tolerance prefixe
    if (!b64) throw new Error("MimeContent absent de la reponse EWS");
    // b64 = ' CharacterSet="UTF-8">BASE64'  -> ne garder que ce qui suit '>'
    var gt = b64.indexOf(">");
    var payload = gt >= 0 ? b64.substring(gt + 1) : b64;
    return decodeBase64Mime(payload.replace(/\s+/g, ""));
  });
}

/* ============================ EWS : envoi du rapport ============================ */
function sendReportViaEws(cfg, subject, bodyText, mime, item) {
  var emlName = safeEmlName(item && item.subject);
  var emlB64 = encodeBase64(mime);

  var recips = "<t:ToRecipients>" + mailbox(cfg.abuseTo) + "</t:ToRecipients>";
  if (cfg.abuseCc) recips += "<t:CcRecipients>" + mailbox(cfg.abuseCc) + "</t:CcRecipients>";

  var soap =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"' +
    ' xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"' +
    ' xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">' +
    '<soap:Body>' +
    '<m:CreateItem MessageDisposition="SendAndSaveCopy">' +
    '<m:SavedItemFolderId><t:DistinguishedFolderId Id="sentitems"/></m:SavedItemFolderId>' +
    '<m:Items>' +
    '<t:Message>' +
    '<t:Subject>' + xmlEsc(subject) + '</t:Subject>' +
    '<t:Body BodyType="Text">' + xmlEsc(bodyText) + '</t:Body>' +
    '<t:Attachments>' +
    '<t:FileAttachment>' +
    '<t:Name>' + xmlEsc(emlName) + '</t:Name>' +
    '<t:ContentType>message/rfc822</t:ContentType>' +
    '<t:Content>' + emlB64 + '</t:Content>' +
    '</t:FileAttachment>' +
    '</t:Attachments>' +
    recips +
    '</t:Message>' +
    '</m:Items>' +
    '</m:CreateItem>' +
    '</soap:Body></soap:Envelope>';

  return ewsRequest(soap).then(function (xml) {
    if (xml.indexOf("NoError") < 0 && xml.indexOf("Success") < 0) {
      // Recherche d'un message d'erreur EWS lisible.
      var msg = between(xml, "<m:MessageText>", "</m:MessageText>") ||
                between(xml, ":MessageText>", ":MessageText>");
      throw new Error("EWS CreateItem: " + (msg || "reponse inattendue"));
    }
    return true;
  });
}

/* ------------------------------- Utilitaires ------------------------------- */
function ewsRequest(soap) {
  return new Promise(function (resolve, reject) {
    Office.context.mailbox.makeEwsRequestAsync(soap, function (res) {
      if (res.status === Office.AsyncResultStatus.Succeeded) resolve(res.value);
      else reject(new Error(res.error ? res.error.message : "makeEwsRequestAsync a échoué"));
    });
  });
}

function mailbox(addr) {
  return "<t:Mailbox><t:EmailAddress>" + xmlEsc(addr) + "</t:EmailAddress></t:Mailbox>";
}

function between(s, a, b) {
  var i = s.indexOf(a); if (i < 0) return "";
  var j = s.indexOf(b, i + a.length); if (j < 0) return "";
  return s.substring(i + a.length, j);
}

function xmlEsc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

function safeEmlName(subject) {
  var base = (subject || "message").replace(/[^\w .\-]+/g, "_").substring(0, 60).trim();
  return (base || "message") + ".eml";
}

/* base64 <-> texte, sans dependance (navigateur : atob/btoa avec passage UTF-8). */
function encodeBase64(str) {
  var utf8 = unescape(encodeURIComponent(str));
  if (typeof btoa === "function") return btoa(utf8);
  return Buffer.from(str, "utf8").toString("base64"); // node (tests)
}
function decodeBase64Mime(b64) {
  if (typeof atob === "function") {
    var bin = atob(b64);
    try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
  }
  return Buffer.from(b64, "base64").toString("utf8"); // node (tests)
}

function notify(message, isError) {
  try {
    Office.context.mailbox.item.notificationMessages.replaceAsync("spamStatus", {
      type: isError ? Office.MailboxEnums.ItemNotificationMessageType.ErrorMessage
                    : Office.MailboxEnums.ItemNotificationMessageType.InformationalMessage,
      message: message.substring(0, 150),
      icon: "icon16",
      persistent: !!isError
    });
  } catch (e) { /* hors contexte (tests) */ }
}

function finish(event) { if (event && event.completed) event.completed(); }

function UserError(msg) { this.message = msg; this.isUser = true; }
UserError.prototype = Object.create(Error.prototype);

// Enregistrement de la fonction pour Outlook + export node (tests).
if (typeof Office !== "undefined" && Office.actions && Office.actions.associate) {
  Office.actions.associate("signalerSpam", signalerSpam);
}
if (typeof module !== "undefined" && module.exports) {
  module.exports = { buildSubject: buildSubject, buildBody: buildBody, safeEmlName: safeEmlName, xmlEsc: xmlEsc };
}
