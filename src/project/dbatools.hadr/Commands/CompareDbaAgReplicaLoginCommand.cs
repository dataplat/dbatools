#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares logins across the replicas of availability groups, reporting logins missing
/// from replicas and optionally modification-date drift. Port of
/// public/Compare-DbaAgReplicaLogin.ps1; surface pinned by
/// migration/baselines/Compare-DbaAgReplicaLogin.json.
/// </summary>
[Cmdlet(VerbsData.Compare, "DbaAgReplicaLogin")]
public sealed class CompareDbaAgReplicaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability groups.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Restricts the comparison to these availability groups.</summary>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Excludes system logins from the comparison.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemLogin { get; set; }

    /// <summary>Also reports modification-date drift for logins present on every replica.</summary>
    [Parameter]
    public SwitchParameter IncludeModifiedDate { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
            // capture (documented observability change, not behaviour); the parity runner strips the
            // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    return;
                }
                WriteObject(item);
            }, ProcessScript,
                new DbaInstanceParameter[] { instance }, SqlCredential, AvailabilityGroup,
                ExcludeSystemLogin.ToBool(), IncludeModifiedDate.ToBool(), EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source process foreach VERBATIM, one element per hop invocation (the
    // source loop line doubles as the guard loop for every Stop-Function -Continue
    // site). No begin block. Substitutions: five -FunctionName appends only - no gates,
    // no Test-Bound.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $ExcludeSystemLogin, $IncludeModifiedDate, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, $ExcludeSystemLogin, $IncludeModifiedDate, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure connecting to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Compare-DbaAgReplicaLogin
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue -FunctionName Compare-DbaAgReplicaLogin
            }

            $availabilityGroups = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $availabilityGroups = $availabilityGroups | Where-Object Name -in $AvailabilityGroup
            }

            if (-not $availabilityGroups) {
                Stop-Function -Message "No Availability Groups found on $instance matching the specified criteria." -Target $instance -Continue -FunctionName Compare-DbaAgReplicaLogin
            }

            foreach ($ag in $availabilityGroups) {
                $replicas = $ag.AvailabilityReplicas

                if ($replicas.Count -lt 2) {
                    Stop-Function -Message "Availability Group '$($ag.Name)' has less than 2 replicas. Nothing to compare." -Target $ag -Continue -FunctionName Compare-DbaAgReplicaLogin
                }

                $replicaInstances = @()
                foreach ($replica in $replicas) {
                    $replicaInstances += $replica.Name
                }

                $loginsByReplica = @{}
                $allLoginNames = New-Object System.Collections.ArrayList

                foreach ($replicaInstance in $replicaInstances) {
                    try {
                        $splatConnection = @{
                            SqlInstance   = $replicaInstance
                            SqlCredential = $SqlCredential
                        }
                        $replicaServer = Connect-DbaInstance @splatConnection

                        if ($ExcludeSystemLogin) {
                            $logins = Get-DbaLogin -SqlInstance $replicaServer -ExcludeSystemLogin
                        } else {
                            $logins = Get-DbaLogin -SqlInstance $replicaServer
                        }

                        if ($IncludeModifiedDate) {
                            $query = "SELECT name, modify_date FROM sys.server_principals WHERE [type] IN ('S', 'U', 'G')"
                            $modifyDates = Invoke-DbaQuery -SqlInstance $replicaServer -Query $query -As PSObject

                            $loginDetails = New-Object System.Collections.ArrayList
                            foreach ($login in $logins) {
                                $modifyDate = ($modifyDates | Where-Object name -eq $login.Name).modify_date
                                $null = $loginDetails.Add([PSCustomObject]@{
                                        Name        = $login.Name
                                        ModifyDate  = $modifyDate
                                        CreateDate  = $login.CreateDate
                                        LoginType   = $login.LoginType
                                    })
                            }
                            $loginsByReplica[$replicaInstance] = $loginDetails
                        } else {
                            $loginsByReplica[$replicaInstance] = $logins
                        }

                        foreach ($login in $logins) {
                            if ($login.Name -notin $allLoginNames) {
                                $null = $allLoginNames.Add($login.Name)
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to retrieve logins from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaLogin
                    }
                }

                foreach ($loginName in $allLoginNames) {
                    $differences = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        $login = $loginsByReplica[$replicaInstance] | Where-Object Name -eq $loginName

                        if (-not $login) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    LoginName         = $loginName
                                    Status            = "Missing"
                                    ModifyDate        = $null
                                    CreateDate        = $null
                                })
                        } elseif ($IncludeModifiedDate) {
                            $null = $differences.Add([PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    LoginName         = $loginName
                                    Status            = "Present"
                                    ModifyDate        = $login.ModifyDate
                                    CreateDate        = $login.CreateDate
                                })
                        }
                    }

                    if ($differences.Count -gt 0) {
                        $hasMissing = $differences | Where-Object Status -eq "Missing"

                        if ($hasMissing -or $IncludeModifiedDate) {
                            if ($IncludeModifiedDate) {
                                $dates = $differences | Where-Object Status -eq "Present" | Select-Object -ExpandProperty ModifyDate
                                $uniqueDates = $dates | Select-Object -Unique

                                if ($uniqueDates.Count -gt 1 -or $hasMissing) {
                                    foreach ($diff in $differences) {
                                        $diff
                                    }
                                }
                            } else {
                                foreach ($diff in $differences) {
                                    $diff
                                }
                            }
                        }
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $AvailabilityGroup $ExcludeSystemLogin $IncludeModifiedDate $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
