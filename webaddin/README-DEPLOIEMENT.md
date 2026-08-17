# BoutonSPAM WEB — complément Outlook web (OWA / nouveau Outlook)

*Volet **web** de la stratégie hybride. Le client lourd garde son bouton VSTO ;
ce complément apporte le même bouton dans OWA et le « nouveau Outlook », en
alimentant **la même boîte abuse**.*

Cible validée : **Outlook 2108** (client lourd, déjà couvert par le VSTO — le web
complète OWA) et **Exchange Server 15.2.2562.42 = Subscription Edition (SE)**,
on-premises.

## 1. Ce que fait ce complément (parité avec le bouton du client lourd)

Au clic sur « Rapporter un Spam à Abuse » (ruban du message ouvert) :

1. lit le message via **EWS `GetItem` + `IncludeMimeContent`** (un seul appel :
   le MIME contient les en-têtes **et** le message complet) ;
2. construit le **même rapport** que le VSTO — bloc « ANALYSE TECHNIQUE »
   (SPF / DKIM / DMARC, routage, scores) + en-têtes bruts — via `src/analyse.js`,
   portage fidèle et **testé** de `Config.vb` (16/16 sur le corpus du banc) ;
3. envoie à la boîte abuse via **EWS `CreateItem`** (message neuf, objet
   `[SPAM] [score] - '...'`, **message d'origine joint en `.eml`**) ;
4. **fail-close** : si la configuration est injoignable ou l'adresse abuse vide,
   le bouton **refuse** d'envoyer et le signale à l'utilisateur.

> **Aval inchangé** : le mail reçu par la boîte abuse porte le message d'origine
> en pièce jointe `.eml`, le format qu'attendent les chaînes de traitement des
> signalements. Rien à modifier côté analyse.

## 2. Pourquoi ces choix techniques (contrainte on-prem)

Exchange **SE on-prem** plafonne le jeu d'API Office.js à **Mailbox 1.5**. On
n'utilise donc **pas** `getAllInternetHeadersAsync` (jeu 1.8, Exchange Online).
`makeEwsRequestAsync` existe **depuis le jeu 1.1** et couvre à la fois la lecture
du MIME et l'envoi — d'où une dépendance minimale et robuste. Le manifeste
déclare `Requirements` **1.1** (socle) et `VersionOverrides` **1.5** (le bouton).

Attention au plafond **client × serveur** : Outlook 2108 monte jusqu'à 1.8, mais
c'est **le serveur (1.5) qui plafonne**. Le complément a été écrit pour 1.5 max.

## 3. Prérequis à vérifier avec l'équipe messagerie

- [ ] **EWS activé et joignable** depuis OWA ; `makeEwsRequestAsync` autorisé
      (pas de blocage par `Get-OrganizationConfig` / stratégie EWS).
- [ ] Droit de déployer un **complément d'organisation** (`New-App -OrganizationApp`).
- [ ] Un **hôte HTTPS interne de confiance** (certificat reconnu des postes) pour
      servir le manifeste, `src/`, `assets/`, `config.json`.
- [ ] La **boîte abuse** accepte les messages envoyés par les utilisateurs
      (mêmes règles de flux que pour le VSTO).
- [ ] OWA réellement **utilisé** par la population visée.

## 4. Préparer les fichiers

1. **Générer un GUID** stable et le mettre dans `manifest.xml` → `<Id>` :
   `PowerShell : [guid]::NewGuid()`
2. **Remplacer** partout `https://addin.interne.example` par l'URL de votre hôte
   HTTPS interne (chercher `A-REMPLACER` dans `manifest.xml`).
3. **Configurer** : copier `config.example.json` en `src/config.json` et
   renseigner **`abuseTo`** (obligatoire), éventuellement `abuseCc`. Laisser
   `abuseTo` vide = bouton volontairement inopérant (fail-close).
4. **Publier** sur l'hôte HTTPS interne, en respectant l'arborescence :
   ```
   /manifest.xml          (sert au déploiement, pas forcément exposé)
   /assets/icone-16..128.png
   /src/commands.html  /src/commands.js  /src/analyse.js
   /src/taskpane.html  /src/config.json
   ```
   Servir `office.js` : soit le CDN Microsoft (déjà référencé), soit une copie
   interne si les postes n'ont pas Internet — dans ce cas, adapter le `<script src>`.

> **Iframe OWA** : les pages du complément sont chargées **dans une iframe**
> par OWA — ne posez pas d'en-tête `X-Frame-Options` sur cet hébergement, et
> si votre hébergement ajoute une CSP, autorisez l'origine de votre OWA dans
> `frame-ancestors`.

Raccourci : `deploy/apply-config.sh` génère `manifest.xml` et `src/config.json`
personnalisés depuis `deploy/deploy.env` (GUID auto, fail-close si boîte vide).

## 5. Déployer (Exchange Management Shell, on-prem)

```powershell
# Depuis un manifeste hébergé en HTTPS interne :
New-App -OrganizationApp -Url "https://addin.interne.example/manifest.xml" `
        -DefaultStateForUser Enabled

# …ou depuis le fichier :
New-App -OrganizationApp -FileData ([System.IO.File]::ReadAllBytes("C:\chemin\manifest.xml")) `
        -DefaultStateForUser Enabled
```

Alternative graphique : **EAC → Organisation → Compléments → + → depuis un
fichier / une URL**. Pour un pilote, `-DefaultStateForUser Disabled` puis activer
pour un groupe restreint.

Mise à jour ultérieure = mettre à jour les fichiers sur l'hôte web (et
`Set-App`/ré-import si le **manifeste** change). Pas de MSI, pas de GPO.

## 6. Tester

- **Hors ligne, maintenant** : `node test/test_analyse.js` (le cœur d'analyse ;
  16/16 attendus).
- **Pilote** : activer pour l'équipe SSI, signaler quelques messages depuis OWA,
  et **comparer** le rapport reçu à celui du bouton VSTO sur les mêmes messages
  (ils doivent être identiques au format près). Vérifier le traitement aval de
  la boîte abuse.

## 7. Limites connues (assumées, documentées)

- **Pas de menu clic-droit** ni de multi-sélection garantis en OWA on-prem : le
  bouton agit sur **le message ouvert** (un à la fois).
- **Taille EWS** : l'envoi encode le `.eml` en base64 dans le SOAP ; pour des
  messages très volumineux (pièces jointes lourdes), surveiller la limite de
  taille de requête EWS (`MaxRequestSize` / IIS). Cas rare pour un signalement.
- Exécution **sandboxée navigateur** : aucun accès au poste (registre, journal
  d'événements) — la traçabilité est côté boîte abuse / serveur.
- Icône : PNG **1.C** (mêmes couleurs que le client lourd) aux tailles requises
  par le manifeste (16/25/32/48/64/80/128), fournies dans `assets/`.

## 8. Inventaire des fichiers

| Fichier | Rôle |
|---|---|
| `manifest.xml` | Déclaration du complément (bouton, icônes, EWS 1.1/1.5) |
| `src/analyse.js` | Analyse SPF/DKIM/DMARC — portage fidèle de `Config.vb` |
| `src/commands.js` | Logique du bouton : EWS GetItem MIME → rapport → EWS CreateItem |
| `src/commands.html` | FunctionFile (page invisible) chargée par Outlook |
| `src/taskpane.html` | Volet de repli (clients anciens) |
| `config.example.json` | Modèle de configuration (à copier en `src/config.json`) |
| `assets/icone-*.png` | Icône 1.C aux tailles du manifeste |
| `test/test_analyse.js` | Tests node du portage (corpus du banc) |
