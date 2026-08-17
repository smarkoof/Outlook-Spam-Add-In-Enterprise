/* taskpane.js — volet de repli : declenche le meme flux que le bouton du ruban.
 * Externalise depuis taskpane.html pour permettre une CSP
 * SANS script 'unsafe-inline'. Charge apres commands.js (qui definit signalerSpam).
 */
"use strict";
Office.onReady(function () {
  var go = document.getElementById("go");
  var msg = document.getElementById("msg");
  if (!go) return;
  go.addEventListener("click", function () {
    if (msg) { msg.textContent = "Envoi en cours..."; }
    signalerSpam({ completed: function () {} });
  });
});
