#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops database synonyms. Port of public/Remove-DbaDbSynonym.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// Process-only: the source has no begin or end block, so the hop is a single per-record
/// invocation. No local needs a cross-record carry - $input, $inputType, $dbSynonyms, $dbSynonym,
/// $db and $instance are each assigned and read inside one loop iteration, and $InputObject is
/// re-bound from the pipeline on every record before the body re-points it at $SqlInstance.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record
/// re-enters the process body and re-evaluates its input guard, warning again. Carrying a latch
/// would suppress warnings the function repeats. There are no Test-Bound call sites.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet. ConfirmImpact is High, so this command
/// prompts by default and -Confirm's "Yes to All" answer - which lives on the invoking runtime -
/// must survive between records rather than being forgotten by a per-record inner runtime.
///
/// Two source shapes ship unchanged because parity is the contract. The element loop variable is
/// $input, shadowing the PowerShell automatic; that was probed across the function,
/// module-scriptblock and production-hop shapes and behaves identically in all three, so it needs
/// no shim. And the default branch of the input-type switch does Stop-Function then a bare return,
/// which abandons the whole record rather than just that element.
///
/// The hop streams rather than buffers. This command DROPS synonyms and each emitted object records
/// one that was actually dropped, so a buffered invocation would discard the audit trail of
/// completed drops if a later synonym threw under -EnableException.
///
/// The termination BOUNDARY matters here. A failed DROP is caught by the body's own catch, which
/// reports it through Stop-Function - so under -WarningAction Stop the conversion happens on THAT
/// warning, inside the catch, and unwinds the loop from there. It has to convert in the body rather
/// than at the host after the loop has finished dropping, and NestedCommand.PropagateActionPreferences
/// is what makes it.
///
/// The integration leg feeds one parameter-bound array holding the same synonym twice followed by a
/// second one - the repeat DROP fails, which is this body's only reachable mid-loop failure. The
/// third element then going unreached shows only that the run stopped early, since a caller-side
/// conversion would leave it undropped too. What separates them is the terminating error's identity:
/// converting in the body raises from Write-Message, the cmdlet Stop-Function reports through, so
/// the error carries activity Write-Message and id ActionPreferenceStop,...WriteMessageCommand.
/// Measured in the function world. It is still UNRUN against this cmdlet - the shipped satellite
/// does not export it yet - so the assertion first bites at flip. -ErrorAction Stop is not
/// observable here: the body raises no non-terminating error, so binding it matches a plain run.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbSynonym", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbSynonymCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only these databases.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Only these schemas.</summary>
    [Parameter(Position = 4)]
    public string[]? Schema { get; set; }

    /// <summary>Skip these schemas.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeSchema { get; set; }

    /// <summary>Only these synonyms.</summary>
    [Parameter(Position = 6)]
    public string[]? Synonym { get; set; }

    /// <summary>Skip these synonyms.</summary>
    [Parameter(Position = 7)]
    public string[]? ExcludeSynonym { get; set; }

    /// <summary>Server, database or synonym objects.</summary>
    [Parameter(Position = 8, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Schema, ExcludeSchema, Synonym,
            ExcludeSynonym, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet so the
    // gate is owned by the outer cmdlet, and -FunctionName on Stop-Function/Write-Message. The body
    // is embedded WITHOUT added indentation, since indenting rewrites multi-line string literals.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Schema, $ExcludeSchema, $Synonym, $ExcludeSynonym, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Schema, [string[]]$ExcludeSchema, [string[]]$Synonym, [string[]]$ExcludeSynonym, [object[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a synonym, database, or server or specify a SqlInstance" -FunctionName Remove-DbaDbSynonym
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaDbSynonym -ModuleName "dbatools"
                    $dbSynonyms = Get-DbaDbSynonym -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Schema $Schema -ExcludeSchema $ExcludeSchema -Synonym $Synonym -ExcludeSynonym $ExcludeSynonym
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaDbSynonym -ModuleName "dbatools"
                    $dbSynonyms = Get-DbaDbSynonym -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Schema $Schema -ExcludeSchema $ExcludeSchema -Synonym $Synonym -ExcludeSynonym $ExcludeSynonym
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Remove-DbaDbSynonym -ModuleName "dbatools"
                    $dbSynonyms = Get-DbaDbSynonym -InputObject $input
                }
                'Microsoft.SqlServer.Management.Smo.Synonym' {
                    Write-Message -Level Verbose -Message "Processing DatabaseSynonym through InputObject" -FunctionName Remove-DbaDbSynonym -ModuleName "dbatools"
                    $dbSynonyms = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database synonym." -FunctionName Remove-DbaDbSynonym
                    return
                }
            }

            foreach ($dbSynonym in $dbSynonyms) {
                $db = $dbSynonym.Parent
                $instance = $db.Parent

                if ($__realCmdlet.ShouldProcess($instance, "Remove synonym $dbSynonym from database $db")) {

                    try {
                        # avoid enumeration issues
                        $db.Query("DROP SYNONYM $dbSynonym")
                        [PSCustomObject]@{
                            ComputerName = $db.ComputerName
                            InstanceName = $db.InstanceName
                            SqlInstance  = $db.SqlInstance
                            Database     = $db.Name
                            Synonym      = $dbSynonym
                            Status       = "Removed"
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbSynonym
                    }

                }

            }
        }

} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Schema $ExcludeSchema $Synonym $ExcludeSynonym $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
