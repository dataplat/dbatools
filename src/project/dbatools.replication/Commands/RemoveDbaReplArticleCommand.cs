#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes an article from a SQL Server replication publication. Port of
/// public/Remove-DbaReplArticle.ps1. The article lookup (Get-DbaReplArticle), the
/// subscription drop (sp_dropsubscription via Invoke-DbaQuery), the article .Remove(), and the
/// result-object shaping all run the original PowerShell body inside the dbatools module scope.
///
/// The function deliberately collects every article across the whole pipeline in its
/// begin/process blocks and only drops them in end, to avoid "Collection was modified" when piped
/// directly from Get-DbaReplArticle. The accumulator ($articles) is pipeline-spanning state a
/// per-record hop scope cannot hold, so it lives in C#: begin seeds an empty list, each process
/// record contributes its articles (the bound InputObject in the pipeline case, or a
/// Get-DbaReplArticle lookup splatting this cmdlet's own bound parameters), and the end hop
/// receives the full list to drop. The source's manual "You must specify either SqlInstance or
/// InputObject" guard (source has NO parameter sets, per the dbatools Test-Bound convention) runs
/// at the top of the process hop and reads this cmdlet's bound-parameter hashtable, faithfully
/// reproducing $PSBoundParameters.SqlInstance / $PSBoundParameters.InputObject.
///
/// The end hop supplies the real ShouldProcess runtime (ConfirmImpact High, no -Force). The
/// source's undefined $PublicationName / $instance interpolations in the "Article doesn't exist"
/// message are preserved verbatim (bug-for-bug). Surface pinned by
/// migration/baselines/Remove-DbaReplArticle.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaReplArticle", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaReplArticleCommand : DbaBaseCmdlet
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

    /// <summary>The publication that contains the article to remove.</summary>
    [Parameter(Position = 3)]
    public string? Publication { get; set; }

    /// <summary>The schema of the article's source object.</summary>
    [Parameter(Position = 4)]
    public string Schema { get; set; } = "dbo";

    /// <summary>The name of the article to remove.</summary>
    [Parameter(Position = 5)]
    public string? Name { get; set; }

    /// <summary>Article objects piped in from Get-DbaReplArticle.</summary>
    [Parameter(Position = 6, ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The pipeline-spanning accumulator: the source's begin "$articles = @()", filled across
    // process records, drained in end.
    private List<PSObject> _articles = null!;

    protected override void BeginProcessing()
    {
        _articles = new List<PSObject>();
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
                _articles.Add(item);
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
            _articles.ToArray(), SqlCredential, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source's manual precondition guard runs first (reading the bound
    // hashtable). A compiled-cmdlet safety guard then refuses a direct lookup unless Database,
    // Publication, or Name supplies scope; InputObject remains exempt. The block EMITS the articles
    // (bound InputObject, or a Get-DbaReplArticle lookup that splats the caller's bound parameters
    // minus InputObject/WhatIf/Confirm exactly as the source's $PSBoundParameters re-splat did) and
    // the C# accumulates them across the pipeline.
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
        Stop-Function -Message "You must specify either SqlInstance or InputObject" -FunctionName Remove-DbaReplArticle
        return
    }

    if (-not $__bound.InputObject -and -not ($__bound.Database -or $__bound.Publication -or $__bound.Name)) {
        Stop-Function -Message "You must specify at least one of Database, Publication, or Name when using SqlInstance" -FunctionName Remove-DbaReplArticle
        return
    }

    if ($InputObject) {
        $InputObject
    } else {
        $params = $__bound
        $null = $params.Remove('InputObject')
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaReplArticle @params
    }
} $SqlInstance $InputObject $__bound $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess
    // and -FunctionName Remove-DbaReplArticle on the direct Stop-Function calls. $articles is the
    // accumulated list the C# collected across all process records. The source's undefined
    // $PublicationName / $instance in the "Article doesn't exist" message are preserved as-is.
    private const string EndScript = """
param($articles, $SqlCredential, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($articles, $SqlCredential, $EnableException, $__realCmdlet)

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaReplArticle.
    foreach ($art in $articles) {
        if ($__realCmdlet.ShouldProcess($art.Name, "Removing the article $($art.SourceObjectOwner).$($art.SourceObjectName) from the $($art.PublicationName) publication on $($art.SqlInstance)")) {
            $output = [pscustomobject]@{
                ComputerName = $art.ComputerName
                InstanceName = $art.InstanceName
                SqlInstance  = $art.SqlInstance
                Database     = $art.DatabaseName
                ObjectName   = $art.SourceObjectName
                ObjectSchema = $art.SourceObjectOwner
                Status       = $null
                IsRemoved    = $false
            }
            try {

                $pub = Get-DbaReplPublication -SqlInstance $art.SqlInstance -SqlCredential $SqlCredential -Database $art.DatabaseName -Name $art.PublicationName -EnableException:$EnableException

                if (($pub.Subscriptions | Measure-Object).count -gt 0 ) {
                    Write-Message -Level Verbose -Message ("There is a subscription so remove article {0} from subscription on {1}" -f $art.Name, $pub.Subscriptions.SubscriberName) -FunctionName Remove-DbaReplArticle -ModuleName "dbatools"
                    $query = "EXEC sp_dropsubscription @publication = '{0}', @article= '{1}',@subscriber = '{2}'" -f $art.PublicationName, $art.Name, $pub.Subscriptions.SubscriberName
                    Invoke-DbaQuery -SqlInstance $art.SqlInstance -SqlCredential $SqlCredential -Database $art.DatabaseName -query $query -EnableException:$EnableException
                }
                if (($art.IsExistingObject)) {
                    $art.Remove()
                } else {
                    Stop-Function -Message "Article doesn't exist in $PublicationName on $instance" -Target $instance -Continue -FunctionName Remove-DbaReplArticle
                }
                $output.Status = "Removed"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed to remove the article from publication" -ErrorRecord $_ -FunctionName Remove-DbaReplArticle
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $articles $SqlCredential $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
