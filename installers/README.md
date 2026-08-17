# installers/ — dependances embarquees (archive 100% autonome)

Ce dossier rend l'archive AUTONOME et alimente `scripts/01_verification-poste.ps1 -Setup` /
`-Install`. Son contenu (sauf ce README) n'est pas suivi par git, mais il EST
inclus dans l'archive .zip generee par scripts/00_make-archive.sh.

## Contenu

| Element | Role | Source (poste connecte) |
|---|---|---|
| `Git-*.exe` | Git pour Windows (Git Bash -> scripts/02_customize.sh) | https://git-scm.com/download/win |
| `InstallerProjects2022.vsix` | Extension VS pour construire le MSI | https://marketplace.visualstudio.com/items?itemName=VisualStudioClient.MicrosoftVisualStudio2022InstallerProjects |
| `vstor_redist.exe` | VSTO Runtime (execute l'add-in) | https://www.microsoft.com/download/details.aspx?id=48217 |
| `ndp48-x86-x64-allos-enu.exe` | .NET 4.8 Runtime | https://go.microsoft.com/fwlink/?linkid=2088631 |
| `ndp48-devpack-enu.exe` | .NET 4.8 Developer Pack (ciblage) | https://dotnet.microsoft.com/download/dotnet-framework/net48 |
| `npp.*.exe` | Notepad++ (optionnel) | https://notepad-plus-plus.org/downloads/ |
| `vslayout/` | **Layout Visual Studio 2022 (~4 Go) EMBARQUE** : permet d'installer/completer VS **entierement hors ligne** | genere par scripts/99_make-layout.cmd dans une VM connectee |

## Installation cle en main

Sur la machine cible, PowerShell administrateur, a la racine du projet :

    .\scripts\01_verification-poste.ps1 -Setup

- Avec internet : installe/complete tout en ligne.
- Sans internet : detecte automatiquement `installers\vslayout` et installe/complete
  Visual Studio depuis ce layout, puis pose extension + Git + VSTO. 100% hors ligne.

## Notes

- Le layout est **volumineux (~4 Go)** : c'est voulu, pour l'autonomie totale. `.gitignore`
  l'exclut de git (regle `installers/*`) ; scripts/00_make-archive.sh l'inclut dans l'archive.
- Charge 'Office/SharePoint' de VS : geree automatiquement par `-Setup`/`-CompleteVS`
  (depuis le layout hors ligne, ou internet).
- **signtool** : recupere en LEGER via NuGet (Microsoft.Windows.SDK.BuildTools) dans
  `tools\signtool\` du projet quand internet est disponible — sans installer le SDK
  complet. Hors ligne : composant 'SDK Windows' via le layout. S'il est deja dans
  `tools\signtool\`, RIEN n'est retelecharge.
- Le script ne reinstalle JAMAIS un composant deja present (detection d'abord).
- SECURITE (v1.1.0.0) : la signature Authenticode de CHAQUE binaire est verifiee AVANT
  execution (installateur VS, signtool NuGet, Python, installateurs .exe/.msi ci-dessus).
  Un fichier non signe ou altere est REFUSE. => si vous remplacez/ajoutez un installateur
  ici, telechargez-le depuis la SOURCE OFFICIELLE de la colonne ci-dessus (binaire signe).
- SECURITE : les telechargements utilisent TLS avec revocation en "meilleur effort"
  (--ssl-revoke-best-effort), et l'archive de migration est accompagnee d'une empreinte
  SHA-256 (fichier .sha256) a verifier avant extraction (voir le README racine, section « Archive portable »).
- Apres tout ajout ici, regenerer l'archive : `./scripts/00_make-archive.sh`
  (elle produit aussi `<archive>.zip.sha256`).
- Reference : README racine (sections « Archive portable » et « Securite »).
