#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Coordinates migration of SQL Agent objects and server properties. Port of
/// public/Copy-DbaAgentServer.ps1 (W2-008). The workflow remains a module-scoped PowerShell
/// compatibility hop so nested command order, refreshes, streams, and source quirks retain
/// engine semantics. The compiled cmdlet supplies the real outer ShouldProcess runtime. Surface
/// pinned by migration/baselines/Copy-DbaAgentServer.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaAgentServer",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentServerCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Disable copied jobs on each destination.</summary>
    [Parameter]
    public SwitchParameter DisableJobsOnDestination { get; set; }

    /// <summary>Disable copied jobs on the source.</summary>
    [Parameter]
    public SwitchParameter DisableJobsOnSource { get; set; }

    /// <summary>Skip SQL Agent server-property scripting.</summary>
    [Parameter]
    public SwitchParameter ExcludeServerProperties { get; set; }

    /// <summary>Request replacement of existing Agent objects.</summary>
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
            Source, SourceSqlCredential, Destination, DestinationSqlCredential,
            DisableJobsOnDestination.ToBool(), DisableJobsOnSource.ToBool(),
            ExcludeServerProperties.ToBool(), Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"), NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $DisableJobsOnDestination, $DisableJobsOnSource, $ExcludeServerProperties, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, $DisableJobsOnDestination, $DisableJobsOnSource, $ExcludeServerProperties, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaAgentServer
        return
    }
    $sourceAgent = $sourceServer.JobServer

    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaAgentServer
        }
        # All of these support whatif inside of them
        Copy-DbaAgentJobCategory -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force

        $destServer.Refresh()
        $destServer.JobServer.Refresh()
        $destServer.JobServer.JobCategories.Refresh()
        $destServer.JobServer.OperatorCategories.Refresh()
        $destServer.JobServer.AlertCategories.Refresh()

        Copy-DbaAgentOperator -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        $destServer.Refresh()
        $destServer.JobServer.Refresh()
        $destServer.JobServer.Operators.Refresh()

        # extra reconnect to force refresh
        $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential

        Copy-DbaAgentProxy -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        $destServer.JobServer.ProxyAccounts.Refresh()

        Copy-DbaAgentSchedule -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        $destServer.JobServer.SharedSchedules.Refresh()

        $destServer.JobServer.Refresh()
        $destServer.Refresh()
        # Copy jobs BEFORE alerts to ensure jobs exist when alerts with job associations are created
        Copy-DbaAgentJob -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource

        Copy-DbaAgentAlert -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force -IncludeDefaults
        $destServer.JobServer.Alerts.Refresh()

        # To do
        <#
        Copy-DbaAgentMasterServer -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        Copy-DbaAgentTargetServer -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        Copy-DbaAgentTargetServerGroup -Source $sourceServer -Destination $destinstance -DestinationSqlCredentia $DestinationSqlCredential -Force:$force
        #>

        <# Here are the properties which must be migrated separately #>
        $copyAgentPropStatus = [PSCustomObject]@{
            SourceServer      = $sourceServer.Name
            DestinationServer = $destServer.Name
            Name              = "Server level properties"
            Type              = "Agent Properties"
            Status            = $null
            Notes             = $null
            DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
        }

        if ($ExcludeServerProperties) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Skipping Agent Server property copy")) {
                $copyAgentPropStatus.Status = "Skipped"
                $copyAgentPropStatus.Notes = $null
                $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        } else {
            if ($__realCmdlet.ShouldProcess($destinstance, "Copying Agent Properties")) {
                try {
                    Write-Message -Level Verbose -Message "Copying SQL Agent Properties" -FunctionName Copy-DbaAgentServer -ModuleName "dbatools"
                    $sql = $sourceAgent.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                    $sql = $sql -replace [Regex]::Escape("@errorlog_file="), [Regex]::Escape("--@errorlog_file=")
                    $sql = $sql -replace [Regex]::Escape("@auto_start="), [Regex]::Escape("--@auto_start=")
                    Write-Message -Level Debug -Message $sql -FunctionName Copy-DbaAgentServer -ModuleName "dbatools"
                    $null = $destServer.Query($sql)
                    $copyAgentPropStatus.Status = "Successful"
                    $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $message = $_.Exception.InnerException.InnerException.InnerException.Message
                    if (-not $message) { $message = $_.Exception.Message }
                    $copyAgentPropStatus.Status = "Failed"
                    $copyAgentPropStatus.Notes = $message
                    $copyAgentPropStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue copying SQL Agent properties on $destinstance | $PSItem" -FunctionName Copy-DbaAgentServer -ModuleName "dbatools"
                    continue
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $DisableJobsOnDestination $DisableJobsOnSource $ExcludeServerProperties $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
