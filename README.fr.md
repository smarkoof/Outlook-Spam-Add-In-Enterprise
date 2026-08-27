> **EN:** [English version](README.md)

# BoutonSPAM — signalement d'e-mails suspects pour Outlook

> Fork **fonctionnel et déployable en parc** de l'add-in open source
> milCERT [Outlook-Spam-Add-In](https://github.com/milcert/Outlook-Spam-Add-In)
> (MIT) : personnalisation centralisée (`branding.conf`), assistant interactif,
> chaîne de build MSI signé, déploiement GPO/Intune silencieux, et une
> **variante web** pour OWA / nouveau Outlook. Attributions : `CREDITS.md`.

Ce complément Outlook permet à vos utilisateurs de signaler les e-mails
suspects (spam / phishing) en un clic et réduit le délai entre le signalement
et l'analyse par votre équipe sécurité. Chaque e-mail signalé est évalué
(contenu, en-têtes, pièces jointes, expéditeur…), joint en pièce jointe au
rapport, puis envoyé à votre boîte abuse. Interface **français / anglais**
(détection automatique, anglais en repli).

![Ruban Outlook](pictures/outlook-classic-ribbon.png)

Deux déclinaisons dans ce dépôt :

| Déclinaison | Dossier | Cible |
|---|---|---|
| **Client lourd (VSTO)** | `OutlookSpamAddin/` + `setup/` | Outlook Windows 2016+ (.NET 4.8, VS 2022, MSI signé) |
| **Complément web** | `webaddin/` | OWA / nouveau Outlook (manifeste + hébergement HTTPS interne) |

## Aperçu

| Confirmation avant envoi | Rapport reçu par la boîte abuse |
|---|---|
| [![Confirmation](pictures/confirm.png)](pictures/confirm.png) | [![Rapport abuse](pictures/abuse-report.png)](pictures/abuse-report.png) |
| **Accusé de réception automatique** | **Bouton et info-bulle d'aide (nouveau Outlook)** |
| [![Accusé de réception](pictures/ack.png)](pictures/ack.png) | [![Info-bulle](pictures/button-tooltip.png)](pictures/button-tooltip.png) |

**Ruban du nouveau Outlook**

[![Nouveau Outlook](pictures/new-outlook-ribbon.png)](pictures/new-outlook-ribbon.png)

*Captures d'écran réelles d'Outlook (classique et nouveau Outlook), zones
propres à l'organisation masquées ; le rapport abuse est une illustration
construite à partir des textes réels du produit.*

## Démarrage rapide (client lourd)

Sous Windows, **PowerShell à la racine du projet, Visual Studio fermé** :

	# 1. Creer votre copie de configuration (jamais editer les .example)
	cp branding.conf.example branding.conf

	# 2. Personnaliser : adresses, textes, identite (voir CUSTOMIZATION.fr.md)

	# 3. Assistant interactif de bout en bout : poste, branding, certificat, MSI signe
	Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
	.\scripts\05_assistant.ps1

`.\scripts\04_build.ps1` fait la même chose **sans questions** quand
`branding.conf` est prêt. Chaîne complète des scripts : en-tête de chaque
fichier du dossier `scripts/`.

## Fonctionnalités

- Signalement d'un ou plusieurs e-mails (bouton du ruban ou menu contextuel)
- Détection et catégorisation des pièces jointes, comptage des liens
- Priorisation automatique (newsletter, liens, pièces à risque, signature…)
- Avertissement si l'expéditeur semble interne (regex configurable)
- Accusé de réception automatique à l'utilisateur (activable par poste)
- Inclusion de l'e-mail original en pièce jointe, journal d'événements Windows
- **Fail-close** : aucun destinataire codé en dur — sans configuration, rien ne part

## Priorités

|                                        | **Basse** | **Moyenne** | **Haute** |
|:---------------------------------------|:---------:|:-----------:|:---------:|
| sans lien ni pièce jointe              |     X     |             |           |
| Newsletter détectée (List-Unsubscribe) |     X     |             |           |
| 3 liens ou plus                        |           |      X      |           |
| Pièce jointe (.png, .css, .jpg, ...)   |           |      X      |           |
| 1 à 2 liens (schéma phishing typique)  |           |             |     X     |
| E-mail signé ou chiffré                |           |             |     X     |
| Pièce jointe (doc, exe, ps, js, ...)   |           |             |     X     |
| Domaine expéditeur du TLD surveillé    |           |             |     X     |

Règles évaluées dans cet ordre, la dernière vraie l'emporte : une newsletter
redescend le signalement en Basse même avec une pièce à risque, et le TLD
n'est testé que hors newsletter. Le TLD « national » surveillé (`\.fr$` par
défaut) se règle dans `Ribbon.vb`. Le volet web OWA ne fixe pas de priorité
(fonction du client lourd).

## Configuration par poste (registre)

L'essentiel se règle une fois par poste — gabarit fourni
(`resources/RegistryConfig.reg`, tenu à jour depuis `branding.conf`) :

	Windows Registry Editor Version 5.00

	[HKEY_LOCAL_MACHINE\SOFTWARE\OutlookSpamAddin]
	"To"="abuse@mondomaine[.]fr"
	"Cc"="spam@mondomaine[.]fr"
	"FilterInternalMessages"=dword:00000001
	"Regex"="(@mondomaine\\.fr$|@.*\\.mondomaine\\.fr$)"
	"SendAcknowledgment"=dword:00000001

Les exemples `[.]` sont volontairement inopérants : remplacez-les par vos
adresses réelles. Contre la désactivation automatique par Office (démarrage
> 1 s), une GPO machine
([ListOfManagedAddins](https://getadmx.com/?Category=Office2016&Policy=visio16.Office.Microsoft.Policies.Windows::L_ListOfManagedAddins))
avec le **libellé du bouton** = `1`, ou la clé HKCU fournie
(`resources/DoNotDisableAddinList*.reg`).

## Déploiement en parc (silencieux)

	msiexec /i "OutlookSpamAddin-<version>.msi" /qn /norestart ALLUSERS=1

Le dossier `deploy/` fournit le modèle **GPO ADMX/ADML** (configuration
centralisée + anti-désactivation) et `install-silencieux.cmd` (MSI + registre,
utilisable tel quel avec SCCM/MECM, Intune ou votre outil de parc).

## Complément web (OWA / nouveau Outlook)

Le dossier `webaddin/` contient le manifeste, les sources et un générateur
de configuration (`deploy.env` → `manifest.xml` + `config.json`, fail-close
sans destinataire) ; l'hébergement se fait sur l'hôte HTTPS interne de votre
choix. Guide : `webaddin/README-DEPLOIEMENT.md`.

## Signature de code

Renseignez `CERT_THUMBPRINT` (et `TIMESTAMP_URL`) dans `branding.conf`, puis
`.\scripts\03_sign.ps1` (intégré à `04_build.ps1`/`05_assistant.ps1`). Sans
certificat, un certificat de **TEST** auto-signé est créé automatiquement —
voir `certs/README.md`.

## Archive portable

`./scripts/00_make-archive.sh` (Git Bash) produit une archive horodatée du
projet avec empreinte **SHA-256**, layout Visual Studio hors-ligne compris.
Sur le poste cible, extraire vers une **racine courte** (ex. `C:\OSA`) :
l'installeur Visual Studio refuse un chemin de layout > 80 caractères.

## Sécurité

Envoi *fail-close*, vérification **Authenticode** des binaires téléchargés,
fichiers temporaires à nom aléatoire, borne anti-**ReDoS**, **SHA-256** des
archives — synthèse par version dans `CHANGELOG.fr.md`.

## Personnalisation

Chaque champ à adapter à votre organisation (les deux déclinaisons) est
répertorié dans [`CUSTOMIZATION.fr.md`](CUSTOMIZATION.fr.md)
([English](CUSTOMIZATION.md)).

## Licence

MIT — voir `LICENSE.md` (© milCERT pour le projet d'origine, © smarkoof pour
les évolutions). Attributions : `CREDITS.md`.
