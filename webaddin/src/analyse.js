/* analyse.js — Portage JavaScript FIDELE de la logique d'analyse d'en-tetes du
 * BoutonSPAM VSTO (Config.vb : UnfoldHeaders / HeaderValue(s) / Rx /
 * BuildHeaderAnalysis + aides). La sortie texte est IDENTIQUE au bloc
 * "ANALYSE TECHNIQUE" du client lourd, pour que les analystes (et leurs outils)
 * recoivent le meme rapport quel que soit le canal (Outlook classique ou OWA).
 *
 * Valide par test/test_analyse.js sur le corpus du banc (test_auth_parsing.py).
 * Aucune dependance : utilisable dans le navigateur (window.AnalyseSPAM) et
 * sous node (module.exports).
 */
(function (global) {
  "use strict";

  function unfoldHeaders(raw) {
    if (!raw) return "";
    return String(raw).replace(/\r?\n[ \t]+/g, " ");
  }

  function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function headerValues(unfolded, name) {
    var res = [];
    if (!unfolded) return res;
    var re = new RegExp("^" + escapeRe(name) + "\\s*:\\s*(.*)$", "gim");
    var m;
    while ((m = re.exec(unfolded)) !== null) {
      res.push(m[1].trim());
      if (m.index === re.lastIndex) re.lastIndex++;
    }
    return res;
  }

  function headerValue(unfolded, name) {
    var v = headerValues(unfolded, name);
    return v.length ? v[0] : "";
  }

  function rx(input, pattern) {
    if (!input) return "";
    var m = new RegExp(pattern, "i").exec(input);
    return m && m[1] !== undefined ? m[1].trim() : "";
  }

  function domainOf(addr) {
    if (!addr) return "";
    var at = addr.lastIndexOf("@");
    if (at >= 0 && at < addr.length - 1) {
      return addr.substring(at + 1).replace(/[>\)\s;,]+$/g, "");
    }
    return "";
  }

  function nz(s) { return s ? s : "(absent)"; }

  function truncStr(s, n) {
    if (!s) return "";
    return s.length <= n ? s : s.substring(0, n) + "...";
  }

  function defang(s) {
    if (!s) return "";
    return s.split("https").join("hxxps").split("http").join("hxxp").split(".").join("[.]");
  }

  function endsWithCI(s, suffix) {
    return s.toLowerCase().endsWith(suffix.toLowerCase());
  }

  function describeSFV(c) {
    switch (c.toUpperCase()) {
      case "SPM": return " (marque SPAM par le filtre)";
      case "NSPM": return " (marque non-spam)";
      case "BLK": return " (bloque - liste noire)";
      case "SKS": return " (marque spam par une regle)";
      case "SKN": return " (marque legitime par une regle)";
      case "SKB": return " (bloque par une regle)";
      default: return "";
    }
  }

  function describeCAT(c) {
    switch (c.toUpperCase()) {
      case "PHSH": return " (hameconnage)";
      case "HPHISH": case "HPHSH": return " (hameconnage haute confiance)";
      case "SPM": return " (spam)";
      case "HSPM": return " (spam haute confiance)";
      case "MALW": return " (logiciel malveillant)";
      case "SPOOF": return " (usurpation)";
      case "BULK": return " (courrier de masse)";
      case "GIMP": return " (graymail)";
      default: return "";
    }
  }

  function describeSFTY(c) {
    if (c.indexOf("9.19") === 0) return " (hameconnage detecte)";
    if (c.indexOf("9.11") === 0) return " (usurpation intra-organisation)";
    if (c.indexOf("9.20") === 0) return " (usurpation de domaine)";
    if (c.indexOf("9.21") === 0) return " (usurpation - domaine externe)";
    if (c.indexOf("9.25") === 0) return " (premiere prise de contact)";
    return "";
  }

  /* Equivalent du extract_auth du banc — utile aux tests et reutilise ci-dessous. */
  function extractAuth(rawHeaders) {
    var h = unfoldHeaders(rawHeaders);
    var authAll = headerValues(h, "Authentication-Results").join("  |  ");
    var spf = rx(authAll, "spf=([A-Za-z]+)");
    if (!spf) spf = rx(headerValue(h, "Received-SPF"), "^\\s*([A-Za-z]+)");
    var dkimSig = headerValue(h, "DKIM-Signature");
    return {
      spf: spf,
      dkim: rx(authAll, "dkim=([A-Za-z]+)"),
      dmarc: rx(authAll, "dmarc=([A-Za-z]+)"),
      action: rx(authAll, "action=([A-Za-z]+)"),
      compauth: rx(authAll, "compauth=([A-Za-z]+)"),
      dkim_d: rx(dkimSig, "[;\\s]d=([^;\\s]+)")
    };
  }

  /* Portage ligne a ligne de Config.BuildHeaderAnalysis (Config.vb:331). */
  function buildHeaderAnalysis(rawHeaders) {
    var out = [];
    function L(s) { out.push(s); }
    try {
      if (!rawHeaders) return "(en-tetes indisponibles - message non SMTP ou droits insuffisants)";
      if (rawHeaders.length > 204800) rawHeaders = rawHeaders.substring(0, 204800);
      var h = unfoldHeaders(rawHeaders);

      var authAll = headerValues(h, "Authentication-Results").join("  |  ");
      var spf = rx(authAll, "spf=([A-Za-z]+)");
      if (!spf) spf = rx(headerValue(h, "Received-SPF"), "^\\s*([A-Za-z]+)");
      var dkim = rx(authAll, "dkim=([A-Za-z]+)");
      var dmarc = rx(authAll, "dmarc=([A-Za-z]+)");
      var dmarcAction = rx(authAll, "action=([A-Za-z]+)");
      var compauth = rx(authAll, "compauth=([A-Za-z]+)");
      var compReason = rx(authAll, "reason=(\\d+)");
      var dkimSig = headerValue(h, "DKIM-Signature");
      var dkimD = rx(dkimSig, "[;\\s]d=([^;\\s]+)");
      var dkimS = rx(dkimSig, "[;\\s]s=([^;\\s]+)");
      var arc = rx(headerValues(h, "ARC-Authentication-Results").join(" "), "arc=([A-Za-z]+)");

      var fromH = headerValue(h, "From");
      var replyTo = headerValue(h, "Reply-To");
      var returnPath = headerValue(h, "Return-Path");
      var fromAddr = rx(fromH, "<([^>]+)>");
      if (!fromAddr) fromAddr = fromH;
      var fromDom = domainOf(fromAddr);
      var rpDom = domainOf(returnPath);
      var replyDom = domainOf(rx(replyTo, "<([^>]+)>"));
      if (!replyDom) replyDom = domainOf(replyTo);

      L("===== ANALYSE TECHNIQUE (automatique - aide analyste) =====");
      L("");
      L("[ Authentification ]  verdict de la PASSERELLE (non recalcule sur le poste)");
      L("  SPF   : " + nz(spf));
      L("  DKIM  : " + nz(dkim) + (dkimD ? "   signe d=" + dkimD + (dkimS ? " s=" + dkimS : "") : ""));
      L("  DMARC : " + nz(dmarc) + (dmarcAction ? "   action=" + dmarcAction : ""));
      if (arc) L("  ARC   : " + arc + "   (message transfere / liste)");
      if (compauth) L("  CompAuth (Microsoft) : " + compauth + (compReason ? "   reason=" + compReason : ""));

      L("");
      L("[ Expediteur & indices d'usurpation ]");
      L("  From (affiche)   : " + nz(truncStr(fromH, 200)));
      if (returnPath) {
        var rpFlag = "";
        if (rpDom && fromDom && !endsWithCI(fromDom, rpDom) && !endsWithCI(rpDom, fromDom))
          rpFlag = "   <-- NON ALIGNE avec From (" + fromDom + ")";
        L("  Return-Path      : " + truncStr(returnPath, 200) + rpFlag);
      }
      if (replyTo) {
        var rtFlag = "";
        if (replyDom && fromDom && replyDom.toLowerCase() !== fromDom.toLowerCase())
          rtFlag = "   <-- DIFFERENT du From";
        L("  Reply-To         : " + truncStr(replyTo, 200) + rtFlag);
      }
      if (dkimD) {
        var dkFlag = "   (coherent)";
        if (fromDom && !endsWithCI(dkimD, fromDom) && !endsWithCI(fromDom, dkimD))
          dkFlag = "   <-- ne correspond pas a From (" + fromDom + ")";
        L("  Alignement DKIM  : d=" + dkimD + dkFlag);
      }

      var recvs = headerValues(h, "Received");
      var origin = recvs.length > 0 ? recvs[recvs.length - 1] : "";
      var originIp = rx(origin, "[\\[\\(](\\d{1,3}(?:\\.\\d{1,3}){3})[\\]\\)]");
      if (!originIp) originIp = rx(headerValue(h, "X-Originating-IP"), "(\\d{1,3}(?:\\.\\d{1,3}){3})");
      if (!originIp) originIp = rx(headerValue(h, "X-Sender-IP"), "(\\d{1,3}(?:\\.\\d{1,3}){3})");
      var helo = rx(origin, "helo=([^\\s\\)]+)");
      L("");
      L("[ Origine & routage ]");
      L("  IP d'origine     : " + defang(nz(originIp)));
      if (helo) L("  HELO/EHLO        : " + helo);
      L("  Sauts (Received) : " + String(recvs.length));
      if (origin) L("  1er relais       : " + truncStr(origin, 250));

      var ff = headerValue(h, "X-Forefront-Antispam-Report");
      var scl = headerValue(h, "X-MS-Exchange-Organization-SCL");
      if (!scl) scl = rx(ff, "SCL:(-?\\d+)");
      var bcl = rx(headerValue(h, "X-Microsoft-Antispam"), "BCL:(\\d+)");
      var sfv = rx(ff, "SFV:([A-Za-z]+)");
      var cat = rx(ff, "CAT:([A-Za-z]+)");
      var sfty = rx(ff, "SFTY:([0-9.]+)");
      var spamScore = rx(headerValue(h, "X-Spam-Status"), "score=([\\d\\.\\-]+)");
      L("");
      L("[ Scores anti-spam / anti-hameconnage ]");
      var anyScore = false;
      if (scl) { L("  SCL (0..9, +eleve = +suspect) : " + scl); anyScore = true; }
      if (bcl) { L("  BCL (0..9, courrier de masse) : " + bcl); anyScore = true; }
      if (sfv) { L("  Verdict Forefront (SFV)       : " + sfv + describeSFV(sfv)); anyScore = true; }
      if (cat) { L("  Categorie (CAT)               : " + cat + describeCAT(cat)); anyScore = true; }
      if (sfty) { L("  Alerte securite (SFTY)        : " + sfty + describeSFTY(sfty)); anyScore = true; }
      if (spamScore) { L("  X-Spam score                  : " + spamScore); anyScore = true; }
      if (!anyScore) L("  (aucun en-tete de score reconnu)");

      var msgId = headerValue(h, "Message-ID");
      /* NB : le VSTO d'origine fait DomainOf(Rx(...)) — or Rx extrait DEJA le
         domaine, donc DomainOf (qui cherche un @) renvoie toujours "" et le
         drapeau "domaine != From" ne s'affiche JAMAIS. Bug latent corrige ici ;
         micro-correctif a reporter cote Config.vb/Ribbon.vb un jour. */
      var midDom = rx(msgId, "@([^>\\s]+)");
      var dateH = headerValue(h, "Date");
      var xmailer = headerValue(h, "X-Mailer");
      if (!xmailer) xmailer = headerValue(h, "User-Agent");
      var clang = headerValue(h, "Content-Language");
      L("");
      L("[ Message ]");
      if (msgId) {
        var midFlag = "";
        if (midDom && fromDom && !endsWithCI(midDom, fromDom)) midFlag = "   <-- domaine " + midDom + " != From";
        L("  Message-ID       : " + truncStr(msgId, 200) + midFlag);
      }
      if (dateH) L("  Date (en-tete)   : " + dateH);
      if (xmailer) L("  Client emetteur  : " + truncStr(xmailer, 160));
      if (clang) L("  Langue declaree  : " + clang);
    } catch (e) {
      L("(analyse des en-tetes interrompue : " + (e && e.message ? e.message : String(e)) + ")");
    }
    return out.join("\r\n") + "\r\n";
  }

  /* En-tetes bruts = tout ce qui precede la premiere ligne vide du MIME. */
  function headersFromMime(mime) {
    if (!mime) return "";
    var ix = mime.indexOf("\r\n\r\n");
    if (ix < 0) ix = mime.indexOf("\n\n");
    return ix >= 0 ? mime.substring(0, ix) : mime;
  }

  var api = {
    unfoldHeaders: unfoldHeaders,
    headerValues: headerValues,
    headerValue: headerValue,
    rx: rx,
    domainOf: domainOf,
    nz: nz,
    truncStr: truncStr,
    defang: defang,
    extractAuth: extractAuth,
    buildHeaderAnalysis: buildHeaderAnalysis,
    headersFromMime: headersFromMime
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else global.AnalyseSPAM = api;
})(typeof window !== "undefined" ? window : this);
