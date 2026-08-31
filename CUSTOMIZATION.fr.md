> **EN:** [English version](CUSTOMIZATION.md)

# BoutonSPAM — Fiche de personnalisation entreprise

Où se trouve chaque champ à adapter à votre organisation, pour les **deux
déclinaisons** du bouton. Principe général : on n'édite **jamais** un fichier
`.example` (ce sont les gabarits) ni un fichier généré — on édite la copie de
travail, puis on laisse les scripts propager.

---

## 1. Client lourd Outlook (VSTO) — la source unique : `branding.conf`

**Fichier : `branding.conf` — racine du projet.**
Tout le rebranding passe par lui, puis `./scripts/02_customize.sh` (Git Bash)
l'applique partout — ou l'assistant `.\scripts\05_assistant.ps1` (PowerShell),
qui gère aussi l'incrément de version et le build du MSI.

| Champ(s) | Rôle — quoi mettre |
|---|---|
| `PRODUCT_NAME` | Nom du produit (gestionnaire de compléments, installeur, ARP, nom des DLL/.vsto) |
| `COMPANY_NAME` | Votre entité — affichée comme « Éditeur » du logiciel |
| `PRODUCT_DESCRIPTION` | Description de l'assembly (peut rester telle quelle) |
| `SUPPORT_URL` | Lien support (ARP). **http(s) uniquement — jamais `mailto:`** |
| `COPYRIGHT` | Votre entité + année |
| `VERSION` | 4 segments ; ne **jamais** diminuer ; à incrémenter à chaque build |
| `INSTALL_FOLDER` | Sous-dossier sous `%ProgramFiles%` |
| `MSI_BASENAME` | Nom de base du MSI (sans espace) |
| `PROJECT_SLUG` | Nom du dossier/projet côté dépôt (dev uniquement) |
| `REGISTRY_CONFIG_KEY` | Clé registre de la config par poste — à ne changer qu'en connaissance de cause |
| `REPORT_TO` | **La boîte abuse destinataire des signalements** (plusieurs adresses possibles, séparées par `;`) |
| `REPORT_CC` | Copie du rapport (`""` = pas de Cc) |
| `REGEX_INTERNAL` | Regex reconnaissant vos expéditeurs **internes** (avertissement avant signalement) — voir « Écrire `REGEX_INTERNAL` » ci-dessous |
| `UI_BUTTON_FR` / `_EN` | Libellé du bouton du ruban (2 à 4 mots, verbe d'action en tête) |
| `UI_GROUP_FR` / `_EN` | Nom du groupe dans le ruban |
| `UI_BUTTON_TIP_FR` / `_EN` | Description courte au survol |
| `UI_BUTTON_SUPERTIP_FR` / `_EN` | Grande info-bulle d'aide |
| `BUTTON_ICON` | Icône du bouton (ruban **et** menus contextuels) — icône fournie par Office (`imageMso`) : `PermissionRestrict` (défaut), `Risks`, `SourceControlRun`, `FilePermissionView`, `CancelRequest`. Rien à livrer, suit le thème d'Outlook. Toute autre valeur est refusée par `02_customize.sh` |
| `UI_CONFIRM_TITLE_FR` / `_EN` | Titre de la boîte de confirmation |
| `UI_REPORT_BODY_FR` / `_EN` | Phrase d'introduction du rapport (vue par vos analystes) |
| `UI_ACK_SUBJECT_FR` / `_EN` | Objet de l'accusé de réception automatique |
| `UI_ACK_BODY_FR/_EN`, `UI_ACK_BODY_MORE_FR/_EN` | Surcharge **texte simple** du corps de l'accusé (`""` = version HTML de `Config.vb` conservée) |
| `REPORT_SUBJECT_PREFIX`, `REPORT_SUBJECT_PREFIX_ERROR` | Préfixes d'objet `[SPAM]` / `[SPAM-ERREUR]` (règles de tri de la boîte abuse) |
| `CERT_THUMBPRINT`, `TIMESTAMP_URL` | Signature de code (empreinte du certificat, horodatage RFC 3161) |
| `UPGRADE_CODE` | Identité de FAMILLE du produit (GUID) — posée une fois, jamais changée ; réappliquée au projet d'installation à chaque exécution, elle survit aux mises à jour du dépôt |
| `REGEN_PRODUCTCODE` | Le ProductCode est régénéré automatiquement à chaque montée de version (mise à niveau majeure Windows) ; `1` en force une sans montée de version |
| `REGEN_GUIDS` | `1` une seule fois à l'adoption initiale ou lors d'un rebranding complet — régénère TOUTE l'identité, UpgradeCode compris ; reportez-le ensuite dans `UPGRADE_CODE` et remettez `0` |

Règles d'écriture (rappel de l'en-tête du fichier) : pas de guillemets doubles
`"` ni de chevrons `< >` dans les valeurs, pas de retour à la ligne ; adresses
**sans** crochets — les exemples `[.]` sont volontairement inopérants
(`02_customize.sh` les refuse, et l'add-in refuse d'envoyer : fail-close).

### Écrire `REGEX_INTERNAL`

Avant l'envoi d'un signalement, l'add-in compare l'adresse de l'expéditeur à ce
motif : si elle correspond, il avertit l'utilisateur (« ce message semble venir
de l'interne, le signaler quand même ? ») — cela évite de rapporter par erreur
des e-mails légitimes de collègues.

Briques : `\.` = point littéral, `$` = fin d'adresse, `.*` = n'importe quels
caractères, `|` = OU (on couvre le domaine exact **et** ses sous-domaines).
Partir de la partie **après le `@`** de vos e-mails (pas de l'URL du site
web) et échapper chaque point en `\.` :

```
Domaine simple     : (@mairie-xyz\.fr$|@.*\.mairie-xyz\.fr$)
Domaine composé    : (@ministere-xyz\.gouv\.fr$|@.*\.ministere-xyz\.gouv\.fr$)
Plusieurs domaines : (@a\.gouv\.fr$|@.*\.a\.gouv\.fr$|@b\.gouv\.fr$|@.*\.b\.gouv\.fr$)
```

Astuce Exchange : le préfixe `^/O=…/OU=…` (voir le projet d'origine) capte
aussi les adresses « internes Exchange » en plus des adresses SMTP `@domaine`.

### Compléments du client lourd (hors branding.conf)

**`OutlookSpamAddin/Config.vb`** — zone « **TEXTES VUS PAR L'UTILISATEUR** »
(à partir de la ligne 683) : corps détaillés des dialogues (confirmation,
erreurs, garde-fous) et **corps HTML de l'accusé de réception** —
`ackBodyOneFR` / `ackBodyMoreFR` lignes 764–765 (EN : 734–735), où figure
« MonOrganisationSSI » à remplacer. Modification = recompiler (nouvelle
`VERSION`). La correspondance champ ↔ constante est documentée en tête de zone
(lignes 683–708).

**`OutlookSpamAddin/Ribbon.vb`** — ligne 403 : regex du **TLD national**
`(\.fr$)` (fait passer le signalement en priorité haute quand l'expéditeur est
sur ce TLD). Codée en dur car elle change rarement.

**`resources/RegistryConfig.reg`** (tenu à jour par `02_customize.sh`) — la
surcharge **par poste, sans recompiler ni redéployer**, sous
`HKLM\SOFTWARE\OutlookSpamAddin` (valeurs lues dans `Config.vb` lignes
520–528) :

| Valeur registre | Rôle |
|---|---|
| `To` / `Cc` | Destinataire / copie du rapport (priment sur les défauts compilés) |
| `FilterInternalMessages` | `1` = avertir si l'expéditeur semble interne |
| `Regex` | La regex interne (même syntaxe que `REGEX_INTERNAL`) |
| `SendAcknowledgment` | `1` = accusé de réception automatique à l'utilisateur |
| `IncludeTechnicalReport` | `1` = bloc « ANALYSE TECHNIQUE » (SPF/DKIM/DMARC…) dans le rapport |

---

## 2. Bouton web (OWA / nouveau Outlook) — dossier `webaddin/`

**`webaddin/deploy/deploy.env`** (à créer : `cp deploy.env.example deploy.env`,
puis `chmod 600`). C'est l'équivalent du `branding.conf` pour le volet web ;
`./apply-config.sh` génère ensuite `manifest.xml` et `config.json` dans
`deploy/out/`, sans toucher au système :

| Variable | Rôle |
|---|---|
| `ABUSE_TO` | **Obligatoire** — la boîte abuse (vide = génération refusée, fail-close) |
| `ABUSE_CC`, `REPORT_SUBJECT_PREFIX` | Copie, préfixe d'objet (défaut `[SPAM]`) |
| `ADDIN_FQDN` | Hôte HTTPS interne qui sert le complément |
| `ADDIN_ID` | GUID du complément — à **figer** après la première génération |

**`webaddin/config.example.json`** → servi comme `src/config.json` (équivalent
des clés registre du VSTO ; `abuseTo`, `abuseCc` et `reportSubjectPrefix` y
sont injectés depuis `deploy.env`) : `includeTechnicalReport`, `attachEml`,
`ackToUser`, `ackSubject`, `ackBody`. Fail-close si `abuseTo` est vide.

**`webaddin/manifest.xml`** — les textes visibles dans OWA, à éditer
directement : `ProviderName` (l. 24), `DisplayName` (l. 26), `Description`
(l. 27), icônes (l. 28–29 et 115–120), `SupportUrl` (l. 30), libellés du groupe
et du bouton + info-bulle (l. 126–130). Le GUID (`11111111-…`) et le domaine
`addin.interne.example` sont remplacés automatiquement par `apply-config.sh` —
ne pas les retoucher à la main.

Détails annexes : phrase d'introduction du rapport web dans
`webaddin/src/commands.js` (l. 73), message « Envoi en cours... » dans
`webaddin/src/taskpane.js` (l. 11).

---

## 3. L'essentiel en trois gestes

1. **Adresses et filtre interne** : `REPORT_TO` / `REPORT_CC` /
   `REGEX_INTERNAL` dans `branding.conf` (et `deploy.env` pour le volet web) —
   c'est le minimum vital, tout le reste a des défauts corrects.
2. **Identité et textes** : `branding.conf` sections « Identité » et « Textes
   utilisateur » ; les corps de dialogues fins dans `Config.vb` (zone l. 683+).
3. **Appliquer** : `./scripts/02_customize.sh` puis build (`05_assistant.ps1`
   recommandé) côté VSTO ; `cp deploy.env.example deploy.env` + édition +
   `./apply-config.sh` côté web.

Les garde-fous de sécurité (fail-close, exemples inopérants, droits sur
`deploy.env`) sont résumés dans `CHANGELOG.fr.md` et dans le `README.fr.md`.
