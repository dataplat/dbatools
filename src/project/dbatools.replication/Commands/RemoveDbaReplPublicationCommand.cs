#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a SQL Server replication publication. Port of public/Remove-DbaReplPublication.ps1. The
/// publication lookup (Get-DbaReplPublication), the REPL-LogReader job stop (Get-DbaAgentJob |
/// Stop-DbaAgentJob), the publication .Remove(), the SMO ReplicationDatabase disable of
/// transactional/merge publishing, and the result-object shaping all run the original PowerShell
/// body inside the dbatools module scope.
///
/// As with Remove-DbaReplArticle the function collects every publication across the whole pipeline
/// and only drops them in end, to avoid "Collection was modified" when piped from
/// Get-DbaReplPublication. The accumulator ($publications) is pipeline-spanning state a per-record
/// hop scope cannot hold, so it lives in C#: begin seeds an empty list, each process record
/// contributes its publications (bound InputObject, or a Get-DbaReplPublication lookup splatting
/// this cmdlet's own bound parameters), and the end hop drops the full list. The source's manual
/// "You must specify either SqlInstance or InputObject" guard (no parameter sets) runs at the top
/// of the process hop reading this cmdlet's bound hashtable.
///
/// The end hop supplies the real ShouldProcess runtime (ConfirmImpact High, no -Force) - the outer
/// publication-removal gate and the inner REPL-LogReader-stop gate both route to $__realCmdlet. The
/// source's undefined $Instance interpolations in two verbose messages are preserved verbatim
/// (bug-for-bug). Surface pinned by migration/baselines/Remove-DbaReplPublication.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaReplPublication", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaReplPublicationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database on the publisher that contains the publication.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>The name of the publication to remove.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>Publication objects piped in from Get-DbaReplPublication.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The pipeline-spanning accumulator: the source's begin "$publications = @()", filled across
    // process records, drained in end.
    private List<PSObject> _publications = null!;

    protected override void BeginProcessing()
    {
        _publications = new List<PSObject>();
    }

    protected override void ProcessRecord()
    {
        // Reproduce "$params = $PSBoundParameters" faithfully: this cmdlet's own bound parameters.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, InputObject, bound, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            if (item is not null)
            {
                _publications.Add(item);
            }
        }
    }

    protected override void EndProcessing()
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
        }, EndScript,
            _publications.ToArray(), SqlCredential, Database, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. Manual precondition guard first, then the block EMITS the publications
    // (bound InputObject, or a Get-DbaReplPublication lookup splatting the caller's bound parameters
    // minus InputObject/WhatIf/Confirm) which the C# accumulates across the pipeline.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__bound, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [psobject[]]$InputObject, [hashtable]$__bound, $EnableException)

    if (-not $__bound.SqlInstance -and -not $__bound.InputObject) {
        Stop-Function -Message "You must specify either SqlInstance or InputObject" -FunctionName Remove-DbaReplPublication
        return
    }

    if ($InputObject) {
        $InputObject
    } else {
        $params = $__bound
        $null = $params.Remove('InputObject')
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaReplPublication @params
    }
} $SqlInstance $InputObject $__bound $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess
    // and -FunctionName Remove-DbaReplPublication on the direct Stop-Function/Write-Message calls.
    // $publications is the accumulated list the C# collected across all process records.
    private const string EndScript = """
param($publications, $SqlCredential, $Database, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($publications, $SqlCredential, $Database, $EnableException, $__realCmdlet)

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaReplArticle.
    foreach ($pub in $publications) {
        if ($__realCmdlet.ShouldProcess($pub.Name, "Removing the publication $($pub.Name) on $($pub.SqlInstance)")) {
            $output = [PSCustomObject]@{
                ComputerName = $pub.ComputerName
                InstanceName = $pub.InstanceName
                SqlInstance  = $pub.SqlInstance
                Database     = $pub.DatabaseName
                Name         = $pub.Name
                Type         = $pub.Type
                Status       = $null
                IsRemoved    = $false
            }

            if ($pub.Type -in ('Transactional', 'Snapshot')) {
                try {
                    if ($pub.IsExistingObject) {
                        Write-Message -Level Verbose -Message "Removing $($pub.Name) from $($pub.SqlInstance).$($pub.DatabaseName)" -FunctionName Remove-DbaReplPublication -ModuleName "dbatools"

                        if ($__realCmdlet.ShouldProcess($pub.Name, "Stopping the REPL-LogReader job for the database $($pub.DatabaseName) on $($pub.SqlInstance)")) {
                            $null = Get-DbaAgentJob -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Category REPL-LogReader | Where-Object { $_.Name -like ('*{0}*' -f $pub.DatabaseName) } | Stop-DbaAgentJob
                        }
                        $pub.Remove()

                        $output.Status = "Removed"
                        $output.IsRemoved = $true
                    }
                } catch {
                    Stop-Function -Message "Failed to remove the publication from $($pub.SqlInstance)" -ErrorRecord $_ -FunctionName Remove-DbaReplPublication
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }

                try {
                    # If no other transactional publications exist for this database, the database can be disabled for transactional publishing
                    if (-not (Get-DbaReplPublication -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Database $pub.DatabaseName -Type Transactional, Snapshot -EnableException:$EnableException)) {
                        $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                        $pubDatabase.ConnectionContext = $pub.ConnectionContext
                        $pubDatabase.Name = $pub.DatabaseName
                        if (-not $pubDatabase.LoadProperties()) {
                            throw "Database $Database not found on $($pub.SqlInstance)"
                        }

                        if ($pubDatabase.EnabledTransPublishing) {
                            Write-Message -Level Verbose -Message "No transactional publications on $Instance.$Database so disabling transactional publishing" -FunctionName Remove-DbaReplPublication -ModuleName "dbatools"
                            $pubDatabase.EnabledTransPublishing = $false
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to disable transactional publishing on $($pub.SqlInstance)" -ErrorRecord $_ -FunctionName Remove-DbaReplPublication
                }

            } elseif ($pub.Type -eq 'Merge') {
                try {
                    if ($pub.IsExistingObject) {
                        Write-Message -Level Verbose -Message "Removing $($pub.Name) from $($pub.SqlInstance).$($pub.DatabaseName)" -FunctionName Remove-DbaReplPublication -ModuleName "dbatools"
                        if ($__realCmdlet.ShouldProcess($pub.Name, "Stopping the REPL-LogReader job for the database $($pub.DatabaseName) on $($pub.SqlInstance)")) {
                            $null = Get-DbaAgentJob -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Category REPL-LogReader | Where-Object { $_.Name -like ('*{0}*' -f $pub.DatabaseName) } | Stop-DbaAgentJob
                        }
                        $pub.Remove()

                        $output.Status = "Removed"
                        $output.IsRemoved = $true
                    } else {
                        Write-Warning "Didn't find $($pub.Name) on $($pub.SqlInstance).$($pub.DatabaseName)"
                    }
                } catch {
                    Stop-Function -Message "Failed to remove the publication from $($pub.SqlInstance)" -ErrorRecord $_ -FunctionName Remove-DbaReplPublication
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }

                try {
                    # If no other merge publications exist for this database, the database can be disabled for merge publishing
                    if (-not (Get-DbaReplPublication -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Database $pub.DatabaseName -Type Merge -EnableException:$EnableException)) {
                        $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                        $pubDatabase.ConnectionContext = $pub.ConnectionContext
                        $pubDatabase.Name = $pub.DatabaseName

                        if (-not $pubDatabase.LoadProperties()) {
                            throw "Database $Database not found on $instance"
                        }

                        if ($pubDatabase.EnabledTransPublishing) {
                            Write-Message -Level Verbose -Message "No merge publications on $Instance.$Database so disabling merge publishing" -FunctionName Remove-DbaReplPublication -ModuleName "dbatools"
                            $pubDatabase.EnabledMergePublishing = $false
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to disable transactional publishing on $($pub.SqlInstance)" -ErrorRecord $_ -FunctionName Remove-DbaReplPublication
                }
            }

            $output
        }
    }
} $publications $SqlCredential $Database $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
