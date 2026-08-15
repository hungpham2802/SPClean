function Invoke-SPCVersionTrimmingInternal {
    <#
    .SYNOPSIS
        Executes file version trimming across document libraries.
    .DESCRIPTION
        Trims historical versions exceeding KeepVersions limit and optionally adjusts library major version limit.
    .OUTPUTS
        [PSCustomObject] with LibrariesProcessed, FilesOptimizedCount, VersionsRemovedCount, StorageFreedMB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter()] [string[]]$LibraryTitle,
        [Parameter(Mandatory)] [int]$KeepVersions,
        [Parameter(Mandatory)] [int]$OlderThanDays,
        [Parameter(Mandatory)] [bool]$ApplyPolicy,
        [Parameter(Mandatory)] [bool]$DryRun,
        [Parameter(Mandatory)] [string]$AuditLogPath
    )

    begin {
        $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
        $librariesProcessed = 0
        $filesOptimized = 0
        $versionsRemoved = 0
        $freedBytes = [int64]0
        $now = (Get-Date).ToUniversalTime()

        $operatorUPN = if ($script:SPCContext -and -not [string]::IsNullOrWhiteSpace($script:SPCContext.OperatorUPN)) {
            $script:SPCContext.OperatorUPN
        } elseif ($script:SPCContext -and $script:SPCContext.TenantName) {
            "admin@$($script:SPCContext.TenantName).onmicrosoft.com"
        } else {
            'System'
        }
    }

    process {
        $lists = Get-PnPList -Connection $siteConn

        $docLibs = @()
        if ($null -ne $lists) {
            $docLibs = @($lists | Where-Object {
                $_.BaseTemplate -eq 101 -and -not $_.Hidden -and
                $_.Title -notin @('FormServerTemplates', 'Style Library', 'PreservationHoldLibrary', 'Preservation Hold Library', 'Site Assets', 'Site Pages')
            })
        }

        if ($LibraryTitle) {
            $docLibs = @($docLibs | Where-Object { $_.Title -in $LibraryTitle })
        }

        foreach ($lib in $docLibs) {
            $librariesProcessed++
            
            # Update Library MajorVersionLimit if requested and not simulation
            if ($ApplyPolicy -and -not $DryRun) {
                Set-PnPList -Identity $lib -MajorVersions $KeepVersions -Connection $siteConn -ErrorAction SilentlyContinue
            }

            Write-Verbose "Optimizing Library '$($lib.Title)' on $SiteUrl"
            $items = Get-PnPListItem -List $lib -Connection $siteConn -PageSize 500
            
            if ($null -ne $items) {
                foreach ($item in $items) {
                    if ($item.FileSystemObjectType -eq 'File') {
                        $file = Get-PnPProperty -ClientObject $item -Property File -Connection $siteConn
                        $versions = Get-PnPProperty -ClientObject $file -Property Versions -Connection $siteConn
                        
                        if ($null -ne $versions -and $versions.Count -gt $KeepVersions) {
                            $filesOptimized++
                            $toRemove = $versions | Select-Object -First ($versions.Count - $KeepVersions)
                            
                            foreach ($ver in $toRemove) {
                                $verSize = [int64]$ver.Length
                                $itemLeaf = if ($null -ne $item['FileLeafRef']) { $item['FileLeafRef'] } else { 'File' }
                                $itemRef = if ($null -ne $item['FileRef']) { $item['FileRef'] } else { '' }
                                $verCreatedBy = if ($ver.CreatedBy -and $ver.CreatedBy.Email) { $ver.CreatedBy.Email } else { 'Unknown' }

                                if ($DryRun) {
                                    Write-SPCAuditLogInternal `
                                        -LogPath $AuditLogPath `
                                        -SiteUrl $SiteUrl `
                                        -TargetType 'FileVersion' `
                                        -ItemId "$($item.Id)_$($ver.VersionLabel)" `
                                        -ItemTitle "$itemLeaf (v$($ver.VersionLabel))" `
                                        -FileRelativeUrl $itemRef `
                                        -SizeBytes $verSize `
                                        -DeletedDate $ver.Created `
                                        -DeletedByUPN $verCreatedBy `
                                        -OperatorUPN $operatorUPN `
                                        -ExecutionStatus 'SIMULATED' `
                                        -ErrorMessage ''

                                    $freedBytes += $verSize
                                    $versionsRemoved++
                                } else {
                                    try {
                                        # CSOM Delete version
                                        $ver.DeleteObject()
                                        if ($siteConn.Context) {
                                            $siteConn.Context.ExecuteQuery()
                                        }

                                        Write-SPCAuditLogInternal `
                                            -LogPath $AuditLogPath `
                                            -SiteUrl $SiteUrl `
                                            -TargetType 'FileVersion' `
                                            -ItemId "$($item.Id)_$($ver.VersionLabel)" `
                                            -ItemTitle "$itemLeaf (v$($ver.VersionLabel))" `
                                            -FileRelativeUrl $itemRef `
                                            -SizeBytes $verSize `
                                            -DeletedDate $ver.Created `
                                            -DeletedByUPN $verCreatedBy `
                                            -OperatorUPN $operatorUPN `
                                            -ExecutionStatus 'SUCCESS' `
                                            -ErrorMessage ''

                                        $freedBytes += $verSize
                                        $versionsRemoved++
                                    }
                                    catch {
                                        Write-SPCAuditLogInternal `
                                            -LogPath $AuditLogPath `
                                            -SiteUrl $SiteUrl `
                                            -TargetType 'FileVersion' `
                                            -ItemId "$($item.Id)_$($ver.VersionLabel)" `
                                            -ItemTitle "$itemLeaf (v$($ver.VersionLabel))" `
                                            -FileRelativeUrl $itemRef `
                                            -SizeBytes $verSize `
                                            -DeletedDate $ver.Created `
                                            -DeletedByUPN $verCreatedBy `
                                            -OperatorUPN $operatorUPN `
                                            -ExecutionStatus 'FAILED' `
                                            -ErrorMessage $_.Exception.Message
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    end {
        return [PSCustomObject]@{
            LibrariesProcessed   = $librariesProcessed
            FilesOptimizedCount  = $filesOptimized
            VersionsRemovedCount = $versionsRemoved
            StorageFreedMB       = [Math]::Round(($freedBytes / 1MB), 2)
        }
    }
}
