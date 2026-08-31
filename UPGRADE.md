> **FR :** [Version française](UPGRADE.fr.md)

# Upgrading an existing deployment

How to move a fleet that already runs BoutonSPAM to a new release of this
repository. One principle drives everything: **a release never contains your
configuration**. Upgrading means starting from the new code, putting your own
files back, then rebuilding your MSI.

## What is yours (never shipped by a release)

| Element | Role |
|---|---|
| `branding.conf` | Your whole configuration — addresses, texts, version, MSI identity, certificate thumbprint. **The one file to never lose.** |
| `certs/` | Your code-signing certificate (never versioned, by design) |
| `installers/` | Offline binaries: VSTO runtime, Visual Studio layout |
| `webaddin/deploy/deploy.env` | Web add-in configuration, if you use it |

Everything else — including `setup/Setup.vdproj` — comes from the release and
is reset to repository defaults on every upgrade. That is fine: the values that
matter are re-applied from `branding.conf` by `scripts/02_customize.sh`.

## Step by step

1. **Fetch the release into a fresh folder** (`git clone --branch <tag> …`, or
   unzip the release archive next to your current folder — never on top of it).
2. **Put your files back**: `branding.conf`, `certs/`, `installers/`, and
   `webaddin/deploy/deploy.env` if applicable.
3. **Raise `VERSION`** in `branding.conf` — it must be strictly higher than the
   deployed one (the toolchain refuses a decrease), and adopt any new settings:
   compare your file with `branding.conf.example` and read the release notes.
4. **Build**: `.\scripts\05_assistant.ps1` (guided) or `.\scripts\04_build.ps1`,
   PowerShell at the project root, Visual Studio closed.
5. **Pilot workstation** (one that already runs the old version): after
   installing the new MSI, "Programs and Features" must list **one single**
   entry at the new version; the button works; the machine registry
   configuration survived (the MSI never touches it).
6. **Fleet**: `msiexec /i "<product>-<version>.msi" /qn /norestart ALLUSERS=1`
   (or `deploy/install-silencieux.cmd`, SCCM/Intune). Redeploy the ADMX only if
   the button label changed. Keep the signed MSI of every version you ship,
   with its ProductCode/UpgradeCode.

## MSI identity — handled for you

Windows only performs a clean **major upgrade** (old version removed
automatically) when, between two versions, the **ProductCode changes** while
the **UpgradeCode stays the same**. Since v1.6.2 the toolchain enforces both:

- **`UPGRADE_CODE`** (in `branding.conf`) pins your product-family identity.
  Set it **once** — at adoption, from the value printed by `REGEN_GUIDS=1` —
  and never change it. It is re-applied to `setup/Setup.vdproj` on every run,
  so it survives repository updates.
- The **ProductCode is regenerated automatically** whenever `VERSION`
  increases (and `REGEN_PRODUCTCODE=1` forces one without a version change).

If both identifiers were left untouched you would hit, at install time, either
error **1638** ("Another version of this product is already installed" — same
ProductCode) or a **side-by-side install**, two buttons in the ribbon
(different UpgradeCode).

> **Repositories at v1.6.1 or older**: the toolchain did not manage identity
> yet. Before building, manually edit `setup/Setup.vdproj`: restore *your*
> `UpgradeCode`, and replace `ProductCode` with a fresh GUID
> (`[guid]::NewGuid()` in PowerShell).

## Certificate replacement

The signing certificate is used twice: the VSTO manifest (at compile time —
**Windows certificate store only**) and the MSI Authenticode signature. To
replace it: import the new certificate into the store of the build machine,
update `CERT_THUMBPRINT` in `branding.conf`, rebuild — the toolchain rewires
both. Timestamped signatures of already-deployed packages remain valid after
the old certificate expires. If the new certificate comes from a different
authority, make sure the fleet trusts that issuer before deploying.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Error **1638** at install | ProductCode did not change | Raise `VERSION` (or `REGEN_PRODUCTCODE=1`), rebuild — or uninstall first |
| Two entries / two buttons | UpgradeCode differs from production | Pin your `UPGRADE_CODE`, rebuild, uninstall the duplicate |
| Toolchain refuses the version | `VERSION` lower than the project's | A version never decreases; `FORCE_VERSION=1` is only for brand-new bases |
| Button installed but refuses to send | Machine registry configuration missing | Apply `resources/RegistryConfig.reg` or the ADMX — fail-close by design |
