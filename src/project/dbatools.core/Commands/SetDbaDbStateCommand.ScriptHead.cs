#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaDbState process hop script, FIRST half (through the MULTI_USER block). The
/// verbatim process body plus the begin-scope helper re-declarations exceed the 400-line
/// file maximum in one file, so the script is split at a block boundary into two
/// compile-time-concatenated constants (the W3-081 pattern) - the joined text is
/// byte-identical to the single-constant form (see SetDbaDbStateCommand.cs).
/// </summary>
public sealed partial class SetDbaDbStateCommand
{
    internal const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $AllDatabases, $ReadOnly, $ReadWrite, $Online, $Offline, $Emergency, $Detached, $SingleUser, $RestrictedUser, $MultiUser, $Force, $InputObject, $EnableException, $__state, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $AllDatabases, $ReadOnly, $ReadWrite, $Online, $Offline, $Emergency, $Detached, $SingleUser, $RestrictedUser, $MultiUser, $Force, [PSCustomObject[]]$InputObject, $EnableException, $__state, $__hopInterrupted, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block lines that must live in the hop scope: the Copy-family ConfirmPreference
    # override (the INNER $Pscmdlet serves every gate - W3-005/W3-064 convention) and the
    # helper functions/constants (definitions cannot cross hop scopes - W3-083 class)
    if ($Force) { $ConfirmPreference = 'none' }

    function Edit-DatabaseState($SqlInstance, $dbName, $opt, $immediate = $false) {
        $warn = $null
        $sql = "ALTER DATABASE [$dbName] SET $opt"
        if ($immediate) {
            $sql += " WITH ROLLBACK IMMEDIATE"
        } else {
            $sql += " WITH NO_WAIT"
        }
        try {
            Write-Message -Level System -Message $sql
            if ($immediate) {
                # this can be helpful only for SINGLE_USER databases
                # but since $immediate is called, it does no more harm
                # than the immediate rollback
                try {
                    $SqlInstance.KillAllProcesses($dbName)
                } catch {
                    Write-Message -Level Verbose -Message "KillAllProcesses failed, moving on to WITH ROLLBACK IMMEDIATE"
                }
            }
            $null = $SqlInstance.Query($sql)
        } catch {
            $warn = "Failed to set '$dbName' to $opt"
            Write-Message -Level Warning -Message $warn
        }
        return $warn
    }

    $statusHash = @{
        'Offline'       = 'OFFLINE'
        'Normal'        = 'ONLINE'
        'EmergencyMode' = 'EMERGENCY'
    }

    function Get-DbState($databaseName, $dbStatuses) {
        $base = $dbStatuses | Where-Object DatabaseName -ceq $databaseName
        foreach ($status in $statusHash.Keys) {
            if ($base.Status -match $status) {
                $base.Status = $statusHash[$status]
                break
            }
        }
        return $base
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaDbState: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__hopInterrupted) { return }
        if (Test-FunctionInterrupt) { return }
        $dbs = @()
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -FunctionName Set-DbaDbState
            return
        }

        if ($InputObject) {
            if ($InputObject.Database) {
                # comes from Get-DbaDbState
                $dbs += $InputObject.Database
            } elseif ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbState
                }
                $all_dbs = $server.Databases
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }

                if ($database) {
                    $dbs = $dbs | Where-Object { $database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # need to pick up here
        foreach ($db in $dbs) {
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $db is a system one, skipping" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                Continue
            }
            $dbStatuses = @{ }
            $server = $db.Parent
            if ($server -notin $dbStatuses.Keys) {
                $dbStatuses[$server] = Get-DbaDbState -SqlInstance $server
            }

            # normalizing properties returned by SMO to something more "fixed"
            $db_status = Get-DbState -DatabaseName $db.Name -dbStatuses $dbStatuses[$server]


            $warn = @()

            if ($db.DatabaseSnapshotBaseName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $db is a snapshot, skipping" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                Continue
            }

            if ($ReadOnly -eq $true) {
                if ($db_status.RW -eq 'READ_ONLY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_ONLY" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_ONLY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_ONLY" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_ONLY" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_ONLY'
                        }
                    }
                }
            }

            if ($ReadWrite -eq $true) {
                if ($db_status.RW -eq 'READ_WRITE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_WRITE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_WRITE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_WRITE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_WRITE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_WRITE'
                        }
                    }
                }
            }

            if ($Online -eq $true) {
                if ($db_status.Status -eq 'ONLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already ONLINE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to ONLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to ONLINE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "ONLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'ONLINE'
                        }
                    }
                }
            }

            if ($Offline -eq $true) {
                if ($db_status.Status -eq 'OFFLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already OFFLINE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to OFFLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to OFFLINE" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'OFFLINE'
                        }
                    }
                }
            }

            if ($Emergency -eq $true) {
                if ($db_status.Status -eq 'EMERGENCY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already EMERGENCY" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to EMERGENCY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to EMERGENCY" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "EMERGENCY" -immediate $Force
                        if (!$partial) {
                            $db_status.Status = 'EMERGENCY'
                        }
                    }
                }
            }

            if ($SingleUser -eq $true) {
                if ($db_status.Access -eq 'SINGLE_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already SINGLE_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to SINGLE_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to SINGLE_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "SINGLE_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'SINGLE_USER'
                        }
                    }
                }
            }

            if ($RestrictedUser -eq $true) {
                if ($db_status.Access -eq 'RESTRICTED_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already RESTRICTED_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to RESTRICTED_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to RESTRICTED_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "RESTRICTED_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'RESTRICTED_USER'
                        }
                    }
                }
            }

            if ($MultiUser -eq $true) {
                if ($db_status.Access -eq 'MULTI_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already MULTI_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to MULTI_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to MULTI_USER" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "MULTI_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'MULTI_USER'
                        }
                    }
                }
            }
""";
}
