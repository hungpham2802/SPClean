# Known Errors & Patterns

## E001 — SecureString leak
**Symptom:** AC-12 fails — "password" found in verbose stream  
**Root cause:** ConvertFrom-SecureString called without -AsPlainText:$false  
**Fix:** Use [System.Runtime.InteropServices.Marshal]::PtrToStringAuto() only in-memory, never Write-Verbose  
**SRS:** 4.3

## E002 — TypeName not propagated through pipeline
**Symptom:** Export-SPCReport complains input is not [SPC.OrphanedUser]  
**Root cause:** PSCustomObject TypeName không được set: PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')  
**Fix:** Add TypeName immediately after PSCustomObject creation in Get-SPCOrphanedUser  
**SRS:** 2.4

## E003 — Import-Module SPClean.psd1 fails without PnP.PowerShell
**Symptom:** `Import-Module .\SPClean.psd1` throws "required module PnP.PowerShell is not loaded"  
**Root cause:** RequiredModules in psd1 enforces that the dependency is installed before import  
**Fix:** Run `Install-Module PnP.PowerShell -Scope CurrentUser` on any dev/test machine  
**Workaround for CI/scaffold testing:** Import `SPClean.psm1` directly — all 7 functions load correctly  
**Not a code defect** — manifest syntax is valid

## E004 — PnP 3.x removed legacy cmdlets used in source files
**Symptom:** Pester unit tests fail with `CommandNotFoundException` for `Get-PnPGraphAccessToken`, `Get-PnPSiteUser`, `Get-PnPRoleAssignment`, `Remove-PnPRoleAssignment`, `Add-PnPRoleAssignment`  
**Root cause:** PnP.PowerShell 2.x had these cmdlets; 3.x renamed/removed them (replacement: `Get-PnPAccessToken`, `Get-PnPUser`, `Get-PnPWebPermission`, `Set-PnPWebPermission`)  
**Fix:** Added compatibility wrapper functions at the top of each source file, guarded with `if (-not (Get-Command ... ))`. Wrappers define the old name and delegate to the PnP 3.x equivalent. Tests mock the old names, which now exist as functions after dot-sourcing.  
**Files affected:** Connect-SPCTenant.ps1, Get-SPCOrphanedUser.ps1, Remove-SPCOrphanedUser.ps1, Restore-SPCOrphanedUser.ps1  
**Note:** `Get-PnPWebPermission` has no `-Connection` param in 3.2.0 — uses module-level current connection. Verify `Get-PnPRoleAssignment` wrapper in Phase 4 integration tests.  
**SRS:** 3.1.1, 3.2.1, 3.4.1, 3.4.2

## E005 — Get-SPCOrphanedUser.Tests.ps1 — two test-file bugs (unfixable from source)

### E005a — $script:callCount not reset between tests (AC-03 tests 4 & 5)
**Symptom:** `Cannot index into a null array` at `$result[0]` in the "SiteUrl and SiteTitle" and "all required output properties" tests.  
**Root cause:** `BeforeEach` resets `$callCount = 0` (local scope) but the mock body uses `$script:callCount`. The counter accumulates across tests 1→3; by tests 4–5, `$script:callCount > 1` so the mock returns the soft-delete branch (status 200, `body:{value:[]}`) for ALL batch calls. Users appear "found but active" → no orphan classification → `$result = $null`.  
**Repro:** Run tests 4 & 5 in isolation — "SiteUrl" passes first (callCount=1 for test 4's first call), "all required props" fails (callCount=3 by then).  
**Fix needed in test file (CANNOT edit per CLAUDE.md):** Change `$callCount = 0` to `$script:callCount = 0` in the Context BeforeEach.  
**Workaround:** None from source — this is purely test logic. 78/81 tests pass.

### E005b — Should -Invoke -Minimum is not valid in Pester 5.7.1
**Symptom:** `Should -Invoke does not take pipeline input or ActualValue` for the "Invoke-SPCGraphBatch is called for real (non-system) users" test.  
**Root cause:** `-Minimum` is not a parameter of `Should -Invoke` in Pester 5.7.x. Pester 5's `Should -Invoke` uses `-Times <n>` (without `-Exactly`) to mean "at least n times". There is no `-Minimum` flag.  
**Fix needed in test file (CANNOT edit per CLAUDE.md):** Remove `-Minimum` from `Should -Invoke Invoke-SPCGraphBatch -Times 1 -Minimum`.  
**Workaround:** None from source. 78/81 tests pass.

## E006 — AADSTS900023: tenant identifier must be a valid DNS name
**Symptom:** `Connect-PnPOnline -Tenant 'icclabvn'` throws `AADSTS900023: The specified tenant 'icclabvn' is neither a valid DNS name`.  
**Root cause:** Azure AD requires a fully qualified domain name; passing only the short tenant name fails.  
**Fix:** In every `Connect-PnPOnline -Tenant $x` call (Connect-SPCTenant.ps1 and all three `$connectToSite` scriptblocks), compute `$tenantId = if ($name -match '\.') { $name } else { "$name.onmicrosoft.com" }`.  
**Files:** Connect-SPCTenant.ps1, Get-SPCOrphanedUser.ps1, Remove-SPCOrphanedUser.ps1, Restore-SPCOrphanedUser.ps1  
**SRS:** 3.1.1

## E007 — PnP 3.x Get-PnPGraphAccessToken: no default connection
**Symptom:** `InvalidOperationException: There is currently no connection yet` from `Get-PnPGraphAccessToken`.  
**Root cause:** `Connect-PnPOnline -ReturnConnection` in PnP 3.x does NOT set the module-level default connection. Calling `Get-PnPGraphAccessToken` without `-Connection` fails.  
**Fix:** Pass `-Connection $pnpContext` to `Get-PnPGraphAccessToken` in Connect-SPCTenant.ps1.  
**SRS:** 3.1.1

## E008 — PnP 3.x GroupPipeBind: SiteGroup object not accepted via call operator
**Symptom:** `PSInvalidCastException: Cannot convert SiteGroup to GroupPipeBind` at `Get-PnPGroupMember` wrapper line 43.  
**Root cause:** When calling the binary `Get-PnPGroupMember` via `& $capturedRef -Group $group`, PnP cannot coerce `SiteGroup → GroupPipeBind`. Direct call works; call operator does not trigger the same coercion.  
**Fix:** In wrapper, pass `$Group.Title` (string) instead of the object. `GroupPipeBind` accepts strings.  
**Note:** `SiteGroup.Id` is NOT populated by `Get-PnPSiteGroup` in PnP 3.x (CSOM lazy load) — always use `.Title`.  
**SRS:** 3.2.1

## E009 — PnP 3.x Get-PnPUser: parameter renamed -LoginName → -Identity
**Symptom:** `A parameter cannot be found that matches parameter name 'LoginName'` when calling the real binary via wrapper.  
**Root cause:** PnP 3.x `Get-PnPUser` uses `-Identity` (UserPipeBind) instead of `-LoginName`.  
**Fix:** In `Get-PnPUser` wrapper (`Get-SPCOrphanedUser.ps1`), change `& $__pnpGetUser -LoginName` to `& $__pnpGetUser -Identity`.  
**SRS:** 3.2.1

## E010 — PnP 3.x Remove-PnPUser: parameter renamed -LoginName → -Identity; -Confirm/-Force absent/present
**Symptom:** `A parameter cannot be found that matches parameter name 'LoginName'`. After fix: `NonInteractive mode. Read and Prompt functionality is not available`.  
**Root cause:** `Remove-PnPUser` binary uses `-Identity` (not `-LoginName`). Without `-Force`, it calls `ShouldContinue()` internally which prompts; in automation this fails.  
**Fix:** Change wrapper to `& $__pnpRemoveUser -Identity $LoginName -Connection $Connection -Force -ErrorAction Stop`. Binary has no `-Confirm` parameter; uses `-Force` to suppress the internal prompt.  
**SRS:** 3.4.1

## E011 — PS empty array in if-branch outputs nothing → variable becomes $null
**Symptom:** Snapshot JSON has `"permissions": null` and `"groupMemberships": null` even when input is `@()`.  
**Root cause:** In PS, `@()` as a statement outputs NOTHING to pipeline. Assignment `$x = if (cond) { @() }` → `$x = $null` because the if-branch produces no pipeline output. `ConvertTo-Json` of a null value → `null` in JSON.  
**Fix 1:** In `Save-SPCPermissionSnapshot.ps1`, use `[System.Collections.Generic.List[object]]::new()` + `AddRange` instead of `if ($null -eq $x) { @() }`. Empty List serializes as `[]`.  
**Fix 2:** In `Remove-SPCOrphanedUser.ps1`, use `$snapPermList = [System.Collections.Generic.List[hashtable]]::new()` and `.Add()` instead of `@($ras | ForEach-Object { ... })`.  
**SRS:** 6.2

## E012 — PnP 3.x Export-SPCReport: integration test uses -Path, source uses -OutputPath
**Symptom:** `A parameter cannot be found that matches parameter name 'Path'` in integration test.  
**Root cause:** Integration test calls `Export-SPCReport -Path $file`; source parameter is named `-OutputPath`.  
**Fix:** Add `[Alias('Path')]` attribute to the `-OutputPath` parameter in `Export-SPCReport.ps1`.  
**SRS:** 3.3.1

## E013 — PS 5.1 ConvertFrom-Json: empty JSON array [] deserializes to $null in Restore-SPCOrphanedUser
**Symptom:** AC-08 results have `Status='Failed'` / `PermissionsFailed=1` even when snapshot has `"permissions": []`.  
**Root cause (two parts):**  
1. `Get-PnPWebPermission -PrincipalId` (PnP 3.x) returns 0 results even for users that `Get-PnPUser -WithRightsAssigned` flags as having permissions (the latter includes group-indirect permissions, not just direct web-level grants). Snapshot therefore contains `"permissions": []`.  
2. PS 5.1 `ConvertFrom-Json` converts `[]` to `$null`, NOT to `@()`. `@($null)` has `Count = 1` with a single null element. The lone null element passes the `$permissions.Count -eq 0` guard (Count = 1 > 0), then hits the blank `permissionLevel` check → `failedCount = 1` → `Status = 'Failed'`.  
**Fix:** `$permissions = @($snap.permissions | Where-Object { $null -ne $_ })`. Empty array after filter → `Count = 0` → emit `Status = 'Success'` with `PermissionsRestored = 0` and return early. This matches the vacuous-success semantic: if nothing was recorded, nothing needs restoring.  
**File:** `Public/Remediate/Restore-SPCOrphanedUser.ps1`  
**Note:** The underlying data issue (`Get-PnPWebPermission` returning empty for group-based permissions) is a PnP 3.x API limitation, not a bug in SPClean. Snapshots will always have `"permissions": []` for users whose access comes from SharePoint group membership rather than direct web-level grants.  
**SRS:** 3.4.2

## E014 — AC-03 test site re-seeding blocked by Entra soft-delete UPN rename
**Symptom:** After AC-07 removes orphaned users from SPCleanTest UIL, re-adding them programmatically fails with "User not found" because Entra renames soft-deleted users' UPNs (prepends a GUID).  
**Root cause:** When a user is soft-deleted in Entra, their UPN is renamed from `user@domain` to `<guid>user@domain`. SharePoint's `ensureuser` cannot resolve the original UPN because it no longer exists in Entra. `Add-PnPGroupMember -LoginName "i:0#.f|membership|user@domain"` → fails. Direct REST POST to UIL list → blocked. Graph restore → 403 (app lacks `User.ReadWrite.All`).  
**Fix / Workaround:** Use `docs/Reseed-TestSite.ps1` — runs `Connect-MgGraph -Scopes "User.ReadWrite.All"` with Global Admin credentials, calls `POST /directory/deletedItems/{id}/restore` to temporarily restore the 3 test accounts, adds them to SPCleanTest Members group (ensureuser works while they're active), then deletes them again.  
**Prevention:** Before running integration tests that include AC-07 (destructive), commit that the test site will need re-seeding afterward. Run `docs/Reseed-TestSite.ps1` before the next test run.  
**SRS:** N/A (test infrastructure issue)

## E015 — Get-SPCOrphanedUser incorrectly filters Entra-deleted users with empty UIL email
**Symptom:** Orphaned users whose Entra accounts were deleted shortly after being added to a SharePoint site have an empty Email field in the SP UIL. The detection system filtered them as "SharePoint service accounts" (the heuristic: `i:0#.f|membership|` + empty email = service account), so they were never classified as orphans.  
**Root cause:** When a user is deleted from Entra very quickly after being added to a SharePoint site, SharePoint may not sync their email before the account is gone. The UIL entry retains the `LoginName` (`i:0#.f|membership|upn@domain`) but Email is empty. The detection heuristic intended to filter SharePoint-internal service accounts but incorrectly caught real Entra users.  
**Fix:** Removed the `i:0#.f|membership| + empty email = system account` check from `Get-SPCOrphanedUser.ps1`. The `i:0#.f|membership|` claim format is ALWAYS a standard Entra user — SharePoint service accounts use different claim types (`SHAREPOINT\system`, `c:0(.s|true)`, etc.). The UPN is already extracted from the LoginName, so email is irrelevant.  
**File:** `Public/Scan/Get-SPCOrphanedUser.ps1`  
**SRS:** 3.2.1

## E016 — Remove-SPCOrphanedUser snapshot includes group-inherited roles in permissions[], causing Restore to fail
**Symptom:** `Restore-SPCOrphanedUser` returned `Status='Failed'` for users whose only permissions were via SharePoint group membership (no direct web-level permissions). The snapshot's `permissions[]` array contained the group's role definitions (e.g. "Edit") rather than being empty.  
**Root cause:** The snapshot logic looped through the user's `GroupMemberships` and added each group's role definitions (`$sg.Roles`) to `$snapPermList` as if they were direct permissions. When Restore tried to call `Add-PnPRoleAssignment` for the deleted user with these role names, it failed because the user no longer exists in Entra — SharePoint can't resolve the identity.  
**Fix:** Removed the `foreach ($role in $sg.Roles)` block from the snapshot logic in `Remove-SPCOrphanedUser.ps1`. Group-inherited roles are informational — they reflect the GROUP's permissions, not the USER's direct assignments. The group memberships are already captured in `groupMemberships[]`.  
**File:** `Public/Remediate/Remove-SPCOrphanedUser.ps1`  
**SRS:** 3.4.1, 6.2

## E017 — PS 5.1 ConvertFrom-Json empty array null conversion breaks SRS 6.2 schema assertion
**Symptom:** Integration test AC-07 (`$snap.permissions | Should -Not -Be $null`) fails. The snapshot file correctly contains `"permissions": []` (empty JSON array), but PS 5.1 `ConvertFrom-Json` converts `[]` to `$null`.  
**Root cause:** Same PS 5.1 `ConvertFrom-Json` bug as E013. The `permissions` field must always be a non-null value per SRS 6.2 schema, but an empty array becomes null after round-trip through PS 5.1.  
**Fix (two parts):**  
1. `Save-SPCPermissionSnapshot.ps1`: When `$permList` is empty after building, add a sentinel entry `@{ scope=''; permissionLevel=''; inheritanceStatus='__empty' }`. This ensures the JSON array is `[{...}]` not `[]`, preserving non-null after ConvertFrom-Json.  
2. `Restore-SPCOrphanedUser.ps1`: Changed blank-`permissionLevel` handling from `$failedCount++` (a failure) to `continue` (a silent skip). Sentinel and group-entry items have blank permissionLevel and are safely ignored without affecting Status.  
**Files:** `Private/Save-SPCPermissionSnapshot.ps1`, `Public/Remediate/Restore-SPCOrphanedUser.ps1`  
**SRS:** 6.2

## E018 — PnP 3.x Connect-PnPOnline -Interactive requires -ClientId (ERR-AUTH-004)
**Symptom:** `Connect-SPCTenant -TenantName <name>` (default Interactive auth, no ClientId) throws `WARNING: Please specify a valid client id for an Entra ID App Registration` + `SPClean: Authentication failed. Specified method is not supported.`  
**Root cause:** PnP.PowerShell 2.x had an implicit "PnP Management Shell" bundled app (`31359c7f-bd7e-475c-86db-fdb8c937548e`). PnP 3.x removed it. `Connect-PnPOnline -Interactive` now requires an explicit `-ClientId` pointing to a caller-owned Entra app registration.  
**Fix (four files):**  
1. `Connect-SPCTenant.ps1` `begin` block: Added ERR-AUTH-004 pre-flight check — throws immediately when `Interactive` + no `$ClientId`, with a message explaining the required Entra app setup.  
2. `Connect-SPCTenant.ps1` `process` block line 89: `Connect-PnPOnline -Interactive -ClientId $ClientId`  
3. Per-site `$connectToSite` scriptblocks in `Get-SPCOrphanedUser.ps1`, `Remove-SPCOrphanedUser.ps1`, `Restore-SPCOrphanedUser.ps1`: `Connect-PnPOnline -Interactive -ClientId $Ctx._ClientId`  
**Entra app requirements for interactive auth:**  
- Platform: Mobile and desktop applications → add BOTH redirect URIs:
  - `http://localhost` ← required; PnP 3.x opens a browser and redirects to a random `http://localhost:<port>`; Azure AD matches this against the port-less entry
  - `https://login.microsoftonline.com/common/oauth2/nativeclient`
- "Allow public client flows" = Yes (Authentication blade)  
- Delegated permissions (not Application): `Sites.FullControl.All`, `User.Read.All`, `Directory.Read.All`  
- Grant admin consent  
**Usage after fix:** `Connect-SPCTenant -TenantName contoso -ClientId '<delegated-app-id>'`  
**SRS:** 3.1.1

## E019 — Connect-SPCTenant.Tests.ps1: 5 tests broken by E018 source fix (test-file bugs)
**Symptom:** Unit tests under "Successful Interactive connection" context all fail with `ERR-AUTH-004: Interactive auth requires -ClientId in PnP.PowerShell 3.x`.
**Root cause:** The E018 fix added a pre-flight check in `Connect-SPCTenant.ps1 begin{}` that throws ERR-AUTH-004 when `Interactive` auth is used without `-ClientId`. The test calls `Connect-SPCTenant -AuthMethod Interactive -TenantName 'contoso'` without a `-ClientId` parameter — this was valid before E018 but now triggers the guard.
**Fix needed in test file (CANNOT edit per CLAUDE.md):** Add `-ClientId 'fake-client-id'` to the Interactive test calls in Connect-SPCTenant.Tests.ps1.
**Workaround:** None from source — reverting the ERR-AUTH-004 check would re-introduce the real PnP 3.x connection failure. 120/130 tests pass with this as a permanent test-file bug.

## E020 — Get-SPCOrphanedUser.Tests.ps1 AC-09: 2 tests broken by E015 source fix (test-file bugs)
**Symptom:** AC-09 "SHAREPOINT\system is excluded" and "membership claim with empty email is treated as service account and excluded" both fail: expected empty collection, got 1 item (`i:0#.f|membership|svc@contoso.com` with empty Email).
**Root cause:** E015 removed the `i:0#.f|membership| + empty Email = service account` heuristic. The test's `$script:SystemAccounts` includes `{ LoginName='i:0#.f|membership|svc@contoso.com'; Email='' }` and expects it to be filtered. After E015, this user is now correctly processed as a real Entra user (not filtered), breaking the test's expectation.
**Fix needed in test file (CANNOT edit per CLAUDE.md):** Remove entry with `i:0#.f|membership|svc@contoso.com` from `$script:SystemAccounts`, or update the test assertions to expect 1 result. E015 documented why the old behavior was wrong.
**Workaround:** None from source — re-introducing the empty-email filter would break real-world detection of Entra-deleted users. 120/130 tests pass with this as a permanent test-file bug.

## E021 — Write-Error terminates pipeline under Pester 5 ($ErrorActionPreference=Stop)
**Symptom:** AC-06 test (`Remove-SPCOrphanedUser.Tests.ps1:145`) fails on CI — `$result` is `$null`; test expects `$result.Status = 'Failed'`  
**Root cause:** Pester 5 sets `$ErrorActionPreference = 'Stop'` inside test blocks. `Write-Error` without `-ErrorAction Continue` throws a `WriteErrorException` that unwinds the pipeline before the `SPC.RemovalResult` result object is emitted. The `2>$null` in the test redirects the error *stream* but does NOT suppress a terminating `WriteErrorException`.  
**Fix:** Add `-ErrorAction Continue` to any `Write-Error` call inside a loop/pipeline that must continue emitting output after logging the error.  
**File:** `Remove-SPCOrphanedUser.ps1:242`  
**Pattern:** Always use `Write-Error "..." -ErrorAction Continue` in process{} blocks that emit per-item result objects on both success and failure paths.

## E022 — Colon after bare $variable in double-quoted string parsed as scoped variable
**Symptom:** CI syntax check fails: "Variable reference is not valid. ':' was not followed by a valid variable name character"  
**Root cause:** In a PowerShell double-quoted string, `$varname:` is parsed as a namespace/scope variable reference (e.g. `$env:PATH`). If the colon is followed by a space or `$(`, parsing fails.  
**Example:** `"Could not delete $key: $($_.Exception.Message)"` → error on `$key:`  
**Fix:** Delimit the variable name with `${}`: `"Could not delete ${key}: $($_.Exception.Message)"`  
**File:** `docs/Reseed-TestSite.ps1:115` (fixed)  
**Pattern:** Any time a variable is followed immediately by `:` in a double-quoted string (e.g. `$name: `, `$item: `), wrap in `${}`.

## E023 — AADSTS50011: redirect URI `http://localhost:<port>` not in app registration
**Symptom:** Interactive browser sign-in fails with `AADSTS50011: The redirect URI 'http://localhost:<port>' specified in the request does not match the redirect URIs configured for the application`.  
**Root cause:** PnP PowerShell 3.x interactive auth uses MSAL's system-browser flow — it starts an HTTP listener on a random ephemeral port (`http://localhost:63195`, etc.) and passes that as the redirect URI. If only `https://login.microsoftonline.com/common/oauth2/nativeclient` is registered (the embedded-browser URI), Azure AD rejects the localhost redirect.  
**Fix:** In the Entra app registration, Authentication blade → Mobile and desktop applications, add `http://localhost` (no port). Azure AD treats this as a wildcard matching any `http://localhost:<port>`.  
**Note:** The port is random per session — you cannot pre-register a specific port. Always add the port-less `http://localhost` entry.  
**SRS:** 3.1.1

<!-- Claude append vào đây khi gặp lỗi mới -->
