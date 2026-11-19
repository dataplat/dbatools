#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds a table or other database object as an article to an existing replication publication.
/// Port of public/Add-DbaReplArticle.ps1. The whole process body rides ONE VERBATIM module
/// hop per pipeline record: the two pre-connection input guards (CreationScriptOptions type
/// check and the Filter-must-not-start-with-WHERE check, both Stop-Function -Continue with the
/// source's undefined $instance target preserved), the foreach over SqlInstance, the
/// Get-DbaReplServer / Get-DbaReplPublication / Get-DbaReplArticle calls (still module-scope
/// PowerShell), the SMO TransArticle / MergeArticle construction and .Create(), and the
/// trailing article refetch. $PSCmdlet.ShouldProcess routes to the real cmdlet via
/// $__realCmdlet so -WhatIf/-Confirm and yes/no-to-all persist across records; in-hop
/// Stop-Function/Write-Message carry -FunctionName and read $EnableException from the hop
/// param scope; merged-back 2&gt;&amp;1 records re-emit via WriteError with the silent-$error
/// compensation. No cross-record state (each SqlInstance record is self-contained). Surface
/// pinned by migration/baselines/Add-DbaReplArticle.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaReplArticle", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class AddDbaReplArticleCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance(s) for the publication.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database containing both the publication and the object to add as an article.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = null!;

    /// <summary>The name of the existing replication publication to add the article to.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Publication { get; set; } = null!;

    /// <summary>The schema name of the object to add as an article. Defaults to dbo.</summary>
    [Parameter(Position = 4)]
    public string Schema { get; set; } = "dbo";

    /// <summary>The name of the database object (typically a table) to add as an article.</summary>
    [Parameter(Mandatory = true, Position = 5)]
    [PsStringCast]
    public string Name { get; set; } = null!;

    /// <summary>A WHERE clause condition to horizontally filter which rows get replicated. Do not include the word WHERE.</summary>
    [Parameter(Position = 6)]
    public string? Filter { get; set; }

    /// <summary>Controls which schema elements get created on the subscriber. Build with New-DbaReplCreationScriptOptions.</summary>
    [Parameter(Position = 7)]
    public PSObject? CreationScriptOptions { get; set; }

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
        SqlInstance, SqlCredential, Database, Publication, Schema, Name, Filter, CreationScriptOptions,
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole process body VERBATIM in the dbatools module scope: the two input guards, the
    // per-instance foreach, the still-PS Get-DbaRepl* calls, the SMO article Create, and the
    // article refetch. ShouldProcess routes to the real cmdlet; Stop-Function/Write-Message
    // carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Publication, $Schema, $Name, $Filter, $CreationScriptOptions, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $Publication, $Schema, $Name, $Filter, $CreationScriptOptions, $EnableException, $__realCmdlet)

    # Check that $CreationScriptOptions is a valid object
    if ($CreationScriptOptions -and ($CreationScriptOptions -isnot [Microsoft.SqlServer.Replication.CreationScriptOptions])) {
        Stop-Function -Message "CreationScriptOptions should be the right type. Use New-DbaReplCreationScriptOptions to create the object" -Target $instance -Continue -FunctionName Add-DbaReplArticle
    }

    if ($Filter -like 'WHERE*') {
        Stop-Function -Message "Filter should not include the word 'WHERE'" -Target $instance -Continue -FunctionName Add-DbaReplArticle
    }

    foreach ($instance in $SqlInstance) {
        try {
            $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Add-DbaReplArticle
        }
        Write-Message -Level Verbose -Message "Adding article $Name to publication $Publication on $instance" -FunctionName Add-DbaReplArticle -ModuleName "dbatools"

        try {
            if ($__realCmdlet.ShouldProcess($instance, "Get the publication details for $Publication")) {

                $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $Publication -EnableException:$EnableException
                if (-not $pub) {
                    Stop-Function -Message "Publication $Publication does not exist on $instance" -Target $instance -Continue -FunctionName Add-DbaReplArticle
                }
            }
        } catch {
            Stop-Function -Message "Unable to get publication $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Add-DbaReplArticle
        }

        try {
            if ($__realCmdlet.ShouldProcess($instance, "Create an article object for $Publication which is a $($pub.Type) publication")) {

                $articleOptions = New-Object Microsoft.SqlServer.Replication.ArticleOptions

                if ($pub.Type -in ('Transactional', 'Snapshot')) {
                    $article = New-Object Microsoft.SqlServer.Replication.TransArticle
                    $article.Type = $ArticleOptions::LogBased
                } elseif ($pub.Type -eq 'Merge') {
                    $article = New-Object Microsoft.SqlServer.Replication.MergeArticle
                    $article.Type = $ArticleOptions::TableBased
                }

                $article.ConnectionContext = $replServer.ConnectionContext
                $article.Name = $Name
                $article.DatabaseName = $Database
                $article.SourceObjectName = $Name
                $article.SourceObjectOwner = $Schema
                $article.PublicationName = $Publication
            }
        } catch {
            Stop-Function -Message "Unable to create article object for $Name to add to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Add-DbaReplArticle
        }

        try {
            if ($CreationScriptOptions) {
                if ($__realCmdlet.ShouldProcess($instance, "Add creation options for article: $Name")) {
                    $article.SchemaOption = $CreationScriptOptions
                }
            }

            if ($Filter) {
                if ($__realCmdlet.ShouldProcess($instance, "Add filter for article: $Name")) {
                    $article.FilterClause = $Filter
                }
            }

            if ($__realCmdlet.ShouldProcess($instance, "Create article: $Name")) {
                if (-not ($article.IsExistingObject)) {
                    $article.Create()
                } else {
                    Stop-Function -Message "Article already exists in $Publication on $instance" -Target $instance -Continue -FunctionName Add-DbaReplArticle
                }

                if ($pub.Type -in ('Transactional', 'Snapshot')) {
                    $pub.RefreshSubscriptions()
                }
            }
        } catch {
            Stop-Function -Message "Unable to add article $Name to $Publication on $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Add-DbaReplArticle
        }
        Get-DbaReplArticle -SqlInstance $instance -SqlCredential $SqlCredential -Publication $Publication -Name $Name -EnableException:$EnableException
    }
} $SqlInstance $SqlCredential $Database $Publication $Schema $Name $Filter $CreationScriptOptions $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
