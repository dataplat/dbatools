#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves synonym objects and metadata from databases. Port of public/Get-DbaDbSynonym.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port with TWO ValueFromPipeline parameters (SqlInstance pos0, InputObject pos8), the structural
/// twin of Get-DbaDbRole (W2-101) with additional schema/synonym filter parameters. The source CmdletBinding
/// declares SupportsShouldProcess (ConfirmImpact Low), mirrored on the compiled [Cmdlet] attribute, but the body
/// contains NO $PSCmdlet.ShouldProcess call (read-only Get), so there is NO $__realCmdlet substitution and
/// -WhatIf/-Confirm are accepted but gate nothing (faithful). The neither-piped guard (source 132) uses TRUTHINESS,
/// NOT Test-Bound; its Stop-Function (no -Continue) + bare return exits the hop scriptblock cleanly (the
/// bare-return law). The one continue (source 143) is inside foreach ($db) - loop-bound. All filters
/// (Synonym/ExcludeSynonym/Schema/ExcludeSchema) are truthiness-based. No accumulator, no interrupt, no Test-Bound.
/// The only edits are -FunctionName Get-DbaDbSynonym on the one Stop-Function and one Write-Message. Surface pinned
/// by migration/baselines/Get-DbaDbSynonym.json (positions 0-8, two VFP, SupportsShouldProcess ConfirmImpact Low).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbSynonym", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class GetDbaDbSynonymCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Filter to synonyms in the specified schema(s).</summary>
    [Parameter(Position = 4)]
    public string[]? Schema { get; set; }

    /// <summary>Exclude synonyms in the specified schema(s).</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeSchema { get; set; }

    /// <summary>Filter to the specified synonym(s) by name.</summary>
    [Parameter(Position = 6)]
    public string[]? Synonym { get; set; }

    /// <summary>Exclude the specified synonym(s) by name.</summary>
    [Parameter(Position = 7)]
    public string[]? ExcludeSynonym { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Schema, ExcludeSchema, Synonym, ExcludeSynonym,
            InputObject, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }
    // PS: the process block VERBATIM. Edit: -FunctionName Get-DbaDbSynonym on the one Stop-Function and one
    // Write-Message. The neither-piped guard uses truthiness (no Test-Bound); its bare return exits cleanly;
    // the one continue is inside foreach ($db) - loop-bound. No $PSCmdlet.ShouldProcess call in the body.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Schema, $ExcludeSchema, $Synonym, $ExcludeSynonym, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Schema, [string[]]$ExcludeSchema, [string[]]$Synonym, [string[]]$ExcludeSynonym, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance" -FunctionName Get-DbaDbSynonym
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.IsAccessible -eq $false) {
                continue
            }
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Synonyms for $db on $server" -FunctionName Get-DbaDbSynonym -ModuleName "dbatools"

            $dbSynonyms = $db.Synonyms

            if ($Synonym) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Name -in $Synonym }
            }

            if ($ExcludeSynonym) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Name -notin $ExcludeSynonym }
            }

            if ($Schema) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Schema -in $Schema }
            }

            if ($ExcludeSchema) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Schema -notin $ExcludeSchema }
            }

            foreach ($dbSynonym in $dbSynonyms) {
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name Database -Value $db.Name

                Select-DefaultView -InputObject $dbSynonym -Property "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "BaseServer", "BaseDatabase", "BaseSchema", "BaseObject"
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Schema $ExcludeSchema $Synonym $ExcludeSynonym $InputObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
