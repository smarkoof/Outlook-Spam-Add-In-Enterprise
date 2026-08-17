> **EN:** [English version](CHANGELOG.md)

# Journal des versions

Historique concis. Les versions suivent le schéma à 4 segments de l'add-in
(`branding.conf` → `VERSION`).

## v1.6.x et suivantes — variante OWA hybride, retours terrain
- **Complément web** (`webaddin/`) pour OWA et le nouvel Outlook : même
  signalement, servi depuis un hôte HTTPS interne ; configuration générée
  depuis `deploy.env` (fail-close sans destinataire).
- Accusé de réception HTML aux couleurs du branding ; surcharge texte simple.
- Neutralisation générique de toutes les adresses livrées (les exemples avec
  `[.]` sont volontairement inopérants ; le script de personnalisation et
  l'add-in les refusent : fail-close par conception).
- Préparation de poste neuf : `01_verification-poste.ps1 -Setup/-Install`
  (inventaire, prérequis, Visual Studio, layout hors-ligne, règle de la
  racine courte).

## v1.6.0.0 — remédiation complète de l'audit (produit + chaîne d'outils)
## v1.5.1 — remédiation de l'audit de suivi (chaîne d'outils)
## v1.5.0.0 — layout hors-ligne fiabilisé, certificat d'entreprise, outillage persistant
- Chaîne MSI signé : `signtool` via NuGet, horodatage RFC 3161.

## v1.1.0.0 — améliorations de sécurité (suite à l'audit)
- Envoi fail-close (aucun destinataire codé), vérification Authenticode des
  binaires téléchargés, fichiers temporaires à nom aléatoire, borne anti-ReDoS
  sur la regex interne, SHA-256 des archives portables.

## v1.0.0.0 — version initiale
- Fork de l'Outlook-Spam-Add-In de milCERT rendu pleinement fonctionnel et
  configurable : `branding.conf` source unique, assistant interactif
  (`05_assistant.ps1`), build en une commande (`04_build.ps1`), interface
  FR/EN, configuration par poste via le registre, déploiement silencieux
  GPO/Intune.
