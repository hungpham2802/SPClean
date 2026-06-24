# Technical Decisions

<!-- Format: ## D-NNN — Title
Date:
Decision:
Reason:
Alternatives considered:
SRS ref: -->

---

## D-001 — PnP.PowerShell as sole SharePoint dependency
**Date:** 2026-06-21  
**Decision:** Use PnP.PowerShell (not CSOM or raw REST) for all SharePoint interactions.  
**Reason:** PnP abstracts throttling, auth, and pagination; aligns with SRS 5.1 recommendation.  
**Alternatives considered:** Microsoft.SharePoint.Client (CSOM) — dropped, no PS5.1 nuget support in module context.  
**SRS ref:** 5.1

## D-002 — Certificate-based auth as primary AppOnly method
**Date:** 2026-06-21  
**Decision:** Connect-SPCTenant uses .pfx certificate + ClientId for AppOnly; Interactive for user-delegated.  
**Reason:** SRS 3.1.1 requires AppOnly support; certificate avoids secret rotation issues.  
**Alternatives considered:** Client secret — rejected, rotates every 2 years and is plain-text in memory.  
**SRS ref:** 3.1.1, 4.3

## D-003 — `-Interactive` used instead of SRS's `-DeviceLogin`
**Date:** 2026-06-22  
**Decision:** `Connect-PnPOnline -Interactive` used for device-code flow instead of `-DeviceLogin`.  
**Reason:** PnP.PowerShell 2.x renamed the switch from `-DeviceLogin` to `-Interactive`; both invoke the same MSAL device code flow. Module requires PnP.PS ≥ 2.0.0 (see psd1).  
**Alternatives considered:** `-DeviceLogin` — would fail on PnP.PS 2.x with "parameter not found" error.  
**SRS ref:** 3.1.1

## D-004 — `Microsoft.Graph.Authentication` added to RequiredModules
**Date:** 2026-06-22  
**Decision:** Added `Microsoft.Graph.Authentication 2.0.0` to `SPClean.psd1` RequiredModules.  
**Reason:** SRS 3.1.1 step 2 requires `Connect-MgGraph` for Interactive mode; that cmdlet ships in this module.  
**Alternatives considered:** Soft-import via `Import-Module -ErrorAction SilentlyContinue` — rejected, would silently skip Graph connection and fail later at `Get-PnPGraphAccessToken` in unexpected ways.  
**SRS ref:** 3.1.1

