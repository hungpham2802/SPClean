# Remove-SPCOrphanedUser

Removes orphaned users from SharePoint User Information Lists (UILs) and revokes direct role assignments.

!!! warning "What this cmdlet does NOT do"
    - Does **not** delete accounts from Entra ID
    - Does **not** remove users from SharePoint groups
    - Direct role assignments are revoked; group-inherited access is not affected

!!! info "License requirement"
    `-CreateSnapshot` requires a Pro or Consultant license.  
    `-WhatIf` preview is always available on the Free tier.

## Synopsis

```powershell
Remove-SPCOrphanedUser
    -InputObject  <SPC.OrphanedUser[]>
    [-RiskLevel   HIGH | MEDIUM | LOW]
    [-OrphanType  Deleted | SoftDeleted | Disabled | GuestOrphaned]
    [-CreateSnapshot]
    [-SnapshotPath <string>]
    [-Force]
    [-WhatIf]
    [-Confirm]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-InputObject` | `SPC.OrphanedUser[]` | ✅ | Accepts pipeline input |
| `-RiskLevel` | `HIGH \| MEDIUM \| LOW` | | Only process orphans at this risk level |
| `-OrphanType` | `Deleted \| SoftDeleted \| Disabled \| GuestOrphaned` | | Filter by orphan type. Default: `Deleted` only |
| `-CreateSnapshot` | switch | | Save a JSON permission snapshot before each removal *(Pro/Consultant)* |
| `-SnapshotPath` | `string` | | Directory for snapshot files. Required when `-CreateSnapshot` is used |
| `-Force` | switch | | Suppress `-Confirm` prompts |
| `-WhatIf` | switch | | Print what would be removed without making any changes |
| `-Confirm` | switch | | Prompt before each removal |

## Returns

`SPC.RemovalResult` per processed record.

## Default behaviour

By default, only orphans with `OrphanType = Deleted` are processed. To include soft-deleted or disabled accounts, explicitly pass `-OrphanType`:

```powershell
Remove-SPCOrphanedUser -OrphanType Deleted,SoftDeleted,Disabled
```

## Examples

=== "WhatIf preview"

    ```powershell
    # See what would be removed — no changes made
    Get-SPCOrphanedUser -SiteUrl $url | Remove-SPCOrphanedUser -WhatIf
    ```

=== "Remove HIGH-risk with snapshot"

    ```powershell
    Get-SPCOrphanedUser -SiteUrl $url |
        Remove-SPCOrphanedUser -RiskLevel HIGH -CreateSnapshot -SnapshotPath C:\Snapshots
    ```

=== "Remove all orphan types"

    ```powershell
    # Use with care — processes SoftDeleted and Disabled as well
    Get-SPCOrphanedUser -SiteUrl $url -IncludeDisabled |
        Remove-SPCOrphanedUser -OrphanType Deleted,SoftDeleted,Disabled -CreateSnapshot -SnapshotPath C:\Snapshots
    ```

## Snapshot files

When `-CreateSnapshot` is used, one JSON file is written per user before removal:

```
C:\Snapshots\
    user@contoso.com_20260622T120000Z.json
    anotheruser@contoso.com_20260622T120001Z.json
```

Use `Restore-SPCOrphanedUser` to re-apply permissions from a snapshot.

## See also

- [Get-SPCOrphanedUser](get-spcorphaneduser.md)
- [Restore-SPCOrphanedUser](restore-spcorphaneduser.md)
- [Snapshot and recovery](../getting-started/quickstart.md#restore-after-accidental-removal)
