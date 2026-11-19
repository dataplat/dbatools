#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaDbState process hop script, SECOND half (the Detached block + the output
/// objects + the sentinel). See the sibling partial for the split rationale.
/// </summary>
public sealed partial class SetDbaDbStateCommand
{
    internal const string ProcessScriptTail = """

            if ($Detached -eq $true) {
                # Refresh info about database state here (before detaching)
                $db.Refresh()
                # we need to see what snaps are on the server, as base databases cannot be dropped
                $snaps = $server.Databases | Where-Object { $_.DatabaseSnapshotBaseName.Length -gt 0 }
                $snaps = $snaps.DatabaseSnapshotBaseName | Get-Unique
                if ($db.Name -in $snaps) {
                    Write-Message -Level Warning -Message "Database $db has snapshots, you need to drop them before detaching, skipping..." -FunctionName Set-DbaDbState -ModuleName "dbatools"
                    Continue
                }
                if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                    if ($Force -eq $false) {
                        Write-Message -Level Warning -Message "Needs -Force to detach $db, skipping" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        Continue
                    }
                }

                if ($db.IsMirroringEnabled) {
                    if ($Pscmdlet.ShouldProcess($server, "Break mirroring for $db")) {
                        try {
                            $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                            $db.Alter()
                            $db.Refresh()
                            Write-Message -Level VeryVerbose -Message "Broke mirroring for $db" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        } catch {
                            Stop-Function -Message "Could not break mirror for $db. Skipping." -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaDbState
                        }
                    }
                }

                if ($db.AvailabilityGroupName) {
                    $agname = $db.AvailabilityGroupName
                    if ($Pscmdlet.ShouldProcess($server, "Removing $db from AG [$agname]")) {
                        try {
                            $server.AvailabilityGroups[$db.AvailabilityGroupName].AvailabilityDatabases[$db.Name].Drop()
                            Write-Message -Level VeryVerbose -Message "Successfully removed $db from AG [$agname] on $server" -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        } catch {
                            Stop-Function -Message "Could not remove $db from AG [$agname] on $server" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaDbState
                        }
                    }
                }

                # DBA 101 should encourage detaching just OFFLINE databases
                # we can do that here
                if ($Pscmdlet.ShouldProcess($server, "Detaching $db")) {
                    if ($db_status.Status -ne 'OFFLINE') {
                        $null = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $true
                    }
                    try {
                        $sql = "EXEC master.dbo.sp_detach_db N'$($db.Name)'"
                        Write-Message -Level System -Message $sql -FunctionName Set-DbaDbState -ModuleName "dbatools"
                        $null = $server.Query($sql)
                        $db_status.Status = 'DETACHED'
                    } catch {
                        Stop-Function -Message "Failed to detach $db" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaDbState
                        $warn += "Failed to detach"
                    }

                }

            }
            if ($warn) {
                $warn = $warn | Where-Object { $_ } | Get-Unique
                $warn = $warn -Join ';'
            } else {
                $warn = $null
            }
            if ($Detached -eq $true) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $db_status.RW
                    Status       = $db_status.Status
                    Access       = $db_status.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            } else {
                $db.Refresh()
                if ($null -eq $warn) {
                    # we avoid reenumerating properties
                    $newstate = $db_status
                } else {
                    $newstate = Get-DbState -databaseName $db.Name -dbStatuses $dbStatuses[$server]
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $newstate.RW
                    Status       = $newstate.Status
                    Access       = $newstate.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            }
        }

    }

    @{ __w3090State = @{ interrupted = (Test-FunctionInterrupt); shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $AllDatabases $ReadOnly $ReadWrite $Online $Offline $Emergency $Detached $SingleUser $RestrictedUser $MultiUser $Force $InputObject $EnableException $__state $__hopInterrupted $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
