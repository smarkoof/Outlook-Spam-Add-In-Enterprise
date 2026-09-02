> **EN:** [English version](UPGRADE.md)

# Mettre à jour un déploiement existant

Comment faire passer un parc qui exécute déjà BoutonSPAM vers une nouvelle
release de ce dépôt. Un principe gouverne tout : **une release ne contient
jamais votre configuration**. Mettre à jour, c'est repartir du code neuf, y
remettre vos fichiers, puis reconstruire votre MSI.

## Ce qui vous appartient (jamais fourni par une release)

| Élément | Rôle |
|---|---|
| `branding.conf` | Toute votre configuration — adresses, textes, version, identité MSI, empreinte de certificat. **Le fichier à ne jamais perdre.** |
| `certs/` | Votre certificat de signature de code (jamais versionné, par conception) |
| `installers/` | Binaires hors ligne : runtime VSTO, layout Visual Studio |
| `tools/` | Outils rendus persistants : `signtool/` (signature) et `python/`. **Jamais versionnés** : un poste hors ligne ne peut pas les re-télécharger. |
| `webaddin/deploy/deploy.env` | Configuration du complément web, si vous l'utilisez |

> **Obtenir `tools/`** : sur un poste **connecté**,
> `.\scripts\01_verification-poste.ps1 -CompleteVS` le récupère depuis les
> sources officielles (paquet NuGet Microsoft pour `signtool`, python.org pour
> le Python embarqué). Sur un poste **isolé**, il voyage dans l'archive projet
> produite par `scripts/00_make-archive.sh`. Ces binaires ne sont volontairement
> pas versionnés : ils ne sont pas redistribuables, et alourdiraient
> définitivement l'historique du dépôt.

Tout le reste — `setup/Setup.vdproj` compris — vient de la release et revient
aux valeurs du dépôt à chaque mise à jour. C'est voulu : les valeurs qui
comptent sont réappliquées depuis `branding.conf` par
`scripts/02_customize.sh`.

## Pas à pas

1. **Récupérer la release dans un dossier neuf** (`git clone --branch <tag> …`,
   ou décompresser l'archive de la release à côté du dossier actuel — jamais
   par-dessus).
2. **Remettre vos fichiers** : `branding.conf`, `certs/`, `installers/`,
   `tools/`, et `webaddin/deploy/deploy.env` le cas échéant.
3. **Monter `VERSION`** dans `branding.conf` — strictement supérieure à celle
   déployée (la chaîne refuse une baisse) — et adopter les nouveaux réglages :
   comparez votre fichier à `branding.conf.example` et lisez les notes de la
   release.
4. **Construire** : `.\scripts\05_assistant.ps1` (guidé) ou
   `.\scripts\04_build.ps1`, PowerShell à la racine, Visual Studio fermé.
5. **Poste pilote** (disposant déjà de l'ancienne version) : après
   installation du nouveau MSI, « Programmes et fonctionnalités » liste **une
   seule** entrée, au nouveau numéro ; le bouton fonctionne ; la configuration
   registre machine a survécu (le MSI n'y touche jamais).
6. **Parc** : `msiexec /i "<produit>-<version>.msi" /qn /norestart ALLUSERS=1`
   (ou `deploy/install-silencieux.cmd`, SCCM/Intune). Ne redéployez l'ADMX que
   si le libellé du bouton a changé. Archivez le MSI signé de chaque version
   diffusée, avec ses ProductCode/UpgradeCode.

## Identité MSI — gérée pour vous

Windows n'exécute une **mise à niveau majeure** propre (ancienne version
retirée automatiquement) que si, entre deux versions, le **ProductCode
change** alors que l'**UpgradeCode reste identique**. Depuis la v1.6.2, la
chaîne d'outils garantit les deux :

- **`UPGRADE_CODE`** (dans `branding.conf`) épingle l'identité de famille de
  votre produit. Posez-le **une fois** — à l'adoption, depuis la valeur
  affichée par `REGEN_GUIDS=1` — et n'y touchez plus. Il est réappliqué à
  `setup/Setup.vdproj` à chaque exécution : il survit ainsi aux mises à jour
  du dépôt.
- Le **ProductCode est régénéré automatiquement** à chaque montée de `VERSION`
  (et `REGEN_PRODUCTCODE=1` en force un sans montée de version).

Sans ces deux garanties, l'installation rencontrerait soit l'erreur **1638**
(« Une autre version de ce produit est déjà installée » — même ProductCode),
soit une **installation côte à côte**, deux boutons dans le ruban
(UpgradeCode différent).

> **Dépôts en v1.6.1 ou antérieure** : la chaîne ne gérait pas encore
> l'identité. Avant de construire, éditez `setup/Setup.vdproj` à la main :
> rétablissez *votre* `UpgradeCode`, et remplacez le `ProductCode` par un GUID
> neuf (`[guid]::NewGuid()` sous PowerShell).

## Remplacement du certificat

Le certificat de signature sert deux fois : le manifeste VSTO (à la
compilation — **magasin de certificats Windows uniquement**) et la signature
Authenticode du MSI. Pour le remplacer : importez le nouveau certificat dans
le magasin du poste de build, mettez `CERT_THUMBPRINT` à jour dans
`branding.conf`, reconstruisez — la chaîne recâble les deux. Les signatures
horodatées des paquets déjà déployés restent valides après l'expiration de
l'ancien certificat. Si le nouveau vient d'une autorité différente, vérifiez
que le parc reconnaît cet émetteur avant de diffuser.

## Dépannage

| Symptôme | Cause | Correction |
|---|---|---|
| Erreur **1638** à l'installation | ProductCode inchangé | Monter `VERSION` (ou `REGEN_PRODUCTCODE=1`), reconstruire — ou désinstaller d'abord |
| Deux entrées / deux boutons | UpgradeCode différent de la production | Épingler votre `UPGRADE_CODE`, reconstruire, désinstaller le doublon |
| La chaîne refuse la version | `VERSION` inférieure à celle du projet | Une version ne diminue jamais ; `FORCE_VERSION=1` est réservé aux bases vierges |
| Bouton installé mais refuse d'envoyer | Configuration registre machine absente | Appliquer `resources/RegistryConfig.reg` ou l'ADMX — fail-close par conception |
| « signtool.exe introuvable » | `tools/` non reporté (il n'est pas versionné) | Recopier `tools/` depuis le dossier précédent, ou `-NoSign` pour construire sans signer |
