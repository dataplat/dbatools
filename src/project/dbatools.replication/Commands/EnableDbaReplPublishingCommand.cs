#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures an instance already acting as a distributor to also act as a replication publisher.
/// Port of public/Enable-DbaReplPublishing.ps1. The whole process body rides ONE VERBATIM module
/// hop per pipeline record: the foreach over SqlInstance, the Get-DbaReplServer lookup (still
/// module-scope PowerShell), the IsDistributor branch that builds a DistributionPublisher (working
/// directory / snapshot share, publisher security, .Create() + Refresh + emit) across the source's
/// three ShouldProcess gates, and the non-distributor Stop-Function -Continue guard. The source's
/// `Test-Bound SnapshotShare -Not` (a boundness check, not a value check) is carried as the
/// $__boundSnapshotShare flag computed from the real cmdlet's MyInvocation.BoundParameters, since a
/// hop always receives the parameter positionally and could not otherwise tell whether the caller
/// supplied it. $PSCmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet so
/// -WhatIf/-Confirm and yes/no-to-all persist across records; in-hop Stop-Function/Write-Message
/// carry -FunctionName and read $EnableException from the hop param scope; merged-back 2&gt;&amp;1
/// records re-emit via WriteError with the silent-$error compensation. No cross-record state (each
/// SqlInstance record is self-contained; every Stop-Function is -Continue, which does not latch).
/// Surface pinned by migration/baselines/Enable-DbaReplPublishing.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaReplPublishing", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class EnableDbaReplPublishingCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The share used to store replication snapshots. Defaults to the instance's ReplData directory.</summary>
    [Parameter(Position = 2)]
    public string? SnapshotShare { get; set; }

    /// <summary>A SQL login used to configure publisher security instead of Windows authentication.</summary>
    [Parameter(Position = 3)]
    public PSCredential? PublisherSqlLogin { get; set; }

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
        SqlInstance, SqlCredential, SnapshotShare, PublisherSqlLogin, EnableException.ToBool(), this,
            MyInvocation.BoundParameters.ContainsKey("SnapshotShare"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole process body VERBATIM in the dbatools module scope: the per-instance foreach, the
    // still-PS Get-DbaReplServer, the IsDistributor publisher-configuration branch across three
    // ShouldProcess gates, and the non-distributor guard. ShouldProcess routes to the real cmdlet;
    // Test-Bound SnapshotShare -Not is the carried $__boundSnapshotShare flag; Stop-Function/
    // Write-Message carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $SnapshotShare, $PublisherSqlLogin, $EnableException, $__realCmdlet, $__boundSnapshotShare, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$SnapshotShare, $PublisherSqlLogin, $EnableException, $__realCmdlet, $__boundSnapshotShare)

    foreach ($instance in $SqlInstance) {

        $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

        Write-Message -Level Verbose -Message "Enabling replication publishing for $instance" -FunctionName Enable-DbaReplPublishing -ModuleName "dbatools"

        if ($replServer.IsDistributor) {
            try {
                if ($__realCmdlet.ShouldProcess($instance, "Getting distribution information on $instance")) {

                    $distPublisher = New-Object Microsoft.SqlServer.Replication.DistributionPublisher
                    $distPublisher.ConnectionContext = $replServer.ConnectionContext
                    $distPublisher.Name = $instance
                    $distPublisher.DistributionDatabase = $replServer.DistributionDatabases.Name

                    if (-not $__boundSnapshotShare) {
                        $SnapshotShare = Join-Path (Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential).InstallDataDirectory 'ReplData'
                        Write-Message -Level Verbose -Message ('No snapshot share specified, using default of {0}' -f $SnapshotShare) -FunctionName Enable-DbaReplPublishing -ModuleName "dbatools"
                    }

                    $distPublisher.WorkingDirectory = $SnapshotShare
                }

                if ($__realCmdlet.ShouldProcess($instance, "Configuring PublisherSecurity on $instance")) {
                    if ($PublisherSqlLogin) {
                        Write-Message -Level Verbose -Message "Configuring with a SQLLogin for PublisherSecurity" -FunctionName Enable-DbaReplPublishing -ModuleName "dbatools"
                        $distPublisher.PublisherSecurity.WindowsAuthentication = $false
                        $distPublisher.PublisherSecurity.SqlStandardLogin = $PublisherSqlLogin.UserName
                        $distPublisher.PublisherSecurity.SecureSqlStandardPassword = $PublisherSqlLogin.Password

                    } else {
                        Write-Message -Level Verbose -Message "Configuring with WindowsAuth for PublisherSecurity" -FunctionName Enable-DbaReplPublishing -ModuleName "dbatools"
                        $distPublisher.PublisherSecurity.WindowsAuthentication = $true
                    }
                }

                if ($__realCmdlet.ShouldProcess($instance, "Enable publishing on $instance")) {
                    Write-Message -Level Debug -Message $distPublisher -FunctionName Enable-DbaReplPublishing -ModuleName "dbatools"
                    # lots more properties to add as params
                    $distPublisher.Create()

                    $replServer.Refresh()
                    $replServer
                }

            } catch {
                Stop-Function -Message "Unable to enable replication publishing" -ErrorRecord $_ -Target $instance -Continue -FunctionName Enable-DbaReplPublishing
            }
        } else {
            Stop-Function -Message "$instance isn't currently enabled for distributing. Please enable that first." -Target $instance -Continue -FunctionName Enable-DbaReplPublishing
        }
    }
} $SqlInstance $SqlCredential $SnapshotShare $PublisherSqlLogin $EnableException $__realCmdlet $__boundSnapshotShare @__commonParameters 3>&1 2>&1
""";
}
