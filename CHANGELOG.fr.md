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
- **Script de migration livré** : `scripts/92_migrate-release.ps1` reprend votre
  configuration, vos certificats et votre outillage dans le dossier d'une nouvelle
  release, épingle l'`UPGRADE_CODE` de votre production et monte la version, puis
  vérifie le résultat. Mode `-Simulation` sans écriture.
- **Renommer le produit ne casse plus le build** : `04_build.ps1` lit le nom de
  l'assembly dans le `.vbproj` (écrit depuis `PRODUCT_NAME`) au lieu de le coder
  en dur. Construire des variantes — pour comparer plusieurs icônes, par exemple —
  fonctionne désormais sans retoucher la chaîne.
- Prérequis de **signature contrôlé avant la compilation** : `signtool`
  manquant est signalé en quelques secondes, et non après tout le build.
  `tools/` (signtool, python) n'est pas versionné : il se reporte d'un
  dossier de travail à l'autre, ou s'obtient via `01_verification-poste.ps1`
  (poste connecté) ou l'archive projet `00_make-archive.sh` (poste isolé).
- Identité MSI automatisée : `UPGRADE_CODE` épinglé dans `branding.conf`,
  ProductCode régénéré à chaque montée de version (mises à niveau majeures
  Windows propres) — guide de mise à jour dans `UPGRADE.fr.md`.

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
