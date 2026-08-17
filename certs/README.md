# certs/ — certificats de signature de code

Déposez ici votre certificat de signature (`.pfx` / `.p12`). Ces fichiers sont
**ignorés par git** (règles `*.pfx` / `*.p12` du `.gitignore` racine) : la clé
privée ne doit jamais être versionnée. Seul ce README est suivi.

**Ce dossier se remplit automatiquement** : `scripts/01_verification-poste.ps1` copie ici
tout `.pfx`/`.p12` trouvé sur le poste (Downloads, Bureau, C:\Dev…), et, si
AUCUN certificat n'existe, crée un certificat de TEST auto-signé
(`TestBoutonAbuse.pfx`, mot de passe aléatoire affiché une seule fois à la création) — à remplacer plus tard par le
vrai certificat de l'organisation (il suffit de déposer le vrai `.pfx` ici et de
mettre à jour `CERT_THUMBPRINT` dans `branding.conf`).
Référence : sections « Signature de code » du `README.md` / `README.fr.md`.

## Deux façons de signer le MSI (sous Windows, après build)

### 1. Via le magasin de certificats (recommandé)

    # importer une fois le certificat dans le magasin utilisateur
    Import-PfxCertificate -FilePath .\certs\moncert.pfx -CertStoreLocation Cert:\CurrentUser\My

    # récupérer l'empreinte (Thumbprint)
    Get-ChildItem Cert:\CurrentUser\My | Format-List Subject, Thumbprint, NotAfter

Renseignez ensuite `CERT_THUMBPRINT` dans `branding.conf` (puis `./scripts/02_customize.sh`
pour câbler aussi la signature du manifeste VSTO dans le `.vbproj`), et lancez :

    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1

### 2. Directement depuis le fichier .pfx

    powershell -ExecutionPolicy Bypass -File .\scripts\03_sign.ps1 -PfxPath .\certs\moncert.pfx -PfxPassword "motdepasse"

Note : la signature du **manifeste VSTO** (à la compilation) passe par le magasin
de certificats uniquement (propriété du projet Visual Studio) ; le mode `.pfx`
direct ne concerne que la signature du MSI.
