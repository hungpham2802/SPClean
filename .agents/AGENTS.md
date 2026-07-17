# SPClean Project Rules & Context

You are working on **SPClean**, a PowerShell toolkit for SharePoint Online permission hygiene. It finds, scores, reports, and safely removes orphaned users (deleted, disabled, or guest accounts).

## 1. Project Context
*   **Architecture:** `Public/` contains exported cmdlets, `Private/` contains internal helpers.
*   **Authentication:** Supports both Interactive (Delegated) and AppOnly (Application) via `Connect-SPCTenant`. Requires `PnP.PowerShell` and `Microsoft.Graph.Authentication`.
*   **License Model:** Freemium. Pro unlocks HTML reports, Scheduling, and Snapshot Backup/Restore.

## 2. PowerShell Coding Standards
*   **Function Structure (Mandatory):**
    1. `[CmdletBinding(SupportsShouldProcess=$true)]` (for write cmdlets).
    2. `[OutputType()]` attribute.
    3. `param()` block with exact types AND strictly use validation attributes (e.g., `[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`) when appropriate.
    4. `begin {}` block (Must call `Test-SPCConnection` guard).
    5. `process {}` block (Main logic).
    6. `end {}` block (Summary `Write-Information` if applicable).
*   **Naming:** 
    - Public: `Verb-SPC{Noun}`. Private: `Verb-SPC{Noun}Internal`.
    - Variables: `$PascalCase` for objects, `$camelCase` for scalars.
    - No abbreviations except: SPC, UIL, UPN, SPO.
*   **Logging & Output:** 
    - Use `Write-Verbose` (tracing), `Write-Progress` (loops), `Write-Information` (summaries).
    - **NEVER** use `Write-Host`.
*   **Error Handling:** 
    - Non-terminating: `Write-Error`.
    - Terminating: `throw` with specific `ERR-xxx` code. Include error code, affected resource, and timestamp.
*   **Throttling:** Use the exact Graph API 429 exponential backoff retry pattern (max 5 attempts).
*   **Graph Batching:** Maximum 20 requests per `$batch` call.

## 3. Business Logic & Constraints (SRS)
*   **Risk Scoring:**
    - **HIGH**: `Deleted` AND (`HasDirectPermissions` OR `GroupCount > 0`). OR `GuestOrphaned` AND `HasDirectPermissions`.
    - **MEDIUM**: `SoftDeleted`. OR `Disabled` AND `HasDirectPermissions`.
    - **LOW**: `Deleted` AND no permissions/groups. Or all others.
*   **WhatIf String:** Must match exactly: `"WhatIf: Would remove user {DisplayName} ({UPN}) from site {SiteUrl}. OrphanType: {OrphanType}. DirectPermissions: {HasDirectPermissions}."`
*   **Snapshot Schema:** Must include `snapshotVersion, createdAt, tenantName, siteUrl, user.loginName, user.displayName, user.upn, permissions[], groupMemberships[]`.
*   **HTML Badges:** HIGH (`#dc3545`), MEDIUM (`#ffc107`), LOW (`#28a745`).

## 4. Testing Standards (Pester 5)
*   **Structure:** `Describe` = cmdlet name, `Context` = scenario, `It` = AC-ID from SRS + description.
*   **Mandatory Mocks:** NEVER let real calls through in Unit tests. Always mock: `Connect-PnPOnline`, `Get-PnPSiteUser`, `Invoke-SPCGraphBatch`, `Remove-PnPUser`.
*   **Security (AC-12):** Every test file must ensure no credentials leak in the verbose stream (`-Not -Match 'password|secret|token|pfx|credential'`).
*   **Workflow:** If a test fails, DO NOT edit the test to force a pass. Fix the source code and log it.

## 5. Security & Pre-commit Guardrails
Before committing any PowerShell code or proposing a final implementation, you MUST verify the following security rules. Block the commit and provide remediation recommendations if any issue is found:

*   **Credentials & Secrets:** 
    - No hardcoded credentials, secrets, API keys, or tokens.
    - Do not store client secrets in scripts (pass them securely via parameters).
*   **Authentication:** 
    - Prefer Managed Identity, certificate-based authentication, or OAuth. 
    - Do not use unattended accounts with passwords.
    - Follow least privilege principles for API scopes.
*   **Network & Encryption:** 
    - Ensure HTTPS is used everywhere.
    - Ensure TLS validation is NEVER bypassed (e.g., do not override `ServerCertificateValidationCallback`).
*   **Vulnerability Prevention:** 
    - Strictly **REJECT** any use of `Invoke-Expression` (`IEX`).
    - Ensure absolutely no sensitive information (tokens, passwords) is written to logs, verbose, or information streams.
*   **Syntax & Code Quality:**
    - ALWAYS explicitly verify PowerShell syntax before proposing or committing code (do not commit broken scripts).
    - Prioritize using the Microsoft Learn MCP (`mslearn`) to fetch the latest API references and best practices for Microsoft Graph and PnP PowerShell.

## 6. Safe Testing Rule
*   **Environment Safety:** DO NOT delete or disable existing active users on the tenant while writing automation or conducting manual tests. ALWAYS create dedicated new test users (e.g. \mismatchtest@...\) dynamically via script for testing purposes, and clean them up afterward.
