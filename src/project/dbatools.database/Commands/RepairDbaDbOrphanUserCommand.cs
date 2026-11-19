#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Maps orphaned database users back to their logins. Port of
/// public/Repair-DbaDbOrphanUser.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// The hop runs once PER INSTANCE. The source foreaches $SqlInstance, keeps no cross-instance state
/// in that loop, and emits verbose output per database, so batching every instance into a single hop
/// would emit all of that verbose ahead of all results instead of interleaving per instance. Unlike
/// Set-DbaDbQueryStoreOption there is no pre-loop guard here, so the split needs no run-once
/// machinery: the process body IS the instance loop.
///
/// The source's begin block does one thing - "if ($Force) { $ConfirmPreference = 'none' }" - and it
/// folds into the top of the hop, since -Force is not a pipeline parameter and setting the
/// preference per invocation is identical to setting it once. That fold is sound because a
/// $ConfirmPreference set inside the hop still reaches a gate routed to the outer cmdlet -
/// ShouldProcess resolves the preference from the scope chain at call time, measured separately with
/// a failing control.
///
/// All three ShouldProcess gates are routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet),
/// which keeps -Confirm's "Yes to All" answer alive across pipeline records rather than letting a
/// per-record inner runtime forget it.
///
/// No local needs a cross-record carry, and the source is unusually explicit about it: $UsersToWork
/// is reset to $null at the end of every database iteration and $UsersToRemove is re-initialised to
/// @() before each user loop, so neither can leak forward. $DatabaseCollection, $db, $User,
/// $ExistLogin and $query are each assigned and read within one iteration, and $server is assigned
/// at the top of the instance loop whose failure path is Stop-Function -Continue, which skips every
/// remaining statement of that iteration including the reads.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record simply
/// re-enters the process body. Carrying a latch would suppress output the function repeats.
///
/// Note that BOTH -SqlInstance and -Users are ValueFromPipeline. That does not change the hop
/// design - each binds per record as usual - but it means a caller can pipe either, and the
/// per-instance split is over whatever -SqlInstance holds for the current record.
///
/// The hop streams rather than buffers. This command MUTATES server state (ALTER USER /
/// sp_change_users_login, and Remove-DbaDbOrphanUser under -RemoveNotExisting), and each emitted
/// object records a user that was actually remapped or reported, so a buffered invocation would
/// discard the records of completed repairs if a later database threw under -EnableException.
/// </summary>
[Cmdlet(VerbsDiagnostic.Repair, "DbaDbOrphanUser", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class RepairDbaDbOrphanUserCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only repair these databases.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only repair these users.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public object[]? Users { get; set; }

    /// <summary>Drop orphaned users that have no matching login.</summary>
    [Parameter]
    public SwitchParameter RemoveNotExisting { get; set; }

    /// <summary>Force the removal, including dependent objects.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // One hop PER INSTANCE, not one for the whole array: the instance loop keeps no
        // cross-instance state and emits verbose per database, so a single hop would batch that
        // verbose ahead of all output. The body still foreaches $SqlInstance, so a single-element
        // array runs exactly one iteration.
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            if (Interrupted)
                return;

            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    return;
                }
                WriteObject(item);
            }, BodyScript,
                new[] { instance }, SqlCredential, Database, ExcludeDatabase, Users,
                RemoveNotExisting, Force, EnableException.ToBool(), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source's begin line followed by its process body VERBATIM. Substitutions only:
    // $Pscmdlet -> $__realCmdlet, and -FunctionName on Stop-Function/Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Users, $RemoveNotExisting, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$Users, $RemoveNotExisting, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

            if ($Force) { $ConfirmPreference = 'none' }


            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Repair-DbaDbOrphanUser
                }

                $DatabaseCollection = $server.Databases | Where-Object IsAccessible

                if ($Database) {
                    $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
                }
                if ($ExcludeDatabase) {
                    $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
                }

                if ($DatabaseCollection.Count -gt 0) {
                    foreach ($db in $DatabaseCollection) {
                        try {

                            Write-Message -Level Verbose -Message "Validating users on database '$db'." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"

                            $UsersToWork = (Get-DbaDbOrphanUser -SqlInstance $server -Database $db.Name).SmoUser
                            if ($Users.Count -gt 0) {
                                $UsersToWork = $UsersToWork | Where-Object { $Users -contains $_.Name }
                            }

                            if ($UsersToWork.Count -gt 0) {
                                Write-Message -Level Verbose -Message "Orphan users found" -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                                $UsersToRemove = @()
                                foreach ($User in $UsersToWork) {
                                    $ExistLogin = $server.logins | Where-Object {
                                        $_.Isdisabled -eq $False -and
                                        $_.IsSystemObject -eq $False -and
                                        $_.IsLocked -eq $False -and
                                        $_.Name -eq $User.Name
                                    }

                                    if ($ExistLogin) {
                                        if ($server.versionMajor -gt 8) {
                                            $query = "ALTER USER " + $User + " WITH LOGIN = " + $User
                                        } else {
                                            $query = "EXEC sp_change_users_login 'update_one', '$User'"
                                        }

                                        if ($__realCmdlet.ShouldProcess($db.Name, "Mapping user '$($User.Name)'")) {
                                            $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                            Write-Message -Level Verbose -Message "User '$($User.Name)' mapped with their login." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"

                                            [PSCustomObject]@{
                                                ComputerName = $server.ComputerName
                                                InstanceName = $server.ServiceName
                                                SqlInstance  = $server.DomainInstanceName
                                                DatabaseName = $db.Name
                                                User         = $User.Name
                                                Status       = "Success"
                                            }
                                        }
                                    } else {
                                        if ($RemoveNotExisting) {
                                            #add user to collection
                                            $UsersToRemove += $User
                                        } else {
                                            Write-Message -Level Verbose -Message "Orphan user $($User.Name) does not have matching login." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                                            [PSCustomObject]@{
                                                ComputerName = $server.ComputerName
                                                InstanceName = $server.ServiceName
                                                SqlInstance  = $server.DomainInstanceName
                                                DatabaseName = $db.Name
                                                User         = $User.Name
                                                Status       = "No matching login"
                                            }
                                        }
                                    }
                                }

                                #With the collection complete invoke remove.
                                if ($RemoveNotExisting) {
                                    if ($Force) {
                                        if ($__realCmdlet.ShouldProcess($db.Name, "Remove-DbaDbOrphanUser")) {
                                            Write-Message -Level Verbose -Message "Calling 'Remove-DbaDbOrphanUser' with -Force." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                                            Remove-DbaDbOrphanUser -SqlInstance $server -Database $db.Name -User $UsersToRemove -Force
                                        }
                                    } else {
                                        if ($__realCmdlet.ShouldProcess($db.Name, "Remove-DbaDbOrphanUser")) {
                                            Write-Message -Level Verbose -Message "Calling 'Remove-DbaDbOrphanUser'." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                                            Remove-DbaDbOrphanUser -SqlInstance $server -Database $db.Name -User $UsersToRemove
                                        }
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No orphan users found on database '$db'." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                            }
                            #reset collection
                            $UsersToWork = $null
                        } catch {
                            Stop-Function -Message $_ -Continue -FunctionName Repair-DbaDbOrphanUser
                        }
                    }
                } else {
                    Write-Message -Level Verbose -Message "There are no databases to analyse." -FunctionName Repair-DbaDbOrphanUser -ModuleName "dbatools"
                }
            }

} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Users $RemoveNotExisting $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
