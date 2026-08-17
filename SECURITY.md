# Security Policy

## Reporting a vulnerability

Please report security issues through GitHub's **private vulnerability
reporting**: [Security → Report a vulnerability](https://github.com/smarkoof/Outlook-Spam-Add-In-Enterprise/security/advisories/new).
Reports are only visible to the maintainer.

Please do **not** open public issues for security matters. You can expect an
acknowledgment within a few days; coordinated disclosure is appreciated —
allow a reasonable delay for a fix before any public disclosure.

## Supported versions

Only the latest release line (**1.6.x**) receives security fixes.

## Notes for reviewers

- The add-in is **fail-close**: without a configured abuse address
  (registry / GPO), nothing is ever sent.
- No binaries are published here: each organisation builds and signs its own
  MSI (`scripts/04_build.ps1`, `scripts/03_sign.ps1`).
- Reports are transmitted by Outlook itself (no third-party service, no
  telemetry).

---

**Version française** — Merci de signaler toute vulnérabilité via
**Security → Report a vulnerability** (signalement privé, visible du seul
mainteneur), et non par une issue publique. Accusé de réception sous
quelques jours ; la divulgation coordonnée est appréciée. Seule la branche
**1.6.x** reçoit des correctifs de sécurité. Rappels : comportement
fail-close (rien ne part sans adresse configurée), aucun binaire publié
(chaque organisation compile et signe son MSI), aucun service tiers ni
télémétrie.
