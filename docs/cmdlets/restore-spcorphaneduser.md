# Restore-SPCOrphanedUser

Re-applies direct permission assignments from a JSON snapshot file created by `Remove-SPCOrphanedUser -CreateSnapshot`.

!!! info "License requirement"
    Requires a Pro or Consultant license.

## Synopsis

```powershell
Restore-SPCOrphanedUser
    -SnapshotPath <string>
    [-WhatIf]
    [-Confirm]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SnapshotPath` | `string` | ✅ | Full path to the `.json` snapshot file created by `Remove-SPCOrphanedUser -CreateSnapshot` |
| `-WhatIf` | switch | | Print what would be restored without making any changes |
| `-Confirm` | switch | | Prompt before applying each permission |

## Returns

`SPC.RestoreResult` with properties:

| Property | Description |
| --- | --- |
| `UserPrincipalName` | UPN of the user being restored |
| `SiteUrl` | Site where permissions are being re-applied |
| `PermissionsRestored` | Count of direct role assignments successfully re-applied |
| `PermissionsFailed` | Count of assignments that could not be re-applied |
| `Status` | `Success` or `Failed` |

## Limitations

!!! warning "What restore does NOT do"
    - **Group memberships are not re-applied.** SharePoint group memberships are recorded in the snapshot for reference but are not automatically restored. They must be re-added manually.
    - **Permanently deleted accounts cannot be restored.** If the user's Entra account was permanently deleted (after the 30-day soft-delete window), SharePoint cannot grant permissions to a non-existent identity. The restore will fail with an identity resolution error.
    - **Only direct role assignments are restored.** Permissions that came from group membership are not affected.

## Examples

=== "Preview restore"

    ```powershell
    Restore-SPCOrphanedUser `
        -SnapshotPath C:\Snapshots\user@contoso.com_20260622T120000Z.json `
        -WhatIf
    ```

=== "Restore"

    ```powershell
    Connect-SPCTenant -TenantName contoso -ClientId '<app-id>'
    Restore-SPCOrphanedUser `
        -SnapshotPath C:\Snapshots\user@contoso.com_20260622T120000Z.json
    Disconnect-SPCTenant
    ```

## See also

- [Remove-SPCOrphanedUser](remove-spcorphaneduser.md)
