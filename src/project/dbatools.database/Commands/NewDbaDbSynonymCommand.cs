#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a synonym in one or more databases. Port of public/New-DbaDbSynonym.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
/// Structurally the New-DbaDbRole (W2-146) template - verified against this source, not assumed
/// from the resemblance.
///
/// NO INTERRUPT BRIDGE, deliberately. The FIVE guards at :157-180 are all Stop-Function WITHOUT
/// -Continue, so they DO set the module latch, but this source contains NO Test-FunctionInterrupt
/// anywhere to read it back. They therefore re-evaluate and warn on EVERY record, and bridging would
/// emit ONE warning where the source emits N. Bridge only where the SOURCE reads the latch back;
/// contrast W2-149, which reads it at :190 and does bridge.
///
/// NO CROSS-RECORD CARRY. Source :184 does "$InputObject += Get-DbaDatabase ..." and :188 reassigns
/// "$InputObject = $InputObject | Where-Object ...", but both target the PIPELINE-BOUND PARAMETER,
/// which the binder rewrites before every record, so neither can outlive its record. Confirmed
/// mechanically: migration/tools/Find-AccumulatorCarry.ps1 reports zero accumulator candidates.
/// $server (:191), $dbSynonyms (:194), $newSynonym (:205) and the loop variables $db and $syn are
/// each assigned before use within their own iteration.
///
/// NO Test-Bound SITES, so no caller-boundness flags. NO .IsPresent sites. NO preference-variable
/// assignment - checked with the UNANCHORED pattern, since the anchored one misses the
/// "if ($Force) { $ConfirmPreference = 'none' }" one-liner idiom entirely (see the W2-149 class and
/// its correction).
///
/// A SOURCE QUIRK RIDES VERBATIM, the same class as New-DbaDbRole's role message: the ShouldProcess
/// text at :203 interpolates $synonym, which PowerShell resolves case-insensitively to the PARAMETER
/// $Synonym rather than to $syn, the item actually being created. The prompt therefore names the
/// requested synonym rather than the current one. Preserved, not corrected; recorded here so no
/// reviewer reads it as port drift.
///
/// STREAMING, NOT BUFFERED (DEF-001): synonyms are created one at a time and each is emitted via
/// Select-DefaultView, so a buffered hop would discard the record of synonyms already created when a
/// later failure terminated the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :203 routes to the real cmdlet via $__realCmdlet, which
/// matters at ConfirmImpact Medium where the prompt is reachable at the default $ConfirmPreference.
/// The two in-loop Stop-Function calls (:198 synonym exists, :224 create failure) carry -Continue,
/// and because PowerShell's continue is dynamically scoped they skip the remainder of the caller's
/// iteration too (measured, migration/logs/probe-20260718-continue-propagation). EnableException
/// crosses as a SwitchParameter OBJECT received untyped, per B's combined rule. In-hop
/// Stop-Function/Write-Message calls carry -FunctionName. -BaseObject is Mandatory at position 9 and
/// -Schema defaults to "dbo". Implicit positions 0-10 are made explicit per the W2-071 law and were
/// CONFIRMED against the exported baseline. Surface pinned by migration/baselines/New-DbaDbSynonym.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbSynonym", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaDbSynonymCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the synonym is created in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The name of the synonym to create.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Synonym { get; set; }

    /// <summary>The schema that owns the synonym.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string Schema { get; set; } = "dbo";

    /// <summary>The server hosting the base object.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string? BaseServer { get; set; }

    /// <summary>The database hosting the base object.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string? BaseDatabase { get; set; }

    /// <summary>The schema hosting the base object.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    public string? BaseSchema { get; set; }

    /// <summary>The object the synonym points at.</summary>
    [Parameter(Mandatory = true, Position = 9)]
    [PsStringCast]
    public string BaseObject { get; set; } = null!;

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 10)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // Streaming, not buffered (DEF-001): synonyms are created and emitted one at a time, so a
        // buffered hop would drop the audit trail of synonyms already created.
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Synonym, Schema, BaseServer,
            BaseDatabase, BaseSchema, BaseObject, InputObject, EnableException, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM, dot-sourced so its five early returns exit only the body and
    // not the whole hop. Edits: the one $Pscmdlet gate routes to $__realCmdlet, and -FunctionName is
    // stamped on the nine Stop-Function/Write-Message calls. NO sentinel epilogue: this source never
    // reads the interrupt latch back (no Test-FunctionInterrupt), so its five guards must re-warn per
    // record exactly as they do here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Synonym, $Schema, $BaseServer, $BaseDatabase, $BaseSchema, $BaseObject, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [String]$Synonym, [String]$Schema, [String]$BaseServer, [String]$BaseDatabase, [String]$BaseSchema, [String]$BaseObject, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance." -FunctionName New-DbaDbSynonym
            return
        }

        if (-not $BaseObject) {
            Stop-Function -Message "You must provide base object name." -FunctionName New-DbaDbSynonym
            return
        }

        if ($BaseServer -and -not $BaseDatabase) {
            Stop-Function -Message "BaseServer parameter used - you must provide base database name." -FunctionName New-DbaDbSynonym
            return
        }

        if ($BaseDatabase -and -not $BaseSchema) {
            Stop-Function -Message "BaseDatabase parameter used - you must provide base schema name." -FunctionName New-DbaDbSynonym
            return
        }

        if (-not $Synonym) {
            Stop-Function -Message "You must specify a new synonym name." -FunctionName New-DbaDbSynonym
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $InputObject = $InputObject | Where-Object { $_.IsAccessible -eq $true }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Synonyms for $db on $server" -FunctionName New-DbaDbSynonym -ModuleName "dbatools"

            $dbSynonyms = $db.Synonyms

            foreach ($syn in $Synonym) {
                if ($dbSynonyms | Where-Object Name -EQ $syn) {
                    Stop-Function -Message "The $syn synonym already exist within database $db on instance $server." -Target $db -Continue -FunctionName New-DbaDbSynonym
                }

                Write-Message -Level Verbose -Message "Add synonyms to Database $db on target $server" -FunctionName New-DbaDbSynonym -ModuleName "dbatools"

                if ($__realCmdlet.ShouldProcess("Creating new Synonym $synonym on database $db", $server)) {
                    try {
                        $newSynonym = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Synonym
                        $newSynonym.Name = $syn
                        $newSynonym.Schema = $Schema
                        $newSynonym.Parent = $db

                        $newSynonym.BaseDatabase = $BaseDatabase
                        $newSynonym.BaseSchema = $BaseSchema
                        $newSynonym.BaseObject = $BaseObject
                        $newSynonym.BaseServer = $BaseServer

                        $newSynonym.Create()

                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name ParentName -Value $db.Name

                        Select-DefaultView -InputObject $newSynonym -Property ComputerName, InstanceName, SqlInstance, 'ParentName as Database', Name, Schema, BaseServer, BaseDatabase, BaseSchema, BaseObject
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaDbSynonym
                    }
                }
            }

        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Synonym $Schema $BaseServer $BaseDatabase $BaseSchema $BaseObject $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
