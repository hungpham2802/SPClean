# SPClean vs alternatives

How SPClean compares to Syskit Point and hand-rolled PowerShell scripts for detecting and cleaning orphaned users in SharePoint Online.

---

## Feature comparison

| Feature | SPClean Free | SPClean Pro | Syskit Point | Manual scripting |
| --- | :---: | :---: | :---: | :---: |
| **Orphaned user detection** | ✅ | ✅ | ✅ | ⚠ custom code required |
| **Risk scoring (HIGH / MEDIUM / LOW)** | ✅ | ✅ | — | — |
| **HTML report** | — | ✅ | ✅ web UI | — |
| **WhatIf / dry-run** | ✅ | ✅ | — | ⚠ manual implementation |
| **Snapshot & restore** | — | ✅ | ✅ permission history | — |
| **Scheduled / unattended scan** | — | ✅ | ✅ continuous | ⚠ manual Task Scheduler setup |
| **Pricing** | $0 | $79 / tenant / year | per-user SaaS (varies) | free (time investment) |
| **PowerShell pipeline support** | ✅ | ✅ | — | ✅ |
| **Air-gapped / offline operation** | ✅ | ✅ | — | ✅ |

⚠ = partial support; — = not available

---

## Positioning

**SPClean** is a focused, single-purpose module: detect orphaned users, score their risk, and remove them safely with rollback support. It lives inside your existing PowerShell workflow, integrates with the pipeline, and runs entirely inside your tenant — no SaaS backend, no data leaving your environment. Licensing is flat per-tenant ($79/year for Pro), which makes the cost predictable regardless of how many users your tenant has.

**Syskit Point** is a broader Microsoft 365 governance platform that covers permissions, lifecycle management, and reporting across Teams, SharePoint, and OneDrive. Orphaned user cleanup is one feature among many. It operates as a SaaS service with per-user pricing, which can be cost-effective for teams that need the full governance suite but adds overhead if the requirement is specifically orphaned user cleanup.

**Manual PowerShell scripting** has no licensing cost and gives full control, but building a reliable implementation — cross-referencing UILs with Entra ID via Graph batch, classifying account states, handling soft-deleted accounts, writing structured output, and wiring up WhatIf — takes substantial effort to develop and maintain. SPClean is effectively that script, already built and tested.

---

## When to use each

| Scenario | Recommendation |
| --- | --- |
| Occasional cleanup of a single tenant | SPClean Free |
| Regular scans with HTML reporting and snapshot backup | SPClean Pro |
| Full M365 governance (Teams, lifecycle, reviews) across many tenants | Syskit Point |
| Unique requirements that no existing tool covers | Manual scripting, or use SPClean as a base |

---

## See also

- [Licensing](licensing.md)
- [Quick Start](getting-started/quickstart.md)
- [Get-SPCOrphanedUser](cmdlets/get-spcorphaneduser.md)
