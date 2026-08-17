# deploy/ — outils de déploiement en parc

| Élément | Rôle |
|---|---|
| `ADMX/BoutonSpam.admx` + `ADMX/fr-FR/BoutonSpam.adml` | Modèle de **GPO** : configuration centralisée (To, Cc, regex, accusé de réception…) + stratégie utilisateur anti-désactivation Outlook. À copier dans le magasin central `\\<domaine>\SYSVOL\<domaine>\Policies\PolicyDefinitions\` |
| `install-silencieux.cmd` | Installation **silencieuse** d'un poste : MSI (`/qn`) + configuration registre + anti-désactivation. Utilisable tel quel comme commande d'installation SCCM / Intune (Win32) / outil de parc |

## Le MSI seul suffit-il ?

**Non — deux compléments sont nécessaires, mais le script `.cmd` n'est PAS obligatoire :**

1. **La clé registre `HKLM\SOFTWARE\OutlookSpamAddin` (valeur `To`, au minimum) est indispensable.**
   Choix de sécurité (*fail-close*) : **aucune adresse n'est codée dans le programme** —
   sans `To` valide, le bouton s'installe mais refuse d'envoyer (« Extension non configurée »).
   Valeurs de référence : `resources\RegistryConfig.reg`, ou l'ADMX ci-dessus.
2. **Le VSTO Runtime** doit être présent (souvent déjà là avec Office ; sinon `installers\vstor_redist.exe /q /norestart`).

Le `.cmd` n'est qu'un **emballage pratique** de ces étapes : tout outil de parc peut les faire en **tâches natives**.
Exemple avec un **outil de télédistribution** (tâches natives) :

| Tâche native | Contenu | Condition |
|---|---|---|
| 1. Prérequis | `vstor_redist.exe /q /norestart` | si clé `HKLM\SOFTWARE\Microsoft\VSTO Runtime Setup\v4R` absente |
| 2. MSI | `msiexec /i "<produit>-<version>.msi" /qn /norestart ALLUSERS=1` (ou module Windows Installer natif) | — |
| 3. Registre machine | valeurs de `resources\RegistryConfig.reg` (To, Cc, FilterInternalMessages, Regex, SendAcknowledgment) via le module Registre | — |
| 4. (Option) Registre utilisateur | clé anti-désactivation HKCU (`resources\DoNotDisableAddinList*.reg`) — idéal via le volet « environnement utilisateur » de l'outil de parc, ou la GPO utilisateur ADMX | par utilisateur |

Le nom de valeur de la stratégie anti-désactivation (= le **libellé du bouton**) est synchronisé
automatiquement par `scripts/02_customize.sh` — redéployer l'ADMX après un changement de nom.

Modes de déploiement pas à pas (GPO, Intune, SCCM, commandes `msiexec`) : **README principal**,
section « Déploiement en parc (silencieux) » (`README.md` / `README.fr.md`).
