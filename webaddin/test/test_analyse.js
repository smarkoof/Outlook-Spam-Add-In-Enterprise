/* test_analyse.js — Valide le portage JS contre le MEME corpus que le banc
 * (harness/patches-addin/test_auth_parsing.py) + cas de rapport complet.
 * Execution : node test/test_analyse.js  (code retour 0 = tout passe)
 */
"use strict";
const A = require("../src/analyse.js");

let fails = 0;
function check(name, got, expect) {
  const diffs = {};
  for (const k of Object.keys(expect)) {
    if (got[k] !== expect[k]) diffs[k] = { got: got[k], attendu: expect[k] };
  }
  if (Object.keys(diffs).length) {
    fails++;
    console.log(`[ECART] ${name}`);
    console.log("        ", JSON.stringify(diffs));
  } else {
    console.log(`[OK  ] ${name}`);
  }
}
function contains(name, haystack, needles) {
  const missing = needles.filter((n) => haystack.indexOf(n) < 0);
  if (missing.length) {
    fails++;
    console.log(`[ECART] ${name} — absent(s): ${JSON.stringify(missing)}`);
  } else {
    console.log(`[OK  ] ${name}`);
  }
}

/* ---- Corpus du banc (identique a test_auth_parsing.py) ---- */
check("M365 pass", A.extractAuth(
  "Authentication-Results: spf=pass (sender IP is 40.107.0.1)\r\n" +
  " smtp.mailfrom=contoso.com; dkim=pass (signature was verified)\r\n" +
  " header.d=contoso.com; dmarc=pass action=none header.from=contoso.com;\r\n" +
  " compauth=pass reason=100\r\n"),
  { spf: "pass", dkim: "pass", dmarc: "pass", action: "none", compauth: "pass", dkim_d: "" });

check("Gmail pass", A.extractAuth(
  "DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=example.com; s=20230601;\r\n" +
  " h=from:to:subject; bh=abc; b=xyz\r\n" +
  "Authentication-Results: mx.google.com;\r\n" +
  " dkim=pass header.i=@example.com header.s=20230601 header.b=Ab1;\r\n" +
  " spf=pass (google.com: domain of a@example.com designates 1.2.3.4 as permitted sender) smtp.mailfrom=a@example.com;\r\n" +
  " dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=example.com\r\n"),
  { spf: "pass", dkim: "pass", dmarc: "pass", action: "", compauth: "", dkim_d: "example.com" });

check("Phish fail", A.extractAuth(
  "Authentication-Results: mx.microsoft;\r\n" +
  " spf=fail smtp.mailfrom=evil.example; dkim=none (message not signed);\r\n" +
  " dmarc=fail action=quarantine header.from=bank.example; compauth=fail reason=001\r\n"),
  { spf: "fail", dkim: "none", dmarc: "fail", action: "quarantine", compauth: "fail", dkim_d: "" });

check("Received-SPF fallback", A.extractAuth(
  "Received-SPF: Pass (protection.outlook.com: domain of x.example designates 1.2.3.4 as permitted sender)\r\n" +
  "Authentication-Results: mx.microsoft; dkim=pass header.d=x.example; dmarc=pass header.from=x.example\r\n"),
  { spf: "Pass", dkim: "pass", dmarc: "pass", action: "", compauth: "", dkim_d: "" });

check("Multi Authentication-Results", A.extractAuth(
  "ARC-Authentication-Results: i=1; mx.google.com; dkim=fail; spf=softfail; dmarc=fail\r\n" +
  "Authentication-Results: mx.microsoft; spf=pass smtp.mailfrom=ok.example;\r\n" +
  " dkim=pass header.d=ok.example; dmarc=pass action=none header.from=ok.example\r\n"),
  { spf: "pass", dkim: "pass", dmarc: "pass", action: "none", compauth: "", dkim_d: "" });

check("softfail/temperror", A.extractAuth(
  "Authentication-Results: mx; spf=softfail smtp.mailfrom=a.example;\r\n" +
  " dkim=temperror; dmarc=none header.from=a.example\r\n"),
  { spf: "softfail", dkim: "temperror", dmarc: "none", action: "", compauth: "", dkim_d: "" });

check("EN-TETES VIDES (bug propriete)", A.extractAuth(""),
  { spf: "", dkim: "", dmarc: "", action: "", compauth: "", dkim_d: "" });

/* ---- Rapport complet : cas phishing riche ---- */
const PHISH =
  "Received: from evil-relay.example ([203.0.113.66]) by mx.interne.example with ESMTP; Mon, 20 Jul 2026 08:00:00 +0200\r\n" +
  "Received: from zombie.botnet.example (unknown [198.51.100.9] helo=zombie.botnet.example) by evil-relay.example; Mon, 20 Jul 2026 07:59:00 +0200\r\n" +
  "Authentication-Results: mx.interne.example; spf=fail smtp.mailfrom=evil.example;\r\n" +
  " dkim=none (message not signed); dmarc=fail action=quarantine header.from=banque-securite.example; compauth=fail reason=001\r\n" +
  "X-Forefront-Antispam-Report: CIP:203.0.113.66;CTRY:XX;SFV:SPM;SCL:8;CAT:HPHSH;SFTY:9.19\r\n" +
  "X-Spam-Status: Yes, score=9.3 required=5.0\r\n" +
  "From: \"Votre Banque\" <alerte@banque-securite.example>\r\n" +
  "Reply-To: contact@recuperation-compte.example\r\n" +
  "Return-Path: <bounce@evil.example>\r\n" +
  "Message-ID: <20260720075900.ABCDEF@evil.example>\r\n" +
  "Date: Mon, 20 Jul 2026 07:59:00 +0200\r\n" +
  "X-Mailer: MassMail 4.2\r\n" +
  "Subject: Verifiez votre compte\r\n";
const rpt = A.buildHeaderAnalysis(PHISH);
contains("Rapport phishing : verdicts", rpt, [
  "SPF   : fail",
  "DKIM  : none",
  "DMARC : fail   action=quarantine",
  "CompAuth (Microsoft) : fail   reason=001"
]);
contains("Rapport phishing : usurpation detectee", rpt, [
  "Return-Path      : <bounce@evil.example>   <-- NON ALIGNE avec From (banque-securite.example)",
  "Reply-To         : contact@recuperation-compte.example   <-- DIFFERENT du From"
]);
contains("Rapport phishing : routage defange", rpt, [
  "IP d'origine     : 198[.]51[.]100[.]9",
  "HELO/EHLO        : zombie.botnet.example",
  "Sauts (Received) : 2"
]);
contains("Rapport phishing : scores", rpt, [
  "SCL (0..9, +eleve = +suspect) : 8",
  "Verdict Forefront (SFV)       : SPM (marque SPAM par le filtre)",
  "Categorie (CAT)               : HPHSH (hameconnage haute confiance)",
  "Alerte securite (SFTY)        : 9.19 (hameconnage detecte)",
  "X-Spam score                  : 9.3"
]);
contains("Rapport phishing : message", rpt, [
  "Message-ID       : <20260720075900.ABCDEF@evil.example>   <-- domaine evil.example != From",
  "Client emetteur  : MassMail 4.2"
]);

/* ---- Rapport complet : message legitime interne (rien a signaler) ---- */
const CLEAN =
  "Received: from srv1.interne.example ([10.1.2.3]) by mx.interne.example; Mon, 20 Jul 2026 09:00:00 +0200\r\n" +
  "Authentication-Results: mx.interne.example; spf=pass smtp.mailfrom=interne.example;\r\n" +
  " dkim=pass header.d=interne.example; dmarc=pass action=none header.from=interne.example\r\n" +
  "DKIM-Signature: v=1; a=rsa-sha256; d=interne.example; s=sel1; h=from:to; bh=x; b=y\r\n" +
  "From: RH <rh@interne.example>\r\n" +
  "Return-Path: <rh@interne.example>\r\n" +
  "Message-ID: <abc@interne.example>\r\n";
const rpt2 = A.buildHeaderAnalysis(CLEAN);
contains("Rapport sain : alignements coherents", rpt2, [
  "SPF   : pass",
  "Alignement DKIM  : d=interne.example   (coherent)",
  "(aucun en-tete de score reconnu)"
]);
if (rpt2.indexOf("NON ALIGNE") >= 0 || rpt2.indexOf("DIFFERENT du From") >= 0) {
  fails++; console.log("[ECART] Rapport sain : faux positif d'usurpation");
} else console.log("[OK  ] Rapport sain : aucun faux positif");

/* ---- En-tetes vides ---- */
if (A.buildHeaderAnalysis("") !== "(en-tetes indisponibles - message non SMTP ou droits insuffisants)") {
  fails++; console.log("[ECART] Cas vide : message attendu different");
} else console.log("[OK  ] Cas vide : message d'indisponibilite");

/* ---- headersFromMime ---- */
const mime = "From: a@b.c\r\nSubject: t\r\n\r\ncorps du message\r\n";
if (A.headersFromMime(mime) !== "From: a@b.c\r\nSubject: t") {
  fails++; console.log("[ECART] headersFromMime");
} else console.log("[OK  ] headersFromMime");

console.log("");
if (fails) { console.log("RESULTAT : " + fails + " ECART(S)"); process.exit(1); }
console.log("RESULTAT : PORTAGE CONFORME — tous les cas passent");
