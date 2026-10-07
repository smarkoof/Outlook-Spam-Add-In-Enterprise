> **FR :** [Version française](CHANGELOG.fr.md)

# Changelog

Concise version history. Versions follow the add-in's 4-segment scheme
(`branding.conf` → `VERSION`).

## v1.6.x and later — hybrid OWA variant, field feedback
- **The five button icons are illustrated**: `README.md` shows the Outlook
  ribbon with each accepted `BUTTON_ICON` value, named under its screenshot.
  Picking an icon no longer requires building it to see it.
- **Icon trials in one pass**: `scripts/93_generate-icons.ps1` builds one MSI
  per icon back to back and gathers them in `essais-icones\`, with a progress
  bar, per-icon timing and devenv CPU time — useful when the build machine and
  the test machine cannot talk to each other: a single transfer. The original
  `BUTTON_ICON` setting is restored even if a build fails, and the produced
  package is found by its timestamp, never by a guessed name.
- The output folder gets an `INSTALLER.txt`: `msiexec` install and uninstall
  commands for each icon, ProductCode, signature state, return codes, and what
  to do on error 1625. No script travels with the packages: `msiexec` goes
  through where a `.ps1` is refused by AppLocker or SRP.
- **Web add-in variant** (`webaddin/`) for OWA and the new Outlook: same
  reporting behaviour, served from an internal HTTPS host; configuration
  generated from `deploy.env` (fail-close if no recipient).
- HTML acknowledgment e-mail themed by branding; plain-text override available.
- Generic neutralisation of every shipped address (the `[.]` examples are
  deliberately inoperative; the customisation script and the add-in both
  refuse them: fail-close by design).
- New-workstation bootstrap: `01_verification-poste.ps1 -Setup/-Install`
  (inventory, prerequisites, Visual Studio, offline layout, short-root rule).
- The migration script **no longer regresses documentation**: it never overwrites a
  file already shipped by the release (the `README.md` files of `certs/` and
  `installers/`), and reports which ones it preserved.
- It **inventories `certs/`** before copying: subject, validity or expiry,
  thumbprint, duplicates (same certificate under two names, identical files), plus a
  reminder of the declared `CERT_THUMBPRINT`. It deletes nothing — losing a
  certificate would be worse than keeping a spare — but pruning becomes an informed
  choice.
- **Versions kept apart**: the repository release number (`v1.6.x`) only concerns the
  toolchain; your button's version (`branding.conf` → `VERSION`) is yours and follows
  its own pace. The script and the guide now say so.
- **Migration script shipped**: `scripts/92_migrate-release.ps1` carries your
  configuration, certificates and tooling into a new release folder, pins your
  production `UPGRADE_CODE`, raises the version, then verifies the result.
  `-Simulation` mode writes nothing.
- **Renaming the product no longer breaks the build**: `04_build.ps1` reads the
  assembly name from the `.vbproj` (written from `PRODUCT_NAME`) instead of
  hardcoding it. Building variants — to compare several icons, for instance —
  now works without touching the toolchain.
- Signing prerequisite **checked before compiling**: a missing `signtool` is
  reported within seconds instead of after the whole build. `tools/`
  (signtool, python) is not versioned: carry it over between working folders,
  or obtain it via `01_verification-poste.ps1` (connected machine) or the
  project archive `00_make-archive.sh` (isolated machine).
- Automated MSI identity: `UPGRADE_CODE` pinned in `branding.conf`, ProductCode
  regenerated on every version increase (clean Windows major upgrades) —
  upgrade guide in `UPGRADE.md`.

## v1.6.0.0 — full remediation of audit findings (product + toolchain)
## v1.5.1 — follow-up audit remediation (toolchain)
## v1.5.0.0 — reliable offline layout, enterprise certificate, persistent tooling
- Signed MSI chain: `signtool` fetched via NuGet, RFC 3161 timestamping.

## v1.1.0.0 — security improvements (after audit)
- Fail-close sending (no built-in recipient), Authenticode verification of
  downloaded binaries, random temporary file names, anti-ReDoS bound on the
  internal-sender regex, SHA-256 for portable archives.

## v1.0.0.0 — initial version
- Fork of milCERT's Outlook-Spam-Add-In made fully functional and
  configurable: `branding.conf` as the single source, interactive assistant
  (`05_assistant.ps1`), one-command build (`04_build.ps1`), FR/EN interface,
  registry-based per-workstation configuration, GPO/Intune silent deployment.
