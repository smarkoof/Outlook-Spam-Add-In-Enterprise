> **FR :** [Version française](CUSTOMIZATION.fr.md)

# BoutonSPAM — Enterprise customisation sheet

Where every field to adapt to your organisation lives, for **both variants**
of the button. General principle: never edit an `.example` file (they are
templates) nor a generated file — edit your working copy, then let the
scripts propagate.

---

## 1. Desktop add-in (VSTO) — the single source: `branding.conf`

**File: `branding.conf` — project root** (created with
`cp branding.conf.example branding.conf`). All rebranding goes through it,
then `./scripts/02_customize.sh` (Git Bash) applies it everywhere — or the
assistant `.\scripts\05_assistant.ps1` (PowerShell), which also handles the
version bump and the MSI build.

| Field(s) | Role — what to put |
|---|---|
| `PRODUCT_NAME` | Product name (add-in manager, installer, ARP, DLL/.vsto names) |
| `COMPANY_NAME` | Your entity — shown as the software "Publisher" |
| `PRODUCT_DESCRIPTION` | Assembly description (can stay as is) |
| `SUPPORT_URL` | Support link (ARP). **http(s) only — never `mailto:`** |
| `COPYRIGHT` | Your entity + year |
| `VERSION` | 4 segments; **never decrease**; bump at every build |
| `INSTALL_FOLDER` | Subfolder under `%ProgramFiles%` |
| `MSI_BASENAME` | MSI base name (no spaces) |
| `PROJECT_SLUG` | Repository folder/project name (dev only) |
| `REGISTRY_CONFIG_KEY` | Per-workstation registry key — change only knowingly |
| `REPORT_TO` | **The abuse mailbox receiving the reports** (several addresses allowed, `;`-separated) |
| `REPORT_CC` | Report copy (`""` = no Cc) |
| `REGEX_INTERNAL` | Regex recognising your **internal** senders (warning before reporting) — see "Writing `REGEX_INTERNAL`" below |
| `UI_BUTTON_FR` / `_EN` | Ribbon button label (2 to 4 words, action verb first) |
| `UI_GROUP_FR` / `_EN` | Ribbon group name |
| `UI_BUTTON_TIP_FR` / `_EN` | Short hover description |
| `UI_BUTTON_SUPERTIP_FR` / `_EN` | Large help tooltip |
| `BUTTON_ICON` | Button icon (ribbon **and** context menus) — an icon provided by Office (`imageMso`): `PermissionRestrict` (default), `Risks`, `SourceControlRun`, `FilePermissionView`, `CancelRequest`. Nothing to ship, follows the Outlook theme. Any other value is rejected by `02_customize.sh` |
| `UI_CONFIRM_TITLE_FR` / `_EN` | Confirmation dialog title |
| `UI_REPORT_BODY_FR` / `_EN` | Report introduction sentence (seen by your analysts) |
| `UI_ACK_SUBJECT_FR` / `_EN` | Subject of the automatic acknowledgment |
| `UI_ACK_BODY_FR/_EN`, `UI_ACK_BODY_MORE_FR/_EN` | **Plain-text** override of the acknowledgment body (`""` = keep the HTML version from `Config.vb`) |
| `REPORT_SUBJECT_PREFIX`, `REPORT_SUBJECT_PREFIX_ERROR` | Subject prefixes `[SPAM]` / `[SPAM-ERREUR]` (abuse mailbox sorting rules) |
| `CERT_THUMBPRINT`, `TIMESTAMP_URL` | Code signing (certificate thumbprint, RFC 3161 timestamping) |
| `REGEN_GUIDS` | `1` once during a full rebranding, otherwise `0` |

Writing rules (recap of the file header): no double quotes `"` nor angle
brackets `< >` in values, no line breaks; addresses **without** brackets —
the `[.]` examples are deliberately inoperative (`02_customize.sh` rejects
them, and the add-in refuses to send: fail-close).

### Writing `REGEX_INTERNAL`

Before sending a report, the add-in matches the sender's address against this
pattern: on a match it warns the user ("this message looks internal, report it
anyway?") — this avoids reporting legitimate colleagues' e-mails by mistake.

Building blocks: `\.` = literal dot, `$` = end of address, `.*` = anything,
`|` = OR (cover the exact domain **and** its subdomains). Start from the part
**after the `@`** of your e-mail addresses (not the website URL) and escape
every dot as `\.`:

```
Simple domain    : (@city-xyz\.fr$|@.*\.city-xyz\.fr$)
Compound domain  : (@ministry-xyz\.gouv\.fr$|@.*\.ministry-xyz\.gouv\.fr$)
Several domains  : (@a\.gouv\.fr$|@.*\.a\.gouv\.fr$|@b\.gouv\.fr$|@.*\.b\.gouv\.fr$)
```

Exchange tip: the `^/O=…/OU=…` prefix (see the original project) also catches
"Exchange internal" addresses in addition to SMTP `@domain` ones.

### Desktop extras (outside branding.conf)

**`OutlookSpamAddin/Config.vb`** — "**USER-FACING TEXTS**" zone (from line
683): detailed dialog bodies (confirmation, errors, guardrails) and the
**HTML acknowledgment body** — `ackBodyOneFR` / `ackBodyMoreFR` lines 764–765
(EN: 734–735), where the `MonOrganisationSSI` placeholder must be replaced.
Changing them = recompile (new `VERSION`). The field ↔ constant mapping is
documented at the top of the zone (lines 683–708).

**`OutlookSpamAddin/Ribbon.vb`** — line 403: the **national TLD** regex
(`(\.fr$)`) that raises the report priority when the sender is on this TLD.
Hardcoded because it rarely changes.

**`resources/RegistryConfig.reg`** (kept in sync by `02_customize.sh`) — the
**per-workstation** override, no recompilation nor redeployment, under
`HKLM\SOFTWARE\OutlookSpamAddin` (values read in `Config.vb` lines 520–528):

| Registry value | Role |
|---|---|
| `To` / `Cc` | Report recipient / copy (take precedence over compiled defaults) |
| `FilterInternalMessages` | `1` = warn when the sender looks internal |
| `Regex` | The internal regex (same syntax as `REGEX_INTERNAL`) |
| `SendAcknowledgment` | `1` = automatic acknowledgment to the user |
| `IncludeTechnicalReport` | `1` = "TECHNICAL ANALYSIS" block (SPF/DKIM/DMARC…) in the report |

---

## 2. Web button (OWA / new Outlook) — `webaddin/` folder

**`webaddin/deploy/deploy.env`** (to create: `cp deploy.env.example
deploy.env`, then `chmod 600`). The web-side equivalent of `branding.conf`;
`./apply-config.sh` then generates `manifest.xml` and `config.json` into
`deploy/out/`, without touching the system:

| Variable | Role |
|---|---|
| `ABUSE_TO` | **Mandatory** — the abuse mailbox (empty = generation refused, fail-close) |
| `ABUSE_CC`, `REPORT_SUBJECT_PREFIX` | Copy, subject prefix (default `[SPAM]`) |
| `ADDIN_FQDN` | Internal HTTPS host serving the add-in |
| `ADDIN_ID` | Add-in GUID — **freeze it** after the first generation |

**`webaddin/config.example.json`** → served as `src/config.json` (equivalent
of the VSTO registry keys; `abuseTo`, `abuseCc` and `reportSubjectPrefix` are
injected from `deploy.env`): `includeTechnicalReport`, `attachEml`,
`ackToUser`, `ackSubject`, `ackBody`. Fail-close if `abuseTo` is empty.

**`webaddin/manifest.xml`** — the texts visible in OWA, to edit directly:
`ProviderName` (l. 24), `DisplayName` (l. 26), `Description` (l. 27), icons
(l. 28–29 and 115–120), `SupportUrl` (l. 30), group and button labels +
tooltip (l. 126–130). The GUID (`11111111-…`) and the
`addin.interne.example` domain are replaced automatically by
`apply-config.sh` — do not edit them by hand.

Side details: web report introduction sentence in `webaddin/src/commands.js`
(l. 73), "Sending..." message in `webaddin/src/taskpane.js` (l. 11).

---

## 3. The essentials in three moves

1. **Addresses and internal filter**: `REPORT_TO` / `REPORT_CC` /
   `REGEX_INTERNAL` in `branding.conf` (and `deploy.env` for the web variant)
   — the vital minimum, everything else has sensible defaults.
2. **Identity and texts**: `branding.conf` "Identity" and "User texts"
   sections; fine-grained dialog bodies in `Config.vb` (zone l. 683+).
3. **Apply**: `./scripts/02_customize.sh` then build (`05_assistant.ps1`
   recommended) on the VSTO side; `cp deploy.env.example deploy.env` + edit +
   `./apply-config.sh` on the web side.

Security guardrails (fail-close, inoperative examples, `deploy.env`
permissions) are summarised in `CHANGELOG.md` and `README.md`.
