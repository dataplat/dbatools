#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reports or reseeds a table's identity value. Port of public/Set-DbaDbIdentity.ps1; the workflow
/// remains a module-scoped PowerShell compatibility hop.
///
/// THREE locals are read on a path that does not assign them, so they carry between records:
/// $results, $identityValue and $columnValue are assigned ONLY inside the first ShouldProcess block
/// ("Execute the command ..."), but are read in the SECOND one ("Outputting object"), which is not
/// nested inside the first. When the execute gate is declined - which is exactly what -WhatIf does,
/// and what answering "no" at a High-impact prompt does - those three keep whatever the PREVIOUS
/// table, database, instance or pipeline record left in them, and the emitted object reports that
/// stale trio against the current table. That is the script function's real behaviour, so the port
/// reproduces it rather than tidying it: the three ride a sentinel emitted from a finally and are
/// re-seeded at the top of the next hop.
///
/// Carrying a plain $null is sufficient and no assigned/unassigned flag is needed: the source itself
/// assigns $null to $identityValue and $columnValue in its own else branch, so "never assigned" and
/// "assigned null" are already indistinguishable in the function world.
///
/// Because that state crosses instances as well as records, the hop stays WHOLE-ARRAY rather than
/// splitting per instance - the per-element rule's stated exemption for loops carrying
/// cross-instance state.
///
/// The source's begin block builds a StringBuilder holding the DBCC template. It folds into the top
/// of the hop rather than carrying: it is constructed fresh from a literal on every invocation, so
/// rebuilding per hop is identical to building once and cannot accumulate.
///
/// Test-Bound cannot ride the hop - inside one the caller is the scriptblock, not this cmdlet - so
/// all four call sites are flag-substituted. Both ShouldProcess gates are routed to the OUTER cmdlet
/// so -Confirm's "Yes to All" answer survives across pipeline records; ConfirmImpact is High here,
/// so that persistence matters.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record
/// re-enters the process body and re-evaluates the two reseed guards, warning again. Carrying a
/// latch would suppress warnings the function repeats.
///
/// The hop streams rather than buffers: each emitted object records a table that was actually
/// checked or reseeded.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbIdentity", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaDbIdentityCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases holding the table.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The table or tables to check or reseed.</summary>
    [Parameter(Position = 3)]
    public string[]? Table { get; set; }

    /// <summary>The value to reseed the identity to.</summary>
    [Parameter(Position = 4)]
    public int ReSeedValue { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The read-before-assign trio. See the class remarks: these are read in the output gate but
    // assigned only in the execute gate, so a declined execute gate reports the previous
    // iteration's values - across records included.
    private object? _results;
    private object? _identityValue;
    private object? _columnValue;
    private bool _hasCarry;

    protected override void ProcessRecord()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__setDbaDbIdentityState"]?.Value))
            {
                _results = item.Properties["Results"]?.Value;
                _identityValue = item.Properties["IdentityValue"]?.Value;
                _columnValue = item.Properties["ColumnValue"]?.Value;
                _hasCarry = true;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Database, Table, ReSeedValue, EnableException.ToBool(), this,
            _results, _identityValue, _columnValue, _hasCarry,
            TestBound(nameof(ReSeedValue)), TestBound(nameof(Database)), TestBound(nameof(Table)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's begin and process bodies VERBATIM. Substitutions only: $Pscmdlet ->
    // $__realCmdlet, the four Test-Bound call sites -> flags, and -FunctionName on
    // Stop-Function/Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $ReSeedValue, $EnableException, $__realCmdlet, $__carriedResults, $__carriedIdentityValue, $__carriedColumnValue, $__hasCarry, $__boundReSeedValue, $__boundDatabase, $__boundTable, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [int]$ReSeedValue, $EnableException, $__realCmdlet, $__carriedResults, $__carriedIdentityValue, $__carriedColumnValue, $__hasCarry, $__boundReSeedValue, $__boundDatabase, $__boundTable, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        # Restore the read-before-assign trio from the previous record. In the script function these
        # are function-scope, so a record whose execute gate is declined reports whatever the last
        # executed iteration left behind; a hop-local would report $null instead.
        if ($__hasCarry) {
            $results = $__carriedResults
            $identityValue = $__carriedIdentityValue
            $columnValue = $__carriedColumnValue
        }

            $stringBuilder = New-Object System.Text.StringBuilder
            $null = $stringBuilder.Append("DBCC CHECKIDENT(#options#)")

            if ($__boundReSeedValue) {
                if ((-not $__boundDatabase) -or (-not $__boundTable)) {
                    Stop-Function -Message "When using a reseed value you must specify a database and a table to execute against." -FunctionName Set-DbaDbIdentity
                    return
                }

                if (($Database.Count -gt 1) -or ($Table.Count -gt 1)) {
                    Stop-Function -Message "When using a reseed value you must specify a single database and a single table to execute against." -FunctionName Set-DbaDbIdentity
                    return
                }
            }

            foreach ($instance in $SqlInstance) {
                Write-Message -Message "Attempting Connection to $instance" -Level Verbose -FunctionName Set-DbaDbIdentity -ModuleName "dbatools"
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbIdentity
                }

                $dbs = $server.Databases

                if ($Database) {
                    $dbs = $dbs | Where-Object Name -In $Database
                }

                foreach ($db in $dbs) {
                    Write-Message -Level Verbose -Message "Processing $db on $instance" -FunctionName Set-DbaDbIdentity -ModuleName "dbatools"

                    if ($db.IsAccessible -eq $false) {
                        Stop-Function -Message "The database $db is not accessible. Skipping." -Continue -FunctionName Set-DbaDbIdentity
                    }

                    foreach ($tbl in $Table) {
                        try {
                            $query = $StringBuilder.ToString()
                            $nameParts = Get-ObjectNameParts -ObjectName $tbl
                            if ($nameParts.Name) {
                                $escapedTableName = $nameParts.Name.Replace("]", "]]")
                                if ($nameParts.Schema) {
                                    $escapedTableSchema = $nameParts.Schema.Replace("]", "]]")
                                    $tblIdentifier = "[$escapedTableSchema].[$escapedTableName]"
                                } else {
                                    $tblIdentifier = "[$escapedTableName]"
                                }
                            } else {
                                $tblIdentifier = $tbl
                            }
                            if (-not $__boundReSeedValue) {
                                $query = $query.Replace('#options#', "'$($tblIdentifier)'")
                            } else {
                                $query = $query.Replace('#options#', "'$($tblIdentifier)', RESEED, $($ReSeedValue)")
                            }

                            if ($__realCmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                                Write-Message -Message "Query to run: $query" -Level Verbose -FunctionName Set-DbaDbIdentity -ModuleName "dbatools"
                                $results = $server | Invoke-DbaQuery  -Query $query -Database $db.Name -MessagesToOutput
                                if ($null -ne $results) {
                                    $words = $results.Split(" ")
                                    $identityValue = $words[6].Replace("'", "").Replace(",", "")
                                    if (-not $__boundReSeedValue) {
                                        $columnValue = $words[10].Replace("'", "").Replace(".", "")
                                    } else {
                                        $columnValue = ''
                                    }

                                } else {
                                    $identityValue = $null
                                    $columnValue = $null
                                }
                            }
                        } catch {
                            Stop-Function -Message "Error running  $query against $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue -FunctionName Set-DbaDbIdentity
                        }
                        if ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
                            [PSCustomObject]@{
                                ComputerName  = $server.ComputerName
                                InstanceName  = $server.ServiceName
                                SqlInstance   = $server.DomainInstanceName
                                Database      = $db.Name
                                Table         = $tbl
                                Cmd           = $query.ToString()
                                IdentityValue = $identityValue
                                ColumnValue   = $columnValue
                                Output        = $results
                            }
                        }
                    }
                }
            }

    } finally {
        # From a finally: the two reseed guards return early, and the trio must survive those paths
        # exactly as the function's function-scope variables did.
        #
        # Read via Get-Variable rather than directly. This block is scaffolding the source does not
        # have, and it runs on EVERY path - including the guard returns, where the trio was never
        # created. The source only ever reads these behind its output gate, so a bare $results here
        # would read a non-existent variable on a path the function never reads it on, which under
        # StrictMode is an error rather than $null. Get-Variable -ErrorAction Ignore yields $null for
        # an uncreated variable and the value for a created one, so the carrier cannot introduce a
        # failure the function would not have had.
        [pscustomobject]@{
            __setDbaDbIdentityState = $true
            Results                 = (Get-Variable -Name 'results'       -Scope 0 -ValueOnly -ErrorAction Ignore)
            IdentityValue           = (Get-Variable -Name 'identityValue' -Scope 0 -ValueOnly -ErrorAction Ignore)
            ColumnValue             = (Get-Variable -Name 'columnValue'   -Scope 0 -ValueOnly -ErrorAction Ignore)
        }
    }
} $SqlInstance $SqlCredential $Database $Table $ReSeedValue $EnableException $__realCmdlet $__carriedResults $__carriedIdentityValue $__carriedColumnValue $__hasCarry $__boundReSeedValue $__boundDatabase $__boundTable $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
