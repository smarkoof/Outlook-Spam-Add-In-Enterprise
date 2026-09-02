> **FR :** [Version française](CHANGELOG.fr.md)

# Changelog

Concise version history. Versions follow the add-in's 4-segment scheme
(`branding.conf` → `VERSION`).

## v1.6.x and later — hybrid OWA variant, field feedback
- **Web add-in variant** (`webaddin/`) for OWA and the new Outlook: same
  reporting behaviour, served from an internal HTTPS host; configuration
  generated from `deploy.env` (fail-close if no recipient).
- HTML acknowledgment e-mail themed by branding; plain-text override available.
- Generic neutralisation of every shipped address (the `[.]` examples are
  deliberately inoperative; the customisation script and the add-in both
  refuse them: fail-close by design).
- New-workstation bootstrap: `01_verification-poste.ps1 -Setup/-Install`
  (inventory, prerequisites, Visual Studio, offline layout, short-root rule).
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
