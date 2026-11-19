#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes the distribution database and configuration from an instance currently acting as a
/// replication distributor. Port of public/Disable-DbaReplDistributor.ps1. The whole process
/// body rides ONE VERBATIM module hop per pipeline record: the foreach over SqlInstance, the
/// Get-DbaReplServer lookup (still module-scope PowerShell), the IsDistributor branch that
/// stops distribution-database connections (Get-DbaProcess | Stop-DbaProcess) and calls the
/// SMO ReplicationServer.UninstallDistributor(Force), the Refresh + object emit, and the
/// non-distributor Stop-Function -Continue guard with the source's $instance target preserved.
/// $PSCmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet so -WhatIf/-Confirm and
/// yes/no-to-all persist across records; in-hop Stop-Function/Write-Message carry -FunctionName
/// and read $EnableException from the hop param scope; merged-back 2&gt;&amp;1 records re-emit via
/// WriteError with the silent-$error compensation. No cross-record state (each SqlInstance
/// record is self-contained; every Stop-Function is -Continue, which does not latch). Surface
/// pinned by migration/baselines/Disable-DbaReplDistributor.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaReplDistributor", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class DisableDbaReplDistributorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Forces removal of the distributor configuration even when dependent replication objects exist or remote publishers cannot be contacted.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
        SqlInstance, SqlCredential, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole process body VERBATIM in the dbatools module scope: the per-instance foreach,
    // the still-PS Get-DbaReplServer, the IsDistributor uninstall branch, the Refresh + emit,
    // and the non-distributor guard. ShouldProcess routes to the real cmdlet;
    // Stop-Function/Write-Message carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [bool]$Force, $EnableException, $__realCmdlet)

    foreach ($instance in $SqlInstance) {

        $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

        Write-Message -Level Verbose -Message "Disabling and removing replication distribution for $instance" -FunctionName Disable-DbaReplDistributor -ModuleName "dbatools"

        if ($replServer.IsDistributor) {
            try {
                if ($__realCmdlet.ShouldProcess($instance, "Disabling and removing distribution on $instance")) {
                    # remove any connections to the distribution database
                    $null = Get-DbaProcess -SqlInstance $instance -SqlCredential $SqlCredential -Database $replServer.DistributionDatabases.name -EnableException:$EnableException | Stop-DbaProcess -EnableException:$EnableException
                    # uninstall distribution
                    $replServer.UninstallDistributor($Force)
                }
            } catch {
                Stop-Function -Message "Unable to disable replication distribution" -ErrorRecord $_ -Target $instance -Continue -FunctionName Disable-DbaReplDistributor
            }

            $replServer.Refresh()
            $replServer

        } else {
            Stop-Function -Message "$instance isn't currently enabled for distributing." -Target $instance -Continue -FunctionName Disable-DbaReplDistributor
        }
    }
} $SqlInstance $SqlCredential $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
