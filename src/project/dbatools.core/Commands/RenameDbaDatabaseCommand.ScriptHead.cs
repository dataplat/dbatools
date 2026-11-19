#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Rename-DbaDatabase hop script, FIRST half (through #endregion logicalname). The
/// 620-line verbatim process body exceeds the 400-line file maximum on its own, so the
/// script is split at a region boundary into two compile-time-concatenated constants -
/// the joined text is byte-identical to the single-constant form (see the sibling
/// partial and RenameDbaDatabaseCommand.cs).
/// </summary>
public sealed partial class RenameDbaDatabaseCommand
{
    internal const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllDatabases, $DatabaseName, $FileGroupName, $LogicalName, $FileName, $ReplaceBefore, $Force, $Move, $SetOffline, $Preview, $InputObject, $EnableException, $__state, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases, [string]$DatabaseName, [string]$FileGroupName, [string]$LogicalName, [string]$FileName, $ReplaceBefore, $Force, $Move, $SetOffline, $Preview, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__state, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block lines that must live in the hop scope: the Copy-family ConfirmPreference
    # override (the INNER $PSCmdlet serves every gate - W3-005/W3-064 convention) and the
    # two helper functions (function definitions cannot cross hop scopes)
    if ($Force) { $ConfirmPreference = 'none' }

    $CurrentDate = $__state.CurrentDate

    # cross-record restore (B batch review, hop-scope-dies-per-record class): the source
    # fn scope leaks $Final_Renames (sole assignment guarded by !$failed -and $FileName,
    # read at output level) and $dirfiles (assigned in a try) across pipeline records,
    # and the inner $PSCmdlet's Yes/No-to-All ShouldProcess answer spans the pipeline in
    # the source (one CommandRuntime). The sentinel carries all three; the engine field
    # name is identical on PS 5.1 and PS 7 (transplant empirically verified).
    $__spField = $PSCmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Rename-DbaDatabase: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    $Final_Renames = $__state.Final_Renames
    $dirfiles = $__state.dirfiles
    if ($null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($PSCmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

        function Get-DbaNameStructure($database) {
            $obj = @()
            # db name
            $obj += "- Database : $database"
            # FileGroups
            foreach ($fg in $database.FileGroups) {
                $obj += "  - FileGroup: $($fg.Name)"
                # LogicalNames
                foreach ($ln in $fg.Files) {
                    $obj += "    - Logical: $($ln.Name)"
                    $obj += "      - FileName: $($ln.FileName)"
                }
            }
            $obj += "  - Logfiles"
            foreach ($log in $database.LogFiles) {
                $obj += "    - Logical: $($log.Name)"
                $obj += "      - FileName: $($log.FileName)"
            }
            return $obj -Join "`n"
        }


        function Get-DbaKeyByValue($hashtable, $Value) {
            ($hashtable.GetEnumerator() | Where-Object Value -eq $Value).Name
        }

    . {
        if ($__hopInterrupted) { return }
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database/ExcludeDatabase to continue" -FunctionName Rename-DbaDatabase
            return
        }
        if (!$DatabaseName -and !$FileGroupName -and !$LogicalName -and !$FileName) {
            Stop-Function -Message "You must specify at least one of -DatabaseName,-FileGroupName,-LogicalName or -Filename to continue" -FunctionName Rename-DbaDatabase
            return
        }
        $dbs = @()
        if ($InputObject) {
            if ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Rename-DbaDatabase
                }
                $all_dbs = $server.Databases | Where-Object IsAccessible
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }
                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # holds all dbs per instance to avoid naming clashes
        $InstanceDbs = @{ }

        # holds all db file enumerations (used for -Move only)
        $InstanceFiles = @{ }

        #region db loop
        foreach ($db in $dbs) {
            # used to stop futher operations on database
            $failed = $false

            # pending renames initialized at db level
            $Pending_Renames = @()

            $Entities_Before = @{ }

            $server = $db.Parent
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $($db.Name) is a system one, skipping..." -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                continue
            }
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $($db.Name) is not accessible, skipping..." -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                continue
            }
            if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $($db.Name) is either mirrored or in an AG, skipping..." -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                continue
            }
            $Server_Id = $server.DomainInstanceName
            if ( !$InstanceDbs.ContainsKey($Server_Id) ) {
                $InstanceDbs[$Server_Id] = @{ }
                foreach ($dn in $server.Databases.Name) {
                    $InstanceDbs[$Server_Id][$dn] = 1
                }
            }

            $Entities_Before['DBN'] = @{ }
            $Entities_Before['FGN'] = @{ }
            $Entities_Before['LGN'] = @{ }
            $Entities_Before['FNN'] = @{ }
            $Entities_Before['DBN'][$db.Name] = $db.Name
            #region databasename
            if ($DatabaseName) {
                $Orig_DBName = $db.Name
                # fixed replacements
                $NewDBName = $DatabaseName.Replace('<DBN>', $Orig_DBName).Replace('<DATE>', $CurrentDate)
                if ($Orig_DBName -eq $NewDBName) {
                    Write-Message -Level VeryVerbose -Message "Database name unchanged, skipping" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                } else {
                    if ($InstanceDbs[$Server_Id].ContainsKey($NewDBName)) {
                        Write-Message -Level Warning -Message "Database $NewDBName exists already, skipping this rename" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                        $failed = $true
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "Renaming Database $db to $NewDBName")) {
                            if ($Force) {
                                $server.KillAllProcesses($Orig_DBName)
                            }
                            try {
                                if (!$Preview) {
                                    $db.Rename($NewDBName)
                                }
                                $InstanceDbs[$Server_Id].Remove($Orig_DBName)
                                $InstanceDbs[$Server_Id][$NewDBName] = 1
                                $Entities_Before['DBN'][$Orig_DBName] = $NewDBName
                                #$db.Refresh()
                            } catch {
                                Stop-Function -Message "Failed to rename Database : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                                # stop any further renames
                                $failed = $true
                            }
                        }
                    }
                }
            }
            #endregion databasename
            #region filegroupname
            if ($ReplaceBefore) {
                #backfill PRIMARY
                $Entities_Before['FGN']['PRIMARY'] = 'PRIMARY'
                foreach ($fg in $db.FileGroups.Name) {
                    $Entities_Before['FGN'][$fg] = $fg
                }
            }

            if (!$failed -and $FileGroupName) {
                $Editable_FGs = $db.FileGroups | Where-Object Name -ne 'PRIMARY'
                $New_FGNames = @{ }
                foreach ($fg in $db.FileGroups.Name) {
                    $New_FGNames[$fg] = 1
                }
                $FGCounter = 0
                foreach ($fg in $Editable_FGs) {
                    $Orig_FGName = $fg.Name
                    $Orig_Placeholder = $Orig_FGName
                    if ($ReplaceBefore) {
                        # at Filegroup level, we need to worry about database name
                        $Orig_Placeholder = $Orig_Placeholder.Replace($Entities_Before['DBN'][$Orig_DBName], '')
                    }
                    $NewFGName = $FileGroupName.Replace('<DBN>', $Entities_Before['DBN'][$db.Name]).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $Orig_Placeholder)
                    $FinalFGName = $NewFGName
                    while ($fg.Name -ne $FinalFGName) {
                        if ($FinalFGName -in $New_FGNames.Keys) {
                            $FGCounter += 1
                            $FinalFGName = "$NewFGName$($FGCounter.ToString('000'))"
                        } else {
                            break
                        }
                    }
                    if ($fg.Name -eq $FinalFGName) {
                        Write-Message -Level VeryVerbose -Message "No rename necessary for FileGroup $($fg.Name) (on $db)" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess($db, "Renaming FileGroup $($fg.Name) to $FinalFGName")) {
                        try {
                            if (!$Preview) {
                                $fg.Rename($FinalFGName)
                            }
                            $New_FGNames.Remove($Orig_FGName)
                            $New_FGNames[$FinalFGName] = 1
                            $Entities_Before['FGN'][$Orig_FGName] = $FinalFGName
                        } catch {
                            Stop-Function -Message "Failed to rename FileGroup : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                            # stop any further renames
                            $failed = $true
                            break
                        }
                    }
                }
                #$db.FileGroups.Refresh()
            }

            #endregion filegroupname
            #region logicalname
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
            }
            if (!$failed -and $LogicalName) {
                $New_LogicalNames = @{ }
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                $LNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $logicalfiles = @($fg.Files)
                    for ($i = 0; $i -lt $logicalfiles.Count; $i++) {
                        $logical = $logicalfiles[$i]
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $Orig_LGName = $logical.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name
                            $dbKey = Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name
                            $fgKey = Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name
                            if ($dbKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($dbKey, '')
                            }
                            if ($fgKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($fgKey, '')
                            }
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        while ($logical.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logical.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary for LogicalFile $($logical.Name) (on FileGroup $($fg.Name) (on $db))" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile $($logical.Name) to $FinalLGName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                }
                #$fg.Files.Refresh()
                if (!$failed) {
                    $logfiles = @($db.LogFiles)
                    for ($i = 0; $i -lt $logfiles.Count; $i++) {
                        $logicallog = $logfiles[$i]
                        $Orig_LGName = $logicallog.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name, but for logfiles filegroup is not there
                            $dbKey = Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name
                            $fgKey = Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name
                            if ($dbKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($dbKey, '')
                            }
                            if ($fgKey) {
                                $Orig_Placeholder = $Orig_Placeholder.Replace($fgKey, '')
                            }
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                            '<FT>', 'LOG').Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        if ($FinalLGName.Length -eq 0) {
                            #someone passed in -LogicalName '<FGN>'.... but we don't have FGN here
                            $FinalLGName = $Orig_LGName
                        }
                        while ($logicallog.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logicallog.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No Rename necessary for LogicalFile log $($logicallog.Name) (LOG on (on $db))" -FunctionName Rename-DbaDatabase -ModuleName "dbatools"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile log $($logicallog.Name) to $FinalLGName (LOG)")) {
                            try {
                                if (!$Preview) {
                                    $logicallog.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Rename-DbaDatabase
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    #$db.Logfiles.Refresh()
                }
            }
            #endregion logicalname
""";
}
