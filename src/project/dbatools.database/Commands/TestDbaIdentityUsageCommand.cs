#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reports how much of each identity column's value range has been consumed. Port of
/// public/Test-DbaIdentityUsage.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// -SqlInstance takes pipeline input, so the blocks are NOT folded the way a non-pipeline
/// command's would be, and the hop runs once PER INSTANCE rather than once per whole array: the
/// source foreaches $SqlInstance with no cross-instance state in the loop body, and a whole-array
/// hop would batch that loop's Verbose output ahead of all its result objects, where the script
/// function interleaves verbose-then-output for each instance in turn.
///
/// The source's begin block builds the $sql query text, and that construction is placed at the top
/// of the hop body instead of running as a separate begin hop. $sql is NOT parameter-independent -
/// begin appends either a "WHERE [PercentUsed] >= $Threshold ORDER BY" or a bare "ORDER BY" clause
/// to it. Rebuilding it per hop is still identical to building it once, for two reasons: -Threshold
/// is not a pipeline parameter, so it is bound once and every hop sees the same value; and the hop
/// re-assigns $sql from its string literal before appending, so the append can never compound the
/// way it would if $sql were carried across hops and appended to again.
///
/// No local needs a cross-record carry. Every process-block local ($instance, $server, $dbs, $db,
/// $results, $row) is assigned and read within the same loop iteration. $server is assigned in the
/// connection try and read further down, but every failure path is Stop-Function -Continue, which
/// skips the rest of that iteration before any read - so a stale $server is never observable.
///
/// Parameter positions are pinned from the golden baseline rather than left to default: a
/// PowerShell advanced function gets implicit positional binding, so the script function bound
/// SqlInstance/SqlCredential/Database/ExcludeDatabase/Threshold at positions 0-4. A compiled cmdlet
/// infers no position, so omitting these would silently reject positional calls the source
/// accepted. The two switches correctly carry no position.
///
/// $ExcludeSystem crosses into the hop as a plain bool, and the inner param block leaves it
/// UNTYPED. Declaring it [switch] there would make it skip positional binding and shift every
/// later argument by one.
///
/// The hop streams rather than buffers: the command emits one object per identity column and a
/// caller can legitimately stop early once a threshold breach is seen.
///
/// $EnableException is passed into the hop because Stop-Function's own parameter block defaults it
/// from the caller's scope. Every in-hop Stop-Function and Write-Message carries -FunctionName,
/// because both derive the reporting command from the call stack, which is a scriptblock in a hop.
///
/// The source declares plain [CmdletBinding()], so this cmdlet does NOT declare
/// SupportsShouldProcess. The bare "continue" in the row loop is an ordinary loop continue within
/// a single hop invocation, not a cross-record control-flow escape.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaIdentityUsage")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaIdentityUsageCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only check these databases.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only report columns at or above this percent-used value.</summary>
    [Parameter(Position = 4)]
    public int Threshold { get; set; }

    /// <summary>Exclude system databases.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystem { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // One hop PER INSTANCE, not one hop for the whole array: the source's instance loop keeps
        // no cross-instance state, and batching every instance into a single hop would emit that
        // loop's verbose messages ahead of all of its output instead of interleaving them per
        // instance the way the script function does. The body still foreaches $SqlInstance, so a
        // single-element array runs exactly one iteration.
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
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
                new[] { instance }, SqlCredential, Database, ExcludeDatabase, Threshold,
                ExcludeSystem.ToBool(), EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source's begin and process bodies VERBATIM, in that order. Substitutions only:
    // -FunctionName Test-DbaIdentityUsage on every Stop-Function and Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Threshold, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [int]$Threshold, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $sql = ";WITH CT_DT AS
        (
            SELECT 'tinyint' AS DataType, 0 AS MinValue ,255 AS MaxValue UNION
            SELECT 'smallint' AS DataType, -32768 AS MinValue ,32767 AS MaxValue UNION
            SELECT 'int' AS DataType, -2147483648 AS MinValue ,2147483647 AS MaxValue UNION
            SELECT 'bigint' AS DataType, -9223372036854775808 AS MinValue ,9223372036854775807 AS MaxValue
        ), CTE_1
        AS
        (
          SELECT SCHEMA_NAME(o.schema_id) AS SchemaName,
                 OBJECT_NAME(a.object_id) AS TableName,
                 a.name AS ColumnName,
                 seed_value AS SeedValue,
                 CONVERT(BIGINT, increment_value) AS IncrementValue,

                 CONVERT(BIGINT, ISNULL(a.last_value, seed_value)) AS LastValue,

                 (CASE
                        WHEN CONVERT(BIGINT, increment_value) < 0 THEN
                            (CONVERT(BIGINT, seed_value)
                            - CONVERT(BIGINT, ISNULL(last_value, seed_value))
                            + (CASE WHEN CONVERT(BIGINT, seed_value) <> 0 THEN ABS(CONVERT(BIGINT, increment_value)) ELSE 0 END))
                        ELSE
                            (CONVERT(BIGINT, ISNULL(last_value, seed_value))
                            - CONVERT(BIGINT, seed_value)
                            + (CASE WHEN CONVERT(BIGINT, seed_value) <> 0 THEN ABS(CONVERT(BIGINT, increment_value)) ELSE 0 END))
                    END) / ABS(CONVERT(BIGINT, increment_value))  AS NumberOfUses,

                  CAST (
                        (CASE
                            WHEN CONVERT(NUMERIC(20, 0), increment_value) < 0 THEN
                                ABS(CONVERT(NUMERIC(20, 0),dt.MinValue)
                                - CONVERT(NUMERIC(20, 0), seed_value)
                                - (CASE WHEN CONVERT(NUMERIC(20, 0), seed_value) <> 0 THEN ABS(CONVERT(NUMERIC(20, 0), increment_value)) ELSE 0 END))
                            ELSE
                                CONVERT(NUMERIC(20, 0),dt.MaxValue)
                                - CONVERT(NUMERIC(20, 0), seed_value)
                                + (CASE WHEN CONVERT(NUMERIC(20, 0), seed_value) <> 0 THEN ABS(CONVERT(NUMERIC(20, 0), increment_value)) ELSE 0 END)
                        END) / ABS(CONVERT(NUMERIC(20, 0), increment_value))
                    AS NUMERIC(20, 0)) AS MaxNumberRows

            FROM sys.identity_columns a
                INNER JOIN sys.objects o
                   ON a.object_id = o.object_id
                INNER JOIN sys.types AS b
                     ON a.system_type_id = b.system_type_id
                INNER JOIN CT_DT dt
                     ON b.name = dt.DataType
          WHERE a.seed_value IS NOT NULL
        ),
        CTE_2
        AS
        (
        SELECT SchemaName, TableName, ColumnName, CONVERT(BIGINT, SeedValue) AS SeedValue, CONVERT(BIGINT, IncrementValue) AS IncrementValue, LastValue, ABS(CONVERT(NUMERIC(20,0),MaxNumberRows)) AS MaxNumberRows, NumberOfUses,
               CONVERT(NUMERIC(18, 2), ((CONVERT(FLOAT, NumberOfUses) / ABS(CONVERT(NUMERIC(20, 0), NULLIF(MaxNumberRows,0))) * 100))) AS [PercentUsed]
          FROM CTE_1
        )
        SELECT DB_NAME() AS DatabaseName, SchemaName, TableName, ColumnName, SeedValue, IncrementValue, LastValue, MaxNumberRows, NumberOfUses, [PercentUsed]
          FROM CTE_2"

        if ($Threshold -gt 0) {
            $sql += " WHERE [PercentUsed] >= " + $Threshold + " ORDER BY [PercentUsed] DESC"
        } else {
            $sql += " ORDER BY [PercentUsed] DESC"
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaIdentityUsage
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($ExcludeSystem) {
                $dbs = $dbs | Where-Object IsSystemObject -EQ $false
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance" -FunctionName Test-DbaIdentityUsage -ModuleName "dbatools"

                if ($db.IsAccessible -eq $false) {
                    Stop-Function -Message "The database $db is not accessible. Skipping." -Continue -FunctionName Test-DbaIdentityUsage
                }

                try {
                    $results = $db.Query($sql)
                } catch {
                    Stop-Function -Message "Error capturing data on $db" -Target $instance -ErrorRecord $_ -Exception $_.Exception -Continue -FunctionName Test-DbaIdentityUsage
                }

                foreach ($row in $results) {
                    if ($row.PercentUsed -eq [System.DBNull]::Value) {
                        continue
                    }

                    if ($row.PercentUsed -ge $threshold) {
                        [PSCustomObject]@{
                            ComputerName   = $server.ComputerName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $row.DatabaseName
                            Schema         = $row.SchemaName
                            Table          = $row.TableName
                            Column         = $row.ColumnName
                            SeedValue      = $row.SeedValue
                            IncrementValue = $row.IncrementValue
                            LastValue      = $row.LastValue
                            MaxNumberRows  = $row.MaxNumberRows
                            NumberOfUses   = $row.NumberOfUses
                            PercentUsed    = $row.PercentUsed
                        } | Select-DefaultView -Exclude MaxNumberRows, NumberOfUses
                    }
                }
            }
        }

} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Threshold $ExcludeSystem $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
